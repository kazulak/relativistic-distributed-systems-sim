# LEGACY EXPLORATORY SCRIPT: not part of the publication analysis pipeline.
# It intentionally preserves historical direct source includes and must run
# under `--project=analysis`; its output is not paper evidence.

using Dates
using StableRNGs

const REPO_SRC = normpath(joinpath(@__DIR__, "..", "..", "..", "src"))
include(joinpath(REPO_SRC, "light_time.jl"))
include(joinpath(REPO_SRC, "raft_baseline.jl"))

const PHASE1_DURATION = 10.0
const PHASE1_C_SIM = 100.0
const PHASE1_SAFETY_EPS = -1.0e-12

function write_csv(path::AbstractString, header, rows)
    open(path, "w") do io
        println(io, join(header, ","))
        for row in rows
            println(io, join(row, ","))
        end
    end
    return path
end

function phase1_betas()
    return [0.05 * i for i in 0:18]
end

function simulate_phase1_baseline(;
    beta::Float64,
    duration::Float64=PHASE1_DURATION,
    c_sim::Float64=PHASE1_C_SIM,
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
    send_time = 0.0
    heartbeats_sent = 0
    while send_time <= duration
        heartbeats_sent += _schedule_heartbeat_round!(events, nodes, last_delivery, seq, send_time, c_sim)
        send_time += heartbeat_dt
    end

    heartbeats_delivered = 0
    false_elections = 0
    safety_violations = 0
    time_any_follower_candidate = 0.0
    last_time = 0.0

    while !isempty(events)
        event = _pop_event!(events)
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
            if s2 < PHASE1_SAFETY_EPS
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

    if any(n -> n.role == Candidate, @view nodes[2:5])
        time_any_follower_candidate += max(0.0, duration - last_time)
    end

    availability = 1.0 - time_any_follower_candidate / duration
    return RaftBaselineResult(
        beta,
        duration,
        heartbeats_sent,
        heartbeats_delivered,
        false_elections,
        safety_violations,
        availability,
    )
end

function run_phase1(; seeds=1:100, betas=phase1_betas(), duration::Float64=PHASE1_DURATION, c_sim::Float64=PHASE1_C_SIM)
    rows = Vector{Vector{Any}}()
    for seed in seeds
        StableRNG(seed)
        for beta in betas
            result = simulate_phase1_baseline(beta=Float64(beta), duration=duration, c_sim=c_sim)
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
    path = joinpath(outdir, "phase1_degradation_$stamp.csv")
    rows = run_phase1()
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
