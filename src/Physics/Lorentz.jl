"""Scale-safe beta, ideal proper-time rate, gamma, and gamma-minus-one."""
function relativistic_factors(
    spacetime::MinkowskiSpacetime{T},
    velocity;
    conditioning_tolerance::Real=sqrt(eps(T)),
) where {T<:AbstractFloat}
    limit = _validate_real_tolerance(
        "relativistic conditioning_tolerance",
        conditioning_tolerance,
        T;
        allow_zero=false,
        less_than_one=true,
    )
    converted = _spatial_vector(T, velocity)
    _validate_velocity(spacetime, converted)
    beta = _beta_norm(spacetime, converted)
    gamma = _gamma_from_beta(beta)
    gamma * gamma * eps(T) <= limit || throw(
        NumericalConditioningError(
            "Lorentz factor $gamma is too ill-conditioned for $(T) under limit $limit",
        ),
    )
    rate = inv(gamma)
    gamma_minus_one = if beta == zero(T)
        zero(T)
    else
        gamma * gamma * beta * beta / (gamma + one(T))
    end
    return (
        beta=beta,
        proper_time_rate=rate,
        gamma=gamma,
        gamma_minus_one=gamma_minus_one,
    )
end

"""Passive standard boost into a frame moving at `frame_velocity`."""
struct LorentzBoost{T<:AbstractFloat}
    spacetime::MinkowskiSpacetime{T}
    frame_velocity::SVector{3,T}
    gamma::T
    gamma_minus_one::T
    conditioning_tolerance::T

    function LorentzBoost{T}(
        spacetime::MinkowskiSpacetime{T},
        frame_velocity::SVector{3,T},
        gamma::T,
        gamma_minus_one::T,
        conditioning_tolerance::T,
    ) where {T<:AbstractFloat}
        return new{T}(
            spacetime,
            frame_velocity,
            gamma,
            gamma_minus_one,
            conditioning_tolerance,
        )
    end
end

function LorentzBoost(
    spacetime::MinkowskiSpacetime{T},
    frame_velocity;
    conditioning_tolerance::Real=sqrt(eps(T)),
) where {T<:AbstractFloat}
    converted = _spatial_vector(T, frame_velocity)
    factors = relativistic_factors(
        spacetime,
        converted;
        conditioning_tolerance=conditioning_tolerance,
    )
    return LorentzBoost{T}(
        spacetime,
        converted,
        factors.gamma,
        factors.gamma_minus_one,
        T(conditioning_tolerance),
    )
end

"""
    SpacetimeDisplacement(dt, dx)

A finite coordinate displacement between two events. Unlike an absolute
`SpacetimeEvent`, this type retains the separation independently of a large
coordinate epoch and is therefore the preferred input/output for numerical
Lorentz-covariance checks.
"""
struct SpacetimeDisplacement{T<:AbstractFloat}
    dt::T
    dx::SVector{3,T}

    function SpacetimeDisplacement{T}(dt::T, dx::SVector{3,T}) where {T<:AbstractFloat}
        isfinite(dt) || throw(ArgumentError("displacement coordinate time must be finite"))
        all(isfinite, dx) ||
            throw(ArgumentError("displacement position must contain only finite values"))
        return new{T}(dt, dx)
    end
end

SpacetimeDisplacement(dt::T, dx::SVector{3,T}) where {T<:AbstractFloat} =
    SpacetimeDisplacement{T}(dt, dx)

function SpacetimeDisplacement(dt::Real, dx)
    dx isa AbstractVector || dx isa Tuple ||
        throw(ArgumentError("displacement position must be a three-component collection"))
    length(dx) == 3 ||
        throw(ArgumentError("displacement position must have exactly three components"))
    raw = SVector{3}(dx)
    T = promote_type(
        typeof(float(dt)),
        typeof(float(raw[1])),
        typeof(float(raw[2])),
        typeof(float(raw[3])),
    )
    T <: AbstractFloat || throw(ArgumentError("displacement coordinates must be real numbers"))
    return SpacetimeDisplacement{T}(T(dt), SVector{3,T}(raw))
