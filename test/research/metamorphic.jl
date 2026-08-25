function _rotate_worldline(worldline::InertialWorldline{Float64})
    rotated_origin = SpacetimeEvent(
        worldline.origin.t,
        (-worldline.origin.x[2], worldline.origin.x[1], worldline.origin.x[3]),
    )
    rotated_velocity = (
        -worldline.velocity[2],
        worldline.velocity[1],
        worldline.velocity[3],
    )
    return InertialWorldline(MinkowskiSpacetime(worldline.c), rotated_origin, rotated_velocity)
end

function _rotate_worldline(worldline::UniformlyAcceleratedWorldline{Float64})
    origin = worldline.origin
    rotated_origin = SpacetimeEvent(origin.t, (-origin.x[2], origin.x[1], origin.x[3]))
    rotated_direction = (-worldline.direction[2], worldline.direction[1], worldline.direction[3])
    return UniformlyAcceleratedWorldline(
        MinkowskiSpacetime(worldline.c),
        rotated_origin,
        rotated_direction,
        worldline.proper_acceleration,
    )
end

function _rotated_scenario(config::ScenarioConfig)
    return ScenarioConfig(
        config.name,
        config.family,
        config.spacetime,
        AbstractWorldline{Float64}[_rotate_worldline(w) for w in config.worldlines],
        config.raft,
        config.network,
        config.faults,
        config.workload,
        config.window,
        config.characteristic_distance,
        config.beta_scale,
        config.proper_acceleration_scale,
    )
end

function _approximate_trace_match(left, right; atol=1.0e-9)
    left_records = trace_records(left.trace)
    right_records = trace_records(right.trace)
    length(left_records) == length(right_records) || return false
    for (a, b) in zip(left_records, right_records)
        a.event_id == b.event_id || return false
        a.causal_parent == b.causal_parent || return false
        a.target == b.target || return false
        a.payload_type == b.payload_type || return false
        isapprox(a.coordinate_time, b.coordinate_time; atol=atol, rtol=1.0e-12) ||
            return false
    end
    return true
end

@testset "rotation metamorphic equivalence preserves the full causal trace" begin
    for family in instances(ScenarioFamily)
        config = canonical_scenario(family; cluster_size=3, workload=SMALL_WORKLOAD)
        original = run_scenario(config; seed=0x5157)
        rotated = run_scenario(_rotated_scenario(config); seed=0x5157)
        @test original.status == :completed
        @test rotated.status == :completed
        @test all_safety(original.safety)
        @test all_safety(rotated.safety)
        @test _approximate_trace_match(original, rotated)
        @test rotated.metrics.elections_started == original.metrics.elections_started
        @test rotated.metrics.committed_operations == original.metrics.committed_operations
        @test rotated.metrics.messages_sent == original.metrics.messages_sent
        @test rotated.metrics.bytes_sent == original.metrics.bytes_sent
        @test rotated.metrics.leaders_observed == original.metrics.leaders_observed
    end
end

function _map_time_through(boost, worldline, time)
    return Float64(lorentz_transform(boost, worldline_event(worldline, time)).t)
end

function _boosted_window(window::ExperimentWindow, boost, client_worldline)
    start_p = _map_time_through(boost, client_worldline, window.start_coordinate)
    warmup_p = _map_time_through(boost, client_worldline, window.warmup_end_coordinate)
    measurement_p =
        _map_time_through(boost, client_worldline, window.measurement_end_coordinate)
    censor_p = _map_time_through(boost, client_worldline, window.censor_coordinate)
    return ExperimentWindow(
        start_coordinate=start_p,
        warmup_duration=warmup_p - start_p,
        measurement_duration=measurement_p - warmup_p,
        censor_duration=censor_p - measurement_p,
    )
end

function _boosted_scenario(config::ScenarioConfig, frame_velocity)
    boost = LorentzBoost(config.spacetime, frame_velocity)
    worldlines = AbstractWorldline{Float64}[
        lorentz_transform(boost, worldline) for worldline in config.worldlines
    ]
    client = config.worldlines[config.workload.client_node]
    return ScenarioConfig(
        config.name,
        config.family,
        config.spacetime,
        worldlines,
        config.raft,
        config.network,
        FaultSpec[],
        config.workload,
        _boosted_window(config.window, boost, client),
        config.characteristic_distance,
        config.beta_scale,
        config.proper_acceleration_scale,
    )
