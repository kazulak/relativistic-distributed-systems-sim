# Tests for the E3 statistics library (experiments/lib/e3_stats.jl) and the
# analyzer CLI refusal path. Synthetic data only; runtime well under a minute.

using Test
using Random

include(joinpath(@__DIR__, "..", "..", "experiments", "lib", "e3_stats.jl"))
using .E3Stats

const R_TEST = 2_000   # resamples in tests (production default is 10k)

# Binomial(n, p) draw without Distributions.jl
binom(rng, n, p) = count(_ -> rand(rng) < p, 1:n)

"""
Build a runs TSV string. `rates` maps arm => per-fire false-suspicion
probability (per cell, via a function of the cell index). Columns are written
in `column_order` (default: shuffled) so tests exercise header-name parsing.
`status_fn(cell, arm, seed)` returns the status string; `safety_fn` likewise
returns "true"/"false"/nothing (omit column).
"""
function make_tsv(; cells=["c1"], seeds=1:40, arms=["B3", "B4", "B5", "P1", "P2", "P3"],
                  p_fn=(cell, arm) -> 0.3, fires=20, detection_fn=(cell, arm, seed) -> (0, ""),
                  status_fn=(cell, arm, seed) -> "completed", safety_fn=nothing, lpf=false,
                  role=nothing, rng_seed=1, shuffle_columns=true)
    rng = Xoshiro(rng_seed)
    cols = ["cell", "family", "arm", "seed", "status", "elections_started", "election_fires", "suspicions",
            "false_suspicion_rate", "committed", "censored", "detection_n", "detection_p50", "detection_p95"]
    lpf && push!(cols, "leader_present_fires")
    safety_fn === nothing || push!(cols, "safety_ok")
    role === nothing || push!(cols, "role")
    order = shuffle_columns ? shuffle(Xoshiro(99), cols) : cols
    lines = [join(order, '\t')]
    for cell in cells, seed in seeds, arm in arms
        susp = binom(rng, fires, p_fn(cell, arm))
        detn, p95 = detection_fn(cell, arm, seed)
        v = Dict(
            "cell" => cell, "family" => "Synthetic", "arm" => arm, "seed" => string(seed),
            "status" => status_fn(cell, arm, seed), "elections_started" => "1",
            "election_fires" => string(lpf ? fires + 5 : fires), "suspicions" => string(susp),
            # when lpf is present, false_suspicion_rate is deliberately "wrong"
            # (per election_fires) so tests can check which denominator is used
            "false_suspicion_rate" => string(susp / (lpf ? fires + 5 : fires)),
            "committed" => "8", "censored" => "0", "detection_n" => string(detn),
            "detection_p50" => "", "detection_p95" => p95,
            "leader_present_fires" => string(fires),
            "safety_ok" => safety_fn === nothing ? "" : string(safety_fn(cell, arm, seed)),
            "role" => role === nothing ? "" : role,
        )
        push!(lines, join([v[c] for c in order], '\t'))
    end
    return join(lines, '\n') * '\n'
end

# Tuning data where B4 is clearly the best arrival arm.
tuning_tsv(; kwargs...) = make_tsv(; seeds=1:30, p_fn=(c, a) -> a == "B4" ? 0.2 : a in ("B3", "B5") ? 0.4 : 0.3, kwargs...)

cfg_test(; kwargs...) = AnalysisConfig(; resamples=R_TEST, tuning_seed_range=1:200, report_seed_range=201:700, kwargs...)

# Delays: every arm detects one crash per replica, p95 ≈ 1.0 ± noise, equal across arms.
equal_delays(cell, arm, seed) = (1, string(1.0 + 0.02 * sin(seed + length(arm))))

