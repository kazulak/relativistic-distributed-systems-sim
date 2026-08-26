function _next_generation(generation::UInt64)
    generation == typemax(UInt64) && throw(OverflowError("timer generation exhausted"))
    return generation + 1
end

function _persist!(effects::Vector{RaftEffect}, node::RaftNode)
    push!(effects, PersistState(node.id, DurableSnapshot(node.durable)))
    return effects
end

function _reset_election!(
    effects::Vector{RaftEffect},
    node::RaftNode,
    local_now::Float64,
    rng::AbstractRNG,
)
    state = node.volatile
    state.election_generation = _next_generation(state.election_generation)
    spread = node.config.election_timeout_max - node.config.election_timeout_min
    state.election_deadline = local_now + node.config.election_timeout_min + spread * rand(rng)
    isfinite(state.election_deadline) || throw(OverflowError("election deadline overflow"))
    push!(
        effects,
        ResetTimer(
            node.id,
            ElectionTimer,
            state.election_generation,
            node.crash_epoch,
            state.election_deadline,
        ),
    )
    return effects
end

function _reset_heartbeat!(effects::Vector{RaftEffect}, node::RaftNode, local_now::Float64)
    state = node.volatile
    state.heartbeat_generation = _next_generation(state.heartbeat_generation)
    state.heartbeat_deadline = local_now + node.config.heartbeat_interval
    isfinite(state.heartbeat_deadline) || throw(OverflowError("heartbeat deadline overflow"))
    push!(
        effects,
        ResetTimer(
            node.id,
            HeartbeatTimer,
            state.heartbeat_generation,
            node.crash_epoch,
            state.heartbeat_deadline,
        ),
    )
    return effects
end

function _cancel_timer!(effects::Vector{RaftEffect}, node::RaftNode, kind::TimerKind)
    state = node.volatile
    if kind == ElectionTimer
        state.election_generation = _next_generation(state.election_generation)
        state.election_deadline = Inf
        generation = state.election_generation
    else
        state.heartbeat_generation = _next_generation(state.heartbeat_generation)
        state.heartbeat_deadline = Inf
        generation = state.heartbeat_generation
    end
    push!(effects, CancelTimer(node.id, kind, generation, node.crash_epoch))
    return effects
end

function _clear_leader_state!(state::VolatileState)
    empty!(state.next_index)
    empty!(state.match_index)
    empty!(state.append_rpc_counter)
    empty!(state.active_append_rpc)
    empty!(state.latest_success_rpc)
    empty!(state.append_probes)
    empty!(state.votes_received)
    empty!(state.pending_clients)
    return state
end

function _become_follower!(
    effects::Vector{RaftEffect},
    node::RaftNode;
    leader_id::Union{Nothing,NodeID}=nothing,
)
    state = node.volatile
    was_leader = state.role == Leader
    state.role = Follower
    state.leader_id = leader_id
    _clear_leader_state!(state)
    was_leader && _cancel_timer!(effects, node, HeartbeatTimer)
    return effects
end

function _advance_term!(effects::Vector{RaftEffect}, node::RaftNode, term::Term)
    term > node.durable.current_term || return false
    node.durable.current_term = term
    node.durable.voted_for = nothing
    _persist!(effects, node)
    _become_follower!(effects, node)
    return true
end

function _send!(effects::Vector{RaftEffect}, node::RaftNode, to::NodeID, message::RaftMessage)
    to in node.config.members || throw(ArgumentError("message recipient is outside membership"))
    to != node.id || throw(ArgumentError("Raft does not transport messages to self"))
    push!(effects, SendMessage(node.id, to, message))
    return effects
end

function _next_append_rpc!(node::RaftNode, follower::NodeID)
    state = node.volatile
    current = get(state.append_rpc_counter, follower, zero(UInt64))
    current == typemax(UInt64) && throw(OverflowError("AppendEntries RPC id exhausted"))
    rpc_id = current + 1
    state.append_rpc_counter[follower] = rpc_id
    state.active_append_rpc[follower] = rpc_id
    return rpc_id
end

