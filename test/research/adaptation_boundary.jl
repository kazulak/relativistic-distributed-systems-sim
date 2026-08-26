@testset "timing boundary: no-op equivalence" begin
    config = canonical_scenario(SeparatedStaticBaseline; cluster_size=3, workload=SMALL_WORKLOAD)
    implicit = run_scenario(config; seed=0x1234)
    explicit = run_scenario(config; seed=0x1234, timing=nothing)
    @test result_signature(implicit) == result_signature(explicit)
    @test isnothing(implicit.adaptation)
    @test isnothing(explicit.adaptation)
end

@testset "PT-FD I2 attaches metadata and stays safe under churn" begin
    spec = TimingSpec(arm=:P2, level=2; base_timeout=0.9)
    stress = canonical_scenario(PartitionDropStress; cluster_size=3, workload=SMALL_WORKLOAD)
    result = run_scenario(stress; seed=0x51, timing=spec)
    @test result.status == :completed
    @test all_safety(result.safety)
    d = something(result.adaptation)
    @test d.arm === :P2
    @test d.information_level == 2
    @test d.metadata_bytes_sent > 0
    @test d.election_fires >= 1
    @test 0.0 <= d.false_suspicion_rate <= 1.0
    @test d.timing_fingerprint == timing_fingerprint(spec)
end

@testset "detector bands recover known intervals" begin
    spec_p2 = TimingSpec(arm=:P2, level=2; base_timeout=0.5)
    runtime = Research.ArmRuntime(spec_p2)
    tau_arrive = 0.0
    for seq in 1:12
        tau_emit = 0.2 * seq
        tau_arrive += 0.4
        observe_arrival!(runtime, spec_p2, UInt64(seq), tau_emit, tau_arrive)
    end
    lo, hi = election_band(runtime, spec_p2)
    @test lo < hi
    midpoint = (lo + hi) / 2
    @test isapprox(midpoint, 0.4; rtol=0.35)

    stale_observations = runtime.observations
    observe_arrival!(runtime, spec_p2, UInt64(3), 0.61, tau_arrive + 0.05)
    @test runtime.observations == stale_observations

    before = election_band(runtime, spec_p2)[2]
    for _ in 1:6
        note_election_started!(runtime)
    end
    widened = election_band(runtime, spec_p2)[2]
    @test widened >= before
end

@testset "quantile arm tracks empirical arrivals" begin
    spec_b4 = TimingSpec(arm=:B4, level=0; base_timeout=0.5)
    runtime = Research.ArmRuntime(spec_b4)
    t = 0.0
    for _ in 1:15
        t += 0.6
        observe_arrival!(runtime, spec_b4, nothing, nothing, t)
    end
    lo, hi = election_band(runtime, spec_b4)
    @test 0.4 <= lo <= 0.6 <= hi
end

@testset "approaching motion validates and runs" begin
    approaching = canonical_scenario(AsymmetricRecedingInertial; cluster_size=3, beta=-0.25)
    @test validate_config(approaching)
    result = run_scenario(approaching; seed=0x77)
    @test result.status == :completed
    @test all_safety(result.safety)
    @test dimensionless_parameters(approaching).rho > 0.0
end

@testset "trajectory change continuity and execution" begin
    tc = trajectory_change_scenario(cluster_size=3)
    @test validate_config(tc)
    onset = 3.0
    wl = tc.worldlines[2]
    v_before = coordinate_velocity(wl, onset - 1.0e-9)
    v_after = coordinate_velocity(wl, onset + 1.0e-9)
    @test isapprox(v_after[1], v_before[1]; rtol=1.0e-6)
    p_before = position_at(wl, onset - 1.0e-7)
    p_after = position_at(wl, onset + 1.0e-7)
    @test isapprox(p_after[1], p_before[1]; atol=1.0e-4)
    result = run_scenario(tc; seed=0x99)
    @test result.status == :completed
    @test all_safety(result.safety)
end
