"""
Timing arms for experiment E3 (see docs/PRE_REGISTRATION_E3.md).

Arms observe heartbeat arrivals in receiver proper time and produce an
election-deadline band as proper-time offsets from now. No arm touches Raft
transitions; the engine applies bands only at the scheduler boundary,
preserving the C1 safety-refinement argument.
"""

struct TimingBudget
    minimum::Float64
    maximum::Float64

    function TimingBudget(minimum::Real, maximum::Real)
        lo = Float64(minimum)
        hi = Float64(maximum)
        isfinite(lo) && lo > 0.0 || throw(ArgumentError("budget minimum must be positive"))
        hi > lo || throw(ArgumentError("budget maximum must exceed its minimum"))
        return new(lo, hi)
    end
end

const TIMING_ARMS = (:B0, :B1, :B2, :B3, :B4, :B5, :P1, :P2, :P3)

"""Frozen specification of one timing arm for a run."""
struct TimingSpec
    arm::Symbol
    level::Int
    budget::TimingBudget
    base_timeout::Float64
    backoff_factor::Float64
    window_capacity::Int
    quantile_low::Float64
    quantile_high::Float64
    phi_threshold::Float64
    band_z_low::Float64
    band_z_high::Float64
    warmup_observations::Int
    reset_on_crash::Bool

    function TimingSpec(;
        arm::Symbol=:B0,
        level::Integer=0,
        budget::TimingBudget=TimingBudget(0.3, 3.0),
        base_timeout::Real=0.75,
        backoff_factor::Real=1.6,
        window_capacity::Integer=24,
        quantile_low::Real=0.60,
        quantile_high::Real=0.99,
        phi_threshold::Real=3.0,
        band_z_low::Real=0.674,
        band_z_high::Real=2.326,
        warmup_observations::Integer=3,
        reset_on_crash::Bool=true,
    )
        arm in TIMING_ARMS ||
            throw(ArgumentError("unknown timing arm $arm; expected one of $TIMING_ARMS"))
        level in 0:3 || throw(ArgumentError("information level must be in 0:3"))
        (arm == :B0 || arm == :B1) && level != 0 &&
            throw(ArgumentError("static arms use level 0"))
        arm in (:P1, :P2, :P3) && level < 1 &&
            throw(ArgumentError("PT-FD arms require metadata level >= 1"))
        Float64(base_timeout) > 0.0 ||
            throw(ArgumentError("base timeout must be positive"))
        Float64(backoff_factor) > 1.0 ||
            throw(ArgumentError("backoff factor must exceed one"))
        Int(window_capacity) >= 8 ||
            throw(ArgumentError("window capacity must be at least eight"))
        0.0 <= Float64(quantile_low) < Float64(quantile_high) <= 1.0 ||
            throw(ArgumentError("quantile band must satisfy 0 <= low < high <= 1"))
        Float64(phi_threshold) > 0.0 ||
            throw(ArgumentError("phi threshold must be positive"))
        0.0 <= Float64(band_z_low) < Float64(band_z_high) ||
            throw(ArgumentError("band z-values must satisfy 0 <= low < high"))
        return new(
            arm,
            Int(level),
            budget,
            Float64(base_timeout),
            Float64(backoff_factor),
            Int(window_capacity),
            Float64(quantile_low),
            Float64(quantile_high),
            Float64(phi_threshold),
            Float64(band_z_low),
            Float64(band_z_high),
            Int(warmup_observations),
            Bool(reset_on_crash),
        )
    end
end

function timing_fingerprint(spec::TimingSpec)
    value = UInt64(0xcbf29ce484222325)
    text = "e3-timing-v1|$(spec.arm)|$(spec.level)|$(spec.budget.minimum)|" *
           "$(spec.budget.maximum)|$(spec.base_timeout)|$(spec.backoff_factor)|" *
           "$(spec.window_capacity)|$(spec.quantile_low)|$(spec.quantile_high)|" *
           "$(spec.phi_threshold)|$(spec.band_z_low)|$(spec.band_z_high)|" *
           "$(spec.warmup_observations)|$(spec.reset_on_crash)"
    for byte in codeunits(text)
        value = xor(value, UInt64(byte))
        value *= UInt64(0x00000100000001b3)
    end
    return lowercase(string(value; base=16, pad=16))
end

mutable struct ArmRuntime
    observations::Int
    observations_at_last_start::Int
    leaderless_streak::Int
    backoff_streak::Int
    window::Vector{Float64}
    seq_buffer::Vector{Union{Nothing,UInt64}}
    emit_buffer::Vector{Union{Nothing,Float64}}
    last_seq::Union{Nothing,UInt64}
    last_arrival::Union{Nothing,Float64}
    log_mean_interval::Float64
    log_variance_interval::Float64
    log_mean_ratio::Float64
end

ArmRuntime(spec::TimingSpec) = ArmRuntime(
    0,
    -1,
    0,
    0,
    Float64[],
    Union{Nothing,UInt64}[],
    Union{Nothing,Float64}[],
    nothing,
    nothing,
    log(spec.base_timeout),
    0.05^2,
    0.0,
)

