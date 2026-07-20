module RelativisticDistributedSystemsSim

include("Physics/Spacetime.jl")
include("Physics/Worldlines.jl")
include("Physics/ProperTime.jl")
include("Physics/LightCone.jl")
include("Physics/Lorentz.jl")

# Keep public component namespaces in dependency order: the protocol may consume
# simulation interfaces, while neither component is allowed to reach into the
# package's legacy compatibility harnesses below.
include("Simulation/Simulation.jl")
include("Protocols/Raft/Raft.jl")

include("raft_baseline.jl")
include("tvat.jl")

export SimulationCore,
    Raft,
    MinkowskiSpacetime,
    SpacetimeEvent,
    NumericalConditioningError,
    interval_squared,
    scaled_interval_residual,
    spatial_distance,
    causal_relation,
    is_future_causal,
    AbstractWorldline,
    InertialWorldline,
    ParametricWorldline,
    UniformlyAcceleratedWorldline,
    InvalidWorldlineError,
    audit_worldline,
    is_timelike_velocity,
    coordinate_domain,
    position_at,
    coordinate_velocity,
    worldline_event,
    position,
    velocity,
    ProperTime,
    QuadratureConvergenceError,
    ProperTimeInversionError,
    lorentz_factor,
    proper_time_rate,
    proper_time_between,
    proper_duration,
    coordinate_time_after_proper_time,
    NoFutureLightConeIntersection,
    LightConeSearchExhausted,
    LightConeConvergenceError,
    LightConeIntersection,
    LightTimeResult,
    light_cone_intersection,
    LorentzBoost,
    SpacetimeDisplacement,
    relativistic_factors,
    lorentz_transform,
    lorentz_transform_displacement,
    lorentz_transform_pair,
    lorentz_transform_velocity,
    inverse_boost,
    boost_event,
    boost_displacement,
    boost_pair,
    boost_velocity,
    solve_light_time,
    solve_light_time_result,
    minkowski_interval2,
    simulate_raft_baseline,
    init_raft_baseline,
    tvat_doppler_factor,
    tvat_beta_radial,
    tvat_timeout_scale,
    tvat_scaled_timeout,
    tvat_jittered_emit_interval,
    tvat_heartbeat,
    tvat_observe_heartbeat,
    init_tvat_follower_state

end
