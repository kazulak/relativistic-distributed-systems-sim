"""Directed causal-delay matrix. `Inf` denotes no finite path in the horizon."""
struct CausalDelayMatrix
    nodes::Vector{Int}
    delays::Matrix{Float64}
    index::Dict{Int,Int}

    function CausalDelayMatrix(nodes::AbstractVector{<:Integer}, delays::AbstractMatrix{<:Real})
        ids = Int.(nodes)
        isempty(ids) && throw(ArgumentError("causal-delay matrix requires at least one node"))
        all(>(0), ids) || throw(ArgumentError("causal-delay node ids must be positive"))
        allunique(ids) || throw(ArgumentError("causal-delay node ids must be unique"))
        size(delays) == (length(ids), length(ids)) ||
            throw(ArgumentError("causal-delay matrix dimensions must match node ids"))
        converted = Matrix{Float64}(delays)
        for value in converted
            (isfinite(value) && value >= 0.0) || value == Inf ||
                throw(ArgumentError("causal delays must be nonnegative or Inf"))
        end
        for diagonal in axes(converted, 1)
            converted[diagonal, diagonal] == 0.0 ||
                throw(ArgumentError("causal-delay diagonal must be exactly zero"))
        end
        lookup = Dict(node => position for (position, node) in enumerate(ids))
        return new(copy(ids), converted, lookup)
    end
end

function causal_delay(matrix::CausalDelayMatrix, from::Integer, to::Integer)
    from_index = get(matrix.index, Int(from), 0)
    to_index = get(matrix.index, Int(to), 0)
    from_index > 0 || throw(ArgumentError("unknown delay-matrix source node"))
    to_index > 0 || throw(ArgumentError("unknown delay-matrix destination node"))
    return matrix.delays[from_index, to_index]
end

struct PlacementConstraints
    quorum_size::Int
    eligible_leaders::Vector{Int}
    required_members::Vector{Int}
    maximum_quorum_delay::Float64
    maximum_placement_cost::Float64

    function PlacementConstraints(
        quorum_size::Integer;
        eligible_leaders::AbstractVector{<:Integer}=Int[],
        required_members::AbstractVector{<:Integer}=Int[],
        maximum_quorum_delay::Real=Inf,
        maximum_placement_cost::Real=Inf,
    )
        quorum_size >= 1 || throw(ArgumentError("placement quorum size must be positive"))
        eligible = sort!(Int.(eligible_leaders))
        required = sort!(Int.(required_members))
        all(>(0), eligible) && all(>(0), required) ||
            throw(ArgumentError("placement constraint node ids must be positive"))
        allunique(eligible) || throw(ArgumentError("eligible leaders must be unique"))
        allunique(required) || throw(ArgumentError("required members must be unique"))
        delay = Float64(maximum_quorum_delay)
        cost = Float64(maximum_placement_cost)
        (isfinite(delay) && delay >= 0.0) || delay == Inf ||
            throw(ArgumentError("maximum quorum delay must be nonnegative or Inf"))
        (isfinite(cost) && cost >= 0.0) || cost == Inf ||
            throw(ArgumentError("maximum placement cost must be nonnegative or Inf"))
        return new(Int(quorum_size), eligible, required, delay, cost)
    end
end

struct PlacementWeights
    quorum_delay::Float64
    placement_cost::Float64

    function PlacementWeights(; quorum_delay::Real=1.0, placement_cost::Real=1.0)
        delay = _finite_nonnegative("placement delay weight", quorum_delay)
        cost = _finite_nonnegative("placement cost weight", placement_cost)
        delay > 0.0 || cost > 0.0 ||
            throw(ArgumentError("at least one placement utility weight must be positive"))
        return new(delay, cost)
    end
end

struct PlacementCandidate
    leader::Int
    quorum::Tuple{Vararg{Int}}
    quorum_delay::Float64
    placement_cost::Float64
    utility::Float64
end

struct PlacementResult
    status::Symbol
    chosen::Union{Nothing,PlacementCandidate}
    tied_best::Vector{PlacementCandidate}
    feasible_candidates::Int
    method::Symbol
    reason::String
end

function _combinations(items::Vector{Int}, count::Int)
    count < 0 && return Vector{Vector{Int}}()
    count == 0 && return [Int[]]
    count > length(items) && return Vector{Vector{Int}}()
    result = Vector{Vector{Int}}()
    chosen = Int[]
    function visit(first_index::Int)
        remaining_needed = count - length(chosen)
        remaining_needed == 0 && return push!(result, copy(chosen))
        last_start = length(items) - remaining_needed + 1
        for index in first_index:last_start
            push!(chosen, items[index])
            visit(index + 1)
            pop!(chosen)
        end
        return nothing
    end
    visit(1)
    return result
end

function _placement_costs(
    matrix::CausalDelayMatrix,
    supplied::AbstractDict{<:Integer,<:Real},
)
    costs = Dict{Int,Float64}()
    for node in matrix.nodes
        value = Float64(get(supplied, node, 0.0))
        isfinite(value) && value >= 0.0 ||
            throw(ArgumentError("placement costs must be finite and nonnegative"))
        costs[node] = value
    end
    for node in keys(supplied)
        Int(node) in matrix.nodes || throw(ArgumentError("placement cost supplied for unknown node"))
    end
    return costs
end

