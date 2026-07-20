module IsolatedRaftTests

using Test
using Random
using RelativisticDistributedSystemsSim
using RelativisticDistributedSystemsSim.SimulationCore
using RelativisticDistributedSystemsSim.Raft

function raft_messages(effects, message_type; to=nothing)
    return [
        effect for effect in effects if effect isa SendMessage &&
        effect.message isa message_type && (isnothing(to) || effect.to == to)
    ]
end

function deliver!(cluster, effect::SendMessage, rngs; increment=0.01)
    recipient = cluster.nodes[effect.to]
    now = recipient.last_local_time + increment
    return transition!(
        cluster,
        effect.to,
        MessageInput(effect.from, effect.message),
        now,
        rngs[effect.to],
    )
end

function initialized_cluster(; logs=Dict{Int,Vector{LogEntry}}(), append_batch_size=2)
    config = RaftConfig(
        [1, 2, 3];
        election_timeout=(1.0, 2.0),
        heartbeat_interval=0.25,
        append_batch_size=append_batch_size,
    )
    rngs = Dict(id => MersenneTwister(100 + id) for id in config.members)
    nodes = RaftNode[]
    for id in config.members
        log = get(logs, id, LogEntry[])
        term = isempty(log) ? 0 : maximum(entry.term for entry in log)
        node = RaftNode(id, config; durable=DurableState(term, nothing, log))
        initialize!(node, 0.0, rngs[id])
        push!(nodes, node)
    end
    return AuditedCluster(nodes), rngs
end

function elect_one!(cluster, rngs; candidate=1, voter=2)
    node = cluster.nodes[candidate]
    election = transition!(
        cluster,
        candidate,
        TimerInput(ElectionTimer, node.volatile.election_generation, node.crash_epoch),
        node.volatile.election_deadline,
        rngs[candidate],
    )
    request = only(raft_messages(election, RequestVoteRequest; to=voter))
    vote_effects = deliver!(cluster, request, rngs)
    response = only(raft_messages(vote_effects, RequestVoteResponse; to=candidate))
    leader_effects = deliver!(cluster, response, rngs)
    @test cluster.nodes[candidate].volatile.role == Leader
    return leader_effects
end

function commit_request!(cluster, rngs, request::ClientRequest; leader=1, follower=2)
    node = cluster.nodes[leader]
    effects = transition!(
        cluster,
        leader,
        ClientInput(request),
        node.last_local_time + 0.01,
        rngs[leader],
    )
    append = only(raft_messages(effects, AppendEntriesRequest; to=follower))
    follower_effects = deliver!(cluster, append, rngs)
    acknowledgement = only(raft_messages(follower_effects, AppendEntriesResponse; to=leader))
    leader_effects = deliver!(cluster, acknowledgement, rngs)
    replies = [effect for effect in leader_effects if effect isa ReplyClient]
    @test length(replies) == 1
    return replies[1].response, leader_effects
end