end

function _wide_boost_event(
    boost::LorentzBoost{T},
    event::SpacetimeEvent{T},
    inverse::Bool,
) where {T<:AbstractFloat}
    return setprecision(BigFloat, _wide_precision(T)) do
        c = BigFloat(boost.spacetime.c)
        sign = inverse ? BigFloat(-1) : BigFloat(1)
        bx = sign * BigFloat(boost.frame_velocity[1]) / c
        by = sign * BigFloat(boost.frame_velocity[2]) / c
        bz = sign * BigFloat(boost.frame_velocity[3]) / c
        beta2 = bx^2 + by^2 + bz^2
        beta2 == 0 && return (
            BigFloat(event.t),
            BigFloat(event.x[1]),
            BigFloat(event.x[2]),
            BigFloat(event.x[3]),
        )
        gamma = BigFloat(boost.gamma)
        gamma_minus_one = BigFloat(boost.gamma_minus_one)
        ct = c * BigFloat(event.t)
        x, y, z = BigFloat.(Tuple(event.x))
        projection = bx * x + by * y + bz * z
        transformed_ct = gamma * (ct - projection)
        coefficient = gamma_minus_one * projection / beta2 - gamma * ct
        return (
            transformed_ct / c,
            x + coefficient * bx,
            y + coefficient * by,
            z + coefficient * bz,
        )
    end
end

function _convert_boosted_event(
    boost::LorentzBoost{T},
    transformed,
) where {T<:AbstractFloat}
    try
        converted = SpacetimeEvent{T}(
            T(transformed[1]),
            SVector{3,T}(T(transformed[2]), T(transformed[3]), T(transformed[4])),
        )
        all(isfinite, converted.x) && isfinite(converted.t) ||
            throw(NumericalConditioningError("Lorentz-transformed event is not representable"))
        return converted
    catch error
        if error isa ArgumentError || error isa InexactError || error isa OverflowError
            throw(NumericalConditioningError("Lorentz-transformed event is not representable"))
        end
        rethrow()
    end
end

function _event_roundtrip_residual(
    boost::LorentzBoost{T},
    original::SpacetimeEvent{T},
    transformed::SpacetimeEvent{T},
) where {T<:AbstractFloat}
    recovered_wide = _wide_boost_event(boost, transformed, true)
    c = BigFloat(boost.spacetime.c)
    original_scale = hypot(
        c * BigFloat(original.t),
        BigFloat(original.x[1]),
        BigFloat(original.x[2]),
        BigFloat(original.x[3]),
    )
    # A four-coordinate norm avoids both overflow and a scale-dependent
    # absolute floor for tiny nonzero events.
    absolute_error = hypot(
        c * (recovered_wide[1] - BigFloat(original.t)),
        recovered_wide[2] - BigFloat(original.x[1]),
        recovered_wide[3] - BigFloat(original.x[2]),
        recovered_wide[4] - BigFloat(original.x[3]),
    )
    if original_scale == 0
        return absolute_error == 0 ? BigFloat(0) : BigFloat(Inf)
    end
    return absolute_error / original_scale
end

function _event_component_roundtrip_residual(
    boost::LorentzBoost{T},
    original::SpacetimeEvent{T},
    transformed::SpacetimeEvent{T},
) where {T<:AbstractFloat}
    recovered_wide = _wide_boost_event(boost, transformed, true)
    c = BigFloat(boost.spacetime.c)
    original_components = (
        c * BigFloat(original.t),
        BigFloat(original.x[1]),
        BigFloat(original.x[2]),
        BigFloat(original.x[3]),
    )
    recovered_components = (
        c * recovered_wide[1],
        recovered_wide[2],
        recovered_wide[3],
        recovered_wide[4],
    )
    # A single event cannot declare the separation that a caller later cares
    # about. This componentwise check nevertheless catches translation-driven
    # loss when a large temporal coordinate contaminates a locally small
    # spatial coordinate. The paired/displacement API is required for a real
    # separation contract.
    local_floor = abs(c)
    residual = BigFloat(0)
    for index in eachindex(original_components)
        scale = max(abs(original_components[index]), local_floor)
        scale > 0 || continue
        residual = max(
            residual,
            abs(recovered_components[index] - original_components[index]) / scale,
        )
    end
    return residual
