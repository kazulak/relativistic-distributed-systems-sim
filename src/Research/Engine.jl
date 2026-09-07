struct ResearchSend{M<:RaftMessage}
    envelope::MessageEnvelope{M}
    wire_bytes::Int
end

struct ClientAttemptEvent
    request_id::RequestID
    preferred_node::Union{Nothing,Int}
end

struct ClientReplyEvent
    response::ClientResponse
end

struct ClientDeadlineEvent
    request_id::RequestID
end

struct TransmissionMetadata
    logical_send_coordinate::Float64
    physical_emission_coordinate::Float64
    direct_reception_coordinate::Float64
    queue_delay::Float64
    serialization_delay::Float64
    propagation_delay::Float64
    direct_null_residual::Float64
    wire_bytes::Int
end

mutable struct OperationState
    request::ClientRequest
    kind::Symbol
    invoked_coordinate::Union{Nothing,Float64}
    invoked_local::Union{Nothing,Float64}
    completed_coordinate::Union{Nothing,Float64}
    completed_local::Union{Nothing,Float64}
    outcome::Symbol
    attempts::Int
    deadline_local::Union{Nothing,Float64}
end

mutable struct ResearchRunState
    config::ScenarioConfig
    seed::UInt64
    scheduler::Scheduler
    trace::EventTrace
    transport::TransportState
    cluster::AuditedCluster
    clocks::Dict{Int,AbstractLocalClock}
    rngs::Dict{Int,MersenneTwister}
    timer_epochs::Dict{UInt64,UInt64}
    next_message_id::UInt64
    transmission_metadata::Dict{UInt64,TransmissionMetadata}
    link_free_at::Dict{Tuple{Int,Int},Float64}
    operations::Dict{RequestID,OperationState}
    history::ClientHistory
    completed_requests::Set{RequestID}
    accumulator::MetricsAccumulator
    last_leader::Union{Nothing,Tuple{Term,Int}}
    invariant_ok::Bool
    causal_delivery_ok::Bool
    violations::Vector{String}
    failure_reason::Union{Nothing,String}
    timing::Union{Nothing,RunTimingState}
end

@inline function _mix64(value::UInt64)
    value = xor(value, value >> 30) * UInt64(0xbf58476d1ce4e5b9)
    value = xor(value, value >> 27) * UInt64(0x94d049bb133111eb)
    return xor(value, value >> 31)
end

@inline _random_word(seed::UInt64, identity::UInt64, stream::UInt64) =
    _mix64(seed + identity * UInt64(0x9e3779b97f4a7c15) + stream)

@inline function _uniform01(seed::UInt64, identity::UInt64, stream::UInt64)
    bits = _random_word(seed, identity, stream) >> 11
    return Float64(bits) * 0x1.0p-53
end

function _rng_seed(seed::UInt64, node::Int)
    mixed = _random_word(seed, UInt64(node), UInt64(0x72616674))
    return Int(mod(mixed, UInt64(typemax(Int) - 1))) + 1
end

function _command_bytes(command::Command)
    command isa PutCommand && return 4 + ncodeunits(command.key) + ncodeunits(command.value)
    command isa DeleteCommand && return 4 + ncodeunits(command.key)
    command isa GetCommand && return 4 + ncodeunits(command.key)
    return 1
end

function _wire_bytes(message::RaftMessage, profile::NetworkProfile)
    payload = if message isa RequestVoteRequest
        40
    elseif message isa RequestVoteResponse
        24
    elseif message isa AppendEntriesRequest
        64 + sum((24 + _command_bytes(entry.command) for entry in message.entries); init=0)
    elseif message isa AppendEntriesResponse
        48
    else
        throw(ArgumentError("unsupported Raft message for byte accounting"))
    end
    return profile.framing_bytes + payload
end

function _protocol_identity(effect::SendMessage)
    message = effect.message
    if message isa AppendEntriesRequest
        return (effect.from, effect.to, :append_request, message.rpc_id)
    elseif message isa AppendEntriesResponse
        return (effect.from, effect.to, :append_response, message.rpc_id)
    elseif message isa RequestVoteRequest
        return (effect.from, effect.to, :vote_request, UInt64(message.term))
    end
    return (effect.from, effect.to, :vote_response, UInt64(message.term))
end

