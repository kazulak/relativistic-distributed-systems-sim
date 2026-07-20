-------------------------- MODULE RelativisticRaft --------------------------
\* A bounded safety model for static-membership Raft.
\*
\* Spacetime is abstracted to causality: a receive action is enabled only for a
\* message previously placed in `inFlight` by a send action.  The transport may
\* delay forever, drop, reorder, or deliver the same message repeatedly.  No
\* fairness assumption is made.  Local timer expiry is nondeterministic, which
\* over-approximates fixed and adaptive proper-time deadline policies for safety.

EXTENDS Naturals, FiniteSets, Sequences, TLC

CONSTANTS Server,
          Value,
          NoNode,
          NoValue,
          MaxTerm,
          MaxLogLength,
          MaxInFlight,
          DeadlineClass

ASSUME /\ IsFiniteSet(Server)
       /\ Cardinality(Server) >= 3
       /\ IsFiniteSet(Value)
       /\ Value # {}
       /\ NoNode \notin Server
       /\ NoValue \notin Value
       /\ MaxTerm \in Nat
       /\ MaxTerm > 0
       /\ MaxLogLength \in Nat
       /\ MaxLogLength > 0
       /\ MaxInFlight \in Nat
       /\ MaxInFlight > 0
       /\ IsFiniteSet(DeadlineClass)
       /\ DeadlineClass # {}

Role == {"Follower", "Candidate", "Leader"}
MsgKind == {"RequestVote", "RequestVoteResponse",
            "AppendEntries", "AppendEntriesResponse"}

Entry == [term : 1..MaxTerm, value : Value]
CommittedEntry == [index      : 1..MaxLogLength,
                   entryTerm  : 1..MaxTerm,
                   value      : Value,
                   commitTerm : 1..MaxTerm]

Message == [kind         : MsgKind,
            src          : Server,
            dst          : Server,
            term         : 0..MaxTerm,
            lastIndex    : 0..MaxLogLength,
            lastTerm     : 0..MaxTerm,
            voteGranted  : BOOLEAN,
            prevLogIndex : 0..MaxLogLength,
            prevLogTerm  : 0..MaxTerm,
            hasEntry     : BOOLEAN,
            entryTerm    : 0..MaxTerm,
            entryValue   : Value \cup {NoValue},
            leaderCommit : 0..MaxLogLength,
            success      : BOOLEAN,
            matchIdx     : 0..MaxLogLength]

VARIABLES role,
          currentTerm,
          votedFor,
          log,
          commitIndex,
          applied,
          votesGranted,
          nextIndex,
          matchIndex,
          alive,
          inFlight,
          timer,
          leadersByTerm,
          committed

raftVars == <<role, currentTerm, votedFor, log, commitIndex, applied,
              votesGranted, nextIndex, matchIndex, alive, inFlight,
              leadersByTerm, committed>>

vars == <<raftVars, timer>>

NatMin(a, b) == IF a <= b THEN a ELSE b
NatMax(a, b) == IF a >= b THEN a ELSE b
Prefix(s, n) == SubSeq(s, 1, n)

LastTerm(i) ==
    IF Len(log[i]) = 0 THEN 0 ELSE log[i][Len(log[i])].term

Majority(members) == 2 * Cardinality(members) > Cardinality(Server)

CandidateIsUpToDate(m, i) ==
    \/ m.lastTerm > LastTerm(i)
    \/ /\ m.lastTerm = LastTerm(i)
       /\ m.lastIndex >= Len(log[i])

RequestVoteMsg(src, dst, msgTerm, lastIdx, lastLogTerm) ==
    [kind         |-> "RequestVote",
     src          |-> src,
     dst          |-> dst,
     term         |-> msgTerm,
     lastIndex    |-> lastIdx,
     lastTerm     |-> lastLogTerm,
     voteGranted  |-> FALSE,
     prevLogIndex |-> 0,
     prevLogTerm  |-> 0,
     hasEntry     |-> FALSE,
     entryTerm    |-> 0,
     entryValue   |-> NoValue,
     leaderCommit |-> 0,
     success      |-> FALSE,
     matchIdx     |-> 0]