function _append_request(node::RaftNode, follower::NodeID)
    state = node.volatile
    next_index = get(state.next_index, follower, last_log_index(node) + 1)
    next_index = clamp(next_index, 1, last_log_index(node) + 1)
    previous_index = next_index - 1
    previous_term = previous_index == 0 ? zero(Term) : node.durable.log[previous_index].term
    final_index = min(last_log_index(node), next_index + node.config.append_batch_size - 1)
    entries = next_index <= final_index ? copy(node.durable.log[next_index:final_index]) : LogEntry[]
    active_rpc = get(state.active_append_rpc, follower, zero(UInt64))
    active_probe = get(state.append_probes, (follower, active_rpc), nothing)
    rpc_id = if !isnothing(active_probe) &&
                active_probe.prev_log_index == previous_index &&
                active_probe.last_log_index == final_index
        # Retransmissions of one logical range share correlation identity, so
        # an RTT spanning many heartbeat periods cannot make every response
        # appear stale merely because another copy was sent.
        active_rpc
    else
        generated = _next_append_rpc!(node, follower)
        state.append_probes[(follower, generated)] =
            AppendProbe(generated, previous_index, final_index)
        generated
    end
    return AppendEntriesRequest(
        node.durable.current_term,
        node.id,
        previous_index,
        previous_term,
        entries,
        state.commit_index,
        rpc_id,
    )
end

function _send_append!(effects::Vector{RaftEffect}, node::RaftNode, follower::NodeID)
    return _send!(effects, node, follower, _append_request(node, follower))
end

function _broadcast_append!(effects::Vector{RaftEffect}, node::RaftNode)
    for follower in peer_ids(node)
        _send_append!(effects, node, follower)
    end
    return effects
end

function _start_election!(
    effects::Vector{RaftEffect},
    node::RaftNode,
    local_now::Float64,
    rng::AbstractRNG,
)
    node.durable.current_term == typemax(Term) && throw(OverflowError("Raft term exhausted"))
    node.durable.current_term += 1
    node.durable.voted_for = node.id
    _persist!(effects, node)

    state = node.volatile
    state.role = Candidate
    state.leader_id = nothing
    _clear_leader_state!(state)
    push!(state.votes_received, node.id)
    _reset_election!(effects, node, local_now, rng)

    request = RequestVoteRequest(
        node.durable.current_term,
        node.id,
        last_log_index(node),
        last_log_term(node),
    )
    for peer in peer_ids(node)
        _send!(effects, node, peer, request)
    end
    return effects
end

function _become_leader!(effects::Vector{RaftEffect}, node::RaftNode, local_now::Float64)
    state = node.volatile
    state.role = Leader
    state.leader_id = node.id
    empty!(state.votes_received)
    empty!(state.next_index)
    empty!(state.match_index)
    next_index = last_log_index(node) + 1
    for member in node.config.members
        state.next_index[member] = next_index
        state.match_index[member] = member == node.id ? last_log_index(node) : 0
        state.append_rpc_counter[member] = 0
        state.active_append_rpc[member] = 0
        state.latest_success_rpc[member] = 0
    end
    _cancel_timer!(effects, node, ElectionTimer)
    _broadcast_append!(effects, node)
    _reset_heartbeat!(effects, node, local_now)
    return effects
end

function initialize!(node::RaftNode, local_now::Real, rng::AbstractRNG)
    now = Float64(local_now)
    isfinite(now) || throw(ArgumentError("local time must be finite"))
    now >= node.last_local_time || throw(ArgumentError("node-local time moved backwards"))
    node.last_local_time = now
    effects = RaftEffect[]
    node.running && _reset_election!(effects, node, now, rng)
    return effects
end

