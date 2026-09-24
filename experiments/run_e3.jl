# E3 runner: executes arm × cell × replica and writes runs.tsv + manifest.json.
#
#   julia --project=. experiments/run_e3.jl --role tuning --replicas 1:24 [--arms B0,P2]
#       [--cells approach_,stationary_r0.1] [--seed-base 0] [--tuned PATH] [--out DIR]
#   julia --project=. experiments/run_e3.jl --role report --confirmatory --tuned PATH \
#       --seed-base 1000 --replicas 1:120 --out results/e3/report-<id>
#
# `include`-ing this file defines the functions without running anything, so the
# CLI parser and guards are unit-testable (test/research/e3_design.jl).

using Dates

include(joinpath(@__DIR__, "lib", "manifest.jl"))
include(joinpath(@__DIR__, "lib", "e3_cells.jl"))

"""Preregistration tag recorded in every manifest (override with --prereg)."""
const E3_PREREG_TAG = "v0.3-e3-prereg-r4-draft"

# Seed ranges are defined once, in experiments/lib/e3_cells.jl:
# E3_TUNING_SEEDS and E3_REPORT_SEEDS (aliased here for brevity).
const TUNING_SEEDS = E3_TUNING_SEEDS
const REPORT_SEEDS = E3_REPORT_SEEDS

const ROLES = ("tuning", "report")

const HEADER = [
    "cell", "regime", "family", "beta", "dsr_target", "dsr_at_start", "dsr_measured",
    "rho_param", "loss", "reorder", "traj",
    "arm", "level", "fingerprint", "cell_fingerprint", "seed", "role",
    "status", "failure_reason", "safety_ok",
    "raft_invariants", "client_history", "causal_deliveries", "causal_trace",
    "elections_started", "election_fires", "leader_present_fires", "suspicions",
    "false_suspicion_rate", "suspicions_per_follower_heartbeat",
    "committed", "censored", "metadata_bytes", "leader_availability",
    "crash_count", "detection_n", "detection_censored", "detection_p50", "detection_p95",
]

struct UsageError <: Exception
    message::String
end
Base.showerror(io::IO, error::UsageError) = print(io, error.message)

function _parse_range(text::AbstractString)
    parts = split(text, ':')
    length(parts) == 2 || throw(UsageError("expected A:B, got '$text'"))
    lo, hi = tryparse(Int, parts[1]), tryparse(Int, parts[2])
    (isnothing(lo) || isnothing(hi)) && throw(UsageError("expected integer range A:B, got '$text'"))
    lo <= hi || throw(UsageError("empty range '$text'"))
    return lo:hi
end

_split_list(text::AbstractString) = String[strip(item) for item in split(text, ',') if !isempty(strip(item))]

"""
    parse_args(arguments) -> NamedTuple

Pure CLI parsing (no filesystem or git access); throws `UsageError`.
"""
function parse_args(arguments::AbstractVector{<:AbstractString})
    replicas = 1:24
    seed_base = 0
    arms = collect(E3_ARM_NAMES)
    cells = String[]
    out = nothing
    role = nothing
    confirmatory = false
    tuned = nothing
    prereg = E3_PREREG_TAG
    index = 1
    value(flag) = index + 1 <= length(arguments) ? arguments[index + 1] :
                  throw(UsageError("flag $flag requires a value"))
    while index <= length(arguments)
        flag = arguments[index]
        if flag == "--replicas"
            replicas = _parse_range(value(flag)); index += 2
        elseif flag == "--seed-base"
            parsed = tryparse(Int, value(flag))
            isnothing(parsed) && throw(UsageError("--seed-base needs an integer"))
            seed_base = parsed; index += 2
        elseif flag == "--arms"
            arms = _split_list(value(flag)); index += 2
        elseif flag == "--cells"
            cells = _split_list(value(flag)); index += 2
        elseif flag == "--out"
            out = String(value(flag)); index += 2
        elseif flag == "--role"
            role = String(value(flag)); index += 2
        elseif flag == "--tuned"
            tuned = String(value(flag)); index += 2
        elseif flag == "--prereg"
            prereg = String(value(flag)); index += 2
        elseif flag == "--confirmatory"
            confirmatory = true; index += 1
        else
            throw(UsageError("unknown argument $flag"))
        end
    end
    isnothing(role) && throw(UsageError("--role tuning|report is required"))
    role in ROLES || throw(UsageError("--role must be one of $(join(ROLES, '|'))"))
    isempty(arms) && throw(UsageError("--arms is empty"))
    for arm in arms
        arm in E3_ARM_NAMES || throw(UsageError("unknown arm $arm"))
    end
    seeds = (seed_base + first(replicas)):(seed_base + last(replicas))
    return (
        replicas=replicas, seed_base=seed_base, seeds=seeds, arms=arms, cells=cells,
        out=out, role=role, confirmatory=confirmatory, tuned=tuned, prereg=prereg,
    )
