@testset "causal quorum completion bounds (Claim C3)" begin
    # 1. Co-located control has zero spatial distance, so causal quorum bound is zero
    control = canonical_scenario(ColocatedControl; cluster_size=3)
    bound_control = causal_quorum_bound(control, 1, 0.0)
    @test bound_control == 0.0

    # 2. Separated static baseline with known geometry
    # Cluster size 3, collinear spacing. Node 1 is at -spacing, Node 2 is at 0, Node 3 is at +spacing.
    # Quorum size is 2 nodes (leader + 1 peer).
    # Nearest peer to Node 1 is Node 2 at distance spacing = rho * c * heartbeat.
    # Round-trip light time: 2 * spacing / c = 2 * rho * heartbeat.
    static_cfg = canonical_scenario(SeparatedStaticBaseline; cluster_size=3)
    heartbeat = static_cfg.raft.heartbeat_interval
    c = static_cfg.spacetime.c
    rho = dimensionless_parameters(static_cfg).rho
    expected_rtt = 2.0 * rho * heartbeat
    bound_static = causal_quorum_bound(static_cfg, 1, 0.0; leader_node=1)
    @test isapprox(bound_static, expected_rtt; atol=1.0e-12)

    # Universal lower bound over all potential leaders
    min_bound = causal_quorum_bound(static_cfg, 1, 0.0)
    @test isapprox(min_bound, expected_rtt; atol=1.0e-12)

    # 3. Receding inertial scenario: distance grows over time, so bound increases monotonically
    receding_cfg = canonical_scenario(AsymmetricRecedingInertial; cluster_size=3)
    t_early = receding_cfg.window.warmup_end_coordinate
    t_late = receding_cfg.window.measurement_end_coordinate
    bound_early = causal_quorum_bound(receding_cfg, 1, t_early)
    bound_late = causal_quorum_bound(receding_cfg, 1, t_late)
    @test bound_early > 0.0
    @test bound_late > bound_early

    # 4. Simulation write operations never complete below the physical causal lower bound
    small_wl = WorkloadSpec(operation_count=4, read_every=0) # pure writes
    for family in instances(ScenarioFamily)
        config = canonical_scenario(family; cluster_size=3, workload=small_wl)
        result = run_scenario(config; seed=0x42)
        @test result.status == :completed
        ok, min_margin, violations = verify_causal_quorum_bounds(config, result.operations)
        @test ok
        @test isempty(violations)
        @test min_margin >= -4096eps(Float64)
    end
end
