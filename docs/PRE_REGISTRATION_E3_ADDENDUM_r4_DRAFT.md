# Pre-registration addendum r4 — Experiment E3 — DRAFT

Status: **DRAFT, not frozen, not tagged.** Prepared 2026-09-24 during audit
remediation. It supersedes the withdrawn addendum r3 and resolves the
blocking entries D-01–D-04, D-09–D-12, and D-15–D-17 in `DEVIATIONS.md`.
Every item below is a *proposal implemented in code* unless marked
**[DECIDE]**; the researcher must accept, amend, or reject each before this
file is renamed `PRE_REGISTRATION_E3_ADDENDUM_r4.md` and tagged
`v0.3-e3-prereg-r4`. The base hypotheses (H-primary, H-null), the
δ = 15 % practical threshold, and the 5 % non-inferiority margin are
unchanged unless stated.

## 1. Corrections to the base document

1. **D_sr convention (D-16).** D_sr = receiver-proper inter-arrival /
   source-proper emission interval; receding > 1. The regimes are
   β ∈ {−0.25, 0, +0.25, +0.5} → D_sr ≈ 0.775 / 1.000 / 1.291 / 1.732.
2. **False suspicion.** A follower→candidate election-timer fire while
   exactly one leader is alive. Candidate re-fires are not suspicions. All
   counts are restricted to the measurement window.
3. **Crash-detection delay.** Only a crash of the sole active leader opens a
   detection obligation; the delay is proper time along the winning node's
   worldline from the crash to the moment it *becomes leader* with a higher
   term; unresolved obligations are censored at the horizon.

## 2. Design (implemented in `experiments/lib/e3_cells.jl`)

1. **Scenario builder.** `dsr_regime_scenario` (`src/Research/DsrScenarios.jl`):
   a homothetic 5-node formation (triangular bipyramid in velocity space) so
   9 of 10 node pairs realize the target D_sr exactly at measurement start;
   receding regimes ramp to speed at measurement start and coast; the
   approaching regime makes an outward excursion during warm-up, then
   coasts inbound through the window without crossings. ρ drifts during the
   window by construction (sustained D_sr ≠ 1 requires it). Realized median
   D_sr in the smoke run: 0.78 / 1.00 / 1.29 / 1.73.
2. **Grid (48 cells).** 4 D_sr regimes × ρ ∈ {0.1, 0.4} × disruption ∈
   {clean, loss 5 %, loss 15 % + reorder 20 %} × trajectory ∈ {inertial,
   onset}. The base document's factors give 72 cells, exceeding its own
   ≤ 48 cap; the middle ρ level is dropped. **[DECIDE: this or
   ρ ∈ {0.1, 0.2, 0.4} × {clean, loss 15 % + reorder 20 %}.]**
3. **Trajectory onset.** The trajectory change occurs at 50 % of the
   measurement window, ramping over 25 % of it.
4. **Window.** Warm-up 5, measurement 4, censor 2, in the scenario's
   coordinate-time units as set in `experiments/lib/e3_cells.jl`.
5. **Crash schedule.** `CrashLeader`: at measurement start + 1.5 and + 2.7
   the sole active leader (if any) crashes and recovers 0.3 later. The rule
   and times are identical across arms; the victim's identity is
   endogenous. **[DECIDE: this rule or the strictly node-exogenous rotating
   schedule (`mode = :rotating`).]**
6. **Receding cells and censoring (D-17).** Detection is fully censored in
   receding cells under θ = (5, 7). **[DECIDE: (a) restrict the
   non-inferiority test to stationary and approaching cells and report
   receding cells for false suspicion only; or (b) change θ or the window
   and re-pilot.]**

## 3. Arms and tuning (implemented in `experiments/tune_e3.jl`)

1. New hyperparameters `miss_tolerance` (band multiplier) and `ewma_alpha`;
   timing fingerprint version `e3-timing-v2`.
2. Tuning objective per regime class, pooled over that class's cells and the
   tuning seeds: minimize false suspicions per follower heartbeat subject to
   pooled p95 detection delay ≤ 2.0 (censored detections count as +∞);
   fallback when infeasible: lowest censored fraction, then lowest p95,
   then lowest rate. B0 is tuned first and its timeout is every arm's
   cold-start timeout. B1 is analytic (4 missed heartbeats × worst design
   D_sr + slack). Grids are listed in `tune_e3.jl`.
3. Tuning seeds: 1–40 of the 1–200 tuning range. **[DECIDE]**
4. O0 geometry oracle implemented as a reference arm, excluded from rankings.

## 4. Primary outcome and analysis (implemented in `experiments/lib/e3_stats.jl`)

1. **Primary rate [DECIDE].** Either the base definition, suspicions /
   election fires (`false_suspicion_rate`, current default), or suspicions
   per follower heartbeat of leader presence
   (`suspicions_per_follower_heartbeat`), which leaderless election churn
   cannot dilute. (Suspicions / leader-present fires is identically 1 and is
   not a candidate.)
2. **Best-arrival.** Selected on tuning data only among B3/B4/B5, globally
   (mean of per-cell means). **[DECIDE: global or per cell.]**
3. **Tests.** Per cell: relative reduction 1 − mean_P/mean_B with a paired
   cluster bootstrap over replicas (10 k resamples); two-sided paired
   sign-flip p-values; Holm step-down within each cell over {P1, P2, P3
   superiority, P2 non-inferiority}. Cross-cell results are reported only
   as counts (descriptive) and a cross-cell Holm (exploratory). **[DECIDE:
   how per-cell verdicts combine into the single C4 verdict.]**
4. **Decision rule.** ELIGIBLE iff P2 superiority Holm p ≤ 0.05, point
   relative reduction ≥ 0.15, CI lower bound > 0, and non-inferiority Holm
   p ≤ 0.05; non-inferiority not estimable → INDETERMINATE.
5. **Failed runs.** Pairs where either arm did not complete are excluded
   from the estimand and reported with a differential-missingness screen;
   `include_failed` is a sensitivity. **[DECIDE: response if differential
   missingness is detected.]**
6. **Sample size [DECIDE].** The base §9 log-ratio formula is unusable with
   zero-inflated rates (D-02). Proposed: paired rate-difference power,
   N = (z₀.₉₇₅ + z₀.₈₀)² σ_d² / (0.15 · mean_B)², from a pilot on the new
   grid; report achieved power per cell at the chosen N and cap. On the old
   pilot, N = 120 gave ≥ 80 % power in only 4 of 46 estimable cells.

## 5. Seeds and execution

1. Tuning seeds: 1–200 (pilot and tuning only).
2. Report seeds: **1001–1120** (fresh; 201–224 contaminated by D-01).
   Changing N changes the range end. **[DECIDE]**
3. The report run executes once per cell × arm × seed with
   `run_e3.jl --role report --confirmatory --tuned <file> --prereg
   v0.3-e3-prereg-r4` from a clean tree; the runner halts on the first safety
   failure (§11) and refuses to overwrite an output directory.
4. Behavioral changes since the r2/r3 pilots (timer boundary fix D-15, client
   transport D-14, solver fixes D-09) mean that pilot data may not be reused
   for sample-size estimation; a new tuning-range pilot on the r4 grid is
   required before the freeze.