"""
Re-arm only the election-deadline bookkeeping to `local_now + timeout`.

This changes WHEN the existing election timer may next fire; it adds no
transition, consumes no RNG draws, and touches no voting/log/quorum state,
so every safety-relevant transition remains exactly as specified. Runners
use it to apply external timing-policy bands at the scheduler boundary.
"""
function rearm_election_deadline!(node::RaftNode, local_now::Real, timeout::Real)
    now = Float64(local_now)
    span = Float64(timeout)
    isfinite(now) || throw(ArgumentError("local time must be finite"))
    isfinite(span) && span > 0.0 ||
        throw(ArgumentError("election timeout must be finite and positive"))
    now >= node.last_local_time - 8eps(max(abs(now), 1.0)) ||
        throw(ArgumentError("node-local time moved backwards"))
    node.volatile.election_deadline = now + span
    return node
end

function _execute_command!(machine::Dict{String,String}, command::PutCommand)
    previous = get(machine, command.key, nothing)
    machine[command.key] = command.value
    return CommandResult(:ok, previous)
end

function _execute_command!(machine::Dict{String,String}, command::DeleteCommand)
    previous = pop!(machine, command.key, nothing)
    return CommandResult(:ok, previous)
end

function _execute_command!(machine::Dict{String,String}, command::GetCommand)
    return CommandResult(:ok, get(machine, command.key, nothing))
end

_execute_command!(::Dict{String,String}, ::NoOpCommand) = CommandResult(:noop, nothing)

function _apply_committed!(effects::Vector{RaftEffect}, node::RaftNode)
    state = node.volatile
    while state.last_applied < state.commit_index
        index = state.last_applied + 1
        entry = node.durable.log[index]
        if isnothing(entry.request_id)
            _execute_command!(state.state_machine, entry.command)
        else
            request_id = entry.request_id::RequestID
            record = get(state.applied_requests, request_id, nothing)
            if isnothing(record)
                result = _execute_command!(state.state_machine, entry.command)
                record = AppliedRecord(index, entry.command, result)
                state.applied_requests[request_id] = record
            elseif record.command != entry.command
                throw(AssertionError("one client request id names different commands"))
            end
            if state.role == Leader && request_id in state.pending_clients
                delete!(state.pending_clients, request_id)
                response = ClientResponse(request_id, ClientCommitted, record.result, node.id)
                push!(effects, ReplyClient(node.id, response))
            end
        end
        state.last_applied = index
    end
    return effects
end

function _advance_commit!(effects::Vector{RaftEffect}, node::RaftNode)
    state = node.volatile
    old_commit = state.commit_index
    for index in last_log_index(node):-1:(old_commit + 1)
        node.durable.log[index].term == node.durable.current_term || continue
        replicated = count(member -> get(state.match_index, member, 0) >= index, node.config.members)
        if replicated >= quorum_size(node.config)
            state.commit_index = index
            break
        end
    end
    _apply_committed!(effects, node)
    return state.commit_index > old_commit
end

function _handle_vote_request!(
    effects::Vector{RaftEffect},
    node::RaftNode,
    from::NodeID,
    request::RequestVoteRequest,
    local_now::Float64,
    rng::AbstractRNG,
    advanced_term::Bool,
)
    request.candidate_id == from || throw(ArgumentError("candidate id disagrees with sender"))
    if request.term < node.durable.current_term
        return _send!(
            effects,
            node,
            from,
            RequestVoteResponse(node.durable.current_term, node.id, false),
        )
    end

    up_to_date = (request.last_log_term, request.last_log_index) >=
                 (last_log_term(node), last_log_index(node))
    can_vote = isnothing(node.durable.voted_for) || node.durable.voted_for == from
    grant = can_vote && up_to_date
    if grant
        if node.durable.voted_for != from
            node.durable.voted_for = from
            _persist!(effects, node)
        end
        _reset_election!(effects, node, local_now, rng)
    elseif advanced_term
        _reset_election!(effects, node, local_now, rng)
    end
    return _send!(
        effects,
        node,
        from,
        RequestVoteResponse(node.durable.current_term, node.id, grant),
    )
end

