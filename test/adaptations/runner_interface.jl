function _static_timing()
    return TimingPolicySet(
        StaticElectionPolicy(0.15, 0.30),
        StaticHeartbeatPolicy(0.05),
    )
end

@testset "adaptation variant construction and fingerprints" begin
    timing = _static_timing()
    redundancy = FixedCopiesPolicy(2, 0.1)

    variant = AdaptationVariant("i1-sequence", timing, redundancy)
    @test variant.variant_id == "i1-sequence"
    @test variant.placement_method === :exhaustive
    @test variant.objective == ParetoObjective()

    @test variant_fingerprint(variant) == variant_fingerprint(variant)
    renamed = AdaptationVariant("i2-timestamp", timing, redundancy)
    @test variant_fingerprint(renamed) != variant_fingerprint(variant)
    retimed = AdaptationVariant(
        "i1-sequence",
        TimingPolicySet(
            StaticElectionPolicy(0.20, 0.40),
            StaticHeartbeatPolicy(0.05),
        ),
        redundancy,
    )
    @test variant_fingerprint(retimed) != variant_fingerprint(variant)

    greedy = AdaptationVariant("greedy", timing, redundancy; placement_method=:greedy)
    @test greedy.placement_method === :greedy
    @test_throws ArgumentError AdaptationVariant("", timing, redundancy)
    @test_throws ArgumentError AdaptationVariant(
        "bad-method",
        timing,
        redundancy;
        placement_method=:random,
    )
end

