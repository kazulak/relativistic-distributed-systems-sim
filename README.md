# Relativistic Distributed Systems Simulator

This is a Julia 1.10 simulator for flat-spacetime distributed systems experiments. It contains:

- A zero-allocation light-time solver for signal delivery between inertial worldlines.
- Phase 0 solver tests for radial motion, transverse Doppler behavior, causal ordering, deterministic RNG, and allocation checks.
- A minimal 5-node Raft baseline harness with fixed follower timeouts and FIFO per-sender delivery.
- T_VAT helpers for Doppler-aware heartbeat timeout scaling.

## Layout

```text
relativistic-distributed-systems-sim/
  Project.toml
  README.md
  src/
    RelativisticDistributedSystemsSim.jl
    light_time.jl
    raft_baseline.jl
    tvat.jl
  test/
    test_solver.jl
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

## Run Tests

```bash
julia --project=. test/test_solver.jl
```

The solver test suite runs 10,000 deterministic random geometries with `StableRNG(1234)` and checks Newton convergence, analytic radial motion, transverse Doppler timing, invariant causal ordering, and zero allocations on the solver hot path.

## Gather Phase 0 Baseline Results

```bash
julia --project=. scripts/run_phase0.jl
```

This writes:

```text
results/phase0_baseline_YYYYMMDD_HHMMSS.csv
```

## Gather Phase 1 Degradation Results

```bash
julia --project=. scripts/run_phase1.jl
```

This runs the fixed-timeout Raft baseline for beta `0.0:0.05:0.9`, 100 deterministic seeds, and 10 seconds of coordinate time. Results are written to:

```text
results/phase1_degradation_YYYYMMDD_HHMMSS.csv
```

## Gather Phase 2 T_VAT Results

```bash
julia --project=. scripts/run_phase2.jl
```

This runs the same beta and seed sweep with T_VAT heartbeat timeout scaling and +/-0.1% leader emission jitter. Results are written to:

```text
results/phase2_tvat_YYYYMMDD_HHMMSS.csv
```

## Gather Phase 3 Causal Stress Results

```bash
julia --project=. scripts/run_phase3.jl
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
