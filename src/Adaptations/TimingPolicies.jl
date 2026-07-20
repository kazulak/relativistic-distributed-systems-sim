"""Unmodified-Raft baseline expressed exclusively in local proper time."""
struct StaticElectionPolicy <: AbstractElectionPolicy
    minimum_timeout::Float64
    maximum_timeout::Float64

    function StaticElectionPolicy(minimum_timeout::Real, maximum_timeout::Real)
        lower = _finite_positive("static election minimum", minimum_timeout)
        upper = _finite_positive("static election maximum", maximum_timeout)
        upper > lower || throw(ArgumentError("static election maximum must exceed its minimum"))
        return new(lower, upper)
    end
end

struct StaticHeartbeatPolicy <: AbstractHeartbeatPolicy
    interval::Float64

    StaticHeartbeatPolicy(interval::Real) =
        new(_finite_positive("static heartbeat interval", interval))
end

election_window(policy::StaticElectionPolicy, state=nothing, bounds=nothing) =
    ready_election_window(policy.minimum_timeout, policy.maximum_timeout, :static_proper_time)

heartbeat_decision(policy::StaticHeartbeatPolicy, bounds=nothing) =
    HeartbeatDecision(_READY_STATUS, policy.interval, :static_proper_time)

"""Election window anchored by a causal round-trip lower bound plus processing margin."""
struct GeometricElectionPolicy <: AbstractElectionPolicy
    safety_factor::Float64
    processing_margin::Float64
    randomization_fraction::Float64
    minimum_timeout::Float64
    maximum_timeout::Float64

    function GeometricElectionPolicy(;
        safety_factor::Real=1.0,
        processing_margin::Real=0.0,
        randomization_fraction::Real=0.5,
        minimum_timeout::Real=0.15,
        maximum_timeout::Real=30.0,
    )
        factor = Float64(safety_factor)
        isfinite(factor) && factor >= 1.0 ||
            throw(ArgumentError("geometric election safety_factor must be finite and at least one"))
        margin = _finite_nonnegative("geometric election processing_margin", processing_margin)
        randomization = _probability("geometric election randomization_fraction", randomization_fraction)
        lower = _finite_positive("geometric election minimum", minimum_timeout)
        upper = _finite_positive("geometric election maximum", maximum_timeout)
        upper > lower || throw(ArgumentError("geometric election maximum must exceed its minimum"))
        return new(factor, margin, randomization, lower, upper)
    end
end

"""Heartbeat cadence anchored independently by a one-way causal lower bound."""
struct GeometricHeartbeatPolicy <: AbstractHeartbeatPolicy
    safety_factor::Float64
    processing_margin::Float64
    minimum_interval::Float64
    maximum_interval::Float64

    function GeometricHeartbeatPolicy(;
        safety_factor::Real=1.0,
        processing_margin::Real=0.0,
        minimum_interval::Real=0.05,
        maximum_interval::Real=10.0,
    )
        factor = Float64(safety_factor)
        isfinite(factor) && factor >= 0.0 ||
            throw(ArgumentError("geometric heartbeat safety_factor must be finite and nonnegative"))
        margin = _finite_nonnegative("geometric heartbeat processing_margin", processing_margin)
        lower = _finite_positive("geometric heartbeat minimum", minimum_interval)
        upper = _finite_positive("geometric heartbeat maximum", maximum_interval)
        upper >= lower || throw(ArgumentError("geometric heartbeat maximum cannot be below its minimum"))
        return new(factor, margin, lower, upper)
    end
end

function _bounded_window(
    base::Float64,
    randomization_fraction::Float64,
    minimum_timeout::Float64,
    maximum_timeout::Float64,
    source::Symbol,
    ;
    reject_at_maximum::Bool=false,
)
    if !isfinite(base)
        return refused_election_window(
            _UNBOUNDED_STATUS,
            source,
            "timeout estimate is not finitely representable",
        )
    end
    if base >= maximum_timeout
        reject_at_maximum && return refused_election_window(
            _INFEASIBLE_STATUS,
            source,
            "causal lower bound leaves no room below the configured maximum",
        )
        return ready_election_window(maximum_timeout, maximum_timeout, source)
    end
    lower = max(base, minimum_timeout)
    requested_upper = lower * (1.0 + randomization_fraction)
    upper = isfinite(requested_upper) ? min(requested_upper, maximum_timeout) : maximum_timeout
    return ready_election_window(lower, max(lower, upper), source)
end

