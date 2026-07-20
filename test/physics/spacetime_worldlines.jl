@testset "Spacetime and causal classification" begin
    @test_throws ArgumentError MinkowskiSpacetime(0.0)
    @test_throws ArgumentError MinkowskiSpacetime(-1.0)
    @test_throws ArgumentError MinkowskiSpacetime(Inf)
    @test_throws ArgumentError MinkowskiSpacetime(NaN)
    @test_throws ArgumentError SpacetimeEvent(0.0, [1.0, 2.0])
    @test_throws ArgumentError SpacetimeEvent(Inf, SA[0.0, 0.0, 0.0])

    spacetime = MinkowskiSpacetime(2.0)
    origin = SpacetimeEvent(0.0, SA[0.0, 0.0, 0.0])
    timelike = SpacetimeEvent(2.0, SA[1.0, 0.0, 0.0])
    null = SpacetimeEvent(2.0, SA[4.0, 0.0, 0.0])
    spacelike = SpacetimeEvent(1.0, SA[3.0, 0.0, 0.0])

    @test interval_squared(spacetime, origin, timelike) == 15.0
    @test interval_squared(spacetime, origin, null) == 0.0
    @test interval_squared(spacetime, origin, spacelike) == -5.0
    @test scaled_interval_residual(spacetime, origin, null) == 0.0
    @test scaled_interval_residual(spacetime, origin, origin) == 0.0
    @test causal_relation(spacetime, origin, timelike) === :future_timelike
    @test causal_relation(spacetime, origin, null) === :future_null
    @test causal_relation(spacetime, origin, spacelike) === :spacelike
    @test causal_relation(spacetime, null, origin) === :past_null
    @test is_future_causal(spacetime, origin, null)
    @test !is_future_causal(spacetime, origin, spacelike)
end

@testset "Worldline validation and proper clocks" begin
    spacetime = MinkowskiSpacetime(10.0)
    origin = SpacetimeEvent(2.0, SA[1.0, -2.0, 0.5])
    velocity_vector = SA[6.0, 0.0, 0.0]
    inertial = InertialWorldline(spacetime, origin, velocity_vector)

    @test position_at(inertial, 3.5) == SA[10.0, -2.0, 0.5]
    @test coordinate_velocity(inertial, -100.0) == velocity_vector
    @test worldline_event(inertial, 2.0) == origin
    @test is_timelike_velocity(spacetime, velocity_vector)
    @test !is_timelike_velocity(spacetime, SA[10.0, 0.0, 0.0])
    @test_throws InvalidWorldlineError InertialWorldline(
        spacetime,
        origin,
        SA[10.0, 0.0, 0.0],
    )
    @test_throws InvalidWorldlineError InertialWorldline(
        spacetime,
        origin,
        SA[11.0, 0.0, 0.0],
    )
    @test_throws InvalidWorldlineError InertialWorldline(
        spacetime,
        origin,
        SA[NaN, 0.0, 0.0],
    )

    gamma = 1.25
    @test lorentz_factor(spacetime, velocity_vector) ≈ gamma
    @test proper_time_rate(spacetime, inertial, 4.0) ≈ 0.8
    @test proper_time_between(spacetime, inertial, 2.0, 12.0) ≈ 8.0
    @test proper_duration(spacetime, inertial, 2.0, 12.0) == ProperTime(8.0)
    @test coordinate_time_after_proper_time(spacetime, inertial, 2.0, ProperTime(8.0)) ≈ 12.0

    circular_position(t) = SA[2.0 * cos(t), 2.0 * sin(t), 0.0]
    circular_velocity(t) = SA[-2.0 * sin(t), 2.0 * cos(t), 0.0]
    parametric = ParametricWorldline(
        spacetime,
        circular_position,
        circular_velocity;
        consistency=:audited,
        tmin=0.0,
        tmax=10.0,
        validate_at=0.0,
        audit_times=(1.0, 3.0, 7.0),
    )
    expected = 4.0 * sqrt(1.0 - 0.04)
    @test proper_time_between(spacetime, parametric, 1.0, 5.0) ≈ expected rtol = 1.0e-11
    @test_throws DomainError position_at(parametric, -1.0)

    invalid_parametric = ParametricWorldline(
        spacetime,
        t -> SA[11.0 * t, 0.0, 0.0],
        _ -> SA[11.0, 0.0, 0.0];
        consistency=:assumed,
        tmin=0.0,
        tmax=1.0,
    )
    @test_throws InvalidWorldlineError coordinate_velocity(invalid_parametric, 0.5)

    accelerated = UniformlyAcceleratedWorldline(
        spacetime,
        origin,
        SA[1.0, 0.0, 0.0],
        2.0,
    )
    coordinate_time = 7.0
    z = 2.0 * (coordinate_time - origin.t) / spacetime.c
    expected_tau = spacetime.c / 2.0 * asinh(z)
    @test proper_time_between(spacetime, accelerated, origin.t, coordinate_time) ≈ expected_tau
    @test is_timelike_velocity(spacetime, coordinate_velocity(accelerated, coordinate_time))
    recovered_time = coordinate_time_after_proper_time(
        spacetime,
        accelerated,
        origin.t,
        ProperTime(expected_tau),
    )
    @test recovered_time ≈ coordinate_time rtol = 1.0e-12
end
