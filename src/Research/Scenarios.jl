function _family_name(family::ScenarioFamily)
    family == ColocatedControl && return :colocated_control
    family == SeparatedStaticBaseline && return :separated_static
    family == AsymmetricRecedingInertial && return :asymmetric_receding
    family == AcceleratingBaseline && return :accelerating
    return :partition_drop_stress
end

function _canonical_worldlines(
    family::ScenarioFamily,
    spacetime::MinkowskiSpacetime{Float64},
    cluster_size::Int,
    spacing::Float64,
    beta::Float64,
    acceleration::Float64,
)
    worldlines = AbstractWorldline{Float64}[]
    midpoint = (cluster_size + 1) / 2
    for node in 1:cluster_size
        centered = node - midpoint
        if family == ColocatedControl
            push!(worldlines, InertialWorldline(spacetime, (0.0, 0.0, 0.0), (0.0, 0.0, 0.0)))
        elseif family == AsymmetricRecedingInertial
            fraction = (node - 1) / (cluster_size - 1)
            position = ((node - 1) * spacing, 0.0, 0.0)
            velocity = (fraction * beta * spacetime.c, 0.0, 0.0)
            push!(worldlines, InertialWorldline(spacetime, position, velocity))
        elseif family == AcceleratingBaseline && centered != 0
            origin = SpacetimeEvent(0.0, (centered * spacing, 0.0, 0.0))
            direction = (sign(centered), 0.0, 0.0)
            push!(
                worldlines,
                UniformlyAcceleratedWorldline(spacetime, origin, direction, acceleration),
            )
        else
            position = (centered * spacing, 0.0, 0.0)
            push!(worldlines, InertialWorldline(spacetime, position, (0.0, 0.0, 0.0)))
        end
    end
    return worldlines
end

function _stress_faults(window::ExperimentWindow, cluster_size::Int)
    isolate = cluster_size
    crash = cluster_size - 1
    partition_at = window.warmup_end_coordinate + 0.65
    heal_at = min(window.measurement_end_coordinate - 0.45, partition_at + 1.25)
    crash_at = window.warmup_end_coordinate + 1.0
    recover_at = min(window.measurement_end_coordinate - 0.2, crash_at + 0.65)
    faults = FaultSpec[]
    for peer in 1:(cluster_size - 1)
        push!(faults, FaultSpec(partition_at, SetLinkAvailability(isolate, peer, false)))
        push!(faults, FaultSpec(partition_at, SetLinkAvailability(peer, isolate, false)))
        push!(faults, FaultSpec(heal_at, SetLinkAvailability(isolate, peer, true)))
        push!(faults, FaultSpec(heal_at, SetLinkAvailability(peer, isolate, true)))
    end
    push!(faults, FaultSpec(crash_at, CrashNode(crash)))
    push!(faults, FaultSpec(recover_at, RecoverNode(crash)))
    return faults
end

