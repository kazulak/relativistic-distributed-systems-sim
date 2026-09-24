"""No intersection exists by a finite, declared receiver/search horizon."""
struct NoFutureLightConeIntersection <: Exception
    message::String
end

Base.showerror(io::IO, error::NoFutureLightConeIntersection) = print(io, error.message)

"""An unbounded numerical search ended without proving absence of an intersection."""
struct LightConeSearchExhausted <: Exception
    message::String
end

Base.showerror(io::IO, error::LightConeSearchExhausted) = print(io, error.message)

"""A bracketed light-cone solve failed its declared residual contract."""
struct LightConeConvergenceError <: Exception
    message::String
end

Base.showerror(io::IO, error::LightConeConvergenceError) = print(io, error.message)

"""Validated earliest direct null-signal intersection with a receiver worldline."""
struct LightConeIntersection{T<:AbstractFloat}
    emission::SpacetimeEvent{T}
    reception::SpacetimeEvent{T}
    iterations::Int
    method::Symbol
    scaled_residual::T
    equation_residual::T
end

"""Compatibility result for the original scalar light-time API."""
struct LightTimeResult{T<:AbstractFloat}
    tB::T
    iterations::Int
    converged_newton::Bool
end

function _validate_light_solver_options(
    ::Type{T},
    rtol::Real,
    atol::Real,
    conditioning_tolerance::Real,
    max_iterations::Integer,
    max_expansions::Integer,
) where {T<:AbstractFloat}
    relative_tolerance = _validate_real_tolerance(
        "light-cone rtol",
        rtol,
        T;
        allow_zero=false,
        less_than_one=true,
    )
    absolute_tolerance = _validate_real_tolerance(
        "light-cone atol",
        atol,
        T;
        allow_zero=true,
    )
    condition_limit = _validate_real_tolerance(
        "light-cone conditioning_tolerance",
        conditioning_tolerance,
        T;
        allow_zero=false,
        less_than_one=true,
    )
    max_iterations >= 1 || throw(ArgumentError("light-cone max_iterations must be positive"))
    max_expansions >= 1 || throw(ArgumentError("light-cone max_expansions must be positive"))
    return relative_tolerance, absolute_tolerance, condition_limit
end

function _representable_reception_time(emission_time::T, requested_delay::T) where {T<:AbstractFloat}
    isfinite(requested_delay) && requested_delay >= zero(T) ||
        throw(NumericalConditioningError("light-time delay must be finite and nonnegative"))
    requested_delay == zero(T) && return emission_time, zero(T)
    reception_time = emission_time + requested_delay
    isfinite(reception_time) ||
        throw(NumericalConditioningError("reception coordinate time overflowed"))
    reception_time > emission_time || throw(
        NumericalConditioningError(
            "positive light-time delay is below coordinate-time resolution at the emission epoch",
        ),
    )
    actual_delay = reception_time - emission_time
    actual_delay > zero(T) ||
        throw(NumericalConditioningError("reception delay subtraction lost its positive increment"))
    return reception_time, actual_delay
end

"""
    _light_equation_floor(spacetime, emission, reception_time, reception_position)

Absolute resolution floor for the unsquared light equation
`E = |‖x_r - x_e‖ - c (t_r - t_e)|`:

    floor = 2 ε (c max(|t_e|, |t_r|) + max(‖x_e‖, ‖x_r‖)),      ε = eps(T).

Rationale: `t_r` is a floating-point coordinate, so the true root can only be
represented to within `ulp(t_r)/2 ≤ ε|t_r|/2`, which alone moves `E` by up to
`(c + |v|) ε|t_r|/2 ≤ c ε|t_r|`. Forming `t_r - t_e` and `x_r - x_e` and
evaluating `x_r` each round at the magnitude of the *absolute* coordinates, not
of the (possibly much smaller) separation, adding O(ε) times `c|t|` and `‖x‖`.
The factor 2 covers these terms. The floor is therefore a small multiple of the
ULP of the compared coordinates, is independent of `rtol`, and is negligible
against `rtol * scale` whenever the separation is not tiny relative to the
coordinate epoch.
"""
function _light_equation_floor(
    spacetime::MinkowskiSpacetime{T},
    emission::SpacetimeEvent{T},
    reception_time::T,
    reception_position::SVector{3,T},
) where {T<:AbstractFloat}
    unit = T(2) * eps(T)
    floor = (unit * spacetime.c) * max(abs(emission.t), abs(reception_time)) +
            unit * max(_spatial_norm(emission.x), _spatial_norm(reception_position))
    isfinite(floor) ||
        throw(NumericalConditioningError("light-cone resolution floor is not representable"))
    return floor