function _active_leader(state::ResearchRunState)
    leaders = sort!(
        [node for node in values(state.cluster.nodes) if node.running && node.volatile.role == Leader];
        by=node -> node.id,
    )
    return length(leaders) == 1 ? leaders[1] : nothing
end

function _account_leader_time!(state::ResearchRunState, next_coordinate::Float64)
    metrics = state.accumulator
    window = state.config.window
    interval_start = max(metrics.last_account_coordinate, window.warmup_end_coordinate)
    interval_end = min(next_coordinate, window.measurement_end_coordinate)
    if interval_end > interval_start && !isnothing(_active_leader(state))
        metrics.leader_coordinate_time += interval_end - interval_start
    end
    metrics.last_account_coordinate = next_coordinate
    return nothing
end

function _observe_transition!(
    state::ResearchRunState,
    before_role::Role,
    before_term::Term,
    node_id::Int,
)
    node = state.cluster.nodes[node_id]
    if node.durable.current_term > before_term && node.volatile.role == Candidate
        state.accumulator.elections_started += 1
        if !isnothing(state.timing)
            state.timing.election_fires += 1
            runtime = get(state.timing.runtimes, node_id, nothing)
            !isnothing(runtime) && note_election_started!(runtime)
            if !isnothing(_active_leader(state))
                state.timing.suspicions += 1
            elseif !isempty(state.timing.open_crashes)
                resolved = nothing
                for (crashed, coordinate) in state.timing.open_crashes
                    if isnothing(resolved) || coordinate > resolved[2]
                        resolved = (crashed, coordinate)
                    end
                end
                delay = proper_time_between(
                    state.config.spacetime,
                    state.config.worldlines[node_id],
                    resolved[2],
                    state.scheduler.now,
                )
                push!(state.timing.detection_delays_proper, Float64(delay))
                filter!(entry -> entry !== resolved, state.timing.open_crashes)
            end
        end
    end
    state.accumulator.maximum_term = max(
        state.accumulator.maximum_term,
        maximum(candidate.durable.current_term for candidate in values(state.cluster.nodes)),
    )
    leader = _active_leader(state)
    if !isnothing(leader)
        identity = (leader.durable.current_term, leader.id)
        push!(state.accumulator.leaders_observed, identity)
        if !isnothing(state.last_leader) && state.last_leader != identity
            state.accumulator.leader_changes += 1
        end
        state.last_leader = identity
    elseif before_role == Leader && node.volatile.role != Leader
        # Preserve the last observed identity across an unwritable interval;
        # the next distinct leader is then counted as a change.
    end
    return nothing
end

function _apply_transition!(state::ResearchRunState, node_id::Int, input::NodeInput, parent::UInt64)
    node = state.cluster.nodes[node_id]
    before_role = node.volatile.role
    before_term = node.durable.current_term
    now_local = local_time(state.clocks[node_id], state.scheduler.now)
    effects = try
        transition!(state.cluster, node_id, input, now_local, state.rngs[node_id])
    catch error
        if error isa InvariantViolation
            state.invariant_ok = false
            append!(state.violations, error.violations)
        end
        rethrow()
    end
    _observe_transition!(state, before_role, before_term, node_id)
    _apply_effects!(state, effects, parent)
    return effects
end

function _schedule_timer!(state::ResearchRunState, effect::ResetTimer, parent)
    timer_name = effect.kind == ElectionTimer ? :election : :heartbeat
    deadline_local = effect.deadline_local
    if !isnothing(state.timing) &&
           effect.kind === ElectionTimer &&
           haskey(state.timing.runtimes, effect.node)
        # Multiplicative timeout scaling: keep the node's own randomized draw,
        # scale its span toward the policy band's midpoint. This preserves the
        # de-synchronization that makes elections resolvable while letting the
        # policy shorten or lengthen timeouts from observed arrivals.
        runtime = state.timing.runtimes[effect.node]
        spec = state.timing.spec
        now_local = local_time(state.clocks[effect.node], state.scheduler.now)
        armed_span = effect.deadline_local - now_local
        armed_span > 0.0 || (armed_span = spec.base_timeout)
        band_lo, band_hi = election_band(runtime, spec)
        target_midpoint = (band_lo + band_hi) / 2
        expected_internal =
            (
                state.config.raft.election_timeout_min +
                state.config.raft.election_timeout_max
            ) / 2
        scale = clamp(target_midpoint / expected_internal, 0.25, 4.0)
        new_span = clamp(armed_span * scale, spec.budget.minimum, spec.budget.maximum)
        deadline_local = now_local + new_span
        Raft.rearm_election_deadline!(
            state.cluster.nodes[effect.node],
            now_local,
            new_span,
        )
    end
    event = schedule_local_timer!(
        state.scheduler,
        state.clocks[effect.node],
        deadline_local,
        effect.node,
        timer_name,
        effect.generation;
        causal_parent=parent,
    )
    state.timer_epochs[event.event_id] = effect.crash_epoch
    return event