"""
Construct one of the preregistered standard-Raft RQ1 scenario families.

`rho`, `theta`, `beta`, and `a_star` are dimensionless inputs. Positions and
accelerations are derived from the declared signal speed and heartbeat scale,
so unit changes do not silently alter the intended regime.
"""
function canonical_scenario(
    family::ScenarioFamily;
    cluster_size::Integer=3,
    name::Union{Nothing,Symbol}=nothing,
    signal_speed::Real=1.0,
    heartbeat_interval::Real=0.2,
    theta::Tuple{<:Real,<:Real}=(5.0, 7.0),
    rho::Real=0.20,
    beta::Real=0.25,
    a_star::Real=0.02,
    window::ExperimentWindow=ExperimentWindow(),
    workload::Union{Nothing,WorkloadSpec}=nothing,
    network::Union{Nothing,NetworkProfile}=nothing,
    faults::Union{Nothing,AbstractVector{FaultSpec}}=nothing,
)
    n = Int(cluster_size)
    n in (3, 5, 7) || throw(ArgumentError("research clusters must contain 3, 5, or 7 nodes"))
    c = Float64(signal_speed)
    heartbeat = Float64(heartbeat_interval)
    rho_value = family == ColocatedControl ? 0.0 : Float64(rho)
    beta_value = family == AsymmetricRecedingInertial ? Float64(beta) : 0.0
    acceleration_scale = family == AcceleratingBaseline ? Float64(a_star) : 0.0
    isfinite(c) && c > 0.0 || throw(ArgumentError("signal speed must be finite and positive"))
    isfinite(heartbeat) && heartbeat > 0.0 ||
        throw(ArgumentError("heartbeat interval must be finite and positive"))
    isfinite(rho_value) && rho_value >= 0.0 ||
        throw(ArgumentError("rho must be finite and non-negative"))
    isfinite(beta_value) && -1.0 < beta_value < 1.0 ||
        throw(ArgumentError("beta must be finite and subluminal"))
    isfinite(acceleration_scale) && acceleration_scale >= 0.0 ||
        throw(ArgumentError("a_star must be finite and non-negative"))
    timeout_min = heartbeat * Float64(theta[1])
    timeout_max = heartbeat * Float64(theta[2])
    raft = RaftConfig(
        collect(1:n);
        election_timeout=(timeout_min, timeout_max),
        heartbeat_interval=heartbeat,
    )
    spacetime = MinkowskiSpacetime(c)
    spacing = rho_value * c * heartbeat
    proper_acceleration = acceleration_scale * c / heartbeat
    worldlines = _canonical_worldlines(
        family,
        spacetime,
        n,
        spacing,
        beta_value,
        proper_acceleration,
    )
    selected_network = if isnothing(network)
        family == PartitionDropStress ? NetworkProfile(
            loss_probability=0.12,
            duplicate_probability=0.10,
            reorder_probability=0.18,
            processing_delay=0.004,
            delay_jitter=0.010,
            reorder_delay=0.08,
            duplicate_delay=0.015,
            bandwidth_bytes_per_time=50_000.0,
        ) : NetworkProfile(
            processing_delay=0.001,
            delay_jitter=0.001,
            bandwidth_bytes_per_time=100_000.0,
        )
    else
        network
    end
    selected_workload = isnothing(workload) ? WorkloadSpec(client_node=1) : workload
    selected_faults = if isnothing(faults)
        family == PartitionDropStress ? _stress_faults(window, n) : FaultSpec[]
    else
        collect(faults)
    end
    config = ScenarioConfig(
        isnothing(name) ? _family_name(family) : name,
        family,
        spacetime,
        worldlines,
        raft,
        selected_network,
        selected_faults,
        selected_workload,
        window,
        spacing,
        beta_value,
        proper_acceleration,
    )
    validate_config(config)
    return config
end

function validate_config(config::ScenarioConfig)
    members = config.raft.members
    n = length(members)
    n in (3, 5, 7) || throw(ArgumentError("scenario membership must contain 3, 5, or 7 nodes"))
    members == Tuple(1:n) ||
        throw(ArgumentError("research scenario node ids must be contiguous from one"))
    length(config.worldlines) == n ||
        throw(ArgumentError("scenario must provide exactly one worldline per member"))
    config.workload.client_node in members ||
        throw(ArgumentError("workload client node is outside Raft membership"))
    isfinite(config.characteristic_distance) && config.characteristic_distance >= 0.0 ||
        throw(ArgumentError("characteristic distance must be finite and non-negative"))
    isfinite(config.beta_scale) && -1.0 < config.beta_scale < 1.0 ||
        throw(ArgumentError("scenario beta scale must be finite and subluminal"))
    isfinite(config.proper_acceleration_scale) && config.proper_acceleration_scale >= 0.0 ||
        throw(ArgumentError("proper acceleration scale must be finite and non-negative"))
    for (node, worldline) in enumerate(config.worldlines)
        worldline_event(worldline, config.window.start_coordinate)
        coordinate_velocity(worldline, config.window.start_coordinate)
        ProperTimeClock(
            config.spacetime,
            worldline;
            coordinate_origin=config.window.start_coordinate,
        )
        node in members || throw(ArgumentError("worldline has no corresponding member"))
    end
    for fault in config.faults
        config.window.start_coordinate <= fault.coordinate_time <= config.window.censor_coordinate ||
            throw(ArgumentError("fault lies outside the declared run window"))
        if fault.fault isa CrashNode || fault.fault isa RecoverNode
            fault.fault.node in members || throw(ArgumentError("fault names an unknown node"))
        elseif fault.fault isa SetLinkAvailability
            fault.fault.from in members && fault.fault.to in members ||
                throw(ArgumentError("link fault names an unknown node"))
        end
    end
    client_clock = ProperTimeClock(
        config.spacetime,
        config.worldlines[config.workload.client_node];
        coordinate_origin=config.window.start_coordinate,
    )
    measurement_start_local = local_time(client_clock, config.window.warmup_end_coordinate)
    if config.workload.operation_count > 0
        last_local = measurement_start_local + config.workload.start_offset_proper +
                     (config.workload.operation_count - 1) * config.workload.interval_proper
        last_coordinate = coordinate_time(client_clock, last_local)
        last_coordinate <= config.window.measurement_end_coordinate || throw(
            ArgumentError("workload invocations extend beyond the measurement window"),
        )
    end
    return true