@testset "generic simulation core" begin
    scheduler = Scheduler(start_time=0.0)
    first = schedule!(scheduler, 2.0, 1, ScenarioMarker(:first))
    second = schedule!(scheduler, 2.0, 2, ScenarioMarker(:second))
    earlier = schedule!(scheduler, 1.0, 1, ScenarioMarker(:earlier))
    @test pop_next!(scheduler).event_id == earlier.event_id
    @test pop_next!(scheduler).event_id == first.event_id
    @test pop_next!(scheduler).event_id == second.event_id
    @test_throws ArgumentError schedule!(scheduler, 1.0, 1, ScenarioMarker(:past))

    clock = AffineLocalClock(0.5, 2.0)
    @test local_time(clock, 4.0) == 4.0
    @test coordinate_time(clock, 4.0) == 4.0
    timer = schedule_local_timer!(scheduler, clock, 4.0, 1, :election, 7)
    @test timer.time == 4.0
    @test timer.payload == TimerFired(:election, 7)

    network = Scheduler()
    envelope = MessageEnvelope(1, 1, 2, :heartbeat)
    duplicate_plan = DeliveryPlan([3.0, 2.0])
    events = enqueue_deliveries!(network, envelope, duplicate_plan)
    @test length(events) == 2
    @test pop_next!(network).payload.copy == 2
    @test pop_next!(network).payload.copy == 1
    @test is_dropped(DeliveryPlan())

    trace = EventTrace()
    event = schedule!(network, 4.0, 1, CrashNode(1))
    record = record!(trace, event)
    @test record.payload_type == :CrashNode
    @test length(trace) == 1
    @test validate_trace(trace)
    detached = trace_records(trace)
    empty!(detached)
    @test length(trace) == 1

    dag = Scheduler()
    parent = schedule!(dag, 2.0, 1, ScenarioMarker(:send))
    @test_throws ArgumentError schedule!(
        dag,
        3.0,
        2,
        ScenarioMarker(:unknown_parent);
        causal_parent=999,
    )
    @test_throws ArgumentError schedule!(
        dag,
        1.0,
        2,
        ScenarioMarker(:past_child);
        causal_parent=parent.event_id,
    )
    child = schedule!(
        dag,
        3.0,
        2,
        ScenarioMarker(:receive);
        causal_parent=parent.event_id,
    )
    dag_trace = EventTrace()
    @test_throws InvalidTraceError record!(dag_trace, child)
    record!(dag_trace, parent)
    record!(dag_trace, child)
    @test validate_trace(dag_trace)
    @test_throws InvalidTraceError record!(dag_trace, child)

    transport_scheduler = Scheduler()
    send_event = schedule!(transport_scheduler, 1.0, 1, ScenarioMarker(:send))
    transport = TransportState()
    link_fault = SetLinkAvailability(1, 2, false)
    apply_fault!(transport, link_fault)
    transport_envelope = MessageEnvelope(2, 1, 2, :payload)
    @test isempty(enqueue_transmission!(
        transport_scheduler,
        transport,
        transport_envelope,
        DeliveryPlan([2.0]);
        causal_parent=send_event.event_id,
    ))
    apply_fault!(transport, SetLinkAvailability(1, 2, true))
    @test_throws InvalidDeliveryError enqueue_transmission!(
        transport_scheduler,
        transport,
        transport_envelope,
        DeliveryPlan([2.0]);
        causal_parent=send_event.event_id,
        delivery_validator=(_, _) -> false,
    )
    delivered = enqueue_transmission!(
        transport_scheduler,
        transport,
        transport_envelope,
        DeliveryPlan([2.0]);
        causal_parent=send_event.event_id,
        delivery_validator=(_, arrival) -> arrival >= 2.0,
    )
    @test length(delivered) == 1
    @test delivered[1].causal_parent == send_event.event_id
end

@testset "configuration and deterministic elections" begin
    @test_throws ArgumentError RaftConfig([1, 2])
    @test_throws ArgumentError RaftConfig([1, 1, 2])
    @test quorum_size(RaftConfig([1, 2, 3, 4, 5])) == 3

    entry = LogEntry(1, PutCommand("owned", "yes"), RequestID(1, 1))
    supplied = DurableState(1, 1, [entry])
    owned_config = RaftConfig([1, 2, 3])
    owned_node = RaftNode(1, owned_config; durable=supplied)
    empty!(supplied.log)
    supplied.current_term = 2
    @test owned_node.durable.current_term == 1
    @test owned_node.durable.log == [entry]
    push!(owned_node.durable.log, LogEntry(1, PutCommand("second", "yes"), RequestID(1, 2)))
    @test isempty(supplied.log)
    duplicate_nodes = [
        RaftNode(1, owned_config),
        RaftNode(1, owned_config),
        RaftNode(2, owned_config),
        RaftNode(3, owned_config),
    ]
    @test_throws ArgumentError AuditedCluster(duplicate_nodes)

    cluster, rngs = initialized_cluster()
    leader_effects = elect_one!(cluster, rngs)
    @test cluster.nodes[1].durable.current_term == 1
    @test cluster.nodes[1].durable.voted_for == 1
    @test cluster.nodes[2].durable.voted_for == 1
    @test length(raft_messages(leader_effects, AppendEntriesRequest)) == 2
    @test any(effect -> effect isa ResetTimer && effect.kind == HeartbeatTimer, leader_effects)
    @test cluster.audit.transitions_checked >= 4

    stale_generation = cluster.nodes[3].volatile.election_generation - 1
    stale = transition!(
        cluster,
        3,
        TimerInput(ElectionTimer, stale_generation, cluster.nodes[3].crash_epoch),
        cluster.nodes[3].last_local_time + 0.01,
        rngs[3],
    )
    @test isempty(stale)
    @test cluster.nodes[3].volatile.role == Follower

    higher_vote = RequestVoteRequest(2, 2, 0, 0)
    transition!(
        cluster,
        1,
        MessageInput(2, higher_vote),
        cluster.nodes[1].last_local_time + 0.01,
        rngs[1],
    )
    @test cluster.nodes[1].volatile.role == Follower
    @test cluster.nodes[1].durable.current_term == 2
