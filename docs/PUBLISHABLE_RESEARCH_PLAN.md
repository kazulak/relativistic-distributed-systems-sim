# Research and implementation plan: Relativistic Raft

Status: proposed redesign, 2026-07-18

Working title: **Relativistic Raft: Causal Bounds, Timed Liveness, and Cost-Aware Failure Detection**

## Executive decision

The current repository is a promising physics-kernel prototype, but it is not yet a Raft study and its existing CSVs and figures are not valid evidence for a paper. The light-time solver is worth retaining. The heartbeat harness, experiment comparison, metrics, analysis, and paper placeholders should be replaced or quarantined as legacy material.

The defensible scientific framing is not “special relativity breaks Raft safety.” Core Raft is designed so that timing affects availability, not replicated-log safety, and recent work explicitly analyzes Raft under relativistic linearizability. The paper should instead ask:

1. where causal propagation, motion, clock rates, and disruption make unmodified Raft miss a precisely defined progress SLO;
2. whether a proper-time-aware failure detector improves the accuracy–detection-delay trade-off over strong conventional baselines;
3. how much metadata, heartbeat/path redundancy, and proactive leader placement cost for each improvement; and
4. which regimes are impossible for any strict-quorum protocol, so that no adaptation is misrepresented as overcoming causality.

A publishable outcome may be positive, mixed, or negative. In particular, finding that a conventional adaptive detector performs as well as a relativistic one would still be useful if the simulator, bounds, comparison, and artifact are rigorous.

## 1. Audit of the current repository

### What is reusable

| Component | Evidence now | Decision |
|---|---|---|
| Light-cone root solver | The current test command passes 30,015 assertions, including analytic radial, transverse, causal-ordering, allocation, and 10,000 random inertial cases. | Retain the mathematical idea; refactor behind typed worldline and spacetime APIs and validate independently. |
| Minkowski interval helper | Correctly encodes the declared `(+---)` signature. | Retain, add units/scaled tolerances and Lorentz metamorphic tests. |
| Deterministic event ordering | The binary heap has an explicit sequence-number tie breaker. | Retain the concept in a generic scheduler; do not let scheduler order create dependencies between spacelike node-local events. |
| Stable RNG and CSV pipeline | Provides a starting point for repeatable runs. | Replace with explicit run manifests, independent exogenous traces, schemas, and immutable raw outputs. |

### Findings that invalidate the present results

1. **The model is not protocol-faithful Raft.** It has no `RequestVote` or vote responses, no real leader election, no `AppendEntries` acknowledgements, no logs, no client operations, no majority commit, no persistent state, and no crash/recovery. A timed-out follower enters `Candidate` forever. See `src/raft_baseline.jl`, especially the heartbeat-only path around lines 138–239.

2. **The baseline and T_VAT comparison is not controlled.** All followers initially time out at 0.150 coordinate-time units, while the first heartbeat from the fixed initial geometry arrives at 1.0. The baseline therefore moves all four followers to `Candidate` before any heartbeat can arrive. The adaptive phase ignores timeout events until its estimator has received a heartbeat (`scripts/run_phase2.jl`, around lines 244–257), giving it a different cold-start rule. Both policies must receive identical bootstrap, warm-up, timeout, and workload treatment.

3. **The “100 seeds” are pseudo-replication in Phase 0 and Phase 1.** `StableRNG(seed)` is constructed and discarded; the simulation contains no random input. Every seed repeats the same execution. Deterministic experiments should report exact results once, while stochastic experiments need genuinely independent exogenous traces.

4. **`safety_violations` is not a Raft safety metric.** It is a floating-point residual from checking whether a network delivery is null-separated. Phase 1 and Phase 2 use a much tighter one-sided threshold than Phase 0 and report many such residuals even though `results/SUMMARY.md` calls safety a pass. This should be renamed `causal_delivery_residual` and kept as a simulator validation metric. Raft safety must mean Election Safety, Leader Append-Only, Log Matching, Leader Completeness, State Machine Safety, and a client-history correctness condition.

5. **`availability` is not service availability.** It is the fraction of coordinate time in which no follower is a candidate. A healthy Raft leader and majority can continue serving while a minority follower is a candidate. Availability should be observed by clients: for example, the fraction of issued operations that commit and return within a client-proper-time deadline.

6. **Phase 3 contains no Raft execution and mislabels concurrency as a violation.** It calls a spacelike pair of writes a `causal_violation`, although spacelike events are causally unrelated rather than invalid. Its geometry makes essentially every sampled pair spacelike, its “commit” waits for all followers instead of a quorum and never models acknowledgement return paths, and its merge cost is an assumed constant plus an unrelated timing difference. This phase must be removed from the primary evidence. If eventual/CRDT degradation is later studied, it needs a separate protocol, consistency specification, and experiment.

7. **The analysis can silently mix runs.** It concatenates every timestamped file matching a glob without a configuration hash or run identity. The timeout-adaptation figure labels a theoretical expression as “measured,” uncertainty ribbons are standard deviations rather than confidence intervals, the pass/fail thresholds have no stated derivation, and several generated paper cells remain `TODO`.

