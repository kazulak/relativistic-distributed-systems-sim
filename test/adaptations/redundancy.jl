@testset "fixed redundancy, dedupe identities, and costs" begin
    paths = [
        PathOption(
            1,
            0.20,
            0.80;
            overhead_bytes=10,
            fixed_energy=1.0,
            energy_per_byte=0.01,
            occupancy_per_byte=0.001,
        ),
        PathOption(
            2,
            0.30,
            0.75;
            overhead_bytes=20,
            fixed_energy=0.5,
            energy_per_byte=0.02,
            occupancy_per_byte=0.002,
        ),
        PathOption(3, 0.10, 0.50; overhead_bytes=5),
    ]
    request = RedundancyRequest(42, 100, 0.0, 1.0, paths)

    baseline = plan_redundancy(FixedCopiesPolicy(1), request)
    @test is_ready(baseline)
    @test length(baseline.copies) == 1
    @test baseline.cost.messages == 1
    @test baseline.cost.bytes == 110
    @test baseline.cost.energy_proxy ≈ 2.1
    @test baseline.cost.link_occupancy ≈ 0.11
    @test redundant_copies(baseline.cost) == 0
    @test dedupe_key(only(baseline.copies)) == UInt64(42)

    independent = plan_redundancy(FixedCopiesPolicy(3, 0.1), request)
    @test getfield.(independent.copies, :path_id) == [1, 2, 3]
    @test getfield.(independent.copies, :send_offset) ≈ [0.0, 0.1, 0.2]
    @test length(unique(copy.id.copy_index for copy in independent.copies)) == 3
    @test all(dedupe_key(copy) == UInt64(42) for copy in independent.copies)
    @test independent.on_time_delivery_probability ≈ 0.975
    @test independent.probability_assumption === :independent_copies

    repeated_path_request = RedundancyRequest(43, 10, 0.0, 1.0, [paths[1]])
    correlated = plan_redundancy(
        FixedCopiesPolicy(3, 0.0; probability_assumption=:path_correlated),
        repeated_path_request,
    )
    independent_repeats = plan_redundancy(FixedCopiesPolicy(3), repeated_path_request)
    @test correlated.on_time_delivery_probability ≈ 0.8
    @test independent_repeats.on_time_delivery_probability ≈ 0.992

    budget = ResourceBudget(
        maximum_messages=2,
        maximum_bytes=1_000,
        maximum_energy_proxy=100.0,
        maximum_link_occupancy=100.0,
    )
    limited = plan_redundancy(FixedCopiesPolicy(3), request, budget)
    @test limited.status === :budget_limited
    @test length(limited.copies) == 2
    @test within_budget(limited.cost, budget)
    @test limited.cost.messages == 2

    zero_budget = ResourceBudget(
        maximum_messages=0,
        maximum_bytes=0,
        maximum_energy_proxy=0.0,
        maximum_link_occupancy=0.0,
    )
    no_copy = plan_redundancy(FixedCopiesPolicy(1), request, zero_budget)
    @test no_copy.status === :budget_limited
    @test isempty(no_copy.copies)
    @test no_copy.cost == ResourceCost()
end

@testset "deadline-risk adaptive copies" begin
    paths = [
        PathOption(1, 0.20, 0.80; overhead_bytes=10),
        PathOption(2, 0.30, 0.75; overhead_bytes=20),
        PathOption(3, 0.10, 0.50; overhead_bytes=5),
    ]
    request = RedundancyRequest(50, 100, 0.0, 1.0, paths)
    low_risk = plan_redundancy(DeadlineRiskCopiesPolicy(0.70; maximum_copies=3), request)
    high_risk = plan_redundancy(DeadlineRiskCopiesPolicy(0.95; maximum_copies=3), request)
    unreachable_risk = plan_redundancy(DeadlineRiskCopiesPolicy(0.99; maximum_copies=3), request)
    @test low_risk.status === :ready
    @test length(low_risk.copies) == 1
    @test high_risk.status === :ready
    @test length(high_risk.copies) == 2
    @test high_risk.on_time_delivery_probability ≈ 0.95
    @test length(unreachable_risk.copies) >= length(high_risk.copies)
    @test unreachable_risk.status === :risk_unmet
    @test unreachable_risk.on_time_delivery_probability ≈ 0.975

    one_copy_budget = ResourceBudget(maximum_messages=1, maximum_bytes=1_000)
    budget_limited = plan_redundancy(
        DeadlineRiskCopiesPolicy(0.95; maximum_copies=3),
        request,
        one_copy_budget,
    )
    @test budget_limited.status === :budget_limited
    @test length(budget_limited.copies) == 1
    @test within_budget(budget_limited.cost, one_copy_budget)

    impossible_deadline = RedundancyRequest(51, 100, 0.0, 0.05, paths)
    impossible = plan_redundancy(
        DeadlineRiskCopiesPolicy(0.50; maximum_copies=3),
        impossible_deadline,
    )
    @test impossible.status === :deadline_infeasible
    @test isempty(impossible.copies)

    unbounded_request = RedundancyRequest(
        52,
        100,
        0.0,
        1.0,
        [PathOption(1, Inf, 0.9)],
    )
    @test plan_redundancy(FixedCopiesPolicy(1), unbounded_request).status === :unbounded
    @test plan_redundancy(
        DeadlineRiskCopiesPolicy(0.5),
        unbounded_request,
    ).status === :unbounded
end
