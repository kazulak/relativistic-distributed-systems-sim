# Relativistic Distributed Systems Simulator

## Research status

This repository is being redesigned from an exploratory heartbeat prototype
into a research-grade simulator. The typed physics kernel, generic simulation
core, and condensed static-membership Raft state machine are available through
the installed package. The original exploratory harness (scripts, results,
figures, and paper placeholders) is quarantined under
[legacy/v0-heartbeat-harness](legacy/v0-heartbeat-harness) and is not
publication-ready evidence. The research questions, validity audit, and
implementation gates are in
[the publishable research plan](docs/PUBLISHABLE_RESEARCH_PLAN.md).

This is a Julia 1.10 simulator for flat-spacetime distributed systems experiments. It contains:

- typed Minkowski events, worldlines, proper clocks, light-cone solvers, and
  Lorentz transforms;
- `RelativisticDistributedSystemsSim.SimulationCore`, containing the scheduler,
  local clocks, causal transport hooks, faults, and traces;
- `RelativisticDistributedSystemsSim.Raft`, containing elections, replication,
  majority commit, client operations, recovery, and invariant auditing;
- `RelativisticDistributedSystemsSim.Research`, the deterministic standard-Raft
  scenario harness for the RQ1 experiments, with proper-time clocks, causal
  transport, client workloads, and safety oracles;
- `RelativisticDistributedSystemsSim.Adaptations`, fingerprintable timing,
  redundancy, placement, and cost-quality policy tooling; and
- compatibility access to the exploratory heartbeat/T_VAT helpers while legacy
  results are quarantined from scientific claims.

## Layout

```text
relativistic-distributed-systems-sim/
  Project.toml
  Manifest-v1.12.toml
  README.md
  LICENSE
  CITATION.cff
  docs/
  src/
    RelativisticDistributedSystemsSim.jl
    Physics/
    Simulation/
    Protocols/Raft/
    Adaptations/
    Research/
    light_time.jl        # legacy compatibility surface
    raft_baseline.jl     # legacy compatibility surface
    tvat.jl              # legacy compatibility surface
  test/
    runtests.jl
    physics/
    raft/
    research/
    adaptations/
  experiments/
    run_rq1.jl
    analyze_rq1.jl
    run_e3.jl
    analyze_e3.jl
    power_analysis_e3.jl
    configs/rq1/
  formal/                # TLA+ models and validation harness inputs
  scripts/               # formal-validation harness entry points
  analysis/
    Project.toml
  legacy/
    v0-heartbeat-harness/
```

## Setup

From this directory:

```bash
julia --project=. -e 'import Pkg; Pkg.instantiate()'
```

Julia 1.12 selects the checked `Manifest-v1.12.toml`, preserving the validated
1.12 dependency closure. There is deliberately no unversioned `Manifest.toml`:
Julia 1.10 and other supported minor releases resolve the compatibility bounds
in `Project.toml` independently instead of consuming 1.12 standard-library
pins. Julia 1.10 remains an external CI compatibility gate.

The root environment intentionally contains only dependencies needed to load
and test the package. Plotting, data-frame, and legacy-script dependencies are
isolated in `analysis/Project.toml`:

```bash
julia --project=analysis -e 'import Pkg; Pkg.instantiate()'
```

## Run Tests

```bash
julia --project=. -e 'import Pkg; Pkg.test()'
```

`Pkg.test()` is the canonical entry point and imports the installed package.
For a focused local run, set `RDS_TEST_GROUP` to `physics`, `raft`,
`research`, `adaptations`, or `differential`:

```bash
RDS_TEST_GROUP=physics julia --project=. test/runtests.jl
RDS_TEST_GROUP=raft julia --project=. test/runtests.jl
RDS_TEST_GROUP=research julia --project=. test/runtests.jl
RDS_TEST_GROUP=adaptations julia --project=. test/runtests.jl
RDS_TEST_GROUP=differential julia --project=. test/runtests.jl
```

## Run an RQ1 Scenario

The deterministic standard-Raft scenario harness lives in the `Research`
component namespace. See [docs/EXPERIMENTS.md](docs/EXPERIMENTS.md) for the
scenario families, configuration schema, and metric definitions.

```bash
julia --project=. experiments/run_rq1.jl all 3 7
```

Families: `control | static | receding | accelerating | stress | all`.
Optional arguments are cluster size and seed. The command exits nonzero if a
run does not complete with clean safety flags.

CI runs the canonical suite with bounds checking enabled and deprecation
warnings treated as errors on Julia 1.10 and the current stable Julia release.

## Legacy exploratory harness

The original heartbeat/T_VAT phase scripts, their raw CSV outputs, generated
figures, and placeholder paper tables are quarantined under
[legacy/v0-heartbeat-harness](legacy/v0-heartbeat-harness). They are
exploratory material: the audit in the research plan invalidated them as a
Raft study, and none of their numbers may be used as evidence. See that
directory's README for why it was quarantined and how to re-run it.

The `light_time.jl`, `raft_baseline.jl`, and `tvat.jl` sources remain in
`src/` only as a tested compatibility surface for the scalar solver helpers;
they are not part of the research pipeline.

## Notes

Protocol decisions and validation checks use the Minkowski interval with signature `(+---)`. The simulation uses one inertial coordinate frame as the scheduler, while network delivery is determined by causal light-cone solving.

## License

[MIT](LICENSE)

## Citation

If you use this software, please cite it via the metadata in
[CITATION.cff](CITATION.cff).

