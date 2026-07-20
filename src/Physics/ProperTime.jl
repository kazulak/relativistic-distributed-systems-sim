"""Typed ideal proper-time interval in the coordinate time unit."""
struct ProperTime{T<:AbstractFloat}
    value::T

    function ProperTime{T}(value::T) where {T<:AbstractFloat}
        isfinite(value) || throw(ArgumentError("proper-time value must be finite"))
        return new{T}(value)
    end
end


ProperTime(value::T) where {T<:AbstractFloat} = ProperTime{T}(value)
ProperTime(value::Real) = ProperTime(float(value))

Base.isless(first::ProperTime, second::ProperTime) = isless(first.value, second.value)
Base.:(==)(first::ProperTime, second::ProperTime) = first.value == second.value
Base.:+(first::ProperTime{T}, second::ProperTime{T}) where {T} =
    ProperTime(first.value + second.value)
Base.:-(first::ProperTime{T}, second::ProperTime{T}) where {T} =
    ProperTime(first.value - second.value)
Base.:*(factor::Real, duration::ProperTime) = ProperTime(factor * duration.value)
Base.:*(duration::ProperTime, factor::Real) = factor * duration
Base.:/(duration::ProperTime, factor::Real) = ProperTime(duration.value / factor)

"""Adaptive quadrature exhausted its declared evaluation or resolution budget."""
struct QuadratureConvergenceError <: Exception
    message::String
end

Base.showerror(io::IO, error::QuadratureConvergenceError) = print(io, error.message)

"""Proper-time-to-coordinate-time inversion missed its declared residual contract."""
struct ProperTimeInversionError <: Exception
    message::String
end

Base.showerror(io::IO, error::ProperTimeInversionError) = print(io, error.message)

"""Return the coordinate-frame Lorentz factor for a representably timelike velocity."""
function lorentz_factor(spacetime::MinkowskiSpacetime{T}, velocity) where {T<:AbstractFloat}
    converted = _spatial_vector(T, velocity)
    _validate_velocity(spacetime, converted)
    return _gamma_from_beta(_beta_norm(spacetime, converted))
end

"""Return the ideal local-clock rate `dτ/dt` on `worldline` at coordinate time `t`."""
function proper_time_rate(
    spacetime::MinkowskiSpacetime{T},
    worldline::AbstractWorldline{T},
    coordinate_time::Real,
) where {T<:AbstractFloat}
    _check_spacetime(worldline, spacetime)
    velocity_now = coordinate_velocity(worldline, T(coordinate_time))
    beta = _beta_norm(spacetime, velocity_now)
    beta < one(T) || throw(InvalidWorldlineError("proper-time rate requires a timelike worldline"))
    rate = sqrt((one(T) - beta) * (one(T) + beta))
    rate > zero(T) || throw(NumericalConditioningError("proper-time rate is not representable"))
    return rate
end

struct _QuadraturePanel{T<:AbstractFloat}
    left::T
    right::T
    value::T
    error::T
end

function _quadrature_constant(::Type{T}, text::AbstractString) where {T<:AbstractFloat}
    return parse(T, text)
end

