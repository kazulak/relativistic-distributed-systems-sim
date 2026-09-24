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

function _try_light_cone_intersection(
    spacetime::MinkowskiSpacetime{Float64},
    emission::SpacetimeEvent{Float64},
    receiver::AbstractWorldline{Float64},
    max_t::Float64,
)
    try
        res = light_cone_intersection(spacetime, emission, receiver; max_coordinate_time=max_t)
        return Float64(res.reception.t)
    catch e
        if e isa NoFutureLightConeIntersection || e isa LightConeSearchExhausted
            return Inf
        end
        rethrow(e)
    end
end

function _quorum_roundtrip(config::ScenarioConfig, source::Int, emission_time::Float64)
    source_worldline = config.worldlines[source]
    outbound_event = worldline_event(source_worldline, emission_time)
    roundtrips = Float64[]
    max_t = config.window.censor_coordinate + 100config.raft.election_timeout_max
    for peer in config.raft.members
        peer == source && continue
        t_out = _try_light_cone_intersection(
            config.spacetime,
            outbound_event,
            config.worldlines[peer],
            max_t,
        )
        if isfinite(t_out)
            out_event = worldline_event(config.worldlines[peer], t_out)
            t_in = _try_light_cone_intersection(
                config.spacetime,
                out_event,
                source_worldline,
                max_t,
            )
            if isfinite(t_in)
                push!(
                    roundtrips,
                    Float64(
                        proper_time_between(
                            config.spacetime,
                            source_worldline,
                            emission_time,
                            t_in,
                        ),
                    ),
                )
            else
                push!(roundtrips, Inf)
            end
        else
            push!(roundtrips, Inf)
        end
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
    max_t = config.window.censor_coordinate + 100config.raft.election_timeout_max
    t_first = _try_light_cone_intersection(
        config.spacetime,
        worldline_event(config.worldlines[source], start),
        config.worldlines[receiver],
        max_t,
    )
    t_second = _try_light_cone_intersection(
        config.spacetime,
        worldline_event(config.worldlines[source], second_emission_time),
        config.worldlines[receiver],
        max_t,
    )
    if !isfinite(t_first) || !isfinite(t_second)
        return Inf
    end
    receiver_elapsed = proper_time_between(
        config.spacetime,
        config.worldlines[receiver],
        t_first,
        t_second,
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
            # The clock rate kinks at the onset (acceleration jumps from 0);
            # declaring it lets quadrature split panels there.
            kinks=alpha == 0 ? () : (onset,),
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


# ---------------------------------------------------------------------------
# Causal quorum completion bound (Claim C3, docs/CAUSAL_QUORUM_BOUND.md)
# ---------------------------------------------------------------------------

"""Relative component of the C3 oracle tolerance (see `causal_bound_tolerance`)."""
const CAUSAL_BOUND_RTOL = 1.0e-9

"""Absolute floor of the C3 oracle tolerance, in client proper-time units."""
const CAUSAL_BOUND_ATOL_FLOOR = 4096eps(Float64)

"""
    causal_bound_tolerance(scale; rtol=CAUSAL_BOUND_RTOL, atol_floor=CAUSAL_BOUND_ATOL_FLOOR)

Scale-aware numerical tolerance used by the C3 oracle:
`max(atol_floor, rtol * abs(scale))`, where `scale` is the larger of the bound
and the measured latency for the audited operation.
"""
causal_bound_tolerance(
    scale::Real;
    rtol::Real=CAUSAL_BOUND_RTOL,
    atol_floor::Real=CAUSAL_BOUND_ATOL_FLOOR,
) = max(Float64(atol_floor), Float64(rtol) * abs(Float64(scale)))

@inline _oracle_position(worldline, t) = worldline_event(worldline, t).x

@inline function _oracle_distance(a, b)
    acc = 0.0
    for k in eachindex(a)
        acc += abs2(Float64(a[k]) - Float64(b[k]))
    end
    return sqrt(acc)
end

"""
Earliest coordinate time at which a null signal emitted at `(t_emit, x_emit)`
reaches `receiver`, computed *independently* of `light_cone_intersection`.

The residual `f(t) = c (t - t_emit) - |x_R(t) - x_emit|` is strictly increasing
for any timelike receiver (`f'(t) >= c - |v_R(t)| > 0`), so it has at most one
root on `[t_emit, Inf)`. The root is bracketed by doubling and then bisected to
adjacent floating-point numbers; the returned value is the lower bracket end
(`f < 0`), which does not exceed the true arrival time up to rounding in `f`.
Returns `Inf` if no arrival occurs by `max_t` (e.g. behind a Rindler horizon).
Only worldline kinematics (`worldline_event` positions) is shared with the engine.
"""
function _oracle_null_arrival(
    spacetime::MinkowskiSpacetime{Float64},
    t_emit::Float64,
    x_emit,
    receiver::AbstractWorldline{Float64},
    max_t::Float64,
)
    c = Float64(spacetime.c)
    residual(t) = c * (t - t_emit) - _oracle_distance(_oracle_position(receiver, t), x_emit)
    residual(t_emit) >= 0.0 && return t_emit
    lo = t_emit
    step = max(
        _oracle_distance(_oracle_position(receiver, t_emit), x_emit) / c,
        4eps(max(abs(t_emit), 1.0)),
    )
    hi = t_emit + step
    while residual(hi) < 0.0
        hi >= max_t && return Inf
        lo = hi
        step *= 2.0
        hi = min(t_emit + step, max(max_t, lo))
    end
    for _ in 1:2000
        mid = lo + (hi - lo) / 2
        (mid <= lo || mid >= hi) && break
        if residual(mid) < 0.0
            lo = mid
        else
            hi = mid
        end
    end
    return lo > max_t ? Inf : lo
end

function _causal_bound_horizon(config::ScenarioConfig, t0::Float64)
    slack = 100 * config.raft.election_timeout_max
    return max(config.window.censor_coordinate + slack, t0 + slack)
end

"""
    causal_quorum_chain(config, client_node, client_invoke_coord_time, leader_node;
                        include_client_legs=true)

Evaluate the Proposition 1 causal chain for one fixed leader `leader_node` and
return a NamedTuple

    (leader, t_invoke, t_leader_receive, t_commit, t_response, bound)

Coordinate times follow docs/CAUSAL_QUORUM_BOUND.md §3: `t_leader_receive` is
t1 (client->leader null arrival; `t_invoke` if the client node is the leader),
`t_commit` is the Q-th smallest acknowledgement time at the leader (the
leader's own log write counts at t1), `t_response` is the null arrival on the
client worldline of the reply emitted at `t_commit`, and `bound` is the client
proper time from `t_invoke` to `t_response`. Unreachable legs give `Inf`.

With `include_client_legs=false` segments 1 and 5 are dropped (t1 = t0 and
t_response = t_commit): the weaker replication-only bound that applies when the
client is attached to the leader without physical propagation.
Null legs are solved by the independent bisection solver `_oracle_null_arrival`,
not by the engine's `light_cone_intersection`.
"""
function causal_quorum_chain(
    config::ScenarioConfig,
    client_node::Integer,
    client_invoke_coord_time::Real,
    leader_node::Integer;
    include_client_legs::Bool=true,
)
    members = config.raft.members
    client_node in eachindex(config.worldlines) ||
        throw(ArgumentError("client_node $client_node has no worldline"))
    leader_node in members ||
        throw(ArgumentError("leader_node $leader_node is not a cluster member"))
    spacetime = config.spacetime
    t0 = Float64(client_invoke_coord_time)
    max_t = _causal_bound_horizon(config, t0)
    client_worldline = config.worldlines[client_node]
    leader_worldline = config.worldlines[leader_node]
    direct = !include_client_legs || leader_node == client_node
    unreachable = (
        leader=Int(leader_node),
        t_invoke=t0,
        t_leader_receive=Inf,
        t_commit=Inf,
        t_response=Inf,
        bound=Inf,
    )

    # Segment 1: client -> leader.
    t1 = direct ? t0 :
         _oracle_null_arrival(spacetime, t0, _oracle_position(client_worldline, t0), leader_worldline, max_t)
    isfinite(t1) || return unreachable

    # Segments 2-3: leader -> peer -> leader; segment 4: quorum at the leader.
    x_leader_t1 = _oracle_position(leader_worldline, t1)
    ack_times = Float64[t1]
    for peer in members
        peer == leader_node && continue
        peer_worldline = config.worldlines[peer]
        t2 = _oracle_null_arrival(spacetime, t1, x_leader_t1, peer_worldline, max_t)
        t3 = isfinite(t2) ?
             _oracle_null_arrival(spacetime, t2, _oracle_position(peer_worldline, t2), leader_worldline, max_t) :
             Inf
        push!(ack_times, t3)
    end
    sort!(ack_times)
    t_commit = ack_times[quorum_size(config.raft)]
    isfinite(t_commit) || return merge(unreachable, (t_leader_receive=t1,))

    # Segment 5: leader -> client.
    t_resp = direct ? t_commit :
             _oracle_null_arrival(
        spacetime,
        t_commit,
        _oracle_position(leader_worldline, t_commit),
        client_worldline,
        max_t,
    )
    isfinite(t_resp) ||
        return merge(unreachable, (t_leader_receive=t1, t_commit=t_commit))
    bound = t_resp == t0 ? 0.0 :
            Float64(proper_time_between(spacetime, client_worldline, t0, t_resp))
    return (
        leader=Int(leader_node),
        t_invoke=t0,
        t_leader_receive=t1,
        t_commit=t_commit,
        t_response=t_resp,
        bound=bound,
    )
end

"""
    causal_quorum_bound(config::ScenarioConfig, client_node::Integer, client_invoke_coord_time::Real;
                        leader_node::Union{Nothing,Integer}=nothing,
                        include_client_legs::Bool=true) -> Float64

Proposition 1 (Claim C3) lower bound on the client proper time elapsed between
invoking a strict-quorum write at coordinate time `client_invoke_coord_time`
and receiving its committed response, via the full five-segment causal chain
client -> leader -> peers -> leader (quorum) -> client (see `causal_quorum_chain`).

With `leader_node=nothing` (default) the bound is the minimum over every
cluster member as the accepting leader, which holds regardless of which node
Raft elects or how redirects route the request; pass `leader_node` to fix it.
Returns `Inf` if no leader can close the chain before the analysis horizon.
"""
function causal_quorum_bound(
    config::ScenarioConfig,
    client_node::Integer,
    client_invoke_coord_time::Real;
    leader_node::Union{Nothing,Integer}=nothing,
    include_client_legs::Bool=true,
)
    candidates = isnothing(leader_node) ? config.raft.members : (leader_node,)
    best = Inf
    for leader in candidates
        chain = causal_quorum_chain(
            config,
            client_node,
            client_invoke_coord_time,
            leader;
            include_client_legs=include_client_legs,
        )
        best = min(best, chain.bound)
    end
    return best
end

"""
    verify_causal_quorum_bounds(config::ScenarioConfig, operations::AbstractVector{OperationMetric};
                                leader_node=nothing, include_client_legs=true,
                                rtol=CAUSAL_BOUND_RTOL, atol_floor=CAUSAL_BOUND_ATOL_FLOOR)

Audit every committed non-read (write) operation against `causal_quorum_bound`
for `config.workload.client_node` (Claim C3). Returns a NamedTuple

    (ok::Bool, audited_writes::Int, min_margin::Float64, violations::Vector{String})

`margin = latency_proper - bound`. An operation violates when
`margin < -causal_bound_tolerance(max(bound, latency))`, when its bound is
infinite, or when it is committed without a recorded latency; `ok` is
`isempty(violations)`. Vacuity rule: when no finite margin was computed
(e.g. `audited_writes == 0`), `min_margin` is `NaN`, never `0.0`, and the run
is no evidence for C3.
"""
function verify_causal_quorum_bounds(
    config::ScenarioConfig,
    operations::AbstractVector{OperationMetric};
    leader_node::Union{Nothing,Integer}=nothing,
    include_client_legs::Bool=true,
    rtol::Real=CAUSAL_BOUND_RTOL,
    atol_floor::Real=CAUSAL_BOUND_ATOL_FLOOR,
)
    violations = String[]
    audited = 0
    min_margin = Inf
    client = config.workload.client_node
    for op in operations
        (op.outcome == :committed && op.operation_kind != :read) || continue
        audited += 1
        if isnothing(op.latency_proper)
            push!(violations, "operation $(op.request_id) is committed but has no recorded proper latency")
            continue
        end
        latency = Float64(op.latency_proper)
        bound = causal_quorum_bound(
            config,
            client,
            op.invoked_coordinate;
            leader_node=leader_node,
            include_client_legs=include_client_legs,
        )
        if !isfinite(bound)
            push!(
                violations,
                "operation $(op.request_id) committed at proper latency $latency but its causal bound is infinite",
            )
            continue
        end
        margin = latency - bound
        min_margin = min(min_margin, margin)
        tolerance = causal_bound_tolerance(max(bound, latency); rtol=rtol, atol_floor=atol_floor)
        if margin < -tolerance
            push!(
                violations,
                "operation $(op.request_id) committed at proper latency $latency below causal quorum bound $bound (margin $margin, tolerance $tolerance)",
            )
        end
    end
    return (
        ok=isempty(violations),
        audited_writes=audited,
        min_margin=isfinite(min_margin) ? min_margin : NaN,
        violations=violations,
    )
end


