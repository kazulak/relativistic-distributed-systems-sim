abstract type AbstractRedundancyPolicy end

"""One declared causal path and its explicit per-copy resource model."""
struct PathOption
    path_id::Int
    causal_delay_bound::Float64
    delivery_probability::Float64
    overhead_bytes::Int
    fixed_energy::Float64
    energy_per_byte::Float64
    occupancy_per_byte::Float64

    function PathOption(
        path_id::Integer,
        causal_delay_bound::Real,
        delivery_probability::Real;
        overhead_bytes::Integer=0,
        fixed_energy::Real=0.0,
        energy_per_byte::Real=0.0,
        occupancy_per_byte::Real=0.0,
    )
        path_id > 0 || throw(ArgumentError("path id must be positive"))
        delay = Float64(causal_delay_bound)
        (isfinite(delay) && delay >= 0.0) || delay == Inf ||
            throw(ArgumentError("path causal delay must be nonnegative or Inf"))
        probability = _probability("path delivery probability", delivery_probability)
        overhead_bytes >= 0 || throw(ArgumentError("path overhead bytes must be nonnegative"))
        energy = _finite_nonnegative("path fixed energy", fixed_energy)
        energy_byte = _finite_nonnegative("path energy per byte", energy_per_byte)
        occupancy = _finite_nonnegative("path occupancy per byte", occupancy_per_byte)
        return new(
            Int(path_id),
            delay,
            probability,
            Int(overhead_bytes),
            energy,
            energy_byte,
            occupancy,
        )
    end
end

"""Explicit transport cost. Redundant copies are `max(messages - 1, 0)`."""
struct ResourceCost
    messages::Int
    bytes::Int
    energy_proxy::Float64
    link_occupancy::Float64

    function ResourceCost(
        messages::Integer=0,
        bytes::Integer=0,
        energy_proxy::Real=0.0,
        link_occupancy::Real=0.0,
    )
        messages >= 0 || throw(ArgumentError("resource messages must be nonnegative"))
        bytes >= 0 || throw(ArgumentError("resource bytes must be nonnegative"))
        energy = _finite_nonnegative("resource energy proxy", energy_proxy)
        occupancy = _finite_nonnegative("resource link occupancy", link_occupancy)
        return new(Int(messages), Int(bytes), energy, occupancy)
    end
end

redundant_copies(cost::ResourceCost) = max(cost.messages - 1, 0)

function Base.:(+)(left::ResourceCost, right::ResourceCost)
    return ResourceCost(
        Base.checked_add(left.messages, right.messages),
        Base.checked_add(left.bytes, right.bytes),
        left.energy_proxy + right.energy_proxy,
        left.link_occupancy + right.link_occupancy,
    )
end

"""Hard resource ceilings; a plan is never allowed to cross them."""
struct ResourceBudget
    maximum_messages::Int
    maximum_bytes::Int
    maximum_energy_proxy::Float64
    maximum_link_occupancy::Float64

    function ResourceBudget(;
        maximum_messages::Integer=typemax(Int),
        maximum_bytes::Integer=typemax(Int),
        maximum_energy_proxy::Real=Inf,
        maximum_link_occupancy::Real=Inf,
    )
        maximum_messages >= 0 || throw(ArgumentError("budget messages must be nonnegative"))
        maximum_bytes >= 0 || throw(ArgumentError("budget bytes must be nonnegative"))
        energy = Float64(maximum_energy_proxy)
        occupancy = Float64(maximum_link_occupancy)
        (isfinite(energy) && energy >= 0.0) || energy == Inf ||
            throw(ArgumentError("budget energy must be nonnegative or Inf"))
        (isfinite(occupancy) && occupancy >= 0.0) || occupancy == Inf ||
            throw(ArgumentError("budget occupancy must be nonnegative or Inf"))
        return new(Int(maximum_messages), Int(maximum_bytes), energy, occupancy)
    end
end

function within_budget(cost::ResourceCost, budget::ResourceBudget)
    return cost.messages <= budget.maximum_messages &&
           cost.bytes <= budget.maximum_bytes &&
           cost.energy_proxy <= budget.maximum_energy_proxy &&
           cost.link_occupancy <= budget.maximum_link_occupancy
end

"""Copy identity is unique while `logical_message_id` remains the receiver dedupe key."""
struct TransmissionID
    logical_message_id::UInt64
    copy_index::UInt32

    function TransmissionID(logical_message_id::Integer, copy_index::Integer)
        logical_message_id >= 0 || throw(ArgumentError("logical message id must be nonnegative"))
        1 <= copy_index <= typemax(UInt32) ||
            throw(ArgumentError("copy index must fit a positive UInt32"))
        return new(UInt64(logical_message_id), UInt32(copy_index))
    end
end

