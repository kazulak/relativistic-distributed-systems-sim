#!/usr/bin/env julia

# E3 analysis CLI: preregistered paired comparison of PT-FD arms against the
# best arrival-only arm (docs/PRE_REGISTRATION_E3.md §2, §5, §7, §8, §11).
# All statistics live in experiments/lib/e3_stats.jl.
#
# Usage:
#   julia --project=. experiments/analyze_e3.jl \
#       --tuning <tuning.tsv> [--tuning-seeds a:b] \
#       --report <report.tsv> [--report-seeds a:b] \
#       [--status-policy pairwise-exclude|include-failed] \
#       [--best-arrival-scope global|per-cell] \
#       [--resamples 10000] [--rng-seed 227] [--ni-min-pairs 10] \
#       [--out report.md]
#
# --tuning is mandatory: best-arrival is selected on tuning traces only and
# never on report rows. The same file may be given for --tuning and --report
# if disjoint --tuning-seeds / --report-seeds ranges are given.
#
# Exit codes: 0 analysis written; 2 usage/input error; 3 safety halt (§11).

include(joinpath(@__DIR__, "lib", "e3_stats.jl"))
using .E3Stats

const USAGE = """
usage: julia --project=. experiments/analyze_e3.jl --tuning <tsv> [--tuning-seeds a:b]
                                                   --report <tsv> [--report-seeds a:b]
                                                   [--status-policy pairwise-exclude|include-failed]
                                                   [--best-arrival-scope global|per-cell]
                                                   [--rate-column false_suspicion_rate|suspicions_per_follower_heartbeat]
                                                   [--resamples N] [--rng-seed N] [--ni-min-pairs N] [--out file.md]"""

function parse_args(arguments)
    opts = Dict{String,String}()
    i = 1
    while i <= length(arguments)
        a = arguments[i]
        a in ("-h", "--help") && return nothing
        startswith(a, "--") || throw(ArgumentError("unexpected argument '$a'"))
        i < length(arguments) || throw(ArgumentError("flag $a needs a value"))
        opts[a[3:end]] = arguments[i+1]
        i += 2
    end
    known = Set(["tuning", "tuning-seeds", "report", "report-seeds", "status-policy", "best-arrival-scope",
                 "resamples", "rng-seed", "ni-min-pairs", "out", "rate-column"])
    for k in keys(opts)
        k in known || throw(ArgumentError("unknown flag --$k"))
    end
    return opts
end

function main(arguments)
    opts = try
        parse_args(arguments)
    catch err
        println(stderr, "error: ", sprint(showerror, err)); println(stderr, USAGE); return 2
    end
    opts === nothing && (println(USAGE); return 0)
    if !haskey(opts, "tuning")
        println(stderr, "error: --tuning <tsv> is required. Best-arrival must be selected on TUNING traces ",
                "(prereg §2, §7); this analyzer never selects on report rows. Refusing to run.")
        println(stderr, USAGE)
        return 2
    end
    haskey(opts, "report") || (println(stderr, "error: --report <tsv> is required"); println(stderr, USAGE); return 2)

    try
        tseeds = haskey(opts, "tuning-seeds") ? parse_seed_range(opts["tuning-seeds"]) : nothing
        rseeds = haskey(opts, "report-seeds") ? parse_seed_range(opts["report-seeds"]) : nothing
        if abspath(opts["tuning"]) == abspath(opts["report"]) && (tseeds === nothing || rseeds === nothing)
            throw(ArgumentError("--tuning and --report are the same file: give disjoint --tuning-seeds and --report-seeds"))
        end
        policy = get(opts, "status-policy", "pairwise-exclude")
        policy in ("pairwise-exclude", "include-failed") || throw(ArgumentError("bad --status-policy '$policy'"))
        scope = get(opts, "best-arrival-scope", "global")
        scope in ("global", "per-cell") || throw(ArgumentError("bad --best-arrival-scope '$scope'"))
        cfg = AnalysisConfig(
            resamples=parse(Int, get(opts, "resamples", "10000")),
            rng_seed=UInt64(parse(Int, get(opts, "rng-seed", "227"))),
            ni_min_pairs=parse(Int, get(opts, "ni-min-pairs", "10")),
            status_policy=Symbol(replace(policy, "-" => "_")),
            best_arrival_scope=Symbol(replace(scope, "-" => "_")),
        )
        rate_column = get(opts, "rate-column", "false_suspicion_rate")
        rate_column in ("false_suspicion_rate", "suspicions_per_follower_heartbeat") ||
            throw(ArgumentError("bad --rate-column '$rate_column'"))
        tuning = load_runs(opts["tuning"]; seeds=tseeds, rate_column=rate_column)
        report = load_runs(opts["report"]; seeds=rseeds, rate_column=rate_column)
        tuning_label = opts["tuning"] * (tseeds === nothing ? "" : " [seeds $(tseeds)]")
        report_label = opts["report"] * (rseeds === nothing ? "" : " [seeds $(rseeds)]")
        tuning = RunTable(tuning.rows, tuning_label, tuning.columns, tuning.has_leader_present_fires,
                          tuning.has_safety_ok, tuning.has_role, tuning.has_failure_reason)
        report = RunTable(report.rows, report_label, report.columns, report.has_leader_present_fires,
                          report.has_safety_ok, report.has_role, report.has_failure_reason)
        result = analyze(tuning, report, cfg)
        text = render_report(result)
        if haskey(opts, "out")
            mkpath(dirname(abspath(opts["out"])))
            write(opts["out"], text)
            println(stderr, "wrote ", opts["out"])
        end
        print(text)
        return result.halted ? 3 : 0
    catch err
        err isa ArgumentError || rethrow()
        println(stderr, "error: ", err.msg)
        return 2
    end
end

exit(main(ARGS))
