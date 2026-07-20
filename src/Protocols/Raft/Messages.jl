abstract type RaftMessage end

struct RequestVoteRequest <: RaftMessage
    term::Term
    candidate_id::NodeID
    last_log_index::LogIndex
    last_log_term::Term
end

function RequestVoteRequest(term::Integer, candidate_id::Integer, last_index::Integer, last_term::Integer)
    term >= 0 && last_index >= 0 && last_term >= 0 ||
        throw(ArgumentError("vote request terms and indices must be non-negative"))
    candidate_id > 0 || throw(ArgumentError("candidate id must be positive"))
    return RequestVoteRequest(UInt64(term), Int(candidate_id), Int(last_index), UInt64(last_term))
end

struct RequestVoteResponse <: RaftMessage
    term::Term
    voter_id::NodeID
    vote_granted::Bool
end

function RequestVoteResponse(term::Integer, voter_id::Integer, vote_granted::Bool)
    term >= 0 || throw(ArgumentError("vote response term must be non-negative"))
    voter_id > 0 || throw(ArgumentError("voter id must be positive"))
    return RequestVoteResponse(UInt64(term), Int(voter_id), vote_granted)
end

struct AppendEntriesRequest <: RaftMessage
    term::Term
    leader_id::NodeID
    prev_log_index::LogIndex
    prev_log_term::Term
    entries::Vector{LogEntry}
    leader_commit::LogIndex
    rpc_id::UInt64

    function AppendEntriesRequest(
        term::Term,
        leader_id::NodeID,
        prev_log_index::LogIndex,
        prev_log_term::Term,
        entries::Vector{LogEntry},
        leader_commit::LogIndex,
        rpc_id::UInt64,
    )
        prev_log_index >= 0 && leader_commit >= 0 ||
            throw(ArgumentError("append request indices must be non-negative"))
        leader_id > 0 || throw(ArgumentError("leader id must be positive"))
        all(entry -> entry.term <= term, entries) ||
            throw(ArgumentError("append request contains an entry from a future term"))
        prev_log_index == 0 && prev_log_term != 0 &&
            throw(ArgumentError("an empty log prefix must have term zero"))
        new(term, leader_id, prev_log_index, prev_log_term, copy(entries), leader_commit, rpc_id)
    end
end

function AppendEntriesRequest(
    term::Integer,
    leader_id::Integer,
    prev_log_index::Integer,
    prev_log_term::Integer,
    entries::AbstractVector{LogEntry},
    leader_commit::Integer,
    rpc_id::Integer=0,
)
    term >= 0 && prev_log_index >= 0 && prev_log_term >= 0 && leader_commit >= 0 && rpc_id >= 0 ||
        throw(ArgumentError("append request terms and indices must be non-negative"))
    leader_id > 0 || throw(ArgumentError("leader id must be positive"))
    all(entry -> entry.term <= term, entries) ||
        throw(ArgumentError("append request contains an entry from a future term"))
    return AppendEntriesRequest(
        UInt64(term),
        Int(leader_id),
        Int(prev_log_index),
        UInt64(prev_log_term),
        collect(entries),
        Int(leader_commit),
        UInt64(rpc_id),
    )
end

struct AppendEntriesResponse <: RaftMessage
    term::Term
    follower_id::NodeID
    success::Bool
    match_index::LogIndex
    conflict_index::LogIndex
    conflict_term::Union{Nothing,Term}
    rpc_id::UInt64
    request_prev_log_index::LogIndex

    function AppendEntriesResponse(
        term::Term,
        follower_id::NodeID,
        success::Bool,
        match_index::LogIndex,
        conflict_index::LogIndex,
        conflict_term::Union{Nothing,Term},
        rpc_id::UInt64,
        request_prev_log_index::LogIndex,
    )
        follower_id > 0 || throw(ArgumentError("follower id must be positive"))
        match_index >= 0 && conflict_index >= 1 && request_prev_log_index >= 0 ||
            throw(ArgumentError("append response indices are invalid"))
        !isnothing(conflict_term) && conflict_term > term &&
            throw(ArgumentError("append conflict term cannot exceed the responder term"))
        if success
            isnothing(conflict_term) ||
                throw(ArgumentError("a successful append response cannot carry a conflict term"))
            match_index >= request_prev_log_index ||
                throw(ArgumentError("successful append acknowledgement precedes its requested prefix"))
        else
            match_index == 0 ||
                throw(ArgumentError("a rejected append response cannot acknowledge a match index"))
        end
        new(
            term,
            follower_id,
            success,
            match_index,
            conflict_index,
            conflict_term,
            rpc_id,
            request_prev_log_index,
        )
    end
end

function AppendEntriesResponse(
    term::Integer,
    follower_id::Integer,
    success::Bool,
    match_index::Integer,
    conflict_index::Integer=1,
    conflict_term::Union{Nothing,Integer}=nothing,
    rpc_id::Integer=0,
    request_prev_log_index::Integer=0,
)
    term >= 0 && match_index >= 0 && conflict_index >= 1 && rpc_id >= 0 &&
        request_prev_log_index >= 0 ||
        throw(ArgumentError("append response terms and indices are invalid"))
    follower_id > 0 || throw(ArgumentError("follower id must be positive"))
    !isnothing(conflict_term) && conflict_term < 0 &&
        throw(ArgumentError("append conflict term must be non-negative"))
    converted_term = isnothing(conflict_term) ? nothing : UInt64(conflict_term)
    return AppendEntriesResponse(
        UInt64(term),
        Int(follower_id),
        success,
        Int(match_index),
        Int(conflict_index),
        converted_term,
        UInt64(rpc_id),
        Int(request_prev_log_index),
    )
end

struct ClientRequest
    request_id::RequestID
    command::Command
end

@enum ClientStatus::UInt8 ClientCommitted ClientNotLeader

struct ClientResponse
    request_id::RequestID
    status::ClientStatus
    result::Union{Nothing,CommandResult}
    leader_hint::Union{Nothing,NodeID}
end

abstract type NodeInput end

struct TimerInput <: NodeInput
    kind::TimerKind
    generation::UInt64
    crash_epoch::UInt64
end

TimerInput(kind::TimerKind, generation::Integer, crash_epoch::Integer=0) = begin
    generation >= 0 && crash_epoch >= 0 ||
        throw(ArgumentError("timer generation and crash epoch must be non-negative"))
    TimerInput(kind, UInt64(generation), UInt64(crash_epoch))
end

struct MessageInput{M<:RaftMessage} <: NodeInput
    from::NodeID
    message::M

    function MessageInput(from::Integer, message::M) where {M<:RaftMessage}
        from > 0 || throw(ArgumentError("message sender must be positive"))
        new{M}(Int(from), message)
    end
end

struct ClientInput <: NodeInput
    request::ClientRequest
end

struct CrashInput <: NodeInput end
struct RecoverInput <: NodeInput end

abstract type RaftEffect end

struct SendMessage{M<:RaftMessage} <: RaftEffect
    from::NodeID
    to::NodeID
    message::M
end

struct ResetTimer <: RaftEffect
    node::NodeID
    kind::TimerKind
    generation::UInt64
    crash_epoch::UInt64
    deadline_local::Float64
end

struct CancelTimer <: RaftEffect
    node::NodeID
    kind::TimerKind
    generation::UInt64
    crash_epoch::UInt64
end

"""Records a synchronous durable write that precedes later effects in the vector."""
struct PersistState <: RaftEffect
    node::NodeID
    snapshot::DurableSnapshot
end

struct ReplyClient <: RaftEffect
    node::NodeID
    response::ClientResponse
end
