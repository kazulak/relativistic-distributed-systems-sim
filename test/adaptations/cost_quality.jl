function _quality(availability, false_suspicion, detection, latency, churn, censoring)
    return QualityMetrics(
        deadline_availability=availability,
        false_suspicion_rate=false_suspicion,
        detection_delay=detection,
        commit_latency=latency,
        leader_churn=churn,
        censoring_rate=censoring,
    )
end

function _cost(messages, bytes, redundancy, energy, placement)
    return CostMetrics(
        message_rate=messages,
        byte_rate=bytes,
        redundancy_rate=redundancy,
        energy_proxy=energy,
        placement_cost=placement,
        link_occupancy=bytes / 10,
        estimator_cpu=1.0,
        estimator_state_bytes=16.0,
    )
end

@testset "cost-quality dominance and Pareto preservation" begin
    a = PolicyOutcome(
        "a-balanced",
        _quality(0.99, 0.01, 2.0, 5.0, 1.0, 0.01),
        _cost(10.0, 100.0, 0.0, 1.0, 0.0),
    )
    b = PolicyOutcome(
        "b-dominated",
        _quality(0.98, 0.02, 3.0, 6.0, 2.0, 0.02),
        _cost(12.0, 120.0, 1.0, 2.0, 1.0),
    )
    c = PolicyOutcome(
        "c-cheap-high-availability",
        _quality(0.995, 0.03, 4.0, 10.0, 2.0, 0.02),
        _cost(5.0, 50.0, 1.0, 0.5, 2.0),
    )
    d = PolicyOutcome(
        "d-equal-tradeoff",
        c.quality,
        c.cost,
    )

    @test dominates(a, b)
    @test !dominates(b, a)
    @test !dominates(a, c)
    @test !dominates(c, a)
    @test !dominates(c, d)
    @test !dominates(d, c)

    frontier = pareto_frontier([d, b, c, a])
    @test getfield.(frontier, :policy_id) == [
        "a-balanced",
        "c-cheap-high-availability",
        "d-equal-tradeoff",
    ]
    @test length(pareto_frontier([c, d])) == 2

    constraints = OutcomeConstraints(
        minimum_deadline_availability=0.99,
        maximum_false_suspicion_rate=0.05,
        maximum_censoring_rate=0.05,
        maximum_message_rate=10.0,
    )
    feasible = feasible_outcomes([a, b, c, d], constraints)
    @test getfield.(feasible, :policy_id) == [
        "a-balanced",
        "c-cheap-high-availability",
        "d-equal-tradeoff",
    ]
    pareto_selected = select_outcomes([a, b, c, d], ParetoObjective(constraints))
    @test getfield.(pareto_selected, :policy_id) == getfield.(frontier, :policy_id)

    minimum_messages = select_outcomes(
        [a, b, c, d],
        MinimumMetricObjective(:message_rate, constraints),
    )
    @test getfield.(minimum_messages, :policy_id) == [
        "c-cheap-high-availability",
        "d-equal-tradeoff",
    ]
    @test_throws ArgumentError MinimumMetricObjective(:deadline_availability)
    @test_throws ArgumentError pareto_frontier([a, a])
end

@testset "resource aggregation and explicit censoring" begin
    resource = ResourceCost(3, 600, 12.0, 4.0)
    metrics = CostMetrics(resource; duration=2.0, placement_cost=5.0)
    @test metrics.message_rate == 1.5
    @test metrics.byte_rate == 300.0
    @test metrics.redundancy_rate == 1.0
    @test metrics.energy_proxy == 12.0
    @test metrics.placement_cost == 5.0
    @test metrics.link_occupancy == 4.0

    censored = _quality(0.0, 0.0, Inf, Inf, 0.0, 1.0)
    @test censored.detection_delay == Inf
    @test censored.commit_latency == Inf
    @test censored.censoring_rate == 1.0
    @test_throws ArgumentError _quality(1.1, 0.0, 1.0, 1.0, 0.0, 0.0)
    @test_throws ArgumentError CostMetrics(message_rate=-1.0)
end
