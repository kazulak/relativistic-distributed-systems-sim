# E3 tuning harness (prereg §7): choose every arm's hyperparameters per D_sr
# regime class on TUNING seeds only, and write a fingerprinted tuned-parameter
# TOML consumed by run_e3.jl (--tuned).
#
#   julia --project=. -t auto experiments/tune_e3.jl --out tuned.toml
#       [--seeds 1:40] [--cells stationary_,approach_r0.1] [--arms B0,P2]
#
# Declared procedure (r4 draft):
#  1. B0 is tuned first per regime class; its timeout becomes the shared
#     cold-start timeout (`base_timeout`) of every other arm in that class
#     (prereg §4 guardrail: "all arms fall back to B0 until ≥ 3 observations").
#  2. B1 is analytic, not tuned: B1_MISSES heartbeat intervals stretched by the
#     class's worst design D_sr, plus network slack.
#  3. Every other arm is grid-searched. Objective, pooled over the class's cells
#     × tuning seeds: minimise the false-suspicion rate per follower-heartbeat
#     of leader presence, subject to pooled p95 crash-detection delay (censored
#     detections counted as +Inf) ≤ DETECTION_P95_BUDGET. If no grid point is
#     feasible the fallback order is: lowest censored fraction, then lowest
#     p95 over resolved detections, then lowest false-suspicion rate.
#     Remaining ties: first grid point in declared order. Every scheduled
#     leader-crash instant counts as a detection opportunity (no leader at that
#     instant = censored), and zero leader presence scores FSR = +Inf, so an
#     arm cannot win by keeping the cluster leaderless.

using Dates

include(joinpath(@__DIR__, "lib", "manifest.jl"))
include(joinpath(@__DIR__, "lib", "e3_cells.jl"))

const E3_TUNE_SCHEMA = "e3-tuned-v1"

"""Declared p95 crash-detection budget (proper time; = 10 heartbeats)."""
const DETECTION_P95_BUDGET = 2.0

"""B1 analytic rule: tolerate this many D_sr-stretched heartbeat intervals."""
const B1_MISSES = 4.0

const DEFAULT_TUNE_SEEDS = 1:40

"""Declared per-arm grids (keyword → values), searched as full products."""
const TUNING_GRIDS = Dict{String,Vector{Pair{Symbol,Vector}}}(
    "B0" => [:base_timeout => [0.5, 0.7, 0.9, 1.1, 1.3, 1.6]],
    "B2" => [:base_timeout => [0.4, 0.6, 0.8], :backoff_factor => [1.3, 1.6, 2.0]],
    "B3" => [:ewma_alpha => [0.1, 0.25, 0.5], :miss_tolerance => [1.5, 2.5, 3.5, 5.0]],
    "B4" => [:window_capacity => [12, 24, 48], :quantile_high => [0.9, 0.99],
             :miss_tolerance => [1.5, 2.5, 3.5, 5.0]],
    "B5" => [:phi_threshold => [1.0, 2.0, 3.0, 4.0, 6.0, 8.0]],
    "P1" => [:band_z_high => [2.326, 3.09], :miss_tolerance => [1.5, 2.5, 3.5, 5.0]],
    "P2" => [:band_z_high => [2.326, 3.09], :miss_tolerance => [1.5, 2.5, 3.5, 5.0]],
    "P3" => [:band_z_high => [2.326, 3.09], :miss_tolerance => [1.5, 2.5, 3.5, 5.0]],
    "O0" => [:miss_tolerance => [1.5, 2.5, 3.5]],
)

"""Arm-specific base spec before grid overrides (B2's budget stays shared)."""
base_spec(arm::AbstractString, b0_timeout::Float64) =
    TimingSpec(arm=Symbol(arm), level=E3_ARM_LEVELS[arm], base_timeout=b0_timeout)

function grid_specs(arm::AbstractString, b0_timeout::Float64)
    grid = TUNING_GRIDS[arm]
    specs = TimingSpec[]
    keys_ = first.(grid)
    for combo in Iterators.product(last.(grid)...)
        overrides = Dict{Symbol,Any}(zip(keys_, combo))
        # Array-literal promotion turns integer grids into Float64.
        haskey(overrides, :window_capacity) && (overrides[:window_capacity] = Int(overrides[:window_capacity]))
        arm == "B0" || arm == "B2" || (overrides[:base_timeout] = b0_timeout)
        haskey(overrides, :base_timeout) || (overrides[:base_timeout] = b0_timeout)
        push!(specs, with_timing(base_spec(arm, b0_timeout); overrides...))
    end
    return specs
end