function _gauss_kronrod_panel(integrand, left::T, right::T) where {T<:AbstractFloat}
    nodes = (
        "0.991455371120812639206854697526329",
        "0.949107912342758524526189684047851",
        "0.864864423359769072789712788640926",
        "0.741531185599394439863864773280788",
        "0.586087235467691130294144838258730",
        "0.405845151377397166906606412076961",
        "0.207784955007898467600689403773245",
    )
    kronrod_weights = (
        "0.022935322010529224963732008058970",
        "0.063092092629978553290700663189204",
        "0.104790010322250183839876322541518",
        "0.140653259715525918745189590510238",
        "0.169004726639267902826583426598550",
        "0.190350578064785409913256402421014",
        "0.204432940075298892414161999234649",
        "0.209482141084727828012999174891714",
    )
    gauss_weights = (
        "0.129484966168869693270611432679082",
        "0.279705391489276667901467771423780",
        "0.381830050505118944950369775488975",
        "0.417959183673469387755102040816327",
    )

    midpoint = left + (right - left) / T(2)
    half_width = (right - left) / T(2)
    if midpoint == left || midpoint == right
        throw(QuadratureConvergenceError("quadrature panel has no representable midpoint"))
    end
    center_value = T(integrand(midpoint))
    isfinite(center_value) || throw(InvalidWorldlineError("proper-time integrand is not finite"))
    center_weight = _quadrature_constant(T, kronrod_weights[8])
    kronrod_sum = center_weight * center_value
    gauss_sum = _quadrature_constant(T, gauss_weights[4]) * center_value
    absolute_sum = center_weight * abs(center_value)
    sampled_pairs = Vector{Tuple{T,T,T}}(undef, 7)

    for index in 1:7
        node = _quadrature_constant(T, nodes[index])
        offset = half_width * node
        left_value = T(integrand(midpoint - offset))
        right_value = T(integrand(midpoint + offset))
        isfinite(left_value) && isfinite(right_value) ||
            throw(InvalidWorldlineError("proper-time integrand is not finite"))
        pair_sum = left_value + right_value
        weight = _quadrature_constant(T, kronrod_weights[index])
        kronrod_sum += weight * pair_sum
        absolute_sum += weight * (abs(left_value) + abs(right_value))
        sampled_pairs[index] = (left_value, right_value, weight)
        if index == 2
            gauss_sum += _quadrature_constant(T, gauss_weights[1]) * pair_sum
        elseif index == 4
            gauss_sum += _quadrature_constant(T, gauss_weights[2]) * pair_sum
        elseif index == 6
            gauss_sum += _quadrature_constant(T, gauss_weights[3]) * pair_sum
        end
    end

    mean_value = kronrod_sum / T(2)
    asc_sum = center_weight * abs(center_value - mean_value)
    for (left_value, right_value, weight) in sampled_pairs
        asc_sum += weight * (abs(left_value - mean_value) + abs(right_value - mean_value))
    end
    result = kronrod_sum * half_width
    absolute_integral = absolute_sum * abs(half_width)
    asc_integral = asc_sum * abs(half_width)
    error = abs((kronrod_sum - gauss_sum) * half_width)
    if asc_integral > zero(T) && error > zero(T)
        error = asc_integral * min(one(T), (T(200) * error / asc_integral)^(T(3) / T(2)))
    end
    roundoff_floor = T(50) * eps(T) * absolute_integral
    error = max(error, roundoff_floor)
    isfinite(result) && isfinite(error) ||
        throw(NumericalConditioningError("quadrature result is not representable"))
    return _QuadraturePanel(left, right, result, error)
end

function _default_quadrature_rtol(::Type{T}) where {T<:AbstractFloat}
    table_floor = parse(T, "1e-28")
    return max(T(128) * eps(T), eps(T)^(T(4) / T(5)), table_floor)
end

function _integrated_proper_time(
    spacetime::MinkowskiSpacetime{T},
    worldline::AbstractWorldline{T},
    first_time::T,
    second_time::T;
    rtol::T,
    atol::T,
    max_evaluations::Int,
    breakpoints,
) where {T<:AbstractFloat}
    first_time == second_time && return zero(T)
    direction = second_time > first_time ? one(T) : -one(T)
    left, right = direction > zero(T) ? (first_time, second_time) : (second_time, first_time)
    internal_points = T[]
    for raw_breakpoint in breakpoints
        breakpoint = T(raw_breakpoint)
        isfinite(breakpoint) || throw(ArgumentError("proper-time breakpoints must be finite"))
        left < breakpoint < right ||
            throw(ArgumentError("proper-time breakpoints must lie strictly inside the interval"))
        push!(internal_points, breakpoint)
    end
    sort!(unique!(internal_points))
    points = T[left; internal_points; right]
    panels = _QuadraturePanel{T}[]
    integrand(time) = proper_time_rate(spacetime, worldline, time)
    evaluations = 0
    for index in 1:(length(points) - 1)
        evaluations + 15 <= max_evaluations || throw(
            QuadratureConvergenceError("initial quadrature panels exceed max_evaluations"),
        )
        push!(panels, _gauss_kronrod_panel(integrand, points[index], points[index + 1]))
        evaluations += 15
    end
    total_value = sum(panel -> panel.value, panels; init=zero(T))
    total_error = sum(panel -> panel.error, panels; init=zero(T))

    while total_error > max(atol, rtol * abs(total_value))
        evaluations + 30 <= max_evaluations || throw(
            QuadratureConvergenceError(
                "proper-time quadrature exhausted max_evaluations with estimated error $total_error",
            ),
        )
        _, split_index = findmax(panel -> panel.error, panels)
        panel = panels[split_index]
        midpoint = panel.left + (panel.right - panel.left) / T(2)
        midpoint != panel.left && midpoint != panel.right || throw(
            QuadratureConvergenceError("quadrature cannot refine an adjacent-float panel"),
        )
        left_panel = _gauss_kronrod_panel(integrand, panel.left, midpoint)
        right_panel = _gauss_kronrod_panel(integrand, midpoint, panel.right)
        evaluations += 30
        total_value += left_panel.value + right_panel.value - panel.value
        total_error = max(
            zero(T),
            total_error + left_panel.error + right_panel.error - panel.error,
        )
        panels[split_index] = left_panel
        push!(panels, right_panel)
    end
    return direction * total_value
