abstract type FaultEvent end

"""Crash a node while retaining its explicitly durable protocol state."""
struct CrashNode <: FaultEvent
    node::Int

    function CrashNode(node::Integer)
        node > 0 || throw(ArgumentError("crashed node id must be positive"))
        new(Int(node))
    end
end

"""Recover a previously crashed node from its durable protocol state."""
struct RecoverNode <: FaultEvent
    node::Int

    function RecoverNode(node::Integer)
        node > 0 || throw(ArgumentError("recovered node id must be positive"))
        new(Int(node))
    end
end

"""An explicit directed-link availability change for a scenario driver."""
struct SetLinkAvailability <: FaultEvent
    from::Int
    to::Int
    available::Bool

    function SetLinkAvailability(from::Integer, to::Integer, available::Bool)
        from > 0 && to > 0 && from != to ||
            throw(ArgumentError("link endpoints must be distinct positive node ids"))
        new(Int(from), Int(to), available)
    end
end

function schedule_fault!(scheduler::Scheduler, time::Real, fault::FaultEvent)
    target = fault isa SetLinkAvailability ? fault.to : fault.node
    return schedule!(scheduler, time, target, fault)
end
