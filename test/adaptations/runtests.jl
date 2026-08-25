using Test
using RelativisticDistributedSystemsSim
using RelativisticDistributedSystemsSim.Adaptations

@testset "Relativistic adaptation policies" begin
    include("timing.jl")
    include("redundancy.jl")
    include("placement.jl")
    include("cost_quality.jl")
    include("runner_interface.jl")
end