end

@testset "split election retry" begin
    cluster, rngs = initialized_cluster()
    for candidate in (1, 2)
        node = cluster.nodes[candidate]
        transition!(
            cluster,
            candidate,
            TimerInput(ElectionTimer, node.volatile.election_generation, node.crash_epoch),
            node.volatile.election_deadline,
            rngs[candidate],
        )
    end
    @test cluster.nodes[1].volatile.role == Candidate
    @test cluster.nodes[2].volatile.role == Candidate
    @test all(node -> node.volatile.role != Leader, values(cluster.nodes))

    candidate = cluster.nodes[1]
    retry = transition!(
        cluster,
        1,
        TimerInput(ElectionTimer, candidate.volatile.election_generation, candidate.crash_epoch),
        candidate.volatile.election_deadline,
        rngs[1],
    )
    @test candidate.durable.current_term == 2
    request = only(raft_messages(retry, RequestVoteRequest; to=3))
    response_effects = deliver!(cluster, request, rngs)
    response = only(raft_messages(response_effects, RequestVoteResponse; to=1))
    deliver!(cluster, response, rngs)
    @test candidate.volatile.role == Leader
end

@testset "replication, majority commit, clients, and recovery" begin
    cluster, rngs = initialized_cluster()
    elect_one!(cluster, rngs)

    put = ClientRequest(RequestID(9, 1), PutCommand("mode", "relativistic"))
    put_response, commit_effects = commit_request!(cluster, rngs, put)
    @test put_response.status == ClientCommitted
    @test put_response.result == CommandResult(:ok, nothing)
    @test cluster.nodes[1].volatile.commit_index == 1
    @test cluster.nodes[1].volatile.state_machine["mode"] == "relativistic"

    for append in raft_messages(commit_effects, AppendEntriesRequest)
        deliver!(cluster, append, rngs)
    end
    @test all(node -> node.volatile.commit_index == 1, values(cluster.nodes))
    @test all(node -> node.volatile.state_machine["mode"] == "relativistic", values(cluster.nodes))

    duplicate_effects = transition!(
        cluster,
        1,
        ClientInput(put),
        cluster.nodes[1].last_local_time + 0.01,
        rngs[1],
    )
    @test length(cluster.nodes[1].durable.log) == 1
    @test only(effect for effect in duplicate_effects if effect isa ReplyClient).response.result ==
          put_response.result

    get_request = ClientRequest(RequestID(9, 2), GetCommand("mode"))
    get_response, _ = commit_request!(cluster, rngs, get_request)
    @test get_response.result == CommandResult(:ok, "relativistic")

    history = ClientHistory()
    record_invocation!(history, put)
    record_completion!(history, put_response)
    record_invocation!(history, get_request; predecessors=[put.request_id])
    record_completion!(history, get_response)
    @test is_linearizable(history)

    durable_before = DurableSnapshot(cluster.nodes[2].durable)
    old_timer = ResetTimer(
        2,
        ElectionTimer,
        cluster.nodes[2].volatile.election_generation,
        cluster.nodes[2].crash_epoch,
        cluster.nodes[2].volatile.election_deadline,
    )
    transition!(
        cluster,
        2,
        CrashInput(),
        cluster.nodes[2].last_local_time + 0.01,
        rngs[2],
    )
    @test DurableSnapshot(cluster.nodes[2].durable) == durable_before
    @test cluster.nodes[2].volatile.commit_index == 0
    transition!(
        cluster,
        2,
        RecoverInput(),
        cluster.nodes[2].last_local_time + 0.01,
        rngs[2],
    )
    stale = transition!(
        cluster,
        2,
        TimerInput(old_timer.kind, old_timer.generation, old_timer.crash_epoch),
        cluster.nodes[2].last_local_time + 0.01,
        rngs[2],
    )
    @test isempty(stale)
    @test cluster.nodes[2].volatile.role == Follower

    leader = cluster.nodes[1]
    heartbeat = AppendEntriesRequest(
        leader.durable.current_term,
        leader.id,
        length(leader.durable.log),
        leader.durable.log[end].term,
        LogEntry[],
        leader.volatile.commit_index,
    )
    deliver!(cluster, SendMessage(1, 2, heartbeat), rngs)
    @test cluster.nodes[2].volatile.commit_index == 2
    @test cluster.nodes[2].volatile.state_machine["mode"] == "relativistic"
    @test all(record -> record.leader_id == 1, values(cluster.audit.commit_provenance))
