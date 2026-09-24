#!/usr/bin/env julia

# Standard-Raft RQ1 experiment runner: single-scenario execution and Stage
# E1/E2 grid sweeps with provenance-complete manifests and TSV run logs.
#
# Raft election deadlines are drawn from per-node seeded RNG streams, so every
# cell -- including the E1 geometry sweep -- is a stochastic experiment and is
# run over several seeds (docs/DEVIATIONS.md, D-05).

using RelativisticDistributedSystemsSim
using RelativisticDistributedSystemsSim.Research
using Dates

include(joinpath(@__DIR__, "lib", "manifest.jl"))

# Seeds for exploratory sweeps. Confirmatory seed ranges are fixed only by an
# RQ1 preregistration and passed explicitly with --seeds.
const EXPLORATORY_SEEDS = 1:20
const SMOKE_SEEDS = 1:3

const FAMILY_BY_NAME = Dict(
    "control" => ColocatedControl,
    "static" => SeparatedStaticBaseline,
    "receding" => AsymmetricRecedingInertial,
    "accelerating" => AcceleratingBaseline,
    "stress" => PartitionDropStress,
)

struct RQ1Cell
    id::String
    family::ScenarioFamily
    config::ScenarioConfig
    disruption::String
end

function disruption_network(kind::String)
    kind == "clean" && return NetworkProfile(
        processing_delay=0.001,
        delay_jitter=0.001,
        bandwidth_bytes_per_time=100_000.0,
    )
    kind == "loss5" && return NetworkProfile(
        loss_probability=0.05,
        processing_delay=0.001,
        delay_jitter=0.001,
        bandwidth_bytes_per_time=100_000.0,
    )
    kind == "loss15" && return NetworkProfile(
        loss_probability=0.15,
        reorder_probability=0.20,
        reorder_delay=0.05,
        processing_delay=0.002,
        delay_jitter=0.004,
        bandwidth_bytes_per_time=80_000.0,
    )
    kind == "stress" && return NetworkProfile(
        loss_probability=0.12,
        duplicate_probability=0.10,
        reorder_probability=0.18,
        processing_delay=0.004,
        delay_jitter=0.010,
        reorder_delay=0.08,
        duplicate_delay=0.015,
        bandwidth_bytes_per_time=50_000.0,
    )
    throw(ArgumentError("unknown disruption kind: $kind"))
end