end

"""
    check_guards(config; provenance, out_exists) -> nothing

Enforce seed discipline and confirmatory preconditions; throws `UsageError`.
`provenance` is `git_provenance()`-shaped; `out_exists(path)` is injectable.
"""
function check_guards(config; provenance, out_exists=ispath)
    seeds = config.seeds
    if config.role == "report"
        config.confirmatory || throw(UsageError("--role report requires --confirmatory"))
        isnothing(config.tuned) && throw(UsageError("--role report requires --tuned PATH"))
        first(seeds) >= first(REPORT_SEEDS) && last(seeds) <= last(REPORT_SEEDS) ||
            throw(UsageError("report seeds $seeds must lie inside REPORT_SEEDS $REPORT_SEEDS"))
        isnothing(config.out) && throw(UsageError("--role report requires an explicit --out DIR"))
        try
            require_clean_tree(provenance; confirmatory=true)
        catch error
            throw(UsageError(sprint(showerror, error)))
        end
        any(arm -> arm in ("O0",), config.arms) &&
            @warn "O0 is a reference arm and is excluded from rankings"
    else
        config.confirmatory && throw(UsageError("--confirmatory is only valid with --role report"))
        first(seeds) >= first(TUNING_SEEDS) && last(seeds) <= last(TUNING_SEEDS) ||
            throw(UsageError("tuning seeds $seeds must lie inside TUNING_SEEDS $TUNING_SEEDS"))
        isempty(intersect(seeds, REPORT_SEEDS)) ||
            throw(UsageError("tuning seeds overlap the report range"))
    end
    if !isnothing(config.out) && out_exists(config.out)
        throw(UsageError("output directory $(config.out) already exists; runs never overwrite or append"))
    end
    !isnothing(config.tuned) && !isfile(config.tuned) &&
        throw(UsageError("tuned-parameter file $(config.tuned) not found"))
    return nothing
end

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

_num(x::Real) = isnan(x) ? "NaN" : string(x)

"""Run one (cell, arm, seed) and return (row::Vector{String}, safety_ok::Bool)."""
function run_row(cell::E3Cell, arm::AbstractString, spec::TimingSpec, seed::Integer, role::AbstractString)
    config = cell.config
    result = try
        run_scenario(config; seed=seed, timing=spec)
    catch error
        error
    end
    common = [
        cell.id, cell.regime, "", string(cell.beta), string(cell.dsr_target), "", "",
        string(cell.rho), string(config.network.loss_probability),
        string(config.network.reorder_probability), String(cell.trajectory),
        arm, string(spec.level), timing_fingerprint(spec), config_fingerprint(config),
        string(seed), role,
    ]
    if result isa Exception
        # Harness-level exception outside run_scenario's own capture.
        row = copy(common)
        append!(row, ["error", tsv_cell(sprint(showerror, result)), "false",
                      "", "", "", ""])
        append!(row, fill("", length(HEADER) - length(row)))
        return row, false
    end
    d = result.adaptation
    safety = result.safety
    safety_ok = safety.raft_invariants && safety.client_history &&
                safety.causal_deliveries && safety.causal_trace
    delays = d.detection_delays_proper
    row = copy(common)
    row[3] = String(Symbol(result.family))
    row[6] = _num(result.dimensionless.source_receiver_rate_ratio)
    row[7] = _num(d.dsr_measured)
    append!(row, [
        String(result.status),
        tsv_cell(something(result.failure_reason, "")),
        string(safety_ok),
        string(safety.raft_invariants), string(safety.client_history),
        string(safety.causal_deliveries), string(safety.causal_trace),
        string(result.metrics.elections_started),
        string(d.election_fires), string(d.leader_present_fires), string(d.suspicions),
        _num(d.false_suspicion_rate), _num(d.suspicions_per_follower_heartbeat),
        string(result.metrics.committed_operations), string(result.metrics.censored_operations),
        string(d.metadata_bytes_sent), string(result.metrics.leader_availability),
        string(d.leader_crashes), string(length(delays)), string(d.censored_detections),
        percentile(delays, 0.50), percentile(delays, 0.95),
    ])
    @assert length(row) == length(HEADER)
    return row, safety_ok
end