@testset "E3 statistics" begin

    @testset "Holm step-down against hand-computed values" begin
        # sorted: 0.005(4)→4·0.005=0.02; 0.01(1)→3·0.01=0.03; 0.03(3)→2·0.03=0.06; 0.04(2)→1·0.04=0.04→max 0.06
        @test holm_adjust([0.01, 0.04, 0.03, 0.005]) ≈ [0.03, 0.06, 0.06, 0.02]
        @test holm_adjust([0.5, 0.001]) ≈ [0.5, 0.002]
        @test holm_adjust([0.3, 0.4, 0.5]) ≈ [0.9, 0.9, 0.9]       # monotone enforcement
        @test holm_adjust([0.2, 0.9, 0.01, 0.02]) ≈ [0.4, 0.9, 0.04, 0.06]
        @test holm_adjust([0.04]) ≈ [0.04]
        @test holm_adjust([0.6, 0.6]) ≈ [1.0, 1.0]                  # capped at 1
        @test_throws ArgumentError holm_adjust([NaN, 0.1])
    end

    @testset "Exact tests and normal helpers" begin
        # d = [1,1,1]: only all-plus and all-minus reach |Σ| = 3 → 2/8
        @test signflip_pvalue([1.0, 1.0, 1.0]; rng=Xoshiro(1)) == 0.25
        @test signflip_pvalue([0.0, 0.0]; rng=Xoshiro(1)) == 1.0
        @test signflip_pvalue([1.0, -1.0]; rng=Xoshiro(1)) == 1.0
        # Monte Carlo branch (n > 13) on a strong effect
        @test signflip_pvalue(fill(0.1, 30); resamples=R_TEST, rng=Xoshiro(1)) ≈ 1 / (R_TEST + 1)
        @test mcnemar_exact(0, 10) ≈ 2 * 0.5^10
        @test mcnemar_exact(3, 3) == 1.0
        @test mcnemar_exact(0, 0) == 1.0
        @test isapprox(mcnemar_exact(2, 8), 2 * sum(binomial(10, k) for k in 0:2) / 2^10; atol=1e-12)
        @test isapprox(norminv(0.975), 1.959963984540054; atol=1e-8)
        @test isapprox(norminv(0.80), 0.8416212335729143; atol=1e-8)
        @test isapprox(normcdf(1.959963984540054), 0.975; atol=1e-6)
        lo, hi = wilson_ci(0, 20)
        @test lo == 0 && 0.1 < hi < 0.2
    end

    @testset "Header-name parsing with shuffled columns" begin
        tsv = make_tsv(; seeds=1:3, arms=["B4", "P2"])
        t = parse_runs(tsv)
        @test length(t) == 6
        @test !t.has_leader_present_fires && !t.has_safety_ok && !t.has_role
        # Same data, unshuffled: identical parsed rows
        t2 = parse_runs(make_tsv(; seeds=1:3, arms=["B4", "P2"], shuffle_columns=false))
        @test [(r.cell, r.arm, r.seed, r.suspicions, r.rate) for r in t.rows] ==
              [(r.cell, r.arm, r.seed, r.suspicions, r.rate) for r in t2.rows]
        @test all(r -> r.rate == r.suspicions / 20, t.rows)
        # leader_present_fires is a consistency check only; the estimand
        # stays suspicions / election_fires (prereg §3).
        tl = parse_runs(make_tsv(; seeds=1:3, arms=["B4", "P2"], lpf=true))
        @test tl.has_leader_present_fires
        @test all(r -> r.rate == r.suspicions / 25 && r.election_fires == 25, tl.rows)
        @test_throws ArgumentError parse_runs(make_tsv(; seeds=1:3, arms=["B4"]);
                                              rate_column="suspicions_per_follower_heartbeat")
        # missing required column → clear error
        bad = replace(tsv, "detection_p95" => "detection_p99")
        err = try parse_runs(bad); nothing catch e; e end
        @test err isa ArgumentError && occursin("detection_p95", err.msg)
        # duplicate (cell, arm, seed) → error
        lines = split(tsv, '\n')
        @test_throws ArgumentError parse_runs(join(vcat(lines[1:2], lines[2:end]), '\n'))
        # seed filter
        @test length(parse_runs(tsv; seeds=2:3)) == 4
        # the real pilot file (old schema) parses, if present
        pilot = joinpath(@__DIR__, "..", "..", "results", "e3", "pilot-20260907_191625", "runs.tsv")
        if isfile(pilot)
            p = load_runs(pilot; seeds=1:2)
            @test length(p) > 0 && !p.has_leader_present_fires
            @test all(r -> r.status in ("completed", "failed"), p.rows)
        end
    end

    @testset "Best-arrival is selected on tuning data only" begin
        tun = parse_runs(tuning_tsv())
        sel = select_best_arrival(tun.rows)
        @test sel.best == "B4"
        # Report data where B3 would look best: the analysis must still use B4.
        rep = parse_runs(make_tsv(; seeds=201:240, rng_seed=2,
                                  p_fn=(c, a) -> a == "B3" ? 0.05 : 0.3))
        res = analyze(tun, rep, cfg_test())
        @test res.best.best == "B4"
        @test all(c -> c.baseline == "B4", res.cells)
        # no tuning data → refuse
        empty_t = parse_runs("cell\tarm\tseed\tstatus\tsuspicions\telection_fires\tfalse_suspicion_rate\tdetection_n\tdetection_p95\n")
        @test_throws ArgumentError analyze(empty_t, rep, cfg_test())
        # overlapping tuning/report seeds → refuse
        @test_throws ArgumentError analyze(tun, parse_runs(make_tsv(; seeds=25:35)), cfg_test())
        # role column contradicting the split → refuse
        @test_throws ArgumentError analyze(tun, parse_runs(make_tsv(; seeds=201:205, role="tuning")), cfg_test())
    end

    @testset "Known effect is recovered and rejected (P2 = 0.7 × B)" begin
        tun = parse_runs(tuning_tsv())
        rep = parse_runs(make_tsv(; seeds=201:280, rng_seed=3, detection_fn=equal_delays,
                                  p_fn=(c, a) -> a in ("P1", "P2", "P3") ? 0.7 * 0.3 : 0.3,
                                  safety_fn=(c, a, s) -> true))
        tun_s = parse_runs(tuning_tsv(; safety_fn=(c, a, s) -> true))
        res = analyze(tun_s, rep, cfg_test())
        @test !res.halted
        @test res.confirmatory_eligible == false     # resamples < 10k is a noted deviation
        c = only(res.cells)
        p2 = only(filter(x -> x.treatment == "P2", c.comparisons))
        @test 0.2 < p2.rel < 0.4                       # true 0.30
        @test p2.rel_ci[1] < 0.3 < p2.rel_ci[2]
        @test p2.rel_ci[1] > 0
        @test p2.diff > 0 && p2.diff_ci[1] > 0
        @test p2.p < 0.01
        @test c.family_p_holm[findfirst(==("P2 superiority"), c.family)] <= 0.05
        @test c.ni.estimable && c.ni.upper < 0.05
        @test c.family_p_holm[end] <= 0.05
        @test c.verdict == "ELIGIBLE"
        # Holm p-values in the report are exactly holm_adjust of the raw family
        @test c.family_p_holm == holm_adjust(c.family_p)
        # unpaired sensitivity agrees in direction
        u = only(x[4] for x in res.unpaired if x[2] == "P2")
        @test u.rel > 0 && u.p < 0.05
        # full-resample config with preregistered seed ranges is confirmatory-eligible
        rep_conf = parse_runs(make_tsv(; seeds=first(E3Stats.REPORT_SEEDS):(first(E3Stats.REPORT_SEEDS) + 79), rng_seed=3,
                                       detection_fn=equal_delays,
                                       p_fn=(c, a) -> a in ("P1", "P2", "P3") ? 0.7 * 0.3 : 0.3,
                                       safety_fn=(c, a, s) -> true))
        res10k = analyze(tun_s, rep_conf, AnalysisConfig(resamples=10_000))
        @test res10k.confirmatory_eligible
        @test !occursin("NOT CONFIRMATORY", render_report(res10k))
    end

    @testset "Null dataset retains H0" begin
        tun = parse_runs(tuning_tsv())
        rep = parse_runs(make_tsv(; seeds=201:280, rng_seed=4, detection_fn=equal_delays,
                                  p_fn=(c, a) -> 0.3))
        res = analyze(tun, rep, cfg_test())
        c = only(res.cells)
        @test all(adj -> adj > 0.05, c.family_p_holm[1:3])
        @test c.verdict == "NOT MET"
        @test occursin("not met in any", res.overall_verdict)
    end

    @testset "No crash detections → NI NOT ESTIMABLE → INDETERMINATE" begin
        tun = parse_runs(tuning_tsv())
        rep = parse_runs(make_tsv(; seeds=201:280, rng_seed=5,
                                  p_fn=(c, a) -> a in ("P1", "P2", "P3") ? 0.5 * 0.3 : 0.3))
        res = analyze(tun, rep, cfg_test())
        c = only(res.cells)
        @test c.superiority_met
        @test !c.ni.estimable && occursin("NOT ESTIMABLE", c.ni.reason)
        @test c.family_p[end] == 1.0
        @test c.verdict == "INDETERMINATE"
        @test startswith(replace(res.overall_verdict, "[NOT CONFIRMATORY] " => ""), "INDETERMINATE")
        @test occursin("NOT ESTIMABLE", render_report(res))
    end

    @testset "Zero baseline events → relative effect undefined" begin
        tun = parse_runs(tuning_tsv())
        rep = parse_runs(make_tsv(; seeds=201:230, rng_seed=6, p_fn=(c, a) -> a == "B4" ? 0.0 : 0.1))
        res = analyze(tun, rep, cfg_test())
        c = only(res.cells)
        p2 = only(filter(x -> x.treatment == "P2", c.comparisons))
        @test p2.mean_b == 0 && isnan(p2.rel)
        @test c.verdict == "UNDEFINED (no baseline events)"
        @test occursin("undefined (mean_B = 0)", render_report(res))
    end

    @testset "Failed runs: pairwise exclusion and differential missingness" begin
        tun = parse_runs(tuning_tsv())
        # B4 fails on half the replicas; treatments never fail.
        st(c, a, s) = (a == "B4" && iseven(s)) ? "failed" : "completed"
        rep = parse_runs(make_tsv(; seeds=201:260, rng_seed=7, status_fn=st))
        res = analyze(tun, rep, cfg_test())
        c = only(res.cells)
        p2 = only(filter(x -> x.treatment == "P2", c.comparisons))
        @test p2.n_pairs == 30 && p2.excluded_status == 30
        @test res.status_counts[("c1", "B4")] == (60, 30)
        @test res.status_counts[("c1", "P2")] == (60, 0)
        m = only(filter(x -> x.treatment == "P2", res.missingness))
        @test m.t_ok_b_failed == 30 && m.t_failed_b_ok == 0
        @test m.p_mcnemar < 1e-6
        @test res.differential_missingness_flag
        @test occursin("differential missingness detected", render_report(res))
        # the alternate policy (include failed) uses all 60 pairs
        alt = only(filter(x -> x.treatment == "P2", res.alt_policy_comparisons))
        @test res.alt_policy == :include_failed && alt.n_pairs == 60
        # balanced failures → no flag
        st2(c, a, s) = s % 10 == 0 ? "failed" : "completed"
        res2 = analyze(tun, parse_runs(make_tsv(; seeds=201:260, rng_seed=8, status_fn=st2)), cfg_test())
        @test !res2.differential_missingness_flag
        # a completed row with a blank required value is a data error, a failed one is not
        blank = "cell\tarm\tseed\tstatus\tsuspicions\telection_fires\tfalse_suspicion_rate\tdetection_n\tdetection_p95\n"
        @test length(parse_runs(blank * "c\tP2\t1\tfailed\t\t\t\t\t\n")) == 1
        @test_throws ArgumentError parse_runs(blank * "c\tP2\t1\tcompleted\t\t\t\t\t\n")
    end

    @testset "safety_ok = false halts with no verdicts" begin
        tun = parse_runs(tuning_tsv(; safety_fn=(c, a, s) -> true))
        rep = parse_runs(make_tsv(; seeds=201:220, safety_fn=(c, a, s) -> !(a == "P3" && s == 207),
                                  p_fn=(c, a) -> a == "P2" ? 0.1 : 0.3))
        res = analyze(tun, rep, cfg_test())
        @test res.halted
        @test isempty(res.cells)
        @test length(res.violations) == 1 && res.violations[1].arm == "P3"
        @test startswith(res.overall_verdict, "HALTED")
        txt = render_report(res)
        @test occursin("HALTED", txt) && !occursin("ELIGIBLE", txt)
        # a violation in the tuning data also halts
        tun_bad = parse_runs(tuning_tsv(; safety_fn=(c, a, s) -> s != 3))
        @test analyze(tun_bad, parse_runs(make_tsv(; seeds=201:210)), cfg_test()).halted
    end

    @testset "Power analysis: formula, no smoothing, undefined cells" begin
        pilot = parse_runs(make_tsv(; cells=["a", "zero"], seeds=1:24, rng_seed=9,
                                    p_fn=(c, a) -> c == "zero" && a == "B4" ? 0.0 : (a == "B4" ? 0.2 : 0.3)))
        pa = power_analysis(pilot.rows; treatments=["P2"], resamples=R_TEST)
        @test pa.best.best == "B4"
        ra = only(r for r in pa.rows if r.cell == "a")
        rz = only(r for r in pa.rows if r.cell == "zero")
        @test rz.status == "no events: effect undefined" && isnan(rz.power_target)
        z = norminv(0.975) + norminv(0.80)
        @test ra.n_required ≈ z^2 * ra.sd_d^2 / (0.15 * ra.mean_b)^2
        λ = 0.15 * ra.mean_b * sqrt(120) / ra.sd_d
        @test ra.power_target ≈ normcdf(λ - norminv(0.975)) + normcdf(-λ - norminv(0.975))
        # power at the required N is 0.80 (up to the negligible second tail)
        λn = 0.15 * ra.mean_b * sqrt(ra.n_required) / ra.sd_d
        @test isapprox(normcdf(λn - norminv(0.975)), 0.80; atol=1e-6)
        txt = render_power(pa; source="synthetic")
        @test occursin("PROPOSED", txt) && occursin("no events: effect undefined", txt)
    end

    @testset "CLI refuses without --tuning" begin
        script = joinpath(@__DIR__, "..", "..", "experiments", "analyze_e3.jl")
        tmp = tempname() * ".tsv"
        write(tmp, make_tsv(; seeds=201:203))
        err = IOBuffer()
        proc = run(pipeline(ignorestatus(`$(Base.julia_cmd()) --startup-file=no $script --report $tmp`); stderr=err, stdout=devnull))
        @test proc.exitcode == 2
        @test occursin("--tuning", String(take!(err)))
        rm(tmp; force=true)
    end
end
