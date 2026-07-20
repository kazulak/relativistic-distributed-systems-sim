using StaticArrays

"""A requested floating-point result is not representable with its accuracy contract."""
struct NumericalConditioningError <: Exception
    message::String
end

Base.showerror(io::IO, error::NumericalConditioningError) = print(io, error.message)

"""Flat `(+---)` spacetime using one internally consistent coordinate unit system."""
struct MinkowskiSpacetime{T<:AbstractFloat}
    c::T

    function MinkowskiSpacetime{T}(c::T) where {T<:AbstractFloat}
        isfinite(c) || throw(ArgumentError("signal speed c must be finite"))
        c > zero(T) || throw(ArgumentError("signal speed c must be strictly positive"))
        return new{T}(c)
    end
end

MinkowskiSpacetime(c::T) where {T<:AbstractFloat} = MinkowskiSpacetime{T}(c)
MinkowskiSpacetime(c::Real) = MinkowskiSpacetime(float(c))

"""A finite coordinate event in an inertial frame."""
struct SpacetimeEvent{T<:AbstractFloat}
    t::T
    x::SVector{3,T}

    function SpacetimeEvent{T}(t::T, x::SVector{3,T}) where {T<:AbstractFloat}
        isfinite(t) || throw(ArgumentError("event coordinate time must be finite"))
        all(isfinite, x) || throw(ArgumentError("event position must contain only finite values"))
        return new{T}(t, x)
    end
end


SpacetimeEvent(t::T, x::SVector{3,T}) where {T<:AbstractFloat} = SpacetimeEvent{T}(t, x)

function SpacetimeEvent(t::Real, x)
    x isa AbstractVector || x isa Tuple ||
        throw(ArgumentError("event position must be a three-component collection"))
    length(x) == 3 || throw(ArgumentError("event position must have exactly three components"))
    raw = SVector{3}(x)
    T = promote_type(
        typeof(float(t)),
        typeof(float(raw[1])),
        typeof(float(raw[2])),
        typeof(float(raw[3])),
    )
    T <: AbstractFloat || throw(ArgumentError("event coordinates must be real numbers"))
    return SpacetimeEvent{T}(T(t), SVector{3,T}(raw))
end

@inline function _spatial_vector(::Type{T}, x) where {T<:AbstractFloat}
    x isa AbstractVector || x isa Tuple ||
        throw(ArgumentError("spatial vectors must be three-component collections"))
    length(x) == 3 || throw(ArgumentError("spatial vectors must have exactly three components"))
    result = SVector{3,T}(x)
    all(isfinite, result) || throw(ArgumentError("spatial vectors must contain only finite values"))
    return result
end

@inline function _spatial_dot(first::SVector{3,T}, second::SVector{3,T}) where {T<:AbstractFloat}
    return muladd(first[1], second[1], muladd(first[2], second[2], first[3] * second[3]))
end

@inline _spatial_norm(vector::SVector{3,T}) where {T<:AbstractFloat} =
    hypot(vector[1], vector[2], vector[3])

@inline function _spatial_norm2(vector::SVector{3,T}) where {T<:AbstractFloat}
    magnitude = _spatial_norm(vector)
    return magnitude * magnitude
end

@inline _wide_precision(::Type{Float16}) = 128
@inline _wide_precision(::Type{Float32}) = 192
@inline _wide_precision(::Type{Float64}) = 256
@inline _wide_precision(::Type{BigFloat}) = max(precision(BigFloat), 256)
@inline _wide_precision(::Type{T}) where {T<:AbstractFloat} = max(4 * precision(T), 256)

function _validate_real_tolerance(
    name::AbstractString,
    value::Real,
    ::Type{T};
    allow_zero::Bool,
    less_than_one::Bool=false,
) where {T<:AbstractFloat}
    converted = try
        T(value)
    catch error
        error isa InexactError || error isa OverflowError || rethrow()
        throw(ArgumentError("$name cannot be represented by the numeric type"))
    end
    isfinite(converted) || throw(ArgumentError("$name must be finite"))
    if allow_zero
        converted >= zero(T) || throw(ArgumentError("$name must be nonnegative"))
    else
        converted > zero(T) || throw(ArgumentError("$name must be strictly positive"))
    end
    less_than_one && converted >= one(T) && throw(ArgumentError("$name must be less than one"))
    return converted
end

@inline function _beta_norm(
    spacetime::MinkowskiSpacetime{T},
    velocity::SVector{3,T},
) where {T<:AbstractFloat}
    return hypot(
        velocity[1] / spacetime.c,
        velocity[2] / spacetime.c,
        velocity[3] / spacetime.c,
    )
end

