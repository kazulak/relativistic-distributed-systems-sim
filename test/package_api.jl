@testset "installed package component namespaces" begin
    @test SimulationCore === RelativisticDistributedSystemsSim.SimulationCore
    @test Raft === RelativisticDistributedSystemsSim.Raft
    @test parentmodule(SimulationCore) === RelativisticDistributedSystemsSim
    @test parentmodule(Raft) === RelativisticDistributedSystemsSim
    @test isdefined(SimulationCore, :Scheduler)
    @test isdefined(SimulationCore, :EventTrace)
    @test isdefined(Raft, :RaftNode)
    @test isdefined(Raft, :transition!)
end
