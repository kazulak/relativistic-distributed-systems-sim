using Test
using Random
using StaticArrays
using RelativisticDistributedSystemsSim

@testset "Physics" begin
    include("spacetime_worldlines.jl")
    include("light_cone.jl")
    include("light_cone_regressions.jl")
    include("lorentz.jl")
    include("numerical_regressions.jl")
    include("quadrature_regressions.jl")
    include("worldline_kinks.jl")
    include("compatibility.jl")
end