end

"""
Contract tolerance for the unsquared light equation:
`atol + rtol * scale + floor`, with `scale = max(‖Δx‖, cΔt)` and `floor`
from `_light_equation_floor`. Every returned intersection must meet it
(`_validated_intersection`).
"""
@inline _light_equation_tolerance(rtol::T, atol::T, scale::T, floor::T) where {T<:AbstractFloat} =
    atol + rtol * scale + floor

# Solver stopping test: the strict `max(atol, rtol * scale)` target, without the
# floor, so iteration continues while the root is still resolvable. The
# floor is only admitted once the bracket has collapsed to adjacent
# representable reception times (see `_light_state_within_contract`).
@inline _light_state_converged(state, rtol, atol) =
    abs(state.value) <= atol || abs(state.value) <= rtol * state.scale

@inline _light_state_within_contract(state, rtol, atol) =
    abs(state.value) <= _light_equation_tolerance(rtol, atol, state.scale, state.floor)

function _light_state_for_delay(
    spacetime::MinkowskiSpacetime{T},
    emission::SpacetimeEvent{T},
    receiver::AbstractWorldline{T},
    requested_delay::T,
) where {T<:AbstractFloat}
    reception_time, _ = _representable_reception_time(emission.t, requested_delay)
    return _light_state_at_time(spacetime, emission, receiver, reception_time)
end

# Light-equation state at a representable reception coordinate time. The root
# search brackets reception times directly, because distinct delays can map to
# the same representable reception time at a large emission epoch.
function _light_state_at_time(
    spacetime::MinkowskiSpacetime{T},
    emission::SpacetimeEvent{T},
    receiver::AbstractWorldline{T},
    reception_time::T,
) where {T<:AbstractFloat}
    isfinite(reception_time) ||
        throw(NumericalConditioningError("reception coordinate time overflowed"))
    reception_time > emission.t || throw(
        NumericalConditioningError("reception coordinate time is not after the emission epoch"),
    )
    actual_delay = reception_time - emission.t
    actual_delay > zero(T) ||
        throw(NumericalConditioningError("reception delay subtraction lost its positive increment"))
    receiver_position = position_at(receiver, reception_time)
    receiver_velocity = coordinate_velocity(receiver, reception_time)
    separation = receiver_position - emission.x
    distance = _spatial_norm(separation)
    isfinite(distance) || throw(NumericalConditioningError("receiver separation is not representable"))
    light_distance = spacetime.c * actual_delay
    isfinite(light_distance) || throw(NumericalConditioningError("light-travel distance overflowed"))
    value = distance - light_distance
    derivative = if distance == zero(T)
        -spacetime.c
    else
        radial_velocity = _spatial_dot(separation / distance, receiver_velocity)
        radial_velocity - spacetime.c
    end
    derivative < zero(T) || throw(
        InvalidWorldlineError(
            "light-time equation is not strictly decreasing; check position/velocity consistency",
        ),
    )
    scale = max(distance, light_distance)
    equation_residual = scale == zero(T) ? zero(T) : abs(value) / scale
    floor = _light_equation_floor(spacetime, emission, reception_time, receiver_position)
    return (
        value=value,
        derivative=derivative,
        distance=distance,
        light_distance=light_distance,
        scale=scale,
        floor=floor,
        equation_residual=equation_residual,
        reception_time=reception_time,
        actual_delay=actual_delay,
    )
end