end

function _apply_effects!(state::ResearchRunState, effects, parent)
    for effect in effects
        if effect isa ResetTimer
            _schedule_timer!(state, effect, parent)
        elseif effect isa SendMessage
            state.next_message_id == typemax(UInt64) &&
                throw(OverflowError("research message id exhausted"))
            wire_bytes = _wire_bytes(effect.message, state.config.network)
            if !isnothing(state.timing) &&
                   state.timing.spec.level >= 1 &&
                   effect.message isa AppendEntriesRequest
                leader = _active_leader(state)
                if !isnothing(leader) && leader.id == effect.from &&
                       leader.durable.current_term == UInt64(effect.message.term)
                    state.timing.heartbeat_sequences[effect.from] += UInt64(1)
                    sequence = state.timing.heartbeat_sequences[effect.from]
                    tau_emit = local_time(state.clocks[effect.from], state.scheduler.now)
                    state.timing.heartbeat_meta[state.next_message_id + UInt64(1)] =
                        (sequence, tau_emit)
                    surcharge = metadata_byte_surcharge(state.timing.spec.level)
                    wire_bytes += surcharge
                    state.timing.metadata_bytes_sent += surcharge
                end
            end
            state.next_message_id += 1
            envelope = MessageEnvelope(
                state.next_message_id,
                effect.from,
                effect.to,
                effect.message,
            )
            schedule!(
                state.scheduler,
                state.scheduler.now,
                effect.from,
                ResearchSend(envelope, wire_bytes);
                causal_parent=parent,
            )
            state.accumulator.messages_sent += 1
            state.accumulator.bytes_sent += wire_bytes
            identity = _protocol_identity(effect)
            if identity in state.accumulator.seen_protocol_messages
                state.accumulator.protocol_retries += 1
            else
                push!(state.accumulator.seen_protocol_messages, identity)
            end
        elseif effect isa ReplyClient
            haskey(state.operations, effect.response.request_id) ||
                throw(ArgumentError("Raft replied to an unknown research client request"))
            schedule!(
                state.scheduler,
                state.scheduler.now,
                state.config.workload.client_node,
                ClientReplyEvent(effect.response);
                causal_parent=parent,
            )
        end
    end
    return nothing
end

function _delivery_validator(state::ResearchRunState, from::Int, to::Int, logical_send::Float64)
    send_event = worldline_event(state.config.worldlines[from], logical_send)
    return (_, arrival) -> is_future_causal(
        state.config.spacetime,
        send_event,
        worldline_event(state.config.worldlines[to], arrival),
    )
end