8. **The solver and test harness need production hardening despite the direct test script passing.** The solver disables Julia’s garbage collector inside a library call, and one public path does not restore it with `try/finally` if solving throws. Tests include source files directly and use internal functions rather than exercising the package API; canonical `Pkg.test()` currently fails because `test/runtests.jl` is absent. Extreme scales, accelerated worldlines, invalid/superluminal inputs, units, and Lorentz covariance are not covered.

### Treatment of legacy material

Before implementation, tag the current state as `v0.1-exploratory`. Move the current phase scripts, raw CSVs, generated plots, and placeholder paper output under `legacy/v0-heartbeat-harness/`, with a short README stating that they are exploratory and unsuitable for scientific claims. Do not silently delete them or carry their numbers into the new paper.

## 2. Literature position and novelty boundary

This is an initial literature check, not a substitute for a systematic related-work review.

- The [extended Raft paper](https://web.stanford.edu/~ouster/cgi-bin/papers/raft-extended.pdf) states that network timing should not affect log safety and gives the liveness condition `broadcastTime ≪ electionTimeout ≪ MTBF`. That is the correct starting point for this project.
- [Chandra and Toueg](https://research.ibm.com/publications/unreliable-failure-detectors-for-reliable-distributed-systems) distinguish failure-detector completeness and accuracy; [Chen, Toueg, and Aguilera](https://www.microsoft.com/en-us/research/wp-content/uploads/2002/05/ieeetc02_fdqos.pdf) quantify detection speed and false-detection quality. The cost–quality study must build on these definitions rather than inventing a single ad hoc “false elections per heartbeat” score.
- [Gilbert and Golab](https://doi.org/10.1007/978-3-662-45174-8_25) define relativistic linearizability. [Jayanti, PODC 2025](https://doi.org/10.1145/3732772.3733563) relates classical, computational, and relativistic executions. Most importantly, [Aeini and Golab, 2026](https://arxiv.org/abs/2606.30419) now argue R3-linearizability specifically for a Raft replicated state machine. Therefore “we show Raft is safe under relativity” is not a novel main contribution.
- Adaptive failure detectors, including the [phi accrual detector](http://hdl.handle.net/10119/4784), are mandatory baselines. A recent preprint, [BALLAST](https://arxiv.org/abs/2512.21165), also studies learned Raft timeouts under non-stationary WAN delay. Any proposed policy must beat or clarify its relationship to simple quantile, accrual, backoff, and learning-based policies.
- [NASA’s DTN program](https://www.nasa.gov/communicating-with-missions/delay-disruption-tolerant-networking/) emphasizes store-and-forward communication, long delay, multiple paths, and disruption. The inference for this project is that using one planet-spanning Raft group needs explicit architectural justification rather than being treated as the default.

### Proposed contribution, stated conservatively

The target contribution is a reproducible, frame-invariant evaluation of **timed progress** for a protocol-faithful Raft implementation on moving worldlines, together with:

- analytical causal lower bounds for quorum commits and failure detection;
- a proper-time-aware adaptive detector whose additional information and overhead are explicit;
- a comparison against tuned conventional detectors on common traces;
- a Pareto frontier for timely availability, false suspicion, crash-detection delay, and resource cost; and
- a clear result that strict Raft remains safe but may be operationally unsuitable when a majority cannot be reached inside the required causal deadline.

These are target contributions, not claims to place in an abstract until the implementation, proof obligations, and held-out experiments pass.

## 3. Scope and non-goals

### Primary scope

- Flat Minkowski spacetime (special relativity), future-directed timelike node worldlines, and causal message delivery.
- Crash-stop initially, then crash-recovery with stable storage.
- Static 3-, 5-, and 7-node Raft membership for the primary study.
- Core Raft writes and quorum-confirmed linearizable reads; no lease optimization in the primary comparison.
- Local monotonic clocks measuring node proper time, with controlled drift/noise sensitivity experiments.
- Inertial, crossing, accelerated, and planned-contact trajectories; stochastic processing, serialization, queueing, loss, and disruption layered on the physical propagation lower bound.

### Explicit non-goals

- No claim to model general relativity, gravitational redshift, realistic radio link budgets, Byzantine faults, radiation faults, or a complete flight network.
- No claim that high-`beta` stress cases represent present-day spacecraft. Mission-inspired cases must use realistic velocities and contact schedules; high-`beta` cases are normalized theory experiments.
- No weakening of majority commit while still calling the result Raft. A CRDT, escrow, or local-write fallback changes consistency semantics and must be a separately named optional study.
- No publication claim based only on absence of observed safety failures in simulation.

### Optional high-novelty track

Raft’s lease-based read optimization relies on bounded clock behavior for safety. After the core simulator is validated, add a secondary question: **can lease safety assumptions be stated in proper-time/frame-invariant form, and does a naively configured lease admit a relativistic counterexample?** This directly targets clock-dependent behavior left outside asynchronous-Raft arguments. It should be omitted if a proof, model-checked counterexample, or clear negative result is not obtained.

## 4. Research questions and falsifiable hypotheses

### RQ1 — Safety versus timed progress

**RQ1:** Across physically admissible worldlines and causal networks, which dimensionless timing regimes cause unmodified Raft to lose timely progress, while its replicated-log safety properties remain intact?

- H1a: A protocol-faithful core will show no Raft safety-property violation; any observed violation is treated as an implementation/model defect, not a physical discovery.
- H1b: leader churn and deadline availability are explained better by causal quorum RTT/election-timeout and observed source-to-receiver rate ratios than by scalar speed `beta` alone.
- H1c: deterministic radial and transverse cases have analytically predictable transition regions that the simulator matches within predeclared numerical error.

### RQ2 — Value of proper-time information

**RQ2:** Does source proper-time and sequence metadata improve failure-detection accuracy and Raft availability over equally tuned arrival-only adaptive detectors under changing motion, source jitter, reordering, and loss?

- H2: metadata that separates source emission variation and skipped heartbeats from path/kinematic variation reduces false suspicions at a fixed crash-detection-delay budget.
- Null result: arrival-only quantile or phi-accrual estimation performs equivalently. If so, report that the relativistic metadata is unnecessary in the tested regimes.

### RQ3 — Cost–quality frontier

**RQ3:** What non-dominated trade-offs exist among timeout conservatism, metadata bytes, heartbeat rate, path redundancy, estimator computation, failure-detection delay, and client deadline availability?

- H3a: extra metadata and independent delivery paths have diminishing returns.
- H3b: proactive leader placement/transfer can lower quorum latency when future contacts are predictable, but its state-transfer/control cost makes it beneficial only in identifiable regimes.
- H3c: no single scalar policy is universally optimal; results should be a Pareto set or constrained choice table rather than a universal “best” score.

### RQ4 — Fundamental boundary

**RQ4:** Which SLOs are physically unattainable because no majority acknowledgement can return inside the client’s future causal deadline, or because a live-but-delayed leader is indistinguishable from a crashed leader at the decision event?

- H4: no timeout or redundancy policy crosses the causal-quorum lower bound. Redundancy can reduce stochastic loss and queueing tails only when it creates an earlier viable causal path.
- H4 also predicts the classic failure-detector trade-off: deciding early increases false suspicion in an indistinguishable live execution; waiting avoids that mistake but increases crash-detection delay.

## 5. Formal system model

### Spacetime and worldlines

Use coordinates only as a simulation implementation device. Let each process `i` follow a future-directed timelike worldline `x_i(τ_i)` parameterized by its proper time. With signature `(+---)`, two events have

`s² = c² Δt² - ||Δx||²`.

A direct vacuum signal first reaches a receiver at the earliest future event satisfying `s² = 0`. Serialization, propagation through media, relays, processing, storage, and queueing can only move delivery further into the causal future (`s² ≥ 0`); protocol traffic must never be spacelike.

For arbitrary motion, proper time is integrated along the worldline. A node timer is scheduled against its local monotonic clock, not against the simulator’s coordinate clock. The ideal-clock primary model uses proper time directly; drift and measurement error are explicit perturbations rather than being conflated with relativistic dilation.

### Network and faults

- Messages may be delayed, dropped, duplicated, and reordered. FIFO is a configurable transport property, not a universal correction imposed by the simulator.
- A link can have finite bandwidth, serialization queues, processing delay, stochastic loss, and contact windows.
- Relays are causal store-and-forward nodes with explicit buffer, bandwidth, and energy/message costs.
- Crash-stop, crash-recovery, and stable-storage actions are exogenous trace events. Byzantine behavior remains out of scope.

### Observable event order

Only same-process program order and send-to-receive edges create protocol happens-before relationships. The event queue may choose a coordinate order for incomparable events, but node-local transitions must be isolated so that this arbitrary choice cannot change the trace except through a later causal interaction. A Lorentz transform of a scenario should preserve the causal protocol history and invariant/local-proper-time metrics.

### Dimensionless explanatory variables

| Symbol | Definition | Purpose |
|---|---|---|
| `D_sr` | receiver proper inter-arrival interval / source proper emission interval | Observed redshift/Doppler-rate factor without assuming radial inertial motion. |
| `rho` | characteristic one-way light time / heartbeat interval | Separates distance scale from raw units. |
| `theta` | election-timeout interval / heartbeat interval | Timeout conservatism. |
| `chi` | causal quorum RTT / election timeout | Expected liveness boundary variable. |
| `a*` | proper acceleration × heartbeat interval / `c` | Motion non-stationarity. |
| `u` | offered load / bottleneck service rate | Queueing pressure. |
| `p_loss`, `CV_delay` | loss probability and non-physical delay variation | Network uncertainty. |
| `d*` | client SLO deadline / earliest causal quorum completion | Physical feasibility margin. |

Raw `beta`, initial distance, and coordinate duration remain scenario descriptors, but conclusions should be expressed through the dimensionless variables where possible.

### Operational meaning of “Raft breaks”

| Category | Definition | Interpretation |
|---|---|---|
| Raft safety failure | Any formal Raft invariant or client-history correctness violation. | A critical defect/counterexample; not expected for core Raft. |
| Timed-progress failure | No successful operation within a declared client-proper-time SLO, or no stable writable leader for a declared interval. | Expected in some regimes; the primary object of study. |
| Eventual-liveness failure | No future reachable majority under the modeled contact/fault schedule. | Protocol cannot progress while preserving strict quorum semantics. |
| Physics-engine failure | A receive event is outside the sender’s causal future or violates a validated numerical bound. | Simulator defect, never a Raft metric. |

## 6. Protocol-faithful Raft implementation

Implement the condensed Raft algorithm and cross-check it against the official [Raft TLA+ specification](https://github.com/ongardie/raft.tla).

Required persistent state:

- `currentTerm`, `votedFor`, and log entries `(term, command)`;
- durable state transitions on crash/recovery.

Required volatile state:

- role, known leader, `commitIndex`, `lastApplied`;
- per-follower `nextIndex` and `matchIndex` at leaders;
- election and heartbeat timers in local proper time.

Required messages and behavior:

- `RequestVote` request/response with log up-to-date checks;
- `AppendEntries` request/response for heartbeats and replication;
- higher-term step-down, randomized elections, split votes, retries, quorum commit, application in index order, and client responses;
- crashes, recovery, loss, duplication, reordering, and partitions;
- a simple deterministic key/value state machine and a generated client history.

Primary membership is static. Pre-vote, snapshots, membership change, and lease reads are extensions and must not silently enter the baseline.

### Correctness oracles

Check after every transition:

- Election Safety;
- Leader Append-Only;
- Log Matching;
- Leader Completeness;
- State Machine Safety;
- monotonic term/commit/application indices;
- durability rules across recovery;
- at-most-once client semantics when request IDs are enabled;
- linearizability/relativistic-linearizability of completed client histories using causal precedence, with an independent history checker where practical.

Simulation checks are regression oracles, not a proof. Add a small TLA+ model in which message delay is nondeterministic and the adaptive policy changes only timer-reset/deadline actions. Establish a trace-refinement argument: because quorum, voting, term, and log rules are unchanged, the adaptation does not add a new safety transition.

## 7. Adaptation design

### 7.1 Provisional policy: proper-time-aware accrual failure detector

Use a neutral provisional name such as **PT-FD** until novelty is established. Do not claim the current `T_VAT` formula as a general relativistic detector: its inverse-beta expression assumes a simple radial inertial relation and is unnecessary for predicting arrivals directly.

Each heartbeat variant may carry:

- term and monotonic heartbeat sequence number;
- source proper emission timestamp `τ_emit`;
- nominal next source-proper emission interval;
- optionally, an uncertainty/contact summary or signed ephemeris identifier.

At follower `j`, measure receiver-proper arrival time `τ_arrive`. Consecutive source and receiver deltas yield `D_sr`; sequence gaps identify missed heartbeats. Maintain a robust, recency-weighted predictive distribution for the next arrival rather than inferring a single radial velocity. Set a randomized election deadline from a high predictive quantile plus processing/clock uncertainty, bounded by configured minimum and maximum failure-detection budgets.

Required guardrails:

- identical cold-start and warm-up rules for every policy;
- randomization retained to avoid synchronized elections;
- stale/reordered sequence numbers cannot move a deadline backward;
- outlier and regime-change handling is specified before experiments;
- loss, leader crash, source pause, and trajectory change remain distinguishable only probabilistically;
- estimator state reset/persistence on crash is an explicit variant.

Use explicit information levels so “more redundancy” is measurable rather than rhetorical:

| Level | Increment beyond the normal Raft heartbeat | Nominal added payload before serialization | Question answered |
|---|---|---:|---|
| I0 | None | 0 B | How far can a correctly tuned standard policy go? |
| I1 | `UInt64` heartbeat sequence | 8 B | Does identifying gaps/reordering improve estimation? |
| I2 | I1 plus fixed-point/`Float64` source proper timestamp | 16 B total | Does separating source and receiver intervals help? |
| I3 | I2 plus nominal next source-proper interval | 24 B total | Does explicit source scheduling improve regime-change handling? |
| I4 | I3 plus contact/ephemeris summary | Variable and encoded explicitly | Is predictive geometry worth its bytes and assumption burden? |

These are logical payload increments, not wire-cost claims. The implementation must record actual serialized bytes, framing, retransmissions, and relay copies. If standard `AppendEntries` already exposes equivalent information in a chosen implementation, charge zero incremental bytes and treat that level as an analysis method rather than new protocol metadata.

### 7.2 Mandatory baselines and ablations

1. Standard randomized fixed timeout, correctly tuned per deployment class.
2. Conservative static timeout using a declared worst-case bound.
3. Exponential-backoff timeout.
4. Arrival-only EWMA/RTT policy.
5. Arrival-only quantile predictor.
6. Phi-accrual failure detector.
7. PT-FD with sequence only.
8. PT-FD with sequence plus source proper timestamp.
9. Geometry/contact-aware oracle, clearly labeled as an upper/reference bound rather than a deployable baseline.
10. If feasible, a learned timeout baseline comparable to current Raft timeout work, with disjoint tuning and evaluation traces.

The decisive ablation is arrival-only versus source-proper-time metadata on the same exogenous trace. Without this comparison, any benefit could be ordinary adaptive timeout behavior rather than a relativistic contribution.

### 7.3 Redundancy and proactive placement

Add these only after PT-FD is stable:

- repeat/duplicate heartbeats on independent causal paths;
- relay-assisted heartbeats with store-and-forward queues;
- compact ephemeris/contact metadata;
- proactive leadership transfer to the member predicted to minimize future quorum RTT;
- planned membership reconfiguration only as a later extension using correct joint consensus.

Redundancy is charged for messages, bytes, link occupancy, relay buffer, and an energy proxy. Proactive transfer is charged for control traffic, catch-up bytes, transfer latency, and any induced unwritable interval.

### 7.4 Causal limits to state and test

Develop two propositions before claiming an adaptation:

1. **Causal-quorum bound:** compute the earliest client-response event reachable through request delivery, leader-to-majority replication, majority acknowledgement return, and response delivery. A strict Raft write cannot finish before it.
2. **Causal failure-detection indistinguishability:** before a heartbeat or other evidence enters a detector’s past light cone, an execution where the leader crashed and an execution where it is alive but delayed may be locally indistinguishable. Early suspicion and delayed detection are therefore unavoidable alternatives under the stated model.

Prove these for the formal model or weaken them to precisely scoped lemmas. Validate the implementation against analytic inertial cases. Never present a simulated curve alone as an impossibility proof.

### 7.5 Cost–quality model

For policy parameters `pi`, report the vector

`quality(pi) = (deadline availability, false-suspicion rate, detection-delay distribution, commit-latency distribution, leader churn)`

and

`cost(pi) = (control bytes/s, messages/s, link occupancy, estimator CPU, estimator state, energy proxy)`.

Report non-dominated policies with confidence regions. Also support transparent constrained queries such as “minimum control bytes subject to ≥99.9% deadline availability and p95 crash detection ≤X.” A weighted scalar utility may be an interactive artifact feature, but not the primary scientific result because weights encode user values.

## 8. Experimental program

### Stage V — validation before research runs

| ID | Validation | Pass gate |
|---|---|---|
| V0 | Analytic radial approaching/receding, transverse, coincident, and stationary light-time cases. | Scaled residual and arrival error below predeclared tolerances across valid parameter ranges. |
| V1 | Independent high-precision root oracle, fuzz/property tests, accelerated worldlines, invalid/superluminal inputs. | Agreement with oracle; explicit errors for invalid/no-intersection cases. |
| V2 | Lorentz-transform metamorphic tests. | Same causal graph, protocol decisions, event counts, and invariant/proper-time metrics after transformation. |
| V3 | Classical Raft limit at `beta=0` and increasing `c`. | Expected elections, commits, partitions, crashes, and recoveries; all Raft invariants hold. |
| V4 | Trace/differential comparison with a reference Raft state machine such as `etcd/raft`, or a second independent implementation. | Equivalent externally visible decisions for a corpus of small deterministic traces. |
| V5 | TLA+ small-state exploration. | No checked safety invariant violation for modeled timers, loss, reordering, crash, and adaptation actions. |

No paper-scale experiment begins until V0–V4 pass; V5 must pass before a safety-preservation claim.

### Stage E1 — deterministic characterization for RQ1

- Stationary control, effectively instantaneous-network limit, and finite-`c` stationary layouts.
- Radial approach, radial recession, transverse motion, crossing/passing, and symmetric moving clusters.
- Sweep dimensionless `rho`, `theta`, `chi`, and `D_sr`; do not vary `beta` while silently changing every other factor.
- Derive heartbeat arrival intervals and causal quorum lower bounds analytically where possible.
- Use no fake seeds. Report exact curves, boundary error, and numerical sensitivity.

### Stage E2 — stochastic and disrupted baseline

- Processing/serialization jitter, long-tail queueing, random loss, correlated bursts, temporary partitions, planned contact windows, and crash/recovery.
- Cluster sizes 3, 5, and 7; read/write workload rates below and near saturation.
- Inertial and changing trajectories, including unseen trajectory changes in the test set.
- Separate normalized high-`beta` stress scenarios from mission-inspired realistic-velocity/contact scenarios.

### Stage E3 — adaptation comparison for RQ2

- Run every policy on the same pre-generated exogenous trace (common random numbers).
- Tune policies on disjoint tuning traces and freeze parameters before report traces.
- Use identical bootstrap/warm-up, heartbeat budget, faults, workload, and eligibility rules.
- Compare full distributions and paired effects, not only means at `beta=0.9`.
- Include metadata and estimator ablations, cold-start, loss gaps, reordered heartbeats, abrupt motion changes, and estimator reset after crash.

### Stage E4 — Pareto study for RQ3

- Vary timeout risk threshold, heartbeat interval, metadata level, duplicate count/path diversity, and proactive-transfer horizon.
- Enumerate a bounded interpretable grid first; use multi-objective optimization only if the grid is demonstrably insufficient.
- Produce Pareto plots, an SLO choice table, and marginal-gain curves for each added byte/message/path.

### Stage E5 — impossibility and graceful refusal for RQ4

- Deadlines below, at, and above the computed causal-quorum bound.
- A minority reachable, a majority reachable only after a planned contact, and no majority reachable within the mission horizon.
- Live-but-delayed versus crash executions sharing the detector’s same local history up to the decision point.
- Expected safe behavior below the bound is refusal/blocking, not a fabricated successful commit.

### Stage E6 — external validation

Replay generated delay/loss/contact traces through a production-grade Raft state machine or scaled network emulator. This does not reproduce relativistic motion physically; it checks that protocol-level trends are not artifacts of the Julia Raft implementation. Compare a small preregistered subset, not whichever scenarios look favorable.

### RQ-to-evidence map

| Planned statement | Required evidence | Acceptable adverse/null outcome |
|---|---|---|
| Core Raft does not acquire a new timing-dependent safety transition in this model. | Existing theory, a scoped trace-refinement argument/TLA+ exploration, runtime invariants, and client-history checks. | A genuine counterexample becomes the primary result; an implementation bug is fixed and all affected runs are invalidated. |
| Timed progress has a predictable causal boundary. | Analytic bounds plus deterministic boundary experiments and stochastic sensitivity analysis. | The proposed dimensionless variables predict poorly; report the mismatch and revise the model before adaptation experiments. |
| Source proper-time metadata improves failure detection. | Held-out paired comparison against arrival-only quantile/accrual and other tuned baselines, with metadata ablations and effect intervals. | No material improvement: recommend the simpler conventional detector. |
| Redundancy/placement improves quality at a measurable cost. | Full resource accounting, common traces, Pareto and marginal-gain analysis. | All variants are dominated: recommend static architecture or local consensus domains. |
| No strict-quorum policy beats the causal lower bound. | Precisely scoped proposition/proof and below/at/above-bound validation scenarios. | A simulated violation indicates an incorrect bound or simulator and blocks publication until resolved. |

### Planned results presentation

- Figure 1: spacetime/worldline diagram mapped to the causal event DAG and local proper-time timers.
- Figure 2: solver/reference error and Lorentz-metamorphic validation, separated from protocol results.
- Figure 3: deterministic Raft phase map over `chi` and `D_sr`, with the analytic transition overlaid.
- Figure 4: client deadline availability, leader churn, and commit-latency distributions for unmodified Raft across representative trajectories.
- Figure 5: false-suspicion versus crash-detection-delay curves for all detector baselines and PT-FD ablations.
- Figure 6: cost–quality Pareto frontier with metadata bytes, heartbeat/path redundancy, and placement policies identified.
- Figure 7: below/at/above causal-quorum-bound behavior, showing safe refusal rather than a “successful” impossible commit.
- Main tables: model/configuration assumptions; validation gates; paired confirmatory effect sizes with confidence intervals; Pareto choice table for several SLOs; limitations and unsupported regimes.

The results prose should answer each RQ in the same order: observation, quantitative effect and uncertainty, mechanism, robustness/ablation, then limitation. It should distinguish prediction from measurement and avoid converting a failure to meet an SLO into a violation of the Raft algorithm.

## 9. Metrics and statistical protocol

### Primary outcomes

- **Deadline availability:** fraction of client operations returning a correct result within deadline `D`, measured in client proper time.
- **Unwritable-time fraction:** intervals in which no leader can commit with a reachable majority, reported separately from client load effects.
- **False-suspicion/election incidence:** suspicions or terms started while the current leader is alive and a policy-defined timely causal heartbeat path exists.
- **Crash-detection delay:** detector decision proper time minus crash event, for nodes that can eventually receive evidence/progress.
- **Commit latency:** invocation-to-response proper time, including p50/p95/p99 and survival/censoring for unfinished operations.
- **Leader/term churn and split-vote rate.**
- **Control and replication cost:** messages, bytes, link occupancy, state, CPU, and energy proxy.

### Safety and validity outcomes

- Every Raft invariant listed in Section 6.
- Client-history checker outcome.
- Maximum scaled causal-delivery residual and high-precision solver error.
- Lorentz metamorphic equivalence outcome.

### Statistical rules

- Deterministic cases are not replicated merely to create error bars.
- For stochastic cases, the run/trace is the experimental unit. Heartbeats within a trace are not independent replicates.
- Use paired comparisons because all policies consume the same exogenous trace.
- Run a pilot to estimate variance and choose replication count from a stated minimum practically important effect and target power; do not default to 100 without justification.
- Use 95% confidence intervals, paired effect sizes, and bootstrap/block-bootstrap methods appropriate to autocorrelated traces. Use suitable interval models for proportions and bootstrap intervals for tail quantiles.
- Separate warm-up and measurement windows, or initialize all policies from the same valid steady state. Report censoring and failures to reach steady state.
- Correct or control multiplicity for confirmatory comparisons; clearly label exploratory sweeps.
- Publish all preregistered outcomes, including null and adverse results. Keep tuning and report seeds/configurations disjoint.

## 10. Proposed repository structure

```text
relativistic-distributed-systems-sim/
  README.md
  LICENSE
  CITATION.cff
  Project.toml
  Manifest.toml
  docs/
    PUBLISHABLE_RESEARCH_PLAN.md
    MODEL.md
    PROTOCOL.md
    EXPERIMENT_PROTOCOL.md
    CLAIMS_AND_LIMITATIONS.md
  src/
    RelativisticDistributedSystemsSim.jl
    Physics/
      Spacetime.jl
      Worldlines.jl
      ProperTime.jl
      LightCone.jl
      Lorentz.jl
    Simulation/
      Events.jl
      Scheduler.jl
      Network.jl
      LocalClocks.jl
      Faults.jl
      Traces.jl
    Protocols/Raft/
      Types.jl
      Messages.jl
      Transitions.jl
      Client.jl
      Invariants.jl
    Adaptations/
      FixedTimeout.jl
      Accrual.jl
      ProperTimeFD.jl
      Redundancy.jl
      LeaderPlacement.jl
    Scenarios/
      Trajectories.jl
      Contacts.jl
      Workloads.jl
    Metrics/
      Safety.jl
      Liveness.jl
      Cost.jl
  test/
    runtests.jl
    physics/
    raft/
    properties/
    integration/
  formal/
    RelativisticRaft.tla
    TimerAdaptation.tla
    models/
  experiments/
    run.jl
    schema.json
    configs/
      validation/
      rq1/
      rq2/
      rq3/
      rq4/
  analysis/
    reproduce.jl
    figures.jl
    tables.jl
  artifact/
    reproduce_small.sh
    reproduce_full.sh
    Dockerfile
  paper/
    main.tex
    sections/
    references.bib
    generated/
  data/
    README.md
    raw/        # ignored or external artifact, immutable
    derived/    # reproducibly generated
  legacy/
    v0-heartbeat-harness/
```

### Architectural rules

- Physics knows nothing about Raft; Raft knows only local clocks and a transport interface.
- The scheduler coordinate frame is never exposed to protocol policy code.
- Protocol transitions are deterministic given node state, local clock observation, message, and RNG stream.
- Scenario configuration, algorithm configuration, and analysis configuration are separate typed schemas.
- Every run stores config hash, git commit, Julia version, dependency manifest hash, seed/trace ID, start/end status, and output schema version.
- Raw event logs are append-only. Summaries, figures, tables, and paper macros are regenerated from named run manifests.
- `Pkg.test()` is the canonical test entry point; tests import the package rather than include source internals.

## 11. Implementation milestones and gates

Estimates are person-weeks for one experienced researcher/developer and are planning ranges, not deadlines.

| Milestone | Main work | Acceptance gate | Estimate |
|---|---|---|---|
| M0 — freeze and specify | Tag/quarantine legacy data; write model, terminology, claim register, scenario schema, and systematic-review protocol. | No current plot is presented as evidence; RQs and primary metrics are frozen for the pilot. | 0.5–1 |
| M1 — physics core | Typed worldlines/proper time, causal network delivery, scaled tolerances, Lorentz transforms, remove GC manipulation. | V0–V2 pass, including independent high-precision and metamorphic tests. | 1–2 |
| M2 — real Raft | Full elections, logs, quorum commits, clients, crashes/recovery, invariants. | V3–V4 pass on deterministic trace corpus; `Pkg.test()` is green. | 3–5 |
| M3 — formal and artifact skeleton | TLA+ timer/transport extension, run manifests, config validation, raw/derived split, CI and small reproduction. | V5 passes in scoped models; one command regenerates a small validation report from a clean checkout. | 1–2 |
| M4 — RQ1 baseline | Analytic timing envelope and deterministic/stochastic baseline characterization. | Boundary predictions and simulations agree within preregistered tolerance; fair baseline behavior is reviewed. | 1–2 |
| M5 — RQ2 adaptation | Implement conventional detectors, PT-FD, guardrails, tuning/report split, ablations. | Paired pilot complete with no safety regression and frozen confirmatory design. | 2–4 |
| M6 — RQ3/RQ4 | Redundancy/placement variants, cost accounting, Pareto analysis, causal-bound scenarios. | Non-dominated set and impossibility tests reproduce from manifests; below-bound runs fail safely. | 1–3 |
| M7 — external validation and paper | Reference-engine trace replay, full runs, statistical analysis, paper, artifact documentation. | All paper numbers are generated; claims table maps every claim to evidence; independent clean-machine reproduction succeeds. | 2–4 |

Expected total: approximately 12–23 person-weeks, with the optional lease-safety track additional.

### Decision gates

- If M2 cannot produce a protocol-faithful, differentially checked Raft core, stop; further plots would not answer the RQs.
- If PT-FD does not beat well-tuned arrival-only baselines on held-out traces, report the null result and focus the contribution on causal bounds, simulator validation, and deployment guidance. Do not retune on the report set.
- If the only gains occur against an intentionally bad 150 ms timeout, the adaptation claim fails.
- If mission-inspired cases show negligible kinematic benefit, say so and separate “finite propagation/contact disruption” from “relativistic time dilation.”
- Pursue the optional lease track only after core milestones and only with a formal property/counterexample.

## 12. Paper structure

1. **Introduction:** practical and theoretical motivation; the safety/liveness distinction; contributions stated without “Raft breaks” rhetoric.
2. **Background and related work:** Raft timing, failure-detector QoS, adaptive detectors, relativistic executions/linearizability, DTN/contact planning, and recent adaptive Raft timeout work.
3. **Model and definitions:** worldlines, proper clocks, causal transport, faults, workload, safety, deadline availability, and cost.
4. **Causal bounds:** quorum-completion and failure-detection indistinguishability propositions with assumptions and proof sketches/full proofs.
5. **Simulator and validation:** architecture, reference checks, Lorentz metamorphic tests, Raft differential/formal checks, and numerical error.
6. **How unmodified Raft behaves:** deterministic envelope followed by stochastic/disrupted cases.
7. **PT-FD and optional placement/redundancy:** algorithm, information assumptions, overhead, guardrails, and safety refinement.
8. **Evaluation:** preregistered RQs, baselines, experimental design, effect sizes, uncertainty, ablations, robustness, and Pareto frontier.
9. **Limitations and threats to validity:** model, implementation, statistical, construct, and external-validity limitations.
10. **Conclusion:** what is safe, what is timely, what adaptation buys, what remains physically impossible, and when not to use one wide-area Raft group.

## 13. Required limitations and claim discipline

- A discrete-event simulator demonstrates behavior under its assumptions; it does not prove that deployed systems behave identically.
- Passing simulations cannot prove Raft safety. Formal arguments/model checking and existing theory support safety; the runtime oracle detects implementation regressions.
- Flat spacetime excludes gravitational dilation and curved null geodesics. Call the model special-relativistic, not a complete relativistic-universe model.
- High velocities may be useful stress tests but have weak near-term external validity. Report normalized and mission-inspired results separately.
- Finite signal propagation is already part of ordinary distributed systems. Novelty must come from frame-invariant modeling, changing proper-time/trajectory effects, causal bounds, or demonstrably useful extra information—not merely replacing a network delay with `distance/c`.
- Ephemerides and contact plans may be unavailable, stale, uncertain, or security-sensitive. Geometry-aware policies must state this assumption and test error.
- Redundant paths can share failures; “independent” is an experimental assumption that requires sensitivity analysis.
- Client deadlines and cost weights are value choices. Show multiple SLOs and Pareto results rather than choosing one favorable operating point.
- A single Raft group may be architecturally inappropriate across long planned disconnections. Local consensus domains plus DTN or application-level reconciliation may be the honest recommendation.

## 14. Publishable-readiness checklist

The project is ready to submit as a research artifact only when all are true:

- RQs, hypotheses, primary metrics, exclusions, and analysis are time-stamped before confirmatory runs.
- Core Raft is protocol-faithful and passes invariant, history, differential, and scoped formal checks.
- The physics engine passes analytic, independent-oracle, scale, and Lorentz metamorphic validation.
- Baselines are strong, fairly tuned, equally initialized, and run on shared held-out traces.
- Deterministic and stochastic evidence are analyzed appropriately; uncertainty and effect sizes are reported.
- Every figure/table is generated from a run manifest and can be rebuilt from a clean checkout.
- The paper distinguishes numerical causality checks, Raft safety, eventual liveness, and deadline availability.
- Null/adverse results and all preregistered outcomes are included.
- Limitations include special-relativity scope, idealizations, actual mission relevance, and simulator/reference-engine disagreement if any.
- A separate reviewer can run the small artifact, understand the repository layout, trace each claim to raw data/configuration, and reproduce the reported summary.

## 15. First implementation backlog

Execute in this order:

1. Tag the current exploratory state and add the legacy warning.
2. Write `MODEL.md`, including units, causal ordering, proper clocks, network delays, and invalid inputs.
3. Refactor the light-time solver; remove GC state manipulation; add high-precision, scale, and Lorentz tests.
4. Introduce `test/runtests.jl`, package-level tests, CI, formatting, and explicit test dependencies/targets.
5. Implement generic scheduler, node isolation, typed messages, local proper-time timers, and trace logging.
6. Implement full static-membership Raft and its transition-by-transition invariants.
7. Build deterministic reference traces and differential validation.
8. Add config/run manifests and a one-command small reproduction before adding new policies.
9. Complete deterministic RQ1 analysis and causal-quorum-bound code.
10. Implement conventional adaptive baselines before PT-FD.
11. Implement PT-FD and its sequence/source-time ablations.
12. Pilot, power/design the confirmatory runs, freeze the analysis, then run RQ2–RQ4.
13. Add redundancy/leader placement and optional lease work only after the core evidence is stable.
