module ReferenceRaft

export RefConfig, RefNode, RefVoteRequest, RefVoteResponse,
    RefAppendRequest, RefAppendResponse, RefCommand, RefReply,
    RefTimer, RefCrash, RefRecover, RefClientRequest,
    initialize_ref!, ref_step!, ref_visible_state, SafetyMonitor, observe!

struct RefConfig
    members::Vector{Int}
    quorum::Int
end

RefConfig(members) = RefConfig(collect(Int.(members)), (length(members) >>> 1) + 1)

struct RefVoteRequest
    term::Int
    candidate::Int
    last_log_index::Int
    last_log_term::Int
end

struct RefVoteResponse
    term::Int
    voter::Int
    granted::Bool
end

struct RefCommand
    request_id::Any
    kind::Symbol
    key::String
    value::Union{Nothing,String}
end

Base.:(==)(a::RefCommand, b::RefCommand) =
    a.request_id == b.request_id && a.kind == b.kind &&
    a.key == b.key && a.value == b.value

struct RefAppendRequest
    term::Int
    leader::Int
    prev_log_index::Int
    prev_log_term::Int
    entries::Vector{Tuple{Int,RefCommand}}
    leader_commit::Int
end

struct RefAppendResponse
    term::Int
    follower::Int
    success::Bool
    match_index::Int
end

struct RefReply
    request_id::Any
    status::Symbol
    value::Union{Nothing,String}
end

struct RefTimer
    kind::Symbol
end

struct RefCrash end
struct RefRecover end

struct RefClientRequest
    request_id::Any
    command::RefCommand
end

mutable struct SafetyMonitor
    leaders::Dict{Int,Set{Int}}
    applied::Dict{Tuple{Int,Int},RefCommand}
    violations::Vector{String}
end

SafetyMonitor() = SafetyMonitor(Dict{Int,Set{Int}}(), Dict{Tuple{Int,Int},RefCommand}(), String[])

function observe!(monitor::SafetyMonitor, node)
    if node.role == :leader
        leaders = get!(monitor.leaders, node.term, Set{Int}())
        if !(node.id in leaders)
            push!(leaders, node.id)
            length(leaders) > 1 &&
                push!(monitor.violations, "two leaders in term $(node.term)")
        end
    end
    for index in 1:node.last_applied
        entry = node.log[index]
        key = (entry[1], index)
        previous = get(monitor.applied, key, nothing)
        if isnothing(previous)
            monitor.applied[key] = entry[2]
        elseif previous != entry[2]
            push!(
                monitor.violations,
                "state-machine safety violated at term=$(key[1]) index=$(key[2])",
            )
        end
    end
    return monitor
end

mutable struct RefNode
    id::Int
    config::RefConfig
    term::Int
    voted_for::Union{Nothing,Int}
    log::Vector{Tuple{Int,RefCommand}}
    commit_index::Int
    last_applied::Int
    machine::Dict{String,String}
    role::Symbol
    votes_received::Set{Int}
    next_index::Dict{Int,Int}
    match_index::Dict{Int,Int}
    election_armed::Bool
    heartbeat_armed::Bool
    alive::Bool
    pending_clients::Set{Any}
    outbound::Vector{Tuple{Int,Any}}
    replies::Vector{RefReply}
end

function RefNode(id::Integer, config::RefConfig)
    return RefNode(
        Int(id),
        config,
        0,
        nothing,
        Tuple{Int,RefCommand}[],
        0,
        0,
        Dict{String,String}(),
        :follower,
        Set{Int}(),
        Dict{Int,Int}(),
        Dict{Int,Int}(),
        true,
        false,
        true,
        Set{Any}(),
        Tuple{Int,Any}[],
        RefReply[],
    )
end

function initialize_ref!(node::RefNode)
    node.term = 0
    node.voted_for = nothing
    empty!(node.log)
    node.commit_index = 0
    node.last_applied = 0
    empty!(node.machine)
    node.role = :follower
    empty!(node.votes_received)
    empty!(node.next_index)
    empty!(node.match_index)
    node.election_armed = true
    node.heartbeat_armed = false
    node.alive = true
    empty!(node.pending_clients)
    empty!(node.outbound)
    empty!(node.replies)
    return node
