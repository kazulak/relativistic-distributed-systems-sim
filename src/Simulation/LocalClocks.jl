abstract type AbstractLocalClock end

"""
An affine monotonic local clock `local = offset + rate * coordinate`.

It is a small adapter for stationary tests and controlled drift experiments.
Relativistic proper-time clocks can implement the same `local_time` and
`coordinate_time` interface without exposing coordinate time to protocols.
"""
struct AffineLocalClock <: AbstractLocalClock
    rate::Float64
    offset::Float64

    function AffineLocalClock(rate::Real=1.0, offset::Real=0.0)
        clock_rate = Float64(rate)
        clock_offset = Float64(offset)
        isfinite(clock_rate) && clock_rate > 0.0 ||
            throw(ArgumentError("local clock rate must be finite and positive"))
        isfinite(clock_offset) || throw(ArgumentError("local clock offset must be finite"))
        new(clock_rate, clock_offset)
    end
end

local_time(clock::AffineLocalClock, coordinate::Real) = clock.offset + clock.rate * Float64(coordinate)
coordinate_time(clock::AffineLocalClock, local_value::Real) =
    (Float64(local_value) - clock.offset) / clock.rate

function schedule_local_timer!(
    scheduler::Scheduler,
    clock::AbstractLocalClock,
    local_deadline::Real,
    target::Integer,
    timer::Symbol,
    generation::Integer;
    causal_parent::Union{Nothing,Integer}=nothing,
)
    generation >= 0 || throw(ArgumentError("timer generation must be non-negative"))
    coordinate_deadline = coordinate_time(clock, local_deadline)
    coordinate_deadline + 8eps(max(abs(coordinate_deadline), 1.0)) >= scheduler.now ||
        throw(ArgumentError("local timer deadline maps into the scheduler past"))
    coordinate_deadline = max(coordinate_deadline, scheduler.now)
    return schedule!(
        scheduler,
        coordinate_deadline,
        target,
        TimerFired(timer, UInt64(generation));
        causal_parent=causal_parent,
    )
end