end

function _quorum_roundtrip(config::ScenarioConfig, source::Int, emission_time::Float64)
    source_worldline = config.worldlines[source]
    outbound_event = worldline_event(source_worldline, emission_time)
    roundtrips = Float64[]
    for peer in config.raft.members
        peer == source && continue
        outbound = light_cone_intersection(
            config.spacetime,
            outbound_event,
            config.worldlines[peer];
            max_coordinate_time=config.window.censor_coordinate + 100config.raft.election_timeout_max,
        )
        inbound = light_cone_intersection(
            config.spacetime,
            outbound.reception,
            source_worldline;
            max_coordinate_time=config.window.censor_coordinate + 100config.raft.election_timeout_max,
        )
        push!(
            roundtrips,
            Float64(
                proper_time_between(
                    config.spacetime,
                    source_worldline,
                    emission_time,
                    inbound.reception.t,
                ),
            ),
        )
    end
    sort!(roundtrips)
    return roundtrips[quorum_size(config.raft) - 1]
end

function _source_receiver_rate_ratio(config::ScenarioConfig, source::Int, receiver::Int, start::Float64)
    source_clock = ProperTimeClock(
        config.spacetime,
        config.worldlines[source];
        coordinate_origin=config.window.start_coordinate,
    )
    source_local = local_time(source_clock, start)
    second_emission_time = coordinate_time(
        source_clock,
        source_local + config.raft.heartbeat_interval,
    )
    first = light_cone_intersection(
        config.spacetime,
        worldline_event(config.worldlines[source], start),
        config.worldlines[receiver];
        max_coordinate_time=config.window.censor_coordinate + 100config.raft.election_timeout_max,
    )
    second = light_cone_intersection(
        config.spacetime,
        worldline_event(config.worldlines[source], second_emission_time),
        config.worldlines[receiver];
        max_coordinate_time=config.window.censor_coordinate + 100config.raft.election_timeout_max,
    )
    receiver_elapsed = proper_time_between(
        config.spacetime,
        config.worldlines[receiver],
        first.reception.t,
        second.reception.t,
    )
    return Float64(receiver_elapsed) / config.raft.heartbeat_interval
end

function dimensionless_parameters(config::ScenarioConfig)
    validate_config(config)
    heartbeat = config.raft.heartbeat_interval
    start = config.window.warmup_end_coordinate
    quorum_rtt = _quorum_roundtrip(config, 1, start)
    rate_ratio = _source_receiver_rate_ratio(config, 1, 2, start)
    deadline_margin = quorum_rtt == 0.0 ? Inf : config.workload.deadline_proper / quorum_rtt
    offered_bytes = 128.0 / config.workload.interval_proper
    return DimensionlessParameters(
        config.characteristic_distance / (config.spacetime.c * heartbeat),
        config.raft.election_timeout_min / heartbeat,
        config.raft.election_timeout_max / heartbeat,
        quorum_rtt / config.raft.election_timeout_min,
        rate_ratio,
        config.proper_acceleration_scale * heartbeat / config.spacetime.c,
        offered_bytes / config.network.bandwidth_bytes_per_time,
        config.network.loss_probability,
        config.network.delay_jitter / heartbeat,
        deadline_margin,
    )
