@testset "Gauss-Kronrod proper-time quadrature" begin
    spacetime = MinkowskiSpacetime(1.0)
    frequency = 200.0
    base_rate = 0.7
    amplitude = 0.2
    final_time = 1.234
    rate(time) = base_rate + amplitude * cos(frequency * time)
    oscillatory = ParametricWorldline(
        spacetime,
        _ -> SA[0.0, 0.0, 0.0],
        time -> SA[sqrt(1.0 - rate(time)^2), 0.0, 0.0];
        consistency=:assumed,
        tmin=0.0,
        tmax=final_time,
    )
    spacing = pi / frequency
    breakpoints = collect(spacing:spacing:(final_time - spacing / 2))
    measured = proper_time_between(
        spacetime,
        oscillatory,
        0.0,
        final_time;
        rtol=1.0e-11,
        breakpoints=breakpoints,
    )
    oracle = base_rate * final_time + amplitude / frequency * sin(frequency * final_time)
    @test measured ≈ oracle rtol = 2.0e-11 atol = 2.0e-13

    inversion_endpoint = 0.731
    inversion_target = base_rate * inversion_endpoint +
                       amplitude / frequency * sin(frequency * inversion_endpoint)
    recovered_endpoint = coordinate_time_after_proper_time(
        spacetime,
        oscillatory,
        0.0,
        inversion_target;
        rtol=1.0e-10,
        # This is the full schedule through the worldline horizon, including
        # points beyond the unknown endpoint being solved for.
        breakpoints=breakpoints,
    )
    @test recovered_endpoint ≈ inversion_endpoint rtol = 2.0e-10 atol = 2.0e-12
    @test_throws ArgumentError coordinate_time_after_proper_time(
        spacetime,
        oscillatory,
        0.0,
        inversion_target;
        breakpoints=(-0.1, breakpoints...),
    )
    @test_throws QuadratureConvergenceError proper_time_between(
        spacetime,
        oscillatory,
        0.0,
        final_time;
        rtol=1.0e-13,
        max_evaluations=15,
    )
    @test_throws ArgumentError proper_time_between(
        spacetime,
        oscillatory,
        0.0,
        final_time;
        breakpoints=(final_time,),
    )

    float_spacetime = MinkowskiSpacetime(1.0f0)
    float_rate(time) = 0.75f0 + 0.1f0 * cos(40.0f0 * time)
    float_worldline = ParametricWorldline(
        float_spacetime,
        _ -> SA[0.0f0, 0.0f0, 0.0f0],
        time -> SA[sqrt(1.0f0 - float_rate(time)^2), 0.0f0, 0.0f0];
        consistency=:assumed,
        tmin=0.0f0,
        tmax=0.7f0,
    )
    float_result = proper_time_between(float_spacetime, float_worldline, 0.0f0, 0.7f0)
    float_oracle = 0.75f0 * 0.7f0 + 0.1f0 / 40.0f0 * sin(40.0f0 * 0.7f0)
    @test float_result ≈ float_oracle rtol = 2.0f-5

    setprecision(BigFloat, 256) do
        big_spacetime = MinkowskiSpacetime(big"1.0")
        big_rate(time) = big"0.8" + big"0.1" * cos(big"20.0" * time)
        big_worldline = ParametricWorldline(
            big_spacetime,
            _ -> SVector{3,BigFloat}(0, 0, 0),
            time -> SVector{3,BigFloat}(sqrt(1 - big_rate(time)^2), 0, 0);
            consistency=:assumed,
            tmin=big"0.0",
            tmax=big"0.7",
        )
        big_breakpoints = [BigFloat(index) * big(pi) / 20 for index in 1:4]
        big_result = proper_time_between(
            big_spacetime,
            big_worldline,
            big"0.0",
            big"0.7";
            rtol=big"1e-20",
            breakpoints=filter(point -> point < big"0.7", big_breakpoints),
        )
        big_oracle = big"0.8" * big"0.7" + big"0.1" / big"20.0" * sin(big"14.0")
        @test big_result ≈ big_oracle rtol = big"1e-20"
    end