function _manifest_fields(config, cells, tuned_meta, specs_used)
    cell_records = [Dict{String,Any}(
        "id" => cell.id, "regime" => cell.regime, "beta" => cell.beta,
        "dsr_target" => cell.dsr_target, "rho" => cell.rho, "disruption" => cell.disruption,
        "trajectory" => String(cell.trajectory), "config_fingerprint" => config_fingerprint(cell.config),
    ) for cell in cells]
    return Dict{String,Any}(
        "experiment" => "E3",
        "run_id" => basename(normpath(config.out)),
        "prereg" => config.prereg,
        "role" => config.role,
        "confirmatory" => config.confirmatory,
        "seed_range" => string(config.seeds),
        "seed_base" => config.seed_base,
        "replicas" => string(config.replicas),
        "tuning_seeds" => string(TUNING_SEEDS),
        "report_seeds" => string(REPORT_SEEDS),
        "arms" => Dict{String,Any}(key => fp for (key, fp) in specs_used),
        "reference_arms" => ["O0"],
        "cells" => cell_records,
        "cell_count" => length(cells),
        "tuned_file" => something(config.tuned, "none (untuned defaults)"),
        "tuned_meta" => isnothing(tuned_meta) ? nothing :
            Dict{String,Any}(string(k) => string(v) for (k, v) in tuned_meta),
        "crash_schedule" => Dict{String,Any}(
            "mode" => String(E3_CRASH_MODE),
            "leader_crash_offsets" => collect(E3_LEADER_CRASH_OFFSETS),
            "rotating_offset" => E3_CRASH_OFFSET, "rotating_spacing" => E3_CRASH_SPACING,
            "downtime" => E3_CRASH_DOWNTIME,
        ),
        "window" => Dict{String,Any}(
            "warmup_end" => E3_WINDOW.warmup_end_coordinate,
            "measurement_end" => E3_WINDOW.measurement_end_coordinate,
            "censor" => E3_WINDOW.censor_coordinate,
        ),
        "tsv_columns" => HEADER,
    )
end

"""Entry point; returns a process exit code."""
function main(arguments; provenance=git_provenance())
    config = try
        parsed = parse_args(arguments)
        out = something(parsed.out, joinpath("results", "e3",
            "$(parsed.role)-" * Dates.format(now(), "yyyymmdd_HHMMSS")))
        parsed = merge(parsed, (out=out,))
        check_guards(parsed; provenance=provenance)
        parsed
    catch error
        error isa UsageError || rethrow()
        println(stderr, "run_e3: ", error.message)
        return 2
    end
    tuned, tuned_meta = isnothing(config.tuned) ? (nothing, nothing) : load_tuned(config.tuned)
    cells = build_e3_cells(prefixes=config.cells)
    isempty(cells) && (println(stderr, "run_e3: no cells match $(config.cells)"); return 2)
    specs_used = Dict{String,String}()
    try
        for cell in cells, arm in config.arms
            specs_used["$(arm)/$(cell.regime)"] = timing_fingerprint(arm_spec(tuned, arm, cell.regime))
        end
    catch error
        println(stderr, "run_e3: ", sprint(showerror, error))
        return 2
    end
    mkpath(config.out)
    write_manifest(joinpath(config.out, "manifest.json"),
                   _manifest_fields(config, cells, tuned_meta, specs_used); provenance=provenance)
    tsv_path = joinpath(config.out, "runs.tsv")
    open(tsv_path, "w") do io
        println(io, join(HEADER, "\t"))
    end
    total = length(cells) * length(config.seeds) * length(config.arms)
    done = 0
    counts = Dict("completed" => 0, "failed" => 0, "invalid" => 0, "error" => 0)
    halted = nothing
    for cell in cells, seed in config.seeds, arm in config.arms
        spec = arm_spec(tuned, arm, cell.regime)
        row, safety_ok = run_row(cell, arm, spec, seed, config.role)
        open(tsv_path, "a") do io
            println(io, join(row, "\t"))
        end
        status = row[findfirst(==("status"), HEADER)]
        counts[status] = get(counts, status, 0) + 1
        done += 1
        done % 25 == 0 && println("progress ", done, "/", total)
        if !safety_ok && status != "error" && config.role == "report"
            # Prereg §11: any safety-flag failure halts E3 entirely.
            halted = "safety failure at cell=$(cell.id) arm=$arm seed=$seed"
            break
        end
    end
    write_manifest(joinpath(config.out, "completion.json"), Dict{String,Any}(
        "runs" => done, "planned" => total, "status_counts" => counts,
        "halted" => halted,
    ); provenance=provenance)
    println("wrote ", tsv_path, " (", done, " runs; ", counts, ")")
    isnothing(halted) || (println(stderr, "HALTED: ", halted); return 3)
    return 0
end

if abspath(PROGRAM_FILE) == @__FILE__
    exit(main(ARGS))
end