RequestVoteResponseMsg(src, dst, msgTerm, granted) ==
    [kind         |-> "RequestVoteResponse",
     src          |-> src,
     dst          |-> dst,
     term         |-> msgTerm,
     lastIndex    |-> 0,
     lastTerm     |-> 0,
     voteGranted  |-> granted,
     prevLogIndex |-> 0,
     prevLogTerm  |-> 0,
     hasEntry     |-> FALSE,
     entryTerm    |-> 0,
     entryValue   |-> NoValue,
     leaderCommit |-> 0,
     success      |-> FALSE,
     matchIdx     |-> 0]

AppendEntriesMsg(src, dst, msgTerm, prevIdx, prevTerm,
                 carriesEntry, newEntryTerm, newEntryValue, leaderCommitIdx) ==
    [kind         |-> "AppendEntries",
     src          |-> src,
     dst          |-> dst,
     term         |-> msgTerm,
     lastIndex    |-> 0,
     lastTerm     |-> 0,
     voteGranted  |-> FALSE,
     prevLogIndex |-> prevIdx,
     prevLogTerm  |-> prevTerm,
     hasEntry     |-> carriesEntry,
     entryTerm    |-> newEntryTerm,
     entryValue   |-> newEntryValue,
     leaderCommit |-> leaderCommitIdx,
     success      |-> FALSE,
     matchIdx     |-> 0]

AppendEntriesResponseMsg(src, dst, msgTerm, wasSuccessful, matched) ==
    [kind         |-> "AppendEntriesResponse",
     src          |-> src,
     dst          |-> dst,
     term         |-> msgTerm,
     lastIndex    |-> 0,
     lastTerm     |-> 0,
     voteGranted  |-> FALSE,
     prevLogIndex |-> 0,
     prevLogTerm  |-> 0,
     hasEntry     |-> FALSE,
     entryTerm    |-> 0,
     entryValue   |-> NoValue,
     leaderCommit |-> 0,
     success      |-> wasSuccessful,
     matchIdx     |-> matched]

Init ==
    /\ role = [i \in Server |-> "Follower"]
    /\ currentTerm = [i \in Server |-> 0]
    /\ votedFor = [i \in Server |-> NoNode]
    /\ log = [i \in Server |-> <<>>]
    /\ commitIndex = [i \in Server |-> 0]
    /\ applied = [i \in Server |-> <<>>]
    /\ votesGranted = [i \in Server |-> {}]
    /\ nextIndex = [i \in Server |-> [j \in Server |-> 1]]
    /\ matchIndex = [i \in Server |-> [j \in Server |-> 0]]
    /\ alive = [i \in Server |-> TRUE]
    /\ inFlight = {}
    /\ timer \in [Server -> [deadlineClass : DeadlineClass,
                              expired       : {FALSE}]]
    /\ leadersByTerm = [t \in 0..MaxTerm |-> {}]
    /\ committed = {}

\* Changes to a detector's deadline estimate are timer-only actions.  They do
\* not clear an already expired timer; a protocol reset is required for that.
AdaptDeadline(i, deadline) ==
    /\ alive[i]
    /\ deadline \in DeadlineClass
    /\ timer' = [timer EXCEPT ![i].deadlineClass = deadline]
    /\ UNCHANGED raftVars

\* Elapsed proper time is abstracted as a nondeterministic expiry event.  This
\* intentionally admits earlier and later expiries than any concrete policy.
TimerElapse(i) ==
    /\ alive[i]
    /\ ~timer[i].expired
    /\ timer' = [timer EXCEPT ![i].expired = TRUE]
    /\ UNCHANGED raftVars