function _transmit!(state::ResearchRunState, event::ScheduledEvent, send::ResearchSend)
    envelope = send.envelope
    profile = state.config.network
    link = (envelope.from, envelope.to)
    if !is_link_available(state.transport, envelope.from, envelope.to) ||
       _uniform01(state.seed, envelope.message_id, UInt64(0x10)) < profile.loss_probability
        state.accumulator.transport_drops += 1
        return nothing
    end

    queue_start = max(event.time, get(state.link_free_at, link, event.time))
    serialization = send.wire_bytes / profile.bandwidth_bytes_per_time
    physical_emission = queue_start + serialization
    isfinite(physical_emission) || throw(OverflowError("physical emission time overflowed"))
    state.link_free_at[link] = physical_emission
    intersection = try
        light_cone_intersection(
            state.config.spacetime,
            worldline_event(state.config.worldlines[envelope.from], physical_emission),
            state.config.worldlines[envelope.to];
            max_coordinate_time=max(
                state.config.window.censor_coordinate + 100state.config.raft.election_timeout_max,
                physical_emission + 100state.config.raft.election_timeout_max,
            ),
        )
    catch error
        if error isa NoFutureLightConeIntersection || error isa LightConeSearchExhausted
            state.accumulator.transport_drops += 1
            return nothing
        end
        rethrow(error)
    end
    jitter = profile.delay_jitter *
             _uniform01(state.seed, envelope.message_id, UInt64(0x20))
    direct_reception = Float64(intersection.reception.t)
    base_arrival = direct_reception + profile.processing_delay + jitter
    first_arrival = base_arrival
    if _uniform01(state.seed, envelope.message_id, UInt64(0x30)) < profile.reorder_probability
        first_arrival += profile.reorder_delay
    end
    arrivals = Float64[first_arrival]
    if _uniform01(state.seed, envelope.message_id, UInt64(0x40)) < profile.duplicate_probability
        push!(arrivals, base_arrival + profile.duplicate_delay)
        state.accumulator.transport_duplicates += 1
    end
    metadata = TransmissionMetadata(
        event.time,
        physical_emission,
        direct_reception,
        queue_start - event.time,
        serialization,
        direct_reception - physical_emission,
        Float64(intersection.scaled_residual),
        send.wire_bytes,
    )
    state.transmission_metadata[envelope.message_id] = metadata
    deliveries = try
        enqueue_transmission!(
            state.scheduler,
            state.transport,
            envelope,
            DeliveryPlan(arrivals);
            causal_parent=event.event_id,
            delivery_validator=_delivery_validator(
                state,
                envelope.from,
                envelope.to,
                event.time,
            ),
        )
    catch error
        error isa InvalidDeliveryError && (state.causal_delivery_ok = false)
        rethrow()
    end
    isempty(deliveries) && (state.accumulator.transport_drops += 1)
    return nothing
end

function _deliver!(state::ResearchRunState, event::ScheduledEvent, delivery::MessageDelivery)
    envelope = delivery.envelope
    metadata = get(state.transmission_metadata, envelope.message_id, nothing)
    isnothing(metadata) && throw(ArgumentError("delivery has no matching transmission metadata"))
    send_event = worldline_event(
        state.config.worldlines[envelope.from],
        metadata.logical_send_coordinate,
    )
    receive_event = worldline_event(state.config.worldlines[envelope.to], event.time)
    if !is_future_causal(state.config.spacetime, send_event, receive_event)
        state.causal_delivery_ok = false
        push!(state.violations, "message $(envelope.message_id) was delivered outside its sender's future light cone")
        throw(InvalidDeliveryError(last(state.violations)))
    end
    state.accumulator.message_copies_delivered += 1
    state.accumulator.bytes_delivered += metadata.wire_bytes
    push!(
        state.accumulator.causal_delays,
        CausalDelayMetric(
            envelope.message_id,
            delivery.copy,
            envelope.from,
            envelope.to,
            metadata.logical_send_coordinate,
            metadata.physical_emission_coordinate,
            metadata.direct_reception_coordinate,
            event.time,
            metadata.queue_delay,
            metadata.serialization_delay,
            metadata.propagation_delay,
            event.time - metadata.direct_reception_coordinate,
            metadata.direct_null_residual,
        ),
    )
    _observe_heartbeat_delivery!(state, envelope, event)
    _apply_transition!(
        state,
        envelope.to,
        MessageInput(envelope.from, envelope.payload),
        event.event_id,
    )
    return nothing
end

function _observe_heartbeat_delivery!(state::ResearchRunState, envelope::MessageEnvelope, event::ScheduledEvent)
    isnothing(state.timing) && return nothing
    envelope.payload isa AppendEntriesRequest || return nothing
    meta = get(state.timing.heartbeat_meta, envelope.message_id, nothing)
    runtime = get(state.timing.runtimes, envelope.to, nothing)
    isnothing(runtime) && return nothing
    tau_arrive = local_time(state.clocks[envelope.to], event.time)
    observe_arrival!(
        runtime,
        state.timing.spec,
        isnothing(meta) ? nothing : meta[1],
        isnothing(meta) ? nothing : meta[2],
        tau_arrive,
    )
    note_leader_traffic!(runtime)
    return nothing
end

function _operation_command(sequence::Int, workload::WorkloadSpec)
    if workload.read_every > 0 && sequence % workload.read_every == 0
        key_sequence = max(sequence - 1, 1)
        return GetCommand("rq1-key-$key_sequence"), :read
    end
    return PutCommand("rq1-key-$sequence", "value-$sequence"), :write
end