end

@testset "follower commits only the acknowledged RPC prefix" begin
    config = RaftConfig([1, 2, 3]; append_batch_size=1)
    first = LogEntry(1, PutCommand("first", "1"), RequestID(7, 1))
    second = LogEntry(2, PutCommand("second", "2"), RequestID(7, 2))
    divergent = LogEntry(2, PutCommand("divergent", "bad"), RequestID(7, 3))
    replacement = LogEntry(3, PutCommand("third", "3"), RequestID(7, 4))
    follower = RaftNode(
        2,
        config;
        durable=DurableState(3, nothing, [first, second, divergent]),
    )
    rng = MersenneTwister(202)
    initialize!(follower, 0.0, rng)

    one_entry = AppendEntriesRequest(3, 1, 1, 1, [second], 3, 11)
    effects = handle!(follower, MessageInput(1, one_entry), 0.1, rng)
    acknowledgement = only(raft_messages(effects, AppendEntriesResponse)).message
    @test acknowledgement.success
    @test acknowledgement.match_index == 2
    @test acknowledgement.rpc_id == 11
    @test acknowledgement.request_prev_log_index == 1
    @test follower.volatile.commit_index == 2
    @test follower.volatile.last_applied == 2
    @test !haskey(follower.volatile.state_machine, "divergent")

    heartbeat = AppendEntriesRequest(3, 1, 2, 2, LogEntry[], 3, 12)
    heartbeat_effects = handle!(follower, MessageInput(1, heartbeat), 0.2, rng)
    heartbeat_ack = only(raft_messages(heartbeat_effects, AppendEntriesResponse)).message
    @test heartbeat_ack.match_index == 2
    @test follower.volatile.commit_index == 2
    @test follower.volatile.last_applied == 2

    multi_entry = AppendEntriesRequest(3, 1, 1, 1, [second, replacement], 3, 13)
    multi_effects = handle!(follower, MessageInput(1, multi_entry), 0.3, rng)
    multi_ack = only(raft_messages(multi_effects, AppendEntriesResponse)).message
    @test multi_ack.match_index == 3
    @test follower.durable.log == [first, second, replacement]
    @test follower.volatile.commit_index == 3
    @test follower.volatile.last_applied == 3
    @test follower.volatile.state_machine["third"] == "3"
    @test !haskey(follower.volatile.state_machine, "divergent")

    duplicate_effects = handle!(follower, MessageInput(1, multi_entry), 0.4, rng)
    duplicate_ack = only(raft_messages(duplicate_effects, AppendEntriesResponse)).message
    @test duplicate_ack.match_index == 3
    @test follower.volatile.commit_index == 3
    @test follower.volatile.last_applied == 3
    @test length(follower.volatile.applied_requests) == 3
