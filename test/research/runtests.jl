module ResearchSimulationTests

using Test
using RelativisticDistributedSystemsSim
using RelativisticDistributedSystemsSim.SimulationCore
using RelativisticDistributedSystemsSim.Research

const SMALL_WORKLOAD = WorkloadSpec(operation_count=2, interval_proper=0.4)

all_safety(flags) = flags.raft_invariants && flags.client_history &&
                    flags.causal_deliveries && flags.causal_trace

trace_signature(result) = [
    (
        record.event_id,
        record.coordinate_time,
        record.target,
        record.payload_type,
        record.causal_parent,
    ) for record in trace_records(result.trace)
]

result_signature(result) = (
    result.status,
    result.failure_reason,
    result.config_fingerprint,
    result.metrics.elections_started,
    result.metrics.terms_observed,
    result.metrics.leaders_observed,
    result.metrics.leader_changes,
    result.metrics.leader_availability,
    result.metrics.committed_operations,
    result.metrics.commit_latencies_proper,
    result.metrics.messages_sent,
    result.metrics.message_copies_delivered,
    result.metrics.bytes_sent,
    result.metrics.bytes_delivered,
    result.metrics.protocol_retries,
    result.metrics.transport_duplicates,
    result.metrics.transport_drops,
    result.metrics.censored_operations,
    trace_signature(result),
)

@testset "proper-time clock and configuration contract" begin
    spacetime = MinkowskiSpacetime(1.0)
    worldline = InertialWorldline(spacetime, (0.0, 0.0, 0.0), (0.6, 0.0, 0.0))
    clock = ProperTimeClock(spacetime, worldline)
    @test local_time(clock, 1.0) ≈ 0.8 atol=8eps(Float64)
    @test coordinate_time(clock, 0.8) ≈ 1.0 atol=8eps(Float64)

    @test_throws ArgumentError canonical_scenario(SeparatedStaticBaseline; cluster_size=4)
    @test_throws ArgumentError NetworkProfile(loss_probability=1.1)
    @test_throws ArgumentError WorkloadSpec(operation_count=-1)

    first = canonical_scenario(SeparatedStaticBaseline; workload=SMALL_WORKLOAD)
    second = canonical_scenario(SeparatedStaticBaseline; workload=SMALL_WORKLOAD)
    moving = canonical_scenario(AsymmetricRecedingInertial; workload=SMALL_WORKLOAD)
    @test validate_config(first)
    @test config_fingerprint(first) == config_fingerprint(second)
    @test config_fingerprint(first) != config_fingerprint(moving)
    parameters = dimensionless_parameters(first)
    @test parameters.rho ≈ 0.2
    @test parameters.theta_min ≈ 5.0
    @test parameters.theta_max ≈ 7.0
    @test 0.0 < parameters.chi_initial < 1.0
    @test parameters.deadline_margin > 1.0
end

@testset "canonical RQ1 families smoke" begin
    for family in instances(ScenarioFamily)
        config = canonical_scenario(family; cluster_size=3, workload=SMALL_WORKLOAD)
        result = run_scenario(config; seed=7)
        @test result.status == :completed
        @test isnothing(result.failure_reason)
        @test all_safety(result.safety)
        @test isempty(result.safety.violations)
        @test validate_trace(result.trace)
        @test result.metrics.committed_operations + result.metrics.censored_operations == 2
        @test !isempty(result.metrics.causal_delays)
        @test all(delay ->
            delay.logical_send_coordinate <= delay.physical_emission_coordinate <=
            delay.direct_reception_coordinate <= delay.actual_reception_coordinate,
            result.metrics.causal_delays,
        )
        @test maximum(delay.direct_null_residual for delay in result.metrics.causal_delays) <=
              4096eps(Float64)
    end
end

@testset "static membership sizes and deterministic regression" begin
    for cluster_size in (3, 5, 7)
        config = canonical_scenario(
            SeparatedStaticBaseline;
            cluster_size=cluster_size,
            workload=WorkloadSpec(operation_count=1),
        )
        result = run_scenario(config; seed=4)
        @test result.status == :completed
        @test result.metrics.committed_operations == 1
        @test all_safety(result.safety)
    end

    config = canonical_scenario(SeparatedStaticBaseline; workload=SMALL_WORKLOAD)
    first = run_scenario(config; seed=0x1234)
    second = run_scenario(config; seed=0x1234)
    @test result_signature(first) == result_signature(second)
    @test first.seed == 0x1234
end

@testset "standard Raft controls, disruption, and censoring" begin
    control = canonical_scenario(ColocatedControl; workload=SMALL_WORKLOAD)
    separated = canonical_scenario(SeparatedStaticBaseline; workload=SMALL_WORKLOAD)
    comparison = only(compare_standard_baselines([control, separated]; seed=7))
    @test comparison.control.status == :completed
    @test comparison.candidate.status == :completed
    @test comparison.control.metrics.committed_operations == 2
    @test comparison.candidate.metrics.committed_operations == 2
    @test !isnothing(comparison.commit_latency_delta)
    @test comparison.commit_latency_delta > 0.0

    stress = run_scenario(
        canonical_scenario(PartitionDropStress; workload=SMALL_WORKLOAD);
        seed=7,
    )
    @test stress.status == :completed
    @test stress.metrics.transport_drops > 0
    @test stress.metrics.terms_observed >= 1
    @test all_safety(stress.safety)

    censored_config = canonical_scenario(
        SeparatedStaticBaseline;
        workload=WorkloadSpec(operation_count=1, deadline_proper=0.4),
        network=NetworkProfile(loss_probability=1.0),
    )
    censored = run_scenario(censored_config; seed=9)
    @test censored.status == :completed
    @test censored.metrics.committed_operations == 0
    @test censored.metrics.censored_operations == 1
    @test censored.metrics.transport_drops > 0
    @test all_safety(censored.safety)
end

include("metamorphic.jl")

end
