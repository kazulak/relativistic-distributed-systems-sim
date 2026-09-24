# Deviation and erratum log

Status: opened 2026-09-23 by a repository audit. This log records every known
departure from the preregistered designs (`PRE_REGISTRATION_E3*.md`), the
claim register (`CLAIMS_AND_LIMITATIONS.md`), and the research plan, together
with its consequence for evidence. Entries are append-only; a resolution is
added as a dated note, never by editing the original finding.

Consequence classes:

- **Void:** affected outputs may not be used as evidence for any claim.
- **Exploratory:** outputs may be described as pilot/exploratory only.
- **Blocking:** no confirmatory run may start until resolved.

## Summary of consequences

- C2 and C3 are returned from "Eligible" to **Target**. The RQ1 runs in
  `results/rq1/confirmatory_e1` and `results/rq1/confirmatory_e2` are
  reclassified as **exploratory** (D-05, D-06, D-07, D-08).
- The E3 addendum r3 sample-size freeze and seed statement are **withdrawn**;
  the `v0.3-e3-prereg-r3` tag named in r3 was never created and must not be
  created from that text (D-01, D-02).
- All E3 pilot outputs remain tuning-range pilot material. Confirmatory E3
  execution is **blocked** pending a new addendum (r4) that resolves D-01–D-04,
  D-09–D-12, and D-15–D-17; a draft is in `PRE_REGISTRATION_E3_ADDENDUM_r4_DRAFT.md`.
- All RQ1 and E3 client-progress numbers produced before the D-14 fix are
  **void** (client traffic had no propagation delay).

## Entries

### D-01 — Report seeds 201–224 were executed (E3) — Void / Blocking

`results/e3/pilot-20260826_151250/runs.tsv` contains 7,177 rows with seeds
201–224, inside the preregistered report range (201–700; r3: 201–320).
Addendum r2 voided these rows, but addendum r3 §3 states that seeds 201–320
"have remained completely untouched and unread", which is incorrect. The
outputs of those seeds have been produced and were available to the
investigators. Resolution required: r4 must declare a fresh, never-executed
report range and record 201–224 as contaminated.

### D-02 — r3 sample-size freeze rests on an artifactual power analysis — Void

`experiments/power_analysis_e3.jl` (as of 1f776f5):

- added a `+1e-4` smoothing constant to per-replica false-suspicion rates, of
  which 7,156/11,880 pilot rows are exactly zero; the resulting
  σ(ln ratio) = 2.5–5.2 is driven by the constant, not by the data;
- applied the two-sample `2σ²` formula to paired differences;
- considered only B4/B5 as best-arrival (preregistration §2: B3/B4/B5);
- applied an undocumented floor `max(N, 40)`;
- read `committed` and `p95` from the wrong columns (unused);
- never reported achieved power at the N = 120 cap.

The r3 freeze of N = 120 is therefore not a valid application of
preregistration §9. The tag `v0.3-e3-prereg-r3` does not exist.

### D-03 — E3 co-primary endpoint unobservable — Blocking

The E3 cells in `experiments/run_e3.jl` contain no crash faults, so
`detection_n = 0` in every pilot row. The preregistered P2 non-inferiority
test on p95 crash-detection delay (§2) cannot be evaluated on this design.

### D-04 — E3 arms were not tuned — Blocking

Preregistration §7 requires all hyperparameters to be chosen on tuning
traces and fingerprinted. Arm parameters were hard-coded in `run_e3.jl`; no
tuning procedure existed. The O0 geometry-oracle arm (§4) was not
implemented.

### D-05 — E1 "deterministic" cells are single stochastic draws (RQ1) — Exploratory

Raft election deadlines are drawn from per-node seeded RNG streams, so a
scenario run is not deterministic across seeds. E1 ran each cell once
(seed 1) and treated it as an exact result. E2 shows the same configuration
(`AsymmetricRecedingInertial`, n = 3, β = 0.25, ρ = 0.2, clean) ranging from
0 % to 100 % deadline availability across 10 seeds. E1 cells are one draw
from a wide distribution, not a phase map.

### D-06 — C2 wording contradicted by its own data — Void (wording)

The claim register stated "monotonic progress loss as χ ≥ 0.50". In
`confirmatory_e1`: `e1_recede_n5_b0.25_r0.1` (χ = 0.663) has 100 % deadline
availability; `e1_static_n5_r0.6_th5_7` (χ = 0.48) has 25 % while
`..._th3_5` (χ = 0.80) has 75 %. `experiments/analyze_rq1.jl` printed
"H1b Validated" unconditionally. H1b (χ/D_sr explain progress better than
β) and H1c (analytic transition within preregistered tolerance) were never
tested, and E1/E2 had no preregistered SLO, sample size, or intervals.

