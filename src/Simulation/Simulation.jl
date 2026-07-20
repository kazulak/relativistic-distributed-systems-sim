module SimulationCore

include("Events.jl")
include("Scheduler.jl")
include("LocalClocks.jl")
include("Faults.jl")
include("Network.jl")
include("Traces.jl")

export ScheduledEvent,
    TimerFired,
    ScenarioMarker,
    Scheduler,
    schedule!,
    schedule_after!,
    pop_next!,
    peek_next,
    run!,
    AbstractLocalClock,
    AffineLocalClock,
    local_time,
    coordinate_time,
    schedule_local_timer!,
    MessageEnvelope,
    MessageDelivery,
    DeliveryPlan,
    is_dropped,
    enqueue_deliveries!,
    InvalidDeliveryError,
    TransportState,
    is_link_available,
    apply_fault!,
    enqueue_transmission!,
    FaultEvent,
    CrashNode,
    RecoverNode,
    SetLinkAvailability,
    schedule_fault!,
    TraceRecord,
    EventTrace,
    InvalidTraceError,
    trace_records,
    record!,
    validate_trace

end
