# Model and numerical contract

Status: implementation model for the M0/M1 physics core, 2026-07-18.

This document fixes the assumptions and validity boundaries used by the
simulator. It is an implementation contract, not a claim that the model is a
complete description of an operational space network. Changes that affect a
research result must be recorded in the run configuration and the paper's
claim/limitations register.

## 1. Scope

The primary model is special relativity in flat Minkowski spacetime. Processes
follow prescribed future-directed timelike worldlines, their ideal local clocks
measure proper time, and direct vacuum signals follow future-directed null
paths. Network and protocol delays can move a receive event later, but never
outside the send event's future light cone.

The model does not include spacetime curvature, gravitational clock shifts,
curved null geodesics, orbital dynamics, radio link budgets, radiation faults,
or Byzantine behavior. Accelerated trajectories are kinematic inputs rather
than the output of a force or fuel model. High fractions of the signal speed are
normalized stress cases unless a scenario explicitly supplies a defensible
mission interpretation.

## 2. Coordinates, units, and signature

Every `MinkowskiSpacetime(c)` chooses one inertial coordinate frame and a
strictly positive finite signal speed `c`. The coordinates use a single
internally consistent unit system:

- coordinate time `t` and proper time `τ` use the same time unit;
- position uses one distance unit on all three axes;
- velocity and `c` use distance/time;
- proper acceleration uses distance/time².

The library does not attach a unit package or assume SI. For example, both
`c = 1` with normalized coordinates and `c = 299_792_458` with metres and
seconds are valid. A scenario must not mix metres, kilometres, seconds, and
milliseconds without explicit conversion.

The metric signature is `(+---)`. For events `A = (t_A, x_A)` and
`B = (t_B, x_B)`, the squared interval is

```text
s²(A, B) = c² (t_B - t_A)² - ||x_B - x_A||².
```

The sign has the following meaning:

- `s² > 0`: timelike separation;
- `s² = 0`: null separation;
- `s² < 0`: spacelike separation.

The sign alone does not identify the future. A future-causal relationship also
requires `t_B >= t_A` in any proper orthochronous inertial frame.

`SpacetimeEvent` rejects non-finite coordinates. `MinkowskiSpacetime` rejects
zero, negative, infinite, and NaN `c` values.

## 3. Worldlines and local clocks

A node worldline is a map from coordinate time to position. Its instantaneous
coordinate velocity must satisfy

```text
||v(t)|| < c
```

throughout the modeled domain. Equality is lightlike, not a valid node
trajectory. `InertialWorldline` validates this condition at construction.
`ParametricWorldline` validates its returned position and velocity whenever it
is evaluated; no finite sampling procedure could prove an arbitrary user
function timelike over a continuous interval. Its constructor therefore
requires an explicit `consistency=:assumed` or `consistency=:audited`
declaration. The audited form compares finite-difference position derivatives
with the supplied velocity at caller-selected times. This is a useful scenario
check, not a continuous proof. A malformed trajectory raises
`InvalidWorldlineError` rather than being silently clipped.

The physics core currently provides:

- `InertialWorldline`: constant coordinate velocity;
- `UniformlyAcceleratedWorldline`: one-dimensional hyperbolic motion with
  constant proper-acceleration magnitude, included principally as a non-linear
  validation trajectory;
- `ParametricWorldline`: a user-supplied position/velocity pair with an optional
  finite coordinate-time domain.

For an ideal clock on a timelike worldline,

```text
dτ/dt = sqrt(1 - ||v(t)||²/c²).
```

`proper_time_between` uses closed forms for inertial and uniform-proper-
acceleration trajectories, evaluating cancellation-prone accelerated
differences in extended precision. A general parametric worldline uses adaptive
15-point Gauss--Kronrod quadrature with an explicit evaluation budget and error
estimate. Known discontinuities, contact transitions, or motion-regime changes
must be passed as `breakpoints`; the integrand is assumed smooth between them.
For `coordinate_time_after_proper_time`, callers may pass the complete future
breakpoint schedule even though the endpoint is initially unknown. Each trial
integration uses only schedule entries strictly inside its current candidate
interval. Schedule entries must be finite and strictly later than the initial
time.
Budget or floating-point resolution exhaustion raises
`QuadratureConvergenceError` rather than returning the last refinement.
`ProperTime` is a lightweight boundary type for local clock intervals; it does
not add physical units. Clock drift, measurement noise, oscillator failure, and
timestamp quantization must be modeled explicitly above this ideal layer.