function _handle_vote_response!(
    effects::Vector{RaftEffect},
    node::RaftNode,
    from::NodeID,
    response::RequestVoteResponse,
    local_now::Float64,
    rng::AbstractRNG,
    advanced_term::Bool,
)
    response.voter_id == from || throw(ArgumentError("voter id disagrees with sender"))
    if advanced_term
        _reset_election!(effects, node, local_now, rng)
        return effects
    end
    response.term == node.durable.current_term || return effects
    node.volatile.role == Candidate || return effects
    response.vote_granted || return effects
    push!(node.volatile.votes_received, from)
    if length(node.volatile.votes_received) >= quorum_size(node.config)
        _become_leader!(effects, node, local_now)
    end
    return effects
end

function _append_conflict(node::RaftNode, request::AppendEntriesRequest)
    if request.prev_log_index > last_log_index(node)
        return last_log_index(node) + 1, nothing
    end
    request.prev_log_index == 0 && return 0, nothing
    local_term = node.durable.log[request.prev_log_index].term
    local_term == request.prev_log_term && return 0, nothing
    first_index = request.prev_log_index
    while first_index > 1 && node.durable.log[first_index - 1].term == local_term
        first_index -= 1
    end
    return first_index, local_term
end

function _merge_entries!(effects::Vector{RaftEffect}, node::RaftNode, request::AppendEntriesRequest)
    changed = false
    for (offset, incoming) in enumerate(request.entries)
        index = request.prev_log_index + offset
        if index <= last_log_index(node)
            existing = node.durable.log[index]
            if existing.term != incoming.term
                resize!(node.durable.log, index - 1)
                append!(node.durable.log, request.entries[offset:end])
                changed = true
                break
            elseif existing != incoming
                throw(AssertionError("same-term entries at one index contain different commands"))
            end
        else
            append!(node.durable.log, request.entries[offset:end])
            changed = true
            break
        end
    end
    changed && _persist!(effects, node)
    return changed
end

function _handle_append_request!(
    effects::Vector{RaftEffect},
    node::RaftNode,
    from::NodeID,
    request::AppendEntriesRequest,
    local_now::Float64,
    rng::AbstractRNG,
)
    request.leader_id == from || throw(ArgumentError("leader id disagrees with sender"))
    if request.term < node.durable.current_term
        response = AppendEntriesResponse(
            node.durable.current_term,
            node.id,
            false,
            0,
            last_log_index(node) + 1,
            nothing,
            request.rpc_id,
            request.prev_log_index,
        )
        return _send!(effects, node, from, response)
    end

    node.volatile.role != Follower && _become_follower!(effects, node; leader_id=from)
    node.volatile.leader_id = from
    _reset_election!(effects, node, local_now, rng)

    conflict_index, conflict_term = _append_conflict(node, request)
    if conflict_index != 0
        response = AppendEntriesResponse(
            node.durable.current_term,
            node.id,
            false,
            0,
            conflict_index,
            conflict_term,
            request.rpc_id,
            request.prev_log_index,
        )
        return _send!(effects, node, from, response)
    end

    _merge_entries!(effects, node, request)
    if request.leader_commit > node.volatile.commit_index
        # Figure 2's "index of last new entry" is the prefix this RPC proved,
        # not the follower's potentially divergent durable suffix.
        acknowledged_prefix = request.prev_log_index + length(request.entries)
        node.volatile.commit_index = min(
            request.leader_commit,
            acknowledged_prefix,
            last_log_index(node),
        )
        _apply_committed!(effects, node)
    end
    match_index = request.prev_log_index + length(request.entries)
    response = AppendEntriesResponse(
        node.durable.current_term,
        node.id,
        true,
        match_index,
        1,
        nothing,
        request.rpc_id,
        request.prev_log_index,
    )
    return _send!(effects, node, from, response)
end

function _retry_index(
    node::RaftNode,
    response::AppendEntriesResponse,
    probe::AppendProbe,
)
    state = node.volatile
    candidate = response.conflict_index
    if !isnothing(response.conflict_term)
        last_with_term = findlast(entry -> entry.term == response.conflict_term, node.durable.log)
        candidate = isnothing(last_with_term) ? response.conflict_index : last_with_term + 1
    end
    candidate = min(candidate, max(probe.prev_log_index, 1))
    return clamp(max(candidate, get(state.match_index, response.follower_id, 0) + 1), 1, last_log_index(node) + 1)
