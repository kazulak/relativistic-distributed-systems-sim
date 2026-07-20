------------------------- MODULE CommitCapRegression ------------------------
\* Focused transition regression for follower commit capping.
\*
\* A term-3 leader has committed three entries with a witness.  A reachable
\* lagging follower has <<E1, F2>>, where F2 is an uncommitted term-1 suffix,
\* while the leader has <<E1, E2, E3>>.  An index-3 repair is rejected.  The
\* same retained failure response is then delivered twice, driving nextIndex
\* 3 -> 2 -> 1 before the target one-entry RPC is sent.
\*
\* That target RPC validates only E1.  Advancing follower commitIndex to
\* Len(follower.log) would incorrectly commit F2 and violate
\* CommittedPrefixPresent.  The Raft rule caps at the last index covered by the
\* RPC, so the fixed transition advances only to index 1.

EXTENDS RelativisticRaft

CONSTANTS LeaderNode,
          FollowerNode,
          WitnessNode,
          CommonValue,
          ConflictingValue,
          RegressionDeadline

ASSUME /\ Server = {LeaderNode, FollowerNode, WitnessNode}
       /\ LeaderNode # FollowerNode
       /\ LeaderNode # WitnessNode
       /\ FollowerNode # WitnessNode
       /\ CommonValue \in Value
       /\ ConflictingValue \in Value
       /\ CommonValue # ConflictingValue
       /\ RegressionDeadline \in DeadlineClass
       /\ MaxTerm >= 3
       /\ MaxLogLength >= 3

E1 == [term |-> 1, value |-> CommonValue]
E2 == [term |-> 2, value |-> CommonValue]
E3 == [term |-> 3, value |-> CommonValue]
F2 == [term |-> 1, value |-> ConflictingValue]

LeaderLog == <<E1, E2, E3>>
FollowerLog == <<E1, F2>>

RejectedAppend ==
    AppendEntriesMsg(LeaderNode, FollowerNode, 3,
                     2, 2, TRUE, 3, CommonValue, 3)

StaleFailureResponse ==
    AppendEntriesResponseMsg(FollowerNode, LeaderNode, 3, FALSE, 0)

TargetAppend ==
    AppendEntriesMsg(LeaderNode, FollowerNode, 3,
                     0, 0, TRUE, 1, CommonValue, 3)

VARIABLE phase

regressionVars == <<vars, phase>>

RegressionInit ==
    /\ role = [i \in Server |->
                  IF i = LeaderNode THEN "Leader" ELSE "Follower"]
    /\ currentTerm = [i \in Server |-> 3]
    /\ votedFor = [i \in Server |-> LeaderNode]
    /\ log = [i \in Server |->
                 IF i = FollowerNode THEN FollowerLog ELSE LeaderLog]
    /\ commitIndex = [i \in Server |->
                         IF i = LeaderNode THEN 3 ELSE 0]
    /\ applied = [i \in Server |->
                     IF i = LeaderNode THEN LeaderLog ELSE <<>>]
    /\ votesGranted = [i \in Server |->
                          IF i = LeaderNode THEN Server ELSE {}]
    /\ nextIndex =
           [i \in Server |->
              [j \in Server |->
                 IF i = LeaderNode
                 THEN IF j = FollowerNode THEN 3 ELSE 4
                 ELSE 1]]
    /\ matchIndex =
           [i \in Server |->
              [j \in Server |->
                 IF i = LeaderNode /\ j \in {LeaderNode, WitnessNode}
                 THEN 3
                 ELSE 0]]
    /\ alive = [i \in Server |-> TRUE]
    /\ inFlight = {}
    /\ timer = [i \in Server |->
                   [deadlineClass |-> RegressionDeadline,
                    expired       |-> FALSE]]
    /\ leadersByTerm = [t \in 0..MaxTerm |->
                           IF t = 3 THEN {LeaderNode} ELSE {}]
    /\ committed =
           {[index |-> 1, entryTerm |-> 1, value |-> CommonValue,
             commitTerm |-> 3],
            [index |-> 2, entryTerm |-> 2, value |-> CommonValue,
             commitTerm |-> 3],
            [index |-> 3, entryTerm |-> 3, value |-> CommonValue,
             commitTerm |-> 3]}
    /\ phase = 0

RegressionNext ==
    \/ /\ phase = 0
       /\ SendAppendEntries(LeaderNode, FollowerNode)
       /\ phase' = 1
    \/ /\ phase = 1
       /\ ReceiveAppendEntries(RejectedAppend)
       /\ phase' = 2
    \* Retain the failure response so the next phase delivers the same logical
    \* response again.  This is the model's duplicate-delivery abstraction.
    \/ /\ phase = 2
       /\ ReceiveAppendEntriesResponse(StaleFailureResponse)
       /\ StaleFailureResponse \in inFlight'
       /\ phase' = 3
    \/ /\ phase = 3
       /\ ReceiveAppendEntriesResponse(StaleFailureResponse)
       /\ StaleFailureResponse \in inFlight'
       /\ phase' = 4
    \/ /\ phase = 4
       /\ SendAppendEntries(LeaderNode, FollowerNode)
       /\ phase' = 5
    \/ /\ phase = 5
       /\ ReceiveAppendEntries(TargetAppend)
       /\ phase' = 6

RegressionSpec ==
    /\ RegressionInit
    /\ [][RegressionNext]_regressionVars
    /\ WF_regressionVars(RegressionNext)

RegressionTypeOK == TypeOK /\ phase \in 0..6

RegressionCommitCapped == commitIndex[FollowerNode] <= 1

RegressionMilestones ==
    /\ (phase <= 2 => nextIndex[LeaderNode][FollowerNode] = 3)
    /\ (phase = 3 => nextIndex[LeaderNode][FollowerNode] = 2)
    /\ (phase >= 4 => nextIndex[LeaderNode][FollowerNode] = 1)

RegressionOutcome ==
    phase = 6
      => /\ log[FollowerNode] = FollowerLog
         /\ commitIndex[FollowerNode] = 1
         /\ CommittedPrefixPresent

\* Non-vacuous negative-control witness.  Every fair regression behavior must
\* reach phase 6 with the fixed transition committed only through index 1.
\* At that same state, the superseded Len(merged) rule computes index 2, whose
\* retained F2 disagrees with the globally committed E2.
OldLengthRuleCounterexample ==
    <> (phase = 6
        /\ LET fixedCommit == commitIndex[FollowerNode]
               oldCommit == NatMin(TargetAppend.leaderCommit,
                                   Len(log[FollowerNode]))
           IN  /\ fixedCommit = 1
               /\ oldCommit = 2
               /\ oldCommit > fixedCommit
               /\ log[FollowerNode][oldCommit] = F2
               /\ \E ce \in committed:
                    /\ ce.index = oldCommit
                    /\ [term |-> ce.entryTerm, value |-> ce.value] = E2
                    /\ log[FollowerNode][oldCommit] #
                           [term |-> ce.entryTerm, value |-> ce.value])

RegressionEventuallyExercisesReceive ==
    <> (phase = 6)

=============================================================================
