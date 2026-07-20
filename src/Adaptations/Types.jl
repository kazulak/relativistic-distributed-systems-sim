const _READY_STATUS = :ready
const _INFEASIBLE_STATUS = :infeasible
const _UNBOUNDED_STATUS = :unbounded

function _finite_nonnegative(name::AbstractString, value::Real)
    converted = Float64(value)
    isfinite(converted) && converted >= 0.0 ||
        throw(ArgumentError("$name must be finite and nonnegative"))
    return converted
end

function _finite_positive(name::AbstractString, value::Real)
    converted = Float64(value)
    isfinite(converted) && converted > 0.0 ||
        throw(ArgumentError("$name must be finite and positive"))
    return converted
end

function _probability(name::AbstractString, value::Real; allow_zero::Bool=true)
    converted = Float64(value)
    lower_ok = allow_zero ? converted >= 0.0 : converted > 0.0
    isfinite(converted) && lower_ok && converted <= 1.0 ||
        throw(ArgumentError("$name must be $(allow_zero ? "in [0, 1]" : "in (0, 1]")"))
    return converted
end

"""A finite local-proper-time election range, or an explicit refusal status."""
struct ElectionWindow
    status::Symbol
    minimum::Float64
    maximum::Float64
    source::Symbol
    reason::String

    function ElectionWindow(
        status::Symbol,
        minimum::Real,
        maximum::Real,
        source::Symbol,
        reason::AbstractString="",
    )
        status in (_READY_STATUS, _INFEASIBLE_STATUS, _UNBOUNDED_STATUS) ||
            throw(ArgumentError("unsupported election-window status: $status"))
        lower = Float64(minimum)
        upper = Float64(maximum)
        if status === _READY_STATUS
            isfinite(lower) && lower > 0.0 ||
                throw(ArgumentError("ready election minimum must be finite and positive"))
            isfinite(upper) && upper >= lower ||
                throw(ArgumentError("ready election maximum must be finite and no smaller than minimum"))
        else
            lower == Inf && upper == Inf ||
                throw(ArgumentError("refused election windows must use infinite bounds"))
            isempty(reason) && throw(ArgumentError("refused election windows require a reason"))
        end
        return new(status, lower, upper, source, String(reason))
    end
end

ready_election_window(minimum::Real, maximum::Real, source::Symbol) =
    ElectionWindow(_READY_STATUS, minimum, maximum, source)

refused_election_window(status::Symbol, source::Symbol, reason::AbstractString) =
    ElectionWindow(status, Inf, Inf, source, reason)

"""Select deterministically from an election range using an externally supplied unit draw."""
function select_election_timeout(window::ElectionWindow, unit_draw::Real)
    window.status === _READY_STATUS ||
        throw(DomainError(window.status, "cannot select a timeout from a refused election window"))
    draw = Float64(unit_draw)
    isfinite(draw) && 0.0 <= draw <= 1.0 ||
        throw(ArgumentError("election timeout draw must be finite and in [0, 1]"))
    return muladd(draw, window.maximum - window.minimum, window.minimum)
end

"""A local-proper-time heartbeat interval, or an explicit refusal status."""
struct HeartbeatDecision
    status::Symbol
    interval::Float64
    source::Symbol
    reason::String

    function HeartbeatDecision(
        status::Symbol,
        interval::Real,
        source::Symbol,
        reason::AbstractString="",
    )
        status in (_READY_STATUS, _INFEASIBLE_STATUS, _UNBOUNDED_STATUS) ||
            throw(ArgumentError("unsupported heartbeat status: $status"))
        converted = Float64(interval)
        if status === _READY_STATUS
            isfinite(converted) && converted > 0.0 ||
                throw(ArgumentError("ready heartbeat interval must be finite and positive"))
        else
            converted == Inf || throw(ArgumentError("refused heartbeat decisions must use Inf"))
            isempty(reason) && throw(ArgumentError("refused heartbeat decisions require a reason"))
        end
        return new(status, converted, source, String(reason))
    end
end

"""
Known causal lower bounds expressed in the detector's local proper-time units.

`reachable=false` represents absent contact or an unbounded future path. It is
never converted into a large finite timeout.
"""
struct CausalTimingBounds
    one_way_lower_bound::Float64
    round_trip_lower_bound::Float64
    reachable::Bool
    source::Symbol

    function CausalTimingBounds(
        one_way_lower_bound::Real,
        round_trip_lower_bound::Real;
        reachable::Bool=true,
        source::Symbol=:declared_geometry,
    )
        if reachable
            one_way = _finite_nonnegative("one-way causal lower bound", one_way_lower_bound)
            round_trip = _finite_nonnegative("round-trip causal lower bound", round_trip_lower_bound)
            round_trip >= one_way ||
                throw(ArgumentError("round-trip lower bound cannot be smaller than one-way lower bound"))
            return new(one_way, round_trip, true, source)
        end
        Float64(one_way_lower_bound) == Inf && Float64(round_trip_lower_bound) == Inf ||
            throw(ArgumentError("unreachable causal bounds must be represented by Inf"))
        return new(Inf, Inf, false, source)
    end