end

function _handle_append_response!(
    effects::Vector{RaftEffect},
    node::RaftNode,
    from::NodeID,
    response::AppendEntriesResponse,
    local_now::Float64,
    rng::AbstractRNG,
    advanced_term::Bool,
)
    response.follower_id == from || throw(ArgumentError("follower id disagrees with sender"))
    if advanced_term
        _reset_election!(effects, node, local_now, rng)
        return effects
    end
    response.term == node.durable.current_term || return effects
    node.volatile.role == Leader || return effects

    state = node.volatile
    probe_key = (from, response.rpc_id)
    probe = get(state.append_probes, probe_key, nothing)
    # Unknown responses are duplicates, responses from a prior leadership
    # incarnation, or malformed synthetic inputs. None may alter leader state.
    isnothing(probe) && return effects
    if response.request_prev_log_index != probe.prev_log_index
        delete!(state.append_probes, probe_key)
        return effects
    end
    if response.success
        if response.match_index != probe.last_log_index
            delete!(state.append_probes, probe_key)
            return effects
        end
        response.match_index <= last_log_index(node) ||
            throw(AssertionError("follower acknowledged beyond the leader log"))
        delete!(state.append_probes, probe_key)
        response.match_index > get(state.match_index, from, 0) || return effects
        state.latest_success_rpc[from] = max(
            get(state.latest_success_rpc, from, zero(UInt64)),
            response.rpc_id,
        )
        state.match_index[from] = max(get(state.match_index, from, 0), response.match_index)
        state.next_index[from] = max(get(state.next_index, from, 1), state.match_index[from] + 1)
        for (key, prior) in collect(state.append_probes)
            key[1] == from && prior.last_log_index <= state.match_index[from] || continue
            delete!(state.append_probes, key)
        end
        committed = _advance_commit!(effects, node)
        targets = Set{NodeID}()
        state.next_index[from] <= last_log_index(node) && push!(targets, from)
        committed && union!(targets, peer_ids(node))
        for follower in node.config.members
            follower in targets && _send_append!(effects, node, follower)
        end
    else
        active_rpc = get(state.active_append_rpc, from, zero(UInt64))
        active_probe = get(state.append_probes, (from, active_rpc), nothing)
        # A delayed rejection remains applicable when it rejects the same
        # prefix as the currently active logical probe. A newer success that
        # proves this prefix raises matchIndex and therefore dominates it.
        if isnothing(active_probe) ||
           probe.prev_log_index != active_probe.prev_log_index ||
           get(state.match_index, from, 0) >= probe.prev_log_index
            delete!(state.append_probes, probe_key)
            return effects
        end
        for (key, prior) in collect(state.append_probes)
            key[1] == from && prior.prev_log_index == probe.prev_log_index || continue
            delete!(state.append_probes, key)
        end
        state.next_index[from] = _retry_index(node, response, probe)
        _send_append!(effects, node, from)
    end
    return effects
end

_message_term(message::RaftMessage) = message.term

function _handle_message!(
    effects::Vector{RaftEffect},
    node::RaftNode,
    input::MessageInput,
    local_now::Float64,
    rng::AbstractRNG,
)
    input.from in node.config.members || throw(ArgumentError("message sender is outside membership"))
    input.from != node.id || throw(ArgumentError("received a transported self-message"))
    message = input.message
    advanced_term = _advance_term!(effects, node, _message_term(message))

    if message isa RequestVoteRequest
        _handle_vote_request!(effects, node, input.from, message, local_now, rng, advanced_term)
    elseif message isa RequestVoteResponse
        _handle_vote_response!(effects, node, input.from, message, local_now, rng, advanced_term)
    elseif message isa AppendEntriesRequest
        _handle_append_request!(effects, node, input.from, message, local_now, rng)
    elseif message isa AppendEntriesResponse
        _handle_append_response!(effects, node, input.from, message, local_now, rng, advanced_term)
    else
        throw(ArgumentError("unsupported Raft message type"))
    end
    return effects
end