function _validated_intersection(
    spacetime::MinkowskiSpacetime{T},
    emission::SpacetimeEvent{T},
    receiver::AbstractWorldline{T},
    reception_time::T,
    initial_distance::T,
    iterations::Int,
    method::Symbol,
    rtol::T,
    atol::T,
) where {T<:AbstractFloat}
    reception = worldline_event(receiver, reception_time)
    if _events_exactly_coincident(emission, reception)
        return LightConeIntersection(
            emission,
            reception,
            iterations,
            method,
            zero(T),
            zero(T),
        )
    end
    reception.t > emission.t ||
        throw(NumericalConditioningError("noncoincident reception is not representably in the future"))
    actual_delay = reception.t - emission.t
    separation = reception.x - emission.x
    distance = _spatial_norm(separation)
    light_distance = spacetime.c * actual_delay
    isfinite(distance) && isfinite(light_distance) ||
        throw(NumericalConditioningError("light-cone validation scale is not representable"))
    unsquared_error = abs(distance - light_distance)
    equation_scale = max(distance, light_distance, initial_distance * eps(T))
    equation_scale > zero(T) ||
        throw(NumericalConditioningError("light-cone equation scale collapsed to zero"))
    equation_residual = unsquared_error / equation_scale
    floor = _light_equation_floor(spacetime, emission, reception.t, reception.x)
    equation_tolerance = _light_equation_tolerance(rtol, atol, equation_scale, floor)
    interval_residual = scaled_interval_residual(spacetime, emission, reception)
    # R_null <= 2E / max(‖Δx‖, cΔt) near the null cone, so the interval check
    # inherits the unsquared contract with a factor-4 allowance.
    interval_tolerance = max(T(4) * rtol, T(4) * (atol + floor) / equation_scale)
    unsquared_error <= equation_tolerance || throw(
        LightConeConvergenceError(
            "unsquared light equation misses tolerance: error=$unsquared_error tolerance=$equation_tolerance",
        ),
    )
    interval_residual <= interval_tolerance || throw(
        LightConeConvergenceError(
            "scaled null interval misses tolerance: residual=$interval_residual tolerance=$interval_tolerance",
        ),
    )
    return LightConeIntersection(
        emission,
        reception,
        iterations,
        method,
        interval_residual,
        equation_residual,
    )
end

function _inertial_delay_and_condition(
    spacetime::MinkowskiSpacetime{T},
    separation::SVector{3,T},
    velocity::SVector{3,T},
) where {T<:AbstractFloat}
    return setprecision(BigFloat, _wide_precision(T)) do
        rx, ry, rz = BigFloat.(Tuple(separation))
        vx, vy, vz = BigFloat.(Tuple(velocity))
        c = BigFloat(spacetime.c)
        range2 = rx^2 + ry^2 + rz^2
        speed2 = vx^2 + vy^2 + vz^2
        coefficient = c^2 - speed2
        coefficient > 0 || throw(InvalidWorldlineError("inertial receiver is not timelike"))
        range2 > 0 || return BigFloat(0), BigFloat(0)
        radial_product = rx * vx + ry * vy + rz * vz
        discriminant = sqrt(radial_product^2 + coefficient * range2)
        delay = if radial_product >= 0
            (radial_product + discriminant) / coefficient
        else
            range2 / (discriminant - radial_product)
        end
        speed = sqrt(speed2)
        input_condition_bound = BigFloat(eps(T)) * (abs(c) + speed) / (c - speed)
        return delay, input_condition_bound
    end
end