end

@testset "real batch-size-one catch-up and heartbeat commit" begin
    cluster, rngs = initialized_cluster(append_batch_size=1)
    elect_one!(cluster, rngs)
    for sequence in 1:3
        request = ClientRequest(
            RequestID(44, sequence),
            PutCommand("batch-$sequence", "value-$sequence"),
        )
        response, _ = commit_request!(cluster, rngs, request)
        @test response.status == ClientCommitted
    end
    @test cluster.nodes[1].volatile.commit_index == 3
    @test cluster.nodes[3].volatile.commit_index == 0

    leader = cluster.nodes[1]
    heartbeat_time = max(leader.last_local_time + 0.01, leader.volatile.heartbeat_deadline)
    leader_effects = transition!(
        cluster,
        1,
        TimerInput(HeartbeatTimer, leader.volatile.heartbeat_generation, leader.crash_epoch),
        heartbeat_time,
        rngs[1],
    )
    append = only(raft_messages(leader_effects, AppendEntriesRequest; to=3))
    for expected_index in 1:3
        @test length(append.message.entries) == 1
        @test append.message.prev_log_index == expected_index - 1
        follower_effects = deliver!(cluster, append, rngs)
        @test cluster.nodes[3].volatile.commit_index == expected_index
        @test cluster.nodes[3].volatile.last_applied == expected_index
        acknowledgement = only(raft_messages(follower_effects, AppendEntriesResponse; to=1))
        leader_followup = deliver!(cluster, acknowledgement, rngs)
        if expected_index < 3
            append = only(raft_messages(leader_followup, AppendEntriesRequest; to=3))
        end
    end
    @test cluster.nodes[3].volatile.state_machine == cluster.nodes[1].volatile.state_machine

    leader = cluster.nodes[1]
    heartbeat_time = max(leader.last_local_time + 0.01, leader.volatile.heartbeat_deadline)
    heartbeat_effects = transition!(
        cluster,
        1,
        TimerInput(HeartbeatTimer, leader.volatile.heartbeat_generation, leader.crash_epoch),
        heartbeat_time,
        rngs[1],
    )
    empty_append = only(raft_messages(heartbeat_effects, AppendEntriesRequest; to=3))
    @test isempty(empty_append.message.entries)
    @test empty_append.message.prev_log_index == 3
    first_delivery = deliver!(cluster, empty_append, rngs)
    second_delivery = deliver!(cluster, empty_append, rngs)
    first_ack = only(raft_messages(first_delivery, AppendEntriesResponse; to=1))
    second_ack = only(raft_messages(second_delivery, AppendEntriesResponse; to=1))
    deliver!(cluster, first_ack, rngs)
    duplicate_result = deliver!(cluster, second_ack, rngs)
    @test isempty(duplicate_result)
    @test cluster.nodes[3].volatile.commit_index == 3
    @test cluster.nodes[3].volatile.last_applied == 3
end