end

"""
    proper_time_between(spacetime, worldline, first_time, second_time; kwargs...)

Integrate ideal proper time between two coordinate times. General parametric
worldlines use adaptive Gauss--Kronrod quadrature; known non-smooth points must
be supplied as interval-internal `breakpoints`.
"""
function proper_time_between(
    spacetime::MinkowskiSpacetime{T},
    worldline::InertialWorldline{T},
    first_time::Real,
    second_time::Real;
    rtol::Real=_default_quadrature_rtol(T),
    atol::Real=zero(T),
    max_evaluations::Integer=100_000,
    breakpoints=(),
) where {T<:AbstractFloat}
    _check_spacetime(worldline, spacetime)
    _validate_real_tolerance("proper-time rtol", rtol, T; allow_zero=false, less_than_one=true)
    _validate_real_tolerance("proper-time atol", atol, T; allow_zero=true)
    max_evaluations >= 15 || throw(ArgumentError("max_evaluations must be at least 15"))
    isempty(breakpoints) ||
        throw(ArgumentError("breakpoints are not applicable to an inertial closed-form clock"))
    first, second = T(first_time), T(second_time)
    _check_coordinate_domain(worldline, first)
    _check_coordinate_domain(worldline, second)
    difference = second - first
    result = difference / lorentz_factor(spacetime, worldline.velocity)
    if first != second && iszero(result)
        throw(NumericalConditioningError("inertial proper-time interval underflows"))
    end
    isfinite(result) || throw(NumericalConditioningError("inertial proper-time interval overflowed"))
    return result
end

function _accelerated_proper_time(
    worldline::UniformlyAcceleratedWorldline{T},
    first::T,
    second::T,
) where {T<:AbstractFloat}
    wide_result = setprecision(BigFloat, _wide_precision(T)) do
        acceleration = BigFloat(worldline.proper_acceleration)
        c = BigFloat(worldline.c)
        origin_time = BigFloat(worldline.origin.t)
        first_z = acceleration * (BigFloat(first) - origin_time) / c
        second_z = acceleration * (BigFloat(second) - origin_time) / c
        return c / acceleration * (asinh(second_z) - asinh(first_z))
    end
    result = T(wide_result)
    isfinite(result) || throw(NumericalConditioningError("accelerated proper time is not representable"))
    if first != second && iszero(result)
        throw(NumericalConditioningError("accelerated proper-time difference underflows"))
    end
    return result
end

function proper_time_between(
    spacetime::MinkowskiSpacetime{T},
    worldline::UniformlyAcceleratedWorldline{T},
    first_time::Real,
    second_time::Real;
    rtol::Real=_default_quadrature_rtol(T),
    atol::Real=zero(T),
    max_evaluations::Integer=100_000,
    breakpoints=(),
) where {T<:AbstractFloat}
    _check_spacetime(worldline, spacetime)
    _validate_real_tolerance("proper-time rtol", rtol, T; allow_zero=false, less_than_one=true)
    _validate_real_tolerance("proper-time atol", atol, T; allow_zero=true)
    max_evaluations >= 15 || throw(ArgumentError("max_evaluations must be at least 15"))
    isempty(breakpoints) || throw(
        ArgumentError("breakpoints are not applicable to a uniformly accelerated closed-form clock"),
    )
    first, second = T(first_time), T(second_time)
    _check_coordinate_domain(worldline, first)
    _check_coordinate_domain(worldline, second)
    return _accelerated_proper_time(worldline, first, second)
end

