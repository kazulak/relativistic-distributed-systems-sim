# Protocol specification and safety boundary

Status: implementation contract for the redesigned simulator and scoped formal
model. This document is not a claim that the implementation or experiments
already satisfy the contract.

## 1. Scope and terminology

The primary protocol is condensed Raft with static membership and majority
quorums. It supports elections, replicated writes, ordered state-machine
application, clean crash/recovery, and causal asynchronous transport. Timing
may change whether and when an election begins; timing must not change who may
vote, which log is up to date, or what constitutes a commit.

“Relativistic” refers to the concrete simulator layer: processes follow
future-directed timelike worldlines, local timers use proper-time clocks, and a
message delivery must be in the causal future of its send. The protocol layer
does not inspect scheduler coordinate time. The TLA+ safety layer erases
coordinates and durations, retaining only process order and send-before-receive
causal edges.

The terms below are intentionally separate:

- a **Raft safety failure** violates a replicated-log invariant or the specified
  client-history property;
- a **timed-progress failure** means an operation misses a client proper-time
  deadline or no stable writable leader exists for a stated interval;
- an **eventual-liveness failure** means the modeled schedule never again makes
  a majority reachable;
- a **physics-engine failure** is a non-causal delivery or numerical error.

Only the first is a violation of Raft safety. A timeout, leader change, blocked
write, or spacelike pair of independent client events is not by itself a safety
failure.

## 2. System assumptions

- Membership is a fixed finite set of three, five, or seven process identities.
- A quorum is any set `Q` for which `2 * |Q| > |Server|`. No policy may lower
  this threshold while retaining the Raft name.
- Processes are non-Byzantine. A live process follows the transition rules.
- `currentTerm`, `votedFor`, and the log are made durable before any dependent
  response is emitted.
- Messages may be delayed, lost, duplicated, or reordered. FIFO is an explicit
  scenario option, not a protocol assumption.
- A recovered process keeps its durable identity and persistent state. Volatile
  leader/election/replication state is reinitialized.
- The primary study has no lease reads, pre-vote, snapshots, dynamic membership,
  leadership transfer, or speculative/local fallback writes. Each extension
  requires a separate specification and claim boundary.

## 3. Protocol state

### 3.1 Per-process persistent state

| Field | Domain | Rule |
|---|---|---|
| `currentTerm` | non-negative integer | Monotonic; updated durably before processing a higher-term message or beginning an election. |
| `votedFor` | process ID or none | At most one candidate per term; reset only when entering a higher term. |
| `log` | sequence of `(term, command)` | Entries are indexed from one. A leader appends only to its own tail. Conflicting uncommitted suffixes may be replaced by `AppendEntries`. |

If request-ID deduplication is enabled in later client experiments, the
deduplication table and last response become state-machine data and inherit the
log's durability. They are not part of the current formal model.

### 3.2 Per-process volatile state

| Field | Applies to | Meaning |
|---|---|---|
| `role` | all | Follower, candidate, or leader. |
| `knownLeader` | followers/candidates | Best current-term leader hint; never a proof of leadership. |
| `commitIndex` | all | Highest log index known committed. Never exceeds the local log length. |
| `lastApplied` | all | Highest entry applied to the state machine; never exceeds `commitIndex`. |
| `votesGranted` | candidates | Distinct current-term voter identities observed by this candidacy. |
| `nextIndex[peer]` | leaders | Next entry index to send to a peer. |
| `matchIndex[peer]` | leaders | Highest index known replicated on a peer. |
| election timer | followers/candidates | Local monotonic-clock deadline and generation token. |
| heartbeat timer | leaders | Local monotonic-clock schedule for replication/heartbeat attempts. |

The executable formal model retains committed/applied prefixes across restart
as a stable-state abstraction. A concrete implementation may reconstruct
volatile `commitIndex` after recovery, but it must never roll the externally
visible state machine back or apply a conflicting command at an applied index.

### 3.3 Detector-only state

A failure detector may keep arrival samples, sequence gaps, source proper-time
samples, quantiles, accrual scores, uncertainty, and contact predictions. This
state may select a new randomized local deadline. It is not an input to vote
eligibility, log comparison, append conflict resolution, or quorum counting.

