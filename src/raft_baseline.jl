using StaticArrays

if !isdefined(@__MODULE__, :solve_light_time)
    include("light_time.jl")
end

const RAFT_FOLLOWER_TIMEOUT = 0.150
const RAFT_HEARTBEAT_PROPER = 0.050

@enum RaftRole::UInt8 Follower Candidate Leader

struct RaftNode
    id::Int
    role::RaftRole
    term::Int
    voted_for::Int
    timeout_deadline::Float64
    x0::SVector{3,Float64}
    v::SVector{3,Float64}
end

struct RaftMessage
    from::Int
    to::Int
    term::Int
    kind::Symbol
    send_time::Float64
    send_position::SVector{3,Float64}
end

struct RaftEvent
    time::Float64
    seq::Int
    kind::Symbol
    node::Int
    message::RaftMessage
end

struct RaftBaselineResult
    beta::Float64
    duration::Float64
    heartbeats_sent::Int
    heartbeats_delivered::Int
    false_elections::Int
    safety_violations::Int
    availability::Float64
end

@inline raft_position(node::RaftNode, t::Float64)::SVector{3,Float64} = node.x0 + node.v * t
@inline raft_gamma(beta::Float64)::Float64 = inv(sqrt(1.0 - beta * beta))
@inline raft_proper_to_coordinate(dtau::Float64, beta::Float64)::Float64 = raft_gamma(beta) * dtau

function _empty_message()
    return RaftMessage(0, 0, 0, :none, 0.0, SVector{3,Float64}(0.0, 0.0, 0.0))
end

function _push_event!(events::Vector{RaftEvent}, event::RaftEvent)
    push!(events, event)
    i = length(events)
    while i > 1
        p = i >>> 1
        parent = events[p]
        if parent.time < event.time || (parent.time == event.time && parent.seq <= event.seq)
            break
        end
        events[i] = parent
        i = p
    end
    events[i] = event
    return events
end

function _pop_event!(events::Vector{RaftEvent})::RaftEvent
    event = events[1]
    tail = pop!(events)
    if !isempty(events)
        i = 1
        while true
            left = i << 1
            right = left + 1
            if left > length(events)
                break
            end
            child = left
            if right <= length(events)
                l = events[left]
                r = events[right]
                if r.time < l.time || (r.time == l.time && r.seq < l.seq)
                    child = right
                end
            end
            c = events[child]
            if tail.time < c.time || (tail.time == c.time && tail.seq <= c.seq)
                break
            end
            events[i] = c
            i = child
        end
        events[i] = tail
    end
    return event
end

function init_raft_baseline(; beta::Float64=0.0, c_sim::Float64=100.0)::Vector{RaftNode}
    leader_v = SVector{3,Float64}(beta * c_sim, 0.0, 0.0)
    zero_v = SVector{3,Float64}(0.0, 0.0, 0.0)
    return RaftNode[
        RaftNode(1, Leader, 1, 1, Inf, SVector{3,Float64}(0.0, 0.0, 0.0), leader_v),
        RaftNode(2, Follower, 1, 0, RAFT_FOLLOWER_TIMEOUT, SVector{3,Float64}(100.0, 0.0, 0.0), zero_v),
        RaftNode(3, Follower, 1, 0, RAFT_FOLLOWER_TIMEOUT, SVector{3,Float64}(105.0, 5.0, 0.0), zero_v),
        RaftNode(4, Follower, 1, 0, RAFT_FOLLOWER_TIMEOUT, SVector{3,Float64}(110.0, -5.0, 0.0), zero_v),
        RaftNode(5, Follower, 1, 0, RAFT_FOLLOWER_TIMEOUT, SVector{3,Float64}(115.0, 0.0, 5.0), zero_v),
    ]
end

