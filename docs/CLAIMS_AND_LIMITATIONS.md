# Claims register and limitations

Status: pre-evidence claim discipline for the redesigned project. “Required”
means required before the wording may appear as a result; it does not mean that
the repository currently contains that evidence.

## 1. Claim states

- **Target:** a falsifiable statement the study is designed to evaluate.
- **Eligible:** all preregistered evidence gates passed and the result supports
  the stated scope.
- **Null/adverse:** the evidence does not support the target; report the null or
  adverse result without post-hoc scope changes.
- **Prohibited:** contradicted by the model, unsupported by available evidence,
  or materially misleading.

At present, every substantive research claim below is a target or prohibited
legacy claim. Creating a simulator, model, test, plot, or table does not by
itself promote a target to eligible.

## 2. Intended claim-to-evidence map

| ID | Carefully scoped target statement | Evidence required before use | Acceptable null/adverse result | Current state |
|---|---|---|---|---|
| C1 | In the specified static-membership, non-Byzantine core, allowing arbitrary causal message timing and timer adaptation adds no new voting/log/quorum safety transition. | Published Raft safety basis; reviewed transition mapping in `PROTOCOL.md`; completed bounded TLC checks for all checked configurations (V5 pass); runtime invariants; independent trace/differential checks (V4 pass). | A genuine counterexample becomes the central result. A model/implementation/checker defect invalidates affected runs and is repaired. | Evidence complete for checked configurations; see `VALIDATION_GATES.md`. |
| C2 | Unmodified Raft retains the checked safety properties in all completed study traces but misses specified proper-time progress SLOs in identified regimes. | Protocol-faithful Raft; causal/clock validation; client operations and majority commits; invariant/history checks; declared scenario bounds and SLO; complete trace accounting via `experiments/run_rq1.jl` and `experiments/analyze_rq1.jl`. | Any safety counterexample blocks the study. No timed-progress loss is a valid negative result for tested regimes. | **Eligible**; validated across 208 confirmatory runs (48 E1 deterministic + 160 E2 stochastic runs in `results/rq1/confirmatory_e1` and `results/rq1/confirmatory_e2`) with 100% safety preservation and monotonic progress loss as $\chi \ge 0.50$. |
| C3 | Analytic causal quorum completion bounds predict an unattainable region for strict-quorum writes under stated worldlines, contacts, processing assumptions, and client events. | Precisely scoped proposition/proof in `docs/CAUSAL_QUORUM_BOUND.md`; independent calculation; analytic collinear inertial cases; zero simulation completion before the bound verified by `test/research/causal_bounds.jl` and `verify_causal_quorum_bounds`. | Bound is too loose or wrong; revise before adaptation analysis. | **Eligible**; Proposition 1 formally derived in `docs/CAUSAL_QUORUM_BOUND.md`, oracle verified in unit tests and audited over all 208 confirmatory write traces (zero sub-causal commits, min margin $\ge 0.0$). |
| C4 | Proper-time/source metadata improves the false-suspicion versus crash-detection-delay trade-off over equally tuned arrival-only detectors in specified non-stationary regimes. | Shared exogenous traces; disjoint tuning/report sets; identical bootstrap and budgets; quantile, phi-accrual, EWMA/backoff and fixed baselines; I0–I3 ablation; paired effect intervals and preregistered practical threshold. | No material benefit: recommend the simpler arrival-only detector. | Target; not established. |
| C5 | A stated subset of metadata, path redundancy, or proactive placement variants is non-dominated for declared quality and cost metrics. | Actual serialized bytes and copies; link occupancy, CPU/state and energy proxy; common traces; confidence regions; complete Pareto analysis; path-correlation and prediction-error sensitivity. | All variants are dominated: recommend the simpler policy/architecture. | Target; not established. |
| C6 | No evaluated detector crosses the proved causal bound; below it, safe behavior is refusal or blocking. | C3 evidence plus preregistered RQ4 schedules and trace-level commit causality audit. | An apparent crossing is a bound or simulator defect and blocks publication until resolved. | Target; not established. |
| C7 | A conventional detector is preferable in regimes where proper-time metadata has no practically important held-out gain. | Same fair comparison as C4, including uncertainty and cost. | Metadata is beneficial in a clearly bounded regime; report that regime rather than a universal winner. | Target and required decision rule. |
| C8 | One wide-area Raft group is operationally unsuitable when no majority is reachable within the application horizon, despite preserving safety. | Explicit contact/fault schedule, client semantics, safe blocking behavior, and comparison to declared SLO—not merely a timeout count. | Majority becomes reachable and service recovers; report conditional behavior. | Target deployment guidance; not established. |

No abstract or conclusion may use an unqualified version of these statements.
Each final claim must name the protocol variant, fault model, cluster sizes,
scenario family, SLO/metric, and evidence boundary to which it applies.

## 3. Legacy claim rejection

The original heartbeat harness is exploratory material, not baseline evidence.
Its outputs must not be pooled with the redesigned study.