function proper_time_between(
    spacetime::MinkowskiSpacetime{T},
    worldline::AbstractWorldline{T},
    first_time::Real,
    second_time::Real;
    rtol::Real=_default_quadrature_rtol(T),
    atol::Real=zero(T),
    max_evaluations::Integer=100_000,
    breakpoints=(),
) where {T<:AbstractFloat}
    _check_spacetime(worldline, spacetime)
    relative_tolerance = _validate_real_tolerance(
        "proper-time rtol",
        rtol,
        T;
        allow_zero=false,
        less_than_one=true,
    )
    absolute_tolerance = _validate_real_tolerance(
        "proper-time atol",
        atol,
        T;
        allow_zero=true,
    )
    max_evaluations >= 15 || throw(ArgumentError("max_evaluations must be at least 15"))
    first, second = T(first_time), T(second_time)
    _check_coordinate_domain(worldline, first)
    _check_coordinate_domain(worldline, second)
    return _integrated_proper_time(
        spacetime,
        worldline,
        first,
        second;
        rtol=relative_tolerance,
        atol=absolute_tolerance,
        max_evaluations=Int(max_evaluations),
        breakpoints=breakpoints,
    )
end

proper_duration(args...; kwargs...) = ProperTime(proper_time_between(args...; kwargs...))

function _duration_residual(
    spacetime::MinkowskiSpacetime{T},
    worldline::AbstractWorldline{T},
    start::T,
    candidate::T,
    target::T,
    rtol::T,
    atol::T,
    breakpoints=(),
) where {T<:AbstractFloat}
    candidate_breakpoints = T[
        breakpoint for breakpoint in breakpoints if start < breakpoint < candidate
    ]
    accumulated = proper_time_between(
        spacetime,
        worldline,
        start,
        candidate;
        rtol=rtol,
        atol=atol,
        breakpoints=candidate_breakpoints,
    )
    residual = abs(accumulated - target)
    tolerance = atol + rtol * max(target, abs(accumulated))
    return accumulated, residual, tolerance
end

function _prepare_future_breakpoints(
    ::Type{T},
    breakpoints,
    start::T,
) where {T<:AbstractFloat}
    prepared = T[]
    for raw_breakpoint in breakpoints
        breakpoint = try
            T(raw_breakpoint)
        catch error
            error isa InexactError || error isa OverflowError || rethrow()
            throw(ArgumentError("proper-time inversion breakpoint is not representable"))
        end
        isfinite(breakpoint) ||
            throw(ArgumentError("proper-time inversion breakpoints must be finite"))
        breakpoint > start || throw(
            ArgumentError("proper-time inversion breakpoints must be strictly after initial_time"),
        )
        push!(prepared, breakpoint)
    end
    sort!(unique!(prepared))
    return prepared
end

function _inversion_search_max(
    worldline::AbstractWorldline{T},
    start::T,
    max_coordinate_time,
) where {T<:AbstractFloat}
    _, domain_max = coordinate_domain(worldline)
    search_max = if max_coordinate_time === nothing
        domain_max
    else
        supplied = T(max_coordinate_time)
        isfinite(supplied) || throw(ArgumentError("max_coordinate_time must be finite"))
        min(domain_max, supplied)
    end
    search_max > start || throw(DomainError(search_max, "no future coordinate interval is available"))
    return search_max
end

function _select_exact_inversion_candidate(
    spacetime::MinkowskiSpacetime{T},
    worldline::AbstractWorldline{T},
    start::T,
    target::T,
    wide_candidate::BigFloat,
    search_max::T,
    rtol::T,
    atol::T,
) where {T<:AbstractFloat}
    wide_candidate <= BigFloat(search_max) || throw(
        DomainError(search_max, "worldline horizon precedes the requested proper duration"),
    )
    candidate = T(wide_candidate)
    isfinite(candidate) && candidate > start || throw(
        NumericalConditioningError("target coordinate time is not representable at this epoch"),
    )
    candidates = T[candidate]
    candidate > -T(Inf) && push!(candidates, prevfloat(candidate))
    candidate < T(Inf) && push!(candidates, nextfloat(candidate))
    best_residual = T(Inf)
    best_tolerance = zero(T)
    best_candidate = candidate
    for option in unique(candidates)
        start < option <= search_max || continue
        _, residual, tolerance = _duration_residual(
            spacetime,
            worldline,
            start,
            option,
            target,
            rtol,
            atol,
        )
        if residual < best_residual
            best_residual = residual
            best_tolerance = tolerance
            best_candidate = option
        end
    end
    best_residual <= best_tolerance || throw(
        NumericalConditioningError(
            "no representable coordinate time satisfies the proper-duration residual contract",
        ),
    )
    return best_candidate