function _schedule_workload!(state::ResearchRunState)
    workload = state.config.workload
    client_clock = state.clocks[workload.client_node]
    measurement_start_local = local_time(
        client_clock,
        state.config.window.warmup_end_coordinate,
    )
    for sequence in 1:workload.operation_count
        command, kind = _operation_command(sequence, workload)
        request_id = RequestID(workload.client_node, sequence)
        request = ClientRequest(request_id, command)
        state.operations[request_id] = OperationState(
            request,
            kind,
            nothing,
            nothing,
            nothing,
            nothing,
            :scheduled,
            0,
            nothing,
        )
        invocation_local = measurement_start_local + workload.start_offset_proper +
                           (sequence - 1) * workload.interval_proper
        schedule!(
            state.scheduler,
            coordinate_time(client_clock, invocation_local),
            workload.client_node,
            ClientAttemptEvent(request_id, nothing),
        )
    end
    return nothing
end

function _attempt_client!(state::ResearchRunState, event::ScheduledEvent, attempt::ClientAttemptEvent)
    operation = state.operations[attempt.request_id]
    operation.outcome in (:committed, :censored) && return nothing
    client_node = state.config.workload.client_node
    client_local = local_time(state.clocks[client_node], event.time)
    if operation.outcome == :scheduled
        operation.outcome = :pending
        operation.invoked_coordinate = event.time
        operation.invoked_local = client_local
        operation.deadline_local = client_local + state.config.workload.deadline_proper
        record_invocation!(
            state.history,
            operation.request;
            predecessors=sort!(collect(state.completed_requests)),
        )
        deadline_coordinate = coordinate_time(state.clocks[client_node], operation.deadline_local)
        schedule!(
            state.scheduler,
            deadline_coordinate,
            client_node,
            ClientDeadlineEvent(operation.request.request_id);
            causal_parent=event.event_id,
        )
    end
    client_local < operation.deadline_local || return nothing
    preferred = attempt.preferred_node
    active = _active_leader(state)
    target = if !isnothing(preferred) &&
                haskey(state.cluster.nodes, preferred) && state.cluster.nodes[preferred].running
        preferred
    elseif !isnothing(active)
        active.id
    else
        client_node
    end
    operation.attempts += 1
    _apply_transition!(state, target, ClientInput(operation.request), event.event_id)
    return nothing
end

function _client_reply!(state::ResearchRunState, event::ScheduledEvent, reply::ClientReplyEvent)
    response = reply.response
    operation = state.operations[response.request_id]
    operation.outcome in (:committed, :censored) && return nothing
    client_node = state.config.workload.client_node
    client_local = local_time(state.clocks[client_node], event.time)
    if response.status == ClientCommitted
        operation.outcome = :committed
        operation.completed_coordinate = event.time
        operation.completed_local = client_local
        push!(state.completed_requests, response.request_id)
        record_completion!(state.history, response)
        return nothing
    end
    next_local = client_local + state.config.workload.retry_interval_proper
    if next_local < operation.deadline_local
        schedule!(
            state.scheduler,
            coordinate_time(state.clocks[client_node], next_local),
            client_node,
            ClientAttemptEvent(response.request_id, response.leader_hint);
            causal_parent=event.event_id,
        )
    end
    return nothing
end

function _dispatch!(state::ResearchRunState, event::ScheduledEvent)
    payload = event.payload
    if payload isa TimerFired
        epoch = get(state.timer_epochs, event.event_id, nothing)
        isnothing(epoch) && throw(ArgumentError("research timer has no crash epoch"))
        kind = payload.timer == :election ? ElectionTimer :
               payload.timer == :heartbeat ? HeartbeatTimer :
               throw(ArgumentError("unknown research timer kind"))
        _apply_transition!(
            state,
            event.target,
            TimerInput(kind, payload.generation, epoch),
            event.event_id,
        )
    elseif payload isa ResearchSend
        _transmit!(state, event, payload)
    elseif payload isa MessageDelivery
        _deliver!(state, event, payload)
    elseif payload isa CrashNode
        if !isnothing(state.timing)
            push!(state.timing.open_crashes, (payload.node, event.time))
            state.timing.spec.reset_on_crash && reset_runtime!(state.timing, payload.node)
        end
        _apply_transition!(state, payload.node, CrashInput(), event.event_id)
    elseif payload isa RecoverNode
        _apply_transition!(state, payload.node, RecoverInput(), event.event_id)
    elseif payload isa SetLinkAvailability
        apply_fault!(state.transport, payload)
    elseif payload isa ClientAttemptEvent
        _attempt_client!(state, event, payload)
    elseif payload isa ClientReplyEvent
        _client_reply!(state, event, payload)
    elseif payload isa ClientDeadlineEvent
        operation = state.operations[payload.request_id]
        operation.outcome == :pending && (operation.outcome = :censored)
    elseif payload isa ScenarioMarker
        nothing
    else
        throw(ArgumentError("unsupported research event $(typeof(payload))"))
    end
    return nothing