The information levels used in experiments are:

| Level | Incremental logical heartbeat information |
|---|---|
| I0 | none beyond ordinary Raft fields |
| I1 | monotonic heartbeat sequence (`UInt64`, nominally 8 B) |
| I2 | I1 plus source proper emission timestamp (nominally 16 B total) |
| I3 | I2 plus nominal next source-proper interval (nominally 24 B total) |
| I4 | I3 plus an explicitly encoded contact/ephemeris summary |

Actual serialization, framing, retransmission, and relay-copy bytes must be
measured. If an implementation already transmits equivalent information, its
incremental cost is zero and the variant is an analysis method, not new wire
metadata.

## 4. Messages

Every message has source, destination, sender term, message kind, and a unique
trace identity in the simulator. Delivery of an identity may occur zero, one,
or multiple times according to the transport trace.

| Message | Required fields | Purpose |
|---|---|---|
| `RequestVote` | term, candidate ID, last-log index, last-log term | Requests one vote for the candidate's current term. |
| `RequestVoteResponse` | responder term, granted flag | Reports the durable voting decision. |
| `AppendEntries` | leader term/ID, previous index/term, zero or more entries, leader commit index | Heartbeat, prefix consistency check, log repair, replication, and commit notification. |
| `AppendEntriesResponse` | responder term, success flag, matched/conflict information | Advances or backs off a leader's replication cursor. |

The TLA+ model sends at most one entry per `AppendEntries`. This is a valid
batch-size choice for safety exploration. The simulator may batch entries, but
the batch transition must be equivalent to applying the same conflict rule and
ordered appends.

PT-FD metadata, when enabled, is authenticated/validated transport payload but
does not change the semantics of the four Raft messages above. Stale or
reordered detector metadata may not move an already armed deadline backward or
alter persistent Raft state.

## 5. Transitions

### 5.1 Local timer and election

1. A detector estimates a deadline from information available in the process's
   causal past and arms it against the process's local monotonic proper-time
   clock. Randomization is retained.
2. Deadline estimation and local-clock advance are protocol-state stutters.
3. When a non-leader's current timer generation expires, it increments and
   durably stores `currentTerm`, becomes candidate, durably votes for itself,
   clears the current vote set, adds itself, chooses a new timer, and sends
   `RequestVote` to the other members.
4. A repeated timeout begins a new, higher-term election. A stale timer event
   whose generation no longer matches is ignored.

The formal model permits expiry at any transition. This is a safety
over-approximation of all concrete deadline algorithms; it makes no prediction
about their timeout frequency.

### 5.2 Higher-term observation

Before kind-specific handling, a live receiver that observes a message term
greater than its `currentTerm` durably adopts that term, clears `votedFor`, and
becomes a follower. A candidate or leader also discards volatile candidacy or
leader replication state. A lower-term message cannot reduce local term or
cause a role promotion.

### 5.3 Voting

A receiver grants `RequestVote(term=t)` exactly when all are true:

- `t == currentTerm` after higher-term handling;
- it has not voted in `t`, or it already voted for the same candidate; and
- the candidate log is at least as up to date, comparing last-entry term first
  and last index second.

The vote is persisted before a positive response. A candidate becomes leader
only after responses from a majority of distinct members in its current term.
Duplicate responses do not add duplicate votes. A response from another term
cannot contribute.

### 5.4 Leader append and replication

A leader accepts an abstract client command only while live and appends
`(currentTerm, command)` to its tail. It never overwrites or removes an entry
while remaining leader.

For follower `f`, a leader sends the entry at `nextIndex[f]`, or an empty
heartbeat when that cursor is beyond its tail. The request identifies the
previous index and term. The follower accepts only if that previous position is
zero or exists locally with the same term. On success it:

- retains the existing entry when its term at that index matches the incoming
  term (Raft defines a conflict by index and term, not command equality);
- otherwise removes the term-conflicting suffix and appends the incoming
  entries;
- advances local commit knowledge to at most
  `min(leaderCommit, index of the last entry covered by this successful RPC)`;
  for the formal one-entry message this covered index is
  `prevLogIndex + (hasEntry ? 1 : 0)`; and
