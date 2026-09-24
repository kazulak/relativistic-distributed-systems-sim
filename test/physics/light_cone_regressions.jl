# Regressions for two light-cone failure classes seen in the E3 pilot
# (909 / 11,880 runs aborted with LightConeConvergenceError). The solver
# inputs below were extracted from the failing runs.

# The E3 trajectory-change worldline (inertial at beta until `onset`, then
# hyperbolic at proper acceleration alpha; C^1 at the onset), written
# generically so the same formula serves as a BigFloat oracle.
function e3_trajectory_position(t, x0; beta=0.5, alpha=0.25, onset=3.0, c=1.0)
    R = typeof(float(t))
    beta, alpha, onset, c, x0 = R(beta), R(alpha), R(onset), R(c), R(x0)
    phi_s = atanh(beta)
    v_s = beta * c
    t <= onset && return x0 + v_s * t
    phi = asinh(sinh(phi_s) + alpha * (t - onset) / c)
    return x0 + v_s * onset + (c^2 / alpha) * (cosh(phi) - cosh(phi_s))
end

function e3_trajectory_velocity(t; beta=0.5, alpha=0.25, onset=3.0, c=1.0)
    t <= onset && return beta * c
    return c * tanh(asinh(sinh(atanh(beta)) + alpha * (t - onset) / c))
end

function e3_trajectory_worldline(spacetime, x0)
    return ParametricWorldline(
        spacetime,
        t -> SA[e3_trajectory_position(t, x0), 0.0, 0.0],
        t -> SA[e3_trajectory_velocity(t), 0.0, 0.0];
        consistency=:assumed,
        tmin=-Inf,
        tmax=Inf,
        validate_at=0.0,
    )
end

# Independent 256-bit bisection for the earliest root of
# |x_r(t) - x_e| = c (t - t_e) on a one-dimensional receiver.
function bigfloat_light_root(position, t_emit, x_emit, c, high_delay)
    return setprecision(BigFloat, 256) do
        te = BigFloat(t_emit)
        xe = BigFloat(x_emit)
        f(delay) = abs(position(te + delay) - xe) - BigFloat(c) * delay
        low, high = BigFloat(0), BigFloat(high_delay)
        f(high) < 0 || error("oracle bracket is invalid")
        for _ in 1:300
            mid = (low + high) / 2
            f(mid) > 0 ? (low = mid) : (high = mid)
        end
        te + (low + high) / 2
    end
end