end

_ref_last_index(node) = length(node.log)
_ref_last_term(node) = isempty(node.log) ? 0 : node.log[end][1]

function _emit!(node, to, payload)
    push!(node.outbound, (to, payload))
    return node
end

_execute(machine, command::RefCommand) =
    command.kind == :put ? (
        begin
            previous = get(machine, command.key, nothing)
            machine[command.key] = command.value
            previous
        end
    ) :
    command.kind == :delete ? pop!(machine, command.key, nothing) :
    get(machine, command.key, nothing)

function _apply_committed!(node)
    while node.last_applied < min(node.commit_index, length(node.log))
        node.last_applied += 1
        (_, command) = node.log[node.last_applied]
        result = _execute(node.machine, command)
        if !isnothing(command.request_id) &&
           command.request_id in node.pending_clients
            delete!(node.pending_clients, command.request_id)
            push!(node.replies, RefReply(command.request_id, :committed, result))
        end
    end
    return node
end

function ref_step!(node::RefNode, input, monitor::SafetyMonitor)
    empty!(node.outbound)
    empty!(node.replies)
    node.alive || return node
    _dispatch!(node, input)
    node.role == :leader && _leader_maintenance!(node)
    observe!(monitor, node)
    return node
end

function _leader_maintenance!(node)
    for candidate_index in length(node.log):-1:(node.commit_index + 1)
        node.log[candidate_index][1] == node.term || continue
        replicated = count(
            member -> member == node.id ||
                      get(node.match_index, member, 0) >= candidate_index,
            node.config.members,
        )
        if replicated >= node.config.quorum
            node.commit_index = candidate_index
            break
        end
    end
    _apply_committed!(node)
    return node
end

function _dispatch!(node, input)
    if input isa RefTimer
        return _timer!(node, input.kind)
    elseif input isa RefCrash
        node.alive = false
        return node
    elseif input isa RefRecover
        node.role = :follower
        empty!(node.votes_received)
        node.election_armed = true
        node.heartbeat_armed = false
        empty!(node.pending_clients)
        return node
    elseif input isa RefVoteRequest
        return _vote_request!(node, input)
    elseif input isa RefVoteResponse
        return _vote_response!(node, input)
    elseif input isa RefAppendRequest
        return _append_request!(node, input)
    elseif input isa RefAppendResponse
        return _append_response!(node, input)
    elseif input isa RefClientRequest
        return _client_request!(node, input)
    end
    throw(ArgumentError("unsupported reference input $(typeof(input))"))
end

function _timer!(node, kind)
    if kind == :election
        if node.role == :follower && node.election_armed
            return _start_election!(node)
        elseif node.role == :candidate
            return _start_election!(node)
        end
    elseif kind == :heartbeat
        node.role == :leader && node.heartbeat_armed && return _broadcast_append!(node)
    end
    return node
end

function _start_election!(node)
    node.term += 1
    node.role = :candidate
    node.voted_for = node.id
    empty!(node.votes_received)
    push!(node.votes_received, node.id)
    for peer in node.config.members
        peer == node.id && continue
        _emit!(
            node,
            peer,
            RefVoteRequest(node.term, node.id, _ref_last_index(node), _ref_last_term(node)),
        )
    end
    return node
end

function _become_leader!(node)
    node.role = :leader
    for peer in node.config.members
        peer == node.id && continue
        node.next_index[peer] = _ref_last_index(node) + 1
        node.match_index[peer] = 0
    end
    node.election_armed = false
    node.heartbeat_armed = true
    _broadcast_append!(node)
    return node
end

function _broadcast_append!(node)
    for peer in node.config.members
        peer == node.id && continue
        _send_append!(node, peer)
    end
    return node
end