function _handle_timer!(
    effects::Vector{RaftEffect},
    node::RaftNode,
    input::TimerInput,
    local_now::Float64,
    rng::AbstractRNG,
)
    state = node.volatile
    input.crash_epoch == node.crash_epoch || return effects
    if input.kind == ElectionTimer
        input.generation == state.election_generation || return effects
        local_now + 8eps(max(abs(local_now), 1.0)) >= state.election_deadline || return effects
        state.role != Leader && _start_election!(effects, node, local_now, rng)
    else
        input.generation == state.heartbeat_generation || return effects
        local_now + 8eps(max(abs(local_now), 1.0)) >= state.heartbeat_deadline || return effects
        if state.role == Leader
            _broadcast_append!(effects, node)
            _reset_heartbeat!(effects, node, local_now)
        end
    end
    return effects
end

function _find_requests(node::RaftNode, request_id::RequestID)
    return findall(entry -> entry.request_id == request_id, node.durable.log)
end

function _handle_client!(effects::Vector{RaftEffect}, node::RaftNode, request::ClientRequest)
    state = node.volatile
    if state.role != Leader
        response = ClientResponse(request.request_id, ClientNotLeader, nothing, state.leader_id)
        push!(effects, ReplyClient(node.id, response))
        return effects
    end

    applied = get(state.applied_requests, request.request_id, nothing)
    if !isnothing(applied)
        applied.command == request.command ||
            throw(ArgumentError("a request id was reused for a different command"))
        response = ClientResponse(request.request_id, ClientCommitted, applied.result, node.id)
        push!(effects, ReplyClient(node.id, response))
        return effects
    end

    existing_indices = _find_requests(node, request.request_id)
    if isempty(existing_indices)
        push!(
            node.durable.log,
            LogEntry(node.durable.current_term, request.command, request.request_id),
        )
        _persist!(effects, node)
        state.match_index[node.id] = last_log_index(node)
        state.next_index[node.id] = last_log_index(node) + 1
    elseif any(index -> node.durable.log[index].command != request.command, existing_indices)
        throw(ArgumentError("a request id was reused for a different command"))
    elseif all(index -> node.durable.log[index].term != node.durable.current_term, existing_indices)
        # A retry of an uncommitted prior-term request must create current-term
        # progress; Raft leaders commit older entries only alongside a
        # current-term entry. Application remains at-most-once by request id.
        push!(
            node.durable.log,
            LogEntry(node.durable.current_term, request.command, request.request_id),
        )
        _persist!(effects, node)
        state.match_index[node.id] = last_log_index(node)
        state.next_index[node.id] = last_log_index(node) + 1
    end
    push!(state.pending_clients, request.request_id)
    _broadcast_append!(effects, node)
    return effects
end

"""
Apply one deterministic node-local transition.

The caller supplies a node-local monotonic clock observation and a per-node RNG
stream.  The returned effect order is significant: durable writes appear before
messages whose correctness depends on them.
"""
function handle!(node::RaftNode, input::NodeInput, local_now::Real, rng::AbstractRNG)
    now = Float64(local_now)
    isfinite(now) || throw(ArgumentError("local time must be finite"))
    now >= node.last_local_time || throw(ArgumentError("node-local time moved backwards"))
    node.last_local_time = now
    effects = RaftEffect[]

    if input isa CrashInput
        if node.running
            node.running = false
            node.crash_epoch == typemax(UInt64) && throw(OverflowError("crash epoch exhausted"))
            node.crash_epoch += 1
            node.volatile = VolatileState()
        end
        return effects
    elseif input isa RecoverInput
        if !node.running
            node.running = true
            node.volatile = VolatileState()
            _reset_election!(effects, node, now, rng)
        end
        return effects
    end

    node.running || return effects
    if input isa TimerInput
        _handle_timer!(effects, node, input, now, rng)
    elseif input isa MessageInput
        _handle_message!(effects, node, input, now, rng)
    elseif input isa ClientInput
        _handle_client!(effects, node, input.request)
    else
        throw(ArgumentError("unsupported node input"))
    end
    return effects
end