function election_window(
    policy::GeometricElectionPolicy,
    state,
    bounds::CausalTimingBounds,
)
    bounds.reachable || return refused_election_window(
        _UNBOUNDED_STATUS,
        :causal_geometry,
        "no finite future round-trip path is declared",
    )
    base = muladd(policy.safety_factor, bounds.round_trip_lower_bound, policy.processing_margin)
    return _bounded_window(
        base,
        policy.randomization_fraction,
        policy.minimum_timeout,
        policy.maximum_timeout,
        :causal_geometry,
        reject_at_maximum=true,
    )
end

function heartbeat_decision(
    policy::GeometricHeartbeatPolicy,
    bounds::CausalTimingBounds,
)
    bounds.reachable || return HeartbeatDecision(
        _UNBOUNDED_STATUS,
        Inf,
        :causal_geometry,
        "no finite future one-way path is declared",
    )
    estimate = muladd(
        policy.safety_factor,
        bounds.one_way_lower_bound,
        policy.processing_margin,
    )
    isfinite(estimate) || return HeartbeatDecision(
        _UNBOUNDED_STATUS,
        Inf,
        :causal_geometry,
        "heartbeat estimate is not finitely representable",
    )
    estimate > policy.maximum_interval && return HeartbeatDecision(
        _INFEASIBLE_STATUS,
        Inf,
        :causal_geometry,
        "causal heartbeat estimate exceeds the configured maximum",
    )
    return HeartbeatDecision(
        _READY_STATUS,
        clamp(estimate, policy.minimum_interval, policy.maximum_interval),
        :causal_geometry,
    )
end

"""One detector observation. Source emission is optional and never inferred."""
struct ArrivalObservation
    sequence::UInt64
    receiver_proper_arrival::Float64
    source_proper_emission::Union{Nothing,Float64}

    function ArrivalObservation(
        sequence::Integer,
        receiver_proper_arrival::Real;
        source_proper_emission::Union{Nothing,Real}=nothing,
    )
        sequence >= 0 || throw(ArgumentError("observation sequence must be nonnegative"))
        arrival = _finite_nonnegative("receiver proper arrival", receiver_proper_arrival)
        emission = if source_proper_emission === nothing
            nothing
        else
            _finite_nonnegative("source proper emission", source_proper_emission)
        end
        return new(UInt64(sequence), arrival, emission)
    end
end

"""Immutable arrival-estimator state; updates never touch protocol state."""
struct AdaptiveTimingState
    sample_count::Int
    mean_interval::Float64
    variance::Float64
    last_arrival::Union{Nothing,Float64}
    last_sequence::Union{Nothing,UInt64}
    rejected_observations::Int

    function AdaptiveTimingState(
        sample_count::Integer,
        mean_interval::Real,
        variance::Real,
        last_arrival::Union{Nothing,Real},
        last_sequence::Union{Nothing,Integer},
        rejected_observations::Integer,
    )
        sample_count >= 0 || throw(ArgumentError("adaptive sample count must be nonnegative"))
        rejected_observations >= 0 ||
            throw(ArgumentError("adaptive rejected count must be nonnegative"))
        mean = _finite_nonnegative("adaptive mean interval", mean_interval)
        spread = _finite_nonnegative("adaptive variance", variance)
        isnothing(last_arrival) == isnothing(last_sequence) ||
            throw(ArgumentError("adaptive last arrival and sequence must be present together"))
        arrival = isnothing(last_arrival) ? nothing :
                  _finite_nonnegative("adaptive last arrival", last_arrival)
        sequence = if isnothing(last_sequence)
            nothing
        else
            last_sequence >= 0 || throw(ArgumentError("adaptive last sequence must be nonnegative"))
            UInt64(last_sequence)
        end
        sample_count > 0 && isnothing(arrival) &&
            throw(ArgumentError("sampled adaptive state requires a last observation"))
        return new(
            Int(sample_count),
            mean,
            spread,
            arrival,
            sequence,
            Int(rejected_observations),
        )
    end
end

AdaptiveTimingState() = AdaptiveTimingState(0, 0.0, 0.0, nothing, nothing, 0)

struct ObservationUpdate
    state::AdaptiveTimingState
    accepted::Bool
    sequence_gap::UInt64
end