dedupe_key(id::TransmissionID) = id.logical_message_id

struct TransmissionCopy
    id::TransmissionID
    path_id::Int
    send_offset::Float64
    arrival_upper_bound::Float64
    payload_bytes::Int
    wire_bytes::Int
    cost::ResourceCost
end

dedupe_key(copy::TransmissionCopy) = dedupe_key(copy.id)

"""Logical transport request supplied by the Research runner."""
struct RedundancyRequest
    logical_message_id::UInt64
    payload_bytes::Int
    base_send_time::Float64
    deadline::Float64
    paths::Vector{PathOption}

    function RedundancyRequest(
        logical_message_id::Integer,
        payload_bytes::Integer,
        base_send_time::Real,
        deadline::Real,
        paths::AbstractVector{PathOption},
    )
        logical_message_id >= 0 || throw(ArgumentError("logical message id must be nonnegative"))
        payload_bytes >= 0 || throw(ArgumentError("payload bytes must be nonnegative"))
        start = _finite_nonnegative("base send time", base_send_time)
        limit = _finite_nonnegative("delivery deadline", deadline)
        limit >= start || throw(ArgumentError("delivery deadline cannot precede base send time"))
        copied_paths = copy(paths)
        isempty(copied_paths) && throw(ArgumentError("redundancy request requires at least one path"))
        allunique(path.path_id for path in copied_paths) ||
            throw(ArgumentError("redundancy request contains duplicate path ids"))
        return new(UInt64(logical_message_id), Int(payload_bytes), start, limit, copied_paths)
    end
end

struct RedundancyPlan
    status::Symbol
    copies::Vector{TransmissionCopy}
    cost::ResourceCost
    on_time_delivery_probability::Float64
    probability_assumption::Symbol
    reason::String

    function RedundancyPlan(
        status::Symbol,
        copies::Vector{TransmissionCopy},
        cost::ResourceCost,
        on_time_delivery_probability::Real,
        probability_assumption::Symbol,
        reason::AbstractString="",
    )
        status in (:ready, :budget_limited, :deadline_infeasible, :risk_unmet, :unbounded) ||
            throw(ArgumentError("unsupported redundancy status: $status"))
        probability = _probability("on-time delivery probability", on_time_delivery_probability)
        return new(status, copy(copies), cost, probability, probability_assumption, String(reason))
    end
end

struct FixedCopiesPolicy <: AbstractRedundancyPolicy
    copies::Int
    spacing::Float64
    probability_assumption::Symbol

    function FixedCopiesPolicy(
        copies::Integer,
        spacing::Real=0.0;
        probability_assumption::Symbol=:independent_copies,
    )
        copies >= 1 || throw(ArgumentError("fixed redundancy copies must be positive"))
        copies <= typemax(UInt32) || throw(ArgumentError("fixed copies exceed TransmissionID capacity"))
        gap = _finite_nonnegative("fixed-copy spacing", spacing)
        probability_assumption in (:independent_copies, :path_correlated) ||
            throw(ArgumentError("unsupported fixed-copy probability assumption"))
        return new(Int(copies), gap, probability_assumption)
    end
end

struct DeadlineRiskCopiesPolicy <: AbstractRedundancyPolicy
    target_delivery_probability::Float64
    maximum_copies::Int
    spacing::Float64

    function DeadlineRiskCopiesPolicy(
        target_delivery_probability::Real;
        maximum_copies::Integer=4,
        spacing::Real=0.0,
    )
        target = _probability(
            "target delivery probability",
            target_delivery_probability;
            allow_zero=false,
        )
        maximum_copies >= 1 || throw(ArgumentError("risk-adaptive maximum copies must be positive"))
        maximum_copies <= typemax(UInt32) ||
            throw(ArgumentError("risk-adaptive copies exceed TransmissionID capacity"))
        gap = _finite_nonnegative("risk-adaptive copy spacing", spacing)
        return new(target, Int(maximum_copies), gap)
    end
end

function _transmission_copy(
    request::RedundancyRequest,
    path::PathOption,
    copy_index::Int,
    send_offset::Float64,
)
    wire_bytes = Base.checked_add(request.payload_bytes, path.overhead_bytes)
    energy = path.fixed_energy + path.energy_per_byte * wire_bytes
    occupancy = path.occupancy_per_byte * wire_bytes
    isfinite(energy) || throw(OverflowError("transmission energy proxy overflowed"))
    isfinite(occupancy) || throw(OverflowError("transmission occupancy proxy overflowed"))
    arrival = request.base_send_time + send_offset + path.causal_delay_bound
    return TransmissionCopy(
        TransmissionID(request.logical_message_id, copy_index),
        path.path_id,
        send_offset,
        arrival,
        request.payload_bytes,
        wire_bytes,
        ResourceCost(1, wire_bytes, energy, occupancy),
    )