ElectionTimeout(i) ==
    /\ alive[i]
    /\ role[i] # "Leader"
    /\ timer[i].expired
    /\ currentTerm[i] < MaxTerm
    /\ \E deadline \in DeadlineClass:
        LET newTerm == currentTerm[i] + 1
            requests ==
                {RequestVoteMsg(i, j, newTerm, Len(log[i]), LastTerm(i)) :
                    j \in Server \ {i}}
        IN  /\ role' = [role EXCEPT ![i] = "Candidate"]
            /\ currentTerm' = [currentTerm EXCEPT ![i] = newTerm]
            /\ votedFor' = [votedFor EXCEPT ![i] = i]
            /\ votesGranted' = [votesGranted EXCEPT ![i] = {i}]
            /\ nextIndex' = [nextIndex EXCEPT
                                ![i] = [j \in Server |-> 1]]
            /\ matchIndex' = [matchIndex EXCEPT
                                 ![i] = [j \in Server |-> 0]]
            /\ inFlight' = inFlight \cup requests
            /\ Cardinality(inFlight') <= MaxInFlight
            /\ timer' = [timer EXCEPT
                            ![i] = [deadlineClass |-> deadline,
                                   expired       |-> FALSE]]
            /\ UNCHANGED <<log, commitIndex, applied, alive,
                            leadersByTerm, committed>>

\* Any kind of message can reveal a higher term.  The message remains in
\* flight so that its kind-specific receive transition can subsequently run.
ObserveHigherTerm(m) ==
    /\ m \in inFlight
    /\ alive[m.dst]
    /\ m.term > currentTerm[m.dst]
    /\ role' = [role EXCEPT ![m.dst] = "Follower"]
    /\ currentTerm' = [currentTerm EXCEPT ![m.dst] = m.term]
    /\ votedFor' = [votedFor EXCEPT ![m.dst] = NoNode]
    /\ votesGranted' = [votesGranted EXCEPT ![m.dst] = {}]
    /\ nextIndex' = [nextIndex EXCEPT
                        ![m.dst] = [j \in Server |-> 1]]
    /\ matchIndex' = [matchIndex EXCEPT
                         ![m.dst] = [j \in Server |-> 0]]
    /\ timer' = [timer EXCEPT ![m.dst].expired = FALSE]
    /\ UNCHANGED <<log, commitIndex, applied, alive, inFlight,
                    leadersByTerm, committed>>

