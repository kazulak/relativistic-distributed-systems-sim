# E3 design tests: runner CLI/guards, tuner selection, cells/crash design,
# D_sr regime realization, timing accounting, and the homothetic clock.

module E3RunnerHarness
include(joinpath(@__DIR__, "..", "..", "experiments", "run_e3.jl"))
end

module E3TunerHarness
include(joinpath(@__DIR__, "..", "..", "experiments", "tune_e3.jl"))
end

const E3R = E3RunnerHarness
const E3T = E3TunerHarness

clean_tree = (sha="abc", dirty=false, diff_sha256="x")
dirty_tree = (sha="abc", dirty=true, diff_sha256="y")
never_exists = _ -> false

@testset "E3 runner CLI parsing" begin
    c = E3R.parse_args(["--role", "tuning", "--replicas", "201:320", "--seed-base", "5",
                        "--arms", "B0,P2", "--cells", "approach_,stationary_r0.1",
                        "--out", "x/y", "--tuned", "t.toml"])
    @test c.replicas == 201:320            # regression: flags used to be silently ignored
    @test c.seed_base == 5
    @test c.seeds == 206:325
    @test c.arms == ["B0", "P2"]
    @test c.cells == ["approach_", "stationary_r0.1"]
    @test c.out == "x/y"
    @test c.tuned == "t.toml"
    @test c.role == "tuning"
    @test !c.confirmatory
    d = E3R.parse_args(["--role", "report", "--confirmatory"])
    @test d.confirmatory && d.replicas == 1:24 && d.seed_base == 0
    @test length(d.arms) == 10
    @test_throws E3R.UsageError E3R.parse_args(String[])                       # role required
    @test_throws E3R.UsageError E3R.parse_args(["--role", "pilot"])
    @test_throws E3R.UsageError E3R.parse_args(["--role", "tuning", "--bogus"])
    @test_throws E3R.UsageError E3R.parse_args(["--role", "tuning", "--replicas", "9:1"])
    @test_throws E3R.UsageError E3R.parse_args(["--role", "tuning", "--replicas"])
    @test_throws E3R.UsageError E3R.parse_args(["--role", "tuning", "--arms", "B9"])
end

@testset "E3 runner guards" begin
    guard(args; provenance=clean_tree, out_exists=never_exists) =
        E3R.check_guards(E3R.parse_args(args); provenance=provenance, out_exists=out_exists)
    @test isnothing(guard(["--role", "tuning", "--replicas", "1:24"]))
    # tuning must stay inside the tuning range and away from report seeds
    @test_throws E3R.UsageError guard(["--role", "tuning", "--replicas", "190:210"])
    @test_throws E3R.UsageError guard(["--role", "tuning", "--seed-base", "1000", "--replicas", "1:5"])
    @test_throws E3R.UsageError guard(["--role", "tuning", "--confirmatory"])
    # report preconditions
    tuned = tempname() * ".toml"
    write(tuned, "schema = \"e3-tuned-v1\"\n")
    base = ["--role", "report", "--seed-base", "1000", "--replicas", "1:120", "--out", "o"]
    @test isnothing(guard(vcat(base, ["--confirmatory", "--tuned", tuned])))
    @test_throws E3R.UsageError guard(vcat(base, ["--tuned", tuned]))                  # no --confirmatory
    @test_throws E3R.UsageError guard(vcat(base, ["--confirmatory"]))                  # no --tuned
    @test_throws E3R.UsageError guard(vcat(base, ["--confirmatory", "--tuned", tuned]);
                                      provenance=dirty_tree)                           # dirty tree
    @test_throws E3R.UsageError guard(["--role", "report", "--confirmatory", "--tuned", tuned,
                                       "--seed-base", "200", "--replicas", "1:120", "--out", "o"])  # contaminated seeds
    @test_throws E3R.UsageError guard(["--role", "report", "--confirmatory", "--tuned", tuned,
                                       "--seed-base", "1000", "--replicas", "1:120"])  # --out required
    @test_throws E3R.UsageError guard(vcat(base, ["--confirmatory", "--tuned", tuned]);
                                      out_exists=_ -> true)                            # never overwrite
    @test_throws E3R.UsageError guard(vcat(base, ["--confirmatory", "--tuned", "missing.toml"]))
    @test E3R.REPORT_SEEDS === E3R.E3_REPORT_SEEDS
    @test isempty(intersect(E3R.E3_REPORT_SEEDS, 201:224))
    @test isempty(intersect(E3R.E3_REPORT_SEEDS, E3R.E3_TUNING_SEEDS))
    # main returns a usage exit code and never runs on bad input
    @test E3R.main(["--role", "report"]; provenance=clean_tree) == 2