function build_e1_cells(mode::String)
    cells = RQ1Cell[]
    workload = WorkloadSpec(client_node=1, operation_count=8, read_every=2)
    clean_net = disruption_network("clean")

    if mode == "smoke"
        # 8 representative geometry cells for fast smoke verification
        push!(cells, RQ1Cell("e1_control_n3", ColocatedControl,
            canonical_scenario(ColocatedControl; cluster_size=3, workload=workload, network=clean_net), "clean"))
        push!(cells, RQ1Cell("e1_control_n5", ColocatedControl,
            canonical_scenario(ColocatedControl; cluster_size=5, workload=workload, network=clean_net), "clean"))
        push!(cells, RQ1Cell("e1_static_n3_r01", SeparatedStaticBaseline,
            canonical_scenario(SeparatedStaticBaseline; cluster_size=3, rho=0.10, workload=workload, network=clean_net), "clean"))
        push!(cells, RQ1Cell("e1_static_n3_r04", SeparatedStaticBaseline,
            canonical_scenario(SeparatedStaticBaseline; cluster_size=3, rho=0.40, workload=workload, network=clean_net), "clean"))
        push!(cells, RQ1Cell("e1_static_n5_r02", SeparatedStaticBaseline,
            canonical_scenario(SeparatedStaticBaseline; cluster_size=5, rho=0.20, workload=workload, network=clean_net), "clean"))
        push!(cells, RQ1Cell("e1_recede_n3_b025_r02", AsymmetricRecedingInertial,
            canonical_scenario(AsymmetricRecedingInertial; cluster_size=3, beta=0.25, rho=0.20, workload=workload, network=clean_net), "clean"))
        push!(cells, RQ1Cell("e1_flyby_n3_bm025_r02", AsymmetricRecedingInertial,
            canonical_scenario(AsymmetricRecedingInertial; cluster_size=3, beta=-0.25, rho=0.20, workload=workload, network=clean_net), "clean"))
        push!(cells, RQ1Cell("e1_accel_n3_a002_r02", AcceleratingBaseline,
            canonical_scenario(AcceleratingBaseline; cluster_size=3, a_star=0.02, rho=0.20, workload=workload, network=clean_net), "clean"))
    else
        # Full Stage E1 grid: geometry sweeps over rho, theta, beta, cluster_size
        for n in (3, 5)
            push!(cells, RQ1Cell("e1_control_n$(n)", ColocatedControl,
                canonical_scenario(ColocatedControl; cluster_size=n, workload=workload, network=clean_net), "clean"))
            for rho in (0.05, 0.10, 0.20, 0.40, 0.60), theta in ((3.0, 5.0), (5.0, 7.0))
                tag_theta = "th$(Int(theta[1]))_$(Int(theta[2]))"
                push!(cells, RQ1Cell("e1_static_n$(n)_r$(rho)_$(tag_theta)", SeparatedStaticBaseline,
                    canonical_scenario(SeparatedStaticBaseline; cluster_size=n, rho=rho, theta=theta, workload=workload, network=clean_net), "clean"))
            end
            for beta in (-0.25, 0.25, 0.50), rho in (0.10, 0.20, 0.40)
                push!(cells, RQ1Cell("e1_recede_n$(n)_b$(beta)_r$(rho)", AsymmetricRecedingInertial,
                    canonical_scenario(AsymmetricRecedingInertial; cluster_size=n, beta=beta, rho=rho, workload=workload, network=clean_net), "clean"))
            end
            for a_star in (0.02, 0.05), rho in (0.10, 0.20)
                push!(cells, RQ1Cell("e1_accel_n$(n)_a$(a_star)_r$(rho)", AcceleratingBaseline,
                    canonical_scenario(AcceleratingBaseline; cluster_size=n, a_star=a_star, rho=rho, workload=workload, network=clean_net), "clean"))
            end
        end
    end
    return cells
end

function build_e2_cells(mode::String)
    cells = RQ1Cell[]
    workload = WorkloadSpec(client_node=1, operation_count=8, read_every=2)
    disruptions = mode == "smoke" ? ("clean", "loss5", "stress") : ("clean", "loss5", "loss15", "stress")

    for dis in disruptions
        net = disruption_network(dis)
        push!(cells, RQ1Cell("e2_static_n3_$(dis)", SeparatedStaticBaseline,
            canonical_scenario(SeparatedStaticBaseline; cluster_size=3, rho=0.20, workload=workload, network=net), dis))
        push!(cells, RQ1Cell("e2_recede_n3_b025_$(dis)", AsymmetricRecedingInertial,
            canonical_scenario(AsymmetricRecedingInertial; cluster_size=3, beta=0.25, rho=0.20, workload=workload, network=net), dis))
        if mode != "smoke"
            push!(cells, RQ1Cell("e2_static_n5_$(dis)", SeparatedStaticBaseline,
                canonical_scenario(SeparatedStaticBaseline; cluster_size=5, rho=0.20, workload=workload, network=net), dis))
            push!(cells, RQ1Cell("e2_accel_n3_a002_$(dis)", AcceleratingBaseline,
                canonical_scenario(AcceleratingBaseline; cluster_size=3, a_star=0.02, rho=0.20, workload=workload, network=net), dis))
        end
    end
    return cells
end

const RQ1_HEADER = [
    "cell", "family", "cluster_size", "beta_scale", "rho", "theta_min", "theta_max",
    "chi_initial", "rate_ratio", "disruption", "seed", "fingerprint",
    "status", "failure_reason", "safety_ok", "raft_invariants", "client_history",
    "causal_deliveries", "causal_trace",
    "causal_bound_ok", "audited_writes", "min_causal_margin",
    "committed", "censored", "deadline_availability", "leader_availability",
    "elections_started", "terms_observed", "messages_sent", "bytes_sent",
]

