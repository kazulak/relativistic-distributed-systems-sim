# Declared worldline kinks split proper-time quadrature panels by default.
# Regression for the E3 trajectory-onset clocks (docs/DEVIATIONS.md D-09):
# without the split, the adaptive error estimate missed the rate kink and
# proper-time inversion refused with NumericalConditioningError.

@testset "declared worldline kinks" begin
    spacetime = MinkowskiSpacetime(1.0)
    kink = 1.3
    v1, v2 = 0.1, 0.8
    position(t) = t <= kink ? (v1 * t, 0.0, 0.0) : (v1 * kink + v2 * (t - kink), 0.0, 0.0)
    velocity(t) = t <= kink ? (v1, 0.0, 0.0) : (v2, 0.0, 0.0)
    exact(a, b) = begin
        before = max(0.0, min(b, kink) - a)
        after = max(0.0, b - max(a, kink))
        before * sqrt(1 - v1^2) + after * sqrt(1 - v2^2)
    end

    declared = ParametricWorldline(spacetime, position, velocity;
        consistency=:assumed, tmin=0.0, tmax=100.0, kinks=(kink,))
    undeclared = ParametricWorldline(spacetime, position, velocity;
        consistency=:assumed, tmin=0.0, tmax=100.0)

    @test worldline_kinks(declared) == [kink]
    @test isempty(worldline_kinks(undeclared))
    @test isempty(worldline_kinks(InertialWorldline(spacetime, (0.0, 0.0, 0.0), (0.0, 0.0, 0.0))))

    for (a, b) in ((0.0, 3.0), (0.2, 1.3000000000000003), (1.0, 7.5), (2.0, 4.0))
        @test isapprox(proper_time_between(spacetime, declared, a, b), exact(a, b); rtol=1e-13)
        # Reverse direction keeps the declared split.
        @test isapprox(proper_time_between(spacetime, declared, b, a), -exact(a, b); rtol=1e-13)
        # Declared kinks and an explicit breakpoint at the same time coexist.
        if prevfloat(kink) > a && nextfloat(kink) < b
            @test isapprox(proper_time_between(spacetime, declared, a, b; breakpoints=(kink,)),
                           exact(a, b); rtol=1e-13)
        end
    end

    # Inversion across the kink recovers the analytic coordinate time.
    for start in (0.0, 0.9)
        duration = exact(start, 5.0)
        t = coordinate_time_after_proper_time(spacetime, declared, start, duration)
        @test isapprox(t, 5.0; rtol=1e-12)
    end

    @test_throws ArgumentError ParametricWorldline(spacetime, position, velocity;
        consistency=:assumed, tmin=0.0, tmax=100.0, kinks=(100.0,))
    @test_throws ArgumentError ParametricWorldline(spacetime, position, velocity;
        consistency=:assumed, tmin=0.0, tmax=100.0, kinks=(NaN,))
end
