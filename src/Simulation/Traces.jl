"""Append-only scheduler trace record containing no mutable payload reference."""
struct TraceRecord
    event_id::UInt64
    coordinate_time::Float64
    target::Int
    payload_type::Symbol
    causal_parent::Union{Nothing,UInt64}
end

struct InvalidTraceError <: Exception
    message::String
end

Base.showerror(io::IO, error::InvalidTraceError) = print(io, error.message)

mutable struct EventTrace
    _records::Vector{TraceRecord}
    _by_id::Dict{UInt64,TraceRecord}

    EventTrace() = new(TraceRecord[], Dict{UInt64,TraceRecord}())
end

Base.length(trace::EventTrace) = length(trace._records)
Base.isempty(trace::EventTrace) = isempty(trace._records)

"""Return a copy so callers cannot mutate the append-only trace storage."""
trace_records(trace::EventTrace) = copy(trace._records)

function record!(trace::EventTrace, event::ScheduledEvent)
    haskey(trace._by_id, event.event_id) &&
        throw(InvalidTraceError("trace already contains event id $(event.event_id)"))
    if !isnothing(event.causal_parent)
        parent = get(trace._by_id, event.causal_parent, nothing)
        isnothing(parent) && throw(
            InvalidTraceError(
                "causal parent $(event.causal_parent) must be recorded before event $(event.event_id)",
            ),
        )
        parent.coordinate_time <= event.time || throw(
            InvalidTraceError("causal child $(event.event_id) precedes its parent"),
        )
    end
    record = TraceRecord(
        event.event_id,
        event.time,
        event.target,
        Symbol(nameof(typeof(event.payload))),
        event.causal_parent,
    )
    push!(trace._records, record)
    trace._by_id[record.event_id] = record
    return record
end


"""Revalidate parent existence, append order, uniqueness, and causal time order."""
function validate_trace(trace::EventTrace)
    seen = Dict{UInt64,TraceRecord}()
    for record in trace._records
        haskey(seen, record.event_id) &&
            throw(InvalidTraceError("trace contains duplicate event id $(record.event_id)"))
        if !isnothing(record.causal_parent)
            parent = get(seen, record.causal_parent, nothing)
            isnothing(parent) && throw(
                InvalidTraceError(
                    "trace event $(record.event_id) has a missing or forward causal parent",
                ),
            )
            parent.coordinate_time <= record.coordinate_time || throw(
                InvalidTraceError("trace event $(record.event_id) precedes its causal parent"),
            )
        end
        seen[record.event_id] = record
    end
    length(seen) == length(trace._by_id) ||
        throw(InvalidTraceError("trace index and append-only records disagree"))
    for (event_id, record) in seen
        get(trace._by_id, event_id, nothing) == record ||
            throw(InvalidTraceError("trace index contains inconsistent record $event_id"))
    end
    return true
end