function _candidate(
    matrix::CausalDelayMatrix,
    leader::Int,
    quorum::Vector{Int},
    constraints::PlacementConstraints,
    weights::PlacementWeights,
    costs::Dict{Int,Float64},
)
    delays = [causal_delay(matrix, leader, member) for member in quorum]
    all(isfinite, delays) || return nothing
    quorum_delay = maximum(delays; init=0.0)
    quorum_delay <= constraints.maximum_quorum_delay || return nothing
    placement_cost = costs[leader]
    placement_cost <= constraints.maximum_placement_cost || return nothing
    utility = muladd(weights.quorum_delay, quorum_delay, weights.placement_cost * placement_cost)
    isfinite(utility) || return nothing
    ordered_quorum = Tuple(sort!(unique!(copy(quorum))))
    return PlacementCandidate(leader, ordered_quorum, quorum_delay, placement_cost, utility)
end

function _validate_placement_inputs(
    matrix::CausalDelayMatrix,
    constraints::PlacementConstraints,
)
    constraints.quorum_size <= length(matrix.nodes) ||
        throw(ArgumentError("placement quorum exceeds matrix membership"))
    all(node -> node in matrix.nodes, constraints.eligible_leaders) ||
        throw(ArgumentError("eligible leader is outside matrix membership"))
    all(node -> node in matrix.nodes, constraints.required_members) ||
        throw(ArgumentError("required quorum member is outside matrix membership"))
    length(constraints.required_members) <= constraints.quorum_size ||
        throw(ArgumentError("required members exceed placement quorum size"))
    return nothing
end

function _finish_placement(candidates::Vector{PlacementCandidate}, method::Symbol)
    isempty(candidates) && return PlacementResult(
        :infeasible,
        nothing,
        PlacementCandidate[],
        0,
        method,
        "no leader/quorum satisfies causal reachability and placement constraints",
    )
    sort!(candidates; by=candidate -> (
        candidate.utility,
        candidate.quorum_delay,
        candidate.placement_cost,
        candidate.leader,
        candidate.quorum,
    ))
    best = first(candidates)
    ties = [
        candidate for candidate in candidates if
        candidate.utility == best.utility &&
        candidate.quorum_delay == best.quorum_delay &&
        candidate.placement_cost == best.placement_cost
    ]
    sort!(ties; by=candidate -> (candidate.leader, candidate.quorum))
    return PlacementResult(:ready, first(ties), ties, length(candidates), method, "")
end

function exhaustive_placement(
    matrix::CausalDelayMatrix,
    constraints::PlacementConstraints;
    weights::PlacementWeights=PlacementWeights(),
    placement_costs::AbstractDict{<:Integer,<:Real}=Dict{Int,Float64}(),
)
    _validate_placement_inputs(matrix, constraints)
    costs = _placement_costs(matrix, placement_costs)
    leaders = isempty(constraints.eligible_leaders) ? sort(matrix.nodes) : constraints.eligible_leaders
    candidates = PlacementCandidate[]
    for leader in leaders
        fixed = sort!(unique!(vcat([leader], constraints.required_members)))
        length(fixed) <= constraints.quorum_size || continue
        optional = sort!(setdiff(matrix.nodes, fixed))
        for addition in _combinations(optional, constraints.quorum_size - length(fixed))
            candidate = _candidate(
                matrix,
                leader,
                vcat(fixed, addition),
                constraints,
                weights,
                costs,
            )
            isnothing(candidate) || push!(candidates, candidate)
        end
    end
    return _finish_placement(candidates, :exhaustive)
end

function greedy_placement(
    matrix::CausalDelayMatrix,
    constraints::PlacementConstraints;
    weights::PlacementWeights=PlacementWeights(),
    placement_costs::AbstractDict{<:Integer,<:Real}=Dict{Int,Float64}(),
)
    _validate_placement_inputs(matrix, constraints)
    costs = _placement_costs(matrix, placement_costs)
    leaders = isempty(constraints.eligible_leaders) ? sort(matrix.nodes) : constraints.eligible_leaders
    candidates = PlacementCandidate[]
    for leader in leaders
        quorum = sort!(unique!(vcat([leader], constraints.required_members)))
        length(quorum) <= constraints.quorum_size || continue
        optional = sort!(
            setdiff(matrix.nodes, quorum);
            by=node -> (causal_delay(matrix, leader, node), node),
        )
        for node in optional
            length(quorum) == constraints.quorum_size && break
            isfinite(causal_delay(matrix, leader, node)) || continue
            push!(quorum, node)
        end
        length(quorum) == constraints.quorum_size || continue
        candidate = _candidate(matrix, leader, quorum, constraints, weights, costs)
        isnothing(candidate) || push!(candidates, candidate)
    end
    return _finish_placement(candidates, :greedy)
end

"""Deterministic runner interface for exhaustive or greedy leader/quorum selection."""
function select_placement(
    matrix::CausalDelayMatrix;
    method::Symbol=:exhaustive,
    constraints::Union{Nothing,PlacementConstraints}=nothing,
    weights::PlacementWeights=PlacementWeights(),
    placement_costs::AbstractDict{<:Integer,<:Real}=Dict{Int,Float64}(),
)
    selected_constraints = isnothing(constraints) ?
                           PlacementConstraints((length(matrix.nodes) >>> 1) + 1) : constraints
    if method === :exhaustive
        return exhaustive_placement(
            matrix,
            selected_constraints;
            weights=weights,
            placement_costs=placement_costs,
        )
    elseif method === :greedy
        return greedy_placement(
            matrix,
            selected_constraints;
            weights=weights,
            placement_costs=placement_costs,
        )
    end
    throw(ArgumentError("placement method must be :exhaustive or :greedy"))
end