end

@testset "Worldline consistency audits" begin
    spacetime = MinkowskiSpacetime(10.0)
    @test_throws UndefKeywordError ParametricWorldline(
        spacetime,
        time -> SA[time, 0.0, 0.0],
        _ -> SA[1.0, 0.0, 0.0],
    )
    @test_throws InvalidWorldlineError ParametricWorldline(
        spacetime,
        time -> SA[time, 0.0, 0.0],
        _ -> SA[0.0, 0.0, 0.0];
        consistency=:audited,
        tmin=-2.0,
        tmax=2.0,
        audit_times=(-1.0, 0.0, 1.0),
    )

    inertial = InertialWorldline(
        spacetime,
        SA[1.0, -2.0, 3.0],
        SA[2.0, 1.0, -0.5],
    )
    @test audit_worldline(spacetime, inertial, (-3.0, 0.0, 4.0); rtol=1.0e-8) <= 1.0e-8
    accelerated = UniformlyAcceleratedWorldline(
        spacetime,
        SpacetimeEvent(0.0, SA[0.0, 0.0, 0.0]),
        SA[1.0, 1.0, 0.0],
        0.5,
    )
    @test audit_worldline(spacetime, accelerated, (-2.0, 0.0, 2.0); rtol=1.0e-7) <= 1.0e-7
end

@testset "Accelerated proper-time cancellation and inversion" begin
    spacetime = MinkowskiSpacetime(1.0)
    accelerated = UniformlyAcceleratedWorldline(
        spacetime,
        SpacetimeEvent(0.0, SA[0.0, 0.0, 0.0]),
        SA[1.0, 0.0, 0.0],
        1.0,
    )
    first_time = 1.0e12
    second_time = nextfloat(first_time)
    measured = proper_time_between(spacetime, accelerated, first_time, second_time)
    oracle = setprecision(BigFloat, 512) do
        asinh(BigFloat(second_time)) - asinh(BigFloat(first_time))
    end
    @test measured ≈ Float64(oracle) rtol = 2.0e-15
    @test measured > 0.0

    late_target = 1.0e-8
    @test_throws NumericalConditioningError coordinate_time_after_proper_time(
        spacetime,
        accelerated,
        first_time,
        late_target;
        rtol=1.0e-12,
    )
    late_recovered = coordinate_time_after_proper_time(
        spacetime,
        accelerated,
        first_time,
        late_target;
        rtol=1.0e-7,
    )
    late_residual = abs(
        proper_time_between(spacetime, accelerated, first_time, late_recovered) - late_target,
    )
    @test late_recovered > first_time
    @test late_residual <= 1.0e-7 * late_target

    target = proper_time_between(spacetime, accelerated, 3.0, 7.0)
    recovered = coordinate_time_after_proper_time(
        spacetime,
        accelerated,
        3.0,
        target;
        rtol=1.0e-13,
    )
    residual = abs(proper_time_between(spacetime, accelerated, 3.0, recovered) - target)
    @test residual <= 1.0e-13 * target

    large_spacetime = MinkowskiSpacetime(1.0e150)
    large_acceleration = UniformlyAcceleratedWorldline(
        large_spacetime,
        SpacetimeEvent(0.0, SA[0.0, 0.0, 0.0]),
        SA[1.0, 0.0, 0.0],
        1.0e150,
    )
    @test all(isfinite, position_at(large_acceleration, 1.0))

    stationary = InertialWorldline(
        spacetime,
        SpacetimeEvent(1.0e16, SA[0.0, 0.0, 0.0]),
        SA[0.0, 0.0, 0.0],
    )
    @test_throws NumericalConditioningError coordinate_time_after_proper_time(
        spacetime,
        stationary,
        1.0e16,
        0.5,
    )
end