ReceiveRequestVote(m) ==
    /\ m \in inFlight
    /\ m.kind = "RequestVote"
    /\ alive[m.dst]
    /\ m.term <= currentTerm[m.dst]
    /\ LET i == m.dst
           grant ==
               /\ m.term = currentTerm[i]
               /\ votedFor[i] \in {NoNode, m.src}
               /\ CandidateIsUpToDate(m, i)
           response == RequestVoteResponseMsg(i, m.src,
                                               currentTerm[i], grant)
       IN  /\ votedFor' =
                   IF grant THEN [votedFor EXCEPT ![i] = m.src]
                            ELSE votedFor
           /\ timer' =
                   IF grant
                   THEN [timer EXCEPT ![i].expired = FALSE]
                   ELSE timer
           \* Retaining m after receipt represents another duplicate copy.
           /\ inFlight' \in {inFlight \cup {response},
                              (inFlight \ {m}) \cup {response}}
           /\ Cardinality(inFlight') <= MaxInFlight
           /\ UNCHANGED <<role, currentTerm, log, commitIndex, applied,
                           votesGranted, nextIndex, matchIndex, alive,
                           leadersByTerm, committed>>

ReceiveRequestVoteResponse(m) ==
    /\ m \in inFlight
    /\ m.kind = "RequestVoteResponse"
    /\ alive[m.dst]
    /\ m.term <= currentTerm[m.dst]
    /\ LET i == m.dst
           relevant ==
               /\ m.term = currentTerm[i]
               /\ role[i] = "Candidate"
               /\ m.voteGranted
           newVotes == IF relevant
                       THEN votesGranted[i] \cup {m.src}
                       ELSE votesGranted[i]
           won == relevant /\ Majority(newVotes)
       IN  /\ votesGranted' =
                   IF relevant
                   THEN [votesGranted EXCEPT ![i] = newVotes]
                   ELSE votesGranted
           /\ role' = IF won
                       THEN [role EXCEPT ![i] = "Leader"]
                       ELSE role
           /\ leadersByTerm' =
                   IF won
                   THEN [leadersByTerm EXCEPT
                           ![currentTerm[i]] = @ \cup {i}]
                   ELSE leadersByTerm
           /\ nextIndex' =
                   IF won
                   THEN [nextIndex EXCEPT
                           ![i] = [j \in Server |-> Len(log[i]) + 1]]
                   ELSE nextIndex
           /\ matchIndex' =
                   IF won
                   THEN [matchIndex EXCEPT
                           ![i] = [j \in Server |->
                                      IF j = i THEN Len(log[i]) ELSE 0]]
                   ELSE matchIndex
           /\ inFlight' \in {inFlight, inFlight \ {m}}
           /\ UNCHANGED <<currentTerm, votedFor, log, commitIndex,
                           applied, alive, timer, committed>>

ClientAppend(i, value) ==
    /\ alive[i]
    /\ role[i] = "Leader"
    /\ currentTerm[i] > 0
    /\ value \in Value
    /\ Len(log[i]) < MaxLogLength
    /\ LET newLog == Append(log[i],
                            [term |-> currentTerm[i], value |-> value])
       IN  /\ log' = [log EXCEPT ![i] = newLog]
           /\ matchIndex' = [matchIndex EXCEPT ![i][i] = Len(newLog)]
           /\ UNCHANGED <<role, currentTerm, votedFor, commitIndex,
                           applied, votesGranted, nextIndex, alive,
                           inFlight, timer, leadersByTerm, committed>>

SendAppendEntries(i, j) ==
    /\ i # j
    /\ alive[i]
    /\ role[i] = "Leader"
    /\ LET ni == nextIndex[i][j]
           prevIdx == ni - 1
           prevTerm == IF prevIdx = 0 THEN 0 ELSE log[i][prevIdx].term
           carries == ni <= Len(log[i])
           newTerm == IF carries THEN log[i][ni].term ELSE 0
           newValue == IF carries THEN log[i][ni].value ELSE NoValue
           msg == AppendEntriesMsg(i, j, currentTerm[i], prevIdx,
                                    prevTerm, carries, newTerm, newValue,
                                    commitIndex[i])
       IN  /\ ni \in 1..(Len(log[i]) + 1)
           /\ inFlight' = inFlight \cup {msg}
           /\ Cardinality(inFlight') <= MaxInFlight
           /\ UNCHANGED <<role, currentTerm, votedFor, log,
                           commitIndex, applied, votesGranted, nextIndex,
                           matchIndex, alive, timer, leadersByTerm,
                           committed>>

ReceiveAppendEntries(m) ==
    /\ m \in inFlight
    /\ m.kind = "AppendEntries"
    /\ alive[m.dst]
    /\ m.term <= currentTerm[m.dst]
    /\ LET i == m.dst
           termMatches == m.term = currentTerm[i]
           prefixMatches ==
               /\ termMatches
               /\ m.prevLogIndex <= Len(log[i])
               /\ IF m.prevLogIndex = 0
                  THEN TRUE
                  ELSE log[i][m.prevLogIndex].term = m.prevLogTerm
           entry == [term |-> m.entryTerm, value |-> m.entryValue]
           entryIdx == m.prevLogIndex + 1
           merged ==
               IF ~prefixMatches \/ ~m.hasEntry
               THEN log[i]
               ELSE IF entryIdx <= Len(log[i])
                    \* Raft conflicts are defined by index and term.  Equality
                    \* of commands at the same index/term follows from safety;
                    \* it is not part of the follower's conflict predicate.
                    THEN IF log[i][entryIdx].term = m.entryTerm
                         THEN log[i]
                         ELSE Prefix(log[i], m.prevLogIndex) \o <<entry>>
                    ELSE log[i] \o <<entry>>
           lastCovered == m.prevLogIndex +
                          (IF m.hasEntry THEN 1 ELSE 0)
           newCommit ==
               IF prefixMatches
               THEN NatMax(commitIndex[i],
                           NatMin(m.leaderCommit, lastCovered))
               ELSE commitIndex[i]
           matched == IF prefixMatches
                      THEN m.prevLogIndex +
                           (IF m.hasEntry THEN 1 ELSE 0)
                      ELSE 0
           response == AppendEntriesResponseMsg(i, m.src,
                                                 currentTerm[i],
                                                 prefixMatches, matched)
       IN  /\ role' = IF termMatches
                       THEN [role EXCEPT ![i] = "Follower"]
                       ELSE role
           /\ log' = IF prefixMatches
                      THEN [log EXCEPT ![i] = merged]
                      ELSE log
           /\ commitIndex' = IF prefixMatches
                              THEN [commitIndex EXCEPT ![i] = newCommit]
                              ELSE commitIndex
           /\ timer' = IF termMatches
                        THEN [timer EXCEPT ![i].expired = FALSE]
                        ELSE timer
           \* Arbitrary removal/retention models loss-free or duplicate receipt.
           /\ inFlight' \in {inFlight \cup {response},
                              (inFlight \ {m}) \cup {response}}
           /\ Cardinality(inFlight') <= MaxInFlight
           /\ UNCHANGED <<currentTerm, votedFor, applied, votesGranted,
                           nextIndex, matchIndex, alive, leadersByTerm,
                           committed>>

ReceiveAppendEntriesResponse(m) ==
    /\ m \in inFlight
    /\ m.kind = "AppendEntriesResponse"
    /\ alive[m.dst]
    /\ m.term <= currentTerm[m.dst]
    /\ LET i == m.dst
           relevant ==
               /\ m.term = currentTerm[i]
               /\ role[i] = "Leader"
       IN  /\ matchIndex' =
                   IF relevant /\ m.success
                   THEN [matchIndex EXCEPT
                           ![i][m.src] = NatMax(@, m.matchIdx)]
                   ELSE matchIndex
           /\ nextIndex' =
                   IF ~relevant
                   THEN nextIndex
                   ELSE IF m.success
                        THEN [nextIndex EXCEPT
                               ![i][m.src] = NatMax(@,
                                   NatMin(MaxLogLength + 1,
                                          m.matchIdx + 1))]
                        ELSE [nextIndex EXCEPT
                               ![i][m.src] = NatMax(1, @ - 1)]
           /\ inFlight' \in {inFlight, inFlight \ {m}}
           /\ UNCHANGED <<role, currentTerm, votedFor, log,
                           commitIndex, applied, votesGranted, alive,
                           timer, leadersByTerm, committed>>

\* Raft may advance commitIndex using a quorum only for an entry from the
\* leader's current term.  Earlier entries become committed indirectly.
AdvanceCommit(i) ==
    /\ alive[i]
    /\ role[i] = "Leader"
    /\ \E k \in (commitIndex[i] + 1)..Len(log[i]):
        /\ log[i][k].term = currentTerm[i]
        /\ Majority({j \in Server : matchIndex[i][j] >= k})
        /\ LET newlyCommitted ==
                   {[index      |-> p,
                     entryTerm  |-> log[i][p].term,
                     value      |-> log[i][p].value,
                     commitTerm |-> currentTerm[i]] :
                       p \in (commitIndex[i] + 1)..k}
           IN  /\ commitIndex' = [commitIndex EXCEPT ![i] = k]
               /\ committed' = committed \cup newlyCommitted
               /\ UNCHANGED <<role, currentTerm, votedFor, log,
                               applied, votesGranted, nextIndex,
                               matchIndex, alive, inFlight, timer,
                               leadersByTerm>>

ApplyOne(i) ==
    /\ alive[i]
    /\ Len(applied[i]) < commitIndex[i]
    /\ LET next == Len(applied[i]) + 1
       IN  /\ applied' = [applied EXCEPT ![i] = Append(@, log[i][next])]
           /\ UNCHANGED <<role, currentTerm, votedFor, log,
                           commitIndex, votesGranted, nextIndex,
                           matchIndex, alive, inFlight, timer,
                           leadersByTerm, committed>>

Crash(i) ==
    /\ alive[i]
    /\ alive' = [alive EXCEPT ![i] = FALSE]
    /\ role' = [role EXCEPT ![i] = "Follower"]
    /\ votesGranted' = [votesGranted EXCEPT ![i] = {}]
    /\ nextIndex' = [nextIndex EXCEPT
                        ![i] = [j \in Server |-> 1]]
    /\ matchIndex' = [matchIndex EXCEPT
                         ![i] = [j \in Server |-> 0]]
    /\ timer' = [timer EXCEPT ![i].expired = FALSE]
    \* currentTerm, votedFor, log, committed/applied prefixes are durable.
    /\ UNCHANGED <<currentTerm, votedFor, log, commitIndex, applied,
                    inFlight, leadersByTerm, committed>>

