using Test
using RelativisticDistributedSystemsSim

const TEST_GROUP = lowercase(get(ENV, "RDS_TEST_GROUP", "all"))
TEST_GROUP in ("all", "physics", "raft", "research", "adaptations", "differential", "experiments") ||
    error("RDS_TEST_GROUP must be one of: all, physics, raft, research, adaptations, differential, experiments")

@testset "RelativisticDistributedSystemsSim" begin
    include("package_api.jl")
    TEST_GROUP in ("all", "physics") && include("physics/runtests.jl")

    raft_tests = joinpath(@__DIR__, "raft", "runtests.jl")
    TEST_GROUP in ("all", "raft") && include(raft_tests)

    research_tests = joinpath(@__DIR__, "research", "runtests.jl")
    TEST_GROUP in ("all", "research") && include(research_tests)

    adaptation_tests = joinpath(@__DIR__, "adaptations", "runtests.jl")
    TEST_GROUP in ("all", "adaptations") && include(adaptation_tests)

    differential_tests = joinpath(@__DIR__, "differential", "runtests.jl")
    TEST_GROUP in ("all", "differential") && include(differential_tests)

    # Experiment tooling: runners, manifests, and analysis statistics.
    experiment_tests = joinpath(@__DIR__, "experiments", "runtests.jl")
    TEST_GROUP in ("all", "experiments") && isfile(experiment_tests) && include(experiment_tests)
    TEST_GROUP in ("all", "experiments") && include(joinpath(@__DIR__, "experiments", "rq1_tooling.jl"))
end
