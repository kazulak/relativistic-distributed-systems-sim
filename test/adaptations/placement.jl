@testset "deterministic exhaustive and greedy placement" begin
    matrix = CausalDelayMatrix(
        [1, 2, 3, 4, 5],
        [
            0.0 1.0 1.0 4.0 4.0
            1.0 0.0 2.0 4.0 4.0
            1.0 2.0 0.0 4.0 4.0
            4.0 4.0 4.0 0.0 1.0
            4.0 4.0 4.0 1.0 0.0
        ],
    )
    constraints = PlacementConstraints(3)
    exhaustive = exhaustive_placement(matrix, constraints)
    greedy = greedy_placement(matrix, constraints)
    @test is_ready(exhaustive)
    @test exhaustive.chosen.leader == 1
    @test exhaustive.chosen.quorum == (1, 2, 3)
    @test exhaustive.chosen.quorum_delay == 1.0
    @test greedy.chosen.leader == 1
    @test greedy.chosen.quorum == (1, 2, 3)
    @test select_placement(matrix).chosen == exhaustive.chosen
    @test select_placement(matrix; method=:greedy).chosen == greedy.chosen

    required = PlacementConstraints(3; required_members=[5])
    required_result = exhaustive_placement(matrix, required)
    @test is_ready(required_result)
    @test 5 in required_result.chosen.quorum

    cost_sensitive = exhaustive_placement(
        matrix,
        constraints;
        weights=PlacementWeights(quorum_delay=1.0, placement_cost=1.0),
        placement_costs=Dict(1 => 10.0, 2 => 0.0, 3 => 5.0, 4 => 5.0, 5 => 5.0),
    )
    @test cost_sensitive.chosen.leader == 2
    @test cost_sensitive.chosen.quorum_delay == 2.0

    constrained = exhaustive_placement(
        matrix,
        PlacementConstraints(3; maximum_quorum_delay=0.5),
    )
    @test constrained.status === :infeasible
    @test isnothing(constrained.chosen)
end

@testset "placement ties, reachability, and validation" begin
    tied_matrix = CausalDelayMatrix(
        [1, 2, 3],
        [
            0.0 1.0 1.0
            1.0 0.0 1.0
            1.0 1.0 0.0
        ],
    )
    exhaustive = select_placement(tied_matrix; method=:exhaustive)
    greedy = select_placement(tied_matrix; method=:greedy)
    @test exhaustive.chosen.leader == 1
    @test exhaustive.chosen.quorum == (1, 2)
    @test length(exhaustive.tied_best) == 6
    @test greedy.chosen.leader == 1
    @test greedy.chosen.quorum == (1, 2)
    @test length(greedy.tied_best) == 3
    @test select_placement(tied_matrix; method=:exhaustive).chosen == exhaustive.chosen

    unreachable = CausalDelayMatrix(
        [1, 2, 3],
        [
            0.0 Inf Inf
            Inf 0.0 Inf
            Inf Inf 0.0
        ],
    )
    unreachable_result = select_placement(unreachable)
    @test unreachable_result.status === :infeasible
    @test isempty(unreachable_result.tied_best)

    @test causal_delay(tied_matrix, 1, 2) == 1.0
    @test_throws ArgumentError causal_delay(tied_matrix, 1, 99)
    @test_throws ArgumentError CausalDelayMatrix([1, 1], zeros(2, 2))
    @test_throws ArgumentError CausalDelayMatrix([1, 2], [1.0 1.0; 1.0 0.0])
    @test_throws ArgumentError select_placement(tied_matrix; method=:unknown)
end
