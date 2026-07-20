----------------------------- MODULE CoverageTrace --------------------------
\* Non-vacuity witness for the principal safety predicates and transition
\* checks.  This is a deliberately forced protocol trace, not a replacement for
\* exhaustive exploration under RelativisticRaft!Spec.

EXTENDS RelativisticRaft

CONSTANTS CandidateNode,
          VoterNode,
          OtherNode,
          ScenarioValue

ASSUME /\ Server = {CandidateNode, VoterNode, OtherNode}
       /\ CandidateNode # VoterNode
       /\ CandidateNode # OtherNode
       /\ VoterNode # OtherNode
       /\ ScenarioValue \in Value
       /\ MaxTerm >= 1
       /\ MaxLogLength >= 1

VARIABLE phase

coverageVars == <<vars, phase>>

VoteRequest ==
    RequestVoteMsg(CandidateNode, VoterNode, 1, 0, 0)

VoteResponse ==
    RequestVoteResponseMsg(VoterNode, CandidateNode, 1, TRUE)

DataAppend ==
    AppendEntriesMsg(CandidateNode, VoterNode, 1,
                     0, 0, TRUE, 1, ScenarioValue, 0)

DataResponse ==
    AppendEntriesResponseMsg(VoterNode, CandidateNode, 1, TRUE, 1)

CommitHeartbeat ==
    AppendEntriesMsg(CandidateNode, VoterNode, 1,
                     1, 1, FALSE, 0, NoValue, 1)

CoverageInit == Init /\ phase = 0

CoverageNext ==
    \/ /\ phase = 0
       /\ TimerElapse(CandidateNode)
       /\ phase' = 1
    \/ /\ phase = 1
       /\ ElectionTimeout(CandidateNode)
       /\ phase' = 2
    \/ /\ phase = 2
       /\ ObserveHigherTerm(VoteRequest)
       /\ phase' = 3
    \/ /\ phase = 3
       /\ ReceiveRequestVote(VoteRequest)
       /\ phase' = 4
    \/ /\ phase = 4
       /\ ReceiveRequestVoteResponse(VoteResponse)
       /\ phase' = 5
    \/ /\ phase = 5
       /\ ClientAppend(CandidateNode, ScenarioValue)
       /\ phase' = 6
    \/ /\ phase = 6
       /\ SendAppendEntries(CandidateNode, VoterNode)
       /\ phase' = 7
    \/ /\ phase = 7
       /\ ReceiveAppendEntries(DataAppend)
       /\ phase' = 8
    \/ /\ phase = 8
       /\ ReceiveAppendEntriesResponse(DataResponse)
       /\ phase' = 9
    \/ /\ phase = 9
       /\ AdvanceCommit(CandidateNode)
       /\ phase' = 10
    \/ /\ phase = 10
       /\ ApplyOne(CandidateNode)
       /\ phase' = 11
    \/ /\ phase = 11
       /\ SendAppendEntries(CandidateNode, VoterNode)
       /\ phase' = 12
    \/ /\ phase = 12
       /\ ReceiveAppendEntries(CommitHeartbeat)
       /\ phase' = 13
    \/ /\ phase = 13
       /\ ApplyOne(VoterNode)
       /\ phase' = 14
    \/ /\ phase = 14
       /\ Crash(VoterNode)
       /\ phase' = 15
    \/ /\ phase = 15
       /\ Restart(VoterNode)
       /\ phase' = 16

CoverageSpec ==
    /\ CoverageInit
    /\ [][CoverageNext]_coverageVars
    /\ WF_coverageVars(CoverageNext)

CoverageTypeOK == TypeOK /\ phase \in 0..16

CoverageMilestones ==
    /\ (phase >= 5 => leadersByTerm[1] = {CandidateNode})
    /\ (phase >= 10 => committed # {})
    /\ (phase >= 11 => Len(applied[CandidateNode]) = 1)
    /\ (phase >= 13 => commitIndex[VoterNode] = 1)
    /\ (phase >= 14 => Len(applied[VoterNode]) = 1)
    /\ (phase = 15 => ~alive[VoterNode])
    /\ (phase = 16 => alive[VoterNode])

CoverageReached ==
    phase = 16
      => /\ leadersByTerm[1] = {CandidateNode}
         /\ committed # {}
         /\ Len(applied[CandidateNode]) = 1
         /\ Len(applied[VoterNode]) = 1
         /\ applied[CandidateNode] = applied[VoterNode]
         /\ alive[VoterNode]

CoverageEventuallyCompletes == <> (phase = 16)

=============================================================================
