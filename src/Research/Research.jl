"""
Deterministic research harness for the standard-Raft RQ1 experiments.

This module composes the public physics, simulation, and Raft components.  It
does not modify the Raft transition rules and deliberately contains no timeout
adaptation.
"""
module Research

using Random
using ..SimulationCore
using ..Raft
using ..RelativisticDistributedSystemsSim: MinkowskiSpacetime,
    SpacetimeEvent,
    AbstractWorldline,
    InertialWorldline,
    UniformlyAcceleratedWorldline,
    proper_time_between,
    coordinate_time_after_proper_time,
    worldline_event,
    coordinate_velocity,
    light_cone_intersection,
    is_future_causal

include("Clocks.jl")
include("Configurations.jl")
include("Results.jl")
include("Scenarios.jl")
include("Engine.jl")

export ProperTimeClock,
    ScenarioFamily,
    ColocatedControl,
    SeparatedStaticBaseline,
    AsymmetricRecedingInertial,
    AcceleratingBaseline,
    PartitionDropStress,
    NetworkProfile,
    ExperimentWindow,
    WorkloadSpec,
    FaultSpec,
    ScenarioConfig,
    DimensionlessParameters,
    canonical_scenario,
    rq1_scenarios,
    validate_config,
    dimensionless_parameters,
    config_fingerprint,
    SafetyOracleFlags,
    OperationMetric,
    CausalDelayMetric,
    RunMetrics,
    RunResult,
    BaselineComparison,
    run_scenario,
    compare_standard_baselines,
    trace_records,
    print_run_summary

end
