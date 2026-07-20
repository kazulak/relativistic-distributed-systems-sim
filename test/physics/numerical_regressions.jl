@testset "Extreme-scale spacetime primitives" begin
    huge_spacetime = MinkowskiSpacetime(1.0)
    huge_origin = SpacetimeEvent(0.0, SA[0.0, 0.0, 0.0])
    huge_null = SpacetimeEvent(1.0e200, SA[1.0e200, 0.0, 0.0])
    huge_timelike = SpacetimeEvent(1.0e200, SA[0.0, 0.0, 0.0])
    @test scaled_interval_residual(huge_spacetime, huge_origin, huge_null) == 0.0
    @test causal_relation(huge_spacetime, huge_origin, huge_null) === :future_null
    @test causal_relation(huge_spacetime, huge_origin, huge_timelike) === :future_timelike
    @test_throws NumericalConditioningError interval_squared(
        huge_spacetime,
        huge_origin,
        huge_timelike,
    )

    tiny_spacetime = MinkowskiSpacetime(1.0f0)
    tiny_origin = SpacetimeEvent(0.0f0, SA[0.0f0, 0.0f0, 0.0f0])
    tiny_null = SpacetimeEvent(1.0f-30, SA[1.0f-30, 0.0f0, 0.0f0])
    distinct_same_time = SpacetimeEvent(0.0f0, SA[nextfloat(0.0f0), 0.0f0, 0.0f0])
    @test scaled_interval_residual(tiny_spacetime, tiny_origin, tiny_null) == 0.0f0
    @test causal_relation(tiny_spacetime, tiny_origin, tiny_null) === :future_null
    @test causal_relation(tiny_spacetime, tiny_origin, distinct_same_time) === :spacelike
    @test_throws NumericalConditioningError interval_squared(
        tiny_spacetime,
        tiny_origin,
        distinct_same_time,
    )

    for T in (Float32, Float64)
        large_c = T === Float32 ? T(1.0e30) : T(1.0e300)
        spacetime = MinkowskiSpacetime(large_c)
        oblique_velocity = SVector{3,T}(T(0.5) * large_c, T(0.4) * large_c, T(0.3) * large_c)
        @test is_timelike_velocity(spacetime, oblique_velocity)
        factors = relativistic_factors(spacetime, oblique_velocity)
        @test factors.beta ≈ sqrt(T(0.5)) rtol = T(16) * eps(T)
        @test factors.gamma ≈ inv(sqrt(T(0.5))) rtol = T(32) * eps(T)
    end
end

@testset "Cross-precision light-time validation" begin
    for T in (Float32, Float64)
        spacetime = MinkowskiSpacetime(T(3))
        range = T === Float32 ? T(1.0e-20) : T(1.0e150)
        emission = SpacetimeEvent{T}(zero(T), SVector{3,T}(zero(T), zero(T), zero(T)))
        receiver = InertialWorldline(
            spacetime,
            SpacetimeEvent{T}(zero(T), SVector{3,T}(range, zero(T), zero(T))),
            SVector{3,T}(T(0.4), T(0.3), zero(T)),
        )
        result = light_cone_intersection(spacetime, emission, receiver)
        @test result.reception.t > emission.t
        @test result.equation_residual <= T(1024) * eps(T)
        @test result.scaled_residual <= T(4096) * eps(T)
    end

    setprecision(BigFloat, 256) do
        spacetime = MinkowskiSpacetime(big"1.0")
        emission = SpacetimeEvent(big"0.0", SVector{3,BigFloat}(0, 0, 0))
        velocity = SVector{3,BigFloat}(big"0.3", big"-0.4", big"0.2")
        receiver = InertialWorldline(
            spacetime,
            SpacetimeEvent(big"0.0", SVector{3,BigFloat}(big"2.5", big"-1.25", big"0.75")),
            velocity,
        )
        result = light_cone_intersection(spacetime, emission, receiver)
        range_vector = position_at(receiver, emission.t) - emission.x
        a = spacetime.c^2 - sum(abs2, velocity)
        b = sum(range_vector .* velocity)
        oracle_delay = (b + sqrt(b^2 + a * sum(abs2, range_vector))) / a
        @test result.reception.t ≈ oracle_delay rtol = big"1e-65"
        @test result.equation_residual <= big"1e-70"
    end
end

