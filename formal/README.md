# Scoped Raft safety model

This directory contains a finite-state TLA+ model for the safety boundary used
by the Relativistic Raft study. It models real elections, one-entry
`AppendEntries` replication, majority commit, ordered application,
crash/restart, and static membership. The model is deliberately stricter about
what it establishes than the simulator: it checks Raft safety under arbitrary
message timing, but it does not predict availability or latency.

## Files

- `RelativisticRaft.tla` is the executable protocol model.
- `TimerAdaptation.tla` states the projection obligations for a concrete
  failure detector. It adds no behavior to the base model.
- `models/Raft3Quick.cfg` is the smallest useful general exploration: three
  nodes, one term, one log entry/value, one deadline class, and at most two
  concurrent distinct message records.
- `models/Raft3Safety.cfg` expands the general exploration to two terms while
  retaining one entry/value, one deadline class, and a two-record network
  bound. The focused repair model separately exercises three terms/entries.
- `models/Timer3Quick.cfg` runs the quick state space through the adaptation
  wrapper.
- `CommitCapRegression.tla` and `models/CommitCapRegression.cfg` force a
  term-3, three-entry stale-suffix repair. The required witness simultaneously
  checks that the RPC-covered-index rule commits only index 1 and that the old
  `Len(merged)` rule would commit the divergent follower entry at index 2; see
  `VALIDATION.md` for its current incomplete execution status.
- `CoverageTrace.tla` and `models/CoverageTrace.cfg` force a non-vacuity witness
  through election, replication, quorum commit, application by two processes,
  crash, and restart.

## What the model means by a relativistic/asynchronous network

There is no coordinate time in this safety model. A receive action can occur
only after the corresponding send has added a message to `inFlight`. That
send-before-receive edge is the causal abstraction: the full simulator must
ensure that every concrete delivery lies in the sender's causal future before
its trace can refine this model.

The network can select any in-flight message, so messages can be reordered.
`Drop` models loss. A receive can retain its input message after processing,
which permits the same logical message to be delivered any finite number of
times and therefore models duplication. Arbitrary stuttering permits unbounded
delay. There is no FIFO or fairness assumption.

Timer expiry is also nondeterministic. `DeadlineClass` records a detector's
abstract choice, but does not constrain when `TimerElapse` occurs. This
over-approximates fixed, randomized, backoff, accrual, proper-time-aware, and
geometry-aware deadlines for a safety check. It is intentionally useless for
comparing their liveness or cost.

## Reproducible validation harness

Run the checked-in harness from the repository root. Its manifest pins the
official TLA+ tools release and SHA-256, declares every SANY module and TLC
configuration, assigns explicit wall-clock/heap/worker caps, and runs each TLC
check in an isolated metadir.

```sh
python3 scripts/formal_validation.py fetch-tool
python3 scripts/formal_validation.py verify-tool
bash scripts/run_formal_validation.sh
```

To use an existing JAR instead of downloading it, pass `--jar /absolute/path`
or set `TLA2TOOLS`. The hash must match the manifest. A quick parser-only smoke
run is deliberately partial:

```sh
python3 scripts/formal_validation.py run \
  --jar /absolute/path/to/tla2tools.jar \
  --sany-only
```

Evidence is written under ignored `formal/results/<run-id>/` directories. Each
step archives its exact command, stdout, stderr, exit status, duration, cap,
input/config hashes, and parsed state statistics. `result.json` is the
machine-readable record and `SUMMARY.md` is its human-readable projection.
TLC state metadirs are removed after classification unless `--keep-state` is
explicitly requested; both locations remain gitignored.

The classifier is fail-closed. `PASS` requires the explicit TLC completion
sentence, final state statistics with zero states queued, exit status zero, and
no error/counterexample/blocker marker. A timeout is `INCOMPLETE`; a localhost
RMI/resource failure is `BLOCKED`; an exit status of zero alone never passes.
Only a full run in which every declared SANY and TLC step passes can label V5
`PASS`. Selected or SANY-only runs always leave V5 `OPEN`.

Run the dependency-free harness checks with:

```sh
python3 -m unittest discover -s test/formal_validation -v
python3 scripts/formal_validation.py validate-manifest
```

The manifest and result schema are documented in `validation/README.md`.

The configurations disable deadlock checking because this is a bounded safety
model: reaching `MaxTerm`/`MaxLogLength`, dropping all messages, and declining
to restart crashed nodes are permitted terminal explorations. No liveness
property should be inferred from the absence or presence of such states.

The required successful result is that TLC completes without violating the
configured checks. The main configurations contain state invariants:

- `ElectionSafety`;
- `LogMatching`;
- `LeaderCompleteness`;
- `StateMachineSafety`;
- `AppliedPrefixConsistency`;
- the type and strengthened commit-history checks.

They also contain the temporal action property
`TransitionDisciplineProperty`, covering leader append-only, term/commit/apply
monotonicity, and the formal crash-durability abstraction. The timer model adds
`TimerProjectionProperty`. Definitions named “projection” or “obligation” in
`TimerAdaptation.tla` are not theorems; a completed bounded TLC property check
does not prove the general refinement implication.

The two focused traces are mandatory non-vacuity/regression gates:

- `CommitCapRegression` must reach follower `commitIndex = 1` while
  `CommittedPrefixPresent` continues to hold. Its non-vacuous negative-control
  property must reach the same final state and show that the superseded
  `Len(merged)` rule would instead commit divergent index 2. Its constants
  deliberately use `MaxTerm = 3` and `MaxLogLength = 3`.
- `CoverageTrace` must satisfy its liveness property and reach phase 16, after
  a leader was elected, an entry was committed/applied on two processes, and a
  follower crashed and restarted.

These witnesses establish that important predicates were exercised. They do
not enlarge the exhaustive state space of the main configurations or prove the
general algorithm.

The manifest orders publication validation as SANY on every module, both
focused traces, the quick core and timer configurations, and finally the
expanded safety configuration. Never relabel an incomplete search,
environment-blocked run, partial selection, or witness-only run as V5 passing.

## Abstraction limits

- Model checking finite constants is exhaustive only for those constants; it
  is not a proof for every cluster, term, log, or command count.
- Each executable configuration also caps concurrent distinct logical message
  records with `MaxInFlight`. Message-adding actions wait for delivery/loss when
  the bound is full. A retained record can still be delivered repeatedly, but
  configurations do not explore larger simultaneous message sets.
- Messages carry at most one log entry. This is a valid Raft batching choice,
  but snapshots and bulk transfer are absent.
- Membership is static. Pre-vote, joint consensus, leases, read-index,
  snapshots, client deduplication, and Byzantine behavior are absent.
- `currentTerm`, `votedFor`, logs, commit knowledge, and applied prefixes remain
  durable across restart. Real implementations must separately validate their
  stable-storage and replay behavior.
- The state machine is an append-only sequence of abstract command values. The
  model checks agreement, not application-specific semantics or client-history
  linearizability.
- Crashes are clean fail/restart actions. Torn writes, storage corruption,
  partial persistence, and process identity changes are out of scope.
- Spacetime coordinates, clock readings, queue lengths, link capacity,
  propagation residuals, and costs are erased. Those belong in the simulator
  and cannot be claimed from TLC.
- TLC exploration supports a scoped safety-preservation argument. It neither
  proves deployed Raft safe nor establishes timed progress in any environment.

The protocol-to-simulator mapping and the precise refinement obligation are in
`../docs/PROTOCOL.md`. The current, deliberately incomplete execution record is
in `VALIDATION.md`; do not infer V5 completion from the existence of the model.