end

function _fault_description(fault::FaultEvent)
    fault isa CrashNode && return "crash:$(fault.node)"
    fault isa RecoverNode && return "recover:$(fault.node)"
    fault isa SetLinkAvailability &&
        return "link:$(fault.from):$(fault.to):$(fault.available)"
    return string(nameof(typeof(fault)))
end

function _canonical_config_text(config::ScenarioConfig)
    fields = String[
        "schema=research-rq1-v1",
        "name=$(config.name)",
        "family=$(Int(config.family))",
        "c=$(repr(config.spacetime.c))",
        "members=$(join(config.raft.members, ','))",
        "election_min=$(repr(config.raft.election_timeout_min))",
        "election_max=$(repr(config.raft.election_timeout_max))",
        "heartbeat=$(repr(config.raft.heartbeat_interval))",
        "batch=$(config.raft.append_batch_size)",
        "characteristic_distance=$(repr(config.characteristic_distance))",
        "beta=$(repr(config.beta_scale))",
        "acceleration=$(repr(config.proper_acceleration_scale))",
        "network=$(join((repr(config.network.loss_probability), repr(config.network.duplicate_probability), repr(config.network.reorder_probability), repr(config.network.processing_delay), repr(config.network.delay_jitter), repr(config.network.reorder_delay), repr(config.network.duplicate_delay), repr(config.network.bandwidth_bytes_per_time), string(config.network.framing_bytes)), ','))",
        "window=$(join((repr(config.window.start_coordinate), repr(config.window.warmup_end_coordinate), repr(config.window.measurement_end_coordinate), repr(config.window.censor_coordinate)), ','))",
        "workload=$(join((string(config.workload.client_node), string(config.workload.operation_count), repr(config.workload.start_offset_proper), repr(config.workload.interval_proper), repr(config.workload.deadline_proper), repr(config.workload.retry_interval_proper), string(config.workload.read_every)), ','))",
    ]
    for (node, worldline) in enumerate(config.worldlines)
        samples = String[]
        for time in (config.window.start_coordinate, config.window.warmup_end_coordinate,
                     config.window.measurement_end_coordinate)
            event = worldline_event(worldline, time)
            velocity = coordinate_velocity(worldline, time)
            push!(samples, join((repr(event.t), repr.(Tuple(event.x))..., repr.(Tuple(velocity))...), ':'))
        end
        push!(fields, "worldline:$node:$(nameof(typeof(worldline)))=$(join(samples, ';'))")
    end
    for fault in sort(config.faults; by=item -> (item.coordinate_time, _fault_description(item.fault)))
        push!(fields, "fault=$(repr(fault.coordinate_time)):$(_fault_description(fault.fault))")
    end
    return join(fields, '\n')
end

"""Stable FNV-1a fingerprint independent of Julia's randomized `hash`."""
function config_fingerprint(config::ScenarioConfig)
    value = UInt64(0xcbf29ce484222325)
    for byte in codeunits(_canonical_config_text(config))
        value = xor(value, UInt64(byte))
        value *= UInt64(0x00000100000001b3)
    end
    return lowercase(string(value; base=16, pad=16))
end

function rq1_scenarios(; cluster_size::Integer=3)
    return ScenarioConfig[
        canonical_scenario(ColocatedControl; cluster_size=cluster_size),
        canonical_scenario(SeparatedStaticBaseline; cluster_size=cluster_size),
        canonical_scenario(AsymmetricRecedingInertial; cluster_size=cluster_size),
        canonical_scenario(AcceleratingBaseline; cluster_size=cluster_size),
        canonical_scenario(PartitionDropStress; cluster_size=cluster_size),
    ]
end

