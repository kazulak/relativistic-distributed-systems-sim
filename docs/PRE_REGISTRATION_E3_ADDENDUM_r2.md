# Pre-registration addendum r2 — Experiment E3

Status addendum to `PRE_REGISTRATION_E3.md`, tagged `v0.3-e3-prereg-r2`
(2026-08-26). The frozen hypotheses, estimands, grid, seeds split, and
decision rules of the base document are unchanged.

## Implementation status (now complete)

- Engine timing boundary: `ResetTimer(ElectionTimer)` effects are rescaled at
  the scheduler boundary via a multiplicative factor toward the policy band
  midpoint (`src/Research/Engine.jl`); node-side re-arming uses the new
  `Raft.rearm_election_deadline!`, which touches only deadline bookkeeping —
  no transition, RNG consumption, or voting/log/quorum state changes, keeping
  the C1 refinement argument intact.
- Metadata side-channel I1–I3: `RunTimingState.heartbeat_meta` keyed by
  message id; byte surcharges 8/16/24 B flow into cost accounting.
- Arms B0–B5, P1–P3 implemented in `src/Research/Detectors.jl` +
  `src/Research/TimingBands.jl`; leaderless-restart uncertainty widening is a
  preregistered-guardrail implementation detail (randomization retained).
- New regimes: signed β (approaching/flyby) and audited rapidity-closed-form
  trajectory-change worldlines (`trajectory_change_scenario`).
- Runner/analyzer: `experiments/run_e3.jl`, `experiments/analyze_e3.jl`.

## Defects found and fixed during bring-up (evidence the design matters)

1. Cold-start band initially degenerate (zero randomization) → permanent
   three-way split-vote deadlock; fixed by retaining randomized cold-start.
2. Deadline override without node-side bookkeeping made every adapted timer
   silently ignored; fixed via `rearm_election_deadline!`.

## Pilot execution status

A pipeline-validation pilot slice (55 cells × replicas × 4 arms; ~7.2 k runs)
was executed. Deviation: an initial runner mapped pilot replicas into the
report-range seed space (201+). **All rows from affected smoke directories
(`pilot-20260826_15*`) are voided for confirmatory use**; the runner now
defaults to tuning-range seeding (`--seed-base 0`). No confirmatory report-
seed run has been executed. Per-cell N remains unfrozen pending the full
24-replica pilot; until the r3 freeze, C4/C7 remain untouched.

## Next gates

1. Full tuning-seed pilot → power computation → N freeze → tag r3.
2. Report-seed confirmatory sweep, executed once, then analysis per §8.