end

"""
    lorentz_transform(boost, event)

Transform one absolute event. This validates representability and inverse
round-trip error for that event, but cannot certify an unknown separation from
another independently transformed event. Use `lorentz_transform_pair` or
`lorentz_transform_displacement` for interval or causal-covariance claims.
"""
function lorentz_transform(
    boost::LorentzBoost{T},
    event::SpacetimeEvent{T},
) where {T<:AbstractFloat}
    all(iszero, boost.frame_velocity) && return event
    transformed = _convert_boosted_event(boost, _wide_boost_event(boost, event, false))
    roundtrip_residual = _event_roundtrip_residual(boost, event, transformed)
    roundtrip_residual <= BigFloat(boost.conditioning_tolerance) || throw(
        NumericalConditioningError(
            "Lorentz event transform fails covariance/round-trip conditioning: $roundtrip_residual",
        ),
    )
    component_residual = _event_component_roundtrip_residual(boost, event, transformed)
    component_residual <= BigFloat(boost.conditioning_tolerance) || throw(
        NumericalConditioningError(
            "single-event Lorentz transform loses local coordinate resolution; " *
            "use lorentz_transform_pair or lorentz_transform_displacement",
        ),
    )
    return transformed
end

function _wide_event_displacement(
    first::SpacetimeEvent{T},
    second::SpacetimeEvent{T},
) where {T<:AbstractFloat}
    return setprecision(BigFloat, _wide_precision(T)) do
        return (
            BigFloat(second.t) - BigFloat(first.t),
            BigFloat(second.x[1]) - BigFloat(first.x[1]),
            BigFloat(second.x[2]) - BigFloat(first.x[2]),
            BigFloat(second.x[3]) - BigFloat(first.x[3]),
        )
    end
end

function _wide_boost_displacement(
    boost::LorentzBoost{T},
    displacement,
    inverse::Bool,
) where {T<:AbstractFloat}
    return setprecision(BigFloat, _wide_precision(T)) do
        c = BigFloat(boost.spacetime.c)
        sign = inverse ? BigFloat(-1) : BigFloat(1)
        bx = sign * BigFloat(boost.frame_velocity[1]) / c
        by = sign * BigFloat(boost.frame_velocity[2]) / c
        bz = sign * BigFloat(boost.frame_velocity[3]) / c
        beta2 = bx^2 + by^2 + bz^2
        dt = BigFloat(displacement[1])
        x = BigFloat(displacement[2])
        y = BigFloat(displacement[3])
        z = BigFloat(displacement[4])
        beta2 == 0 && return (dt, x, y, z)
        gamma = BigFloat(boost.gamma)
        gamma_minus_one = BigFloat(boost.gamma_minus_one)
        ct = c * dt
        projection = bx * x + by * y + bz * z
        transformed_ct = gamma * (ct - projection)
        coefficient = gamma_minus_one * projection / beta2 - gamma * ct
        return (
            transformed_ct / c,
            x + coefficient * bx,
            y + coefficient * by,
            z + coefficient * bz,
        )
    end
end

function _convert_boosted_displacement(
    transformed,
    ::Type{T},
) where {T<:AbstractFloat}
    try
        converted = SpacetimeDisplacement{T}(
            T(transformed[1]),
            SVector{3,T}(T(transformed[2]), T(transformed[3]), T(transformed[4])),
        )
        for index in eachindex(transformed)
            transformed[index] != 0 && (index == 1 ? converted.dt : converted.dx[index - 1]) == 0 &&
                throw(
                    NumericalConditioningError(
                        "nonzero Lorentz-transformed displacement component underflowed",
                    ),
                )
        end
        return converted
    catch error
        if error isa ArgumentError || error isa InexactError || error isa OverflowError
            throw(NumericalConditioningError("Lorentz-transformed displacement is not representable"))
        end
        rethrow()
    end
