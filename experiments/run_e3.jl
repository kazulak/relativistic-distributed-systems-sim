using RelativisticDistributedSystemsSim
using RelativisticDistributedSystemsSim.Research
using Dates

const ARMS = Dict{String,TimingSpec}(
    "B0" => TimingSpec(arm=:B0, level=0; base_timeout=1.2),
    "B1" => TimingSpec(arm=:B1, level=0; base_timeout=2.5),
    "B2" => TimingSpec(arm=:B2, level=0, base_timeout=0.6, budget=TimingBudget(0.3, 3.0)),
    "B3" => TimingSpec(arm=:B3, level=0; base_timeout=0.7),
    "B4" => TimingSpec(arm=:B4, level=0; base_timeout=0.7),
    "B5" => TimingSpec(arm=:B5, level=0; base_timeout=0.7),
    "P1" => TimingSpec(arm=:P1, level=1; base_timeout=0.9),
    "P2" => TimingSpec(arm=:P2, level=2; base_timeout=0.9),
    "P3" => TimingSpec(arm=:P3, level=3; base_timeout=0.9),
)

struct Cell
    id::String
    config::ScenarioConfig
end

function disruption_profile(kind::String)
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
    throw(ArgumentError("unknown disruption $kind"))
end

function build_cells()
    cells = Cell[]
    workload = WorkloadSpec(client_node=1, operation_count=8, read_every=2)
    betas = [(-0.25, "flyby"), (0.25, "recede"), (0.5, "recede")]
    for (beta, tag) in betas, rho in (0.1, 0.2, 0.4),
        dis in ("clean", "loss5", "loss15"), traj in ("inertial", "onset")
        network = disruption_profile(dis)
        if traj == "inertial"
            config = canonical_scenario(
                AsymmetricRecedingInertial;
                cluster_size=5,
                beta=beta,
                rho=rho,
                workload=workload,
                network=network,
            )
        else
            config = trajectory_change_scenario(
                cluster_size=5;
                beta_initial=beta,
                rho=rho,
                a_star=0.05,
                workload=workload,
                network=network,
            )
        end
        push!(
            cells,
            Cell("$(tag)_b$(beta)_r$(rho)_$(dis)_$(traj)", config),
        )
    end
    push!(
        cells,
        Cell("control_static_r02_clean", canonical_scenario(
            SeparatedStaticBaseline;
            cluster_size=5,
            rho=0.2,
            workload=workload,
            network=disruption_profile("clean"),
        )),
    )
    return cells
end

const HEADER = [
    "cell", "family", "beta_scale", "rho_param", "loss", "reorder", "traj",
    "arm", "level", "fingerprint", "seed",
    "status", "elections_started", "election_fires", "suspicions",
    "false_suspicion_rate", "committed", "censored",
    "metadata_bytes", "leader_availability",
    "detection_n", "detection_p50", "detection_p95",
]

function percentile(values::Vector{Float64}, q::Float64)
    isempty(values) && return ""
    ordered = sort(values)
    position = clamp(q * (length(ordered) - 1) + 1, 1.0, Float64(length(ordered)))
    lower = floor(Int, position)
    upper = ceil(Int, position)
    lower == upper && return string(ordered[lower])
    weight = position - lower
    return string(ordered[lower] + weight * (ordered[upper] - ordered[lower]))
end

function git_sha()
    try
        return strip(String(read(`git rev-parse HEAD`)))
    catch
        return "unknown"
    end
end

function main(arguments)
    replicas = 1:24
    seed_base = 0
    out_root = nothing
    selected_arms = sort(collect(keys(ARMS)))
    index = 1
    while index <= length(arguments)
        argument = arguments[index]
        if argument == "--replicas"
            global replicas
            bounds = split(arguments[index + 1], ':')
            replicas = parse(Int, bounds[1]):parse(Int, bounds[2])
            index += 2
        elseif argument == "--arms"
            global selected_arms
            selected_arms = split(arguments[index + 1], ',')
            index += 2
        elseif argument == "--seed-base"
            global seed_base = parse(Int, arguments[index + 1])
            index += 2
        elseif argument == "--out"
            global out_root
            out_root = arguments[index + 1]
            index += 2
        else
            println(stderr, "unknown argument ", argument)
            return 2
        end
    end
    isnothing(out_root) && (out_root = "results/e3/pilot-" *
                                          Dates.format(now(), "yyyymmdd_HHMMSS"))
    mkpath(out_root)

    cells = filter(cell -> any(startswith(cell.id, prefix) for prefix in ()) || true, build_cells())
    manifest = IOBuffer()
    println(manifest, "{")
    println(manifest, "  \"run_id\": \"", basename(out_root), "\",")
    println(manifest, "  \"prereg\": \"v0.3-e3-prereg\",")
    println(manifest, "  \"git_sha\": \"", git_sha(), "\",")
    println(manifest, "  \"julia\": \"", string(VERSION), "\",")
    println(manifest, "  \"started\": \"", Dates.format(now(), "yyyy-mm-ddTHH:MM:SS"), "\",")
    println(manifest, "  \"replicas\": \"", replicas, "\",")
    print(manifest, "  \"arms\": {")
    join(manifest, ["\"$a\": \"" * timing_fingerprint(ARMS[a]) * "\"" for a in selected_arms], ", ")
    println(manifest, "},")
    println(manifest, "  \"cells\": ", length(cells))
    println(manifest, "}")
    open(joinpath(out_root, "manifest.json"), "w") do io
        write(io, take!(manifest))
    end

    tsv_path = joinpath(out_root, "runs.tsv")
    open(tsv_path, "w") do io
        println(io, join(HEADER, "\t"))
    end

    total = length(cells) * length(replicas) * length(selected_arms)
    done = 0
    for cell in cells, replica in replicas
        seed = seed_base + replica
        for arm_name in selected_arms
            spec = ARMS[arm_name]
            result = run_scenario(cell.config; seed=seed, timing=spec)
            d = result.adaptation
            delays = isnothing(d) ? Float64[] : d.detection_delays_proper
            row = [
                cell.id,
                String(Symbol(result.family)),
                string(result.dimensionless.source_receiver_rate_ratio),
                string(cell.config.characteristic_distance /
                       (cell.config.spacetime.c * cell.config.raft.heartbeat_interval)),
                string(cell.config.network.loss_probability),
                string(cell.config.network.reorder_probability),
                occursin("_onset", cell.id) ? "onset" : "inertial",
                arm_name,
                string(spec.level),
                timing_fingerprint(spec),
                string(seed),
                String(result.status),
                string(result.metrics.elections_started),
                string(isnothing(d) ? -1 : d.election_fires),
                string(isnothing(d) ? -1 : d.suspicions),
                string(isnothing(d) ? "" : d.false_suspicion_rate),
                string(result.metrics.committed_operations),
                string(result.metrics.censored_operations),
                string(isnothing(d) ? 0 : d.metadata_bytes_sent),
                string(result.metrics.leader_availability),
                string(length(delays)),
                percentile(delays, 0.50),
                percentile(delays, 0.95),
            ]
            open(tsv_path, "a") do io
                println(io, join(row, "\t"))
            end
            done += 1
            done % 25 == 0 && println("progress ", done, "/", total)
        end
    end
    println("wrote ", tsv_path, " (", done, " runs)")
    return 0
end

exit(main(ARGS))