end

function _on_time_probability(
    copies::Vector{TransmissionCopy},
    request::RedundancyRequest,
    assumption::Symbol,
)
    on_time = [copy for copy in copies if copy.arrival_upper_bound <= request.deadline]
    isempty(on_time) && return 0.0
    path_probability = Dict(path.path_id => path.delivery_probability for path in request.paths)
    probabilities = if assumption === :path_correlated
        [path_probability[path_id] for path_id in sort!(unique!(getfield.(on_time, :path_id)))]
    else
        [path_probability[copy.path_id] for copy in on_time]
    end
    any(==(1.0), probabilities) && return 1.0
    log_failure = sum(log1p(-probability) for probability in probabilities)
    return -expm1(log_failure)
end

function plan_redundancy(
    policy::FixedCopiesPolicy,
    request::RedundancyRequest,
    budget::ResourceBudget=ResourceBudget(),
)
    finite_paths = sort!(
        [path for path in request.paths if isfinite(path.causal_delay_bound)];
        by=path -> path.path_id,
    )
    isempty(finite_paths) && return RedundancyPlan(
        :unbounded,
        TransmissionCopy[],
        ResourceCost(),
        0.0,
        policy.probability_assumption,
        "no path has a finite causal delay bound",
    )

    copies = TransmissionCopy[]
    total = ResourceCost()
    budget_limited = false
    for copy_index in 1:policy.copies
        path = finite_paths[mod1(copy_index, length(finite_paths))]
        send_offset = (copy_index - 1) * policy.spacing
        copy = _transmission_copy(request, path, copy_index, send_offset)
        proposed = total + copy.cost
        if !within_budget(proposed, budget)
            budget_limited = true
            break
        end
        push!(copies, copy)
        total = proposed
    end
    probability = _on_time_probability(copies, request, policy.probability_assumption)
    status = if budget_limited
        :budget_limited
    elseif probability == 0.0
        :deadline_infeasible
    else
        :ready
    end
    reason = status === :budget_limited ? "hard resource budget prevented requested copies" :
             status === :deadline_infeasible ? "no planned copy arrives by the deadline bound" : ""
    return RedundancyPlan(
        status,
        copies,
        total,
        probability,
        policy.probability_assumption,
        reason,
    )
end

function plan_redundancy(
    policy::DeadlineRiskCopiesPolicy,
    request::RedundancyRequest,
    budget::ResourceBudget=ResourceBudget(),
)
    # One opportunity per declared path makes the independent-path assumption
    # explicit. Correlated failures belong in scenario sensitivity analysis.
    candidates = sort!(
        [path for path in request.paths if isfinite(path.causal_delay_bound)];
        by=path -> (
            -path.delivery_probability,
            path.causal_delay_bound,
            path.overhead_bytes,
            path.path_id,
        ),
    )
    isempty(candidates) && return RedundancyPlan(
        :unbounded,
        TransmissionCopy[],
        ResourceCost(),
        0.0,
        :independent_paths,
        "no path has a finite causal delay bound",
    )

    copies = TransmissionCopy[]
    total = ResourceCost()
    budget_blocked = false
    remaining = copy(candidates)
    while length(copies) < policy.maximum_copies && !isempty(remaining)
        copy_index = length(copies) + 1
        send_offset = (copy_index - 1) * policy.spacing
        selected_index = nothing
        selected_copy = nothing
        for (index, path) in pairs(remaining)
            candidate = _transmission_copy(request, path, copy_index, send_offset)
            candidate.arrival_upper_bound <= request.deadline || continue
            if within_budget(total + candidate.cost, budget)
                selected_index = index
                selected_copy = candidate
                break
            end
            budget_blocked = true
        end
        isnothing(selected_index) && break
        push!(copies, selected_copy::TransmissionCopy)
        total = total + (selected_copy::TransmissionCopy).cost
        deleteat!(remaining, selected_index::Int)
        probability = _on_time_probability(copies, request, :independent_paths)
        probability + 8eps(max(probability, 1.0)) >= policy.target_delivery_probability &&
            return RedundancyPlan(
                :ready,
                copies,
                total,
                probability,
                :independent_paths,
            )
    end

    probability = _on_time_probability(copies, request, :independent_paths)
    status = if budget_blocked
        :budget_limited
    elseif isempty(copies)
        :deadline_infeasible
    else
        :risk_unmet
    end
    reason = status === :budget_limited ? "hard resource budget prevented the risk target" :
             status === :deadline_infeasible ? "no finite path can arrive by the deadline" :
             "available independent paths cannot meet the requested delivery probability"
    return RedundancyPlan(
        status,
        copies,
        total,
        probability,
        :independent_paths,
        reason,
    )
end