end

_committed_request_ids(result) =
    sort([operation.request_id for operation in result.operations if operation.outcome == :committed])

function _assert_invariant_decision_equivalence(
    original,
    boosted;
    dilation=1.0,
    dilation_rtol=nothing,
)
    @test boosted.status == :completed == original.status
    @test all_safety(original.safety)
    @test all_safety(boosted.safety)
    @test isempty(boosted.safety.violations)
    @test boosted.metrics.elections_started == original.metrics.elections_started
    @test boosted.metrics.terms_observed == original.metrics.terms_observed
    @test boosted.metrics.leader_changes == original.metrics.leader_changes
    @test boosted.metrics.leaders_observed == original.metrics.leaders_observed
    @test boosted.metrics.committed_operations == original.metrics.committed_operations
    @test boosted.metrics.committed_writes == original.metrics.committed_writes
    @test boosted.metrics.committed_reads == original.metrics.committed_reads
    @test boosted.metrics.censored_operations == original.metrics.censored_operations
    @test _committed_request_ids(boosted) == _committed_request_ids(original)
    original_latencies = sort(original.metrics.commit_latencies_proper)
    boosted_latencies = sort(boosted.metrics.commit_latencies_proper)
    rtol = isnothing(dilation_rtol) ? 0.05 : dilation_rtol
    @test all(
        isapprox(a, b * dilation; rtol=rtol, atol=1.0e-9) for
        (a, b) in zip(original_latencies, boosted_latencies)
    )
    @test maximum(delay.direct_null_residual for delay in boosted.metrics.causal_delays) <=
          4096eps(Float64)
end

@testset "boost metamorphic equivalence preserves decisions and proper times" begin
    for family in (ColocatedControl, SeparatedStaticBaseline, AsymmetricRecedingInertial),
        velocity in ((0.5, 0.0, 0.0), (0.28, 0.32, -0.18))

        config = canonical_scenario(family; cluster_size=3, workload=SMALL_WORKLOAD)
        c = config.spacetime.c
        boosted_velocity =
            (velocity[1] * c, velocity[2] * c, velocity[3] * c)
        beta_norm = sqrt(sum(abs2, velocity))
        dilation = 1 / sqrt(1 - beta_norm^2)
        original = run_scenario(config; seed=0x424242)
        boosted =
            run_scenario(_boosted_scenario(config, boosted_velocity); seed=0x424242)
        _assert_invariant_decision_equivalence(
            original,
            boosted;
            dilation=family == ColocatedControl ? dilation : 1.0,
            dilation_rtol=0.02,
        )

        if family == ColocatedControl && !isempty(original.metrics.commit_latencies_proper)
            ordered = sort(copy(original.metrics.commit_latencies_proper))
            boosted_ordered = sort(copy(boosted.metrics.commit_latencies_proper))
            original_median =
                isempty(ordered) ? 0.0 :
                (isodd(length(ordered)) ? ordered[length(ordered) >>> 1 + 1] :
                 (ordered[length(ordered) >> 1] + ordered[length(ordered) >> 1 + 1]) / 2)
            boosted_median =
                isempty(boosted_ordered) ? 0.0 :
                (isodd(length(boosted_ordered)) ? boosted_ordered[length(boosted_ordered) >>> 1 + 1] :
                 (boosted_ordered[length(boosted_ordered) >> 1] + boosted_ordered[length(boosted_ordered) >> 1 + 1]) / 2)
            @test boosted_median * dilation ≈ original_median rtol = 0.05
        end

        inverse_velocity = (-boosted_velocity[1], -boosted_velocity[2], -boosted_velocity[3])
        restored =
            _boosted_scenario(_boosted_scenario(config, boosted_velocity), inverse_velocity)
        for (index, worldline) in enumerate(config.worldlines)
            expected = coordinate_velocity(worldline, config.window.start_coordinate)
            observed = coordinate_velocity(
                restored.worldlines[index],
                restored.window.start_coordinate,
            )
            @test all(
                isapprox(observed[i], expected[i]; rtol=1.0e-9, atol=1.0e-12) for i in 1:3
            )
        end
        @test isapprox(
            restored.window.warmup_end_coordinate,
            config.window.warmup_end_coordinate;
            rtol=1.0e-9,
        )
    end
end
