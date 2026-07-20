@testset "Legacy scalar solver compatibility through package API" begin
    spacetime_c = 100.0
    x_emit = SA[0.0, 0.0, 0.0]
    receiver_origin = SA[10.0, -4.0, 2.0]
    receiver_velocity = SA[30.0, 10.0, -5.0]
    x_receiver(t) = receiver_origin + receiver_velocity * t
    v_receiver(_) = receiver_velocity

    result = solve_light_time_result(
        0.0,
        x_emit,
        x_receiver,
        v_receiver,
        spacetime_c,
    )
    reception_time = solve_light_time(
        0.0,
        x_emit,
        x_receiver,
        v_receiver,
        spacetime_c,
    )
    @test reception_time == result.tB
    @test result.converged_newton
    @test result.iterations <= 6
    @test abs(
        sqrt(sum(abs2, x_receiver(reception_time) - x_emit)) - spacetime_c * reception_time,
    ) <= 2.0e-13
    @test minkowski_interval2(
        0.0,
        x_emit,
        reception_time,
        x_receiver(reception_time),
        spacetime_c,
    ) ≈ 0.0 atol = 2.0e-12

    rng = MersenneTwister(1234)
    for _ in 1:10_000
        t_emit = 10.0 * rand(rng)
        direction = SVector{3,Float64}(randn(rng, 3))
        direction /= sqrt(sum(abs2, direction))
        velocity_vector = direction * (0.95 * spacetime_c * rand(rng))
        receiver_at_emit = SA[
            1.0 + 100.0 * rand(rng),
            -50.0 + 100.0 * rand(rng),
            -50.0 + 100.0 * rand(rng),
        ]
        receiver_at_zero = receiver_at_emit - velocity_vector * t_emit
        receiver_position(t) = receiver_at_zero + velocity_vector * t
        receiver_rate(_) = velocity_vector
        solved = solve_light_time_result(
            t_emit,
            x_emit,
            receiver_position,
            receiver_rate,
            spacetime_c,
        )
        distance_residual = abs(
            sqrt(sum(abs2, receiver_position(solved.tB) - x_emit)) -
            spacetime_c * (solved.tB - t_emit),
        )
        scale = max(sqrt(sum(abs2, receiver_position(solved.tB) - x_emit)), 1.0)
        @test distance_residual / scale <= 5.0e-14
        @test solved.iterations <= 8
    end
end

@testset "Package-level fallback and exception compatibility" begin
    spacetime = MinkowskiSpacetime(10.0)
    emission = SpacetimeEvent(0.0, SA[0.0, 0.0, 0.0])
    accelerated = UniformlyAcceleratedWorldline(
        spacetime,
        SpacetimeEvent(0.0, SA[5.0, 0.0, 0.0]),
        SA[1.0, 0.0, 0.0],
        1.0,
    )
    solved = light_cone_intersection(
        spacetime,
        emission,
        accelerated;
        max_coordinate_time=10.0,
    )
    @test solved.method === :newton
    @test solved.iterations > 1
    @test solved.equation_residual <= 512 * eps(Float64)
    @test_throws LightConeConvergenceError light_cone_intersection(
        spacetime,
        emission,
        accelerated;
        max_coordinate_time=10.0,
        max_iterations=1,
        rtol=eps(Float64),
    )

    x_receiver(time) = SA[2.0 + 0.2 * time, 1.0 + 0.1 * time, 0.0]
    v_receiver(_) = SA[0.2, 0.1, 0.0]
    @test_throws ArgumentError solve_light_time(
        0.0,
        SA[0.0, 0.0, 0.0],
        x_receiver,
        v_receiver,
        0.0,
    )
    superluminal_velocity(_) = SA[11.0, 0.0, 0.0]
    @test_throws InvalidWorldlineError solve_light_time(
        0.0,
        SA[0.0, 0.0, 0.0],
        x_receiver,
        superluminal_velocity,
        10.0,
    )
end

@testset "Production solver allocation and GC-state contract" begin
    spacetime = MinkowskiSpacetime(1.0)
    emission = SpacetimeEvent(0.0, SA[0.0, 0.0, 0.0])
    receiver = InertialWorldline(
        spacetime,
        SA[2.0, 1.0, 0.0],
        SA[0.2, 0.1, 0.0],
    )
    light_cone_intersection(spacetime, emission, receiver)
    typed_allocations = @allocated light_cone_intersection(spacetime, emission, receiver)
    @test typed_allocations <= 16_384

    x_receiver(time) = SA[2.0 + 0.2 * time, 1.0 + 0.1 * time, 0.0]
    v_receiver(_) = SA[0.2, 0.1, 0.0]
    solve_light_time(0.0, emission.x, x_receiver, v_receiver, spacetime.c)
    compatibility_allocations = @allocated solve_light_time(
        0.0,
        emission.x,
        x_receiver,
        v_receiver,
        spacetime.c,
    )
    @test compatibility_allocations <= 8_192

    previous_gc_state = GC.enable(false)
    try
        solve_light_time(0.0, emission.x, x_receiver, v_receiver, spacetime.c)
        observed_gc_state = GC.enable(false)
        @test observed_gc_state === false
    finally
        GC.enable(previous_gc_state)
    end

    physics_directory = joinpath(dirname(pathof(RelativisticDistributedSystemsSim)), "Physics")
    production_source = join(
        read(joinpath(physics_directory, filename), String) for filename in readdir(physics_directory)
    )
    @test !occursin("jl_gc_enable", production_source)
    @test !occursin("GC.enable", production_source)
end