function run_sweep(
    sweep_name::String,
    out_dir::Union{Nothing,String};
    seeds::Union{Nothing,AbstractVector{<:Integer}}=nothing,
    confirmatory::Bool=false,
    prereg::String="none",
)
    mode = endswith(sweep_name, "-smoke") ? "smoke" : "full"
    stage = startswith(sweep_name, "e2") ? 2 : 1

    cells = stage == 1 ? build_e1_cells(mode) : build_e2_cells(mode)
    seeds = isnothing(seeds) ? (mode == "smoke" ? SMOKE_SEEDS : EXPLORATORY_SEEDS) : seeds
    isempty(seeds) && throw(ArgumentError("seed range is empty"))
    all(>=(0), seeds) || throw(ArgumentError("seeds must be non-negative"))
    confirmatory && prereg == "none" &&
        throw(ArgumentError("confirmatory sweeps require --prereg TAG"))

    provenance = git_provenance()
    require_clean_tree(provenance; confirmatory=confirmatory)

    timestamp = Dates.format(now(), "yyyymmdd_HHMMSS")
    target_dir = isnothing(out_dir) ? joinpath("results", "rq1", "run_$(sweep_name)_$(timestamp)") : out_dir
    # Never append to or overwrite an existing run directory.
    ispath(target_dir) && throw(ArgumentError("output directory already exists: $target_dir"))
    mkpath(target_dir)

    manifest_path = joinpath(target_dir, "manifest.json")
    tsv_path = joinpath(target_dir, "runs.tsv")

    write_manifest(manifest_path, Dict(
        "schema" => "rq1-manifest-v2",
        "run_id" => basename(target_dir),
        "sweep" => sweep_name,
        "stage" => stage,
        "role" => confirmatory ? "confirmatory" : "exploratory",
        "prereg" => prereg,
        "seeds" => collect(Int, seeds),
        "cells" => [Dict("id" => c.id, "fingerprint" => config_fingerprint(c.config)) for c in cells],
        "total_planned_runs" => length(cells) * length(seeds),
    ); provenance=provenance)

    open(tsv_path, "w") do io
        println(io, join(RQ1_HEADER, "\t"))
    end

    total_runs = length(cells) * length(seeds)
    completed = 0
    clean_runs = 0
    clean_bounds = 0

    println("Starting RQ1 sweep: ", sweep_name, " (", total_runs, " total runs, output: ", target_dir, ")")

    for cell in cells, seed in seeds
        result = run_scenario(cell.config; seed=seed)
        params = dimensionless_parameters(cell.config)
        flags = result.safety
        all_safety = flags.raft_invariants && flags.client_history &&
                     flags.causal_deliveries && flags.causal_trace
        audit = verify_causal_quorum_bounds(cell.config, result.operations)

        (all_safety && result.status == :completed) && (clean_runs += 1)
        audit.ok && (clean_bounds += 1)

        committed = result.metrics.committed_operations
        censored = result.metrics.censored_operations
        total_ops = committed + censored
        deadline_avail = total_ops == 0 ? NaN : committed / total_ops

        row = [
            cell.id,
            String(Symbol(result.family)),
            string(length(cell.config.raft.members)),
            string(cell.config.beta_scale),
            string(params.rho),
            string(params.theta_min),
            string(params.theta_max),
            string(params.chi_initial),
            string(params.source_receiver_rate_ratio),
            cell.disruption,
            string(seed),
            result.config_fingerprint,
            String(result.status),
            tsv_cell(something(result.failure_reason, "")),
            string(all_safety),
            string(flags.raft_invariants),
            string(flags.client_history),
            string(flags.causal_deliveries),
            string(flags.causal_trace),
            string(audit.ok),
            string(audit.audited_writes),
            string(audit.min_margin),
            string(committed),
            string(censored),
            string(deadline_avail),
            string(result.metrics.leader_availability),
            string(result.metrics.elections_started),
            string(result.metrics.terms_observed),
            string(result.metrics.messages_sent),
            string(result.metrics.bytes_sent),
        ]

        open(tsv_path, "a") do io
            println(io, join(row, "\t"))
        end

        completed += 1
        if completed % max(1, total_runs ÷ 10) == 0 || completed == total_runs
            println("progress: ", completed, "/", total_runs,
                    " (clean runs: ", clean_runs, "/", completed,
                    ", causal_bound: ", clean_bounds, "/", completed, ")")
        end
    end

    println("RQ1 sweep completed: ", tsv_path)
    println("Summary: ", completed, " runs, ", clean_runs, " completed with clean safety flags, ",
            clean_bounds, " clean causal-bound audits.")
    return clean_runs == completed && clean_bounds == completed ? 0 : 1