"""Robust arrival-only EWMA/variance election policy with explicit warm-up and clamps."""
struct RobustAdaptiveElectionPolicy <: AbstractElectionPolicy
    alpha::Float64
    sigma_multiplier::Float64
    robust_clip_sigma::Float64
    processing_margin::Float64
    randomization_fraction::Float64
    warmup_samples::Int
    warmup_timeout::Float64
    minimum_timeout::Float64
    maximum_timeout::Float64

    function RobustAdaptiveElectionPolicy(;
        alpha::Real=0.2,
        sigma_multiplier::Real=4.0,
        robust_clip_sigma::Real=6.0,
        processing_margin::Real=0.0,
        randomization_fraction::Real=0.25,
        warmup_samples::Integer=4,
        warmup_timeout::Real=0.30,
        minimum_timeout::Real=0.15,
        maximum_timeout::Real=30.0,
    )
        smoothing = _probability("adaptive alpha", alpha; allow_zero=false)
        sigma = _finite_nonnegative("adaptive sigma_multiplier", sigma_multiplier)
        clipping = _finite_positive("adaptive robust_clip_sigma", robust_clip_sigma)
        margin = _finite_nonnegative("adaptive processing_margin", processing_margin)
        randomization = _probability("adaptive randomization_fraction", randomization_fraction)
        warmup_samples >= 1 || throw(ArgumentError("adaptive warmup_samples must be positive"))
        lower = _finite_positive("adaptive minimum timeout", minimum_timeout)
        upper = _finite_positive("adaptive maximum timeout", maximum_timeout)
        upper > lower || throw(ArgumentError("adaptive maximum timeout must exceed its minimum"))
        warmup = _finite_positive("adaptive warmup timeout", warmup_timeout)
        lower <= warmup <= upper ||
            throw(ArgumentError("adaptive warmup timeout must lie inside the timeout clamps"))
        return new(
            smoothing,
            sigma,
            clipping,
            margin,
            randomization,
            Int(warmup_samples),
            warmup,
            lower,
            upper,
        )
    end
end

function _rejected_update(state::AdaptiveTimingState)
    rejected = Base.checked_add(state.rejected_observations, 1)
    return ObservationUpdate(
        AdaptiveTimingState(
            state.sample_count,
            state.mean_interval,
            state.variance,
            state.last_arrival,
            state.last_sequence,
            rejected,
        ),
        false,
        0,
    )
end

function update_observation(
    policy::RobustAdaptiveElectionPolicy,
    state::AdaptiveTimingState,
    observation::ArrivalObservation,
)
    if state.last_sequence === nothing
        return ObservationUpdate(
            AdaptiveTimingState(
                state.sample_count,
                state.mean_interval,
                state.variance,
                observation.receiver_proper_arrival,
                observation.sequence,
                state.rejected_observations,
            ),
            true,
            0,
        )
    end
    observation.sequence > state.last_sequence || return _rejected_update(state)
    observation.receiver_proper_arrival > state.last_arrival || return _rejected_update(state)

    gap = observation.sequence - state.last_sequence
    raw_interval =
        (observation.receiver_proper_arrival - state.last_arrival) / Float64(gap)
    isfinite(raw_interval) && raw_interval > 0.0 || return _rejected_update(state)
    # A value above the hard timeout ceiling cannot affect the eventual finite
    # decision except by saturating it, and clipping it keeps variance finite.
    sample = min(raw_interval, policy.maximum_timeout)
    if state.sample_count >= 2 && state.variance > 0.0
        radius = policy.robust_clip_sigma * sqrt(state.variance)
        if isfinite(radius)
            sample = clamp(sample, max(0.0, state.mean_interval - radius), state.mean_interval + radius)
        end
    end

    count = Base.checked_add(state.sample_count, 1)
    if state.sample_count == 0
        mean = sample
        variance = 0.0
    else
        delta = sample - state.mean_interval
        mean = muladd(policy.alpha, delta, state.mean_interval)
        variance_update = state.variance + policy.alpha * delta * delta
        variance = (1.0 - policy.alpha) * variance_update
        isfinite(variance) || (variance = floatmax(Float64))
    end
    return ObservationUpdate(
        AdaptiveTimingState(
            count,
            mean,
            max(0.0, variance),
            observation.receiver_proper_arrival,
            observation.sequence,
            state.rejected_observations,
        ),
        true,
        gap,
    )
end

function _adaptive_base(
    policy::RobustAdaptiveElectionPolicy,
    state::AdaptiveTimingState,
)
    state.sample_count < policy.warmup_samples && return policy.warmup_timeout
    deviation = sqrt(max(0.0, state.variance))
    estimate = state.mean_interval + policy.sigma_multiplier * deviation + policy.processing_margin
    return isfinite(estimate) ? estimate : policy.maximum_timeout