end

@testset "E3 tuner selection and CLI" begin
    E = E3T.Evaluation
    # feasible candidates: lowest FSR wins
    evals = [E(5, 100.0, [1.0, 1.1], 0, 0), E(1, 100.0, [1.5, 1.9], 0, 0), E(0, 100.0, [3.0], 0, 0)]
    @test E3T.select_candidate(evals) == (2, true)
    # leaderless candidate (zero heartbeats) never wins by FSR = 0
    evals = [E(0, 0.0, Float64[], 2, 0), E(2, 50.0, [1.0], 0, 0)]
    @test E3T.select_candidate(evals) == (2, true)
    # all infeasible: fall back to censored fraction, then resolved p95
    evals = [E(0, 10.0, [1.0], 3, 0), E(0, 10.0, [2.5, 2.6], 1, 0), E(0, 10.0, [1.2, 1.3], 1, 0)]
    @test E3T.select_candidate(evals) == (3, false)
    @test E3T.p95_with_censoring(E(0, 1.0, [1.0], 1, 0)) == Inf
    c = E3T.tune_parse_args(["--seeds", "1:3", "--cells", "stationary_", "--out", "t.toml"])
    @test c.seeds == 1:3 && c.cells == ["stationary_"]
    @test_throws E3T.TuneUsageError E3T.tune_parse_args(["--seeds", "1:3"])              # --out
    @test_throws E3T.TuneUsageError E3T.tune_parse_args(["--seeds", "1001:1003", "--out", "t"])
    @test_throws E3T.TuneUsageError E3T.tune_parse_args(["--seeds", "150:250", "--out", "t"])
    @test_throws E3T.TuneUsageError E3T.tune_parse_args(["--arms", "P2", "--out", "t"])  # B0 required
    specs = E3T.grid_specs("B4", 0.9)
    @test length(specs) == 24 && all(s -> s.base_timeout == 0.9, specs)
    @test all(s -> s.window_capacity isa Int, specs)
    @test length(unique(timing_fingerprint.(specs))) == 24
end

@testset "E3 confirmatory grid" begin
    cells = E3R.build_e3_cells()
    @test length(cells) == 48
    @test length(unique(c.id for c in cells)) == 48
    @test length(unique(config_fingerprint(c.config) for c in cells)) == 48
    @test Set(c.regime for c in cells) == Set(["approach", "stationary", "recede25", "recede50"])
    @test length(E3R.build_e3_cells(prefixes=["approach_r0.1"])) == 6
    for c in cells
        crash_faults = filter(f -> f.fault isa CrashLeader, c.config.faults)
        @test length(crash_faults) == length(E3R.E3_LEADER_CRASH_OFFSETS)
        w = c.config.window
        @test all(w.warmup_end_coordinate < f.coordinate_time < w.measurement_end_coordinate
                  for f in crash_faults)
    end
end

@testset "D_sr regimes realized at measurement start" begin
    targets = Dict(-0.25 => 0.7745966692414834, 0.0 => 1.0, 0.25 => 1.2909944487358056,
                   0.5 => 1.7320508075688772)
    for (beta, target) in targets, traj in (:inertial, :onset)
        config = dsr_regime_scenario(beta=beta, rho=0.1, trajectory=traj)
        w = config.window
        ratios = filter(!isnan, vec(dsr_pairwise_ratios(config, w.warmup_end_coordinate)))
        on_target = count(r -> isapprox(r, target; rtol=1.0e-6), ratios)
        @test on_target >= 18                        # 9 of 10 unordered pairs, both directions
        @test isapprox(sort(ratios)[10], target; rtol=1.0e-6)
        # formation never collapses or crosses during the run
        @test minimum(nearest_neighbour_rho(config, t)
                      for t in range(w.start_coordinate, w.censor_coordinate; length=201)) > 0.05
        if traj == :onset
            later = filter(!isnan, vec(dsr_pairwise_ratios(config, w.measurement_end_coordinate - 0.3)))
            @test !isapprox(sort(later)[10], target; rtol=1.0e-3)   # non-stationary inside window
        end
    end
    @test_throws ArgumentError dsr_regime_scenario(beta=0.25, cluster_size=7)
end

