"""
E3 source/receiver rate-ratio (D_sr) regimes.

Convention (matches `_source_receiver_rate_ratio`): D_sr is the receiver-proper
inter-arrival divided by the source-proper emission interval. Receding pairs
have D_sr > 1 (redshift), approaching pairs D_sr < 1. For a pair with signed
relative velocity β along the line of sight, D_sr = sqrt((1 + β) / (1 - β)).

Design (see docs/PRE_REGISTRATION_E3_ADDENDUM_r4 draft in the E3 report):

- Homothetic formation: node i sits at `w_i * F(t)`, where `w_i` is a fixed
  velocity vector and `F` a scalar profile with piecewise-constant second
  derivative (C¹ worldlines, closed form). Whenever |F'| = 1 the formation is
  an exact Milne (common-event) congruence, so every pair has the constant
  Doppler factor exp(±η_ij), with η_ij the pairwise relative rapidity.
- For n = 5 the velocity vectors form a triangular bipyramid in velocity space
  whose equatorial–equatorial and apex–equatorial relative rapidities are all
  η = atanh(|β|): 9 of 10 unordered pairs sit exactly on target; the apex–apex
  pair has 2·χ_apex (≈1.52 for β = 0.25, ≈2.42 for β = 0.5). No 5-point
  equilateral configuration exists in hyperbolic 3-space, so exact equality
  for all pairs is impossible. For n = 3 an equilateral triangle is exact.
- `rho` is the nearest-neighbour separation of the compact static formation
  (in units of c·heartbeat). Moving regimes drift away from it: light-delay
  changes by ≈ β_nn heartbeats per heartbeat, which is unavoidable for any
  sustained D_sr ≠ 1 in flat spacetime.
- Receding (β > 0): static compact formation during warm-up, a half-heartbeat
  ramp ending exactly at measurement start, then Milne coasting.
- Approaching (β < 0): static compact formation for the leader election, an
  outward excursion during warm-up, and inbound Milne coasting over the whole
  measurement window, braking to the compact formation at measurement end.
  Pairs therefore never cross.
- Onset (`trajectory = :onset`): at `onset_fraction` of the measurement window
  F' increases by `onset_delta_slope` (default +0.5) over
  `onset_ramp_fraction` of the window (outward acceleration). Stationary
  cells start expanding (reference geometry β = 0.25), approaching cells
  halve their closing speed, receding cells speed up by 50 %. The trajectory
  change therefore happens strictly inside the measurement window.
"""

struct _ScalarProfile
    times::Vector{Float64}
    values::Vector{Float64}
    slopes::Vector{Float64}
    accels::Vector{Float64}
end

_ScalarProfile(start::Float64, value::Float64) =
    _ScalarProfile([start], [value], [0.0], [0.0])

function _profile_segment(profile::_ScalarProfile, t::Float64)
    index = searchsortedlast(profile.times, t)
    return max(index, 1)
end

function _profile_value(profile::_ScalarProfile, t::Float64)
    k = _profile_segment(profile, t)
    dt = t - profile.times[k]
    k == 1 && dt < 0.0 && return profile.values[1]
    return profile.values[k] + profile.slopes[k] * dt + 0.5 * profile.accels[k] * dt^2
end

function _profile_slope(profile::_ScalarProfile, t::Float64)
    k = _profile_segment(profile, t)
    dt = t - profile.times[k]
    k == 1 && dt < 0.0 && return profile.slopes[1]
    return profile.slopes[k] + profile.accels[k] * dt
end

"""Append a segment starting at `t` with constant second derivative `accel`."""
function _profile_push!(profile::_ScalarProfile, t::Float64, accel::Float64)
    t > profile.times[end] || throw(ArgumentError("profile segments must be increasing in time"))
    push!(profile.values, _profile_value(profile, t))
    slope = _profile_slope(profile, t)
    # Snap round-off so ramps land exactly on their intended integer slopes;
    # a 1e-16 residual velocity would otherwise fail the relative audit.
    nearest = round(slope)
    abs(slope - nearest) < 1.0e-9 && (slope = nearest)
    push!(profile.slopes, slope)
    push!(profile.times, t)
    push!(profile.accels, accel)
    return profile
end

