"""
An ideal node clock whose reading is proper time accumulated on `worldline`.

`coordinate_origin` and `local_origin` make the chosen zero explicit.  The
research engine uses origins at the simulation start, but retaining both makes
the adapter useful for restart and frame-transform validation.
"""
struct ProperTimeClock{T<:AbstractFloat,W<:AbstractWorldline{T}} <: AbstractLocalClock
    spacetime::MinkowskiSpacetime{T}
    worldline::W
    coordinate_origin::T
    local_origin::T

    function ProperTimeClock(
        spacetime::MinkowskiSpacetime{T},
        worldline::W;
        coordinate_origin::Real=zero(T),
        local_origin::Real=zero(T),
    ) where {T<:AbstractFloat,W<:AbstractWorldline{T}}
        coordinate = T(coordinate_origin)
        local_value = T(local_origin)
        isfinite(coordinate) || throw(ArgumentError("clock coordinate origin must be finite"))
        isfinite(local_value) || throw(ArgumentError("clock local origin must be finite"))
        # This also validates that the origin lies in the worldline domain and
        # that the worldline uses the same signal speed.
        proper_time_between(spacetime, worldline, coordinate, coordinate)
        new{T,W}(spacetime, worldline, coordinate, local_value)
    end
end

function SimulationCore.local_time(clock::ProperTimeClock{T}, coordinate::Real) where {T}
    coordinate_value = T(coordinate)
    elapsed = proper_time_between(
        clock.spacetime,
        clock.worldline,
        clock.coordinate_origin,
        coordinate_value,
    )
    result = clock.local_origin + elapsed
    isfinite(result) || throw(OverflowError("proper-time clock reading is not finite"))
    return Float64(result)
end

function SimulationCore.coordinate_time(clock::ProperTimeClock{T}, local_value::Real) where {T}
    target = T(local_value)
    isfinite(target) || throw(ArgumentError("local clock target must be finite"))
    duration = target - clock.local_origin
    duration >= zero(T) || throw(
        ArgumentError("proper-time clock inversion before its declared origin is unsupported"),
    )
    return Float64(
        coordinate_time_after_proper_time(
            clock.spacetime,
            clock.worldline,
            clock.coordinate_origin,
            duration,
        ),
    )
end
