struct InvariantViolation <: Exception
    violations::Vector{String}
end

function Base.showerror(io::IO, error::InvariantViolation)
    print(io, "Raft invariant violation")
    for violation in error.violations
        print(io, "\n - ", violation)
    end
end

struct CommitRecord
    entry::LogEntry
    committed_in_term::Term
    leader_id::NodeID
end

Base.:(==)(left::CommitRecord, right::CommitRecord) =
    left.entry == right.entry &&
    left.committed_in_term == right.committed_in_term &&
    left.leader_id == right.leader_id

struct NodeObservation
    durable::DurableSnapshot
    running::Bool
    crash_epoch::UInt64
    commit_index::LogIndex
    last_applied::LogIndex
end

mutable struct InvariantAudit
    leaders_by_term::Dict{Term,NodeID}
    leader_logs::Dict{Tuple{NodeID,Term},Vector{LogEntry}}
    committed_entries::Dict{LogIndex,CommitRecord}
    commit_provenance::Dict{LogIndex,CommitRecord}
    node_committed_entries::Dict{Tuple{NodeID,LogIndex},LogEntry}
    applied_entries::Dict{LogIndex,LogEntry}
    request_commands::Dict{RequestID,Command}
    observations::Dict{NodeID,NodeObservation}
    transitions_checked::UInt64
end

InvariantAudit() = InvariantAudit(
    Dict{Term,NodeID}(),
    Dict{Tuple{NodeID,Term},Vector{LogEntry}}(),
    Dict{LogIndex,CommitRecord}(),
    Dict{LogIndex,CommitRecord}(),
    Dict{Tuple{NodeID,LogIndex},LogEntry}(),
    Dict{LogIndex,LogEntry}(),
    Dict{RequestID,Command}(),
    Dict{NodeID,NodeObservation}(),
    0,
)

struct InvariantReport
    ok::Bool
    transitions_checked::UInt64
    violations::Vector{String}
end

_is_prefix(prefix::Vector{LogEntry}, log::Vector{LogEntry}) =
    length(prefix) <= length(log) && all(index -> prefix[index] == log[index], eachindex(prefix))

function _check_local_state!(violations::Vector{String}, node::RaftNode)
    durable = node.durable
    state = node.volatile
    any(entry -> entry.term > durable.current_term, durable.log) &&
        push!(violations, "node $(node.id) has a log entry from a future term")
    !isnothing(durable.voted_for) && !(durable.voted_for in node.config.members) &&
        push!(violations, "node $(node.id) voted outside its membership")
    !(0 <= state.last_applied <= state.commit_index <= last_log_index(node)) &&
        push!(violations, "node $(node.id) has invalid applied/commit/log indices")
    !node.running && state.role != Follower &&
        push!(violations, "crashed node $(node.id) is not a follower")
    state.role == Candidate && durable.voted_for != node.id &&
        push!(violations, "candidate $(node.id) did not durably vote for itself")

    if state.role == Leader
        state.leader_id == node.id ||
            push!(violations, "leader $(node.id) does not identify itself as leader")
        for member in node.config.members
            match_index = get(state.match_index, member, -1)
            next_index = get(state.next_index, member, -1)
            !(0 <= match_index <= last_log_index(node)) &&
                push!(violations, "leader $(node.id) has invalid matchIndex for $member")
            !(max(match_index + 1, 1) <= next_index <= last_log_index(node) + 1) &&
                push!(violations, "leader $(node.id) has invalid nextIndex for $member")
        end
        get(state.match_index, node.id, -1) == last_log_index(node) ||
            push!(violations, "leader $(node.id) does not fully match its own log")
        for ((follower, rpc_id), probe) in state.append_probes
            follower in node.config.members && follower != node.id ||
                push!(violations, "leader $(node.id) retained a probe for invalid follower $follower")
            rpc_id == probe.rpc_id ||
                push!(violations, "leader $(node.id) probe key disagrees with its RPC id")
            probe.last_log_index <= last_log_index(node) ||
                push!(violations, "leader $(node.id) probe extends beyond its log")
            rpc_id <= get(state.append_rpc_counter, follower, 0) ||
                push!(violations, "leader $(node.id) probe RPC was never issued")
        end
    end

    rebuilt_machine = Dict{String,String}()
    rebuilt_requests = Dict{RequestID,AppliedRecord}()
    for index in 1:state.last_applied
        entry = durable.log[index]
        if isnothing(entry.request_id)
            _execute_command!(rebuilt_machine, entry.command)
            continue
        end
        request_id = entry.request_id::RequestID
        existing = get(rebuilt_requests, request_id, nothing)
        if isnothing(existing)
            result = _execute_command!(rebuilt_machine, entry.command)
            rebuilt_requests[request_id] = AppliedRecord(index, entry.command, result)
        elseif existing.command != entry.command
            push!(violations, "node $(node.id) applied one request id as different commands")
        end
    end
    rebuilt_machine == state.state_machine ||
        push!(violations, "node $(node.id) state machine differs from deterministic log replay")
    rebuilt_requests == state.applied_requests ||
        push!(violations, "node $(node.id) at-most-once request table differs from log replay")
    return violations