end

function _wide_displacement_interval(spacetime::MinkowskiSpacetime, displacement)
    cdt = BigFloat(spacetime.c) * BigFloat(displacement[1])
    spatial = BigFloat(displacement[2])^2 +
              BigFloat(displacement[3])^2 +
              BigFloat(displacement[4])^2
    temporal = cdt^2
    return temporal - spatial, temporal + spatial
end

function _wide_displacement_relation(spacetime::MinkowskiSpacetime, displacement, tolerance)
    all(iszero, displacement) && return :coincident
    interval, scale = _wide_displacement_interval(spacetime, displacement)
    scale > 0 || throw(NumericalConditioningError("displacement scale is not resolvable"))
    signed_scaled = interval / scale
    if signed_scaled < -BigFloat(tolerance)
        return :spacelike
    elseif abs(signed_scaled) <= BigFloat(tolerance)
        return displacement[1] > 0 ? :future_null : :past_null
    else
        return displacement[1] > 0 ? :future_timelike : :past_timelike
    end
end

function _displacement_tuple(displacement::SpacetimeDisplacement)
    return (displacement.dt, displacement.dx[1], displacement.dx[2], displacement.dx[3])
end

function _validate_displacement_covariance(
    boost::LorentzBoost{T},
    original,
    transformed::SpacetimeDisplacement{T},
    covariance_tolerance::T,
) where {T<:AbstractFloat}
    transformed_tuple = _displacement_tuple(transformed)
    original_relation =
        _wide_displacement_relation(boost.spacetime, original, covariance_tolerance)
    transformed_relation =
        _wide_displacement_relation(boost.spacetime, transformed_tuple, covariance_tolerance)
    original_relation === transformed_relation || throw(
        NumericalConditioningError(
            "Lorentz displacement conversion changed causal class from " *
            "$original_relation to $transformed_relation",
        ),
    )

    original_interval, original_scale =
        _wide_displacement_interval(boost.spacetime, original)
    transformed_interval, transformed_scale =
        _wide_displacement_interval(boost.spacetime, transformed_tuple)
    interval_scale = max(original_scale, transformed_scale)
    if interval_scale > 0
        invariant_residual = abs(transformed_interval - original_interval) / interval_scale
        invariant_residual <= BigFloat(covariance_tolerance) || throw(
            NumericalConditioningError(
                "Lorentz displacement interval covariance exceeds tolerance: $invariant_residual",
            ),
        )
    end

    recovered = _wide_boost_displacement(boost, transformed_tuple, true)
    original_norm = hypot(
        BigFloat(boost.spacetime.c) * BigFloat(original[1]),
        BigFloat(original[2]),
        BigFloat(original[3]),
        BigFloat(original[4]),
    )
    recovery_error = hypot(
        BigFloat(boost.spacetime.c) * (recovered[1] - BigFloat(original[1])),
        recovered[2] - BigFloat(original[2]),
        recovered[3] - BigFloat(original[3]),
        recovered[4] - BigFloat(original[4]),
    )
    if original_norm == 0
        recovery_error == 0 ||
            throw(NumericalConditioningError("zero displacement did not remain zero under boost"))
    elseif recovery_error / original_norm > BigFloat(boost.conditioning_tolerance)
        throw(NumericalConditioningError("Lorentz displacement inverse round trip is ill-conditioned"))
    end
    return transformed
end