@inline function _gamma_from_beta(beta::T) where {T<:AbstractFloat}
    zero(T) <= beta < one(T) ||
        throw(NumericalConditioningError("Lorentz factor requires a representably subluminal beta"))
    rate = sqrt((one(T) - beta) * (one(T) + beta))
    rate > zero(T) || throw(NumericalConditioningError("proper-time rate rounded to zero"))
    gamma = inv(rate)
    isfinite(gamma) || throw(NumericalConditioningError("Lorentz factor is not representable"))
    return gamma
end

@inline function _events_exactly_coincident(first::SpacetimeEvent, second::SpacetimeEvent)
    return first.t == second.t && first.x == second.x
end

function _wide_interval_parts(
    spacetime::MinkowskiSpacetime{T},
    first::SpacetimeEvent{T},
    second::SpacetimeEvent{T},
) where {T<:AbstractFloat}
    return setprecision(BigFloat, _wide_precision(T)) do
        dt = BigFloat(second.t) - BigFloat(first.t)
        dx1 = BigFloat(second.x[1]) - BigFloat(first.x[1])
        dx2 = BigFloat(second.x[2]) - BigFloat(first.x[2])
        dx3 = BigFloat(second.x[3]) - BigFloat(first.x[3])
        temporal = (BigFloat(spacetime.c) * dt)^2
        spatial = dx1^2 + dx2^2 + dx3^2
        return temporal - spatial, temporal + spatial
    end
end

"""
    interval_squared(spacetime, first, second)

Squared Minkowski interval. Intermediate computation uses extended precision;
if the dimensionful result cannot be represented in `T`, a conditioning error
is raised rather than returning a misleading zero or infinity. Use
`scaled_interval_residual` or `causal_relation` for extreme-scale diagnostics.
"""
function interval_squared(
    spacetime::MinkowskiSpacetime{T},
    first::SpacetimeEvent{T},
    second::SpacetimeEvent{T},
) where {T<:AbstractFloat}
    interval, _ = _wide_interval_parts(spacetime, first, second)
    result = T(interval)
    isfinite(result) || throw(NumericalConditioningError("squared interval is not representable"))
    if iszero(result) && !iszero(interval)
        throw(NumericalConditioningError("nonzero squared interval underflows the coordinate type"))
    end
    return result
end

"""Dimensionless `|s²|/(c²Δt²+||Δx||²)`, evaluated without squared overflow."""
function scaled_interval_residual(
    spacetime::MinkowskiSpacetime{T},
    first::SpacetimeEvent{T},
    second::SpacetimeEvent{T},
) where {T<:AbstractFloat}
    _events_exactly_coincident(first, second) && return zero(T)
    interval, scale = _wide_interval_parts(spacetime, first, second)
    iszero(scale) && throw(NumericalConditioningError("distinct events have an unresolvable interval scale"))
    return T(abs(interval) / scale)
end

"""Euclidean coordinate-frame spatial separation, using scaled `hypot`."""
function spatial_distance(first::SpacetimeEvent{T}, second::SpacetimeEvent{T}) where {T}
    distance = _spatial_norm(second.x - first.x)
    isfinite(distance) || throw(NumericalConditioningError("spatial distance is not representable"))
    return distance
end

"""Scale-safe causal classification with an explicit dimensionless tolerance."""
function causal_relation(
    spacetime::MinkowskiSpacetime{T},
    first::SpacetimeEvent{T},
    second::SpacetimeEvent{T};
    tolerance::Real=T(64) * eps(T),
) where {T<:AbstractFloat}
    threshold = _validate_real_tolerance(
        "causal tolerance",
        tolerance,
        T;
        allow_zero=true,
        less_than_one=true,
    )
    _events_exactly_coincident(first, second) && return :coincident
    interval, scale = _wide_interval_parts(spacetime, first, second)
    iszero(scale) && throw(NumericalConditioningError("distinct events have an unresolvable interval scale"))
    signed_scaled = interval / scale
    wide_threshold = BigFloat(threshold)
    if signed_scaled < -wide_threshold
        return :spacelike
    elseif abs(signed_scaled) <= wide_threshold
        return second.t > first.t ? :future_null : :past_null
    else
        return second.t > first.t ? :future_timelike : :past_timelike
    end
end

function is_future_causal(
    spacetime::MinkowskiSpacetime{T},
    first::SpacetimeEvent{T},
    second::SpacetimeEvent{T};
    tolerance::Real=T(64) * eps(T),
) where {T<:AbstractFloat}
    relation = causal_relation(spacetime, first, second; tolerance=tolerance)
    return relation === :coincident || relation === :future_null || relation === :future_timelike
end

function minkowski_interval2(tA::Real, xA, tB::Real, xB, c_sim::Real)
    spacetime = MinkowskiSpacetime(c_sim)
    T = typeof(spacetime.c)
    first = SpacetimeEvent{T}(T(tA), _spatial_vector(T, xA))
    second = SpacetimeEvent{T}(T(tB), _spatial_vector(T, xB))
    return interval_squared(spacetime, first, second)
end