end

function _initialize_state(config::ScenarioConfig, seed::UInt64, timing::Union{Nothing,TimingSpec})
    scheduler = Scheduler(start_time=config.window.start_coordinate)
    clocks = Dict{Int,AbstractLocalClock}()
    rngs = Dict{Int,MersenneTwister}()
    nodes = RaftNode[]
    initial_effects = Dict{Int,Vector{RaftEffect}}()
    for node_id in config.raft.members
        clock = ProperTimeClock(
            config.spacetime,
            config.worldlines[node_id];
            coordinate_origin=config.window.start_coordinate,
        )
        rng = MersenneTwister(_rng_seed(seed, node_id))
        node = RaftNode(node_id, config.raft)
        effects = initialize!(node, local_time(clock, config.window.start_coordinate), rng)
        clocks[node_id] = clock
        rngs[node_id] = rng
        initial_effects[node_id] = effects
        push!(nodes, node)
    end
    state = ResearchRunState(
        config,
        seed,
        scheduler,
        EventTrace(),
        TransportState(),
        AuditedCluster(nodes),
        clocks,
        rngs,
        Dict{UInt64,UInt64}(),
        0,
        Dict{UInt64,TransmissionMetadata}(),
        Dict{Tuple{Int,Int},Float64}(),
        Dict{RequestID,OperationState}(),
        ClientHistory(),
        Set{RequestID}(),
        MetricsAccumulator(config.window.start_coordinate),
        nothing,
        true,
        true,
        String[],
        nothing,
        isnothing(timing) ? nothing : RunTimingState(timing, collect(config.raft.members)),
    )
    for node_id in config.raft.members
        _apply_effects!(state, initial_effects[node_id], nothing)
    end
    for fault in config.faults
        schedule_fault!(state.scheduler, fault.coordinate_time, fault.fault)
    end
    schedule!(
        state.scheduler,
        config.window.warmup_end_coordinate,
        1,
        ScenarioMarker(:measurement_start),
    )
    schedule!(
        state.scheduler,
        config.window.measurement_end_coordinate,
        1,
        ScenarioMarker(:measurement_end),
    )
    schedule!(
        state.scheduler,
        config.window.censor_coordinate,
        1,
        ScenarioMarker(:censor),
    )
    _schedule_workload!(state)
    return state
end

function _exception_text(error)
    io = IOBuffer()
    showerror(io, error)
    return "$(nameof(typeof(error))): $(String(take!(io)))"
end

function _operation_metrics(state::ResearchRunState)
    results = OperationMetric[]
    for request_id in sort!(collect(keys(state.operations)))
        operation = state.operations[request_id]
        operation.outcome in (:scheduled, :pending) && (operation.outcome = :censored)
        invoked_coordinate = something(operation.invoked_coordinate, state.config.window.censor_coordinate)
        invoked_local = something(
            operation.invoked_local,
            local_time(state.clocks[state.config.workload.client_node], invoked_coordinate),
        )
        latency = isnothing(operation.completed_local) ? nothing :
                  operation.completed_local - invoked_local
        push!(
            results,
            OperationMetric(
                request_id,
                operation.kind,
                invoked_coordinate,
                invoked_local,
                operation.completed_coordinate,
                operation.completed_local,
                latency,
                operation.outcome,
                operation.attempts,
            ),
        )
    end
    return results
end