end

unreachable_causal_bounds(source::Symbol=:no_reachable_path) =
    CausalTimingBounds(Inf, Inf; reachable=false, source=source)

abstract type AbstractElectionPolicy end
abstract type AbstractHeartbeatPolicy end

"""Election and heartbeat policies are deliberately separate and composable."""
struct TimingPolicySet{E<:AbstractElectionPolicy,H<:AbstractHeartbeatPolicy}
    election::E
    heartbeat::H
end

struct TimingDecision
    election_window::ElectionWindow
    selected_election_timeout::Float64
    heartbeat::HeartbeatDecision

    function TimingDecision(
        election_window::ElectionWindow,
        selected_election_timeout::Real,
        heartbeat::HeartbeatDecision,
    )
        selected = Float64(selected_election_timeout)
        if election_window.status === _READY_STATUS
            isfinite(selected) &&
                election_window.minimum <= selected <= election_window.maximum ||
                throw(ArgumentError("selected election timeout lies outside its window"))
        else
            selected == Inf || throw(ArgumentError("refused election decisions must select Inf"))
        end
        return new(election_window, selected, heartbeat)
    end
end

"""One named sensitivity axis; value order is retained deterministically."""
struct ParameterAxis
    name::Symbol
    values::Vector{Any}

    function ParameterAxis(name::Symbol, values)
        collected = Any[values...]
        isempty(collected) && throw(ArgumentError("parameter axis $name cannot be empty"))
        canonical_values = _canonical_config.(collected)
        allunique(canonical_values) ||
            throw(ArgumentError("parameter axis $name contains duplicate values"))
        return new(name, collected)
    end
end

function _canonical_config(value)
    if value === nothing
        return "nothing"
    elseif value isa Bool
        return value ? "true" : "false"
    elseif value isa Symbol
        return ":" * String(value)
    elseif value isa AbstractString
        return repr(String(value))
    elseif value isa Integer
        return string(nameof(typeof(value)), ":", value)
    elseif value isa Float16 || value isa Float32 || value isa Float64
        return string(nameof(typeof(value)), ":", bitstring(value))
    elseif value isa AbstractFloat
        return string(nameof(typeof(value)), ":", repr(value))
    elseif value isa NamedTuple
        entries = String[]
        for name in keys(value)
            push!(entries, String(name) * "=" * _canonical_config(getproperty(value, name)))
        end
        return "NamedTuple(" * join(entries, ",") * ")"
    elseif value isa Tuple
        return "Tuple(" * join(_canonical_config.(collect(value)), ",") * ")"
    elseif value isa AbstractVector
        return "Vector(" * join(_canonical_config.(collect(value)), ",") * ")"
    elseif value isa AbstractSet
        return "Set(" * join(sort!(_canonical_config.(collect(value))), ",") * ")"
    elseif value isa AbstractDict
        entries = [
            _canonical_config(key) * "=>" * _canonical_config(entry)
            for (key, entry) in value
        ]
        return "Dict(" * join(sort!(entries), ",") * ")"
    elseif isstructtype(typeof(value))
        entries = String[]
        for name in fieldnames(typeof(value))
            push!(entries, String(name) * "=" * _canonical_config(getfield(value, name)))
        end
        return string(nameof(typeof(value)), "(", join(entries, ","), ")")
    end
    throw(ArgumentError("configuration value of type $(typeof(value)) is not fingerprintable"))
end

"""Stable FNV-1a fingerprint over a canonical, insertion-order-independent encoding."""
function config_fingerprint(value)
    state = UInt64(0xcbf29ce484222325)
    for byte in codeunits("relativistic-adaptations-v1|" * _canonical_config(value))
        state = (state ⊻ UInt64(byte)) * UInt64(0x100000001b3)
    end
    return lowercase(string(state; base=16, pad=16))
end

function parameter_grid(axes::AbstractVector{ParameterAxis})
    names = Tuple(axis.name for axis in axes)
    allunique(names) || throw(ArgumentError("parameter-grid axis names must be unique"))
    isempty(axes) && return [NamedTuple()]
    rows = NamedTuple[]
    function visit(index::Int, chosen::Vector{Any})
        if index > length(axes)
            push!(rows, NamedTuple{names}(Tuple(chosen)))
            return
        end
        for value in axes[index].values
            push!(chosen, value)
            visit(index + 1, chosen)
            pop!(chosen)
        end
    end
    visit(1, Any[])
    return rows
end

parameter_grid(axes::ParameterAxis...) = parameter_grid(ParameterAxis[axes...])

function fingerprinted_grid(axes::ParameterAxis...)
    return [(parameters=row, fingerprint=config_fingerprint(row)) for row in parameter_grid(axes...)]
end
