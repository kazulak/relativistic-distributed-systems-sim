using Test

include(joinpath(@__DIR__, "../../src/Adaptations/Adaptations.jl"))
using .RelativisticAdaptations

@testset "Relativistic adaptation policies" begin
    include("timing.jl")
    include("redundancy.jl")
    include("placement.jl")
    include("cost_quality.jl")
    include("runner_interface.jl")
end

