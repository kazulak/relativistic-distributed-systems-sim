using Dates
using StableRNGs

include("../src/light_time.jl")
include("../src/raft_baseline.jl")
include("../src/tvat.jl")

function write_csv(path::AbstractString, header, rows)
    open(path, "w") do io
        println(io, join(header, ","))
        for row in rows
            println(io, join(row, ","))
        end
    end
    return path
end

function run_baseline_sweep(; seeds=1:100, betas=(0.0, 0.3, 0.6, 0.9), duration=5.0, c_sim=100.0)
    rows = Vector{Vector{Any}}()
    for seed in seeds
        StableRNG(seed)
        for beta in betas
            result = simulate_raft_baseline(beta=Float64(beta), duration=duration, c_sim=c_sim)
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
    path = joinpath(outdir, "phase0_baseline_$stamp.csv")
    rows = run_baseline_sweep()
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

main()