@testset "homothetic clock accuracy and timer boundary" begin
    config = dsr_regime_scenario(beta=0.5, rho=0.1, trajectory=:onset)
    w = config.worldlines[4]
    @test w isa HomotheticWorldline
    @test !isempty(worldline_kinks(w))
    # composite Simpson reference, split at kinks
    reference(t1, t2) = begin
        points = sort(unique(vcat(t1, filter(k -> t1 < k < t2, worldline_kinks(w)), t2)))
        total = 0.0
        for i in 1:(length(points) - 1)
            a, b = points[i], points[i + 1]
            n = 4000
            h = (b - a) / n
            f(t) = sqrt(1 - sum(abs2, coordinate_velocity(w, t)))
            s = f(a) + f(b) + sum((isodd(j) ? 4 : 2) * f(a + j * h) for j in 1:(n - 1))
            total += s * h / 3
        end
        total
    end
    for (t1, t2) in ((0.0, 11.0), (5.1, 7.3), (6.9, 7.05))
        @test isapprox(proper_time_between(config.spacetime, w, t1, t2), reference(t1, t2);
                       rtol=1.0e-11, atol=1.0e-13)
    end
    clock = ProperTimeClock(config.spacetime, w)
    for local_value in range(0.1, 9.0; length=97)
        @test local_time(clock, coordinate_time(clock, local_value)) >= local_value
        @test Research._timer_coordinate(clock, local_value, 0.0) >= 0.0
        @test local_time(clock, Research._timer_coordinate(clock, local_value, 0.0)) >= local_value
    end
end

@testset "E3 timing accounting: fires, suspicions, crash detection" begin
    cells = E3R.build_e3_cells(prefixes=["stationary_r0.1_loss15r20_inertial"])
    config = only(cells).config
    aggressive = TimingSpec(arm=:B0, base_timeout=0.3)
    saw_suspicion = false
    for seed in 1:4
        result = run_scenario(config; seed=seed, timing=aggressive)
        @test result.status == :completed
        @test all_safety(result.safety)
        d = result.adaptation
        @test d.suspicions <= d.leader_present_fires <= d.election_fires
        @test d.election_fires == 0 ? isnan(d.false_suspicion_rate) :
              d.false_suspicion_rate ≈ d.suspicions / d.election_fires
        @test length(d.detection_delays_proper) + d.censored_detections == d.leader_crashes
        @test all(x -> x > 0.0, d.detection_delays_proper)
        saw_suspicion |= d.suspicions > 0
    end
    @test saw_suspicion
    # With the default arm, stationary crash cells yield detections in most runs.
    detected = 0
    runs = 0
    for cell in E3R.build_e3_cells(prefixes=["stationary_r0.1"]), seed in 1:2
        result = run_scenario(cell.config; seed=seed, timing=E3R.default_arm_spec("P2"))
        runs += 1
        detected += !isempty(result.adaptation.detection_delays_proper)
        @test result.adaptation.leader_crashes <= length(E3R.E3_LEADER_CRASH_OFFSETS)
        @test isapprox(result.adaptation.dsr_measured, 1.0; atol=0.1)
    end
    @test detected >= 0.8runs
    # Realized D_sr follows the design in a moving regime.
    receding = only(E3R.build_e3_cells(prefixes=["recede25_r0.1_clean_inertial"]))
    result = run_scenario(receding.config; seed=1, timing=E3R.default_arm_spec("B0"))
    @test isapprox(result.adaptation.dsr_measured, receding.dsr_target; rtol=0.03)
    # O0 oracle arm runs and is flagged as reference-only.
    oracle = run_scenario(receding.config; seed=1, timing=E3R.default_arm_spec("O0"))
    @test oracle.status == :completed && oracle.adaptation.arm === :O0
    @test :O0 in REFERENCE_ARMS
end

@testset "E3 runner end-to-end (tiny)" begin
    out = joinpath(mktempdir(), "run")
    code = E3R.main(["--role", "tuning", "--replicas", "1:1", "--arms", "B0,P2",
                     "--cells", "stationary_r0.1_clean_inertial", "--out", out];
                    provenance=clean_tree)
    @test code == 0
    lines = readlines(joinpath(out, "runs.tsv"))
    header = split(lines[1], '\t')
    @test header == E3R.HEADER
    for name in ("cell", "arm", "seed", "status", "suspicions", "election_fires",
                 "false_suspicion_rate", "detection_n", "detection_p95",
                 "leader_present_fires", "failure_reason", "safety_ok", "role",
                 "dsr_at_start", "dsr_measured", "beta", "crash_count")
        @test name in header
    end
    @test length(lines) == 3
    @test all(length(split(l, '\t')) == length(header) for l in lines)
    manifest = read(joinpath(out, "manifest.json"), String)
    @test occursin("\"git_dirty\": false", manifest)
    @test occursin("\"role\": \"tuning\"", manifest)
    # never append to an existing directory
    @test E3R.main(["--role", "tuning", "--replicas", "1:1", "--out", out]; provenance=clean_tree) == 2
end