@testset "AppendEntries response correlation and stale hints" begin
    entry = LogEntry(1, PutCommand("probe", "value"), RequestID(5, 1))
    cluster, rngs = initialized_cluster(logs=Dict(1 => [entry], 2 => [entry]))
    leader_effects = elect_one!(cluster, rngs)
    initial = only(raft_messages(leader_effects, AppendEntriesRequest; to=3))
    rejected_effects = deliver!(cluster, initial, rngs)
    rejection = only(raft_messages(rejected_effects, AppendEntriesResponse; to=1))
    retry_effects = deliver!(cluster, rejection, rngs)
    retry = only(raft_messages(retry_effects, AppendEntriesRequest; to=3))
    next_before_duplicate = cluster.nodes[1].volatile.next_index[3]
    duplicate_failure = deliver!(cluster, rejection, rngs)
    @test isempty(duplicate_failure)
    @test cluster.nodes[1].volatile.next_index[3] == next_before_duplicate

    accepted_effects = deliver!(cluster, retry, rngs)
    accepted = only(raft_messages(accepted_effects, AppendEntriesResponse; to=1))
    deliver!(cluster, accepted, rngs)
    @test cluster.nodes[1].volatile.match_index[3] == 1
    @test cluster.nodes[1].volatile.next_index[3] == 2
    stale_after_success = deliver!(cluster, rejection, rngs)
    @test isempty(stale_after_success)
    @test cluster.nodes[1].volatile.next_index[3] == 2

    leader = cluster.nodes[1]
    first_time = max(leader.last_local_time + 0.01, leader.volatile.heartbeat_deadline)
    first_round = transition!(
        cluster,
        1,
        TimerInput(HeartbeatTimer, leader.volatile.heartbeat_generation, leader.crash_epoch),
        first_time,
        rngs[1],
    )
    older_probe = only(raft_messages(first_round, AppendEntriesRequest; to=3))
    leader = cluster.nodes[1]
    second_time = max(leader.last_local_time + 0.01, leader.volatile.heartbeat_deadline)
    second_round = transition!(
        cluster,
        1,
        TimerInput(HeartbeatTimer, leader.volatile.heartbeat_generation, leader.crash_epoch),
        second_time,
        rngs[1],
    )
    newer_probe = only(raft_messages(second_round, AppendEntriesRequest; to=3))
    older_response = only(raft_messages(deliver!(cluster, older_probe, rngs), AppendEntriesResponse; to=1))
    newer_response = only(raft_messages(deliver!(cluster, newer_probe, rngs), AppendEntriesResponse; to=1))
    deliver!(cluster, newer_response, rngs)
    reordered_old_success = deliver!(cluster, older_response, rngs)
    @test isempty(reordered_old_success)
    @test cluster.nodes[1].volatile.match_index[3] == 1
    @test cluster.nodes[1].volatile.next_index[3] == 2

    active_rpc = cluster.nodes[1].volatile.active_append_rpc[3]
    stale_hint = AppendEntriesResponse(
        cluster.nodes[1].durable.current_term,
        3,
        false,
        0,
        10_000,
        1,
        active_rpc - 1,
        1,
    )
    ignored_hint = transition!(
        cluster,
        1,
        MessageInput(3, stale_hint),
        cluster.nodes[1].last_local_time + 0.01,
        rngs[1],
    )
    @test isempty(ignored_hint)
    @test cluster.nodes[1].volatile.next_index[3] == 2

    @test_throws ArgumentError AppendEntriesResponse(2, 3, false, 0, 1, 3, 9, 1)
    @test_throws ArgumentError AppendEntriesResponse(2, 3, false, 0, 1, -1, 9, 1)
    @test_throws ArgumentError AppendEntriesResponse(2, 3, true, 1, 1, 1, 9, 1)
end

