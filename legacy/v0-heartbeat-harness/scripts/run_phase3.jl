# LEGACY EXPLORATORY SCRIPT: not part of the publication analysis pipeline.
# It intentionally preserves historical direct source includes and must run
# under `--project=analysis`; its output is not paper evidence.

using Dates
using StableRNGs
using StaticArrays

const REPO_SRC = normpath(joinpath(@__DIR__, "..", "..", "..", "src"))
include(joinpath(REPO_SRC, "light_time.jl"))

const PHASE3_C_SIM = 100.0
const PHASE3_DURATION = 5.0
const PHASE3_WRITE_RATE = 1000
const PHASE3_REPLICA_COUNT = 6
const PHASE3_MERGE_COST_MS = 0.05

struct Phase3Worldline
    x0::SVector{3,Float64}
    v::SVector{3,Float64}
end

@inline function phase3_position(w::Phase3Worldline, t::Float64)::SVector{3,Float64}
    return w.x0 + w.v * t
end

@inline function phase3_velocity(w::Phase3Worldline, t::Float64)::SVector{3,Float64}
    return w.v
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

function phase3_leaders(c_sim::Float64=PHASE3_C_SIM)
    return [
        Phase3Worldline(SVector{3,Float64}(-150.0, 0.0, 0.0), SVector{3,Float64}(0.0, 0.0, 0.0)),
        Phase3Worldline(SVector{3,Float64}(0.0, 0.0, 0.0), SVector{3,Float64}(0.5 * c_sim, 0.0, 0.0)),
        Phase3Worldline(SVector{3,Float64}(150.0, 0.0, 0.0), SVector{3,Float64}(0.8 * c_sim, 0.0, 0.0)),
    ]
end

function phase3_followers()
    return [
        Phase3Worldline(SVector{3,Float64}(-75.0, -40.0, 0.0), SVector{3,Float64}(0.0, 0.0, 0.0)),
        Phase3Worldline(SVector{3,Float64}(-25.0, 40.0, 0.0), SVector{3,Float64}(0.0, 0.0, 0.0)),
        Phase3Worldline(SVector{3,Float64}(25.0, -40.0, 0.0), SVector{3,Float64}(0.0, 0.0, 0.0)),
        Phase3Worldline(SVector{3,Float64}(75.0, 40.0, 0.0), SVector{3,Float64}(0.0, 0.0, 0.0)),
        Phase3Worldline(SVector{3,Float64}(125.0, -40.0, 0.0), SVector{3,Float64}(0.0, 0.0, 0.0)),
        Phase3Worldline(SVector{3,Float64}(175.0, 40.0, 0.0), SVector{3,Float64}(0.0, 0.0, 0.0)),
    ]
end

function phase3_beta_label(beta_a::Float64, beta_b::Float64)
    return string(beta_a, "-", beta_b)
end

function phase3_commit_time(
    leader::Phase3Worldline,
    followers::Vector{Phase3Worldline},
    propose_time::Float64,
    c_sim::Float64,
)::Float64
    xA = phase3_position(leader, propose_time)
    commit_time = propose_time
    for follower in followers
        xB_func(t::Float64)::SVector{3,Float64} = phase3_position(follower, t)
        vB_func(t::Float64)::SVector{3,Float64} = phase3_velocity(follower, t)
        delivery = solve_light_time(propose_time, xA, xB_func, vB_func, c_sim)
        commit_time = max(commit_time, delivery)
    end
    return commit_time
end

function run_phase3(;
    seeds=1:100,
    duration::Float64=PHASE3_DURATION,
    write_rate::Int=PHASE3_WRITE_RATE,
    c_sim::Float64=PHASE3_C_SIM,
)
    betas = (0.0, 0.5, 0.8)
    pairs = ((1, 2), (1, 3), (2, 3))
    total_writes = Int(round(duration * write_rate))
    base_dt = 1.0 / write_rate
    rows = Vector{Vector{Any}}()

    for seed in seeds
        rng = StableRNG(seed)
        leaders = phase3_leaders(c_sim)
        followers = phase3_followers()

        for (a, b) in pairs
            spacelike_writes = 0
            merge_overhead_ms = 0.0

            for i in 0:(total_writes - 1)
                base_time = i * base_dt
                jitter_a = (rand(rng) - 0.5) * base_dt
                jitter_b = (rand(rng) - 0.5) * base_dt
                propose_a = clamp(base_time + jitter_a, 0.0, duration)
                propose_b = clamp(base_time + jitter_b, 0.0, duration)
                xa = phase3_position(leaders[a], propose_a)
                xb = phase3_position(leaders[b], propose_b)

                s2 = minkowski_interval2(propose_a, xa, propose_b, xb, c_sim)
                if s2 < 0.0
                    spacelike_writes += 1
                    commit_a = phase3_commit_time(leaders[a], followers, propose_a, c_sim)
                    commit_b = phase3_commit_time(leaders[b], followers, propose_b, c_sim)
                    merge_overhead_ms += abs(commit_a - commit_b) * 1000.0 + PHASE3_MERGE_COST_MS
                end
            end

            causal_violation_rate = spacelike_writes / total_writes
            push!(
                rows,
                Any[
                    seed,
                    phase3_beta_label(betas[a], betas[b]),
                    total_writes,
                    spacelike_writes,
                    causal_violation_rate,
                    merge_overhead_ms,
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
    path = joinpath(outdir, "phase3_causal_$stamp.csv")
    rows = run_phase3()
    write_csv(
        path,
        [
            "seed",
            "beta_pair",
            "total_writes",
            "spacelike_writes",
            "causal_violation_rate",
            "merge_overhead_ms",
        ],
        rows,
    )
    println(path)
    return path
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