Restart(i) ==
    /\ ~alive[i]
    /\ \E deadline \in DeadlineClass:
        /\ alive' = [alive EXCEPT ![i] = TRUE]
        /\ role' = [role EXCEPT ![i] = "Follower"]
        /\ votesGranted' = [votesGranted EXCEPT ![i] = {}]
        /\ nextIndex' = [nextIndex EXCEPT
                            ![i] = [j \in Server |-> 1]]
        /\ matchIndex' = [matchIndex EXCEPT
                             ![i] = [j \in Server |-> 0]]
        /\ timer' = [timer EXCEPT
                        ![i] = [deadlineClass |-> deadline,
                               expired       |-> FALSE]]
        /\ UNCHANGED <<currentTerm, votedFor, log, commitIndex,
                        applied, inFlight, leadersByTerm, committed>>

Drop(m) ==
    /\ m \in inFlight
    /\ inFlight' = inFlight \ {m}
    /\ UNCHANGED <<role, currentTerm, votedFor, log, commitIndex,
                    applied, votesGranted, nextIndex, matchIndex,
                    alive, timer, leadersByTerm, committed>>

Next ==
    \/ \E i \in Server, deadline \in DeadlineClass:
           AdaptDeadline(i, deadline)
    \/ \E i \in Server: TimerElapse(i)
    \/ \E i \in Server: ElectionTimeout(i)
    \/ \E m \in inFlight: ObserveHigherTerm(m)
    \/ \E m \in inFlight: ReceiveRequestVote(m)
    \/ \E m \in inFlight: ReceiveRequestVoteResponse(m)
    \/ \E i \in Server, value \in Value: ClientAppend(i, value)
    \/ \E i, j \in Server: SendAppendEntries(i, j)
    \/ \E m \in inFlight: ReceiveAppendEntries(m)
    \/ \E m \in inFlight: ReceiveAppendEntriesResponse(m)
    \/ \E i \in Server: AdvanceCommit(i)
    \/ \E i \in Server: ApplyOne(i)
    \/ \E i \in Server: Crash(i)
    \/ \E i \in Server: Restart(i)
    \/ \E m \in inFlight: Drop(m)

