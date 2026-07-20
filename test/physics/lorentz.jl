@testset "Lorentz interval and inverse metamorphisms" begin
    rng = MersenneTwister(0x10ae17)
    spacetime = MinkowskiSpacetime(11.0)
    for _ in 1:256
        boost_direction = SVector{3,Float64}(randn(rng, 3))
        boost_direction /= sqrt(sum(abs2, boost_direction))
        frame_velocity = boost_direction * (0.9 * spacetime.c * rand(rng))
        boost = LorentzBoost(spacetime, frame_velocity)
        first = SpacetimeEvent(10.0 * randn(rng), SVector{3,Float64}(randn(rng, 3)) * 20.0)
        second = SpacetimeEvent(10.0 * randn(rng), SVector{3,Float64}(randn(rng, 3)) * 20.0)
        first_transformed, second_transformed =
            lorentz_transform_pair(boost, first, second)

        original_interval = interval_squared(spacetime, first, second)
        transformed_interval = interval_squared(spacetime, first_transformed, second_transformed)
        scale = max(abs(original_interval), spacetime.c^2 * (second.t - first.t)^2, sum(abs2, second.x - first.x), 1.0)
        @test abs(original_interval - transformed_interval) / scale <= 2.0e-13

        recovered = lorentz_transform(inverse_boost(boost), first_transformed)
        @test recovered.t ≈ first.t rtol = 2.0e-13 atol = 2.0e-13
        @test recovered.x ≈ first.x rtol = 2.0e-13 atol = 2.0e-13
    end
end

@testset "Lorentz separation-aware large-epoch contract" begin
    spacetime = MinkowskiSpacetime(1.0)
    axial = LorentzBoost(spacetime, SA[0.3, 0.0, 0.0])
    first = SpacetimeEvent(1.0e16, SA[0.0, 0.0, 0.0])
    second = SpacetimeEvent(1.0e16 + 4.0, SA[4.0, 0.0, 0.0])
    @test causal_relation(spacetime, first, second) === :future_null

    # Independently rounded absolute transforms cannot carry this separation.
    @test_throws NumericalConditioningError lorentz_transform(axial, first)
    @test_throws NumericalConditioningError lorentz_transform(axial, second)
    @test_throws NumericalConditioningError lorentz_transform_pair(axial, first, second)
    @test_throws NumericalConditioningError boost_pair(axial, first, second)

    transformed = lorentz_transform_displacement(axial, first, second)
    transformed_alias = boost_displacement(
        axial,
        SpacetimeDisplacement(4.0, SA[4.0, 0.0, 0.0]),
    )
    relative_origin = SpacetimeEvent(0.0, SA[0.0, 0.0, 0.0])
    relative_endpoint = SpacetimeEvent(transformed.dt, transformed.dx)
    @test causal_relation(spacetime, relative_origin, relative_endpoint) === :future_null
    @test scaled_interval_residual(spacetime, relative_origin, relative_endpoint) <= 256eps(Float64)
    @test transformed_alias.dt == transformed.dt
    @test transformed_alias.dx == transformed.dx

    recovered = lorentz_transform_displacement(inverse_boost(axial), transformed)
    @test recovered.dt ≈ 4.0 rtol = 4.0e-15
    @test recovered.dx ≈ SA[4.0, 0.0, 0.0] rtol = 4.0e-15 atol = 4.0e-15

    moderate_first = SpacetimeEvent(10.0, SA[0.0, 0.0, 0.0])
    moderate_second = SpacetimeEvent(14.0, SA[4.0, 0.0, 0.0])
    boosted_first, boosted_second =
        lorentz_transform_pair(axial, moderate_first, moderate_second)
    @test causal_relation(spacetime, boosted_first, boosted_second) === :future_null

    oblique = LorentzBoost(spacetime, SA[0.2, -0.15, 0.1])
    oblique_input = SpacetimeDisplacement(5.0, SA[1.0, 2.0, -0.5])
    oblique_output = lorentz_transform_displacement(oblique, oblique_input)
    input_event = SpacetimeEvent(oblique_input.dt, oblique_input.dx)
    output_event = SpacetimeEvent(oblique_output.dt, oblique_output.dx)
    @test causal_relation(spacetime, relative_origin, input_event) ===
          causal_relation(spacetime, relative_origin, output_event)
    @test interval_squared(spacetime, relative_origin, output_event) ≈
          interval_squared(spacetime, relative_origin, input_event) rtol = 2.0e-14

    float_spacetime = MinkowskiSpacetime(1.0f0)
    float_boost = LorentzBoost(float_spacetime, SA[0.25f0, -0.1f0, 0.05f0])
    float_displacement = SpacetimeDisplacement(2.0f0, SA[0.4f0, -0.2f0, 0.1f0])
    float_output = lorentz_transform_displacement(float_boost, float_displacement)
    float_origin = SpacetimeEvent(0.0f0, SA[0.0f0, 0.0f0, 0.0f0])
    @test causal_relation(
        float_spacetime,
        float_origin,
        SpacetimeEvent(float_output.dt, float_output.dx),
    ) === :future_timelike
end

@testset "Lorentz light-cone and proper-time metamorphisms" begin
    rng = MersenneTwister(0xc0ffee)
    spacetime = MinkowskiSpacetime(100.0)
    for _ in 1:256
        emission = SpacetimeEvent(
            4.0 * randn(rng),
            SVector{3,Float64}(randn(rng, 3)) * 10.0,
        )
        receiver_offset = SVector{3,Float64}(randn(rng, 3)) * (1.0 + 30.0 * rand(rng))
        receiver_direction = SVector{3,Float64}(randn(rng, 3))
        receiver_direction /= sqrt(sum(abs2, receiver_direction))
        receiver_velocity = receiver_direction * (0.8 * spacetime.c * rand(rng))
        receiver = InertialWorldline(
            spacetime,
            SpacetimeEvent(emission.t, emission.x + receiver_offset),
            receiver_velocity,
        )

        boost_direction = SVector{3,Float64}(randn(rng, 3))
        boost_direction /= sqrt(sum(abs2, boost_direction))
        boost = LorentzBoost(
            spacetime,
            boost_direction * (0.75 * spacetime.c * rand(rng)),
        )

        original = light_cone_intersection(spacetime, emission, receiver)
        transformed_emission = lorentz_transform(boost, emission)
        transformed_receiver = lorentz_transform(boost, receiver)
        transformed = light_cone_intersection(
            spacetime,
            transformed_emission,
            transformed_receiver,
        )
        expected_reception = lorentz_transform(boost, original.reception)
        coordinate_scale = max(abs(expected_reception.t), maximum(abs, expected_reception.x), 1.0)
        @test abs(transformed.reception.t - expected_reception.t) / coordinate_scale <= 3.0e-13
        @test maximum(abs, transformed.reception.x - expected_reception.x) / coordinate_scale <= 3.0e-13
        @test transformed.scaled_residual <= 3.0e-13

        first_time = emission.t
        second_time = original.reception.t + rand(rng)
        first_event = worldline_event(receiver, first_time)
        second_event = worldline_event(receiver, second_time)
        transformed_first = lorentz_transform(boost, first_event)
        transformed_second = lorentz_transform(boost, second_event)
        original_tau = proper_time_between(spacetime, receiver, first_time, second_time)
        transformed_tau = proper_time_between(
            spacetime,
            transformed_receiver,
            transformed_first.t,
            transformed_second.t,
        )
        @test transformed_tau ≈ original_tau rtol = 4.0e-13 atol = 4.0e-13
    end
end