- returns the matched index.

The commit cap is the RPC's covered index, not the length of the follower's
merged/local log. A follower may have an unvalidated suffix beyond a heartbeat
or one-entry repair. Committing that suffix merely because it is locally
present can apply entries the leader has not established as matching.

On failure the leader backs off `nextIndex`; on success it monotonically raises
`matchIndex` and `nextIndex`. Reordered and duplicate responses may cause extra
retries but cannot fabricate a quorum or rewrite the leader log.

### 5.5 Commit and apply

A leader may advance `commitIndex` to index `N` only when:

- a majority, including the leader, is known to store index `N`; and
- the entry at `N` was created in the leader's current term.

Advancing to `N` also commits all prior entries. Followers learn commit progress
through `AppendEntries`. Each process applies committed entries exactly in
increasing index order. A client success response is permitted only after the
operation's entry is committed and applied according to the client contract.
No timeout policy or metadata level may bypass these conditions.

### 5.6 Crash and recovery

A crash disables local sends, receives, timer expiry, client handling, and
application actions for that process. Network messages to or from the identity
may remain delayed or be dropped. Recovery restores persistent state and starts
as a follower with fresh volatile election/replication state and a newly armed
timer. Old messages can arrive after recovery and are handled by their terms
and log consistency fields.

The primary simulator must make durability ordering observable in deterministic
traces. Torn writes, disk corruption, Byzantine persistence, and identity reuse
are separate fault models and out of scope.

## 6. Safety properties and check classes

The implementation checks the following after each protocol transition. The
formal artifact represents them in different ways; “encoded by a transition”
must not be described as a configured TLC invariant:

1. **Election Safety:** at most one process is elected leader in a term.
2. **Leader Append-Only:** while a process remains leader in a term, it only
   appends to its log.
3. **Log Matching:** if two logs contain an entry with the same index and term,
   their prefixes through that index are identical.
4. **Leader Completeness:** an entry committed in term `t` appears in the log of
   every leader elected in a term greater than `t`.
5. **State Machine Safety:** no two processes apply different commands at the
   same state-machine index.
6. Terms, commit indices, and applied indices obey their monotonicity and bound
   rules; persistent fields obey crash/recovery durability.

The checked-in TLC configurations list these **state invariants**:

- `ElectionSafety`, `LogMatching`, `LeaderCompleteness`, and
  `StateMachineSafety`;
- `AppliedPrefixConsistency`, which requires each applied sequence to be the
  corresponding local-log prefix; and
- `CommittedEntryAgreement` and `CommittedPrefixPresent`, using the history
  variables `leadersByTerm` and `committed`.

The configurations separately list the temporal **action property**
`TransitionDisciplineProperty`. It checks pre/post-state relations for leader
append-only, nondecreasing terms and commit indices, append-only applied state,
and retention of term/vote/log/commit/applied state over crash, downtime, and
restart. These are not state invariants. Durable-before-response ordering is
still atomic/transition-encoded in this model and requires concrete trace and
storage conformance evidence.

`TimerProjectionProperty` is a bounded action-property check in the timer
configuration. The named projection and safety-preservation formulas in
`TimerAdaptation.tla` are definitions/obligations, not proved theorems.

Simulation checks are regression oracles. Passing them is not a proof. A safety
counterexample blocks all affected experiments until it is classified as a
model error, implementation error, checker error, or genuine protocol result.

## 7. Concrete-to-formal trace mapping

Let `C` be a concrete simulator state and `pi(C)` its formal projection. The
projection keeps process identity, live/crashed status, role, term, vote, log,
commit/applied prefix, vote set, replication cursors, abstract timer status,
and logical in-flight Raft messages. It erases:

- coordinate frame and coordinate timestamps;
- worldline representation and positions;
- proper-clock numeric readings after they determine timer order;
- queue, serialization, processing, propagation, and relay delays;
- detector samples, scores, metadata bytes, CPU, and energy counters; and
- event-queue order between causally incomparable local events.

Concrete actions map as follows:

