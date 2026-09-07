# Pre-registration addendum r3 — Experiment E3

Status addendum to `PRE_REGISTRATION_E3.md` and `PRE_REGISTRATION_E3_ADDENDUM_r2.md`,
tagged `v0.3-e3-prereg-r3` (2026-09-07). The frozen hypotheses, estimands,
grid, seed partition, and decision rules of the base documents are unchanged.

## 1. Pilot execution completion

The full 24-replica pre-registration pilot sweep has been executed:
- **Scope**: 55 cells × 24 replicas × 9 arms = 11,880 total runs.
- **Data Location**: `results/e3/pilot-20260907_191625/runs.tsv`.
- **Seed Discipline**: Executed strictly within tuning seed space 1–24 (`--seed-base 0`).
  Zero report-seed space (201+) was accessed during the pilot.
- **Safety Oracle Audit**: Zero invariant violations, zero linearizability failures,
  zero causal delivery anomalies across all 11,880 runs.

## 2. Power analysis and sample size derivation

As specified in `PRE_REGISTRATION_E3.md` §9, sample size is determined to provide
80% statistical power at two-sided $\alpha = 0.05$ to detect a $\delta = 15\%$
relative reduction in false suspicion rate ($\ln 0.85 = -0.1625$):

$$N = \left\lceil \frac{2 (z_{0.975} + z_{0.80})^2 \sigma_{\ln \text{ratio}}^2}{(\ln 0.85)^2} \right\rceil$$

where $z_{0.975} = 1.95996$ and $z_{0.80} = 0.84162$.

Per the pre-registration protocol, calculated raw sample sizes are rounded up to the nearest
multiple of 10 and capped at 120.

Power analysis executed via `experiments/power_analysis_e3.jl` over the 11,880 pilot runs produced:
- In regimes with high volatility (e.g. onset acceleration, elevated Doppler, packet loss),
  $\sigma_{\ln \text{ratio}}$ ranges from 2.5 to 5.2, driving raw $N$ beyond the cap.
- In low-variation quiescent regimes, smaller sample sizes suffice ($N = 10 \text{ to } 20$).
- Across all 55 evaluated cells, the maximum required sample size reaches the pre-registered ceiling of 120.

## 3. Authoritative sample size freeze

Per §9 of the pre-registration plan, the per-cell sample size is formally frozen:

$$\mathbf{N = 120 \text{ replications per cell}}$$

### Confirmatory Execution Boundary
- **Target Arms**: B0, B1, B2, B3, B4, B5, P1, P2, P3 (full 9-arm grid).
- **Report Seed Range**: Seeds **201 to 320** ($N = 120$).
- **Seed Inviolability**: Seeds 201–320 have remained completely untouched and unread throughout all pilot and tuning phases.
- **Execution Protocol**: The confirmatory report run will be executed exactly once per cell-arm-seed combination. No post-hoc subsetting, re-tuning, or re-running will be performed.
