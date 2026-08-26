# Pre-registration — Experiment E3

Status: **FROZEN** at tag `v0.3-e3-prereg` (2026-08-26), before any adaptation
code exists in the package. The `Research` engine contains no timeout
adaptation as of this tag (`src/Research/Research.jl`, docstring). Any change
to this document after confirmatory runs begin requires a new superseding tag
(`v0.3-e3-prereg-r2`, …); edits are never made in place. This file maps to
claim-register rows C4 and C7 in `CLAIMS_AND_LIMITATIONS.md`.

## 1. Research question

Does heartbeat metadata carrying source proper-time information improve the
false-suspicion versus crash-detection-delay trade-off of Raft failure
detection over equally tuned arrival-only detectors, across relativistic
regimes (D_sr ≠ 1) and non-stationary trajectories, at equal information
budgets and identical exogenous fault exposure?

## 2. Hypotheses and decision rules

- **H-primary (C4):** PT-FD at information level **I2** (heartbeat sequence +
  source proper-time emission stamp) reduces the false-suspicion rate by at
  least **δ = 15 % relative** against **best-arrival** (the best of B3/B4/B5
  per tuning traces) on report traces, with a two-sided 95 % paired bootstrap
  CI excluding zero, **and** is non-inferior on p95 crash-detection delay
  (worse by ≤ 5 % relative, one-sided 95 % CI). If both hold → C4 eligible.
- **H-null (C7):** if H-primary fails → C7 becomes the actionable result:
  recommend the simpler arrival-only detector for the tested regimes. This is
  a publishable outcome and must be reported at equal visibility.
- Exploratory (no confirmatory claims): I1/I3 ablations, per-regime
  breakdowns, geometry-oracle gap O0−P2, estimator-reset-on-crash ablation.

## 3. Operational definitions (implementable form)

- **False suspicion:** an election timer firing that transitions a follower to
  Candidate while exactly one leader exists in the cluster at that coordinate
  time (leader-alive criterion). The analytic causal-path refinement is an
  exploratory variant. Rate = suspicions / election-timer fires.
- **Crash-detection delay:** for each exogenous `CrashNode(f)` followed by a
  successful follower election: delay = proper time elapsed along the winning
  follower's worldline between the crash coordinate time and the election
  coordinate time. Censored when no majority is reachable before censoring.
- **Deadline availability, leader churn, throughput:** existing `RunMetrics`.
- **Cost:** bytes/s including metadata surcharge (I0=0, I1=+8 B, I2=+16 B,
  I3=+24 B per heartbeat copy).

## 4. Arms

| ID | Arm | Level | Notes |
|---|---|---|---|
| B0 | Fixed timeout, tuned per regime class | I0 | tuned like every arm; no strawman |
| B1 | Worst-case static from analytic χ bound | I0 | |
| B2 | Exponential backoff | I0 | resets on valid leader traffic |
| B3 | Arrival EWMA | I0 | wraps `Adaptations.RobustAdaptiveElectionPolicy` |
| B4 | Arrival sliding-window quantile | I0 | empirical receiver-proper inter-arrivals |
| B5 | φ-accrual | I0 | exponential model, tuned φ threshold |
| P1 | PT-FD sequence-only | I1 | gap-aware uncertainty inflation |
| P2 | PT-FD sequence + τ_emit | I2 | **primary arm** |
| P3 | PT-FD + nominal next interval | I3 | |
| O0 | Geometry oracle | — | upper reference; excluded from rankings |

Shared guardrails (plan §7.1): identical cold-start (all arms fall back to B0
until ≥ 3 observations), identical clamp budgets `[T_min, T_max]`, deadline
randomization retained inside the predictive band via the node RNG stream,
stale sequence numbers never move a deadline backward, estimator reset-on-crash
is an explicit ablation (default: reset).

## 5. Design and deviation from ideal CRN

Matched-replica paired design. Crashes, recoveries, partitions, and link
outages are exogenous scenario inputs and therefore **identical across arms**
within `(cell, replica)`. Propagation noise is i.i.d. per replica and keyed by
seed rather than message identity because legitimate policy differences change
message counts; this deviates from ideal common-random-numbers pairing and is
declared here as a limitation. Primary analysis is paired on
`(cell, replica)`; an unpaired sensitivity analysis is mandatory.

## 6. Confirmatory grid (≤ 48 cells)

- D_sr regime × ρ ∈ {0.1, 0.2, 0.4} × disruption ∈ {clean, loss 5 %,
  loss 15 % + reorder 20 %} × trajectory ∈ {inertial, accelerating onset}.
- D_sr regimes: approaching ≈ 1.3, stationary = 1.0, receding ≈ 0.77 and
  ≈ 0.58 (β ∈ {−0.25, 0, +0.25, +0.5}; signed β support added in P1).
- 5-node static membership; single client; workload/deadline fixed
  (8 ops, read_every 2, deadline 1.5 proper).
- 7-node and additional disruption levels: exploratory only.

## 7. Seeds, tuning/report split

- Tuning: replica seeds 1–200. All hyperparameters (B0 timeouts per regime
  class, B2 factors, B3 α and window, B4 window/quantiles, B5 φ, P1–P3
  quantile band z-values, buffer lengths, clamp budgets) are chosen on tuning
  traces only and fingerprinted.
- Report: replica seeds 201–700. Executed exactly once per arm×cell×replica
  after the r2 re-tag; no peeking, no reruns, no exclusions except
  preregistered safety-halt.

## 8. Statistics

Primary family (Holm-corrected, α = 0.05): {P1, P2, P3} vs best-arrival on
relative false-suspicion reduction, plus the P2 non-inferiority test. Paired
bootstrap (10 k resamples) over replicas within cell, then cell-level
aggregation reported separately (no pooling across cells into one p-value).
Effect sizes with percentile CIs; censoring reported; no post-hoc
subsetting.

## 9. Sample size procedure (P3)

Pilot: 24 replicas × 12 representative cells × all arms, tuning seeds only.
Estimate σ of per-cell paired log-ratios; choose per-cell N for 80 % power at
δ = 15 % (formula preregistered: N = ceil(2·(z_{0.975}+z_{0.80})²·σ²/(ln 0.85)²),
rounded up to a multiple of 10, capped at 120). Freeze N in an r2 addendum
before any report-seed execution.

## 10. Execution-status honesty box

At tag time: nothing below P0 is implemented. Pilot and confirmatory runs
have NOT been executed. Any partial execution performed during development
uses tuning seeds exclusively and is labeled PILOT; it cannot promote C4.

## 11. Stopping rules (from CLAIMS_AND_LIMITATIONS §4)

Any safety-flag failure (`raft_invariants && client_history &&
causal_deliveries && causal_trace`) on any arm halts E3 entirely pending root
cause. A violation inside the adaptation boundary invalidates the boundary
design, not Raft.

## 12. Deliverables map

| Deliverable | Location |
|---|---|
| Engine timing boundary + metadata side-channel | `src/Research/Engine.jl`, `src/Research/Detectors.jl` |
| Arms | `src/Research/Detectors.jl` (+ reuse of `Adaptations` policies for B3) |
| Runner / analysis CLI | `experiments/run_e3.jl`, `experiments/analyze_e3.jl` |
| Raw outputs (ignored) | `results/e3/<run-id>/manifest.json`, `runs.jsonl` |
| Report skeleton | `docs/E3_REPORT.md` |