"""
Build a non-stationary E3 scenario: inertial coast at signed `beta_initial`
followed by constant proper acceleration onset at `onset_coordinate` for
every member. Trajectories are closed-form in rapidity space and audited.
"""
function trajectory_change_scenario(;
    cluster_size::Integer=5,
    name::Union{Nothing,Symbol}=nothing,
    signal_speed::Real=1.0,
    heartbeat_interval::Real=0.2,
    rho::Real=0.20,
    beta_initial::Real=0.25,
    a_star::Real=0.05,
    onset_coordinate::Real=3.0,
    window::ExperimentWindow=ExperimentWindow(),
    workload::Union{Nothing,WorkloadSpec}=nothing,
    network::Union{Nothing,NetworkProfile}=nothing,
    faults::Union{Nothing,AbstractVector{FaultSpec}}=nothing,
)
    n = Int(cluster_size)
    n in (3, 5, 7) || throw(ArgumentError("research clusters must contain 3, 5, or 7 nodes"))
    c = Float64(signal_speed)
    heartbeat = Float64(heartbeat_interval)
    beta = Float64(beta_initial)
    onset = Float64(onset_coordinate)
    -1.0 < beta < 1.0 || throw(ArgumentError("beta_initial must be subluminal"))
    a_star >= 0.0 || throw(ArgumentError("a_star must be non-negative"))
    onset > window.start_coordinate ||
        throw(ArgumentError("onset must lie inside the run window"))
    alpha = Float64(a_star) * c / heartbeat

    spacetime = MinkowskiSpacetime(c)
    spacing = Float64(rho) * c * heartbeat
    midpoint = (n + 1) / 2
    phi_s = atanh(beta)
    gamma_s = cosh(phi_s)

    function make_worldline(node::Int)
        centered = node - midpoint
        x0 = centered * spacing
        v_s = beta * c
        x_onset = x0 + v_s * onset
        sh_s = sinh(phi_s)
        ch_s = cosh(phi_s)
        position(t) =
            (alpha == 0 || t <= onset) ? SVector{3,Float64}(x0 + v_s * t, 0.0, 0.0) :
            begin
                phi = asinh(sh_s + alpha * (t - onset) / c)
                SVector{3,Float64}(
                    x_onset + (c^2 / alpha) * (cosh(phi) - ch_s),
                    0.0,
                    0.0,
                )
            end
        velocity(t) =
            (alpha == 0 || t <= onset) ? SVector{3,Float64}(v_s, 0.0, 0.0) :
            SVector{3,Float64}(c * tanh(asinh(sh_s + alpha * (t - onset) / c)), 0.0, 0.0)
        # The worldline is C^1 but not C^2 at the onset kink; finite-difference
        # auditing therefore samples strictly inside the smooth segments.
        # Continuity of position and velocity at the onset is exact by
        # construction and asserted in the test suite.
        audit_points = sort(union(
            collect(range(window.start_coordinate + 1.0e-6; stop=onset - 1.0e-4, length=4)),
            collect(range(onset + 1.0e-4; stop=window.censor_coordinate, length=6)),
        ))
        return ParametricWorldline(
            spacetime,
            position,
            velocity;
            consistency=:audited,
            tmin=-Inf,
            tmax=Inf,
            validate_at=window.start_coordinate,
            audit_times=collect(audit_points),
        )
    end

    worldlines = AbstractWorldline{Float64}[make_worldline(node) for node in 1:n]
    timeout_min = heartbeat * 5.0
    timeout_max = heartbeat * 7.0
    raft = RaftConfig(
        collect(1:n);
        election_timeout=(timeout_min, timeout_max),
        heartbeat_interval=heartbeat,
    )
    selected_network = something(
        network,
        NetworkProfile(
            processing_delay=0.001,
            delay_jitter=0.001,
            bandwidth_bytes_per_time=100_000.0,
        ),
    )
    selected_workload = something(workload, WorkloadSpec(client_node=1))
    config = ScenarioConfig(
        something(name, :trajectory_change),
        AcceleratingBaseline,
        spacetime,
        worldlines,
        raft,
        selected_network,
        isnothing(faults) ? FaultSpec[] : collect(faults),
        selected_workload,
        window,
        spacing,
        beta,
        alpha * heartbeat / c,
    )
    validate_config(config)
    return config
end
