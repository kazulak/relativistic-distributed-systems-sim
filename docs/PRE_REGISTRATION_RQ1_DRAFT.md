# Pre-registration — RQ1 (Stages E1/E2) — DRAFT

Status: **DRAFT, not frozen.** Prepared 2026-09-23 during audit remediation
(`DEVIATIONS.md` D-05–D-08). Items marked **[DECIDE]** need an explicit
researcher decision before this document is renamed
`PRE_REGISTRATION_RQ1.md` and tagged `v0.4-rq1-prereg`. Once tagged, it follows the same rules as the E3
preregistration: no in-place edits, superseding addenda only. It maps to
claim-register rows C2, C3 (bound audit), and C8.

## 1. Research question and hypotheses

RQ1 (research plan §4): across physically admissible worldlines and causal
networks, which dimensionless timing regimes cause unmodified Raft to lose
timely progress while its replicated-log safety properties remain intact?

- **H1a (safety):** in every completed run, all four safety oracles
  (`raft_invariants`, `client_history`, `causal_deliveries`, `causal_trace`)
  pass. Decision: any violation halts RQ1 pending root cause. Runs with status
  `failed` (exception before the censor horizon) are reported with their
  reason and count as *unaudited*, never as passes; a failure rate above
  **[DECIDE: 0 %]** blocks the C2 claim.
- **H1b (explanatory variables):** per-run deadline availability is predicted
  better by (χ, D_sr) than by |β| alone. Test: leave-one-cell-out
  cross-validated log-loss of two pre-specified binomial models on
  per-operation outcomes aggregated per run (committed out of invoked),
  model A: logit(p) ~ χ + log D_sr; model B: logit(p) ~ |β|; H1b supported
  if model A's CV log-loss is lower with a paired bootstrap (over cells) 95 %
  CI of the difference excluding zero. **[DECIDE: model forms; whether
  cluster size enters both models.]**
- **H1c (analytic transition):** for stationary collinear layouts, the
  analytic prediction is that a write can meet deadline D only if
  D ≥ causal quorum bound (Proposition 1); and the leader-stability
  transition occurs where the quorum heartbeat round trip approaches
  θ_min (χ → 1). **[DECIDE: the precise analytic availability curve and a
  numerical agreement tolerance, e.g. |predicted − observed transition χ| ≤
  0.05.]** If no closed-form curve is adopted, H1c is dropped and reported
  as untested, not as supported.

## 2. Primary outcome and SLO

- Deadline availability per run: committed / (committed + censored), with
  the client deadline `deadline_proper` in client proper time.
- SLO for C2 wording ("misses the declared progress SLO"): a cell misses the
  SLO when the upper 95 % bootstrap bound of mean deadline availability over
  runs is below **[DECIDE: 0.99]**.
- Secondary: leader availability, elections started, terms, message/byte
  cost. Descriptive only.

## 3. Design

- Experimental unit: the run (one seed). Operations within a run are not
  independent replicates.
- Grid: the E1/E2 cells in `experiments/run_rq1.jl` (`e1-full`, `e2-full`)
  plus the plan-required gaps **[DECIDE: which to add before freezing]**:
  transverse motion, crossing trajectories, symmetric moving clusters,
  cluster size 7, correlated loss bursts, planned contact windows, offered
  load near saturation, and cells with `PartitionDropStress` crash/partition
  faults (the current E2 "stress" cells use a stress *network* profile on a
  static layout without crashes).
- Deadline sweep for C3's unattainable region: for each stationary cell,
  deadlines at 0.5×, 1×, 1.5×, 3× the Proposition 1 bound; prediction:
  zero commits within deadline below 1×.

## 4. Seeds and sample size

- Exploratory pilot: seeds 1–20 (`EXPLORATORY_SEEDS`), any number of times.
- Confirmatory seeds: **[DECIDE: e.g. 5001–5000+N]**, disjoint from all
  E3 ranges, executed once with `--confirmatory --prereg v0.4-rq1-prereg`.
- N per cell: chosen from the pilot so that the 95 % CI half-width of mean
  deadline availability is ≤ **[DECIDE: 0.05]** in the highest-variance cell,
  capped at **[DECIDE]**; the achieved half-width is reported for every cell.

## 5. Analysis

- `experiments/analyze_rq1.jl` produces the descriptive per-cell table,
  failure accounting, and the causal-bound audit (with the number of writes
  actually audited). The H1b model comparison and the H1c comparison must be
  implemented and tested on pilot data **before** the tag. **[TODO]**
- No exclusions except runs halted by a safety violation (reported).
- All cells are reported; no post-hoc subsetting.

## 6. Provenance

Confirmatory runs require a clean tree at the tagged commit (enforced by the
runner), and the output directory plus a SHA-256 of `runs.tsv` is archived
**[DECIDE: location, e.g. Zenodo or a `results-archive` branch]** before any
claim-register update cites it.
