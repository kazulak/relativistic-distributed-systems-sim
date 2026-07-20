"""Abstract future-directed timelike trajectory in a coordinate frame."""
abstract type AbstractWorldline{T<:AbstractFloat} end

"""Raised when a supplied trajectory is non-finite, non-timelike, or internally inconsistent."""
struct InvalidWorldlineError <: Exception
    message::String
end

Base.showerror(io::IO, error::InvalidWorldlineError) = print(io, error.message)

@inline function _validate_velocity(
    spacetime::MinkowskiSpacetime{T},
    velocity::SVector{3,T},
) where {T<:AbstractFloat}
    all(isfinite, velocity) ||
        throw(InvalidWorldlineError("worldline coordinate velocity must be finite"))
    beta = _beta_norm(spacetime, velocity)
    isfinite(beta) || throw(InvalidWorldlineError("worldline beta is not finite"))
    beta < one(T) || throw(
        InvalidWorldlineError(
            "worldline must be timelike: coordinate speed must be strictly less than c",
        ),
    )
    return velocity
end

function is_timelike_velocity(spacetime::MinkowskiSpacetime{T}, velocity) where {T<:AbstractFloat}
    converted = try
        _spatial_vector(T, velocity)
    catch error
        if error isa ArgumentError || error isa InexactError || error isa MethodError
            return false
        end
        rethrow()
    end
    return isfinite(_beta_norm(spacetime, converted)) && _beta_norm(spacetime, converted) < one(T)
end

"""Future-directed inertial trajectory through `origin` with constant coordinate velocity."""
struct InertialWorldline{T<:AbstractFloat} <: AbstractWorldline{T}
    origin::SpacetimeEvent{T}
    velocity::SVector{3,T}
    c::T

    function InertialWorldline{T}(
        origin::SpacetimeEvent{T},
        velocity::SVector{3,T},
        c::T,
    ) where {T<:AbstractFloat}
        spacetime = MinkowskiSpacetime{T}(c)
        _validate_velocity(spacetime, velocity)
        return new{T}(origin, velocity, c)
    end
end

function InertialWorldline(
    spacetime::MinkowskiSpacetime{T},
    origin::SpacetimeEvent{T},
    velocity,
) where {T<:AbstractFloat}
    converted = try
        _spatial_vector(T, velocity)
    catch error
        if error isa ArgumentError || error isa InexactError || error isa MethodError
            throw(InvalidWorldlineError("inertial velocity must be a finite three-vector"))
        end
        rethrow()
    end
    return InertialWorldline{T}(origin, converted, spacetime.c)
end

function InertialWorldline(
    spacetime::MinkowskiSpacetime{T},
    initial_position,
    velocity;
    t0::Real=zero(T),
) where {T<:AbstractFloat}
    coordinate_time = T(t0)
    isfinite(coordinate_time) || throw(ArgumentError("inertial reference time must be finite"))
    origin = SpacetimeEvent{T}(coordinate_time, _spatial_vector(T, initial_position))
    return InertialWorldline(spacetime, origin, velocity)
end

"""
User-supplied coordinate-time trajectory. `consistency` is deliberately
mandatory: use `:assumed` to record an external modeling assumption, or
`:audited` with `audit_times` to numerically compare `dx/dt` to the supplied
velocity function at construction.
"""
struct ParametricWorldline{T<:AbstractFloat,P,V} <: AbstractWorldline{T}
    position_function::P
    velocity_function::V
    c::T
    tmin::T
    tmax::T
    consistency::Symbol

    function ParametricWorldline{T,P,V}(
        position_function::P,
        velocity_function::V,
        c::T,
        tmin::T,
        tmax::T,
        consistency::Symbol,
    ) where {T<:AbstractFloat,P,V}
        isnan(tmin) && throw(ArgumentError("worldline lower coordinate bound cannot be NaN"))
        isnan(tmax) && throw(ArgumentError("worldline upper coordinate bound cannot be NaN"))
        tmin <= tmax || throw(ArgumentError("worldline bounds must satisfy tmin <= tmax"))
        consistency in (:assumed, :audited) ||
            throw(ArgumentError("consistency must be :assumed or :audited"))
        MinkowskiSpacetime{T}(c)
        return new{T,P,V}(position_function, velocity_function, c, tmin, tmax, consistency)
    end
end

function ParametricWorldline(
    spacetime::MinkowskiSpacetime{T},
    position_function::P,
    velocity_function::V;
    consistency::Symbol,
    tmin::Real=-T(Inf),
    tmax::Real=T(Inf),
    validate_at=nothing,
    audit_times=nothing,
    audit_rtol::Real=sqrt(eps(T)),
    audit_atol::Real=zero(T),
) where {T<:AbstractFloat,P,V}
    worldline = ParametricWorldline{T,P,V}(
        position_function,
        velocity_function,
        spacetime.c,
        T(tmin),
        T(tmax),
        consistency,
    )
    if validate_at !== nothing
        position_at(worldline, T(validate_at))
        coordinate_velocity(worldline, T(validate_at))
    end
    if consistency === :audited
        audit_times === nothing &&
            throw(ArgumentError("consistency=:audited requires explicit audit_times"))
        audit_worldline(
            spacetime,
            worldline,
            audit_times;
            rtol=audit_rtol,
            atol=audit_atol,
        )
    elseif audit_times !== nothing
        throw(ArgumentError("audit_times requires consistency=:audited"))
    end
    return worldline