end

function election_window(
    policy::RobustAdaptiveElectionPolicy,
    state::AdaptiveTimingState,
    bounds=nothing,
)
    return _bounded_window(
        _adaptive_base(policy, state),
        policy.randomization_fraction,
        policy.minimum_timeout,
        policy.maximum_timeout,
        state.sample_count < policy.warmup_samples ? :adaptive_warmup : :arrival_ewma,
    )
end

"""Geometric causal prior blended with arrival observations after warm-up."""
struct HybridElectionPolicy <: AbstractElectionPolicy
    geometry::GeometricElectionPolicy
    observations::RobustAdaptiveElectionPolicy
    prior_strength::Float64

    function HybridElectionPolicy(
        geometry::GeometricElectionPolicy,
        observations::RobustAdaptiveElectionPolicy;
        prior_strength::Real=4.0,
    )
        strength = _finite_positive("hybrid prior_strength", prior_strength)
        return new(geometry, observations, strength)
    end
end

update_observation(
    policy::HybridElectionPolicy,
    state::AdaptiveTimingState,
    observation::ArrivalObservation,
) = update_observation(policy.observations, state, observation)

function election_window(
    policy::HybridElectionPolicy,
    state::AdaptiveTimingState,
    bounds::CausalTimingBounds,
)
    geometric = election_window(policy.geometry, nothing, bounds)
    geometric.status === _READY_STATUS || return geometric
    lower_clamp = max(
        policy.geometry.minimum_timeout,
        policy.observations.minimum_timeout,
    )
    upper_clamp = min(
        policy.geometry.maximum_timeout,
        policy.observations.maximum_timeout,
    )
    upper_clamp > lower_clamp || return refused_election_window(
        _INFEASIBLE_STATUS,
        :hybrid_geometry_observations,
        "geometric and observational timeout clamps do not overlap",
    )

    observational = _adaptive_base(policy.observations, state)
    sample_weight = Float64(state.sample_count)
    prior_weight = policy.prior_strength / (policy.prior_strength + sample_weight)
    blended = muladd(prior_weight, geometric.minimum - observational, observational)
    # Observations may increase conservatism, but can never undercut the known
    # causal lower bound.
    base = max(geometric.minimum, blended)
    randomization = max(
        policy.geometry.randomization_fraction,
        policy.observations.randomization_fraction,
    )
    return _bounded_window(
        base,
        randomization,
        lower_clamp,
        upper_clamp,
        state.sample_count < policy.observations.warmup_samples ?
        :hybrid_warmup : :hybrid_geometry_observations,
    )
end

function _resolve_election_window(policy::StaticElectionPolicy, state, bounds)
    return election_window(policy, state, bounds)
end

function _resolve_election_window(policy::RobustAdaptiveElectionPolicy, state, bounds)
    state isa AdaptiveTimingState ||
        throw(ArgumentError("adaptive election policy requires AdaptiveTimingState"))
    return election_window(policy, state, bounds)
end

function _resolve_election_window(policy::GeometricElectionPolicy, state, bounds)
    bounds isa CausalTimingBounds ||
        throw(ArgumentError("geometric election policy requires CausalTimingBounds"))
    return election_window(policy, state, bounds)
end

function _resolve_election_window(policy::HybridElectionPolicy, state, bounds)
    state isa AdaptiveTimingState ||
        throw(ArgumentError("hybrid election policy requires AdaptiveTimingState"))
    bounds isa CausalTimingBounds ||
        throw(ArgumentError("hybrid election policy requires CausalTimingBounds"))
    return election_window(policy, state, bounds)
end

_resolve_heartbeat(policy::StaticHeartbeatPolicy, bounds) = heartbeat_decision(policy, bounds)

function _resolve_heartbeat(policy::GeometricHeartbeatPolicy, bounds)
    bounds isa CausalTimingBounds ||
        throw(ArgumentError("geometric heartbeat policy requires CausalTimingBounds"))
    return heartbeat_decision(policy, bounds)
end

"""Pure runner-facing timing evaluation; the caller owns timer generations and scheduling."""
function evaluate_timing(
    policies::TimingPolicySet;
    state=nothing,
    bounds=nothing,
    election_draw::Real=0.5,
)
    window = _resolve_election_window(policies.election, state, bounds)
    selected = window.status === _READY_STATUS ?
               select_election_timeout(window, election_draw) : Inf
    heartbeat = _resolve_heartbeat(policies.heartbeat, bounds)
    return TimingDecision(window, selected, heartbeat)
end