"""
    lorentz_transform_displacement(boost, displacement; covariance_tolerance=...)
    lorentz_transform_displacement(boost, first, second; covariance_tolerance=...)

Transform a relative four-displacement without first transforming its absolute
endpoints. The returned displacement is checked for interval, causal-class,
and inverse-round-trip covariance after conversion to the coordinate type.
This is the preferred API at large coordinate epochs.
"""
function lorentz_transform_displacement(
    boost::LorentzBoost{T},
    displacement::SpacetimeDisplacement{T};
    covariance_tolerance::Real=T(256) * eps(T),
) where {T<:AbstractFloat}
    tolerance = _validate_real_tolerance(
        "Lorentz covariance_tolerance",
        covariance_tolerance,
        T;
        allow_zero=false,
        less_than_one=true,
    )
    original = _displacement_tuple(displacement)
    all(iszero, boost.frame_velocity) && return displacement
    converted = _convert_boosted_displacement(
        _wide_boost_displacement(boost, original, false),
        T,
    )
    return _validate_displacement_covariance(boost, original, converted, tolerance)
end

function lorentz_transform_displacement(
    boost::LorentzBoost{T},
    first::SpacetimeEvent{T},
    second::SpacetimeEvent{T};
    covariance_tolerance::Real=T(256) * eps(T),
) where {T<:AbstractFloat}
    tolerance = _validate_real_tolerance(
        "Lorentz covariance_tolerance",
        covariance_tolerance,
        T;
        allow_zero=false,
        less_than_one=true,
    )
    original = _wide_event_displacement(first, second)
    all(iszero, boost.frame_velocity) &&
        return _convert_boosted_displacement(original, T)
    converted = _convert_boosted_displacement(
        _wide_boost_displacement(boost, original, false),
        T,
    )
    return _validate_displacement_covariance(boost, original, converted, tolerance)
end

"""
    lorentz_transform_pair(boost, first, second; covariance_tolerance=...)

Transform two events as one separation-aware operation. The displacement is
formed before either absolute endpoint is rounded. If the transformed absolute
epoch cannot represent that displacement while preserving its interval and
causal class, `NumericalConditioningError` is raised. Use
`lorentz_transform_displacement` when only the invariant separation is needed.
"""
function lorentz_transform_pair(
    boost::LorentzBoost{T},
    first::SpacetimeEvent{T},
    second::SpacetimeEvent{T};
    covariance_tolerance::Real=T(256) * eps(T),
) where {T<:AbstractFloat}
    tolerance = _validate_real_tolerance(
        "Lorentz covariance_tolerance",
        covariance_tolerance,
        T;
        allow_zero=false,
        less_than_one=true,
    )
    all(iszero, boost.frame_velocity) && return (first, second)
    original = _wide_event_displacement(first, second)
    transformed_displacement = lorentz_transform_displacement(
        boost,
        first,
        second;
        covariance_tolerance=tolerance,
    )
    transformed_first =
        _convert_boosted_event(boost, _wide_boost_event(boost, first, false))
    wide_second = setprecision(BigFloat, _wide_precision(T)) do
        return (
            BigFloat(transformed_first.t) + BigFloat(transformed_displacement.dt),
            BigFloat(transformed_first.x[1]) + BigFloat(transformed_displacement.dx[1]),
            BigFloat(transformed_first.x[2]) + BigFloat(transformed_displacement.dx[2]),
            BigFloat(transformed_first.x[3]) + BigFloat(transformed_displacement.dx[3]),
        )
    end
    transformed_second = _convert_boosted_event(boost, wide_second)
    realized = _wide_event_displacement(transformed_first, transformed_second)
    realized_displacement = _convert_boosted_displacement(realized, T)
    _validate_displacement_covariance(
        boost,
        original,
        realized_displacement,
        tolerance,
    )

    ideal = _displacement_tuple(transformed_displacement)
    ideal_norm = hypot(
        BigFloat(boost.spacetime.c) * BigFloat(ideal[1]),
        BigFloat(ideal[2]),
        BigFloat(ideal[3]),
        BigFloat(ideal[4]),
    )
    realization_error = hypot(
        BigFloat(boost.spacetime.c) * (BigFloat(realized[1]) - BigFloat(ideal[1])),
        BigFloat(realized[2]) - BigFloat(ideal[2]),
        BigFloat(realized[3]) - BigFloat(ideal[3]),
        BigFloat(realized[4]) - BigFloat(ideal[4]),
    )
    if ideal_norm == 0
        realization_error == 0 || throw(
            NumericalConditioningError("coincident transformed pair separated during reconstruction"),
        )
    elseif realization_error / ideal_norm > BigFloat(tolerance)
        throw(
            NumericalConditioningError(
                "transformed absolute epoch cannot represent the covariant displacement; " *
                "use lorentz_transform_displacement",
            ),
        )
    end
    return (transformed_first, transformed_second)
