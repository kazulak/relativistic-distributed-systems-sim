#!/usr/bin/env julia

# Deterministic and stochastic standard-Raft RQ1 experiment runner
# Supports single-scenario execution and Stage E1/E2 grid execution with
# immutable run manifests and structured TSV logging (satisfying Audit Findings 3 & 7).

using RelativisticDistributedSystemsSim
using RelativisticDistributedSystemsSim.Research
using Dates

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
    is_deterministic::Bool
end

function git_sha()
    try
        return readchomp(`git rev-parse HEAD`)
    catch
        return "unknown"
    end
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
        # 8 representative deterministic cells for fast smoke verification
        push!(cells, RQ1Cell("e1_control_n3", ColocatedControl,
            canonical_scenario(ColocatedControl; cluster_size=3, workload=workload, network=clean_net), "clean", true))
        push!(cells, RQ1Cell("e1_control_n5", ColocatedControl,
            canonical_scenario(ColocatedControl; cluster_size=5, workload=workload, network=clean_net), "clean", true))
        push!(cells, RQ1Cell("e1_static_n3_r01", SeparatedStaticBaseline,
            canonical_scenario(SeparatedStaticBaseline; cluster_size=3, rho=0.10, workload=workload, network=clean_net), "clean", true))
        push!(cells, RQ1Cell("e1_static_n3_r04", SeparatedStaticBaseline,
            canonical_scenario(SeparatedStaticBaseline; cluster_size=3, rho=0.40, workload=workload, network=clean_net), "clean", true))
        push!(cells, RQ1Cell("e1_static_n5_r02", SeparatedStaticBaseline,
            canonical_scenario(SeparatedStaticBaseline; cluster_size=5, rho=0.20, workload=workload, network=clean_net), "clean", true))
        push!(cells, RQ1Cell("e1_recede_n3_b025_r02", AsymmetricRecedingInertial,
            canonical_scenario(AsymmetricRecedingInertial; cluster_size=3, beta=0.25, rho=0.20, workload=workload, network=clean_net), "clean", true))
        push!(cells, RQ1Cell("e1_flyby_n3_bm025_r02", AsymmetricRecedingInertial,
            canonical_scenario(AsymmetricRecedingInertial; cluster_size=3, beta=-0.25, rho=0.20, workload=workload, network=clean_net), "clean", true))
        push!(cells, RQ1Cell("e1_accel_n3_a002_r02", AcceleratingBaseline,
            canonical_scenario(AcceleratingBaseline; cluster_size=3, a_star=0.02, rho=0.20, workload=workload, network=clean_net), "clean", true))
    else
        # Full Stage E1 grid: parameter sweeps over rho, theta, beta, cluster_size
        for n in (3, 5)
            push!(cells, RQ1Cell("e1_control_n$(n)", ColocatedControl,
                canonical_scenario(ColocatedControl; cluster_size=n, workload=workload, network=clean_net), "clean", true))
            for rho in (0.05, 0.10, 0.20, 0.40, 0.60), theta in ((3.0, 5.0), (5.0, 7.0))
                tag_theta = "th$(Int(theta[1]))_$(Int(theta[2]))"
                push!(cells, RQ1Cell("e1_static_n$(n)_r$(rho)_$(tag_theta)", SeparatedStaticBaseline,
                    canonical_scenario(SeparatedStaticBaseline; cluster_size=n, rho=rho, theta=theta, workload=workload, network=clean_net), "clean", true))
            end
            for beta in (-0.25, 0.25, 0.50), rho in (0.10, 0.20, 0.40)
                push!(cells, RQ1Cell("e1_recede_n$(n)_b$(beta)_r$(rho)", AsymmetricRecedingInertial,
                    canonical_scenario(AsymmetricRecedingInertial; cluster_size=n, beta=beta, rho=rho, workload=workload, network=clean_net), "clean", true))
            end
            for a_star in (0.02, 0.05), rho in (0.10, 0.20)
                push!(cells, RQ1Cell("e1_accel_n$(n)_a$(a_star)_r$(rho)", AcceleratingBaseline,
                    canonical_scenario(AcceleratingBaseline; cluster_size=n, a_star=a_star, rho=rho, workload=workload, network=clean_net), "clean", true))
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
            canonical_scenario(SeparatedStaticBaseline; cluster_size=3, rho=0.20, workload=workload, network=net), dis, false))
        push!(cells, RQ1Cell("e2_recede_n3_b025_$(dis)", AsymmetricRecedingInertial,
            canonical_scenario(AsymmetricRecedingInertial; cluster_size=3, beta=0.25, rho=0.20, workload=workload, network=net), dis, false))
        if mode != "smoke"
            push!(cells, RQ1Cell("e2_static_n5_$(dis)", SeparatedStaticBaseline,
                canonical_scenario(SeparatedStaticBaseline; cluster_size=5, rho=0.20, workload=workload, network=net), dis, false))
            push!(cells, RQ1Cell("e2_accel_n3_a002_$(dis)", AcceleratingBaseline,
                canonical_scenario(AcceleratingBaseline; cluster_size=3, a_star=0.02, rho=0.20, workload=workload, network=net), dis, false))
        end
    end
    return cells
end

const RQ1_HEADER = [
    "cell", "family", "cluster_size", "beta_scale", "rho", "theta_min", "theta_max",
    "chi_initial", "rate_ratio", "disruption", "seed", "fingerprint",
    "status", "safety_ok", "causal_bound_ok", "min_causal_margin",
    "committed", "censored", "deadline_availability", "leader_availability",
    "elections_started", "terms_observed", "messages_sent", "bytes_sent",
]

