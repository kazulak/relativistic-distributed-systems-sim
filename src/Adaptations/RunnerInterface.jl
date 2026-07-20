"""
Named, fingerprintable policy bundle consumed by the Research runner.

The bundle contains no Raft node, term, vote, log, quorum, or commit state. A
runner may use the returned timing and transport directives only at the
scheduler/transport boundary.
"""
struct AdaptationVariant{
    T<:TimingPolicySet,
    R<:AbstractRedundancyPolicy,
    O<:AbstractOutcomeObjective,
}
    variant_id::String
    timing::T
    redundancy::R
    placement_method::Symbol
    objective::O

    function AdaptationVariant(
        variant_id::AbstractString,
        timing::T,
        redundancy::R;
        placement_method::Symbol=:exhaustive,
        objective::O=ParetoObjective(),
    ) where {
        T<:TimingPolicySet,
        R<:AbstractRedundancyPolicy,
        O<:AbstractOutcomeObjective,
    }
        isempty(variant_id) && throw(ArgumentError("adaptation variant id cannot be empty"))
        placement_method in (:exhaustive, :greedy) ||
            throw(ArgumentError("variant placement method must be :exhaustive or :greedy"))
        return new{T,R,O}(
            String(variant_id),
            timing,
            redundancy,
            placement_method,
            objective,
        )
    end
end

variant_fingerprint(variant::AdaptationVariant) = config_fingerprint(variant)

is_ready(decision::ElectionWindow) = decision.status === _READY_STATUS
is_ready(decision::HeartbeatDecision) = decision.status === _READY_STATUS
is_ready(decision::RedundancyPlan) = decision.status === :ready
is_ready(decision::PlacementResult) = decision.status === :ready

runner_timing_decision(variant::AdaptationVariant; kwargs...) =
    evaluate_timing(variant.timing; kwargs...)

runner_redundancy_plan(
    variant::AdaptationVariant,
    request::RedundancyRequest,
    budget::ResourceBudget=ResourceBudget(),
) = plan_redundancy(variant.redundancy, request, budget)

function runner_placement(
    variant::AdaptationVariant,
    matrix::CausalDelayMatrix;
    constraints::Union{Nothing,PlacementConstraints}=nothing,
    weights::PlacementWeights=PlacementWeights(),
    placement_costs::AbstractDict{<:Integer,<:Real}=Dict{Int,Float64}(),
)
    return select_placement(
        matrix;
        method=variant.placement_method,
        constraints=constraints,
        weights=weights,
        placement_costs=placement_costs,
    )
end

runner_select_outcomes(variant::AdaptationVariant, outcomes::AbstractVector{PolicyOutcome}) =
    select_outcomes(outcomes, variant.objective)

