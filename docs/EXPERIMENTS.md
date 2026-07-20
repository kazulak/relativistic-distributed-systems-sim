# Standard-Raft relativistic experiments

Status: executable RQ1 baseline lane. This is an experiment interface, not a
paper claim and not an adaptation of Raft.

## Purpose and claim boundary

The `Research` module composes the package's public physics, scheduler, trace,
network, proper-clock, and Raft APIs. It asks how the existing condensed Raft
implementation behaves when direct messages cannot arrive before the
receiver's future light-cone intersection. Raft voting, log replication,
quorum, commit, and recovery rules are unchanged.

Passing a run means that the runtime Raft invariant oracle, bounded client
history checker, causal-delivery checks, and causal-trace validator all passed
for that execution. It is regression evidence, not a proof of Raft safety.
Failure to commit before a client deadline is recorded as timed-progress
censoring, not as a safety violation.

## Running the small RQ1 artifact

The runner imports only the installed package API:

```sh
julia --project=. experiments/run_rq1.jl static 3 7
julia --project=. experiments/run_rq1.jl all 3 7
```

The arguments are scenario family, cluster size (`3`, `5`, or `7`), and an
explicit non-negative seed. Families are:

| CLI name | Typed family | Intended comparison |
|---|---|---|
| `control` | `ColocatedControl` | Co-located, zero-velocity control. |
| `static` | `SeparatedStaticBaseline` | Finite-light-time stationary layout. |
| `receding` | `AsymmetricRecedingInertial` | Increasing separation and unequal inertial clock rates. |
| `accelerating` | `AcceleratingBaseline` | Non-stationary proper-time/propagation relation. |
| `stress` | `PartitionDropStress` | Static geometry plus loss, duplication, reordering, link isolation, crash, and recovery. |

For programmatic experiments:

```julia
using RelativisticDistributedSystemsSim
using RelativisticDistributedSystemsSim.Research

config = canonical_scenario(
    SeparatedStaticBaseline;
    cluster_size=5,
    rho=0.2,
    theta=(5.0, 7.0),
)
result = run_scenario(config; seed=7)
```

`rq1_scenarios` constructs the complete family set, while
`compare_standard_baselines` evaluates candidates against a co-located control
with the same explicit seed. The files under `experiments/configs/rq1/` are
human- and machine-readable declarations of the canonical families. The typed
constructors remain authoritative in this lane; a file loader is intentionally
not introduced merely to add a new root dependency.

## Timing, randomness, and causal order

- Every node follows a typed worldline and owns a `ProperTimeClock`. Raft
  election and heartbeat deadlines are local proper-time values; clock
  inversion maps them to scheduler coordinate time.
- A protocol send is a trace event. Serialization finishes no earlier than the
  directed link queue allows. The physics solver then finds the earliest null
  intersection with the receiver. Processing, jitter, duplication, and
  reordering add only non-negative delay.
- Every receive is rechecked against the logical send event's future light
  cone. Send-to-receive, timer-reset, client-reply, and retry relations are
  explicit parent edges in the append-only event DAG.
- Raft has one private seeded RNG stream per node. Transport loss, duplication,
  reordering, and jitter are stateless functions of the declared seed and
  message identity. The engine does not read the global RNG, wall clock, or
  Julia's randomized `hash`.
- Crash, restart, and link faults are absolute, exogenous scenario events.
  Link availability is sampled when a message is transmitted; a later link
  change does not retroactively cancel an already in-flight copy.

## Dimensionless configuration

`dimensionless_parameters(config)` reports:

- `rho`: characteristic one-way light time divided by heartbeat interval;
- `theta_min` and `theta_max`: election-timeout bounds divided by heartbeat;
- `chi_initial`: analytic reference-node causal quorum RTT divided by the
  minimum election timeout;
- `source_receiver_rate_ratio`: receiver-proper heartbeat inter-arrival divided
  by source-proper emission interval at measurement start;
- acceleration scale `a*`, offered-load proxy `u`, loss probability, normalized
  delay variation, and client-deadline/causal-quorum margin.

The quorum and rate descriptors are reference-node, start-of-measurement
diagnostics. They do not assert that node 1 will be elected or that one scalar
describes the entire moving execution.

## Measurement contract

`ExperimentWindow` explicitly separates startup warm-up, operation invocation,
measurement, and a post-measurement censor horizon. Workload invocation times,
retry intervals, deadlines, and operation latency are measured on the client
node's proper clock. Pending operations become `:censored`; they are never
silently removed or converted into successful commits.

Each `RunResult` contains:

- seed, stable configuration fingerprint, status, and failure reason;
- runtime safety flags and all oracle diagnostics;
- elections, maximum observed term, distinct leaders, leader changes, and the
  fraction of measurement coordinate time with exactly one running leader;
- committed reads/writes, client-proper latency samples, throughput, and
  censored operations;
- attempted protocol messages, delivered copies, modeled wire bytes, repeated
  protocol correlation identities, transport duplicates, and drops;
- per-copy queue, serialization, propagation, excess, and null-residual timing;
- direct access to the append-only `EventTrace` through `trace_records`.

The byte model is an explicit logical encoding budget plus configurable framing;
it is not a claim about Julia serialization, TCP/IP framing, radio energy, or a
particular production Raft implementation. `leader_availability` means one live
leader is observed; it is not yet the stronger reachable-majority or writable
availability metric. Client commit outcomes are the primary service evidence.

## Reproducibility and current limitations

- `config_fingerprint` is stable FNV-1a over a canonical configuration and
  sampled worldline description. It detects accidental mix-ups but is not a
  cryptographic integrity signature.
- The default workload has eight operations because the independent history
  checker is bounded. Larger histories are accepted but may be computationally
  expensive.
- The model is flat Minkowski spacetime with direct point-to-point propagation.
  It does not model gravity, relays, radio link budgets, energy, storage latency,
  or Byzantine faults.
- Deterministic pseudo-random stress traces establish reproducibility, not a
  statistical sample size. Confirmatory stochastic experiments still require
  frozen tuning/report seeds, power justification, paired analysis, and
  uncertainty intervals.
- Results remain in memory and the small CLI prints a summary. Immutable raw-run
  manifests and archival result serialization belong to the later artifact
  pipeline.
- This lane implements standard Raft only. Proper-time-aware detectors,
  redundancy, relays, and leader placement must be separate adaptations and
  must be compared on common exogenous traces.
