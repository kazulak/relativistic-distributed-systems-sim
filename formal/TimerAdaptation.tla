--------------------------- MODULE TimerAdaptation --------------------------
\* Refinement obligations for deadline adaptation in RelativisticRaft.
\*
\* This module intentionally adds no protocol behavior.  It names the
\* projection obligations that a concrete fixed, accrual, proper-time-aware,
\* or geometry-aware detector must satisfy before sharing Raft's safety claim.

EXTENDS RelativisticRaft

TimerOnlyActions ==
    \/ \E i \in Server: TimerElapse(i)
    \/ \E i \in Server, deadline \in DeadlineClass:
           AdaptDeadline(i, deadline)

\* These are action-level definitions, not proved theorems: neither estimating
\* a deadline nor observing local expiry may change the projected Raft state.
DeadlineUpdatesAreProjectionStutters ==
    \A i \in Server:
      \A deadline \in DeadlineClass:
        AdaptDeadline(i, deadline) => UNCHANGED raftVars

TimerExpiryIsProjectionStutter ==
    \A i \in Server:
      TimerElapse(i) => UNCHANGED raftVars

TimerOnlyActionsAreProjectionStutters ==
    TimerOnlyActions => UNCHANGED raftVars

TimerProjectionStep == /\ DeadlineUpdatesAreProjectionStutters
                       /\ TimerExpiryIsProjectionStutter
                       /\ TimerOnlyActionsAreProjectionStutters

TimerProjectionProperty == [][TimerProjectionStep]_vars

\* ElectionTimeout is not a projection stutter: it maps to ordinary Raft's
\* BeginElection transition.  All other protocol actions already are core
\* transitions.  TLC checks the following obligation as the individual safety
\* invariants listed in the model configuration; it is not a machine-checked
\* inductive proof in this artifact.
SafetyPreservationObligation == Spec => []CoreSafety

=============================================================================
