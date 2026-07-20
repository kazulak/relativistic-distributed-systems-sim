"""A typed immutable transport envelope."""
struct MessageEnvelope{M}
    message_id::UInt64
    from::Int
    to::Int
    payload::M
end

function MessageEnvelope(message_id::Integer, from::Integer, to::Integer, payload)
    message_id >= 0 || throw(ArgumentError("message id must be non-negative"))
    from > 0 || throw(ArgumentError("message sender must be positive"))
    to > 0 || throw(ArgumentError("message recipient must be positive"))
    from != to || throw(ArgumentError("transport messages must cross node boundaries"))
    return MessageEnvelope(UInt64(message_id), Int(from), Int(to), payload)
end

"""One delivered copy of an envelope; `copy` distinguishes duplication."""
struct MessageDelivery{M}
    envelope::MessageEnvelope{M}
    copy::UInt32
end

"""
An exogenous delivery decision for one sent message.

An empty vector means loss. Multiple times mean duplication. Arbitrary times
across plans permit reordering. Physics/contact models, rather than this generic
transport layer, are responsible for producing causally admissible times.
"""
struct DeliveryPlan
    arrival_times::Vector{Float64}

    function DeliveryPlan(arrival_times::AbstractVector{<:Real})
        times = Float64.(arrival_times)
        all(isfinite, times) || throw(ArgumentError("delivery times must be finite"))
        new(times)
    end
end

DeliveryPlan() = DeliveryPlan(Float64[])

is_dropped(plan::DeliveryPlan) = isempty(plan.arrival_times)

"""Raised when an integrated transport validator rejects a planned arrival."""
struct InvalidDeliveryError <: Exception
    message::String
end

Base.showerror(io::IO, error::InvalidDeliveryError) = print(io, error.message)

"""Directed-link state consumed by the integrated transmission hook."""
mutable struct TransportState
    link_available::Dict{Tuple{Int,Int},Bool}
end

TransportState() = TransportState(Dict{Tuple{Int,Int},Bool}())

is_link_available(state::TransportState, from::Integer, to::Integer) =
    get(state.link_available, (Int(from), Int(to)), true)

function apply_fault!(state::TransportState, fault::SetLinkAvailability)
    state.link_available[(fault.from, fault.to)] = fault.available
    return state
end

function enqueue_deliveries!(
    scheduler::Scheduler,
    envelope::MessageEnvelope,
    plan::DeliveryPlan;
    causal_parent::Union{Nothing,Integer}=nothing,
)
    events = ScheduledEvent[]
    for (copy, arrival) in enumerate(plan.arrival_times)
        copy <= typemax(UInt32) || throw(OverflowError("too many duplicate message copies"))
        event = schedule!(
            scheduler,
            arrival,
            envelope.to,
            MessageDelivery(envelope, UInt32(copy));
            causal_parent=causal_parent,
        )
        push!(events, event)
    end
    return events
end

"""
Apply current directed-link availability and enqueue a validated transmission.

The required `causal_parent` names the already-scheduled send event; the
scheduler verifies parent existence and coordinate-time order. A Physics-layer
caller can additionally supply `delivery_validator(envelope, arrival_time)` to
enforce a light-cone/contact model without coupling this module to Physics.
Unavailable links produce an explicit dropped outcome (an empty event vector).
"""
function enqueue_transmission!(
    scheduler::Scheduler,
    transport::TransportState,
    envelope::MessageEnvelope,
    plan::DeliveryPlan;
    causal_parent::Integer,
    delivery_validator=nothing,
)
    is_link_available(transport, envelope.from, envelope.to) || return ScheduledEvent[]
    for arrival in plan.arrival_times
        if delivery_validator !== nothing
            accepted = delivery_validator(envelope, arrival)
            accepted === true || throw(
                InvalidDeliveryError(
                    "delivery validator rejected message $(envelope.message_id) at $arrival",
                ),
            )
        end
    end
    return enqueue_deliveries!(
        scheduler,
        envelope,
        plan;
        causal_parent=causal_parent,
    )
end
