"""
Deterministic research harness for the standard-Raft RQ1 experiments.

This module composes the public physics, simulation, and Raft components.  It
does not modify the Raft transition rules and deliberately contains no timeout
adaptation.
"""
module Research

using Random
using StaticArrays
using ..SimulationCore
using ..Raft
using ..RelativisticDistributedSystemsSim: MinkowskiSpacetime,
    SpacetimeEvent,
    AbstractWorldline,
    InertialWorldline,
    UniformlyAcceleratedWorldline,
    ParametricWorldline,
    proper_time_between,
    coordinate_time_after_proper_time,
    worldline_event,
    coordinate_velocity,
    light_cone_intersection,
    is_future_causal,
    NoFutureLightConeIntersection,
    LightConeSearchExhausted

include("Clocks.jl")
include("Configurations.jl")
include("Detectors.jl")
include("TimingBands.jl")
include("Results.jl")
include("Scenarios.jl")
include("DsrScenarios.jl")
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
    trajectory_change_scenario,
    dsr_regime_scenario,
    dsr_pairwise_ratios,
    nearest_neighbour_rho,
    HomotheticWorldline,
    CrashLeader,
    with_timing,
    REFERENCE_ARMS,
    rq1_scenarios,
    validate_config,
    dimensionless_parameters,
    config_fingerprint,
    TimingBudget,
    TimingSpec,
    TIMING_ARMS,
    timing_fingerprint,
    election_band,
    draw_election_offset!,
    observe_arrival!,
    note_leader_traffic!,
    note_election_started!,
    reset_runtime!,
    metadata_byte_surcharge,
    SafetyOracleFlags,
    OperationMetric,
    CausalDelayMetric,
    RunMetrics,
    RunResult,
    AdaptationDiagnostics,
    BaselineComparison,
    run_scenario,
    compare_standard_baselines,
    trace_records,
    print_run_summary,
    causal_quorum_bound,
    causal_quorum_chain,
    causal_bound_tolerance,
    CAUSAL_BOUND_RTOL,
    CAUSAL_BOUND_ATOL_FLOOR,
    verify_causal_quorum_bounds

end