@testset "Light-cone E3 pilot regressions" begin
    spacetime = MinkowskiSpacetime(1.0)
    rtol = 512 * eps(Float64)

    @testset "unsquared tolerance is not below the coordinate ULP" begin
        # Failing input: separation 1.7e-5 at emission epoch 0.64. The old
        # tolerance rtol * scale = 1.9e-18 was below half an ULP of the
        # reception coordinate (5.6e-17), so the exactly rounded analytic
        # root failed validation with error 6.9e-18.
        emission = SpacetimeEvent(0.6397317140276021, SA[1.6767873274876888e-5, 0.0, 0.0])
        receiver = InertialWorldline(
            spacetime,
            SpacetimeEvent(0.0, SA[0.0, 0.0, 0.0]),
            SA[-0.0, 0.0, 0.0],
        )
        result = light_cone_intersection(spacetime, emission, receiver; max_coordinate_time=147.0)
        @test result.method === :analytic_inertial
        oracle = setprecision(BigFloat, 256) do
            BigFloat(emission.t) + BigFloat(emission.x[1])
        end
        @test abs(BigFloat(result.reception.t) - oracle) <= eps(result.reception.t)

        error = abs(emission.x[1] - (result.reception.t - emission.t))
        scale = max(emission.x[1], result.reception.t - emission.t)
        @test error > rtol * scale  # the old, scale-unaware contract fails
        floor = RelativisticDistributedSystemsSim._light_equation_floor(
            spacetime,
            emission,
            result.reception.t,
            result.reception.x,
        )
        @test error <= floor
        # The floor is a small multiple of the coordinate ULP, not a loosening.
        @test floor <= 4 * eps(Float64) * (result.reception.t + emission.x[1])
        @test result.equation_residual < 1.0e-12
    end

    @testset "trajectory-change receiver no longer exhausts max_iterations" begin
        # Failing input: node 5 -> node 4 of the E3 onset scenario
        # (beta_initial=0.5, rho=0.1, a_star=0.05), emission after the onset.
        # The delay-space bracket never collapsed because every probe snapped
        # to the same two adjacent reception times (ULP 8.9e-16 at t=4.78) and
        # Newton 2-cycled between them.
        receiver = e3_trajectory_worldline(spacetime, 0.02)
        sender = e3_trajectory_worldline(spacetime, 0.04)
        emission = worldline_event(sender, 4.771023212978069)
        @test emission.x == SA[2.6352036553943066, 0.0, 0.0]  # exact failing input
        result = light_cone_intersection(spacetime, emission, receiver; max_coordinate_time=147.0)
        @test result.iterations <= 8
        oracle = bigfloat_light_root(
            t -> e3_trajectory_position(t, 0.02),
            emission.t,
            emission.x[1],
            1.0,
            0.02,
        )
        @test abs(BigFloat(result.reception.t) - oracle) <= 4 * eps(result.reception.t)
        # At the resolution limit the solver returns the causal endpoint:
        # never outside the future light cone.
        @test causal_relation(spacetime, emission, result.reception) in
              (:future_null, :future_timelike)
        @test result.reception.t - emission.t >= abs(result.reception.x[1] - emission.x[1])
    end

    @testset "roots across the C^1 onset kink match the oracle" begin
        receiver = e3_trajectory_worldline(spacetime, -0.02)
        for sender_x0 in (0.02, 0.04, 0.2), t_emit in (2.95, 2.99, 2.9999, 3.0, 3.0001, 3.2, 12.0)
            sender = e3_trajectory_worldline(spacetime, sender_x0)
            emission = worldline_event(sender, t_emit)
            result = light_cone_intersection(spacetime, emission, receiver)
            oracle = bigfloat_light_root(
                t -> e3_trajectory_position(t, -0.02),
                emission.t,
                emission.x[1],
                1.0,
                8.0,
            )
            @test abs(BigFloat(result.reception.t) - oracle) <= 8 * eps(result.reception.t)
            @test result.iterations <= 16
        end
    end

    @testset "safeguard converges when Newton is poor" begin
        # A deliberately inconsistent (but timelike) declared velocity makes
        # every Newton step wrong; the bracketed safeguard must still converge
        # to the root of the position equation.
        receiver = ParametricWorldline(
            spacetime,
            t -> SA[1.0 + 0.6 * t + 0.005 * sin(40.0 * t), 0.0, 0.0],
            _ -> SA[-0.9, 0.0, 0.0];
            consistency=:assumed,
            tmin=0.0,
            tmax=Inf,
        )
        emission = SpacetimeEvent(0.25, SA[0.0, 0.0, 0.0])
        result = light_cone_intersection(spacetime, emission, receiver)
        oracle = bigfloat_light_root(
            t -> 1 + big"0.6" * t + big"0.005" * sin(40 * t),
            emission.t,
            0.0,
            1.0,
            40.0,
        )
        @test abs(BigFloat(result.reception.t) - oracle) <= 1.0e-12
        @test result.iterations <= 128
    end

    @testset "invalid inputs still throw" begin
        superluminal = ParametricWorldline(
            spacetime,
            t -> SA[1.0 + 1.5 * t, 0.0, 0.0],
            _ -> SA[1.5, 0.0, 0.0];
            consistency=:assumed,
            tmin=0.0,
            tmax=Inf,
            validate_at=nothing,
        )
        @test_throws InvalidWorldlineError light_cone_intersection(
            spacetime,
            SpacetimeEvent(0.0, SA[0.0, 0.0, 0.0]),
            superluminal,
        )
        receding = InertialWorldline(
            spacetime,
            SpacetimeEvent(0.0, SA[1.0, 0.0, 0.0]),
            SA[0.5, 0.0, 0.0],
        )
        @test_throws NoFutureLightConeIntersection light_cone_intersection(
            spacetime,
            SpacetimeEvent(0.0, SA[0.0, 0.0, 0.0]),
            receding;
            max_coordinate_time=1.5,
        )
    end

    @testset "E3 pilot repro runs no longer abort" begin
        Research = RelativisticDistributedSystemsSim.Research
        workload = Research.WorkloadSpec(client_node=1, operation_count=8, read_every=2)
        network = Research.NetworkProfile(
            processing_delay=0.001,
            delay_jitter=0.001,
            bandwidth_bytes_per_time=100_000.0,
        )
        inertial = Research.canonical_scenario(
            Research.AsymmetricRecedingInertial;
            cluster_size=5,
            beta=-0.25,
            rho=0.2,
            workload=workload,
            network=network,
        )
        run = Research.run_scenario(
            inertial;
            seed=2,
            timing=Research.TimingSpec(arm=:B3, level=0; base_timeout=0.7),
        )
        @test run.status != :failed
        onset = Research.trajectory_change_scenario(
            cluster_size=5;
            beta_initial=0.5,
            rho=0.1,
            a_star=0.05,
            workload=workload,
            network=network,
        )
        run = Research.run_scenario(
            onset;
            seed=1,
            timing=Research.TimingSpec(arm=:B0, level=0; base_timeout=1.2),
        )
        @test run.status != :failed
    end
end