### D-07 — Run provenance insufficient — Exploratory

Every manifest (RQ1 and E3) recorded `git rev-parse HEAD` without a dirty
flag; the recorded SHA predates the code that produced the rows (E3 pilots
record 8d2e006, the prereg-only commit; RQ1 "confirmatory" runs record
5237284, but 1f776f5 changed the Research engine and scenarios). Under the
register's stopping rule ("Missing raw manifest/config/version information
makes a run ineligible"), these runs are ineligible as paper results.
`results/` is git-ignored, so no evidence is archived with the repository.
Runs.tsv files also lacked failure reasons and per-oracle safety flags.

### D-08 — C3 oracle weaker than Proposition 1 and partly vacuous — Exploratory

`causal_quorum_bound` omitted the client→leader and leader→client segments
of Proposition 1; `verify_causal_quorum_bounds` returned a margin of `0.0`
for runs with no committed writes, so "min margin ≥ 0" summaries were
largely vacuous; the oracle reused the engine's light-cone solver, so it was
not the "independent calculation" the register requires; the unattainable
region (deadlines below the bound) was never exercised.

### D-09 — 7.7 % of E3 pilot runs aborted on solver errors — Blocking

909/11,880 pilot runs have status `failed`: physics-kernel
`LightConeConvergenceError`s (sub-ulp acceptance tolerance; iteration
exhaustion on accelerating worldlines). Failures differ by arm (B4: 145,
P3: 76), i.e. missingness is arm-dependent. Validation gates V0/V1 are
reopened for the operating regime (see `VALIDATION_GATES.md`).

### D-10 — E3 realized regimes do not match the preregistered grid — Blocking

Measured source/receiver rate ratios at measurement start are
{1.0, 1.065, 1.134}, versus preregistered regimes ≈1.3 / 1.0 / 0.77 / 0.58.
"flyby β = −0.25" and "recede β = +0.25" are the same regime at measurement
start; all trajectory-onset cells have D_sr = 1.0. The pilot grid has 55
cells against the preregistered ≤ 48 (§6).

### D-11 — E3 CLI flags silently ignored — Blocking

`run_e3.jl` flag handlers assigned `global` variables while `main` read
locals, so `--replicas`, `--seed-base`, `--arms`, `--out` had no effect
(verified). The frozen confirmatory command could not have executed as
described.

### D-12 — E3 analyzer not the preregistered analysis — Blocking

`experiments/analyze_e3.jl` substituted fixed pseudo p-values (0.02/0.4),
applied an incorrect Holm step, selected the best arrival arm on report data,
pooled cells into one bootstrap over rows, omitted the non-inferiority and
unpaired sensitivity analyses, and read wrong columns.

### D-13 — Documentation inconsistencies — Resolved in this remediation

`CLAIMS_AND_LIMITATIONS.md` §1 ("every substantive claim is a target")
contradicted §2 (C2/C3 "Eligible"); `EXPERIMENTS.md` said results stay in
memory; the preregistration promised `runs.jsonl` and `docs/E3_REPORT.md`,
which do not exist.

### D-14 — Client traffic bypassed causal transport — Void (RQ1 progress metrics) / Blocking

Found by the rewritten C3 oracle (full five-segment Proposition 1).
`src/Research/Engine.jl` delivered a client request to the target node at
the client's own event time (`_attempt_client!` applied `ClientInput` on the
target directly) and scheduled the leader's reply at the client at the
leader's commit time (`ReplyClient` effect handler). Client→leader and
leader→client legs therefore had zero propagation delay whenever the leader
was not the client's node, and the target was chosen with global knowledge
of the current leader. Consequences: client-proper latencies and deadline
availability in every RQ1/E3 run are optimistic when the leader is remote;
committed writes completed below the Proposition 1 bound (e.g.
`SeparatedStaticBaseline`, n = 5: margin −0.075 against a tolerance of
≈1.6e-10); and the `causal_trace` oracle did not detect these spacelike
parent edges. All RQ1 progress numbers produced before the fix are void.

### D-15 — Leader heartbeat timers silently dropped on quadrature worldlines — Void (affected runs)

On `ParametricWorldline` clocks, converting a local timer deadline to
coordinate time and back could land a few ulps before the deadline (e.g.
−5.8e-15). Raft rejected the early timer and never re-armed it, so the
leader stopped heartbeating permanently. This plausibly affected every
pilot `trajectory_change_scenario` cell. Fixed in `Engine._timer_coordinate`
(forward nudge until the node clock reaches the deadline; no-op for
closed-form clocks).

