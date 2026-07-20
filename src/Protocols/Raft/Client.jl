mutable struct HistoryOperation
    request::ClientRequest
    predecessors::Set{RequestID}
    result::Union{Nothing,CommandResult}
    completed::Bool
end

mutable struct ClientHistory
    operations::Dict{RequestID,HistoryOperation}
end

ClientHistory() = ClientHistory(Dict{RequestID,HistoryOperation}())

function record_invocation!(
    history::ClientHistory,
    request::ClientRequest;
    predecessors=RequestID[],
)
    haskey(history.operations, request.request_id) &&
        throw(ArgumentError("client request was invoked more than once in this history"))
    predecessor_set = Set{RequestID}(predecessors)
    request.request_id in predecessor_set &&
        throw(ArgumentError("an operation cannot causally precede itself"))
    history.operations[request.request_id] =
        HistoryOperation(request, predecessor_set, nothing, false)
    return history.operations[request.request_id]
end

function record_completion!(history::ClientHistory, response::ClientResponse)
    operation = get(history.operations, response.request_id, nothing)
    isnothing(operation) && throw(ArgumentError("completion has no matching invocation"))
    response.status == ClientCommitted || return operation
    operation.completed && operation.result != response.result &&
        throw(ArgumentError("one request completed with inconsistent results"))
    operation.completed = true
    operation.result = response.result
    return operation
end

function _history_result!(machine::Dict{String,String}, command::Command)
    return _execute_command!(machine, command)
end

function _linearization_search(
    operations::Dict{RequestID,HistoryOperation},
    remaining::Set{RequestID},
    executed::Set{RequestID},
    machine::Dict{String,String},
)
    isempty(remaining) && return true
    for request_id in sort!(collect(remaining))
        operation = operations[request_id]
        required = Set(filter(predecessor -> haskey(operations, predecessor) && operations[predecessor].completed,
                              operation.predecessors))
        issubset(required, executed) || continue
        next_machine = copy(machine)
        expected = _history_result!(next_machine, operation.request.command)
        expected == operation.result || continue
        next_remaining = copy(remaining)
        delete!(next_remaining, request_id)
        next_executed = copy(executed)
        push!(next_executed, request_id)
        _linearization_search(operations, next_remaining, next_executed, next_machine) && return true
    end
    return false
end

"""
Independent bounded checker for completed key/value operations.

The caller supplies causal/real-time predecessors at invocation recording time;
there is deliberately no comparison of unrelated nodes' coordinate timestamps.
Pending operations are omitted, as permitted by linearizability completion.
"""
function is_linearizable(history::ClientHistory; max_completed::Integer=12)
    completed_ids = Set(
        request_id for (request_id, operation) in history.operations if operation.completed
    )
    length(completed_ids) <= max_completed ||
        throw(ArgumentError("history exceeds bounded checker limit of $max_completed operations"))
    for request_id in completed_ids
        operation = history.operations[request_id]
        isnothing(operation.result) && return false
        any(predecessor -> !haskey(history.operations, predecessor), operation.predecessors) &&
            throw(ArgumentError("history names an unknown causal predecessor"))
    end
    return _linearization_search(
        history.operations,
        completed_ids,
        Set{RequestID}(),
        Dict{String,String}(),
    )
end

"""Generate a deterministic write/read workload with globally unique request ids."""
function deterministic_workload(client::Integer, count::Integer; key_prefix::AbstractString="key")
    client >= 0 || throw(ArgumentError("client id must be non-negative"))
    count >= 0 || throw(ArgumentError("workload count must be non-negative"))
    requests = ClientRequest[]
    for sequence in 1:count
        key = "$(key_prefix)-$sequence"
        request_id = RequestID(client, sequence)
        push!(requests, ClientRequest(request_id, PutCommand(key, "value-$sequence")))
    end
    return requests
end