"""
    light_cone_intersection(spacetime, emission, receiver; ...)

Earliest direct future null intersection. The solve is delay-relative to avoid
epoch-dependent stopping. Every returned event is independently checked
against both the unsquared light equation and a scale-safe interval residual.
An inertial root whose input conditioning or coordinate representation cannot
meet the contract raises `NumericalConditioningError`.
"""
function light_cone_intersection(
    spacetime::MinkowskiSpacetime{T},
    emission::SpacetimeEvent{T},
    receiver::InertialWorldline{T};
    rtol::Real=T(512) * eps(T),
    atol::Real=zero(T),
    conditioning_tolerance::Real=sqrt(eps(T)),
    max_iterations::Integer=128,
    max_expansions::Integer=256,
    max_coordinate_time=nothing,
) where {T<:AbstractFloat}
    relative_tolerance, absolute_tolerance, condition_limit =
        _validate_light_solver_options(
            T,
            rtol,
            atol,
            conditioning_tolerance,
            max_iterations,
            max_expansions,
        )
    _check_spacetime(receiver, spacetime)
    receiver_at_emission = position_at(receiver, emission.t)
    coordinate_velocity(receiver, emission.t)
    separation = receiver_at_emission - emission.x
    initial_distance = _spatial_norm(separation)
    isfinite(initial_distance) ||
        throw(NumericalConditioningError("initial receiver range is not representable"))
    if receiver_at_emission == emission.x
        return _validated_intersection(
            spacetime,
            emission,
            receiver,
            emission.t,
            initial_distance,
            0,
            :coincident,
            relative_tolerance,
            absolute_tolerance,
        )
    end

    wide_delay, condition_bound =
        _inertial_delay_and_condition(spacetime, separation, receiver.velocity)
    condition_bound <= BigFloat(condition_limit) || throw(
        NumericalConditioningError(
            "near-null inertial geometry is input-conditioned at $condition_bound, above $condition_limit",
        ),
    )
    delay = T(wide_delay)
    isfinite(delay) && delay > zero(T) ||
        throw(NumericalConditioningError("inertial light-time delay is not representable"))
    reception_time, actual_delay = _representable_reception_time(emission.t, delay)
    delay_error = abs(BigFloat(actual_delay) - wide_delay)
    delay_tolerance = max(
        BigFloat(relative_tolerance) * wide_delay +
        BigFloat(absolute_tolerance) / BigFloat(spacetime.c),
        BigFloat(2) * BigFloat(eps(reception_time)),
    )
    delay_error <= delay_tolerance || throw(
        NumericalConditioningError(
            "coordinate epoch cannot represent the inertial delay to the requested tolerance",
        ),
    )
    if max_coordinate_time !== nothing
        horizon = T(max_coordinate_time)
        isfinite(horizon) || throw(ArgumentError("max_coordinate_time must be finite"))
        horizon >= emission.t || throw(ArgumentError("max_coordinate_time cannot precede emission"))
        reception_time <= horizon || throw(
            NoFutureLightConeIntersection(
                "inertial receiver does not intersect the light cone by max_coordinate_time",
            ),
        )
    end
    return _validated_intersection(
        spacetime,
        emission,
        receiver,
        reception_time,
        initial_distance,
        0,
        :analytic_inertial,
        relative_tolerance,
        absolute_tolerance,
    )
end

