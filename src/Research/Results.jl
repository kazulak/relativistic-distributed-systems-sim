"""Outcome of every runtime safety and simulator-validity oracle."""
struct SafetyOracleFlags
    raft_invariants::Bool
    client_history::Bool
    causal_deliveries::Bool
    causal_trace::Bool
    violations::Vector{String}
end

"""
E3 adaptation telemetry; `nothing` when no timing arm is active.

Counts cover the measurement window only (see `RunTimingState`).
- `false_suspicion_rate` = suspicions / election_fires (prereg §3 literal;
  `NaN` when no fire occurred).
- `leader_present_fires`: fires while exactly one leader was alive.
- `suspicions_per_follower_heartbeat`: suspicions per follower-heartbeat of
  leader presence, i.e. suspicions / (leader_time · (n − 1) / heartbeat); an
  opportunity-normalized mistake rate that cannot be diluted by leaderless
  election churn (`NaN` when no leader was present).
- `leader_crashes`: exogenous crashes that hit the sole active leader;
  each is either resolved (a delay in `detection_delays_proper`) or censored.
- `dsr_measured`: median realized leader→follower receiver-proper
  inter-arrival / source-proper emission interval (`NaN` without samples).
"""
struct AdaptationDiagnostics
    arm::Symbol
    information_level::Int
    timing_fingerprint::String
    suspicions::Int
    election_fires::Int
    false_suspicion_rate::Float64
    detection_delays_proper::Vector{Float64}
    censored_detections::Int
    metadata_bytes_sent::Int
    leader_present_fires::Int
    suspicions_per_follower_heartbeat::Float64
    leader_crashes::Int
    dsr_measured::Float64
end

"""Per-operation observation; pending requests are explicitly right-censored."""
struct OperationMetric
    request_id::RequestID
    operation_kind::Symbol
    invoked_coordinate::Float64
    invoked_client_proper::Float64
    completed_coordinate::Union{Nothing,Float64}
    completed_client_proper::Union{Nothing,Float64}
    latency_proper::Union{Nothing,Float64}
    outcome::Symbol
    attempts::Int
end

"""Physics and transport timing for one delivered physical message copy."""
struct CausalDelayMetric
    message_id::UInt64
    copy::UInt32
    from::Int
    to::Int
    logical_send_coordinate::Float64
    physical_emission_coordinate::Float64
    direct_reception_coordinate::Float64
    actual_reception_coordinate::Float64
    queue_delay::Float64
    serialization_delay::Float64
    propagation_delay::Float64
    excess_delay::Float64
    direct_null_residual::Float64
end

"""Primary RQ1 outcomes and resource accounting for one run."""
struct RunMetrics
    elections_started::Int
    terms_observed::Int
    leaders_observed::Int
    leader_changes::Int
    leader_availability::Float64
    committed_operations::Int
    committed_writes::Int
    committed_reads::Int
    commit_latencies_proper::Vector{Float64}
    throughput_per_coordinate_time::Float64
    messages_sent::Int
    message_copies_delivered::Int
    bytes_sent::Int
    bytes_delivered::Int
    protocol_retries::Int
    transport_duplicates::Int
    transport_drops::Int
    censored_operations::Int
    causal_delays::Vector{CausalDelayMetric}
end

"""Immutable public record returned even when a run fails safely."""
struct RunResult
    scenario_name::Symbol
    family::ScenarioFamily
    seed::UInt64
    config_fingerprint::String
    status::Symbol
    failure_reason::Union{Nothing,String}
    dimensionless::DimensionlessParameters
    safety::SafetyOracleFlags
    metrics::RunMetrics
    operations::Vector{OperationMetric}
    trace::EventTrace
    adaptation::Union{Nothing,AdaptationDiagnostics}
end

"""One standard-Raft scenario result relative to the co-located control."""
struct BaselineComparison
    control::RunResult
    candidate::RunResult
    commit_latency_delta::Union{Nothing,Float64}
    availability_delta::Float64
    throughput_delta::Float64
end

mutable struct MetricsAccumulator
    elections_started::Int
    leader_changes::Int
    leaders_observed::Set{Tuple{Term,Int}}
    maximum_term::Term
    leader_coordinate_time::Float64
    last_account_coordinate::Float64
    messages_sent::Int
    message_copies_delivered::Int
    bytes_sent::Int
    bytes_delivered::Int
    protocol_retries::Int
    transport_duplicates::Int
    transport_drops::Int
    seen_protocol_messages::Set{Tuple{Int,Int,Symbol,UInt64}}
    causal_delays::Vector{CausalDelayMetric}
end

MetricsAccumulator(start_coordinate::Real) = MetricsAccumulator(
    0,
    0,
    Set{Tuple{Term,Int}}(),
    zero(Term),
    0.0,
    Float64(start_coordinate),
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    Set{Tuple{Int,Int,Symbol,UInt64}}(),
    CausalDelayMetric[],
)

function _median(values::Vector{Float64})
    isempty(values) && return nothing
    ordered = sort(copy(values))
    middle = length(ordered) >>> 1
    return isodd(length(ordered)) ? ordered[middle + 1] :
           (ordered[middle] + ordered[middle + 1]) / 2
end

function BaselineComparison(control::RunResult, candidate::RunResult)
    control_median = _median(control.metrics.commit_latencies_proper)
    candidate_median = _median(candidate.metrics.commit_latencies_proper)
    latency_delta = if isnothing(control_median) || isnothing(candidate_median)
        nothing
    else
        candidate_median - control_median
    end
    return BaselineComparison(
        control,
        candidate,
        latency_delta,
        candidate.metrics.leader_availability - control.metrics.leader_availability,
        candidate.metrics.throughput_per_coordinate_time -
        control.metrics.throughput_per_coordinate_time,
    )
end

"""Compact human-readable output for smoke runs and the CLI."""
function print_run_summary(io::IO, result::RunResult)
    metrics = result.metrics
    println(io, "scenario=", result.scenario_name)
    println(io, "family=", Symbol(result.family))
    println(io, "seed=", result.seed)
    println(io, "fingerprint=", result.config_fingerprint)
    println(io, "status=", result.status)
    !isnothing(result.failure_reason) && println(io, "failure_reason=", result.failure_reason)
    println(io, "safety_ok=", all((
        result.safety.raft_invariants,
        result.safety.client_history,
        result.safety.causal_deliveries,
        result.safety.causal_trace,
    )))
    println(io, "committed_operations=", metrics.committed_operations)
    println(io, "censored_operations=", metrics.censored_operations)
    println(io, "leader_availability=", metrics.leader_availability)
    println(io, "messages_sent=", metrics.messages_sent)
    println(io, "bytes_sent=", metrics.bytes_sent)
    return nothing
end

print_run_summary(result::RunResult) = print_run_summary(stdout, result)