@testset "reliable RTT longer than multiple heartbeat periods" begin
    entry = LogEntry(1, PutCommand("slow-link", "caught-up"), RequestID(66, 1))
    cluster, rngs = initialized_cluster(
        logs=Dict(1 => [entry], 2 => [entry]),
        append_batch_size=1,
    )
    leader_effects = elect_one!(cluster, rngs)
    initial_probe = only(raft_messages(leader_effects, AppendEntriesRequest; to=3))
    delayed_rejection = only(
        raft_messages(deliver!(cluster, initial_probe, rngs), AppendEntriesResponse; to=1),
    )

    rejection_retransmissions = SendMessage[]
    for _ in 1:4
        leader = cluster.nodes[1]
        timer_time = max(leader.last_local_time + 0.01, leader.volatile.heartbeat_deadline)
        round = transition!(
            cluster,
            1,
            TimerInput(HeartbeatTimer, leader.volatile.heartbeat_generation, leader.crash_epoch),
            timer_time,
            rngs[1],
        )
        retransmission = only(raft_messages(round, AppendEntriesRequest; to=3))
        @test retransmission.message.rpc_id == initial_probe.message.rpc_id
        @test retransmission.message.prev_log_index == 1
        push!(rejection_retransmissions, retransmission)
    end

    retry_effects = deliver!(cluster, delayed_rejection, rngs)
    retry = only(raft_messages(retry_effects, AppendEntriesRequest; to=3))
    @test retry.message.prev_log_index == 0
    @test retry.message.rpc_id != initial_probe.message.rpc_id
    delayed_success = only(
        raft_messages(deliver!(cluster, retry, rngs), AppendEntriesResponse; to=1),
    )

    success_retransmissions = SendMessage[]
    for _ in 1:4
        leader = cluster.nodes[1]
        timer_time = max(leader.last_local_time + 0.01, leader.volatile.heartbeat_deadline)
        round = transition!(
            cluster,
            1,
            TimerInput(HeartbeatTimer, leader.volatile.heartbeat_generation, leader.crash_epoch),
            timer_time,
            rngs[1],
        )
        retransmission = only(raft_messages(round, AppendEntriesRequest; to=3))
        @test retransmission.message.rpc_id == retry.message.rpc_id
        @test retransmission.message.prev_log_index == 0
        push!(success_retransmissions, retransmission)
    end

    deliver!(cluster, delayed_success, rngs)
    @test cluster.nodes[1].volatile.match_index[3] == 1
    @test cluster.nodes[1].volatile.next_index[3] == 2
    @test cluster.nodes[3].durable.log == [entry]

    duplicate_rejection = deliver!(cluster, delayed_rejection, rngs)
    @test isempty(duplicate_rejection)
    @test cluster.nodes[1].volatile.next_index[3] == 2

    delayed_duplicate_success = only(
        raft_messages(
            deliver!(cluster, success_retransmissions[end], rngs),
            AppendEntriesResponse;
            to=1,
        ),
    )
    ignored_duplicate_success = deliver!(cluster, delayed_duplicate_success, rngs)
    @test isempty(ignored_duplicate_success)
    @test cluster.nodes[1].volatile.match_index[3] == 1

    delayed_old_request = rejection_retransmissions[1]
    out_of_order_success = only(
        raft_messages(deliver!(cluster, delayed_old_request, rngs), AppendEntriesResponse; to=1),
    )
    @test out_of_order_success.message.success
    @test isempty(deliver!(cluster, out_of_order_success, rngs))
    @test cluster.nodes[1].volatile.next_index[3] == 2
end

@testset "conflict retry catches up a missing follower" begin
    entry = LogEntry(1, PutCommand("x", "1"), RequestID(1, 1))
    cluster, rngs = initialized_cluster(logs=Dict(1 => [entry], 2 => [entry]))
    leader_effects = elect_one!(cluster, rngs)
    initial = only(raft_messages(leader_effects, AppendEntriesRequest; to=3))
    @test initial.message.prev_log_index == 1
    rejection_effects = deliver!(cluster, initial, rngs)
    rejection = only(raft_messages(rejection_effects, AppendEntriesResponse; to=1))
    @test !rejection.message.success
    retry_effects = deliver!(cluster, rejection, rngs)
    retry = only(raft_messages(retry_effects, AppendEntriesRequest; to=3))
    @test retry.message.prev_log_index == 0
    @test retry.message.entries == [entry]
    acknowledgement_effects = deliver!(cluster, retry, rngs)
    acknowledgement = only(raft_messages(acknowledgement_effects, AppendEntriesResponse; to=1))
    deliver!(cluster, acknowledgement, rngs)
    @test cluster.nodes[3].durable.log == [entry]

    retried = ClientRequest(RequestID(1, 1), PutCommand("x", "1"))
    response, _ = commit_request!(cluster, rngs, retried)
    @test response.status == ClientCommitted
    @test cluster.nodes[1].volatile.commit_index == 2
    @test length(cluster.nodes[1].volatile.applied_requests) == 1
end