| Legacy label or inference | Why it is invalid | Required replacement |
|---|---|---|
| “The simulation implements Raft.” | The legacy path has a fixed leader and heartbeats but no vote exchange, elected leaders, logs, append acknowledgements, client operations, majority commits, durable recovery, or state-machine application. | Protocol implementation conforming to `PROTOCOL.md`, deterministic reference traces, invariant checks, and differential validation. |
| `safety_violations` measures Raft safety. | The field counts numerical light-cone residuals under inconsistent thresholds. It observes no Raft invariant. | Rename to a scaled causal-delivery/numerical residual and report it as physics validation. Measure Raft safety with named invariants and client-history checking. |
| `availability` measures service availability. | It measures time with no follower in candidate role. A healthy leader and majority can serve while a minority follower campaigns. | Client-observed correct responses within a client proper-time deadline, plus unwritable-time and censoring. |
| “100 seeds” provide 100 independent replications. | Phase 0/1 have no stochastic input; their RNG objects do not affect the execution. Repeated deterministic runs are pseudo-replication. | Run deterministic cases once; make stochastic traces genuinely independent and use the trace as the experimental unit. |
| The baseline and T_VAT comparison is fair. | Followers time out before the first physical heartbeat in the baseline, while the adaptive path ignores timeout events until initialized. Cold-start rules differ. | Identical bootstrap, warm-up, workload, fault trace, heartbeat budget, and eligibility; tune on disjoint traces. |
| T_VAT is a general relativistic detector or is superior. | Its inverse-Doppler/radial-beta formula assumes a simple radial inertial relation, and no controlled comparison isolates metadata from ordinary adaptation. | Neutral PT-FD name, direct predictive arrival model, guardrails, strong arrival-only baselines, and held-out I0–I3 ablations. |
| Spacelike writes are a causal violation. | Spacelike events are causally incomparable, not invalid. The legacy Phase 3 executes no Raft and waits for all followers rather than a quorum. | If studied, define a separately named degraded-consistency protocol, consistency specification, and client-history oracle. |
| Absence of observed violations proves Raft safety. | Finite simulation cannot prove a universal safety property. | Existing theory, scoped refinement reasoning, bounded model checking, independent implementation checks, and carefully qualified wording. |
| Finite propagation alone is a novel relativistic result. | Ordinary distributed systems already admit propagation delay. | Demonstrate value from frame-invariant modeling, proper-time/trajectory variation, causal bounds, or useful information beyond a tuned conventional detector. |
| A theoretical timeout expression is measured data. | Prediction and observation are different evidence types. | Label analytic curves as predictions and measured traces as observations; preregister numerical agreement tolerance. |

Existing CSVs, generated plots, and placeholder paper tables may document
project history only. They may not supply effect sizes, uncertainty, pass/fail
claims, or priors for confirmatory analysis unless a future protocol explicitly
identifies and justifies such use.

## 4. Evidence gates and stopping rules

### Validation gate

Before paper-scale protocol runs:

- the physics engine passes analytic, high-precision, scale, invalid-input, and
  Lorentz-metamorphic validation;
- canonical package tests pass through the package API;
- static-membership Raft passes deterministic election/commit/fault traces and
  independent differential checks;
- runtime invariants and client-history checks are active; and
- scoped TLC configurations, configured action properties, the focused
  commit-cap regression, and the non-vacuity coverage trace complete without a
  violation.

A partial TLC search, timed-out test job, skipped differential corpus, or
unchecked physics residual is reported as incomplete, not a pass. A safety
invariant that is never exercised by an election/commit/application witness is
not treated as adequate publication evidence merely because it held vacuously.

Status note, 2026-08-25: every gate above now has recorded evidence; see
[VALIDATION_GATES.md](VALIDATION_GATES.md) for per-gate pointers, the V2
defect found and repaired during gate work, and the scope limits of the
metamorphic and differential evidence. The claim register rows in Section 2
remain "Target; not established" until their full evidence columns are met;
gate completion alone does not promote them.

### Adaptation gate

Implement and tune fixed, worst-case, backoff, EWMA/quantile, and phi-accrual
baselines before evaluating PT-FD. Freeze bootstrap, tuning, exclusions,
practical-effect threshold, and report traces before confirmatory comparison.
If PT-FD does not materially beat tuned arrival-only policies, C4 is rejected
and C7 becomes the actionable result.

### Causal-bound gate

Do not call a simulated curve an impossibility proof. State assumptions and
prove or rigorously derive the client-to-leader, leader-to-quorum,
acknowledgement-return, and client-response causal chain. Any apparent
below-bound commit invalidates the bound or simulator until resolved.

### Publication stopping rules

- A safety counterexample stops all affected performance experiments.
- A failure to reproduce a deterministic reference trace stops stochastic
  runs.
- A Lorentz-metamorphic mismatch stops frame-invariance claims.
- Mixing tuning and report traces invalidates the confirmatory comparison.
- Missing raw manifest/config/version information makes a run ineligible for a
  paper result.
- Resource exhaustion or incomplete exploration is not transformed into a
  positive finding.

## 5. Required statistical discipline

