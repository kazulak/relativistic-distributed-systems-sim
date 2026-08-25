@testset "installed package component namespaces" begin
    @test SimulationCore === RelativisticDistributedSystemsSim.SimulationCore
    @test Raft === RelativisticDistributedSystemsSim.Raft
    @test Adaptations === RelativisticDistributedSystemsSim.Adaptations
    @test Research === RelativisticDistributedSystemsSim.Research
    @test parentmodule(SimulationCore) === RelativisticDistributedSystemsSim
    @test parentmodule(Raft) === RelativisticDistributedSystemsSim
    @test parentmodule(Adaptations) === RelativisticDistributedSystemsSim
    @test parentmodule(Research) === RelativisticDistributedSystemsSim
    @test isdefined(SimulationCore, :Scheduler)
    @test isdefined(SimulationCore, :EventTrace)
    @test isdefined(Raft, :RaftNode)
    @test isdefined(Raft, :transition!)
    @test isdefined(Adaptations, :TimingPolicySet)
    @test isdefined(Research, :run_scenario)
end
