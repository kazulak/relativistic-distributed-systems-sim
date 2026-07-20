@testset "proper-time timing policies" begin
    baseline = TimingPolicySet(
        StaticElectionPolicy(0.15, 0.30),
        StaticHeartbeatPolicy(0.05),
    )
    at_minimum = evaluate_timing(baseline; election_draw=0.0)
    at_maximum = evaluate_timing(baseline; election_draw=1.0)
    @test is_ready(at_minimum.election_window)
    @test at_minimum.selected_election_timeout == 0.15
    @test at_maximum.selected_election_timeout == 0.30
    @test at_minimum.heartbeat.interval == 0.05

    zero_geometry = CausalTimingBounds(0.0, 0.0)
    geometric_limit = TimingPolicySet(
        GeometricElectionPolicy(
            safety_factor=1.0,
            processing_margin=0.0,
            randomization_fraction=1.0,
            minimum_timeout=0.15,
            maximum_timeout=0.30,
        ),
        GeometricHeartbeatPolicy(
            safety_factor=0.0,
            processing_margin=0.0,
            minimum_interval=0.05,
            maximum_interval=0.10,
        ),
    )
    recovered_baseline = evaluate_timing(
        geometric_limit;
        bounds=zero_geometry,
        election_draw=0.25,
    )
    @test recovered_baseline.election_window.minimum == 0.15
    @test recovered_baseline.election_window.maximum == 0.30
    @test recovered_baseline.selected_election_timeout == 0.1875
    @test recovered_baseline.heartbeat.interval == 0.05

    geometric = GeometricElectionPolicy(
        safety_factor=1.2,
        processing_margin=0.02,
        randomization_fraction=0.25,
        minimum_timeout=0.1,
        maximum_timeout=2.0,
    )
    short = election_window(geometric, nothing, CausalTimingBounds(0.1, 0.2))
    long = election_window(geometric, nothing, CausalTimingBounds(0.2, 0.6))
    @test short.minimum ≈ 0.26
    @test long.minimum ≈ 0.74
    @test long.minimum > short.minimum
    @test long.maximum >= long.minimum

    unreachable = election_window(geometric, nothing, unreachable_causal_bounds())
    @test unreachable.status === :unbounded
    @test unreachable.minimum == Inf
    beyond_budget = election_window(geometric, nothing, CausalTimingBounds(1.0, 2.0))
    @test beyond_budget.status === :infeasible
    @test_throws DomainError select_election_timeout(beyond_budget, 0.5)

    geometric_heartbeat = GeometricHeartbeatPolicy(
        safety_factor=1.0,
        processing_margin=0.01,
        minimum_interval=0.05,
        maximum_interval=0.50,
    )
    @test heartbeat_decision(geometric_heartbeat, CausalTimingBounds(0.2, 0.4)).interval ≈ 0.21
    @test heartbeat_decision(geometric_heartbeat, unreachable_causal_bounds()).status === :unbounded
    @test heartbeat_decision(geometric_heartbeat, CausalTimingBounds(0.6, 1.2)).status === :infeasible
end

@testset "robust observation policy and hybrid prior" begin
    policy = RobustAdaptiveElectionPolicy(
        alpha=0.5,
        sigma_multiplier=1.0,
        robust_clip_sigma=4.0,
        processing_margin=0.01,
        randomization_fraction=0.2,
        warmup_samples=3,
        warmup_timeout=0.30,
        minimum_timeout=0.10,
        maximum_timeout=1.0,
    )
    state = AdaptiveTimingState()
    warmup = election_window(policy, state)
    @test warmup.source === :adaptive_warmup
    @test warmup.minimum == 0.30

    first = update_observation(policy, state, ArrivalObservation(10, 0.0))
    @test first.accepted
    @test first.sequence_gap == 0
    @test first.state.sample_count == 0
    state = first.state
    for (sequence, arrival) in ((11, 0.10), (12, 0.21), (13, 0.33))
        update = update_observation(policy, state, ArrivalObservation(sequence, arrival))
        @test update.accepted
        @test update.sequence_gap == 1
        state = update.state
    end
    @test state.sample_count == 3
    adapted = election_window(policy, state)
    @test adapted.source === :arrival_ewma
    @test 0.10 <= adapted.minimum <= 1.0

    stale = update_observation(policy, state, ArrivalObservation(12, 0.40))
    @test !stale.accepted
    @test stale.state.last_sequence == state.last_sequence
    @test stale.state.mean_interval == state.mean_interval
    @test stale.state.rejected_observations == state.rejected_observations + 1

    gap = update_observation(policy, state, ArrivalObservation(16, 0.63))
    @test gap.accepted
    @test gap.sequence_gap == 3
    @test gap.state.mean_interval < 0.3

    saturated_state = AdaptiveTimingState(
        policy.warmup_samples,
        policy.maximum_timeout,
        0.0,
        10.0,
        100,
        0,
    )
    saturated = election_window(policy, saturated_state)
    @test is_ready(saturated)
    @test saturated.minimum == policy.maximum_timeout
    @test saturated.maximum == policy.maximum_timeout

    geometry = GeometricElectionPolicy(
        safety_factor=1.0,
        processing_margin=0.05,
        randomization_fraction=0.1,
        minimum_timeout=0.1,
        maximum_timeout=2.0,
    )
    hybrid = HybridElectionPolicy(geometry, policy; prior_strength=2.0)
    bounds = CausalTimingBounds(0.1, 0.4)
    hybrid_warmup = election_window(hybrid, AdaptiveTimingState(), bounds)
    geometric_only = election_window(geometry, nothing, bounds)
    @test hybrid_warmup.minimum >= geometric_only.minimum
    @test election_window(hybrid, state, bounds).minimum >= geometric_only.minimum
    @test election_window(hybrid, state, unreachable_causal_bounds()).status === :unbounded
end

@testset "fingerprints and sensitivity grids" begin
    left = Dict{Symbol,Any}(:alpha => 0.2, :warmup => 4, :levels => [:i0, :i2])
    right = Dict{Symbol,Any}(:levels => [:i0, :i2], :warmup => 4, :alpha => 0.2)
    @test config_fingerprint(left) == config_fingerprint(right)
    changed = copy(right)
    changed[:alpha] = 0.3
    @test config_fingerprint(left) != config_fingerprint(changed)

    axes = (
        ParameterAxis(:timeout, [0.2, 0.4]),
        ParameterAxis(:copies, [1, 2, 3]),
    )
    grid = parameter_grid(axes...)
    @test length(grid) == 6
    @test grid[1] == (timeout=0.2, copies=1)
    @test grid[end] == (timeout=0.4, copies=3)
    fingerprinted = fingerprinted_grid(axes...)
    @test length(unique(row.fingerprint for row in fingerprinted)) == 6
    @test parameter_grid() == [NamedTuple()]
    @test_throws ArgumentError ParameterAxis(:duplicate, [1, 1])
end
