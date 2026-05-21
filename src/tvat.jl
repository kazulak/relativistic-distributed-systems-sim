using Random

const TVAT_JITTER_FRACTION = 0.001
const TVAT_SMOOTHING_ALPHA = 0.2

struct TVATHeartbeat
    leader_id::Int
    term::Int
    sequence::Int
    send_time::Float64
    delta_tau_emit::Float64
end

struct TVATFollowerState
    last_arrival_time::Float64
    last_emit_interval::Float64
    doppler_factor::Float64
    beta_radial::Float64
    timeout::Float64
    initialized::Bool
end

function init_tvat_follower_state(base_timeout::Float64=0.150)::TVATFollowerState
    return TVATFollowerState(NaN, NaN, 1.0, 0.0, base_timeout, false)
end

@inline function tvat_doppler_factor(delta_t_obs::Float64, delta_tau_emit::Float64)::Float64
    return delta_t_obs / delta_tau_emit
end

@inline function tvat_beta_radial(D::Float64)::Float64
    D2 = D * D
    return (D2 - 1.0) / (D2 + 1.0)
end

@inline function tvat_timeout_scale(beta_radial::Float64)::Float64
    beta = clamp(beta_radial, -0.999999999999, 0.999999999999)
    return sqrt((1.0 + beta) / (1.0 - beta))
end

@inline function tvat_scaled_timeout(base_timeout::Float64, beta_radial::Float64)::Float64
    return base_timeout * tvat_timeout_scale(beta_radial)
end

function tvat_jittered_emit_interval(rng::AbstractRNG, nominal_delta_tau::Float64)::Float64
    jitter = (2.0 * rand(rng) - 1.0) * TVAT_JITTER_FRACTION
    return nominal_delta_tau * (1.0 + jitter)
end

function tvat_heartbeat(
    rng::AbstractRNG,
    leader_id::Int,
    term::Int,
    sequence::Int,
    send_time::Float64,
    nominal_delta_tau::Float64,
)::TVATHeartbeat
    return TVATHeartbeat(
        leader_id,
        term,
        sequence,
        send_time,
        tvat_jittered_emit_interval(rng, nominal_delta_tau),
    )
end

function tvat_observe_heartbeat(
    state::TVATFollowerState,
    heartbeat::TVATHeartbeat,
    arrival_time::Float64,
    base_timeout::Float64=0.150,
)::TVATFollowerState
    if !state.initialized
        return TVATFollowerState(
            arrival_time,
            heartbeat.delta_tau_emit,
            state.doppler_factor,
            state.beta_radial,
            state.timeout,
            true,
        )
    end

    delta_t_obs = arrival_time - state.last_arrival_time
    D_sample = tvat_doppler_factor(delta_t_obs, heartbeat.delta_tau_emit)
    D = TVAT_SMOOTHING_ALPHA * D_sample + (1.0 - TVAT_SMOOTHING_ALPHA) * state.doppler_factor
    beta = tvat_beta_radial(D)
    timeout = tvat_scaled_timeout(base_timeout, beta)

    return TVATFollowerState(
        arrival_time,
        heartbeat.delta_tau_emit,
        D,
        beta,
        timeout,
        true,
    )
end
