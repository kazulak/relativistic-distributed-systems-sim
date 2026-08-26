"""
Election-deadline bands per timing arm. Bands are proper-time offsets from
the node's current local time; the engine draws uniformly inside the band
using the node's private RNG stream, preserving deadline randomization.
"""

function _empirical_quantile(sorted::Vector{Float64}, q::Float64)
    isempty(sorted) && return nothing
    position = q * (length(sorted) - 1) + 1
    lower = floor(Int, position)
    upper = ceil(Int, position)
    lower == upper && return sorted[lower]
    weight = position - lower
    return sorted[lower] + weight * (sorted[upper] - sorted[lower])
end

function _cold_start(spec::TimingSpec)
    return (spec.base_timeout * 0.75, spec.base_timeout * 1.25)
end

function election_band(runtime::ArmRuntime, spec::TimingSpec)
    if runtime.observations < spec.warmup_observations || isempty(runtime.window)
        lo, hi = _cold_start(spec)
        return _widen_and_clamp(lo, hi, runtime, spec)
    end
    lo = 0.0
    hi = 0.0
    if spec.arm in (:B0, :B1, :B2)
        timeout = spec.base_timeout
        if spec.arm == :B2
            timeout = min(
                spec.base_timeout * spec.backoff_factor^runtime.backoff_streak,
                spec.budget.maximum,
            )
        end
        lo = hi = timeout
    elseif spec.arm == :B3
        sigma = sqrt(max(runtime.log_variance_interval, 0.05^2))
        center = runtime.log_mean_interval
        lo = exp(center + spec.band_z_low * sigma)
        hi = exp(center + spec.band_z_high * sigma)
    elseif spec.arm == :B4
        ordered = sort(copy(runtime.window))
        lo = something(_empirical_quantile(ordered, spec.quantile_low), spec.base_timeout)
        hi = something(_empirical_quantile(ordered, spec.quantile_high), spec.base_timeout)
    elseif spec.arm == :B5
        mean_interval = exp(runtime.log_mean_interval + 0.5 * runtime.log_variance_interval)
        scale = spec.phi_threshold * log(10.0)
        lo = mean_interval * 0.5 * scale
        hi = mean_interval * scale
    elseif spec.arm == :P1
        sigma = sqrt(max(runtime.log_variance_interval, 0.05^2))
        center = runtime.log_mean_interval
        lo = exp(center + spec.band_z_low * sigma)
        hi = exp(center + spec.band_z_high * sigma)
    elseif spec.arm in (:P2, :P3)
        sigma = sqrt(max(runtime.log_variance_interval, 0.05^2))
        ratio = exp(runtime.log_mean_ratio)
        source_interval = _recent_source_interval(runtime, spec)
        center = log(max(source_interval * ratio, eps(Float64)))
        lo = exp(center + spec.band_z_low * sigma)
        hi = exp(center + spec.band_z_high * sigma)
    else
        lo = hi = spec.base_timeout
    end
    return _widen_and_clamp(lo, hi, runtime, spec)
end

function _widen_and_clamp(lo::Float64, hi::Float64, runtime::ArmRuntime, spec::TimingSpec)
    if runtime.leaderless_streak > 0
        mid = (lo + hi) / 2
        half = (hi - lo) / 2 * (1 + 0.5runtime.leaderless_streak) +
               0.25 * spec.base_timeout * runtime.leaderless_streak
        lo = mid - half
        hi = mid + half
    end
    return _clamp_band(lo, hi, spec)
end

function _recent_source_interval(runtime::ArmRuntime, spec::TimingSpec)
    buffer = runtime.emit_buffer
    intervals = Float64[]
    for index in (length(buffer) - 1):-1:1
        delta = buffer[index + 1] - buffer[index]
        delta > 0.0 && push!(intervals, delta)
        length(intervals) >= 8 && break
    end
    isempty(intervals) && return exp(runtime.log_mean_interval) / max(exp(runtime.log_mean_ratio), 0.25)
    return _empirical_quantile(sort(intervals), 0.5)
end

"""Draw the randomized election-deadline offset for one timer reset."""
function draw_election_offset!(
    runtime::ArmRuntime,
    spec::TimingSpec,
    rng::AbstractRNG,
)
    lo, hi = election_band(runtime, spec)
    draw = rand(rng)
    return lo + draw * (hi - lo)
end