@testset "Epoch, near-null, and search failure contracts" begin
    spacetime = MinkowskiSpacetime(1.0)
    epoch = 1.0e16
    emission = SpacetimeEvent(epoch, SA[0.0, 0.0, 0.0])
    unrepresentable_receiver = InertialWorldline(
        spacetime,
        SpacetimeEvent(epoch, SA[1.0, 0.0, 0.0]),
        SA[0.0, 0.0, 0.0],
    )
    @test_throws NumericalConditioningError light_cone_intersection(
        spacetime,
        emission,
        unrepresentable_receiver,
    )

    representable_receiver = InertialWorldline(
        spacetime,
        SpacetimeEvent(epoch, SA[4.0, 0.0, 0.0]),
        SA[0.0, 0.0, 0.0],
    )
    representable = light_cone_intersection(spacetime, emission, representable_receiver)
    @test representable.reception.t == epoch + 4.0
    @test representable.equation_residual == 0.0

    near_null = InertialWorldline(
        spacetime,
        SA[1.0, 0.0, 0.0],
        SA[prevfloat(1.0), 0.0, 0.0],
    )
    @test_throws NumericalConditioningError light_cone_intersection(
        spacetime,
        SpacetimeEvent(0.0, SA[0.0, 0.0, 0.0]),
        near_null,
    )

    controlled_recession = InertialWorldline(
        spacetime,
        SA[1.0, 0.0, 0.0],
        SA[1.0 - 1.0e-6, 0.0, 0.0],
    )
    controlled = light_cone_intersection(
        spacetime,
        SpacetimeEvent(0.0, SA[0.0, 0.0, 0.0]),
        controlled_recession,
    )
    @test controlled.reception.t ≈ 1.0e6 rtol = 5.0e-11
    @test controlled.equation_residual <= 1.0e-12

    asymptotic_unbounded = ParametricWorldline(
        spacetime,
        time -> SA[time + exp(-time), 0.0, 0.0],
        time -> SA[1.0 - exp(-time), 0.0, 0.0];
        consistency=:assumed,
        tmin=0.0,
    )
    @test_throws LightConeSearchExhausted light_cone_intersection(
        spacetime,
        SpacetimeEvent(0.0, SA[0.0, 0.0, 0.0]),
        asymptotic_unbounded;
        max_expansions=1,
    )
    asymptotic_finite = ParametricWorldline(
        spacetime,
        time -> SA[time + exp(-time), 0.0, 0.0],
        time -> SA[1.0 - exp(-time), 0.0, 0.0];
        consistency=:assumed,
        tmin=0.0,
        tmax=2.0,
    )
    @test_throws NoFutureLightConeIntersection light_cone_intersection(
        spacetime,
        SpacetimeEvent(0.0, SA[0.0, 0.0, 0.0]),
        asymptotic_finite,
    )
end

@testset "Lorentz conditioning and extreme covariance" begin
    spacetime = MinkowskiSpacetime(1.0)
    tiny_boost = LorentzBoost(spacetime, SA[1.0e-8, 0.0, 0.0])
    @test tiny_boost.gamma_minus_one > 0.0
    @test tiny_boost.gamma_minus_one ≈ 0.5e-16 rtol = 1.0e-14
    @test_throws NumericalConditioningError LorentzBoost(
        spacetime,
        SA[prevfloat(1.0), 0.0, 0.0],
    )

    boost = LorentzBoost(spacetime, SA[0.6, 0.2, -0.1])
    first = SpacetimeEvent(1.0e150, SA[-2.0e150, 0.5e150, 0.25e150])
    second = SpacetimeEvent(1.0e150 + 1.0e140, SA[-2.0e150 + 0.2e140, 0.5e150, 0.25e150])
    transformed_displacement = lorentz_transform_displacement(boost, first, second)
    relative_origin = SpacetimeEvent(0.0, SA[0.0, 0.0, 0.0])
    original_relative = SpacetimeEvent(second.t - first.t, second.x - first.x)
    transformed_relative =
        SpacetimeEvent(transformed_displacement.dt, transformed_displacement.dx)
    @test causal_relation(spacetime, relative_origin, original_relative) ===
          causal_relation(spacetime, relative_origin, transformed_relative)
    @test_throws NumericalConditioningError lorentz_transform_pair(boost, first, second)
end