end

"""One-dimensional hyperbolic motion with constant proper-acceleration magnitude."""
struct UniformlyAcceleratedWorldline{T<:AbstractFloat} <: AbstractWorldline{T}
    origin::SpacetimeEvent{T}
    direction::SVector{3,T}
    proper_acceleration::T
    c::T

    function UniformlyAcceleratedWorldline{T}(
        origin::SpacetimeEvent{T},
        direction::SVector{3,T},
        proper_acceleration::T,
        c::T,
    ) where {T<:AbstractFloat}
        spacetime = MinkowskiSpacetime{T}(c)
        all(isfinite, direction) ||
            throw(InvalidWorldlineError("acceleration direction must be finite"))
        direction_scale = maximum(abs, direction)
        isfinite(direction_scale) && direction_scale > zero(T) ||
            throw(InvalidWorldlineError("acceleration direction must be finite and nonzero"))
        isfinite(proper_acceleration) && proper_acceleration > zero(T) ||
            throw(InvalidWorldlineError("proper acceleration must be finite and strictly positive"))
        scaled_direction = direction / direction_scale
        scaled_norm = _spatial_norm(scaled_direction)
        normalized = scaled_direction / scaled_norm
        _validate_velocity(spacetime, zero(normalized))
        return new{T}(origin, normalized, proper_acceleration, c)
    end
end

function UniformlyAcceleratedWorldline(
    spacetime::MinkowskiSpacetime{T},
    origin::SpacetimeEvent{T},
    direction,
    proper_acceleration::Real,
) where {T<:AbstractFloat}
    converted_acceleration = T(proper_acceleration)
    return UniformlyAcceleratedWorldline{T}(
        origin,
        _spatial_vector(T, direction),
        converted_acceleration,
        spacetime.c,
    )
end

@inline coordinate_domain(::InertialWorldline{T}) where {T} = (-T(Inf), T(Inf))
@inline coordinate_domain(worldline::ParametricWorldline) = (worldline.tmin, worldline.tmax)
@inline coordinate_domain(::UniformlyAcceleratedWorldline{T}) where {T} = (-T(Inf), T(Inf))

@inline reference_coordinate_time(worldline::InertialWorldline) = worldline.origin.t
@inline reference_coordinate_time(worldline::UniformlyAcceleratedWorldline) = worldline.origin.t
function reference_coordinate_time(worldline::ParametricWorldline{T}) where {T}
    worldline.tmin <= zero(T) <= worldline.tmax && return zero(T)
    isfinite(worldline.tmin) && return worldline.tmin
    isfinite(worldline.tmax) && return worldline.tmax
    return zero(T)
end

@inline function _check_coordinate_domain(worldline::AbstractWorldline{T}, t::T) where {T}
    isfinite(t) || throw(DomainError(t, "worldline coordinate time must be finite"))
    tmin, tmax = coordinate_domain(worldline)
    tmin <= t <= tmax || throw(DomainError(t, "coordinate time lies outside the worldline domain"))
    return t
end

function position_at(worldline::InertialWorldline{T}, t::Real) where {T}
    coordinate_time = T(t)
    _check_coordinate_domain(worldline, coordinate_time)
    displacement = worldline.velocity * (coordinate_time - worldline.origin.t)
    position = worldline.origin.x + displacement
    all(isfinite, position) || throw(NumericalConditioningError("inertial position is not representable"))
    any(value -> !iszero(value), displacement) && position == worldline.origin.x && throw(
        NumericalConditioningError("inertial displacement is below position resolution"),
    )
    return position
end

function position_at(worldline::ParametricWorldline{T}, t::Real) where {T}
    coordinate_time = T(t)
    _check_coordinate_domain(worldline, coordinate_time)
    return _spatial_vector(T, worldline.position_function(coordinate_time))
end

function position_at(worldline::UniformlyAcceleratedWorldline{T}, t::Real) where {T}
    coordinate_time = T(t)
    _check_coordinate_domain(worldline, coordinate_time)
    dt = coordinate_time - worldline.origin.t
    z = _acceleration_coordinate(worldline, dt)
    root = hypot(one(T), z)
    ratio = z / (root + one(T))
    displacement = dt * (worldline.c * ratio)
    dt != zero(T) && z != zero(T) && displacement == zero(T) && throw(
        NumericalConditioningError("accelerated displacement underflows the coordinate type"),
    )
    position = worldline.origin.x + worldline.direction * displacement
    all(isfinite, position) ||
        throw(NumericalConditioningError("accelerated position is not representable"))
    displacement != zero(T) && position == worldline.origin.x && throw(
        NumericalConditioningError("accelerated displacement is below position resolution"),
    )
    return position
end

