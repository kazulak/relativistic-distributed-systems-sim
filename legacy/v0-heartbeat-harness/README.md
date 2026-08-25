# Legacy v0 heartbeat harness (quarantined)

Status: **exploratory, superseded, and not publication evidence.**

This directory preserves the project's original exploratory heartbeat/T_VAT
harness: the phase scripts that produced it, their raw CSV outputs, generated
figures, and placeholder paper tables. It exists so the repository history and
the historical run commands remain reproducible while making it impossible to
mistake this material for evidence in the redesigned study.

Nothing in this directory may be used for effect sizes, uncertainty estimates,
pass/fail claims, or priors for confirmatory analysis.

## Why it was quarantined

The audit in [docs/PUBLISHABLE_RESEARCH_PLAN.md](../../docs/PUBLISHABLE_RESEARCH_PLAN.md)
(Section 1) invalidated this harness as a Raft study:

1. The model is not protocol-faithful Raft (no votes, logs, commits,
   persistence, or recovery; a timed-out follower stays `Candidate` forever).
2. The baseline-versus-T_VAT comparison is uncontrolled (different cold-start
   rules between arms).
3. The "100 seeds" are pseudo-replication: deterministic runs with no
   stochastic input.
4. `safety_violations` counts floating-point light-cone residuals, not any
   Raft safety property.
5. `availability` measures time without a candidate follower, not client
   service availability.
6. Phase 3 executes no Raft and mislabels spacelike (causally unrelated)
   writes as violations.

The claim-level rejections are tabulated in
[docs/CLAIMS_AND_LIMITATIONS.md](../../docs/CLAIMS_AND_LIMITATIONS.md),
Section 3 ("Legacy claim rejection"). The historical snapshot of this state is
tagged `v0.1-exploratory` on the initial commit.

## Contents

```text
legacy/v0-heartbeat-harness/
  README.md          # this file
  scripts/           # run_phase0..3.jl, analyze_results.jl
  results/           # raw phase CSVs, aggregated CSVs, SUMMARY.md
  figures/           # figure2..4 PDF/PNG outputs
  paper/             # placeholders.tex and generated LaTeX table stubs
```

## Running it

The scripts still require the separate analysis environment (plotting and
table dependencies live there) and still include the compatibility sources
from the package's `src/` directory directly:

```bash
julia --project=analysis -e 'import Pkg; Pkg.instantiate()'
julia --project=analysis legacy/v0-heartbeat-harness/scripts/run_phase0.jl
julia --project=analysis legacy/v0-heartbeat-harness/scripts/run_phase1.jl
julia --project=analysis legacy/v0-heartbeat-harness/scripts/run_phase2.jl
julia --project=analysis legacy/v0-heartbeat-harness/scripts/run_phase3.jl
julia --project=analysis legacy/v0-heartbeat-harness/scripts/analyze_results.jl
```

Outputs are written next to this README (`results/`, `figures/`, `paper/`),
not to the repository root. The current research pipeline lives in
`experiments/` and `src/Research/`; see the root README.