end

function _wide_boost_velocity(
    boost::LorentzBoost{T},
    velocity::SVector{3,T},
    inverse::Bool,
) where {T<:AbstractFloat}
    return setprecision(BigFloat, _wide_precision(T)) do
        c = BigFloat(boost.spacetime.c)
        sign = inverse ? BigFloat(-1) : BigFloat(1)
        bx = sign * BigFloat(boost.frame_velocity[1]) / c
        by = sign * BigFloat(boost.frame_velocity[2]) / c
        bz = sign * BigFloat(boost.frame_velocity[3]) / c
        beta2 = bx^2 + by^2 + bz^2
        qx = BigFloat(velocity[1]) / c
        qy = BigFloat(velocity[2]) / c
        qz = BigFloat(velocity[3]) / c
        beta2 == 0 && return (BigFloat(velocity[1]), BigFloat(velocity[2]), BigFloat(velocity[3]))
        projection = bx * qx + by * qy + bz * qz
        gamma = BigFloat(boost.gamma)
        denominator = gamma * (1 - projection)
        denominator > 0 || throw(NumericalConditioningError("boosted coordinate-time rate is nonpositive"))
        coefficient = BigFloat(boost.gamma_minus_one) * projection / beta2 - gamma
        return (
            c * (qx + coefficient * bx) / denominator,
            c * (qy + coefficient * by) / denominator,
            c * (qz + coefficient * bz) / denominator,
        )
    end
end

function lorentz_transform_velocity(
    boost::LorentzBoost{T},
    velocity,
) where {T<:AbstractFloat}
    converted = _spatial_vector(T, velocity)
    _validate_velocity(boost.spacetime, converted)
    all(iszero, boost.frame_velocity) && return converted
    wide = _wide_boost_velocity(boost, converted, false)
    transformed = SVector{3,T}(T(wide[1]), T(wide[2]), T(wide[3]))
    try
        _validate_velocity(boost.spacetime, transformed)
    catch error
        error isa InvalidWorldlineError || rethrow()
        throw(NumericalConditioningError("boosted velocity is not representably timelike"))
    end
    recovered_wide = _wide_boost_velocity(boost, transformed, true)
    scale = max(_spatial_norm(converted), boost.spacetime.c * eps(T))
    error = hypot(
        T(recovered_wide[1]) - converted[1],
        T(recovered_wide[2]) - converted[2],
        T(recovered_wide[3]) - converted[3],
    ) / scale
    error <= boost.conditioning_tolerance || throw(
        NumericalConditioningError("Lorentz velocity round trip exceeds conditioning tolerance"),
    )
    return transformed
end

function lorentz_transform(
    boost::LorentzBoost{T},
    worldline::InertialWorldline{T},
) where {T<:AbstractFloat}
    _check_spacetime(worldline, boost.spacetime)
    transformed_origin = lorentz_transform(boost, worldline.origin)
    transformed_velocity = lorentz_transform_velocity(boost, worldline.velocity)
    return InertialWorldline(boost.spacetime, transformed_origin, transformed_velocity)
end

inverse_boost(boost::LorentzBoost) = LorentzBoost(
    boost.spacetime,
    -boost.frame_velocity;
    conditioning_tolerance=boost.conditioning_tolerance,
)

const boost_event = lorentz_transform
const boost_velocity = lorentz_transform_velocity
const boost_displacement = lorentz_transform_displacement
const boost_pair = lorentz_transform_pair
