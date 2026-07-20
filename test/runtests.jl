using Test
using RelativisticDistributedSystemsSim

const TEST_GROUP = lowercase(get(ENV, "RDS_TEST_GROUP", "all"))
TEST_GROUP in ("all", "physics", "raft") ||
    error("RDS_TEST_GROUP must be one of: all, physics, raft")

@testset "RelativisticDistributedSystemsSim" begin
    include("package_api.jl")
    TEST_GROUP in ("all", "physics") && include("physics/runtests.jl")

    raft_tests = joinpath(@__DIR__, "raft", "runtests.jl")
    TEST_GROUP in ("all", "raft") && include(raft_tests)
end
