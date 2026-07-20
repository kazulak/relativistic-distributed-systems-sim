"""
Deterministic, heterogeneous discrete-event priority queue.

The queue orders equal coordinate-time events by insertion sequence solely to
make runs reproducible.  The sequence is not exposed through node-local Raft
inputs, so this bookkeeping cannot become protocol state.
"""
mutable struct Scheduler
    heap::Vector{ScheduledEvent}
    next_sequence::UInt64
    next_event_id::UInt64
    now::Float64
    event_times::Dict{UInt64,Float64}
end

Scheduler(; start_time::Real=0.0) = begin
    time = Float64(start_time)
    isfinite(time) || throw(ArgumentError("scheduler start_time must be finite"))
    Scheduler(ScheduledEvent[], 0, 0, time, Dict{UInt64,Float64}())
end

Base.isempty(scheduler::Scheduler) = isempty(scheduler.heap)
Base.length(scheduler::Scheduler) = length(scheduler.heap)

function _heap_push!(heap::Vector{ScheduledEvent}, event::ScheduledEvent)
    push!(heap, event)
    position = length(heap)
    while position > 1
        parent = position >>> 1
        isless(event, heap[parent]) || break
        heap[position] = heap[parent]
        position = parent
    end
    heap[position] = event
    return event
end

function _heap_pop!(heap::Vector{ScheduledEvent})
    isempty(heap) && throw(ArgumentError("cannot pop an empty scheduler"))
    first_event = heap[1]
    tail = pop!(heap)
    isempty(heap) && return first_event

    position = 1
    while true
        left = position << 1
        left > length(heap) && break
        right = left + 1
        child = right <= length(heap) && isless(heap[right], heap[left]) ? right : left
        isless(heap[child], tail) || break
        heap[position] = heap[child]
        position = child
    end
    heap[position] = tail
    return first_event
end

"""
Schedule `payload` at an absolute coordinate time.

`causal_parent` is trace metadata and does not alter ordering.  Scheduling into
the past is rejected, including after the scheduler has advanced.
"""
function schedule!(
    scheduler::Scheduler,
    time::Real,
    target::Integer,
    payload;
    causal_parent::Union{Nothing,Integer}=nothing,
)
    event_time = Float64(time)
    isfinite(event_time) || throw(ArgumentError("event time must be finite"))
    event_time >= scheduler.now || throw(ArgumentError("cannot schedule an event in the past"))
    target > 0 || throw(ArgumentError("event target must be positive"))

    !isnothing(causal_parent) && causal_parent < 0 &&
        throw(ArgumentError("causal parent id must be non-negative"))
    parent = isnothing(causal_parent) ? nothing : UInt64(causal_parent)
    if !isnothing(parent)
        parent_time = get(scheduler.event_times, parent, nothing)
        isnothing(parent_time) && throw(ArgumentError("causal parent is not a scheduled event"))
        parent_time <= event_time ||
            throw(ArgumentError("causal child cannot precede its parent in coordinate time"))
    end
    scheduler.next_sequence == typemax(UInt64) && throw(OverflowError("scheduler sequence exhausted"))
    scheduler.next_event_id == typemax(UInt64) && throw(OverflowError("scheduler event id exhausted"))
    scheduler.next_sequence += 1
    scheduler.next_event_id += 1
    event = ScheduledEvent(
        event_time,
        scheduler.next_sequence,
        scheduler.next_event_id,
        Int(target),
        payload,
        parent,
    )
    scheduler.event_times[event.event_id] = event.time
    return _heap_push!(scheduler.heap, event)
end

function schedule_after!(scheduler::Scheduler, delay::Real, target::Integer, payload; kwargs...)
    delay_value = Float64(delay)
    isfinite(delay_value) || throw(ArgumentError("event delay must be finite"))
    delay_value >= 0.0 || throw(ArgumentError("event delay must be non-negative"))
    return schedule!(scheduler, scheduler.now + delay_value, target, payload; kwargs...)
end

"""Remove and return the next event, advancing scheduler coordinate time."""
function pop_next!(scheduler::Scheduler)
    event = _heap_pop!(scheduler.heap)
    scheduler.now = event.time
    return event
end

"""Return the next event without advancing the scheduler."""
function peek_next(scheduler::Scheduler)
    isempty(scheduler) && throw(ArgumentError("cannot peek an empty scheduler"))
    return scheduler.heap[1]
end

"""Run events through `handler(event)` until the queue or horizon is exhausted."""
function run!(handler::F, scheduler::Scheduler; until::Real=Inf, max_events::Integer=typemax(Int)) where {F}
    horizon = Float64(until)
    isnan(horizon) && throw(ArgumentError("run horizon cannot be NaN"))
    max_events >= 0 || throw(ArgumentError("max_events must be non-negative"))
    processed = 0
    while !isempty(scheduler) && processed < max_events
        peek_next(scheduler).time > horizon && break
        handler(pop_next!(scheduler))
        processed += 1
    end
    return processed
end
