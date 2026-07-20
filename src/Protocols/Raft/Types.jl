const NodeID = Int
const Term = UInt64
const LogIndex = Int

@enum Role::UInt8 Follower Candidate Leader
@enum TimerKind::UInt8 ElectionTimer HeartbeatTimer

"""Static Raft configuration. Only the primary 3-, 5-, and 7-node sizes are accepted."""
struct RaftConfig
    members::Tuple{Vararg{NodeID}}
    election_timeout_min::Float64
    election_timeout_max::Float64
    heartbeat_interval::Float64
    append_batch_size::Int

    function RaftConfig(
        members::AbstractVector{<:Integer};
        election_timeout::Tuple{<:Real,<:Real}=(0.15, 0.30),
        heartbeat_interval::Real=0.05,
        append_batch_size::Integer=64,
    )
        member_ids = sort!(Int.(members))
        length(member_ids) in (3, 5, 7) ||
            throw(ArgumentError("Raft membership must contain exactly 3, 5, or 7 nodes"))
        all(>(0), member_ids) || throw(ArgumentError("node ids must be positive"))
        allunique(member_ids) || throw(ArgumentError("Raft membership contains duplicate node ids"))

        timeout_min = Float64(election_timeout[1])
        timeout_max = Float64(election_timeout[2])
        isfinite(timeout_min) && timeout_min > 0.0 ||
            throw(ArgumentError("minimum election timeout must be finite and positive"))
        isfinite(timeout_max) && timeout_max > timeout_min ||
            throw(ArgumentError("maximum election timeout must exceed the minimum"))
        heartbeat = Float64(heartbeat_interval)
        isfinite(heartbeat) && heartbeat > 0.0 ||
            throw(ArgumentError("heartbeat interval must be finite and positive"))
        append_batch_size > 0 || throw(ArgumentError("append_batch_size must be positive"))

        new(Tuple(member_ids), timeout_min, timeout_max, heartbeat, Int(append_batch_size))
    end
end

quorum_size(config::RaftConfig) = (length(config.members) >>> 1) + 1

struct RequestID
    client::UInt64
    sequence::UInt64
end

function RequestID(client::Integer, sequence::Integer)
    client >= 0 || throw(ArgumentError("client id must be non-negative"))
    sequence >= 0 || throw(ArgumentError("client sequence must be non-negative"))
    return RequestID(UInt64(client), UInt64(sequence))
end

Base.:(==)(left::RequestID, right::RequestID) =
    left.client == right.client && left.sequence == right.sequence
Base.isequal(left::RequestID, right::RequestID) = left == right
Base.hash(request::RequestID, seed::UInt) = hash(request.sequence, hash(request.client, seed))
Base.isless(left::RequestID, right::RequestID) =
    left.client == right.client ? left.sequence < right.sequence : left.client < right.client

abstract type Command end

struct PutCommand <: Command
    key::String
    value::String
end

PutCommand(key::AbstractString, value::AbstractString) = PutCommand(String(key), String(value))

struct DeleteCommand <: Command
    key::String
end

DeleteCommand(key::AbstractString) = DeleteCommand(String(key))

"""A linearizable read implemented as an ordinary replicated log command."""
struct GetCommand <: Command
    key::String
end

GetCommand(key::AbstractString) = GetCommand(String(key))

"""Internal command; the baseline does not automatically append no-op entries."""
struct NoOpCommand <: Command end

Base.:(==)(left::PutCommand, right::PutCommand) =
    left.key == right.key && left.value == right.value
Base.:(==)(left::DeleteCommand, right::DeleteCommand) = left.key == right.key
Base.:(==)(left::GetCommand, right::GetCommand) = left.key == right.key
Base.:(==)(::NoOpCommand, ::NoOpCommand) = true

struct CommandResult
    status::Symbol
    value::Union{Nothing,String}
end

Base.:(==)(left::CommandResult, right::CommandResult) =
    left.status == right.status && left.value == right.value

struct LogEntry
    term::Term
    command::Command
    request_id::Union{Nothing,RequestID}
end

function LogEntry(term::Integer, command::Command, request_id::Union{Nothing,RequestID}=nothing)
    term >= 0 || throw(ArgumentError("log term must be non-negative"))
    command isa NoOpCommand && !isnothing(request_id) &&
        throw(ArgumentError("an internal no-op cannot carry a client request id"))
    !(command isa NoOpCommand) && isnothing(request_id) &&
        throw(ArgumentError("a client command requires a request id"))
    return LogEntry(UInt64(term), command, request_id)
end

Base.:(==)(left::LogEntry, right::LogEntry) =
    left.term == right.term && left.command == right.command && left.request_id == right.request_id