end

function _check_observation!(violations::Vector{String}, audit::InvariantAudit, node::RaftNode)
    previous = get(audit.observations, node.id, nothing)
    current = NodeObservation(
        DurableSnapshot(node.durable),
        node.running,
        node.crash_epoch,
        node.volatile.commit_index,
        node.volatile.last_applied,
    )
    if !isnothing(previous)
        current.durable.current_term < previous.durable.current_term &&
            push!(violations, "node $(node.id) currentTerm decreased")
        if current.durable.current_term == previous.durable.current_term
            old_vote = previous.durable.voted_for
            new_vote = current.durable.voted_for
            !isnothing(old_vote) && new_vote != old_vote &&
                push!(violations, "node $(node.id) changed its vote within one term")
        end
        if current.running != previous.running
            current.durable != previous.durable &&
                push!(violations, "node $(node.id) changed durable state during crash/recovery")
        elseif !current.running
            current.durable != previous.durable &&
                push!(violations, "crashed node $(node.id) changed durable state")
        end
        if current.running && previous.running && current.crash_epoch == previous.crash_epoch
            current.commit_index < previous.commit_index &&
                push!(violations, "node $(node.id) commitIndex decreased without a crash")
            current.last_applied < previous.last_applied &&
                push!(violations, "node $(node.id) lastApplied decreased without a crash")
        end
    end

    for ((owner, index), entry) in audit.node_committed_entries
        owner == node.id || continue
        (index <= last_log_index(node) && node.durable.log[index] == entry) ||
            push!(violations, "node $(node.id) lost a previously committed durable entry at $index")
    end
    audit.observations[node.id] = current
    return violations
end

function _check_log_matching!(violations::Vector{String}, nodes::Vector{RaftNode})
    for left_index in eachindex(nodes), right_index in (left_index + 1):length(nodes)
        right_index > length(nodes) && continue
        left = nodes[left_index]
        right = nodes[right_index]
        shared = min(last_log_index(left), last_log_index(right))
        for index in 1:shared
            if left.durable.log[index].term == right.durable.log[index].term &&
               !_is_prefix(left.durable.log[1:index], right.durable.log[1:index])
                push!(
                    violations,
                    "log matching failed for nodes $(left.id) and $(right.id) at index $index",
                )
            end
        end
    end
    return violations
end

function _record_requests!(violations::Vector{String}, audit::InvariantAudit, node::RaftNode)
    for entry in node.durable.log
        isnothing(entry.request_id) && continue
        request_id = entry.request_id::RequestID
        previous = get(audit.request_commands, request_id, nothing)
        if isnothing(previous)
            audit.request_commands[request_id] = entry.command
        elseif previous != entry.command
            push!(violations, "request id $request_id names multiple commands")
        end
    end
    return violations
end

function _record_leader!(violations::Vector{String}, audit::InvariantAudit, node::RaftNode)
    node.running && node.volatile.role == Leader || return violations
    term = node.durable.current_term
    previous_leader = get(audit.leaders_by_term, term, nothing)
    if !isnothing(previous_leader) && previous_leader != node.id
        push!(violations, "election safety failed in term $term: leaders $previous_leader and $(node.id)")
    else
        audit.leaders_by_term[term] = node.id
    end

    key = (node.id, term)
    prior_log = get(audit.leader_logs, key, nothing)
    if !isnothing(prior_log) && !_is_prefix(prior_log, node.durable.log)
        push!(violations, "leader append-only failed for node $(node.id) in term $term")
    end
    audit.leader_logs[key] = copy(node.durable.log)
    return violations
end

function _record_commit_and_apply!(violations::Vector{String}, audit::InvariantAudit, node::RaftNode)
    for index in 1:node.volatile.commit_index
        entry = node.durable.log[index]
        provenance = get(audit.commit_provenance, index, nothing)
        if isnothing(provenance)
            push!(violations, "committed index $index has no observed leader-quorum provenance")
            continue
        elseif provenance.entry != entry
            push!(violations, "commit provenance disagrees with node $(node.id) at index $index")
            continue
        end
        record = get(audit.committed_entries, index, nothing)
        if isnothing(record)
            audit.committed_entries[index] = provenance
        elseif record.entry != entry
            push!(violations, "state machine safety failed: different committed entries at index $index")
        end
        key = (node.id, index)
        prior = get(audit.node_committed_entries, key, nothing)
        !isnothing(prior) && prior != entry &&
            push!(violations, "node $(node.id) changed committed index $index")
        audit.node_committed_entries[key] = entry
    end
    for index in 1:node.volatile.last_applied
        entry = node.durable.log[index]
        prior = get(audit.applied_entries, index, nothing)
        if isnothing(prior)
            audit.applied_entries[index] = entry
        elseif prior != entry
            push!(violations, "state machine safety failed: different applied entries at index $index")
        end
    end
    return violations
