#!/usr/bin/env julia

# E3 pilot power analysis — PROPOSED revision of the sample-size procedure in
# docs/PRE_REGISTRATION_E3.md §9. The preregistered formula is superseded only
# if a new preregistration addendum adopts this procedure.
#
# Procedure (implemented in experiments/lib/e3_stats.jl, `power_analysis`):
#  1. best-arrival among B3/B4/B5 on the pilot (a tuning-seed dataset);
#  2. per cell and treatment, paired differences d = r_B − r_T of per-replica
#     false-suspicion rates (both runs completed), σ_d = SD(d); SD of the ratio
#     estimand 1 − mean_T/mean_B by paired bootstrap;
#  3. N = (z_{1−α/2} + z_{power})² σ_d² / Δ² with Δ = 0.15·mean_B;
#  4. achieved power at N = 120 (the frozen cap) per cell;
#  5. no smoothing constants, no floors; mean_B = 0 → "no events: effect undefined".
#
# Usage:
#   julia --project=. experiments/power_analysis_e3.jl <pilot runs.tsv> [--seeds a:b]
#       [--n-target 120] [--resamples 10000] [--rng-seed 227] [--out power.md]

include(joinpath(@__DIR__, "lib", "e3_stats.jl"))
using .E3Stats

const USAGE = "usage: julia --project=. experiments/power_analysis_e3.jl <pilot runs.tsv> [--seeds a:b] [--n-target 120] [--resamples N] [--rng-seed N] [--out file.md]"

function main(arguments)
    (isempty(arguments) || arguments[1] in ("-h", "--help")) && (println(stderr, USAGE); return 2)
    path = arguments[1]
    opts = Dict{String,String}()
    rest = arguments[2:end]
    isodd(length(rest)) && (println(stderr, "error: every flag needs a value\n", USAGE); return 2)
    for i in 1:2:length(rest)
        k = rest[i]
        k in ("--seeds", "--n-target", "--resamples", "--rng-seed", "--out") ||
            (println(stderr, "error: unknown flag $k\n", USAGE); return 2)
        opts[k[3:end]] = rest[i+1]
    end
    try
        seeds = haskey(opts, "seeds") ? parse_seed_range(opts["seeds"]) : nothing
        table = load_runs(path; seeds=seeds)
        bad = [r for r in table.rows if r.safety_ok === false]
        isempty(bad) || (println(stderr, "error: $(length(bad)) pilot rows have safety_ok = false; prereg §11 halt"); return 3)
        report_like = [r for r in table.rows if r.seed in 201:700 || (!ismissing(r.role) && r.role == "report")]
        isempty(report_like) ||
            (println(stderr, "error: input contains $(length(report_like)) report-range/report-role rows; the pilot must be tuning data only"); return 2)
        pa = power_analysis(table.rows;
                            n_target=parse(Int, get(opts, "n-target", "120")),
                            resamples=parse(Int, get(opts, "resamples", "10000")),
                            rng_seed=parse(Int, get(opts, "rng-seed", "227")))
        text = render_power(pa; source=path, seeds=haskey(opts, "seeds") ? opts["seeds"] : "all in file")
        if haskey(opts, "out")
            mkpath(dirname(abspath(opts["out"])))
            write(opts["out"], text)
            println(stderr, "wrote ", opts["out"])
        end
        print(text)
        return 0
    catch err
        err isa ArgumentError || rethrow()
        println(stderr, "error: ", err.msg)
        return 2
    end
end

exit(main(ARGS))