# ---------------------------------------------------------------------------
# Homothetic worldline: x(t) = w · F(t), v(t) = w · F'(t) with F' piecewise
# linear. Proper time uses a fixed Gauss–Legendre rule per segment with
# precomputed breakpoint totals (no adaptive quadrature) and a bisection
# inverse accurate to one ulp; both are far cheaper and tighter than the
# generic ParametricWorldline path.
# ---------------------------------------------------------------------------

const _RDS = parentmodule(@__MODULE__)

struct HomotheticWorldline <: AbstractWorldline{Float64}
    direction::SVector{3,Float64}
    profile::_ScalarProfile
    c::Float64
    speed_scale::Float64          # S = |w| / c
    anchor::Float64               # proper time is zero at this coordinate
    cumulative::Vector{Float64}   # proper time at profile.times[k] (k ≥ 2)
end

function HomotheticWorldline(spacetime::MinkowskiSpacetime{Float64}, direction, profile::_ScalarProfile)
    w = SVector{3,Float64}(direction)
    S = sqrt(sum(abs2, w)) / spacetime.c
    S > 0.0 || throw(ArgumentError("homothetic direction must be nonzero"))
    anchor = length(profile.times) >= 2 ? profile.times[2] : 0.0
    worldline = HomotheticWorldline(w, profile, spacetime.c, S, anchor, zeros(length(profile.times)))
    for k in 3:length(profile.times)
        worldline.cumulative[k] = worldline.cumulative[k - 1] +
            _segment_proper_time(worldline, k - 1, profile.times[k - 1], profile.times[k])
    end
    maximum(abs(s) for s in profile.slopes) * S < 1.0 ||
        throw(ArgumentError("homothetic worldline would exceed the signal speed"))
    return worldline
end

const _GL8_NODES = (0.1834346424956498, 0.5255324099163290, 0.7966664774136267, 0.9602898564975363)
const _GL8_WEIGHTS = (0.3626837833783620, 0.3137066458778873, 0.2223810344533745, 0.1012285362903763)

"""
Proper time on segment k between coordinates t1 ≤ t2 (both inside the segment).
The integrand sqrt(1 − u²), u = S·F'(t) linear in t with |u| ≤ 0.9, is analytic;
8-point Gauss–Legendre on panels with |Δu| ≤ 0.05 is accurate to ~1e-15
relative (the closed form above suffers cancellation for short intervals).
"""
function _segment_proper_time(w::HomotheticWorldline, k::Int, t1::Float64, t2::Float64)
    p = w.profile
    S = w.speed_scale
    a = p.accels[k]
    s0 = p.slopes[k]
    tk = p.times[k]
    a == 0.0 && return sqrt((1 - S * s0) * (1 + S * s0)) * (t2 - t1)
    panels = max(1, ceil(Int, abs(S * a * (t2 - t1)) / 0.05))
    width = (t2 - t1) / panels
    total = 0.0
    for panel in 0:(panels - 1)
        left = t1 + panel * width
        mid = left + width / 2
        half = width / 2
        acc = 0.0
        for (x, weight) in zip(_GL8_NODES, _GL8_WEIGHTS)
            for sgn in (-1.0, 1.0)
                u = S * (s0 + a * (mid + sgn * half * x - tk))
                acc += weight * sqrt((1 - u) * (1 + u))
            end
        end
        total += acc * half
    end
    return total
end

function _homothetic_tau(w::HomotheticWorldline, t::Float64)
    p = w.profile
    length(p.times) < 2 && return t - w.anchor
    t <= p.times[2] && return t - w.anchor   # initial static segment, rate 1
    k = searchsortedlast(p.times, t)
    return w.cumulative[k] + _segment_proper_time(w, k, p.times[k], t)
end

_RDS.coordinate_domain(::HomotheticWorldline) = (-Inf, Inf)
# Clock-rate kinks sit at every profile breakpoint (F'' jumps there).
_RDS.worldline_kinks(w::HomotheticWorldline) = w.profile.times[2:end]
_RDS.reference_coordinate_time(::HomotheticWorldline) = 0.0
_RDS.position_at(w::HomotheticWorldline, t::Real) = w.direction * _profile_value(w.profile, Float64(t))
_RDS.coordinate_velocity(w::HomotheticWorldline, t::Real) = w.direction * _profile_slope(w.profile, Float64(t))