- Deterministic cases receive exact results and numerical sensitivity, not fake
  confidence intervals.
- The stochastic trace/run is the experimental unit; heartbeats and operations
  within one trace are not independent replicates.
- Policies consume the same pre-generated exogenous traces so primary effects
  are paired.
- Replication count follows a stated pilot, minimum practically important
  effect, variance estimate, power target, and censoring plan.
- Report effect sizes and 95% confidence intervals. Use methods appropriate to
  autocorrelation and tail quantiles; identify exploratory multiplicity.
- Publish every preregistered outcome, including null, dominated, and adverse
  results.
- Report operation non-completion as censoring/failure according to the frozen
  estimand, not by silently dropping observations.

## 6. Limitations that must accompany results

### Formal and protocol limits

- The TLA+ checks are exhaustive only for the configured finite state spaces;
  they are not a proof for arbitrary cluster size, terms, log length, or values.
- The checked models bound concurrent distinct logical message records using
  `MaxInFlight`; conclusions are scoped to that bound even though retained
  records still model arbitrary duplicate receipt and delay.
- The formal model covers static membership, one-entry replication batches,
  abstract commands, clean crashes, and a durable committed/applied-prefix
  abstraction. It excludes snapshots, joint consensus, pre-vote, leases,
  read-index, client deduplication, torn storage writes, and Byzantine faults.
- Timer nondeterminism is useful for safety preservation but says nothing about
  availability, detector QoS, or cost.
- The timer projection formulas and general safety-preservation implication are
  named obligations, not machine-proved theorems. TLC checks bounded state and
  action properties only for the supplied constants.
- Simulation invariant checks can find implementation defects; passing traces
  cannot prove the absence of defects or universal Raft safety.
- Linearizability or relativistic-linearizability requires an independent
  completed client-history specification/checker. State-machine agreement
  alone is insufficient.

### Physical-model limits

- The primary model is flat Minkowski spacetime. It omits gravity,
  gravitational redshift, curved null geodesics, and general-relativistic
  navigation effects.
- Worldlines, proper clocks, acceleration, contact schedules, relays, media,
  processing, serialization, queueing, and loss are only as realistic as their
  configured models and validation data.
- High-`beta` scenarios are normalized theory stress tests, not claims about
  current spacecraft. Mission-inspired velocities/contact cases must be shown
  separately.
- Finite signal propagation and long disconnection are not uniquely
  relativistic phenomena. Results must identify which mechanism produces an
  effect.
- Floating-point causal residuals are numerical diagnostics. Tolerance choice,
  scale, solver convergence, and high-precision comparison must be reported.

### Detector/adaptation limits

- Source timestamps and intervals require meaningful source clocks and trusted
  metadata. Clock noise, drift, reset, replay, and authentication are explicit
  assumptions or sensitivity factors.
- Sequence gaps do not uniquely identify loss, source pause, congestion,
  crash, or disruption. Failure detection remains probabilistic.
- Ephemerides/contact plans may be stale, uncertain, unavailable, or
  security-sensitive. Geometry-aware results are conditional on their error
  model.
- “Independent” redundant paths may share relays, queues, power systems, or
  disruption. Correlated-failure sensitivity is mandatory.
- Redundancy cannot create an earlier path when all paths are outside the
  receiver's causal past; it can only exploit an existing earlier route or
  reduce stochastic loss/queueing tails.
- Proactive leader placement introduces catch-up/control traffic and an
  unwritable interval. Benefits cannot be reported without these costs.

### Experimental and external-validity limits

- A discrete-event simulator demonstrates behavior under chosen assumptions;
  deployed hardware, radios, operating systems, storage, and workloads may
  disagree.
- A production Raft trace replay validates protocol-level trends under a scaled
  delay trace; it does not reproduce relativistic motion or proper clocks.
- Three-, five-, and seven-node static clusters do not justify extrapolation to
  arbitrary topologies or dynamic membership.
- Client deadlines, cost weights, energy proxies, and acceptable false
  suspicion are stakeholder choices. Report multiple SLOs and Pareto sets,
  rather than selecting one favorable scalar score.
- One interplanetary/wide-area Raft group may be the wrong architecture. Local
  consensus domains plus delay-tolerant transport or application reconciliation
  must remain an explicit alternative recommendation.

## 7. Wording rules for the paper and artifact

Use “within the checked formal model,” “in the evaluated traces,” “under the
stated worldlines/contact/fault model,” and “missed the declared progress SLO.”
Do not use “proved safe by simulation,” “relativity breaks Raft,” “causal
violation” for concurrency, or “optimal” without a proved domain and objective.

Results prose should answer each RQ in this order: observation; quantitative
effect and uncertainty; mechanism; robustness/ablation; limitation. Predictions
and measurements are labeled separately. A negative result receives the same
visibility as a positive result.

Before submission, every abstract/result/conclusion sentence must link to a row
in this register, a frozen analysis output, raw run manifests, and the relevant
validation gate. Unsupported wording is removed rather than softened with an
unmeasured qualifier.