Spec == Init /\ [][Next]_vars

\* The executable bounded model caps concurrent distinct logical records.
\* Message-adding actions wait until loss/receipt frees capacity.  This is a
\* state invariant rather than a TLC state constraint, so temporal action
\* properties are checked over exactly the same bounded transition relation.
\* A retained record may still be delivered arbitrarily many times.
InFlightBound == Cardinality(inFlight) <= MaxInFlight

TypeOK ==
    /\ role \in [Server -> Role]
    /\ currentTerm \in [Server -> 0..MaxTerm]
    /\ votedFor \in [Server -> Server \cup {NoNode}]
    /\ log \in [Server -> Seq(Entry)]
    /\ \A i \in Server: Len(log[i]) <= MaxLogLength
    /\ commitIndex \in [Server -> 0..MaxLogLength]
    /\ \A i \in Server: commitIndex[i] <= Len(log[i])
    /\ applied \in [Server -> Seq(Entry)]
    /\ \A i \in Server: Len(applied[i]) <= commitIndex[i]
    /\ votesGranted \in [Server -> SUBSET Server]
    /\ nextIndex \in
           [Server -> [Server -> 1..(MaxLogLength + 1)]]
    /\ matchIndex \in
           [Server -> [Server -> 0..MaxLogLength]]
    /\ alive \in [Server -> BOOLEAN]
    /\ \A m \in inFlight: m \in Message
    /\ InFlightBound
    /\ timer \in [Server -> [deadlineClass : DeadlineClass,
                              expired       : BOOLEAN]]
    /\ leadersByTerm \in [0..MaxTerm -> SUBSET Server]
    /\ committed \in SUBSET CommittedEntry