function _final_metrics(state::ResearchRunState, operations::Vector{OperationMetric})
    committed = filter(operation -> operation.outcome == :committed, operations)
    latencies = Float64[operation.latency_proper::Float64 for operation in committed]
    measurement_duration = state.config.window.measurement_end_coordinate -
                           state.config.window.warmup_end_coordinate
    return RunMetrics(
        state.accumulator.elections_started,
        Int(state.accumulator.maximum_term),
        length(state.accumulator.leaders_observed),
        state.accumulator.leader_changes,
        clamp(state.accumulator.leader_coordinate_time / measurement_duration, 0.0, 1.0),
        length(committed),
        count(operation -> operation.operation_kind == :write, committed),
        count(operation -> operation.operation_kind == :read, committed),
        latencies,
        length(committed) / measurement_duration,
        state.accumulator.messages_sent,
        state.accumulator.message_copies_delivered,
        state.accumulator.bytes_sent,
        state.accumulator.bytes_delivered,
        state.accumulator.protocol_retries,
        state.accumulator.transport_duplicates,
        state.accumulator.transport_drops,
        count(operation -> operation.outcome == :censored, operations),
        copy(state.accumulator.causal_delays),
    )
end

"""
Run standard Raft in one relativistic scenario.

All stochastic choices are functions of the explicit `seed`; Raft owns one
private RNG stream per node, and transport decisions are stateless functions of
the seed and message identity. No global RNG or wall clock is read.
"""
function run_scenario(
    config::ScenarioConfig;
    seed::Integer=1,
    max_events::Integer=1_000_000,
    timing::Union{Nothing,TimingSpec}=nothing,
)
    validate_config(config)
    seed >= 0 || throw(ArgumentError("research seed must be non-negative"))
    max_events > 0 || throw(ArgumentError("max_events must be positive"))
    seed_value = UInt64(seed)
    state = _initialize_state(config, seed_value, timing)
    processed = 0
    while !isempty(state.scheduler) &&
          peek_next(state.scheduler).time <= config.window.censor_coordinate &&
          processed < max_events
        event = pop_next!(state.scheduler)
        _account_leader_time!(state, event.time)
        try
            record!(state.trace, event)
            _dispatch!(state, event)
        catch error
            state.failure_reason = _exception_text(error)
            push!(state.violations, state.failure_reason)
            break
        end
        processed += 1
    end
    if processed >= max_events && !isempty(state.scheduler) &&
       peek_next(state.scheduler).time <= config.window.censor_coordinate
        state.failure_reason = "event limit $max_events reached before the censor horizon"
        push!(state.violations, state.failure_reason)
    end
    state.accumulator.last_account_coordinate < config.window.measurement_end_coordinate &&
        _account_leader_time!(state, config.window.measurement_end_coordinate)

    trace_ok = try
        validate_trace(state.trace)
    catch error
        push!(state.violations, _exception_text(error))
        false
    end
    history_ok = try
        is_linearizable(
            state.history;
            max_completed=max(12, length(state.completed_requests)),
        )
    catch error
        push!(state.violations, _exception_text(error))
        false
    end
    operations = _operation_metrics(state)
    safety = SafetyOracleFlags(
        state.invariant_ok,
        history_ok,
        state.causal_delivery_ok,
        trace_ok,
        unique(copy(state.violations)),
    )
    safety_ok = safety.raft_invariants && safety.client_history &&
                safety.causal_deliveries && safety.causal_trace
    status = !isnothing(state.failure_reason) ? :failed : safety_ok ? :completed : :invalid
    adaptation = if isnothing(state.timing)
        nothing
    else
        timing_state = state.timing
        elections = max(timing_state.election_fires, 1)
        AdaptationDiagnostics(
            timing_state.spec.arm,
            timing_state.spec.level,
            timing_fingerprint(timing_state.spec),
            timing_state.suspicions,
            timing_state.election_fires,
            timing_state.suspicions / elections,
            copy(timing_state.detection_delays_proper),
            length(timing_state.open_crashes),
            timing_state.metadata_bytes_sent,
        )
    end
    return RunResult(
        config.name,
        config.family,
        seed_value,
        config_fingerprint(config),
        status,
        state.failure_reason,
        dimensionless_parameters(config),
        safety,
        _final_metrics(state, operations),
        operations,
        state.trace,
        adaptation,
    )
end

function compare_standard_baselines(configs::AbstractVector{ScenarioConfig}; seed::Integer=1)
    isempty(configs) && throw(ArgumentError("baseline comparison requires at least one scenario"))
    control_index = findfirst(config -> config.family == ColocatedControl, configs)
    isnothing(control_index) && throw(ArgumentError("baseline comparison requires a co-located control"))
    control = run_scenario(configs[control_index]; seed=seed)
    return BaselineComparison[
        BaselineComparison(control, run_scenario(config; seed=seed))
        for (index, config) in enumerate(configs) if index != control_index
    ]
end
