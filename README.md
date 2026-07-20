# Relativistic Distributed Systems Simulator

## Research status

This repository is being redesigned from an exploratory heartbeat prototype
into a research-grade simulator. The typed physics kernel, generic simulation
core, and condensed static-membership Raft state machine are available through
the installed package. The older phase scripts and checked-in phase results
remain exploratory and are not publication-ready evidence. The research
questions, validity audit, and implementation gates are in
[the publishable research plan](docs/PUBLISHABLE_RESEARCH_PLAN.md).

This is a Julia 1.10 simulator for flat-spacetime distributed systems experiments. It contains:

- typed Minkowski events, worldlines, proper clocks, light-cone solvers, and
  Lorentz transforms;
- `RelativisticDistributedSystemsSim.SimulationCore`, containing the scheduler,
  local clocks, causal transport hooks, faults, and traces;
- `RelativisticDistributedSystemsSim.Raft`, containing elections, replication,
  majority commit, client operations, recovery, and invariant auditing; and
- compatibility access to the exploratory heartbeat/T_VAT helpers while legacy
  results are quarantined from scientific claims.

## Layout

```text
relativistic-distributed-systems-sim/
  Project.toml
  Manifest-v1.12.toml
  README.md
  src/
    RelativisticDistributedSystemsSim.jl
    Physics/
    Simulation/
    Protocols/Raft/
    raft_baseline.jl
    tvat.jl
  test/
    runtests.jl
    physics/
    raft/
  analysis/
    Project.toml
  scripts/
    run_phase0.jl
    run_phase1.jl
    run_phase2.jl
    run_phase3.jl
  results/
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
For a focused local run, set `RDS_TEST_GROUP` to `physics` or `raft`:

```bash
RDS_TEST_GROUP=physics julia --project=. test/runtests.jl
RDS_TEST_GROUP=raft julia --project=. test/runtests.jl
```

CI runs the canonical suite with bounds checking enabled and deprecation
warnings treated as errors on Julia 1.10 and the current stable Julia release.

## Legacy exploratory phase scripts

The phase commands below use the separate analysis environment and retain
direct source includes for historical reproducibility. They are not the
publication analysis pipeline and their outputs are not paper evidence.

## Gather Phase 0 Baseline Results

```bash
julia --project=analysis scripts/run_phase0.jl
```

This writes:

```text
results/phase0_baseline_YYYYMMDD_HHMMSS.csv
```

## Gather Phase 1 Degradation Results

```bash
julia --project=analysis scripts/run_phase1.jl
```

This runs the fixed-timeout Raft baseline for beta `0.0:0.05:0.9`, 100 deterministic seeds, and 10 seconds of coordinate time. Results are written to:

```text
results/phase1_degradation_YYYYMMDD_HHMMSS.csv
```

## Gather Phase 2 T_VAT Results

```bash
julia --project=analysis scripts/run_phase2.jl
```

This runs the same beta and seed sweep with T_VAT heartbeat timeout scaling and +/-0.1% leader emission jitter. Results are written to:

```text
results/phase2_tvat_YYYYMMDD_HHMMSS.csv
```

## Gather Phase 3 Causal Stress Results

```bash
julia --project=analysis scripts/run_phase3.jl
```

This runs the multi-leader simultaneity stress test and writes:

```text
results/phase3_causal_YYYYMMDD_HHMMSS.csv
```

Phase 0, 1, and 2 CSV columns:

- `seed`: deterministic trial seed.
- `beta`: leader velocity as a fraction of `c_sim`.
- `duration`: coordinate-time simulation duration.
- `heartbeats_sent`: scheduled leader heartbeats.
- `heartbeats_delivered`: heartbeats delivered before the run horizon.
- `false_elections`: follower timeouts that become candidate transitions.
- `safety_violations`: non-lightlike network deliveries by invariant interval check.
- `availability`: fraction of simulated time with no follower in candidate state.

Phase 3 CSV columns:

- `seed`: deterministic trial seed.
- `beta_pair`: pair of leader velocities compared.
- `total_writes`: writes evaluated for that pair.
- `spacelike_writes`: write pairs with invariant interval `s^2 < 0`.
- `causal_violation_rate`: `spacelike_writes / total_writes`.
- `merge_overhead_ms`: deterministic merge overhead accumulated for spacelike writes.

## Read Results

In Julia:

```julia
rows = readlines("results/phase1_degradation_YYYYMMDD_HHMMSS.csv")
header = split(rows[1], ",")
data = split.(rows[2:end], ",")
```

Or with standard shell tools:

```bash
column -s, -t results/phase*_*.csv | less -S
```

## Notes

Protocol decisions and validation checks use the Minkowski interval with signature `(+---)`. The simulation uses one inertial coordinate frame as the scheduler, while network delivery is determined by `solve_light_time`.