end

function usage(io::IO=stdout)
    println(io, "usage:")
    println(io, "  Single run:  julia --project=. experiments/run_rq1.jl FAMILY [CLUSTER_SIZE] [SEED]")
    println(io, "               FAMILY: control | static | receding | accelerating | stress | all")
    println(io, "  Grid sweep:  julia --project=. experiments/run_rq1.jl --sweep SWEEP [--out DIR]")
    println(io, "                   [--seeds A:B] [--confirmatory --prereg TAG]")
    println(io, "               SWEEP: e1-smoke | e1-full | e2-smoke | e2-full")
    println(io, "               --confirmatory requires a clean git tree and a preregistration tag;")
    println(io, "               the output directory must not already exist.")
end

"""Parse sweep flags; returns `nothing` on an unknown or incomplete flag."""
function parse_sweep_options(arguments::AbstractVector{<:AbstractString})
    out_dir = nothing
    seeds = nothing
    confirmatory = false
    prereg = "none"
    index = 1
    while index <= length(arguments)
        flag = arguments[index]
        if flag == "--confirmatory"
            confirmatory = true
            index += 1
            continue
        end
        index < length(arguments) || (println(stderr, "missing value for ", flag); return nothing)
        value = arguments[index + 1]
        if flag in ("--out", "--output-dir")
            out_dir = String(value)
        elseif flag == "--seeds"
            bounds = split(value, ':')
            length(bounds) == 2 || (println(stderr, "--seeds expects A:B"); return nothing)
            seeds = parse(Int, bounds[1]):parse(Int, bounds[2])
        elseif flag == "--prereg"
            prereg = String(value)
        else
            println(stderr, "unknown flag: ", flag)
            return nothing
        end
        index += 2
    end
    return (; out_dir, seeds, confirmatory, prereg)
end

function print_audit(audit)
    println("causal_bound_ok=", audit.ok, " audited_writes=", audit.audited_writes,
            " min_causal_margin=", audit.min_margin)
end

function main(arguments)
    isempty(arguments) && (usage(stderr); return 2)

    if arguments[1] == "--sweep"
        length(arguments) >= 2 || (usage(stderr); return 2)
        sweep_name = lowercase(arguments[2])
        sweep_name in ("e1-smoke", "e1-full", "e2-smoke", "e2-full") ||
            (println(stderr, "unknown sweep: ", sweep_name); usage(stderr); return 2)
        options = parse_sweep_options(arguments[3:end])
        isnothing(options) && (usage(stderr); return 2)
        return run_sweep(
            sweep_name,
            options.out_dir;
            seeds=options.seeds,
            confirmatory=options.confirmatory,
            prereg=options.prereg,
        )
    end

    # Classic single-scenario execution
    family_name = lowercase(arguments[1])
    cluster_size = length(arguments) >= 2 ? parse(Int, arguments[2]) : 3
    seed = length(arguments) >= 3 ? parse(UInt64, arguments[3]) : UInt64(1)
    if family_name == "all"
        for config in rq1_scenarios(cluster_size=cluster_size)
            result = run_scenario(config; seed=seed)
            print_run_summary(result)
            print_audit(verify_causal_quorum_bounds(config, result.operations))
            println()
        end
        return 0
    end
    family = get(FAMILY_BY_NAME, family_name, nothing)
    if isnothing(family)
        usage(stderr)
        return 2
    end
    config = canonical_scenario(family; cluster_size=cluster_size)
    result = run_scenario(config; seed=seed)
    print_run_summary(result)
    audit = verify_causal_quorum_bounds(config, result.operations)
    print_audit(audit)
    return (result.status == :completed && audit.ok) ? 0 : 1
end

if abspath(PROGRAM_FILE) == @__FILE__
    exit(main(ARGS))
end
