using StaticArrays
using DoubleFloats

const LIGHT_TIME_MAX_NEWTON_ITERS = 20
const LIGHT_TIME_TOL = 1.0e-12
const LIGHT_TIME_BISECTION_ITERS = 96
const LIGHT_TIME_DOUBLE_BISECTION_ITERS = 5

struct LightTimeResult
    tB::Float64
    iterations::Int
    converged_newton::Bool
end

@inline function _lt_dot(a::SVector{3,Float64}, b::SVector{3,Float64})::Float64
    @inbounds return muladd(a[1], b[1], muladd(a[2], b[2], a[3] * b[3]))
end

@inline function _lt_norm(a::SVector{3,Float64})::Float64
    @inbounds return sqrt(muladd(a[1], a[1], muladd(a[2], a[2], a[3] * a[3])))
end

@inline function _lt_f(
    tB::Float64,
    tA::Float64,
    xA::SVector{3,Float64},
    xB_func,
    c_sim::Float64,
)::Float64
    @inbounds r = xB_func(tB) - xA
    return _lt_norm(r) - c_sim * (tB - tA)
end

@noinline function _bisect_light_time(
    tA::Float64,
    xA::SVector{3,Float64},
    xB_func,
    c_sim::Float64,
    lo::Float64,
    hi::Float64,
)::Float64
    flo = _lt_f(lo, tA, xA, xB_func, c_sim)
    if flo == 0.0
        return lo
    end

    for _ in 1:(LIGHT_TIME_BISECTION_ITERS - LIGHT_TIME_DOUBLE_BISECTION_ITERS)
        mid = 0.5 * (lo + hi)
        fmid = _lt_f(mid, tA, xA, xB_func, c_sim)
        if fmid == 0.0
            return mid
        elseif signbit(fmid) == signbit(flo)
            lo = mid
            flo = fmid
        else
            hi = mid
        end
    end

    dlo = Double64(lo)
    dhi = Double64(hi)
    for _ in 1:LIGHT_TIME_DOUBLE_BISECTION_ITERS
        dmid = (dlo + dhi) / Double64(2.0)
        mid = Float64(dmid)
        fmid = _lt_f(mid, tA, xA, xB_func, c_sim)
        if fmid == 0.0
            return mid
        elseif signbit(fmid) == signbit(flo)
            dlo = dmid
            flo = fmid
        else
            dhi = dmid
        end
    end

    return Float64((dlo + dhi) / Double64(2.0))
end

function solve_light_time_result(
    tA::Float64,
    xA::SVector{3,Float64},
    xB_func,
    vB_func,
    c_sim::Float64,
)::LightTimeResult
    gc_state = ccall(:jl_gc_enable, Int32, (Int32,), 0)
    try
        return _solve_light_time_result_nogc(tA, xA, xB_func, vB_func, c_sim)
    finally
        ccall(:jl_gc_enable, Int32, (Int32,), gc_state)
    end
end

function _solve_light_time_result_nogc(
    tA::Float64,
    xA::SVector{3,Float64},
    xB_func,
    vB_func,
    c_sim::Float64,
)::LightTimeResult
    xB_at_emit = xB_func(tA)
    r0 = xB_at_emit - xA
    radius0 = _lt_norm(r0)
    if radius0 == 0.0
        return LightTimeResult(tA, 0, true)
    end

    v0 = vB_func(tA)
    radial_v0 = _lt_dot(r0, v0) / radius0
    seed_denom = c_sim - radial_v0
    t = if isfinite(seed_denom) && seed_denom > eps(Float64) * c_sim
        tA + radius0 / seed_denom
    else
        tA + radius0 / c_sim
    end

    for iter in 1:LIGHT_TIME_MAX_NEWTON_ITERS
        @inbounds r = xB_func(t) - xA
        radius = _lt_norm(r)
        f = radius - c_sim * (t - tA)
        if abs(f) <= LIGHT_TIME_TOL
            return LightTimeResult(t, iter, true)
        end

        if radius == 0.0
            break
        end

        v = vB_func(t)
        denom = _lt_dot(r, v) / radius - c_sim
        if !isfinite(denom) || abs(denom) <= eps(Float64) * c_sim
            break
        end

        t_next = t - f / denom
        if !isfinite(t_next) || t_next < tA
            break
        end
        if abs(_lt_f(t_next, tA, xA, xB_func, c_sim)) <= LIGHT_TIME_TOL
            return LightTimeResult(t_next, iter, true)
        end
        t = t_next
    end

    lo = tA
    hi = max(t, tA + max(radius0 / c_sim, eps(Float64)))
    fhi = _lt_f(hi, tA, xA, xB_func, c_sim)
    expansions = 0
    while fhi > 0.0 && expansions < 128
        hi = tA + 2.0 * (hi - tA + eps(Float64))
        fhi = _lt_f(hi, tA, xA, xB_func, c_sim)
        expansions += 1
    end
    if fhi > 0.0
        throw(ArgumentError("receiver worldline does not intersect future light cone"))
    end

    tB = _bisect_light_time(tA, xA, xB_func, c_sim, lo, hi)
    return LightTimeResult(
        tB,
        LIGHT_TIME_MAX_NEWTON_ITERS + expansions + LIGHT_TIME_BISECTION_ITERS,
        false,
    )
end

function solve_light_time(
    tA::Float64,
    xA::SVector{3,Float64},
    xB_func,
    vB_func,
    c_sim::Float64,
)::Float64
    gc_state = ccall(:jl_gc_enable, Int32, (Int32,), 0)
    result = _solve_light_time_result_nogc(tA, xA, xB_func, vB_func, c_sim)
    ccall(:jl_gc_enable, Int32, (Int32,), gc_state)
    return result.tB
end

@inline function minkowski_interval2(
    tA::Float64,
    xA::SVector{3,Float64},
    tB::Float64,
    xB::SVector{3,Float64},
    c_sim::Float64,
)::Float64
    dt = tB - tA
    dr = xB - xA
    return c_sim * c_sim * dt * dt - _lt_dot(dr, dr)
end