function _send_append!(node, peer)
    previous = get(node.next_index, peer, _ref_last_index(node) + 1) - 1
    previous = clamp(previous, 0, _ref_last_index(node))
    entries = [node.log[i] for i in (previous + 1):length(node.log)]
    _emit!(
        node,
        peer,
        RefAppendRequest(
            node.term,
            node.id,
            previous,
            previous == 0 ? 0 : node.log[previous][1],
            entries,
            node.commit_index,
        ),
    )
    return node
end

function _step_down!(node, term::Int)
    node.term = term
    node.voted_for = nothing
    node.role = :follower
    empty!(node.votes_received)
    empty!(node.pending_clients)
    node.election_armed = true
    node.heartbeat_armed = false
    return node
end

function _vote_request!(node, request::RefVoteRequest)
    granted = false
    if request.term > node.term
        _step_down!(node, request.term)
    end
    if request.term == node.term
        up_to_date =
            (request.last_log_term, request.last_log_index) >=
            (_ref_last_term(node), _ref_last_index(node))
        can_vote =
            isnothing(node.voted_for) || node.voted_for == request.candidate
        granted = can_vote && up_to_date
        if granted
            node.voted_for = request.candidate
            node.election_armed = true
        end
    end
    _emit!(node, request.candidate, RefVoteResponse(node.term, node.id, granted))
    return node
end

function _vote_response!(node, response::RefVoteResponse)
    node.role == :candidate || return node
    response.term > node.term && return _step_down!(node, response.term)
    response.term == node.term || return node
    if response.granted
        push!(node.votes_received, response.voter)
        if length(node.votes_received) >= node.config.quorum
            _become_leader!(node)
        end
    end
    return node
end

function _append_request!(node, request::RefAppendRequest)
    if request.term < node.term
        _emit!(
            node,
            request.leader,
            RefAppendResponse(node.term, node.id, false, 0),
        )
        return node
    end
    if request.term > node.term
        _step_down!(node, request.term)
    elseif node.role == :candidate
        node.role = :follower
        empty!(node.votes_received)
        node.heartbeat_armed = false
        node.election_armed = true
    end
    matched =
        request.prev_log_index <= _ref_last_index(node) &&
        (
            request.prev_log_index == 0 ||
            node.log[request.prev_log_index][1] == request.prev_log_term
        )
    if !matched
        _emit!(
            node,
            request.leader,
            RefAppendResponse(node.term, node.id, false, 0),
        )
        return node
    end
    for (offset, entry) in enumerate(request.entries)
        index = request.prev_log_index + offset
        if index <= length(node.log)
            node.log[index] == entry || (node.log = node.log[1:(index - 1)]; push!(node.log, entry))
        else
            push!(node.log, entry)
        end
    end
    node.election_armed = true
    match = request.prev_log_index + length(request.entries)
    request.leader_commit > node.commit_index &&
        (node.commit_index = min(request.leader_commit, length(node.log)))
    _apply_committed!(node)
    _emit!(node, request.leader, RefAppendResponse(node.term, node.id, true, match))
    return node
end

function _append_response!(node, response::RefAppendResponse)
    node.role == :leader || return node
    response.term > node.term && return _step_down!(node, response.term)
    response.term == node.term || return node
    if response.success
        node.match_index[response.follower] = max(
            get(node.match_index, response.follower, 0),
            response.match_index,
        )
        node.next_index[response.follower] = response.match_index + 1
    else
        lowered = max(1, get(node.next_index, response.follower, 2) - 1)
        node.next_index[response.follower] = lowered
        _send_append!(node, response.follower)
    end
    return node
end

function _client_request!(node, request::RefClientRequest)
    if node.role != :leader
        push!(node.replies, RefReply(request.request_id, :not_leader, nothing))
        return node
    end
    push!(node.pending_clients, request.request_id)
    push!(node.log, (node.term, request.command))
    return node
end

function ref_visible_state(node::RefNode)
    return (
        term=node.term,
        voted_for=node.voted_for,
        role=node.role,
        alive=node.alive,
        log_length=length(node.log),
        commit_index=node.commit_index,
        last_applied=node.last_applied,
        machine=copy(node.machine),
        log=[(term, command.kind, command.key, command.value, command.request_id) for (term, command) in node.log],
    )
end

end
