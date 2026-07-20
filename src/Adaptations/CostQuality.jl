function _nonnegative_metric(name::AbstractString, value::Real; allow_infinite::Bool=true)
    converted = Float64(value)
    valid = converted >= 0.0 && !isnan(converted) && (allow_infinite || isfinite(converted))
    valid || throw(ArgumentError("$name must be nonnegative$(allow_infinite ? "" : " and finite")"))
    return converted
end

"""Quality vector. Availability is maximized; every other component is minimized."""
struct QualityMetrics
    deadline_availability::Float64
    false_suspicion_rate::Float64
    detection_delay::Float64
    commit_latency::Float64
    leader_churn::Float64
    censoring_rate::Float64

    function QualityMetrics(;
        deadline_availability::Real,
        false_suspicion_rate::Real,
        detection_delay::Real,
        commit_latency::Real,
        leader_churn::Real,
        censoring_rate::Real,
    )
        availability = _probability("deadline availability", deadline_availability)
        false_suspicion = _probability("false suspicion rate", false_suspicion_rate)
        detection = _nonnegative_metric("detection delay", detection_delay)
        latency = _nonnegative_metric("commit latency", commit_latency)
        churn = _nonnegative_metric("leader churn", leader_churn)
        censoring = _probability("censoring rate", censoring_rate)
        return new(availability, false_suspicion, detection, latency, churn, censoring)
    end
end

"""Resource vector. Every component is minimized and retains its native meaning."""
struct CostMetrics
    message_rate::Float64
    byte_rate::Float64
    redundancy_rate::Float64
    energy_proxy::Float64
    placement_cost::Float64
    link_occupancy::Float64
    estimator_cpu::Float64
    estimator_state_bytes::Float64

    function CostMetrics(;
        message_rate::Real=0.0,
        byte_rate::Real=0.0,
        redundancy_rate::Real=0.0,
        energy_proxy::Real=0.0,
        placement_cost::Real=0.0,
        link_occupancy::Real=0.0,
        estimator_cpu::Real=0.0,
        estimator_state_bytes::Real=0.0,
    )
        return new(
            _nonnegative_metric("message rate", message_rate),
            _nonnegative_metric("byte rate", byte_rate),
            _nonnegative_metric("redundancy rate", redundancy_rate),
            _nonnegative_metric("energy proxy", energy_proxy),
            _nonnegative_metric("placement cost", placement_cost),
            _nonnegative_metric("link occupancy", link_occupancy),
            _nonnegative_metric("estimator CPU", estimator_cpu),
            _nonnegative_metric("estimator state bytes", estimator_state_bytes),
        )
    end
end

function CostMetrics(cost::ResourceCost; duration::Real=1.0, placement_cost::Real=0.0)
    window = _finite_positive("cost aggregation duration", duration)
    return CostMetrics(
        message_rate=cost.messages / window,
        byte_rate=cost.bytes / window,
        redundancy_rate=redundant_copies(cost) / window,
        energy_proxy=cost.energy_proxy,
        placement_cost=placement_cost,
        link_occupancy=cost.link_occupancy,
    )
end

struct PolicyOutcome
    policy_id::String
    quality::QualityMetrics
    cost::CostMetrics
    configuration_fingerprint::String

    function PolicyOutcome(
        policy_id::AbstractString,
        quality::QualityMetrics,
        cost::CostMetrics;
        configuration_fingerprint::AbstractString=config_fingerprint((policy_id=String(policy_id),)),
    )
        isempty(policy_id) && throw(ArgumentError("policy outcome id cannot be empty"))
        fingerprint = String(configuration_fingerprint)
        isempty(fingerprint) && throw(ArgumentError("configuration fingerprint cannot be empty"))
        return new(String(policy_id), quality, cost, fingerprint)
    end
end

function _minimization_vector(outcome::PolicyOutcome)
    quality = outcome.quality
    cost = outcome.cost
    return (
        1.0 - quality.deadline_availability,
        quality.false_suspicion_rate,
        quality.detection_delay,
        quality.commit_latency,
        quality.leader_churn,
        quality.censoring_rate,
        cost.message_rate,
        cost.byte_rate,
        cost.redundancy_rate,
        cost.energy_proxy,
        cost.placement_cost,
        cost.link_occupancy,
        cost.estimator_cpu,
        cost.estimator_state_bytes,
    )
end

"""True only for componentwise no-worse and at least one strictly-better outcome."""
function dominates(left::PolicyOutcome, right::PolicyOutcome; tolerance::Real=0.0)
    threshold = _finite_nonnegative("Pareto dominance tolerance", tolerance)
    left_values = _minimization_vector(left)
    right_values = _minimization_vector(right)
    no_worse = all(l <= r + threshold for (l, r) in zip(left_values, right_values))
    strictly_better = any(l < r - threshold for (l, r) in zip(left_values, right_values))
    return no_worse && strictly_better
end

function pareto_frontier(outcomes::AbstractVector{PolicyOutcome}; tolerance::Real=0.0)
    ids = getfield.(outcomes, :policy_id)
    allunique(ids) || throw(ArgumentError("policy outcome ids must be unique"))
    frontier = PolicyOutcome[]
    for (index, candidate) in pairs(outcomes)
        is_dominated = any(
            other_index != index && dominates(other, candidate; tolerance=tolerance)
            for (other_index, other) in pairs(outcomes)
        )
        is_dominated || push!(frontier, candidate)
    end
    sort!(frontier; by=outcome -> outcome.policy_id)
    return frontier
end