function _schedule_delivery!(
    events::Vector{RaftEvent},
    nodes::Vector{RaftNode},
    last_delivery::Matrix{Float64},
    seq::Base.RefValue{Int},
    msg::RaftMessage,
    c_sim::Float64,
)
    receiver = nodes[msg.to]
    xB_func(t::Float64)::SVector{3,Float64} = raft_position(receiver, t)
    vB_func(t::Float64)::SVector{3,Float64} = receiver.v
    delivery = solve_light_time(msg.send_time, msg.send_position, xB_func, vB_func, c_sim)
    floor_time = last_delivery[msg.from, msg.to]
    if delivery <= floor_time
        delivery = nextfloat(floor_time)
    end
    last_delivery[msg.from, msg.to] = delivery
    seq[] += 1
    _push_event!(events, RaftEvent(delivery, seq[], :deliver, msg.to, msg))
    return delivery
end

function _schedule_heartbeat_round!(
    events::Vector{RaftEvent},
    nodes::Vector{RaftNode},
    last_delivery::Matrix{Float64},
    seq::Base.RefValue{Int},
    send_time::Float64,
    c_sim::Float64,
)::Int
    leader = nodes[1]
    sent = 0
    for to in 2:5
        msg = RaftMessage(1, to, leader.term, :heartbeat, send_time, raft_position(leader, send_time))
        _schedule_delivery!(events, nodes, last_delivery, seq, msg, c_sim)
        sent += 1
    end
    return sent
end

function simulate_raft_baseline(;
    beta::Float64,
    duration::Float64=5.0,
    c_sim::Float64=100.0,
)::RaftBaselineResult
    nodes = init_raft_baseline(beta=beta, c_sim=c_sim)
    events = RaftEvent[]
    last_delivery = fill(-Inf, 5, 5)
    seq = Ref(0)
    empty_msg = _empty_message()

    for id in 2:5
        seq[] += 1
        _push_event!(events, RaftEvent(RAFT_FOLLOWER_TIMEOUT, seq[], :timeout, id, empty_msg))
    end

    heartbeat_dt = raft_proper_to_coordinate(RAFT_HEARTBEAT_PROPER, beta)
    t = 0.0
    heartbeats_sent = 0
    while t <= duration
        heartbeats_sent += _schedule_heartbeat_round!(events, nodes, last_delivery, seq, t, c_sim)
        t += heartbeat_dt
    end

    heartbeats_delivered = 0
    false_elections = 0
    safety_violations = 0
    stable_time = 0.0
    last_time = 0.0

    while !isempty(events)
        event = _pop_event!(events)
        event.time > duration && break
        if all(n -> n.role != Candidate, @view nodes[2:5])
            stable_time += event.time - last_time
        end
        last_time = event.time

        if event.kind === :deliver && event.message.kind === :heartbeat
            follower = nodes[event.node]
            s2 = minkowski_interval2(
                event.message.send_time,
                event.message.send_position,
                event.time,
                raft_position(follower, event.time),
                c_sim,
            )
            if abs(s2) > 1.0e-8
                safety_violations += 1
            end
            if event.message.term >= follower.term
                nodes[event.node] = RaftNode(
                    follower.id,
                    Follower,
                    event.message.term,
                    follower.voted_for,
                    event.time + RAFT_FOLLOWER_TIMEOUT,
                    follower.x0,
                    follower.v,
                )
                seq[] += 1
                _push_event!(events, RaftEvent(event.time + RAFT_FOLLOWER_TIMEOUT, seq[], :timeout, event.node, empty_msg))
            end
            heartbeats_delivered += 1
        elseif event.kind === :timeout
            follower = nodes[event.node]
            if follower.role == Follower && event.time >= follower.timeout_deadline
                nodes[event.node] = RaftNode(
                    follower.id,
                    Candidate,
                    follower.term + 1,
                    follower.id,
                    Inf,
                    follower.x0,
                    follower.v,
                )
                false_elections += 1
            end
        end
    end

    stable_time += max(0.0, duration - last_time) * (all(n -> n.role != Candidate, @view nodes[2:5]) ? 1.0 : 0.0)
    availability = stable_time / duration
    return RaftBaselineResult(beta, duration, heartbeats_sent, heartbeats_delivered, false_elections, safety_violations, availability)
end