"""B1 timeout for a regime: B1_MISSES × h × worst design D_sr + slack, clamped."""
function b1_spec(cells::Vector{E3Cell}, b0_timeout::Float64)
    worst = 1.0
    slack = 0.0
    heartbeat = cells[1].config.raft.heartbeat_interval
    for cell in cells
        geometry = e3_cell_geometry(cell)
        worst = max(worst, geometry["dsr_start_max"], geometry["dsr_mid_max"], geometry["dsr_late_max"])
        net = cell.config.network
        slack = max(slack, net.processing_delay + net.delay_jitter +
                           (net.reorder_probability > 0 ? net.reorder_delay : 0.0))
    end
    timeout = clamp(B1_MISSES * heartbeat * worst + slack, 0.3, 3.0)
    return with_timing(base_spec("B1", b0_timeout); base_timeout=timeout)
end

struct Evaluation
    suspicions::Int
    follower_heartbeats::Float64
    delays::Vector{Float64}
    censored::Int
    failed::Int
end

# Zero leader presence is not a perfect detector: it is the worst outcome.
fsr(e::Evaluation) = e.follower_heartbeats > 0 ? e.suspicions / e.follower_heartbeats : Inf
censored_fraction(e::Evaluation) =
    (total = length(e.delays) + e.censored; total == 0 ? 0.0 : e.censored / total)

function p95_with_censoring(e::Evaluation)
    values = vcat(e.delays, fill(Inf, e.censored))
    isempty(values) && return NaN
    sort!(values)
    position = 0.95 * (length(values) - 1) + 1
    lo, hi = floor(Int, position), ceil(Int, position)
    (isinf(values[hi]) || lo == hi) && return values[hi]
    return values[lo] + (position - lo) * (values[hi] - values[lo])
end

function p95_resolved(e::Evaluation)
    isempty(e.delays) && return Inf
    return p95_with_censoring(Evaluation(0, 0.0, e.delays, 0, 0))
end

feasible(e::Evaluation; budget=DETECTION_P95_BUDGET) =
    (p = p95_with_censoring(e); !isnan(p) && p <= budget)

"""
Index of the selected candidate per the declared objective (see file header).
NaN p95 (no opportunity at all) is infeasible.
"""
function select_candidate(evaluations::Vector{Evaluation}; budget=DETECTION_P95_BUDGET)
    isempty(evaluations) && throw(ArgumentError("no candidates"))
    ok = [feasible(e; budget=budget) && isfinite(fsr(e)) for e in evaluations]
    if any(ok)
        candidates = findall(ok)
        return (candidates[argmin([fsr(evaluations[i]) for i in candidates])], true)
    end
    keys_ = [(censored_fraction(e), p95_resolved(e), fsr(e)) for e in evaluations]
    return (argmin(keys_), false)
end

function evaluate(spec::TimingSpec, cells::Vector{E3Cell}, seeds)
    jobs = [(cell, seed) for cell in cells for seed in seeds]
    parts = Vector{Evaluation}(undef, length(jobs))
    Threads.@threads for index in eachindex(jobs)
        cell, seed = jobs[index]
        result = try
            run_scenario(cell.config; seed=seed, timing=spec)
        catch
            nothing
        end
        if isnothing(result) || result.status != :completed
            parts[index] = Evaluation(0, 0.0, Float64[], length(E3_LEADER_CRASH_OFFSETS), 1)
            continue
        end
        d = result.adaptation
        window = cell.config.window
        leader_time = result.metrics.leader_availability *
                      (window.measurement_end_coordinate - window.warmup_end_coordinate)
        heartbeats = leader_time * (length(cell.config.raft.members) - 1) /
                     cell.config.raft.heartbeat_interval
        # Every scheduled leader-crash instant is a detection opportunity; one
        # that found no leader (CrashLeader no-op) or never resolved is censored.
        opportunities = E3_CRASH_MODE == :leader ? length(E3_LEADER_CRASH_OFFSETS) :
                        d.leader_crashes
        censored = max(opportunities - length(d.detection_delays_proper), d.censored_detections)
        parts[index] = Evaluation(d.suspicions, heartbeats, copy(d.detection_delays_proper),
                                  censored, 0)
    end
    return Evaluation(
        sum(p.suspicions for p in parts),
        sum(p.follower_heartbeats for p in parts),
        reduce(vcat, (p.delays for p in parts); init=Float64[]),
        sum(p.censored for p in parts),
        sum(p.failed for p in parts),
    )
end

struct TuneUsageError <: Exception
    message::String
end
Base.showerror(io::IO, e::TuneUsageError) = print(io, e.message)