function coordinate_velocity(worldline::InertialWorldline{T}, t::Real) where {T}
    _check_coordinate_domain(worldline, T(t))
    return worldline.velocity
end

function coordinate_velocity(worldline::ParametricWorldline{T}, t::Real) where {T}
    coordinate_time = T(t)
    _check_coordinate_domain(worldline, coordinate_time)
    converted = try
        _spatial_vector(T, worldline.velocity_function(coordinate_time))
    catch error
        if error isa ArgumentError || error isa InexactError || error isa MethodError
            throw(InvalidWorldlineError("parametric velocity must be a finite three-vector"))
        end
        rethrow()
    end
    return _validate_velocity(MinkowskiSpacetime{T}(worldline.c), converted)
end

function coordinate_velocity(worldline::UniformlyAcceleratedWorldline{T}, t::Real) where {T}
    coordinate_time = T(t)
    _check_coordinate_domain(worldline, coordinate_time)
    z = _acceleration_coordinate(worldline, coordinate_time - worldline.origin.t)
    fraction = z / hypot(one(T), z)
    abs(fraction) < one(T) || throw(
        NumericalConditioningError("accelerated velocity is too near-null for the coordinate type"),
    )
    result = worldline.direction * (worldline.c * fraction)
    return _validate_velocity(MinkowskiSpacetime{T}(worldline.c), result)
end

function _acceleration_coordinate(
    worldline::UniformlyAcceleratedWorldline{T},
    coordinate_offset::T,
) where {T<:AbstractFloat}
    wide = setprecision(BigFloat, _wide_precision(T)) do
        BigFloat(worldline.proper_acceleration) * BigFloat(coordinate_offset) /
        BigFloat(worldline.c)
    end
    result = T(wide)
    isfinite(result) ||
        throw(NumericalConditioningError("accelerated rapidity coordinate is not representable"))
    if coordinate_offset != zero(T) && !iszero(wide) && iszero(result)
        throw(NumericalConditioningError("accelerated rapidity coordinate underflows"))
    end
    return result
end

function worldline_event(worldline::AbstractWorldline{T}, t::Real) where {T}
    coordinate_time = T(t)
    return SpacetimeEvent{T}(coordinate_time, position_at(worldline, coordinate_time))
end

@inline position(worldline::AbstractWorldline, t::Real) = position_at(worldline, t)
@inline velocity(worldline::AbstractWorldline, t::Real) = coordinate_velocity(worldline, t)

function _check_spacetime(worldline::AbstractWorldline{T}, spacetime::MinkowskiSpacetime{T}) where {T}
    worldline.c == spacetime.c ||
        throw(ArgumentError("worldline and spacetime must use exactly the same c"))
    return nothing
end

"""
    audit_worldline(spacetime, worldline, times; rtol, atol, relative_step)

Finite-difference audit that the supplied coordinate velocity agrees with the
derivative of position at declared sample times. Passing samples is regression
evidence, not a proof over a continuous domain. Returns the maximum normalized
velocity discrepancy and throws `InvalidWorldlineError` on failure.
"""
function audit_worldline(
    spacetime::MinkowskiSpacetime{T},
    worldline::AbstractWorldline{T},
    times;
    rtol::Real=sqrt(eps(T)),
    atol::Real=zero(T),
    relative_step::Real=cbrt(eps(T)),
) where {T<:AbstractFloat}
    _check_spacetime(worldline, spacetime)
    relative_tolerance = _validate_real_tolerance(
        "worldline audit rtol",
        rtol,
        T;
        allow_zero=false,
        less_than_one=true,
    )
    absolute_tolerance = _validate_real_tolerance(
        "worldline audit atol",
        atol,
        T;
        allow_zero=true,
    )
    step_fraction = _validate_real_tolerance(
        "worldline audit relative_step",
        relative_step,
        T;
        allow_zero=false,
        less_than_one=true,
    )
    isempty(times) && throw(ArgumentError("worldline audit requires at least one sample time"))
    tmin, tmax = coordinate_domain(worldline)
    maximum_residual = zero(T)
    for raw_time in times
        sample_time = T(raw_time)
        _check_coordinate_domain(worldline, sample_time)
        step = step_fraction * max(abs(sample_time), one(T))
        left = max(tmin, sample_time - step)
        right = min(tmax, sample_time + step)
        left < sample_time < right || throw(
            NumericalConditioningError("audit sample lacks a representable two-sided increment"),
        )
        finite_difference = (position_at(worldline, right) - position_at(worldline, left)) /
                            (right - left)
        declared = coordinate_velocity(worldline, sample_time)
        error_norm = _spatial_norm(finite_difference - declared)
        velocity_scale = max(_spatial_norm(declared), _spatial_norm(finite_difference), spacetime.c * eps(T))
        residual = error_norm / velocity_scale
        maximum_residual = max(maximum_residual, residual)
        error_norm <= absolute_tolerance + relative_tolerance * velocity_scale || throw(
            InvalidWorldlineError(
                "position/velocity inconsistency at coordinate time $sample_time (residual=$residual)",
            ),
        )
    end
    return maximum_residual
end