@testset "invariant oracle detects injected faults" begin
    config = RaftConfig([1, 2, 3])
    first = LogEntry(1, PutCommand("a", "1"), RequestID(1, 1))
    conflicting = LogEntry(1, PutCommand("a", "2"), RequestID(2, 1))
    nodes = [
        RaftNode(1, config; durable=DurableState(1, nothing, [first])),
        RaftNode(2, config; durable=DurableState(1, nothing, [conflicting])),
        RaftNode(3, config; durable=DurableState()),
    ]
    report = check_invariants!(InvariantAudit(), nodes)
    @test !report.ok
    @test any(contains("log matching"), report.violations)

    provenance_config = RaftConfig([1, 2, 3])
    provenance_nodes = [RaftNode(id, provenance_config) for id in 1:3]
    provenance_rngs = Dict(id => MersenneTwister(700 + id) for id in 1:3)
    for node in provenance_nodes
        initialize!(node, 0.0, provenance_rngs[node.id])
    end
    provenance_cluster = AuditedCluster(provenance_nodes)
    fabricated = AppendEntriesRequest(1, 1, 0, 0, [first], 1, 77)
    @test_throws InvariantViolation transition!(
        provenance_cluster,
        2,
        MessageInput(1, fabricated),
        0.1,
        provenance_rngs[2],
    )
end

function randomized_replay(seed)
    cluster, rngs = initialized_cluster(append_batch_size=1)
    pending = SendMessage[]
    append!(pending, [effect for effect in elect_one!(cluster, rngs) if effect isa SendMessage])
    scenario_rng = MersenneTwister(seed)
    next_request = 1

    for step in 1:480
        if step % 20 == 1 && next_request <= 10 && cluster.nodes[1].volatile.role == Leader
            request = ClientRequest(
                RequestID(88, next_request),
                PutCommand("random-$next_request", "value-$next_request"),
            )
            effects = transition!(
                cluster,
                1,
                ClientInput(request),
                cluster.nodes[1].last_local_time + 0.01,
                rngs[1],
            )
            append!(pending, [effect for effect in effects if effect isa SendMessage])
            next_request += 1
        end

        if step == 75
            transition!(
                cluster,
                3,
                CrashInput(),
                cluster.nodes[3].last_local_time + 0.01,
                rngs[3],
            )
        elseif step == 105
            transition!(
                cluster,
                3,
                RecoverInput(),
                cluster.nodes[3].last_local_time + 0.01,
                rngs[3],
            )
        end

        if step % 17 == 0 && cluster.nodes[1].volatile.role == Leader
            leader = cluster.nodes[1]
            timer_time = max(leader.last_local_time + 0.01, leader.volatile.heartbeat_deadline)
            effects = transition!(
                cluster,
                1,
                TimerInput(HeartbeatTimer, leader.volatile.heartbeat_generation, leader.crash_epoch),
                timer_time,
                rngs[1],
            )
            append!(pending, [effect for effect in effects if effect isa SendMessage])
        end

        isempty(pending) && continue
        index = rand(scenario_rng, eachindex(pending))
        message = pending[index]
        action = rand(scenario_rng)
        if action < 0.18
            deleteat!(pending, index) # loss
            continue
        elseif action >= 0.42
            deleteat!(pending, index) # ordinary delivery
        end # otherwise retain one copy to model duplication/reordering
        effects = deliver!(cluster, message, rngs; increment=0.001)
        append!(pending, [effect for effect in effects if effect isa SendMessage])
    end

    assert_invariants!(cluster.audit, values(cluster.nodes))
    return (
        [DurableSnapshot(cluster.nodes[id].durable) for id in 1:3],
        [cluster.nodes[id].durable.current_term for id in 1:3],
        [cluster.nodes[id].volatile.role for id in 1:3],
        [cluster.nodes[id].volatile.commit_index for id in 1:3],
        [copy(cluster.nodes[id].volatile.state_machine) for id in 1:3],
        cluster.audit.transitions_checked,
    )
end

@testset "randomized loss, duplication, reordering, and deterministic replay" begin
    first_replay = randomized_replay(0x5eed)
    second_replay = randomized_replay(0x5eed)
    @test first_replay == second_replay
    @test first_replay[6] > 200
end

end