"""Per-run adaptation bookkeeping owned by the engine."""
mutable struct RunTimingState
    spec::TimingSpec
    runtimes::Dict{Int,ArmRuntime}
    heartbeat_sequences::Dict{Int,UInt64}
    heartbeat_meta::Dict{UInt64,Tuple{UInt64,Float64}}
    metadata_bytes_sent::Int
    suspicions::Int
    election_fires::Int
    detection_delays_proper::Vector{Float64}
    censored_detections::Int
    open_crashes::Vector{Tuple{Int,Float64}}

    function RunTimingState(spec::TimingSpec, members::Vector{Int})
        runtimes = Dict{Int,ArmRuntime}(id => ArmRuntime(spec) for id in members)
        return new(
            spec,
            runtimes,
            Dict{Int,UInt64}(id => UInt64(0) for id in members),
            Dict{UInt64,Tuple{UInt64,Float64}}(),
            0,
            0,
            0,
            Float64[],
            0,
            Tuple{Int,Float64}[],
        )
    end
end

metadata_byte_surcharge(level::Integer) =
    (level <= 0) ? 0 : 8 * Int(level)

function _clamp_band(lo::Float64, hi::Float64, spec::TimingSpec)
    lo = clamp(lo, spec.budget.minimum, spec.budget.maximum)
    hi = clamp(hi, spec.budget.minimum, spec.budget.maximum)
    hi = max(hi, lo)
    return (lo, hi)
end

function _push_circular!(buffer::Vector{T}, item::T, capacity::Int) where {T}
    push!(buffer, item)
    length(buffer) > capacity && deleteat!(buffer, 1)
    return buffer
end

"""
Feed one observed leader-heartbeat arrival into the arm runtime.

`hb_seq` and `tau_emit` carry the I1/I2 metadata when present; `tau_nominal`
is reserved for future I3 handling. Sequence regressions never move any
estimator state backward.
"""
function observe_arrival!(
    runtime::ArmRuntime,
    spec::TimingSpec,
    hb_seq::Union{Nothing,UInt64},
    tau_emit::Union{Nothing,Float64},
    tau_arrive::Float64,
    tau_nominal::Union{Nothing,Float64}=nothing,
)
    gap = 0
    if !isnothing(hb_seq)
        if !isnothing(runtime.last_seq) && hb_seq <= runtime.last_seq
            return runtime
        end
        gap = isnothing(runtime.last_seq) ? 0 :
              Int(min(hb_seq - runtime.last_seq - 1, UInt64(64)))
        runtime.last_seq = hb_seq
    end
    if !isnothing(runtime.last_arrival)
        delta = tau_arrive - runtime.last_arrival
        if delta > 0.0
            _integrate_interval!(runtime, spec, delta, gap)
            _push_circular!(runtime.window, delta, spec.window_capacity)
        end
    end
    runtime.last_arrival = tau_arrive
    if spec.level >= 2 && !isnothing(tau_emit)
        _push_circular!(runtime.emit_buffer, tau_emit, spec.window_capacity)
        _push_circular!(runtime.seq_buffer, hb_seq, spec.window_capacity)
        if length(runtime.emit_buffer) >= 2 && length(runtime.window) >= 2
            source_delta = tau_emit - runtime.emit_buffer[end - 1]
            arrive_delta = runtime.window[end] - runtime.window[end - 1]
            source_delta > 0.0 || return runtime
            ratio = arrive_delta / source_delta
            0.1 <= ratio <= 10.0 || return runtime
            sample = log(clamp(ratio, 0.25, 4.0))
            alpha = 0.3
            runtime.log_mean_ratio +=
                alpha * (sample - runtime.log_mean_ratio)
        end
    end
    runtime.observations += 1
    return runtime
end

spec_is_gap_aware(spec::TimingSpec) = spec.arm in (:P1, :P2, :P3)

function _integrate_interval!(runtime::ArmRuntime, spec::TimingSpec, delta::Float64, gap::Int)
    sample = log(delta)
    prior = runtime.log_mean_interval
    runtime.log_mean_interval += 0.25 * (sample - prior)
    residual = sample - runtime.log_mean_interval
    runtime.log_variance_interval += 0.20 * (residual^2 - runtime.log_variance_interval)
    gap > 0 && (runtime.log_variance_interval += 0.10 * gap)
    return runtime
end

function note_election_started!(runtime::ArmRuntime)
    runtime.backoff_streak += 1
    # A candidacy that consumed no new arrival evidence means the cluster is
    # leaderless and silent; widen uncertainty so repeated restarts
    # de-synchronize and eventually achieve quorum.
    if runtime.observations == runtime.observations_at_last_start
        runtime.leaderless_streak += 1
    else
        runtime.leaderless_streak = 0
    end
    runtime.observations_at_last_start = runtime.observations
    return runtime
end

note_leader_traffic!(runtime::ArmRuntime) =
    (runtime.backoff_streak = 0; runtime)

function reset_runtime!(state::RunTimingState, node_id::Int)
    state.runtimes[node_id] = ArmRuntime(state.spec)
    return state
end
