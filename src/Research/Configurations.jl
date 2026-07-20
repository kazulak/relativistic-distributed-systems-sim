@enum ScenarioFamily::UInt8 begin
    ColocatedControl
    SeparatedStaticBaseline
    AsymmetricRecedingInertial
    AcceleratingBaseline
    PartitionDropStress
end

"""Transport parameters, all expressed in the scenario's coordinate units."""
struct NetworkProfile
    loss_probability::Float64
    duplicate_probability::Float64
    reorder_probability::Float64
    processing_delay::Float64
    delay_jitter::Float64
    reorder_delay::Float64
    duplicate_delay::Float64
    bandwidth_bytes_per_time::Float64
    framing_bytes::Int

    function NetworkProfile(;
        loss_probability::Real=0.0,
        duplicate_probability::Real=0.0,
        reorder_probability::Real=0.0,
        processing_delay::Real=0.0,
        delay_jitter::Real=0.0,
        reorder_delay::Real=0.0,
        duplicate_delay::Real=0.0,
        bandwidth_bytes_per_time::Real=1.0e6,
        framing_bytes::Integer=24,
    )
        loss = Float64(loss_probability)
        duplicate = Float64(duplicate_probability)
        reorder = Float64(reorder_probability)
        all(probability -> isfinite(probability) && 0.0 <= probability <= 1.0,
            (loss, duplicate, reorder)) ||
            throw(ArgumentError("network probabilities must be finite values in [0, 1]"))
        processing = Float64(processing_delay)
        jitter = Float64(delay_jitter)
        reordering = Float64(reorder_delay)
        duplicate_lag = Float64(duplicate_delay)
        all(delay -> isfinite(delay) && delay >= 0.0,
            (processing, jitter, reordering, duplicate_lag)) ||
            throw(ArgumentError("network delays must be finite and non-negative"))
        bandwidth = Float64(bandwidth_bytes_per_time)
        isfinite(bandwidth) && bandwidth > 0.0 ||
            throw(ArgumentError("network bandwidth must be finite and positive"))
        framing_bytes >= 0 || throw(ArgumentError("framing bytes must be non-negative"))
        new(
            loss,
            duplicate,
            reorder,
            processing,
            jitter,
            reordering,
            duplicate_lag,
            bandwidth,
            Int(framing_bytes),
        )
    end
end

"""Coordinate-time boundaries for startup, measurement, and right censoring."""
struct ExperimentWindow
    start_coordinate::Float64
    warmup_end_coordinate::Float64
    measurement_end_coordinate::Float64
    censor_coordinate::Float64

    function ExperimentWindow(;
        start_coordinate::Real=0.0,
        warmup_duration::Real=2.0,
        measurement_duration::Real=4.0,
        censor_duration::Real=1.0,
    )
        start = Float64(start_coordinate)
        warmup = Float64(warmup_duration)
        measurement = Float64(measurement_duration)
        censor = Float64(censor_duration)
        isfinite(start) || throw(ArgumentError("experiment start must be finite"))
        all(value -> isfinite(value) && value >= 0.0, (warmup, censor)) ||
            throw(ArgumentError("warmup and censor durations must be finite and non-negative"))
        isfinite(measurement) && measurement > 0.0 ||
            throw(ArgumentError("measurement duration must be finite and positive"))
        warmup_end = start + warmup
        measurement_end = warmup_end + measurement
        censor_at = measurement_end + censor
        all(isfinite, (warmup_end, measurement_end, censor_at)) ||
            throw(OverflowError("experiment window overflowed"))
        new(start, warmup_end, measurement_end, censor_at)
    end
end

"""Deterministic single-client mix of replicated writes and reads."""
struct WorkloadSpec
    client_node::Int
    operation_count::Int
    start_offset_proper::Float64
    interval_proper::Float64
    deadline_proper::Float64
    retry_interval_proper::Float64
    read_every::Int

    function WorkloadSpec(;
        client_node::Integer=1,
        operation_count::Integer=8,
        start_offset_proper::Real=0.1,
        interval_proper::Real=0.35,
        deadline_proper::Real=1.5,
        retry_interval_proper::Real=0.1,
        read_every::Integer=2,
    )
        client_node > 0 || throw(ArgumentError("client node must be positive"))
        operation_count >= 0 || throw(ArgumentError("operation count must be non-negative"))
        start_offset = Float64(start_offset_proper)
        interval = Float64(interval_proper)
        deadline = Float64(deadline_proper)
        retry = Float64(retry_interval_proper)
        isfinite(start_offset) && start_offset >= 0.0 ||
            throw(ArgumentError("workload start offset must be finite and non-negative"))
        all(value -> isfinite(value) && value > 0.0, (interval, deadline, retry)) ||
            throw(ArgumentError("workload intervals and deadline must be finite and positive"))
        read_every >= 0 || throw(ArgumentError("read_every must be non-negative"))
        new(
            Int(client_node),
            Int(operation_count),
            start_offset,
            interval,
            deadline,
            retry,
            Int(read_every),
        )
    end
end

"""An exogenous fault at an absolute scheduler coordinate time."""
struct FaultSpec
    coordinate_time::Float64
    fault::FaultEvent

    function FaultSpec(coordinate_time::Real, fault::FaultEvent)
        time = Float64(coordinate_time)
        isfinite(time) || throw(ArgumentError("fault coordinate time must be finite"))
        new(time, fault)
    end
end

"""Complete, typed configuration for one standard-Raft research run."""
struct ScenarioConfig
    name::Symbol
    family::ScenarioFamily
    spacetime::MinkowskiSpacetime{Float64}
    worldlines::Vector{AbstractWorldline{Float64}}
    raft::RaftConfig
    network::NetworkProfile
    faults::Vector{FaultSpec}
    workload::WorkloadSpec
    window::ExperimentWindow
    characteristic_distance::Float64
    beta_scale::Float64
    proper_acceleration_scale::Float64
end

"""Dimensionless explanatory variables evaluated at the measurement boundary."""
struct DimensionlessParameters
    rho::Float64
    theta_min::Float64
    theta_max::Float64
    chi_initial::Float64
    source_receiver_rate_ratio::Float64
    acceleration_scale::Float64
    offered_load::Float64
    loss_probability::Float64
    delay_variation::Float64
    deadline_margin::Float64
end