function tune_parse_args(arguments::AbstractVector{<:AbstractString})
    seeds = DEFAULT_TUNE_SEEDS
    cells = String[]
    arms = collect(E3_ARM_NAMES)
    out = nothing
    index = 1
    value(flag) = index + 1 <= length(arguments) ? arguments[index + 1] :
                  throw(TuneUsageError("flag $flag requires a value"))
    while index <= length(arguments)
        flag = arguments[index]
        if flag == "--seeds"
            parts = split(value(flag), ':')
            length(parts) == 2 || throw(TuneUsageError("--seeds expects A:B"))
            lo, hi = tryparse(Int, parts[1]), tryparse(Int, parts[2])
            (isnothing(lo) || isnothing(hi) || lo > hi) && throw(TuneUsageError("bad --seeds"))
            seeds = lo:hi
        elseif flag == "--cells"
            cells = String[strip(s) for s in split(value(flag), ',') if !isempty(strip(s))]
        elseif flag == "--arms"
            arms = String[strip(s) for s in split(value(flag), ',') if !isempty(strip(s))]
        elseif flag == "--out"
            out = String(value(flag))
        else
            throw(TuneUsageError("unknown argument $flag"))
        end
        index += 2
    end
    isnothing(out) && throw(TuneUsageError("--out PATH.toml is required"))
    first(seeds) >= first(E3_TUNING_SEEDS) && last(seeds) <= last(E3_TUNING_SEEDS) ||
        throw(TuneUsageError("tuning seeds $seeds must lie inside E3_TUNING_SEEDS $E3_TUNING_SEEDS"))
    isempty(intersect(seeds, E3_REPORT_SEEDS)) || throw(TuneUsageError("seeds overlap the report range"))
    for arm in arms
        arm in E3_ARM_NAMES || throw(TuneUsageError("unknown arm $arm"))
    end
    "B0" in arms || throw(TuneUsageError("B0 must be tuned (it fixes the shared cold-start timeout)"))
    return (seeds=seeds, cells=cells, arms=arms, out=out)
end

_stat(x) = isfinite(x) ? x : string(x)   # TOML has no Inf/NaN literals in all readers

function tune(config; log=stdout)
    all_cells = build_e3_cells(prefixes=config.cells)
    isempty(all_cells) && throw(TuneUsageError("no cells match $(config.cells)"))
    regimes = unique(cell.regime for cell in all_cells)
    specs = Dict{String,Any}()
    for regime in regimes
        cells = filter(cell -> cell.regime == regime, all_cells)
        b0_timeout = NaN
        for arm in vcat(["B0"], filter(!=("B0"), config.arms))
            candidates = if arm == "B1"
                [b1_spec(cells, b0_timeout)]
            else
                grid_specs(arm, isnan(b0_timeout) ? 1.0 : b0_timeout)
            end
            evaluations = [evaluate(spec, cells, config.seeds) for spec in candidates]
            chosen, was_feasible = select_candidate(evaluations)
            spec = candidates[chosen]
            arm == "B0" && (b0_timeout = spec.base_timeout)
            e = evaluations[chosen]
            record = spec_to_dict(spec)
            record["sel_feasible"] = was_feasible
            record["sel_candidates"] = length(candidates)
            record["sel_fsr_per_follower_heartbeat"] = _stat(fsr(e))
            record["sel_detection_p95_censored_inf"] = _stat(p95_with_censoring(e))
            record["sel_censored_fraction"] = _stat(censored_fraction(e))
            record["sel_failed_runs"] = e.failed
            get!(specs, arm, Dict{String,Any}())[regime] = record
            println(log, "tuned $arm/$regime: ", timing_fingerprint(spec),
                    " feasible=", was_feasible, " fsr=", round(fsr(e); sigdigits=3),
                    " p95=", p95_with_censoring(e), " censored=", round(censored_fraction(e); digits=3))
        end
    end
    provenance = git_provenance()
    return Dict{String,Any}(
        "schema" => E3_TUNE_SCHEMA,
        "prereg" => "v0.3-e3-prereg-r4-draft",
        "created" => Dates.format(now(), "yyyy-mm-ddTHH:MM:SS"),
        "git_sha" => provenance.sha,
        "git_dirty" => provenance.dirty,
        "tuning_seeds" => string(config.seeds),
        "cells" => [cell.id for cell in all_cells],
        "cell_fingerprints" => Dict(cell.id => config_fingerprint(cell.config) for cell in all_cells),
        "objective" => "min suspicions per follower-heartbeat s.t. p95 detection (censored=Inf) <= budget",
        "detection_p95_budget" => DETECTION_P95_BUDGET,
        "b1_misses" => B1_MISSES,
        "threads" => Threads.nthreads(),
        "specs" => specs,
    )
end

function tune_main(arguments)
    config = try
        tune_parse_args(arguments)
    catch error
        error isa TuneUsageError || rethrow()
        println(stderr, "tune_e3: ", error.message)
        return 2
    end
    ispath(config.out) && (println(stderr, "tune_e3: $(config.out) exists; refusing to overwrite"); return 2)
    result = tune(config)
    mkpath(dirname(abspath(config.out)))
    open(config.out, "w") do io
        TOML.print(io, result; sorted=true)
    end
    load_tuned(config.out)   # round-trip + fingerprint verification
    println("wrote ", config.out)
    return 0
end

if abspath(PROGRAM_FILE) == @__FILE__
    exit(tune_main(ARGS))
end
