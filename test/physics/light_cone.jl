function independent_inertial_oracle(t_emit, x_emit, receiver_at_emit, receiver_velocity, c)
    return setprecision(BigFloat, 256) do
        t0 = BigFloat(t_emit)
        x0 = BigFloat.(Tuple(x_emit))
        receiver0 = BigFloat.(Tuple(receiver_at_emit))
        velocity0 = BigFloat.(Tuple(receiver_velocity))
        c_big = BigFloat(c)
        distance_at(delay) = sqrt(sum((receiver0[i] + velocity0[i] * delay - x0[i])^2 for i in 1:3))
        equation(delay) = distance_at(delay) - c_big * delay
        initial_distance = distance_at(BigFloat(0))
        speed = sqrt(sum(value^2 for value in velocity0))
        high = 2 * initial_distance / (c_big - speed)
        while equation(high) > 0
            high *= 2
        end
        low = BigFloat(0)
        for _ in 1:300
            midpoint = (low + high) / 2
            if equation(midpoint) > 0
                low = midpoint
            else
                high = midpoint
            end
        end
        return Float64(t0 + (low + high) / 2)
    end
end

@testset "Analytic direct light-time cases" begin
    spacetime = MinkowskiSpacetime(100.0)
    emission = SpacetimeEvent(2.0, SA[0.0, 0.0, 0.0])
    range = 40.0

    cases = (
        (:stationary, SA[0.0, 0.0, 0.0], range / spacetime.c),
        (:receding, SA[60.0, 0.0, 0.0], range / (spacetime.c - 60.0)),
        (:approaching, SA[-60.0, 0.0, 0.0], range / (spacetime.c + 60.0)),
        (:transverse, SA[0.0, 60.0, 0.0], range / sqrt(spacetime.c^2 - 60.0^2)),
    )

    for (name, receiver_velocity, expected_delay) in cases
        @testset "$name" begin
            receiver = InertialWorldline(
                spacetime,
                SpacetimeEvent(emission.t, SA[range, 0.0, 0.0]),
                receiver_velocity,
            )
            result = light_cone_intersection(spacetime, emission, receiver)
            @test result.reception.t ≈ emission.t + expected_delay rtol = 8.0e-15
            @test result.method === :analytic_inertial
            @test result.scaled_residual <= 8.0e-16
            @test causal_relation(spacetime, emission, result.reception) === :future_null
        end
    end

    coincident_receiver = InertialWorldline(
        spacetime,
        emission,
        SA[20.0, 0.0, 0.0],
    )
    coincident = light_cone_intersection(spacetime, emission, coincident_receiver)
    @test coincident.reception == emission
    @test coincident.method === :coincident
end

@testset "Independent high-precision inertial oracle" begin
    rng = MersenneTwister(0x5eed)
    spacetime = MinkowskiSpacetime(37.0)
    for _ in 1:512
        t_emit = 20.0 * rand(rng) - 10.0
        x_emit = SVector{3,Float64}(randn(rng, 3))
        receiver_at_emit = x_emit + SVector{3,Float64}(randn(rng, 3)) * (0.01 + 100.0 * rand(rng))
        direction = SVector{3,Float64}(randn(rng, 3))
        direction /= sqrt(sum(abs2, direction))
        receiver_velocity = direction * (0.97 * spacetime.c * rand(rng))
        emission = SpacetimeEvent(t_emit, x_emit)
        receiver = InertialWorldline(
            spacetime,
            SpacetimeEvent(t_emit, receiver_at_emit),
            receiver_velocity,
        )
        result = light_cone_intersection(spacetime, emission, receiver)
        oracle = independent_inertial_oracle(
            t_emit,
            x_emit,
            receiver_at_emit,
            receiver_velocity,
            spacetime.c,
        )
        @test result.reception.t ≈ oracle rtol = 3.0e-14 atol = 3.0e-14
        @test result.scaled_residual <= 2.0e-14
    end
end

@testset "Scale invariance and invalid horizons" begin
    for scale in 10.0 .^ (-12:3:12)
        spacetime = MinkowskiSpacetime(3.0)
        emission = SpacetimeEvent(-2.0 * scale, SA[scale, -scale, 0.5 * scale])
        receiver = InertialWorldline(
            spacetime,
            SpacetimeEvent(emission.t, emission.x + SA[4.0 * scale, 0.0, 0.0]),
            SA[0.75, 0.3, 0.0],
        )
        result = light_cone_intersection(spacetime, emission, receiver)
        oracle = independent_inertial_oracle(
            emission.t,
            emission.x,
            position_at(receiver, emission.t),
            receiver.velocity,
            spacetime.c,
        )
        @test result.reception.t ≈ oracle rtol = 7.0e-14 atol = 1.0e-26 * scale
        @test result.scaled_residual <= 3.0e-14
    end

    spacetime = MinkowskiSpacetime(1.0)
    emission = SpacetimeEvent(0.0, SA[0.0, 0.0, 0.0])
    asymptotic = ParametricWorldline(
        spacetime,
        t -> SA[t + exp(-t), 0.0, 0.0],
        t -> SA[1.0 - exp(-t), 0.0, 0.0];
        consistency=:assumed,
        tmin=0.0,
        tmax=20.0,
        validate_at=0.0,
    )
    @test_throws NoFutureLightConeIntersection light_cone_intersection(
        spacetime,
        emission,
        asymptotic,
    )

    receding = InertialWorldline(
        spacetime,
        SA[2.0, 0.0, 0.0],
        SA[0.5, 0.0, 0.0],
    )
    @test_throws NoFutureLightConeIntersection light_cone_intersection(
        spacetime,
        emission,
        receding;
        max_coordinate_time=3.0,
    )
    @test_throws ArgumentError light_cone_intersection(spacetime, emission, receding; rtol=0.0)
end

@testset "Accelerated receiver" begin
    spacetime = MinkowskiSpacetime(10.0)
    emission = SpacetimeEvent(0.0, SA[0.0, 0.0, 0.0])
    receiver = UniformlyAcceleratedWorldline(
        spacetime,
        SpacetimeEvent(0.0, SA[5.0, 0.0, 0.0]),
        SA[1.0, 0.0, 0.0],
        1.0,
    )
    result = light_cone_intersection(spacetime, emission, receiver; max_coordinate_time=10.0)
    @test result.reception.t > 0.5
    @test result.reception.t < 1.0
    @test result.scaled_residual <= 1.0e-13

    oracle = setprecision(BigFloat, 256) do
        low = BigFloat(0)
        high = BigFloat(10)
        c = BigFloat(10)
        acceleration = BigFloat(1)
        equation(t) = BigFloat(5) + c^2 / acceleration *
                      (sqrt(1 + (acceleration * t / c)^2) - 1) - c * t
        for _ in 1:300
            midpoint = (low + high) / 2
            if equation(midpoint) > 0
                low = midpoint
            else
                high = midpoint
            end
        end
        Float64((low + high) / 2)
    end
    @test result.reception.t ≈ oracle rtol = 5.0e-14
end