end

"""
    coordinate_time_after_proper_time(spacetime, worldline, initial_time, duration; kwargs...)

Find the future coordinate time at which an ideal clock accumulates `duration`.
For a general worldline, `breakpoints` may contain the complete future schedule;
each trial integration automatically uses only points strictly inside its
current candidate interval.
"""
function coordinate_time_after_proper_time(
    spacetime::MinkowskiSpacetime{T},
    worldline::InertialWorldline{T},
    initial_time::Real,
    duration::Union{Real,ProperTime};
    max_coordinate_time=nothing,
    rtol::Real=_default_quadrature_rtol(T),
    atol::Real=zero(T),
    max_iterations::Integer=192,
    breakpoints=(),
) where {T<:AbstractFloat}
    _check_spacetime(worldline, spacetime)
    relative_tolerance = _validate_real_tolerance(
        "proper-time inversion rtol",
        rtol,
        T;
        allow_zero=false,
        less_than_one=true,
    )
    absolute_tolerance = _validate_real_tolerance(
        "proper-time inversion atol",
        atol,
        T;
        allow_zero=true,
    )
    max_iterations >= 1 || throw(ArgumentError("max_iterations must be positive"))
    isempty(breakpoints) ||
        throw(ArgumentError("breakpoints are not applicable to an inertial closed-form clock"))
    start = T(initial_time)
    _check_coordinate_domain(worldline, start)
    target = duration isa ProperTime ? T(duration.value) : T(duration)
    isfinite(target) && target >= zero(T) ||
        throw(ArgumentError("proper-time duration must be finite and nonnegative"))
    target == zero(T) && return start
    search_max = _inversion_search_max(worldline, start, max_coordinate_time)
    wide_candidate = setprecision(BigFloat, _wide_precision(T)) do
        BigFloat(start) + BigFloat(target) * BigFloat(lorentz_factor(spacetime, worldline.velocity))
    end
    return _select_exact_inversion_candidate(
        spacetime,
        worldline,
        start,
        target,
        wide_candidate,
        search_max,
        relative_tolerance,
        absolute_tolerance,
    )
end

function coordinate_time_after_proper_time(
    spacetime::MinkowskiSpacetime{T},
    worldline::UniformlyAcceleratedWorldline{T},
    initial_time::Real,
    duration::Union{Real,ProperTime};
    max_coordinate_time=nothing,
    rtol::Real=_default_quadrature_rtol(T),
    atol::Real=zero(T),
    max_iterations::Integer=192,
    breakpoints=(),
) where {T<:AbstractFloat}
    _check_spacetime(worldline, spacetime)
    relative_tolerance = _validate_real_tolerance(
        "proper-time inversion rtol",
        rtol,
        T;
        allow_zero=false,
        less_than_one=true,
    )
    absolute_tolerance = _validate_real_tolerance(
        "proper-time inversion atol",
        atol,
        T;
        allow_zero=true,
    )
    max_iterations >= 1 || throw(ArgumentError("max_iterations must be positive"))
    isempty(breakpoints) || throw(
        ArgumentError("breakpoints are not applicable to a uniformly accelerated closed-form clock"),
    )
    start = T(initial_time)
    _check_coordinate_domain(worldline, start)
    target = duration isa ProperTime ? T(duration.value) : T(duration)
    isfinite(target) && target >= zero(T) ||
        throw(ArgumentError("proper-time duration must be finite and nonnegative"))
    target == zero(T) && return start
    search_max = _inversion_search_max(worldline, start, max_coordinate_time)
    wide_candidate = setprecision(BigFloat, _wide_precision(T)) do
        c = BigFloat(worldline.c)
        acceleration = BigFloat(worldline.proper_acceleration)
        origin_time = BigFloat(worldline.origin.t)
        initial_z = acceleration * (BigFloat(start) - origin_time) / c
        target_rapidity = asinh(initial_z) + acceleration * BigFloat(target) / c
        return origin_time + c / acceleration * sinh(target_rapidity)
    end
    return _select_exact_inversion_candidate(
        spacetime,
        worldline,
        start,
        target,
        wide_candidate,
        search_max,
        relative_tolerance,
        absolute_tolerance,
    )