"""Transparent quality and budget constraints for an SLO choice table."""
struct OutcomeConstraints
    minimum_deadline_availability::Float64
    maximum_false_suspicion_rate::Float64
    maximum_detection_delay::Float64
    maximum_commit_latency::Float64
    maximum_leader_churn::Float64
    maximum_censoring_rate::Float64
    maximum_message_rate::Float64
    maximum_byte_rate::Float64
    maximum_redundancy_rate::Float64
    maximum_energy_proxy::Float64
    maximum_placement_cost::Float64
    maximum_link_occupancy::Float64

    function OutcomeConstraints(;
        minimum_deadline_availability::Real=0.0,
        maximum_false_suspicion_rate::Real=1.0,
        maximum_detection_delay::Real=Inf,
        maximum_commit_latency::Real=Inf,
        maximum_leader_churn::Real=Inf,
        maximum_censoring_rate::Real=1.0,
        maximum_message_rate::Real=Inf,
        maximum_byte_rate::Real=Inf,
        maximum_redundancy_rate::Real=Inf,
        maximum_energy_proxy::Real=Inf,
        maximum_placement_cost::Real=Inf,
        maximum_link_occupancy::Real=Inf,
    )
        return new(
            _probability("minimum deadline availability", minimum_deadline_availability),
            _probability("maximum false suspicion rate", maximum_false_suspicion_rate),
            _nonnegative_metric("maximum detection delay", maximum_detection_delay),
            _nonnegative_metric("maximum commit latency", maximum_commit_latency),
            _nonnegative_metric("maximum leader churn", maximum_leader_churn),
            _probability("maximum censoring rate", maximum_censoring_rate),
            _nonnegative_metric("maximum message rate", maximum_message_rate),
            _nonnegative_metric("maximum byte rate", maximum_byte_rate),
            _nonnegative_metric("maximum redundancy rate", maximum_redundancy_rate),
            _nonnegative_metric("maximum energy proxy", maximum_energy_proxy),
            _nonnegative_metric("maximum placement cost", maximum_placement_cost),
            _nonnegative_metric("maximum link occupancy", maximum_link_occupancy),
        )
    end
end

function satisfies(outcome::PolicyOutcome, constraints::OutcomeConstraints)
    quality = outcome.quality
    cost = outcome.cost
    return quality.deadline_availability >= constraints.minimum_deadline_availability &&
           quality.false_suspicion_rate <= constraints.maximum_false_suspicion_rate &&
           quality.detection_delay <= constraints.maximum_detection_delay &&
           quality.commit_latency <= constraints.maximum_commit_latency &&
           quality.leader_churn <= constraints.maximum_leader_churn &&
           quality.censoring_rate <= constraints.maximum_censoring_rate &&
           cost.message_rate <= constraints.maximum_message_rate &&
           cost.byte_rate <= constraints.maximum_byte_rate &&
           cost.redundancy_rate <= constraints.maximum_redundancy_rate &&
           cost.energy_proxy <= constraints.maximum_energy_proxy &&
           cost.placement_cost <= constraints.maximum_placement_cost &&
           cost.link_occupancy <= constraints.maximum_link_occupancy
end

function feasible_outcomes(
    outcomes::AbstractVector{PolicyOutcome},
    constraints::OutcomeConstraints=OutcomeConstraints(),
)
    selected = [outcome for outcome in outcomes if satisfies(outcome, constraints)]
    sort!(selected; by=outcome -> outcome.policy_id)
    return selected
end

abstract type AbstractOutcomeObjective end

struct ParetoObjective <: AbstractOutcomeObjective
    constraints::OutcomeConstraints
    tolerance::Float64

    ParetoObjective(
        constraints::OutcomeConstraints=OutcomeConstraints();
        tolerance::Real=0.0,
    ) = new(
        constraints,
        _finite_nonnegative("Pareto objective tolerance", tolerance),
    )
end

const _MINIMIZABLE_METRICS = (
    :false_suspicion_rate,
    :detection_delay,
    :commit_latency,
    :leader_churn,
    :censoring_rate,
    :message_rate,
    :byte_rate,
    :redundancy_rate,
    :energy_proxy,
    :placement_cost,
    :link_occupancy,
    :estimator_cpu,
    :estimator_state_bytes,
)

struct MinimumMetricObjective <: AbstractOutcomeObjective
    metric::Symbol
    constraints::OutcomeConstraints

    function MinimumMetricObjective(
        metric::Symbol,
        constraints::OutcomeConstraints=OutcomeConstraints(),
    )
        metric in _MINIMIZABLE_METRICS ||
            throw(ArgumentError("unsupported minimum objective metric: $metric"))
        return new(metric, constraints)
    end
end

function _outcome_metric(outcome::PolicyOutcome, metric::Symbol)
    if hasfield(QualityMetrics, metric)
        return getfield(outcome.quality, metric)
    elseif hasfield(CostMetrics, metric)
        return getfield(outcome.cost, metric)
    end
    throw(ArgumentError("unknown outcome metric: $metric"))
end

function select_outcomes(
    outcomes::AbstractVector{PolicyOutcome},
    objective::ParetoObjective=ParetoObjective(),
)
    feasible = feasible_outcomes(outcomes, objective.constraints)
    return pareto_frontier(feasible; tolerance=objective.tolerance)
end

function select_outcomes(
    outcomes::AbstractVector{PolicyOutcome},
    objective::MinimumMetricObjective,
)
    feasible = feasible_outcomes(outcomes, objective.constraints)
    isempty(feasible) && return PolicyOutcome[]
    minimum_value = minimum(_outcome_metric(outcome, objective.metric) for outcome in feasible)
    # Every exact tie is returned; an arbitrary policy id is never silently
    # chosen for the user.
    selected = [
        outcome for outcome in feasible if
        _outcome_metric(outcome, objective.metric) == minimum_value
    ]
    sort!(selected; by=outcome -> outcome.policy_id)
    return selected
end