function run_sweep(sweep_name::String, out_dir::Union{Nothing,String})
    mode = endswith(sweep_name, "-smoke") ? "smoke" : "full"
    stage = startswith(sweep_name, "e2") ? 2 : 1

    cells = stage == 1 ? build_e1_cells(mode) : build_e2_cells(mode)
    seeds = if stage == 1
        UInt64[1] # Stage E1 is deterministic: run once (Audit Finding 3)
    else
        mode == "smoke" ? UInt64[101, 102, 103] : UInt64[200 + i for i in 1:10]
    end

    timestamp = Dates.format(now(), "yyyymmdd_HHMMSS")
    target_dir = isnothing(out_dir) ? joinpath("results", "rq1", "run_$(sweep_name)_$(timestamp)") : out_dir
    mkpath(target_dir)

    manifest_path = joinpath(target_dir, "manifest.json")
    tsv_path = joinpath(target_dir, "runs.tsv")

    # Write run manifest (Audit Finding 7)
    open(manifest_path, "w") do io
        println(io, "{")
        println(io, "  \"schema\": \"rq1-manifest-v1\",")
        println(io, "  \"run_id\": \"", basename(target_dir), "\",")
        println(io, "  \"sweep\": \"", sweep_name, "\",")
        println(io, "  \"git_sha\": \"", git_sha(), "\",")
        println(io, "  \"julia\": \"", string(VERSION), "\",")
        println(io, "  \"started\": \"", Dates.format(now(), "yyyy-mm-ddTHH:MM:SS"), "\",")
        println(io, "  \"stage\": ", stage, ",")
        println(io, "  \"cells_count\": ", length(cells), ",")
        println(io, "  \"replications_per_cell\": ", length(seeds), ",")
        println(io, "  \"total_planned_runs\": ", length(cells) * length(seeds))
        println(io, "}")
    end

    open(tsv_path, "w") do io
        println(io, join(RQ1_HEADER, "\t"))
    end

    total_runs = length(cells) * length(seeds)
    completed = 0
    clean_safety = 0
    clean_bounds = 0

    println("Starting RQ1 sweep: ", sweep_name, " (", total_runs, " total runs, output: ", target_dir, ")")

    for cell in cells, seed in seeds
        result = run_scenario(cell.config; seed=seed)
        params = dimensionless_parameters(cell.config)
        all_safety = result.safety.raft_invariants && result.safety.client_history &&
                     result.safety.causal_deliveries && result.safety.causal_trace
        bound_ok, min_margin, _ = verify_causal_quorum_bounds(cell.config, result.operations)

        all_safety && (clean_safety += 1)
        bound_ok && (clean_bounds += 1)

        committed = result.metrics.committed_operations
        censored = result.metrics.censored_operations
        total_ops = committed + censored
        deadline_avail = total_ops == 0 ? 1.0 : committed / total_ops

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
            string(all_safety),
            string(bound_ok),
            string(min_margin),
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
                    " (safety: ", clean_safety, "/", completed,
                    ", causal_bound: ", clean_bounds, "/", completed, ")")
        end
    end

    println("RQ1 sweep completed: ", tsv_path)
    println("Summary: ", completed, " runs, ", clean_safety, " clean safety flags, ", clean_bounds, " clean causal bounds.")
    return clean_safety == completed && clean_bounds == completed ? 0 : 1
end

function usage(io::IO=stdout)
    println(io, "usage:")
    println(io, "  Single run:  julia --project=. experiments/run_rq1.jl FAMILY [CLUSTER_SIZE] [SEED]")
    println(io, "               FAMILY: control | static | receding | accelerating | stress | all")
    println(io, "  Grid sweep:  julia --project=. experiments/run_rq1.jl --sweep SWEEP [--out DIR]")
    println(io, "               SWEEP: e1-smoke | e1-full | e2-smoke | e2-full")
end

function main(arguments)
    isempty(arguments) && (usage(stderr); return 2)

    if arguments[1] == "--sweep"
        length(arguments) >= 2 || (usage(stderr); return 2)
        sweep_name = lowercase(arguments[2])
        sweep_name in ("e1-smoke", "e1-full", "e2-smoke", "e2-full") ||
            (println(stderr, "unknown sweep: ", sweep_name); usage(stderr); return 2)
        out_dir = nothing
        if length(arguments) >= 4 && arguments[3] in ("--out", "--output-dir")
            out_dir = arguments[4]
        end
        return run_sweep(sweep_name, out_dir)
    end

    # Classic single-scenario execution
    family_name = lowercase(arguments[1])
    cluster_size = length(arguments) >= 2 ? parse(Int, arguments[2]) : 3
    seed = length(arguments) >= 3 ? parse(UInt64, arguments[3]) : UInt64(1)
    if family_name == "all"
        for config in rq1_scenarios(cluster_size=cluster_size)
            result = run_scenario(config; seed=seed)
            print_run_summary(result)
            bound_ok, min_margin, _ = verify_causal_quorum_bounds(config, result.operations)
            println("causal_bound_ok=", bound_ok, " min_causal_margin=", min_margin)
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
    bound_ok, min_margin, _ = verify_causal_quorum_bounds(config, result.operations)
    println("causal_bound_ok=", bound_ok, " min_causal_margin=", min_margin)
    return (result.status == :completed && bound_ok) ? 0 : 1
end

exit(main(ARGS))
