# LEGACY EXPLORATORY SCRIPT: not part of the publication analysis pipeline.
# It intentionally preserves historical direct source includes and must run
# under `--project=analysis`; its output is not paper evidence.

using Dates
using StableRNGs
using StaticArrays

include("../src/light_time.jl")
include("../src/raft_baseline.jl")
include("../src/tvat.jl")

const PHASE2_DURATION = 10.0
const PHASE2_C_SIM = 100.0
const PHASE2_SAFETY_EPS = -1.0e-12

struct Phase2Message
    from::Int
    to::Int
    term::Int
    kind::Symbol
    send_time::Float64
    send_position::SVector{3,Float64}
    delta_tau_emit::Float64
end

struct Phase2Event
    time::Float64
    seq::Int
    kind::Symbol
    node::Int
    message::Phase2Message
end

struct Phase2Result
    beta::Float64
    duration::Float64
    heartbeats_sent::Int
    heartbeats_delivered::Int
    false_elections::Int
    safety_violations::Int
    availability::Float64
end

function write_csv(path::AbstractString, header, rows)
    open(path, "w") do io
        println(io, join(header, ","))
        for row in rows
            println(io, join(row, ","))
        end
    end
    return path
end

function phase2_betas()
    return [0.05 * i for i in 0:18]
end

function phase2_empty_message()
    return Phase2Message(0, 0, 0, :none, 0.0, SVector{3,Float64}(0.0, 0.0, 0.0), 0.0)
end

function push_phase2_event!(events::Vector{Phase2Event}, event::Phase2Event)
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

function pop_phase2_event!(events::Vector{Phase2Event})::Phase2Event
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

function schedule_phase2_delivery!(
    events::Vector{Phase2Event},
    nodes::Vector{RaftNode},
    last_delivery::Matrix{Float64},
    seq::Base.RefValue{Int},
    msg::Phase2Message,
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
    push_phase2_event!(events, Phase2Event(delivery, seq[], :deliver, msg.to, msg))
    return delivery
end

function schedule_phase2_heartbeat_round!(
    events::Vector{Phase2Event},
    nodes::Vector{RaftNode},
    last_delivery::Matrix{Float64},
    seq::Base.RefValue{Int},
    send_time::Float64,
    delta_tau_emit::Float64,
    c_sim::Float64,
)::Int
    leader = nodes[1]
    sent = 0
    for to in 2:5
        msg = Phase2Message(
            1,
            to,
            leader.term,
            :heartbeat,
            send_time,
            raft_position(leader, send_time),
            delta_tau_emit,
        )
        schedule_phase2_delivery!(events, nodes, last_delivery, seq, msg, c_sim)
        sent += 1
    end
    return sent
end

function simulate_phase2_tvat(;
    seed::Int,
    beta::Float64,
    duration::Float64=PHASE2_DURATION,
    c_sim::Float64=PHASE2_C_SIM,
)::Phase2Result
    rng = StableRNG(seed)
    nodes = init_raft_baseline(beta=beta, c_sim=c_sim)
    events = Phase2Event[]
    last_delivery = fill(-Inf, 5, 5)
    seq = Ref(0)
    empty_msg = phase2_empty_message()
    follower_states = [init_tvat_follower_state(RAFT_FOLLOWER_TIMEOUT) for _ in 1:5]

    heartbeat_gamma = raft_gamma(beta)
    send_time = 0.0
    heartbeat_seq = 1
    heartbeats_sent = 0
    while send_time <= duration
        heartbeat = tvat_heartbeat(rng, 1, nodes[1].term, heartbeat_seq, send_time, RAFT_HEARTBEAT_PROPER)
        heartbeats_sent += schedule_phase2_heartbeat_round!(
            events,
            nodes,
            last_delivery,
            seq,
            send_time,
            heartbeat.delta_tau_emit,
            c_sim,
        )
        send_time += heartbeat_gamma * heartbeat.delta_tau_emit
        heartbeat_seq += 1
    end

    heartbeats_delivered = 0
    false_elections = 0
    safety_violations = 0
    time_any_follower_candidate = 0.0
    last_time = 0.0

    while !isempty(events)
        event = pop_phase2_event!(events)
        event.time > duration && break

        if any(n -> n.role == Candidate, @view nodes[2:5])
            time_any_follower_candidate += event.time - last_time
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
            if s2 < PHASE2_SAFETY_EPS
                safety_violations += 1
            end

            state = tvat_observe_heartbeat(
                follower_states[event.node],
                TVATHeartbeat(
                    event.message.from,
                    event.message.term,
                    heartbeats_delivered + 1,
                    event.message.send_time,
                    event.message.delta_tau_emit,
                ),
                event.time,
                RAFT_FOLLOWER_TIMEOUT,
            )
            follower_states[event.node] = state

            if event.message.term >= follower.term
                nodes[event.node] = RaftNode(
                    follower.id,
                    Follower,
                    event.message.term,
                    follower.voted_for,
                    event.time + state.timeout,
                    follower.x0,
                    follower.v,
                )
                seq[] += 1
                push_phase2_event!(events, Phase2Event(event.time + state.timeout, seq[], :timeout, event.node, empty_msg))
            end
            heartbeats_delivered += 1
        elseif event.kind === :timeout
            follower = nodes[event.node]
            if follower_states[event.node].initialized && follower.role == Follower && event.time >= follower.timeout_deadline
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

    if any(n -> n.role == Candidate, @view nodes[2:5])
        time_any_follower_candidate += max(0.0, duration - last_time)
    end

    return Phase2Result(
        beta,
        duration,
        heartbeats_sent,
        heartbeats_delivered,
        false_elections,
        safety_violations,
        1.0 - time_any_follower_candidate / duration,
    )
end

function run_phase2(; seeds=1:100, betas=phase2_betas(), duration::Float64=PHASE2_DURATION, c_sim::Float64=PHASE2_C_SIM)
    rows = Vector{Vector{Any}}()
    for seed in seeds
        for beta in betas
            result = simulate_phase2_tvat(seed=seed, beta=Float64(beta), duration=duration, c_sim=c_sim)
            push!(
                rows,
                Any[
                    seed,
                    result.beta,
                    result.duration,
                    result.heartbeats_sent,
                    result.heartbeats_delivered,
                    result.false_elections,
                    result.safety_violations,
                    result.availability,
                ],
            )
        end
    end
    return rows
end

function main()
    root = normpath(joinpath(@__DIR__, ".."))
    outdir = joinpath(root, "results")
    mkpath(outdir)

    stamp = Dates.format(now(), "yyyymmdd_HHMMSS")
    path = joinpath(outdir, "phase2_tvat_$stamp.csv")
    rows = run_phase2()
    write_csv(
        path,
        [
            "seed",
            "beta",
            "duration",
            "heartbeats_sent",
            "heartbeats_delivered",
            "false_elections",
            "safety_violations",
            "availability",
        ],
        rows,
    )
    println(path)
    return path
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
