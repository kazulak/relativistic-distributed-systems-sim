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

function _light_state_for_delay(
    spacetime::MinkowskiSpacetime{T},
    emission::SpacetimeEvent{T},
    receiver::AbstractWorldline{T},
    requested_delay::T,
) where {T<:AbstractFloat}
    reception_time, actual_delay = _representable_reception_time(emission.t, requested_delay)
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
    return (
        value=value,
        derivative=derivative,
        distance=distance,
        light_distance=light_distance,
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
    equation_tolerance = atol + rtol * equation_scale
    interval_residual = scaled_interval_residual(spacetime, emission, reception)
    interval_tolerance = max(T(4) * rtol, T(4) * atol / equation_scale)
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
    while high_state.value > absolute_tolerance &&
          high_state.equation_residual > relative_tolerance
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
    if high_state.equation_residual <= relative_tolerance ||
       abs(high_state.value) <= absolute_tolerance
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

    low = zero(T)
    current = min(initial_distance / (-initial_derivative), high)
    current = max(current, minimum_delay)
    used_bisection = false
    for iteration in 1:Int(max_iterations)
        state = _light_state_for_delay(spacetime, emission, receiver, current)
        if state.equation_residual <= relative_tolerance || abs(state.value) <= absolute_tolerance
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
        if state.value > zero(T)
            low = state.actual_delay
        else
            high = state.actual_delay
        end
        midpoint = low + (high - low) / T(2)
        if midpoint == low || midpoint == high
            for adjacent_delay in (low, high)
                adjacent_delay > zero(T) || continue
                adjacent_state = _light_state_for_delay(
                    spacetime,
                    emission,
                    receiver,
                    adjacent_delay,
                )
                if adjacent_state.equation_residual <= relative_tolerance ||
                   abs(adjacent_state.value) <= absolute_tolerance
                    return _validated_intersection(
                        spacetime,
                        emission,
                        receiver,
                        adjacent_state.reception_time,
                        initial_distance,
                        iteration,
                        :bisection,
                        relative_tolerance,
                        absolute_tolerance,
                    )
                end
            end
            throw(
                NumericalConditioningError(
                    "adjacent representable delays do not satisfy the light-cone tolerance",
                ),
            )
        end
        newton = state.actual_delay - state.value / state.derivative
        if isfinite(newton) && low < newton < high
            current = newton
        else
            current = midpoint
            used_bisection = true
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