function _RDS.proper_time_between(
    spacetime::MinkowskiSpacetime{Float64},
    worldline::HomotheticWorldline,
    first_time::Real,
    second_time::Real;
    kwargs...,
)
    spacetime.c == worldline.c || throw(ArgumentError("worldline and spacetime must use exactly the same c"))
    t1, t2 = Float64(first_time), Float64(second_time)
    (isfinite(t1) && isfinite(t2)) || throw(DomainError((t1, t2), "coordinate times must be finite"))
    t1 == t2 && return 0.0
    return _homothetic_tau(worldline, t2) - _homothetic_tau(worldline, t1)
end

function _RDS.coordinate_time_after_proper_time(
    spacetime::MinkowskiSpacetime{Float64},
    worldline::HomotheticWorldline,
    initial_time::Real,
    duration::Union{Real,_RDS.ProperTime};
    kwargs...,
)
    spacetime.c == worldline.c || throw(ArgumentError("worldline and spacetime must use exactly the same c"))
    start = Float64(initial_time)
    d = duration isa Real ? Float64(duration) : Float64(duration.value)
    isfinite(d) && d >= 0.0 || throw(ArgumentError("proper-time duration must be finite and nonnegative"))
    d == 0.0 && return start
    tau_start = _homothetic_tau(worldline, start)
    peak = maximum(abs(s) for s in worldline.profile.slopes) * worldline.speed_scale
    min_rate = sqrt((1 - peak) * (1 + peak))
    lo, hi = start, start + d / min_rate + 1.0e-12 * max(1.0, abs(start))
    while _homothetic_tau(worldline, hi) - tau_start < d
        hi += d
    end
    for _ in 1:200
        mid = lo + (hi - lo) / 2
        (mid == lo || mid == hi) && break
        _homothetic_tau(worldline, mid) - tau_start < d ? (lo = mid) : (hi = mid)
    end
    return hi
end

"""Velocity-space geometry: returns lab velocity vectors (units of c)."""
function _dsr_velocity_geometry(n::Int, eta::Float64)
    eta > 0.0 || throw(ArgumentError("geometry rapidity must be positive"))
    # Equatorial nodes on a circle at 120°: cosh η = 1 + (3/2) sinh²χ_e.
    sinh2_e = (cosh(eta) - 1.0) / 1.5
    cosh_e = sqrt(1.0 + sinh2_e)
    speed_e = sqrt(sinh2_e) / cosh_e
    vectors = SVector{3,Float64}[]
    for k in 0:2
        angle = 2pi * k / 3
        push!(vectors, SVector(speed_e * cos(angle), speed_e * sin(angle), 0.0))
    end
    n == 3 && return vectors
    n == 5 || throw(ArgumentError("dsr_regime_scenario supports 3 or 5 nodes (no equilateral 7-node layout)"))
    # Apex nodes perpendicular to the equator: cosh η = cosh χ_a cosh χ_e.
    cosh_a = cosh(eta) / cosh_e
    speed_a = sqrt(1.0 - 1.0 / cosh_a^2)
    push!(vectors, SVector(0.0, 0.0, speed_a))
    push!(vectors, SVector(0.0, 0.0, -speed_a))
    return vectors
end

function _nearest_separation(vectors::Vector{SVector{3,Float64}})
    best = Inf
    for i in eachindex(vectors), j in eachindex(vectors)
        i < j || continue
        best = min(best, sqrt(sum(abs2, vectors[i] - vectors[j])))
    end
    return best
end

"""Reference rapidity used for the formation shape when β = 0."""
const DSR_REFERENCE_BETA = 0.25