end

function _record_leader_commit!(
    audit::InvariantAudit,
    node::RaftNode,
    previous_commit::LogIndex,
)
    node.running && node.volatile.role == Leader || throw(
        InvariantViolation(["only a running leader may originate commit provenance"]),
    )
    new_commit = node.volatile.commit_index
    new_commit > previous_commit || return audit
    node.durable.log[new_commit].term == node.durable.current_term || throw(
        InvariantViolation(["leader advanced commitIndex without a current-term quorum entry"]),
    )
    for index in (previous_commit + 1):new_commit
        record = CommitRecord(
            node.durable.log[index],
            node.durable.current_term,
            node.id,
        )
        prior = get(audit.commit_provenance, index, nothing)
        !isnothing(prior) && prior != record && throw(
            InvariantViolation(["conflicting leader provenance for committed index $index"]),
        )
        audit.commit_provenance[index] = record
    end
    return audit
end

function _check_leader_completeness!(violations::Vector{String}, audit::InvariantAudit)
    for (index, commit) in audit.committed_entries
        for ((leader, term), log) in audit.leader_logs
            term > commit.committed_in_term || continue
            (index <= length(log) && log[index] == commit.entry) || push!(
                violations,
                "leader completeness failed: leader $leader term $term lacks committed index $index",
            )
        end
    end
    return violations
end

"""Check and audit every named Raft safety property after a cluster transition."""
function check_invariants!(audit::InvariantAudit, nodes_input)
    nodes = sort!(collect(nodes_input); by=node -> node.id)
    violations = String[]
    isempty(nodes) && push!(violations, "cannot check an empty Raft cluster")
    length(unique(node.id for node in nodes)) == length(nodes) ||
        push!(violations, "cluster contains duplicate node ids")
    if !isempty(nodes)
        membership = nodes[1].config.members
        all(node -> node.config.members == membership, nodes) ||
            push!(violations, "cluster nodes disagree on static membership")
        Set(node.id for node in nodes) == Set(membership) ||
            push!(violations, "checked nodes do not exactly match static membership")
    end

    for node in nodes
        _check_local_state!(violations, node)
        _check_observation!(violations, audit, node)
        _record_requests!(violations, audit, node)
        _record_leader!(violations, audit, node)
        _record_commit_and_apply!(violations, audit, node)
    end
    _check_log_matching!(violations, nodes)
    _check_leader_completeness!(violations, audit)
    audit.transitions_checked == typemax(UInt64) && throw(OverflowError("audit transition count exhausted"))
    audit.transitions_checked += 1
    return InvariantReport(isempty(violations), audit.transitions_checked, violations)
end

function assert_invariants!(audit::InvariantAudit, nodes)
    report = check_invariants!(audit, nodes)
    report.ok || throw(InvariantViolation(report.violations))
    return report
end

mutable struct AuditedCluster
    nodes::Dict{NodeID,RaftNode}
    audit::InvariantAudit
end

function AuditedCluster(nodes_input)
    nodes = collect(nodes_input)
    ids = [node.id for node in nodes]
    allunique(ids) || throw(ArgumentError("audited cluster contains duplicate node ids"))
    cluster = AuditedCluster(Dict(node.id => node for node in nodes), InvariantAudit())
    assert_invariants!(cluster.audit, values(cluster.nodes))
    return cluster
end

function _validate_durable_effects(before::DurableSnapshot, node::RaftNode, effects::Vector{RaftEffect})
    final = DurableSnapshot(node.durable)
    before == final && return nothing
    persist_positions = findall(effect -> effect isa PersistState, effects)
    isempty(persist_positions) &&
        throw(InvariantViolation(["node $(node.id) changed durable state without PersistState"]))
    last_persist = effects[last(persist_positions)]::PersistState
    last_persist.snapshot == final ||
        throw(InvariantViolation(["node $(node.id) final durable state was not persisted"]))
    first_send = findfirst(effect -> effect isa SendMessage, effects)
    !isnothing(first_send) && last(persist_positions) > first_send &&
        throw(InvariantViolation(["node $(node.id) sent before its final durable write"]))
    return nothing
end

"""Apply one node transition and immediately run the cluster-wide invariant oracle."""
function transition!(
    cluster::AuditedCluster,
    node_id::Integer,
    input::NodeInput,
    local_now::Real,
    rng::AbstractRNG,
)
    node = get(cluster.nodes, Int(node_id), nothing)
    isnothing(node) && throw(ArgumentError("unknown node id"))
    before = DurableSnapshot(node.durable)
    previous_commit = node.volatile.commit_index
    effects = handle!(node, input, local_now, rng)
    _validate_durable_effects(before, node, effects)
    node.volatile.commit_index > previous_commit && node.volatile.role == Leader &&
        _record_leader_commit!(cluster.audit, node, previous_commit)
    assert_invariants!(cluster.audit, values(cluster.nodes))
    return effects
end