mutable struct DurableState
    current_term::Term
    voted_for::Union{Nothing,NodeID}
    log::Vector{LogEntry}

    function DurableState(
        current_term::Term,
        voted_for::Union{Nothing,NodeID},
        log::Vector{LogEntry},
    )
        !isnothing(voted_for) && voted_for <= 0 &&
            throw(ArgumentError("voted_for must be a positive node id"))
        all(entry -> entry.term <= current_term, log) ||
            throw(ArgumentError("durable log contains an entry from a future term"))
        new(current_term, voted_for, copy(log))
    end
end

"""Metadata retained by a leader for one in-flight AppendEntries probe."""
struct AppendProbe
    rpc_id::UInt64
    prev_log_index::LogIndex
    last_log_index::LogIndex

    function AppendProbe(rpc_id::UInt64, prev_log_index::LogIndex, last_log_index::LogIndex)
        prev_log_index >= 0 || throw(ArgumentError("append probe prev_log_index must be non-negative"))
        last_log_index >= prev_log_index ||
            throw(ArgumentError("append probe last_log_index cannot precede prev_log_index"))
        new(rpc_id, prev_log_index, last_log_index)
    end
end

function DurableState(
    current_term::Integer=0,
    voted_for::Union{Nothing,Integer}=nothing,
    log::AbstractVector{LogEntry}=LogEntry[],
)
    current_term >= 0 || throw(ArgumentError("current term must be non-negative"))
    vote = isnothing(voted_for) ? nothing : Int(voted_for)
    !isnothing(vote) && vote <= 0 && throw(ArgumentError("voted_for must be a positive node id"))
    entries = collect(log)
    all(entry -> entry.term <= current_term, entries) ||
        throw(ArgumentError("durable log contains an entry from a future term"))
    return DurableState(UInt64(current_term), vote, entries)
end

struct DurableSnapshot
    current_term::Term
    voted_for::Union{Nothing,NodeID}
    log::Vector{LogEntry}
end

DurableSnapshot(state::DurableState) =
    DurableSnapshot(state.current_term, state.voted_for, copy(state.log))

Base.:(==)(left::DurableSnapshot, right::DurableSnapshot) =
    left.current_term == right.current_term &&
    left.voted_for == right.voted_for &&
    left.log == right.log

struct AppliedRecord
    index::LogIndex
    command::Command
    result::CommandResult
end

Base.:(==)(left::AppliedRecord, right::AppliedRecord) =
    left.index == right.index && left.command == right.command && left.result == right.result

mutable struct VolatileState
    role::Role
    leader_id::Union{Nothing,NodeID}
    commit_index::LogIndex
    last_applied::LogIndex
    next_index::Dict{NodeID,LogIndex}
    match_index::Dict{NodeID,LogIndex}
    append_rpc_counter::Dict{NodeID,UInt64}
    active_append_rpc::Dict{NodeID,UInt64}
    latest_success_rpc::Dict{NodeID,UInt64}
    append_probes::Dict{Tuple{NodeID,UInt64},AppendProbe}
    votes_received::Set{NodeID}
    state_machine::Dict{String,String}
    applied_requests::Dict{RequestID,AppliedRecord}
    pending_clients::Set{RequestID}
    election_generation::UInt64
    heartbeat_generation::UInt64
    election_deadline::Float64
    heartbeat_deadline::Float64
end

function VolatileState()
    return VolatileState(
        Follower,
        nothing,
        0,
        0,
        Dict{NodeID,LogIndex}(),
        Dict{NodeID,LogIndex}(),
        Dict{NodeID,UInt64}(),
        Dict{NodeID,UInt64}(),
        Dict{NodeID,UInt64}(),
        Dict{Tuple{NodeID,UInt64},AppendProbe}(),
        Set{NodeID}(),
        Dict{String,String}(),
        Dict{RequestID,AppliedRecord}(),
        Set{RequestID}(),
        0,
        0,
        Inf,
        Inf,
    )
end

mutable struct RaftNode
    id::NodeID
    config::RaftConfig
    durable::DurableState
    volatile::VolatileState
    running::Bool
    crash_epoch::UInt64
    last_local_time::Float64

    function RaftNode(
        id::Integer,
        config::RaftConfig;
        durable::DurableState=DurableState(),
        running::Bool=true,
    )
        node_id = Int(id)
        node_id in config.members || throw(ArgumentError("node id is not in the static membership"))
        !isnothing(durable.voted_for) && !(durable.voted_for in config.members) &&
            throw(ArgumentError("durable vote is outside the static membership"))
        owned_durable = DurableState(
            durable.current_term,
            durable.voted_for,
            durable.log,
        )
        new(node_id, config, owned_durable, VolatileState(), running, 0, -Inf)
    end
end

last_log_index(node::RaftNode) = length(node.durable.log)
last_log_term(node::RaftNode) = isempty(node.durable.log) ? zero(Term) : node.durable.log[end].term

function peer_ids(node::RaftNode)
    return (member for member in node.config.members if member != node.id)
end