"""
    dsr_regime_scenario(; beta, rho, trajectory=:inertial, cluster_size=5, ...)

Build an E3 D_sr-regime scenario (see the file docstring for the design).
`beta` is the signed pairwise relative velocity target: β > 0 receding
(D_sr = sqrt((1+β)/(1-β)) > 1), β < 0 approaching, β = 0 stationary.
"""
function dsr_regime_scenario(;
    beta::Real=0.0,
    rho::Real=0.2,
    trajectory::Symbol=:inertial,
    cluster_size::Integer=5,
    name::Union{Nothing,Symbol}=nothing,
    signal_speed::Real=1.0,
    heartbeat_interval::Real=0.2,
    theta::Tuple{<:Real,<:Real}=(5.0, 7.0),
    window::ExperimentWindow=ExperimentWindow(
        warmup_duration=5.0,
        measurement_duration=4.0,
        censor_duration=2.0,
    ),
    ramp_heartbeats::Real=0.5,
    election_settle::Real=1.6,
    excursion_speed_cap::Real=0.85,
    excursion_max_slope::Real=1.5,
    onset_fraction::Real=0.5,
    onset_ramp_fraction::Real=0.25,
    onset_delta_slope::Real=0.5,
    workload::Union{Nothing,WorkloadSpec}=nothing,
    network::Union{Nothing,NetworkProfile}=nothing,
    faults::Union{Nothing,AbstractVector{FaultSpec}}=nothing,
)
    n = Int(cluster_size)
    c = Float64(signal_speed)
    h = Float64(heartbeat_interval)
    b = Float64(beta)
    rho_value = Float64(rho)
    isfinite(c) && c > 0.0 || throw(ArgumentError("signal speed must be finite and positive"))
    isfinite(h) && h > 0.0 || throw(ArgumentError("heartbeat interval must be finite and positive"))
    isfinite(b) && -1.0 < b < 1.0 || throw(ArgumentError("beta must be subluminal"))
    isfinite(rho_value) && rho_value > 0.0 || throw(ArgumentError("rho must be positive"))
    trajectory in (:inertial, :onset) ||
        throw(ArgumentError("trajectory must be :inertial or :onset"))
    0.0 < onset_fraction < 1.0 || throw(ArgumentError("onset_fraction must lie in (0, 1)"))
    0.0 < onset_ramp_fraction <= 1.0 - onset_fraction ||
        throw(ArgumentError("onset ramp must end inside the measurement window"))

    eta = atanh(b == 0.0 ? DSR_REFERENCE_BETA : abs(b))
    unit_vectors = _dsr_velocity_geometry(n, eta)
    velocities = [c * v for v in unit_vectors]
    d_nn = _nearest_separation(unit_vectors) * c
    max_speed = maximum(v -> sqrt(sum(abs2, v)), velocities)
    F0 = rho_value * c * h / d_nn

    t_ms = window.warmup_end_coordinate
    t_me = window.measurement_end_coordinate
    t_meas = t_me - t_ms
    ramp = Float64(ramp_heartbeats) * h
    onset_time = t_ms + Float64(onset_fraction) * t_meas
    onset_ramp = Float64(onset_ramp_fraction) * t_meas
    onset_delta = Float64(onset_delta_slope)
    0.0 < onset_delta <= 1.0 || throw(ArgumentError("onset_delta_slope must lie in (0, 1]"))
    profile = _ScalarProfile(window.start_coordinate - 1.0e3, F0)
    peak_slope = 1.0
    if b > 0.0
        _profile_push!(profile, t_ms - ramp, 1.0 / ramp)
        _profile_push!(profile, t_ms, 0.0)
        if trajectory == :onset
            _profile_push!(profile, onset_time, onset_delta / onset_ramp)
            _profile_push!(profile, onset_time + onset_ramp, 0.0)
            peak_slope = 1.0 + onset_delta
        end
    elseif b < 0.0
        accel = 1.0 / ramp
        K = min(Float64(excursion_max_slope), Float64(excursion_speed_cap) * c / max_speed)
        K > 1.0 || throw(ArgumentError("excursion speed cap leaves no room for the outward leg"))
        F_target = F0 + ramp / 2 + t_meas
        distance = F_target - F0
        coast = (distance - (2K^2 - 1) / (2accel)) / K
        coast >= 0.0 || throw(ArgumentError("excursion ramps overshoot the required distance"))
        t0 = t_ms - (2K + 1) / accel - coast
        t0 >= window.start_coordinate + Float64(election_settle) || throw(ArgumentError(
            "warm-up too short for the approaching excursion (needs start at $t0)",
        ))
        _profile_push!(profile, t0, accel)
        _profile_push!(profile, t0 + K / accel, 0.0)
        _profile_push!(profile, t0 + K / accel + coast, -accel)
        _profile_push!(profile, t_ms, 0.0)
        if trajectory == :onset
            _profile_push!(profile, onset_time, onset_delta / onset_ramp)
            _profile_push!(profile, onset_time + onset_ramp, 0.0)
        end
        # Brake to rest at measurement end so the formation never collapses.
        closing = -_profile_slope(profile, t_me)
        _profile_push!(profile, t_me, closing / ramp)
        _profile_push!(profile, t_me + ramp, 0.0)
        peak_slope = K
    else
        if trajectory == :onset
            _profile_push!(profile, onset_time, onset_delta / onset_ramp)
            _profile_push!(profile, onset_time + onset_ramp, 0.0)
        end
    end
    peak_slope * max_speed < c ||
        throw(ArgumentError("formation profile would exceed the signal speed"))
    minimum_F = minimum(
        _profile_value(profile, t) for
        t in range(window.start_coordinate, window.censor_coordinate; length=2001)
    )
    minimum_F > 0.0 || throw(ArgumentError("formation collapses inside the run window"))

    spacetime = MinkowskiSpacetime(c)
    breakpoints = profile.times[2:end]
    samples = collect(range(window.start_coordinate + 1.0e-3, window.censor_coordinate; length=13))
    audit_points = sort!(filter(
        t -> all(abs(t - bp) > 1.0e-3 for bp in breakpoints),
        samples,
    ))
    worldlines = AbstractWorldline{Float64}[]
    for velocity in velocities
        worldline = HomotheticWorldline(spacetime, velocity, profile)
        # Same position/velocity consistency audit ParametricWorldline applies.
        _RDS.audit_worldline(spacetime, worldline, audit_points)
        push!(worldlines, worldline)
    end

    raft = RaftConfig(
        collect(1:n);
        election_timeout=(h * Float64(theta[1]), h * Float64(theta[2])),
        heartbeat_interval=h,
    )
    selected_network = something(
        network,
        NetworkProfile(processing_delay=0.001, delay_jitter=0.001, bandwidth_bytes_per_time=100_000.0),
    )
    family = trajectory == :onset ? AcceleratingBaseline :
             b == 0.0 ? SeparatedStaticBaseline : AsymmetricRecedingInertial
    acceleration_scale = trajectory == :onset ? max_speed / onset_ramp * h / c : 0.0
    default_name = Symbol("e3_dsr_b$(b)_r$(rho_value)_$(trajectory)")
    config = ScenarioConfig(
        something(name, default_name),
        family,
        spacetime,
        worldlines,
        raft,
        selected_network,
        isnothing(faults) ? FaultSpec[] : collect(faults),
        something(workload, WorkloadSpec(client_node=1)),
        window,
        rho_value * c * h,
        b,
        acceleration_scale,
    )
    validate_config(config)
    return config