| Concrete action | Formal action/projection |
|---|---|
| detector sample or deadline recomputation | `AdaptDeadline`, a Raft-state stutter |
| local proper-clock progress before expiry | stutter |
| current timer generation becomes due | `TimerElapse` |
| valid election-timeout handler | `ElectionTimeout` |
| Raft send after durable update | adds the matching message to `inFlight` |
| causal delivery and handler | matching receive action; input may remain to model duplication |
| transport loss | `Drop` |
| arbitrary transport delay | one or more stuttering steps |
| crash/recovery | `Crash` / `Restart` |
| cost/metric bookkeeping | stutter |

A concrete message may project to the same logical record as another message;
the formal set representation then collapses identities. Because a formal
receive may retain its record indefinitely, the projection still
over-approximates arbitrary duplicate deliveries for safety.

Each executable TLC configuration additionally bounds the number of concurrent
distinct logical message records by `MaxInFlight`. When the bound is full,
message-adding actions wait until a record is delivered or dropped. Retained
records can still be delivered repeatedly, but a completed run is exhaustive
only for its declared `MaxInFlight`; it does not establish safety for executions
with larger simultaneous message sets.

## 8. Safety-preservation obligation

For a detector or transport adaptation `A`, the intended trace-refinement
argument must establish all of the following:

1. **Initial-state mapping:** every valid concrete initial state projects to
   `Init` (or to a separately documented initialized-state extension).
2. **Step simulation:** every concrete step projects either to one allowed
   formal `Next` step or to stuttering of the projected state.
3. **Causal authenticity:** a delivered protocol message has a prior matching
   send in its causal past; physics and relay actions cannot synthesize a Raft
   response.
4. **Timer confinement:** estimation, source timestamps, sequence numbers,
   ephemerides, and deadline changes modify only detector/timer state.
5. **Election mapping:** a detector decision can enable only the ordinary
   higher-term `ElectionTimeout` transition. It cannot directly elect a leader,
   add a vote, suppress higher-term handling, or reuse a term.
6. **Rule identity:** vote eligibility, log comparison, append conflict
   handling, current-term commit restriction, majority definition, persistence,
   and apply order are identical to the specified core.
7. **Crash mapping:** restart preserves every field the concrete durability
   contract calls persistent; delayed pre-crash traffic remains subject to
   ordinary term/log checks.
8. **No hidden scheduler channel:** coordinate ordering of spacelike events
   cannot mutate another process or change a later trace except through an
   explicit causal interaction.

If `pi(C0)` satisfies the core initial condition and each adapted step maps to a
core step or stutter, every stutter-invariant core safety property established
for the abstract traces is preserved by the adaptation. `TimerAdaptation.tla`
defines the timer-stutter part of this obligation, and its focused
configuration checks that action property in a bounded model. TLC explores the
bounded safety state space; it does not prove the general refinement
obligation. A proof and implementation conformance review remain separate
evidence.

This obligation supports only the conservative statement that changing timer
actions adds no new voting/log/quorum transition within this model. It does not
establish availability, detector accuracy, causal-quorum optimality,
linearizability of a concrete client API, or safety of leases and other omitted
features.

## 9. Conformance evidence required before experiments

- Deterministic traces for clean election, split vote/retry, log repair,
  indirect commit of prior-term entries, leader crash, follower crash/recovery,
  stale/higher-term messages, duplicate delivery, reordering, and partitions.
- Transition-by-transition runtime invariant checks and durable-write ordering
  checks.
- Differential traces against an independent/reference Raft state machine.
- Completed small-state TLC runs using the checked-in configurations, with tool
  version and state statistics recorded.
- Completed `CommitCapRegression` witness showing that a one-entry repair does
  not commit an unvalidated suffix, and completed `CoverageTrace` witness
  reaching election, replication, quorum commit, application on two processes,
  crash, and restart. These witnesses reduce vacuity risk but do not replace
  exhaustive safety exploration.
- A mapping test showing that detector actions do not change persistent Raft
  state, votes, logs, replication acknowledgements, or commit calculation.
- Causal-delivery validation and Lorentz-metamorphic simulator checks, kept
  separate from Raft safety metrics.

Failure of any item is a validation defect, not an adverse RQ outcome. Paper
experiments do not begin until the relevant gate is repaired and rerun.
