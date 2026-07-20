"""
An event held by the discrete-event scheduler.

`sequence` is a scheduler-private tie breaker.  Consumers should deliver only
`payload` (and, when useful for tracing, `event_id`) to a node; protocol state
must never depend on `sequence`.
"""
struct ScheduledEvent
    time::Float64
    _order_token::UInt64
    event_id::UInt64
    target::Int
    payload::Any
    causal_parent::Union{Nothing,UInt64}
end

function Base.isless(left::ScheduledEvent, right::ScheduledEvent)
    left.time == right.time && return left._order_token < right._order_token
    return left.time < right.time
end

"""A generation-tagged firing of a node-local timer."""
struct TimerFired
    timer::Symbol
    generation::UInt64
end

"""A marker useful for deterministic scenario events that have no payload."""
struct ScenarioMarker
    name::Symbol
end