function light_cone_intersection(
    spacetime::MinkowskiSpacetime{T},
    emission::SpacetimeEvent{T},
    receiver::AbstractWorldline{T};
    rtol::Real=T(512) * eps(T),
    atol::Real=zero(T),
    conditioning_tolerance::Real=sqrt(eps(T)),
    max_iterations::Integer=128,
    max_expansions::Integer=256,
    max_coordinate_time=nothing,
) where {T<:AbstractFloat}
    relative_tolerance, absolute_tolerance, _ = _validate_light_solver_options(
        T,
        rtol,
        atol,
        conditioning_tolerance,
        max_iterations,
        max_expansions,
    )
    _check_spacetime(receiver, spacetime)
    domain_min, domain_max = coordinate_domain(receiver)
    domain_min <= emission.t <= domain_max || throw(
        NoFutureLightConeIntersection("emission lies outside the receiver worldline domain"),
    )
    finite_horizon = max_coordinate_time !== nothing || isfinite(domain_max)
    horizon = if max_coordinate_time === nothing
        domain_max
    else
        supplied = T(max_coordinate_time)
        isfinite(supplied) || throw(ArgumentError("max_coordinate_time must be finite"))
        supplied >= emission.t || throw(ArgumentError("max_coordinate_time cannot precede emission"))
        min(domain_max, supplied)
    end

    receiver_at_emission = position_at(receiver, emission.t)
    coordinate_velocity(receiver, emission.t)
    initial_separation = receiver_at_emission - emission.x
    initial_distance = _spatial_norm(initial_separation)
    isfinite(initial_distance) ||
        throw(NumericalConditioningError("initial receiver range is not representable"))
    if receiver_at_emission == emission.x
        return _validated_intersection(
            spacetime,
            emission,
            receiver,
            emission.t,
            initial_distance,
            0,
            :coincident,
            relative_tolerance,
            absolute_tolerance,
        )
    end

    emission_velocity = coordinate_velocity(receiver, emission.t)
    initial_radial_velocity = _spatial_dot(initial_separation / initial_distance, emission_velocity)
    initial_derivative = initial_radial_velocity - spacetime.c
    initial_derivative < zero(T) ||
        throw(InvalidWorldlineError("receiver is not timelike at emission"))
    minimum_delay = nextfloat(emission.t) - emission.t
    isfinite(minimum_delay) && minimum_delay > zero(T) || throw(
        NumericalConditioningError("emission epoch has no representable finite future increment"),
    )
    step = max(initial_distance / (-initial_derivative), minimum_delay)
    isfinite(step) && step > zero(T) ||
        throw(NumericalConditioningError("initial light-time step is not representable"))
    if finite_horizon
        available_delay = horizon - emission.t
        available_delay > zero(T) || throw(
            NoFutureLightConeIntersection("receiver worldline has no future interval"),
        )
        step = min(step, available_delay)
    end

    high_state = _light_state_for_delay(spacetime, emission, receiver, step)
    high = high_state.actual_delay
    expansions = 0
    while high_state.value > zero(T) &&
          !_light_state_converged(high_state, relative_tolerance, absolute_tolerance)
        if finite_horizon && high_state.reception_time == horizon
            throw(
                NoFutureLightConeIntersection(
                    "receiver does not intersect the future light cone within the declared horizon",
                ),
            )
        end
        expansions += 1
        expansions <= max_expansions || throw(
            LightConeSearchExhausted(
                "unbounded future light-cone search exhausted max_expansions without a bracket",
            ),
        )
        step *= T(2)
        isfinite(step) || throw(
            LightConeSearchExhausted("future light-cone delay search overflowed without a bracket"),
        )
        if finite_horizon
            step = min(step, horizon - emission.t)
        end
        high_state = _light_state_for_delay(spacetime, emission, receiver, step)
        high = high_state.actual_delay
    end
    if _light_state_converged(high_state, relative_tolerance, absolute_tolerance)
        return _validated_intersection(
            spacetime,
            emission,
            receiver,
            high_state.reception_time,
            initial_distance,
            1,
            :newton_seed,
            relative_tolerance,
            absolute_tolerance,
        )
    end

    # Safeguarded bracketed Newton over *representable reception times*.
    # Invariant: f(low_time) > 0 (receiver outside the light cone, or the
    # emission epoch itself) and f(high_time) < 0. Newton steps from the best
    # iterate and is used only when it lands strictly inside the bracket; a
    # Newton step that halves neither the bracket nor |f_best| forces a
    # bisection. The loop ends when a state meets the strict target
    # `max(atol, rtol * scale)`, or when the bracket collapses to adjacent
    # floating-point reception times, whose endpoints are then checked against
    # the floor-aware contract.
    #
    # Bracketing in reception time rather than in delay is essential: at a
    # large emission epoch many distinct delays round to the same reception
    # time, so a delay-space bracket can stay "open" while every probe snaps to
    # the same two adjacent reception times (a Newton 2-cycle that previously
    # exhausted max_iterations).
    low_time = emission.t
    high_time = high_state.reception_time
    seed_delay = max(min(initial_distance / (-initial_derivative), high), minimum_delay)
    current_time, _ = _representable_reception_time(emission.t, seed_delay)
    current_time = min(current_time, high_time)
    used_bisection = false
    last_step_newton = true
    best_state = nothing
    for iteration in 1:Int(max_iterations)
        state = _light_state_at_time(spacetime, emission, receiver, current_time)
        if _light_state_converged(state, relative_tolerance, absolute_tolerance)
            return _validated_intersection(
                spacetime,
                emission,
                receiver,
                state.reception_time,
                initial_distance,
                iteration,
                used_bisection ? :hybrid : :newton,
                relative_tolerance,
                absolute_tolerance,
            )
        end
        previous_width = high_time - low_time
        previous_best_value = best_state === nothing ? T(Inf) : abs(best_state.value)
        if state.value > zero(T)
            low_time = max(low_time, state.reception_time)
        else
            high_time = min(high_time, state.reception_time)
        end
        low_time < high_time || throw(
            LightConeConvergenceError("light-cone bracket lost its sign change"),
        )
        if best_state === nothing || abs(state.value) < abs(best_state.value)
            best_state = state
        end
        if nextfloat(low_time) >= high_time
            # The root is not representable more finely. Prefer the later
            # (causal, f <= 0) endpoint so a delivery is never placed outside
            # the future light cone; fall back to the earlier one. Either must
            # meet the floor-aware contract.
            adjacent_best = nothing
            for endpoint in (high_time, low_time)
                endpoint > emission.t || continue
                endpoint_state = _light_state_at_time(spacetime, emission, receiver, endpoint)
                if _light_state_within_contract(endpoint_state, relative_tolerance, absolute_tolerance)
                    adjacent_best = endpoint_state
                    break
                end
            end
            adjacent_best === nothing && throw(
                NumericalConditioningError(
                    "adjacent representable reception times do not satisfy the light-cone tolerance",
                ),
            )
            return _validated_intersection(
                spacetime,
                emission,
                receiver,
                adjacent_best.reception_time,
                initial_distance,
                iteration,
                :bisection,
                relative_tolerance,
                absolute_tolerance,
            )
        end
        width = high_time - low_time
        midpoint = low_time + width / T(2)
        if !(low_time < midpoint < high_time)
            midpoint = nextfloat(low_time)
        end
        # Newton always steps from the best iterate so far (smallest |f|, an
        # endpoint of the bracket), so interleaved bisections never discard
        # Newton progress. A Newton step that halved neither the bracket nor
        # |f_best| forces the next step to bisect; this keeps the search
        # robust where Newton is poor (near-kinks such as the C^1
        # trajectory-change onset, or noise-dominated residuals).
        stalled = last_step_newton && width > previous_width / T(2) &&
                  abs(best_state.value) > previous_best_value / T(2)
        newton_time = best_state.reception_time - best_state.value / best_state.derivative
        if isfinite(newton_time) && !(low_time < newton_time < high_time) &&
           abs(newton_time - best_state.reception_time) <= T(2) * eps(best_state.reception_time)
            # Newton has resolved the root to the ULP of the reception
            # coordinate: probe the neighbouring representable time towards
            # the opposite endpoint, which collapses the bracket directly.
            newton_time = best_state.reception_time == low_time ? nextfloat(low_time) :
                          prevfloat(high_time)
        end
        if !stalled && isfinite(newton_time) && low_time < newton_time < high_time
            current_time = newton_time
            last_step_newton = true
        else
            current_time = midpoint
            used_bisection = true
            last_step_newton = false
        end
    end
    throw(LightConeConvergenceError("light-cone root exhausted max_iterations"))
end

function solve_light_time_result(tA::Real, xA, xB_func, vB_func, c_sim::Real; kwargs...)
    spacetime = MinkowskiSpacetime(c_sim)
    T = typeof(spacetime.c)
    emission = SpacetimeEvent{T}(T(tA), _spatial_vector(T, xA))
    receiver = ParametricWorldline(
        spacetime,
        time -> _spatial_vector(T, xB_func(time)),
        time -> _spatial_vector(T, vB_func(time));
        consistency=:assumed,
        tmin=emission.t,
        validate_at=emission.t,
    )
    intersection = if haskey(kwargs, :rtol)
        light_cone_intersection(spacetime, emission, receiver; kwargs...)
    else
        light_cone_intersection(spacetime, emission, receiver; rtol=T(128) * eps(T), kwargs...)
    end
    converged_newton = intersection.method in (:newton, :newton_seed, :coincident)
    return LightTimeResult(intersection.reception.t, intersection.iterations, converged_newton)
end

function solve_light_time(tA::Real, xA, xB_func, vB_func, c_sim::Real; kwargs...)
    return solve_light_time_result(tA, xA, xB_func, vB_func, c_sim; kwargs...).tB
end