end

function coordinate_time_after_proper_time(
    spacetime::MinkowskiSpacetime{T},
    worldline::AbstractWorldline{T},
    initial_time::Real,
    duration::Union{Real,ProperTime};
    max_coordinate_time=nothing,
    rtol::Real=_default_quadrature_rtol(T),
    atol::Real=zero(T),
    max_iterations::Integer=192,
    breakpoints=(),
) where {T<:AbstractFloat}
    _check_spacetime(worldline, spacetime)
    relative_tolerance = _validate_real_tolerance(
        "proper-time inversion rtol",
        rtol,
        T;
        allow_zero=false,
        less_than_one=true,
    )
    absolute_tolerance = _validate_real_tolerance(
        "proper-time inversion atol",
        atol,
        T;
        allow_zero=true,
    )
    max_iterations >= 1 || throw(ArgumentError("max_iterations must be positive"))
    start = T(initial_time)
    _check_coordinate_domain(worldline, start)
    target = duration isa ProperTime ? T(duration.value) : T(duration)
    isfinite(target) && target >= zero(T) ||
        throw(ArgumentError("proper-time duration must be finite and nonnegative"))
    future_breakpoints = _prepare_future_breakpoints(T, breakpoints, start)
    target == zero(T) && return start

    search_max = _inversion_search_max(worldline, start, max_coordinate_time)
    initial_rate = proper_time_rate(spacetime, worldline, start)
    step = target / initial_rate
    isfinite(step) && step > zero(T) ||
        throw(NumericalConditioningError("initial coordinate-time increment is not representable"))
    high = start + step
    high > start || throw(
        NumericalConditioningError("requested proper duration is below coordinate-time resolution at this epoch"),
    )
    high = min(high, search_max)
    accumulated, _, _ = _duration_residual(
        spacetime,
        worldline,
        start,
        high,
        target,
        relative_tolerance,
        absolute_tolerance,
        future_breakpoints,
    )
    expansions = 0
    while accumulated < target
        high == search_max && throw(
            DomainError(search_max, "worldline ends before the requested proper duration elapses"),
        )
        expansions += 1
        expansions <= max_iterations || throw(
            ProperTimeInversionError("proper-time inversion failed to bracket the target"),
        )
        step *= T(2)
        isfinite(step) || throw(NumericalConditioningError("coordinate-time search increment overflowed"))
        candidate = start + step
        candidate > high || throw(
            NumericalConditioningError("no larger coordinate time is representable during inversion"),
        )
        high = min(candidate, search_max)
        accumulated, _, _ = _duration_residual(
            spacetime,
            worldline,
            start,
            high,
            target,
            relative_tolerance,
            absolute_tolerance,
            future_breakpoints,
        )
    end

    low = start
    current = high
    for iteration in 1:Int(max_iterations)
        accumulated, residual, tolerance = _duration_residual(
            spacetime,
            worldline,
            start,
            current,
            target,
            relative_tolerance,
            absolute_tolerance,
            future_breakpoints,
        )
        residual <= tolerance && return current
        if accumulated < target
            low = current
        else
            high = current
        end
        midpoint = low + (high - low) / T(2)
        if midpoint == low || midpoint == high
            for candidate in (low, high)
                _, adjacent_residual, adjacent_tolerance = _duration_residual(
                    spacetime,
                    worldline,
                    start,
                    candidate,
                    target,
                    relative_tolerance,
                    absolute_tolerance,
                    future_breakpoints,
                )
                adjacent_residual <= adjacent_tolerance && return candidate
            end
            throw(
                NumericalConditioningError(
                    "no representable coordinate time satisfies the proper-duration tolerance",
                ),
            )
        end
        rate = proper_time_rate(spacetime, worldline, current)
        newton = current + (target - accumulated) / rate
        current = isfinite(newton) && low < newton < high ? newton : midpoint
        iteration == max_iterations && throw(
            ProperTimeInversionError("proper-time inversion exhausted max_iterations"),
        )
    end
    throw(ProperTimeInversionError("proper-time inversion failed unexpectedly"))
end