### D-16 — Preregistration §6 states D_sr in the inverse convention — Blocking (wording)

The code and `EXPERIMENTS.md` define D_sr as receiver-proper inter-arrival
divided by source-proper emission interval (receding > 1). Preregistration
§6 lists "approaching ≈ 1.3, receding ≈ 0.77/0.58", which is the frequency
convention. The β values {−0.25, 0, +0.25, +0.5} map to D_sr = 0.775 / 1 /
1.291 / 1.732 under the code convention. r4 must state one convention.

### D-17 — Receding E3 regimes cannot observe crash detection — Blocking (design)

With θ = (5, 7) heartbeats, sustaining D_sr > 1 makes one-way delay grow by
≈ β heartbeats per heartbeat (ρ drifts from ≈0.2 to 5–10 within the
window). Once one-way latency exceeds the timeout randomization spread,
post-crash elections split and never complete before censoring: 100 % of
detections are censored in receding cells for every arm and crash placement
tried. The P2 non-inferiority endpoint is therefore estimable only in
stationary and approaching cells unless θ or the window changes. r4 must
choose.

## Remediation notes

- 2026-09-23: branch `audit-remediation` opened. See the entries above for
  per-item status; each fix is recorded below when verified.
- D-02, D-12: `experiments/analyze_e3.jl` and `power_analysis_e3.jl`
  rewritten on `experiments/lib/e3_stats.jl` (header-name parsing, tuning-only
  best-arrival selection, per-cell paired cluster bootstrap, exact/Monte Carlo
  sign-flip p-values, correct Holm step-down, non-inferiority test with
  NOT ESTIMABLE → INDETERMINATE, unpaired and run-status sensitivity analyses,
  differential-missingness screen, safety halt, no smoothing constants).
  Tests: `test/experiments/runtests.jl`. The pilot power exercise shows
  N = 120 reaches 80 % power in 4 of 46 estimable cells at δ = 15 %; the
  sample-size rule itself is an r4 decision.
- D-03, D-04, D-10, D-11: `experiments/run_e3.jl` rewritten (pure argument
  parser, report-role guards: confirmatory flag, clean tree, tuned file,
  report-range seeds, fresh output directory); `experiments/tune_e3.jl`
  tunes every arm on tuning seeds only; `experiments/lib/e3_cells.jl` holds a
  48-cell grid built on `dsr_regime_scenario` with realized D_sr on target
  (0.78 / 1.00 / 1.29 / 1.73); leader-crash schedule makes detection delay
  observable (except D-17); O0 geometry oracle implemented. Tests:
  `test/research/e3_design.jl`. All of these are *proposals* for the r4
  addendum; none is frozen.
- D-05, D-06, D-07: `experiments/run_rq1.jl` runs every cell over seeds and
  writes provenance-complete manifests (HEAD, dirty flag, diff digest,
  role, prereg tag, seeds, cell fingerprints) plus failure reasons and
  per-oracle flags; confirmatory sweeps require a clean tree and a prereg
  tag and never overwrite a run directory. `experiments/analyze_rq1.jl`
  reports bootstrap intervals over runs and no hard-coded verdicts. RQ1
  confirmatory design drafted in `PRE_REGISTRATION_RQ1_DRAFT.md`.
- D-08: full five-segment oracle (`causal_quorum_chain`,
  `causal_quorum_bound`, `verify_causal_quorum_bounds`) with an independent
  bisection solver, scale-aware tolerance, `NaN` margin when nothing is
  audited, closed-form collinear-inertial checks, and negative controls
  (`test/research/causal_bounds.jl`).
- D-09: light-cone acceptance floor and ULP-aware safeguarded Newton
  (`src/Physics/LightCone.jl`, `test/physics/light_cone_regressions.jl`);
  declared worldline kinks split proper-time quadrature
  (`worldline_kinks`, `test/physics/worldline_kinks.jl`). Full E3 tuning
  smoke (48 cells × 10 arms × seeds 1–2 = 960 runs): 0 failed, 0 invalid.
- D-14: client requests and replies now propagate along the light cone
  (plus processing delay) and are causality-checked on arrival; the
  previously broken full-chain C3 test passes. Exploratory RQ1 sweeps after
  the fix (E1 48 cells × 5 seeds, E2 16 cells × 5 seeds): 320/320 runs
  clean, 0 bound violations, 475 writes audited, minimum margin 0.0040.
  Target routing still uses global knowledge of the current leader (oracle
  routing), an explicit modeling assumption in `EXPERIMENTS.md`.