\* At most one server is elected leader in a term.
ElectionSafety ==
    \A t \in 1..MaxTerm: Cardinality(leadersByTerm[t]) <= 1

\* If two logs contain an entry with the same index and term, their prefixes
\* through that entry are identical.
LogMatching ==
    \A i, j \in Server:
      \A k \in 1..NatMin(Len(log[i]), Len(log[j])):
        log[i][k].term = log[j][k].term
          => Prefix(log[i], k) = Prefix(log[j], k)

\* Every entry committed in term t is present in every leader elected in a
\* later term.  `committed` and `leadersByTerm` are history variables.
LeaderCompleteness ==
    \A ce \in committed:
      \A t \in (ce.commitTerm + 1)..MaxTerm:
        \A i \in leadersByTerm[t]:
          /\ ce.index <= Len(log[i])
          /\ log[i][ce.index] =
                 [term |-> ce.entryTerm, value |-> ce.value]

\* Servers never apply different entries at the same state-machine index.
StateMachineSafety ==
    \A i, j \in Server:
      \A k \in 1..NatMin(Len(applied[i]), Len(applied[j])):
        applied[i][k] = applied[j][k]

\* Applied state is not merely pairwise consistent: it is exactly a prefix of
\* the process's current log.  This also detects rollback/rewrite defects that
\* could otherwise be hidden when only one process has applied an index.
AppliedPrefixConsistency ==
    \A i \in Server:
      applied[i] = Prefix(log[i], Len(applied[i]))

\* This stronger history check catches conflicting commit witnesses even before
\* both entries have been applied by different servers.
CommittedEntryAgreement ==
    \A a, b \in committed:
      a.index = b.index
        => /\ a.entryTerm = b.entryTerm
           /\ a.value = b.value

CommittedPrefixPresent ==
    \A ce \in committed:
      \A i \in Server:
        commitIndex[i] >= ce.index
          => /\ ce.index <= Len(log[i])
             /\ log[i][ce.index] =
                    [term |-> ce.entryTerm, value |-> ce.value]

IsPrefix(shorter, longer) ==
    /\ Len(shorter) <= Len(longer)
    /\ shorter = Prefix(longer, Len(shorter))

\* These are transition properties, not state invariants.  The checked
\* temporal property below observes both the pre-state and post-state of every
\* transition.  It must be listed under PROPERTY in a TLC configuration.
LeaderAppendOnlyStep ==
    \A i \in Server:
      ( /\ role[i] = "Leader"
        /\ role'[i] = "Leader"
        /\ currentTerm'[i] = currentTerm[i])
        => IsPrefix(log[i], log'[i])

TermMonotonicStep ==
    \A i \in Server: currentTerm'[i] >= currentTerm[i]

CommitMonotonicStep ==
    \A i \in Server: commitIndex'[i] >= commitIndex[i]

AppliedMonotonicStep ==
    \A i \in Server: IsPrefix(applied[i], applied'[i])

\* In this scoped model, term/vote/log/commit/applied state is retained across
\* a crash.  The implication covers the crash step, time spent down, and the
\* restart step.  Concrete implementations may reconstruct commit knowledge,
\* but need a separate refinement mapping if they do not match this abstraction.
CrashDurabilityStep ==
    \A i \in Server:
      (~alive[i] \/ ~alive'[i])
        => /\ currentTerm'[i] = currentTerm[i]
           /\ votedFor'[i] = votedFor[i]
           /\ log'[i] = log[i]
           /\ commitIndex'[i] = commitIndex[i]
           /\ applied'[i] = applied[i]

TransitionDisciplineStep ==
    /\ LeaderAppendOnlyStep
    /\ TermMonotonicStep
    /\ CommitMonotonicStep
    /\ AppliedMonotonicStep
    /\ CrashDurabilityStep

TransitionDisciplineProperty == [][TransitionDisciplineStep]_vars

CoreSafety == /\ ElectionSafety
              /\ LogMatching
              /\ LeaderCompleteness
              /\ StateMachineSafety
              /\ AppliedPrefixConsistency
              /\ CommittedEntryAgreement
              /\ CommittedPrefixPresent

ServerSymmetry == Permutations(Server)

=============================================================================