Protocol timer policies must consume a local-clock observation or proper-time
deadline. They must not inspect the scheduler's coordinate time.

## 4. Direct signal delivery

For a signal emitted at event `A` and receiver worldline `x_B(t)`, direct vacuum
delivery is the earliest future solution of

```text
||x_B(t_B) - x_A|| = c (t_B - t_A),    t_B >= t_A.
```

For a strictly timelike receiver the left-minus-right function is strictly
decreasing wherever differentiable, so an intersection is unique when it
exists. `light_cone_intersection` returns both events, solver metadata, and a
scaled null residual.

Inertial receivers use a rationalized extended-precision analytic expression
and reject near-null input conditioning that exceeds the declared contract.
General worldlines use a delay-relative bracketed, safeguarded
Newton/bisection algorithm. Solving for delay rather than absolute reception
time prevents a large coordinate epoch from becoming a false stopping scale.
A finite worldline endpoint or explicit `max_coordinate_time` defines the
search horizon. If the monotone equation remains positive at that horizon, the
API raises `NoFutureLightConeIntersection`. Exhausting an unbounded numerical
search is instead `LightConeSearchExhausted`: it is not a proof that no future
intersection exists.

Coincident emission and receiver events have zero light time. Emission outside
the receiver's coordinate domain is invalid. A receiver trajectory that
becomes non-finite, lightlike, or superluminal while solving is invalid. A
positive delay smaller than the coordinate type's ULP at the chosen epoch is
not rounded to a zero-time delivery; it raises `NumericalConditioningError`.

The retained scalar functions `solve_light_time`, `solve_light_time_result`,
and `minkowski_interval2` are compatibility adapters around the typed
production implementation. They do not disable or otherwise manipulate
Julia's process-wide garbage collector.

## 5. Network delays and contacts

The direct light-cone event is a physical lower bound, not a complete network
delivery model. A transport may add, in causal order:

1. sender processing and queueing;
2. serialization at finite bandwidth;
3. propagation through a medium or explicit relay path;
4. receiver queueing and processing.

Messages may be lost, duplicated, reordered, or delayed. FIFO delivery is a
configuration choice, not an invariant imposed to repair out-of-order traces.
A relay is a process with explicit receive, store, and later send events; an
end-to-end shortcut must not be substituted for those causal edges. Contact
windows can prevent a send or constrain it to a later event, but cannot move a
delivery earlier than the light-cone bound.

For every realized send/receive edge, the simulator must check that receive is
in the causal future of send. A null residual checks the direct propagation
kernel. It is a physics-engine validation metric and must never be labeled a
Raft safety violation.

## 6. Event order

The scheduler uses one inertial coordinate frame to place events in a priority
queue. This ordering is an implementation device. Protocol happens-before is
created only by:

- program order within one process; and
- a message send followed by its receive.

Spacelike events are concurrent. Their arbitrary queue order must not expose
shared mutable node state or create a protocol dependency. A proper
orthochronous Lorentz transformation may reverse the coordinate order of
spacelike events while preserving every causal edge.

Validation therefore transforms complete inertial scenarios and checks:

- squared intervals and causal classifications;
- the transformed direct-reception event;
- proper-time intervals on node worldlines;
- eventually, the causal protocol trace and frame-invariant metrics.

Floating-point coordinates in different frames are not expected to be bitwise
identical. Comparisons use documented scaled tolerances.

## 7. Numerical error contract

Absolute interval residuals have squared-distance units and grow under a mere
change of scale. The primary null-delivery diagnostic is instead

```text
R_null = |c² Δt² - ||Δx||²| / (c² Δt² + ||Δx||²),
```

with `R_null = 0` for coincident events. This dimensionless residual is exposed
as `scaled_interval_residual` and in each `LightConeIntersection`.

The squared terms in `R_null`, causal classification, and interval diagnostics
are evaluated with extended-range intermediates. `hypot`-style norms and
velocity-to-`c` ratios avoid avoidable overflow and underflow. The dimensionful
`interval_squared` raises `NumericalConditioningError` when its result cannot be
represented, while the dimensionless classification remains usable.

