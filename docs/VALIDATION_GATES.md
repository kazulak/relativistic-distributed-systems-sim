# Validation gate ledger

Status of the predeclared validation gates from
[PUBLISHABLE_RESEARCH_PLAN.md](PUBLISHABLE_RESEARCH_PLAN.md), Section 8
(Stage V). Each row names its evidence so a reviewer can re-derive the
status. A gate is reopened by any change to the code or models its evidence
covers.

| Gate | Definition | Status | Evidence |
|---|---|---|---|
| V0 | Analytic radial/transverse/coincident/stationary light-time cases within predeclared tolerances | **PASS** | `test/physics/light_cone.jl`, `test/physics/numerical_regressions.jl` |
| V1 | Independent high-precision oracle, fuzz/property tests, accelerated worldlines, invalid/superluminal input rejection | **PASS** | `test/physics/quadrature_regressions.jl` (DoubleFloats oracle), `test/physics/spacetime_worldlines.jl`, property fuzz in `light_cone.jl` |
| V2 | Lorentz-transform metamorphic equivalence | **PASS** (2026-08-25) | Scenario level: `test/research/metamorphic.jl` — rotation preserves the full causal trace on every RQ1 family including faults; boosts preserve elections/terms/commits/censored sets, client-visible results, and safety flags, with the expected gamma dilation of coordinate-parameterized transport delay verified exactly on the co-located control. Transform level: `test/physics/lorentz.jl`. Gate work surfaced and fixed a real defect: `lorentz_transform_velocity` normalized its round-trip residual only by the source speed, so boosting slow/static worldlines always raised `NumericalConditioningError` (`src/Physics/Lorentz.jl`). |
| V3 | Classical limit at `beta = 0`: elections, commits, partitions, crashes, recovery with all runtime oracles clean | **PASS** | `test/research/runtests.jl` — co-located control, separated static baseline, partition/drop/crash stress family, cluster sizes 3/5/7, deterministic regression signatures, linearizability checker active on all traces |
| V4 | Trace/differential comparison against an independent Raft implementation | **PASS, scoped** (2026-08-25) | `test/differential/` — a second, spec-derived implementation (`reference_raft.jl`) driven by identically distributed deterministic schedules (delivery/drop/duplicate/heartbeat/election sweeps/crash/recover/client retries) across fourteen traces (ten 3-node at 380 actions, four 5-node at 220). Asserted contract: no safety-monitor violation in either implementation, package-cluster internal consistency (identical applied state machines on every member), and package-cluster client progress. Gate work surfaced and fixed a genuine defect: the runtime audit oracle rejected lawful re-commits of an already-committed index by a later leader (`src/Protocols/Raft/Invariants.jl`), which would have poisoned later experiments with false safety violations. Known open limitation: the two sides share one fault stream but not one logical clock; under heavy churn the reference halts client progress earlier, so full bidirectional commit-set equality is not asserted yet. Independence is structural (spec-derived), not authorship-based; recorded in `CLAIMS_AND_LIMITATIONS.md`. Production-reference replay remains Stage E6 work. |
| V5 | Bounded TLA+ exploration completes without violation for all declared configurations | **PASS** (2026-08-25) | Authoritative run `formal-v5-full-r2`: SANY x4 PASS; both focused traces PASS; `Raft3Quick` exhaustive (769,727 distinct states); `Timer3Quick` exhaustive (6,156,762 distinct states); `Raft3Safety` exhaustive (11,560,890 distinct states, depth 47); all zero queued. One pre-declared cap revision (`tlc_timer3_quick` 300 s -> 1800 s) is documented in [../formal/VALIDATION.md](../formal/VALIDATION.md). Evidence under gitignored `formal/results/`; narrative record in the same file. |

## Cap revision record

The original manifest gave `tlc_timer3_quick` a 300 s wall-clock cap. On
2026-08-25 the first full local run classified that step INCOMPLETE at
89,614,282 generated states; every other step passed. Under the pre-declared
one-revision policy, the cap was raised once to 1800 s (matching
`tlc_raft3_safety`), after which the same configuration completed explicitly
with zero queued states. No other cap was changed. The revised manifest is
checked in; superseded evidence remains under its original run id.

## What V2/V4/V5 do not establish

- Metamorphic equivalence excludes the scheduler-frame-relative model inputs:
  the network transport profile (processing/jitter/reorder delays,
  bandwidth) and the experiment-window censoring hyperplanes are defined in
  the scheduler coordinate frame and are not transformed. Boost-equivalence
  claims are scoped to decisions, proper-time metrics, causal validity, and
  the documented dilation relation.
- Differential agreement is simulation-level evidence about these two
  implementations on the tested corpus; it is not a proof of Raft safety.
- TLC checks are exhaustive only for their configured finite constants and
  `MaxInFlight` bounds; see `formal/README.md` abstraction limits.