@testset "runner timing delegation" begin
    geometric = TimingPolicySet(
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
    variant = AdaptationVariant("geometric-i0", geometric, FixedCopiesPolicy(1))
    bounds = CausalTimingBounds(0.10, 0.20)

    decision = runner_timing_decision(variant; bounds=bounds, election_draw=0.25)
    direct = evaluate_timing(geometric; bounds=bounds, election_draw=0.25)
    @test decision.selected_election_timeout == direct.selected_election_timeout

    recovered = runner_timing_decision(
        variant;
        bounds=CausalTimingBounds(0.0, 0.0),
        election_draw=0.25,
    )
    @test is_ready(recovered.election_window)
    @test recovered.election_window.minimum == 0.15
    @test recovered.selected_election_timeout == 0.1875
    @test recovered.heartbeat.interval == 0.05

    unbounded = runner_timing_decision(
        variant;
        bounds=unreachable_causal_bounds(),
        election_draw=0.5,
    )
    @test !is_ready(unbounded.election_window)
    @test unbounded.election_window.status === :unbounded
end

@testset "runner redundancy delegation" begin
    paths = [
        PathOption(1, 0.20, 0.80; overhead_bytes=10),
        PathOption(2, 0.30, 0.75; overhead_bytes=20),
        PathOption(3, 0.10, 0.50; overhead_bytes=5),
    ]
    request = RedundancyRequest(42, 100, 0.0, 1.0, paths)
    variant = AdaptationVariant("triple-copy", _static_timing(), FixedCopiesPolicy(3, 0.1))

    plan = runner_redundancy_plan(variant, request)
    @test is_ready(plan)
    @test length(plan.copies) == 3
    @test all(dedupe_key(copy) == UInt64(42) for copy in plan.copies)

    budget = ResourceBudget(
        maximum_messages=2,
        maximum_bytes=1_000,
        maximum_energy_proxy=100.0,
        maximum_link_occupancy=100.0,
    )
    limited = runner_redundancy_plan(variant, request, budget)
    @test !is_ready(limited)
    @test limited.status === :budget_limited
    @test within_budget(limited.cost, budget)
end

@testset "runner placement delegation" begin
    matrix = CausalDelayMatrix(
        [1, 2, 3],
        [
            0.0 1.0 1.0
            1.0 0.0 1.0
            1.0 1.0 0.0
        ],
    )
    exhaustive_variant = AdaptationVariant("place-exhaustive", _static_timing(), FixedCopiesPolicy(1))
    greedy_variant = AdaptationVariant(
        "place-greedy",
        _static_timing(),
        FixedCopiesPolicy(1);
        placement_method=:greedy,
    )

    result = runner_placement(exhaustive_variant, matrix)
    @test is_ready(result)
    @test result.chosen.leader == 1
    @test result.chosen.quorum == (1, 2)
    @test result.chosen.quorum_delay == 1.0
    @test result.chosen == select_placement(matrix).chosen

    greedy_result = runner_placement(greedy_variant, matrix)
    @test is_ready(greedy_result)
    @test greedy_result.chosen == select_placement(matrix; method=:greedy).chosen

    cost_matrix = CausalDelayMatrix(
        [1, 2, 3],
        [
            0.0 2.0 1.0
            2.0 0.0 2.0
            1.0 2.0 0.0
        ],
    )
    weights = PlacementWeights(quorum_delay=1.0, placement_cost=1.0)
    costs = Dict(1 => 10.0, 2 => 0.0, 3 => 5.0)
    weighted = runner_placement(
        exhaustive_variant,
        cost_matrix;
        weights=weights,
        placement_costs=costs,
    )
    @test weighted.chosen ==
          select_placement(cost_matrix; weights=weights, placement_costs=costs).chosen

    constrained = runner_placement(
        exhaustive_variant,
        matrix;
        constraints=PlacementConstraints(3; maximum_quorum_delay=0.5),
    )
    @test !is_ready(constrained)
    @test constrained.status === :infeasible
end

@testset "runner outcome selection" begin
    quality(availability, suspicion, detection, latency, churn, censoring) = QualityMetrics(
        deadline_availability=availability,
        false_suspicion_rate=suspicion,
        detection_delay=detection,
        commit_latency=latency,
        leader_churn=churn,
        censoring_rate=censoring,
    )
    cost(messages, bytes, energy, placement) = CostMetrics(
        message_rate=messages,
        byte_rate=bytes,
        redundancy_rate=0.0,
        energy_proxy=energy,
        placement_cost=placement,
        link_occupancy=bytes / 10,
        estimator_cpu=1.0,
        estimator_state_bytes=16.0,
    )
    balanced = PolicyOutcome("a-balanced", quality(0.99, 0.01, 2.0, 5.0, 1.0, 0.01), cost(10.0, 100.0, 1.0, 0.0))
    dominated = PolicyOutcome("b-dominated", quality(0.98, 0.02, 3.0, 6.0, 2.0, 0.02), cost(12.0, 120.0, 2.0, 1.0))

    variant = AdaptationVariant("pareto-default", _static_timing(), FixedCopiesPolicy(1))
    selected = runner_select_outcomes(variant, [dominated, balanced])
    @test getfield.(selected, :policy_id) == ["a-balanced"]

    constraints = OutcomeConstraints(
        minimum_deadline_availability=0.99,
        maximum_false_suspicion_rate=0.05,
        maximum_censoring_rate=0.05,
        maximum_message_rate=10.0,
    )
    cheap = PolicyOutcome(
        "c-cheap-high-availability",
        quality(0.995, 0.03, 4.0, 10.0, 2.0, 0.02),
        cost(5.0, 50.0, 0.5, 2.0),
    )
    equal_tradeoff = PolicyOutcome("d-equal-tradeoff", cheap.quality, cheap.cost)
    constrained_variant = AdaptationVariant(
        "pareto-constrained",
        _static_timing(),
        FixedCopiesPolicy(1);
        objective=ParetoObjective(constraints),
    )
    chosen = runner_select_outcomes(
        constrained_variant,
        [balanced, dominated, cheap, equal_tradeoff],
    )
    @test getfield.(chosen, :policy_id) == [
        "a-balanced",
        "c-cheap-high-availability",
        "d-equal-tradeoff",
    ]
end