Every light-cone return, including analytic and coincident paths, is validated
against the unsquared equation and `R_null`. The light solver controls the
unsquared equation with a relative tolerance and an optional absolute spatial
tolerance. Bracket endpoints that become adjacent floating-point values are
accepted only if one independently passes both residual checks. Defaults are
based on the numeric type's precision. Research configurations must record any
non-default tolerance. A bracketed result that misses its contract raises
`LightConeConvergenceError`; representability or forward-conditioning failures
raise `NumericalConditioningError`.

Lorentz factors share the same scale-safe beta calculation as worldline
validation and proper clocks. Boosts use stable `gamma - 1` evaluation,
extended-precision transformations, and inverse round-trip checks. A boost too
near null for covariance at the requested precision is rejected as
ill-conditioned instead of being presented as a failed physical invariant.

An independently transformed absolute event cannot express which small
separation a later calculation will need. In particular, scaling its error by
a large absolute epoch is not an interval-covariance guarantee.
`lorentz_transform_displacement` therefore transforms relative coordinates
directly and validates the converted displacement's interval, causal class,
and inverse round trip. `lorentz_transform_pair` first transforms the relative
separation, then reconstructs the absolute pair; it raises
`NumericalConditioningError` if the transformed epoch's ULP cannot carry that
separation. Scientific interval or causal-covariance checks must use one of
these separation-aware APIs. Single-event `lorentz_transform` remains useful
for isolated coordinates and performs conservative whole-event and
component-local round-trip checks, but it cannot certify an unspecified future
separation.

Validation contains four distinct forms of evidence:

- analytic stationary, radial-approaching, radial-receding, and transverse
  solutions;
- an independent `BigFloat` bisection oracle for inertial cases;
- Float32, Float64, and BigFloat checks across coordinate scales and large
  epochs, including oblique and near-null cases;
- an independent analytic oscillatory proper-time oracle designed to expose
  quadrature aliasing;
- Lorentz metamorphic checks of intervals, receptions, velocities, and proper
  time.

These checks establish numerical agreement within their tested domains. They
do not prove correctness for every user-supplied worldline. Extended-precision
validation allocates and is intentionally favored over the prototype's former
zero-allocation claim; experiment manifests should record solver cost
separately from protocol cost. Gauss--Kronrod error estimates assume adequate
breakpoints and regularity, finite-difference audits cover only declared sample
times, and the near-null conditioning bound is conservative. A rejected case
may be solvable after rescaling coordinates or choosing a higher-precision type;
it is not evidence of a physical impossibility.

## 8. Invalid inputs and failure semantics

Inputs are rejected rather than coerced when any of the following holds:

| Condition | Result |
|---|---|
| `c` is non-finite or not strictly positive | `ArgumentError` |
| event coordinate is non-finite or has the wrong dimension | `ArgumentError` |
| inertial node speed is `>= c` or non-finite | `InvalidWorldlineError` |
| parametric velocity is non-finite or `>= c` when evaluated | `InvalidWorldlineError` |
| parametric position and velocity fail a requested audit | `InvalidWorldlineError` |
| coordinate time lies outside a worldline domain | `DomainError` |
| no reception exists within the declared future horizon | `NoFutureLightConeIntersection` |
| an unbounded light-cone search exhausts its bracket budget | `LightConeSearchExhausted` |
| a bracketed solve fails its iteration/error contract | `LightConeConvergenceError` |
| a value or causal increment cannot meet the numeric representation contract | `NumericalConditioningError` |
| proper-time quadrature exhausts its evaluation/error budget | `QuadratureConvergenceError` |
| proper-time inversion exhausts its root budget | `ProperTimeInversionError` |
| proper-time inversion exceeds a finite worldline domain | `DomainError` |

NaN is never used as a missing receive event, and infinity is never used to
pretend that a delivery occurred. The simulation layer may represent a dropped
or horizon-censored message as an explicit trace outcome.

## 9. Scientific interpretation

The physics layer is deliberately independent of Raft. It can establish when
information could causally arrive and whether numerical deliveries respect the
model. It cannot by itself establish a Raft election, commit, safety property,
client-visible availability, or impossibility theorem.

Absence of a reachable majority inside a deadline is a timed-progress or
feasibility result, not a replicated-log safety violation. Passing simulator
checks is regression evidence, not a proof of Raft safety. Claims must retain
the limitations in the publishable research plan, distinguish normalized
high-velocity tests from mission-inspired scenarios, and report null or adverse
results without retuning the question after observing them.