end

"""
    dsr_pairwise_ratios(config, coordinate_time)

Matrix `R[s, r]` of source→receiver rate ratios (receiver-proper inter-arrival
over source-proper emission interval of one heartbeat) for emissions at
`coordinate_time`; the diagonal is `NaN`.
"""
function dsr_pairwise_ratios(config::ScenarioConfig, coordinate_time::Real)
    n = length(config.worldlines)
    ratios = fill(NaN, n, n)
    for source in 1:n, receiver in 1:n
        source == receiver && continue
        ratios[source, receiver] =
            _source_receiver_rate_ratio(config, source, receiver, Float64(coordinate_time))
    end
    return ratios
end

"""Minimum pairwise light-delay separation in units of c·heartbeat at a coordinate time."""
function nearest_neighbour_rho(config::ScenarioConfig, coordinate_time::Real)
    positions = [worldline_event(w, Float64(coordinate_time)).x for w in config.worldlines]
    best = Inf
    for i in eachindex(positions), j in eachindex(positions)
        i < j || continue
        best = min(best, sqrt(sum(abs2, positions[i] - positions[j])))
    end
    return best / (config.spacetime.c * config.raft.heartbeat_interval)
end

"""
    CrashLeader(downtime)

Exogenous E3 fault: at its scheduled coordinate time, crash whichever node is
the sole active leader (no-op when there is none) and recover it `downtime`
coordinate-time units later. The rule and the time are identical across
arms; only the identity of the crashed node is endogenous (as it is, in
effect, for any fixed-node schedule, since which node leads is itself
arm-dependent). `node` is only the nominal scheduling target.
"""
struct CrashLeader <: FaultEvent
    node::Int
    downtime::Float64

    function CrashLeader(downtime::Real; node::Integer=1)
        d = Float64(downtime)
        isfinite(d) && d > 0.0 || throw(ArgumentError("CrashLeader downtime must be positive"))
        node > 0 || throw(ArgumentError("nominal target must be positive"))
        return new(Int(node), d)
    end
end
