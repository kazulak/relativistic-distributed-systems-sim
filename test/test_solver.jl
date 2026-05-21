using Test
using StaticArrays
using StableRNGs
using Random

include("../src/light_time.jl")

const C_SIM = 100.0

struct ConstantPosition
    x0::SVector{3,Float64}
    v::SVector{3,Float64}
end

struct ConstantVelocity
    v::SVector{3,Float64}
end

@inline (x::ConstantPosition)(t::Float64)::SVector{3,Float64} = x.x0 + x.v * t
@inline (v::ConstantVelocity)(t::Float64)::SVector{3,Float64} = v.v

@inline function constant_worldline(x0::SVector{3,Float64}, v::SVector{3,Float64})
    return ConstantPosition(x0, v), ConstantVelocity(v)
end

struct TransversePosition
    r0::Float64
    v::Float64
    t_emit::Float64
end

struct TransverseVelocity
    v::Float64
end

@inline function (x::TransversePosition)(t::Float64)::SVector{3,Float64}
    return @SVector [x.r0, x.v * (t - x.t_emit), 0.0]
end

@inline function (v::TransverseVelocity)(t::Float64)::SVector{3,Float64}
    return @SVector [0.0, v.v, 0.0]
end

@testset "Phase 0 Part A light-time solver" begin
    rng = StableRNG(1234)

    @testset "radial beta 0.9" begin
        tA = 2.0
        r0 = 10.0
        beta = 0.9
        v = beta * C_SIM
        xA = @SVector [0.0, 0.0, 0.0]
        xB0 = @SVector [r0 - v * tA, 0.0, 0.0]
        vB = @SVector [v, 0.0, 0.0]
        xB_func, vB_func = constant_worldline(xB0, vB)

        result = solve_light_time_result(tA, xA, xB_func, vB_func, C_SIM)
        analytic = tA + r0 / (C_SIM - v)

        @test isapprox(result.tB, analytic; atol=1.0e-12, rtol=0.0)
        @test result.converged_newton
        @test result.iterations <= 6

        solve_light_time(tA, xA, xB_func, vB_func, C_SIM)
        @test @allocations(solve_light_time(tA, xA, xB_func, vB_func, C_SIM)) == 0
    end

    @testset "transverse doppler" begin
        beta = 0.8
        gamma = inv(sqrt(1.0 - beta * beta))
        v = beta * C_SIM
        delta_tau = 0.05
        r0 = 40.0
        xA = @SVector [0.0, 0.0, 0.0]

        t_emit_1 = 0.0
        xB1 = TransversePosition(r0, v, t_emit_1)
        vB1 = TransverseVelocity(v)
        t_recv_1 = solve_light_time(t_emit_1, xA, xB1, vB1, C_SIM)

        t_emit_2 = gamma * delta_tau
        xB2 = TransversePosition(r0, v, t_emit_2)
        vB2 = TransverseVelocity(v)
        t_recv_2 = solve_light_time(t_emit_2, xA, xB2, vB2, C_SIM)

        delta_t_obs = t_recv_2 - t_recv_1
        @test isapprox(delta_t_obs, gamma * delta_tau; atol=1.0e-12, rtol=0.0)
    end

    @testset "causal ordering by invariant interval" begin
        t_emit_1 = 1.0
        t_emit_2 = 1.125
        x_emit = @SVector [0.0, 0.0, 0.0]
        receiver_x = 25.0

        for beta in (0.2, 0.75)
            v = beta * C_SIM
            xB0 = @SVector [receiver_x - v * t_emit_1, 0.0, 0.0]
            vB = @SVector [v, 0.0, 0.0]
            xB_func, vB_func = constant_worldline(xB0, vB)

            t_recv_1 = solve_light_time(t_emit_1, x_emit, xB_func, vB_func, C_SIM)
            t_recv_2 = solve_light_time(t_emit_2, x_emit, xB_func, vB_func, C_SIM)
            x_recv_1 = xB_func(t_recv_1)
            x_recv_2 = xB_func(t_recv_2)
            s_emit = minkowski_interval2(t_emit_1, x_emit, t_emit_2, x_emit, C_SIM)
            s_recv = minkowski_interval2(t_recv_1, x_recv_1, t_recv_2, x_recv_2, C_SIM)

            @test abs(minkowski_interval2(t_emit_1, x_emit, t_recv_1, x_recv_1, C_SIM)) <= 1.0e-9
            @test abs(minkowski_interval2(t_emit_2, x_emit, t_recv_2, x_recv_2, C_SIM)) <= 1.0e-9
            @test s_emit > 0.0
            @test s_recv > 0.0
            @test t_recv_1 < t_recv_2
        end
    end

    @testset "random geometries converge within six newton iterations" begin
        for _ in 1:10_000
            tA = 10.0 * rand(rng)
            beta = 0.95 * rand(rng)
            theta = 2.0 * pi * rand(rng)
            phi = acos(2.0 * rand(rng) - 1.0)
            speed = beta * C_SIM
            vB = speed * @SVector [sin(phi) * cos(theta), sin(phi) * sin(theta), cos(phi)]
            xA = @SVector [0.0, 0.0, 0.0]
            x_at_emit = @SVector [
                1.0 + 100.0 * rand(rng),
                -50.0 + 100.0 * rand(rng),
                -50.0 + 100.0 * rand(rng),
            ]
            xB0 = x_at_emit - vB * tA
            xB_func, vB_func = constant_worldline(xB0, vB)

            result = solve_light_time_result(tA, xA, xB_func, vB_func, C_SIM)
            @test abs(_lt_f(result.tB, tA, xA, xB_func, C_SIM)) <= 1.0e-12
            @test result.converged_newton
            @test result.iterations <= 6
        end
    end
end
