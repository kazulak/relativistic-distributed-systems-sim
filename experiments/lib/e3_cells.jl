# Shared E3 design: confirmatory cells, exogenous crash schedule, arm specs,
# and the tuned-parameter file format. Used by experiments/run_e3.jl and
# experiments/tune_e3.jl. Every constant here is a preregistration decision;
# changing one requires a new addendum (see docs/DEVIATIONS.md).

using RelativisticDistributedSystemsSim
using RelativisticDistributedSystemsSim.Research
using RelativisticDistributedSystemsSim.SimulationCore: CrashNode, RecoverNode
using TOML

"""Signed pairwise relative velocity β per D_sr regime class.

D_sr convention: receiver-proper inter-arrival / source-proper emission
interval, so receding > 1 and approaching < 1. The base prereg §6 text
("approaching ≈ 1.3, receding ≈ 0.77/0.58") uses the inverse (frequency)
convention; the β values {−0.25, 0, +0.25, +0.5} are unchanged."""
const E3_REGIMES = (
    (label="approach", beta=-0.25),
    (label="stationary", beta=0.0),
    (label="recede25", beta=0.25),
    (label="recede50", beta=0.5),
)
const E3_RHOS = (0.1, 0.4)
const E3_DISRUPTIONS = ("clean", "loss5", "loss15r20")
const E3_TRAJECTORIES = (:inertial, :onset)
const E3_CLUSTER_SIZE = 5
const E3_WINDOW = ExperimentWindow(warmup_duration=5.0, measurement_duration=4.0, censor_duration=2.0)
const E3_WORKLOAD = WorkloadSpec(client_node=1, operation_count=8, read_every=2)

# Exogenous crash design (identical rule and times across arms and replicas
# within a cell; coordinate-time units, offsets from measurement start):
#
# :leader (default) — `CrashLeader` at each offset in E3_LEADER_CRASH_OFFSETS:
#   crash whichever node is the sole active leader at that instant (no-op if
#   none) and recover it E3_CRASH_DOWNTIME later. Every run with a leader at
#   the crash instant yields exactly one detection opportunity per offset at
#   a *fixed* time, which is what the paired delay estimand needs. The first
#   crash is placed right after measurement start because receding
#   formations outrun the election round-trip budget within ~1.5 time units.
# :rotating (sensitivity) — node k crashes at OFFSET + (k-1)·SPACING, recovers
#   DOWNTIME later; strictly node-exogenous, but the *time* at which the
#   leader is hit is then arm-dependent and mostly late (censored when
#   receding).
const E3_CRASH_MODE = :leader
const E3_LEADER_CRASH_OFFSETS = (1.5, 2.7)
const E3_CRASH_OFFSET = 0.2
const E3_CRASH_SPACING = 0.4
const E3_CRASH_DOWNTIME = 0.3

include(joinpath(@__DIR__, "e3_seeds.jl"))  # E3_TUNING_SEEDS, E3_REPORT_SEEDS

dsr_target(beta::Real) = sqrt((1 + beta) / (1 - beta))

function e3_crash_faults(window::ExperimentWindow=E3_WINDOW;
                         cluster_size::Int=E3_CLUSTER_SIZE, mode::Symbol=E3_CRASH_MODE)
    faults = FaultSpec[]
    start = window.warmup_end_coordinate
    if mode == :leader
        for offset in E3_LEADER_CRASH_OFFSETS
            push!(faults, FaultSpec(start + offset, CrashLeader(E3_CRASH_DOWNTIME)))
        end
    elseif mode == :rotating
        for node in 1:cluster_size
            crash_at = start + E3_CRASH_OFFSET + (node - 1) * E3_CRASH_SPACING
            push!(faults, FaultSpec(crash_at, CrashNode(node)))
            push!(faults, FaultSpec(crash_at + E3_CRASH_DOWNTIME, RecoverNode(node)))
        end
    else
        throw(ArgumentError("unknown crash mode $mode"))
    end
    return faults
end

function e3_network(kind::AbstractString)
    kind == "clean" && return NetworkProfile(
        processing_delay=0.001, delay_jitter=0.001, bandwidth_bytes_per_time=100_000.0)
    kind == "loss5" && return NetworkProfile(
        loss_probability=0.05, processing_delay=0.001, delay_jitter=0.001,
        bandwidth_bytes_per_time=100_000.0)
    kind == "loss15r20" && return NetworkProfile(
        loss_probability=0.15, reorder_probability=0.20, reorder_delay=0.05,
        processing_delay=0.002, delay_jitter=0.004, bandwidth_bytes_per_time=80_000.0)
    throw(ArgumentError("unknown disruption $kind"))
end

struct E3Cell
    id::String
    regime::String
    beta::Float64
    dsr_target::Float64
    rho::Float64
    disruption::String
    trajectory::Symbol
    config::ScenarioConfig
end

e3_cell_id(regime, rho, disruption, trajectory) = "$(regime)_r$(rho)_$(disruption)_$(trajectory)"

"""All confirmatory cells whose id starts with any of `prefixes` (all if empty)."""
function build_e3_cells(; prefixes::AbstractVector{<:AbstractString}=String[],
                         crash_mode::Symbol=E3_CRASH_MODE)
    cells = E3Cell[]
    for regime in E3_REGIMES, rho in E3_RHOS, disruption in E3_DISRUPTIONS, trajectory in E3_TRAJECTORIES
        id = e3_cell_id(regime.label, rho, disruption, trajectory)
        isempty(prefixes) || any(prefix -> startswith(id, prefix), prefixes) || continue
        config = dsr_regime_scenario(
            beta=regime.beta,
            rho=rho,
            trajectory=trajectory,
            cluster_size=E3_CLUSTER_SIZE,
            name=Symbol(id),
            window=E3_WINDOW,
            workload=E3_WORKLOAD,
            network=e3_network(disruption),
            faults=e3_crash_faults(E3_WINDOW; mode=crash_mode),
        )
        push!(cells, E3Cell(id, regime.label, regime.beta, dsr_target(regime.beta),
                            rho, disruption, trajectory, config))
    end
    return cells
end

"""Design-side D_sr and ρ summary of one cell (all ordered pairs)."""
function e3_cell_geometry(cell::E3Cell)
    window = cell.config.window
    times = (
        start=window.warmup_end_coordinate,
        mid=(window.warmup_end_coordinate + window.measurement_end_coordinate) / 2,
        late=window.measurement_end_coordinate - 0.25,
    )
    summary = Dict{String,Any}()
    for (label, t) in pairs(times)
        ratios = filter(!isnan, vec(dsr_pairwise_ratios(cell.config, t)))
        sorted = sort(ratios)
        summary["dsr_$(label)_min"] = first(sorted)
        summary["dsr_$(label)_median"] = sorted[(length(sorted) + 1) ÷ 2]
        summary["dsr_$(label)_max"] = last(sorted)
        summary["rho_nn_$(label)"] = nearest_neighbour_rho(cell.config, t)
    end
    return summary
end

# ---------------------------------------------------------------------------
# Arms
# ---------------------------------------------------------------------------

const E3_ARM_NAMES = ("B0", "B1", "B2", "B3", "B4", "B5", "P1", "P2", "P3", "O0")
const E3_ARM_LEVELS = Dict("B0" => 0, "B1" => 0, "B2" => 0, "B3" => 0, "B4" => 0,
                           "B5" => 0, "P1" => 1, "P2" => 2, "P3" => 3, "O0" => 0)

"""Untuned r2/r3 defaults (pipeline smoke only; never confirmatory)."""
function default_arm_spec(arm::AbstractString)
    level = E3_ARM_LEVELS[arm]
    base = Dict("B0" => 1.2, "B1" => 2.5, "B2" => 0.6, "B3" => 0.7, "B4" => 0.7,
                "B5" => 0.7, "P1" => 0.9, "P2" => 0.9, "P3" => 0.9, "O0" => 1.2)[arm]
    arm == "O0" && return TimingSpec(arm=:O0, level=0, base_timeout=base, miss_tolerance=2.5)
    return TimingSpec(arm=Symbol(arm), level=level, base_timeout=base)
end

const _SPEC_FIELDS = (:base_timeout, :backoff_factor, :window_capacity, :quantile_low,
                      :quantile_high, :phi_threshold, :band_z_low, :band_z_high,
                      :warmup_observations, :reset_on_crash, :ewma_alpha, :miss_tolerance)

function spec_to_dict(spec::TimingSpec)
    record = Dict{String,Any}(
        "arm" => String(spec.arm),
        "level" => spec.level,
        "budget_min" => spec.budget.minimum,
        "budget_max" => spec.budget.maximum,
        "fingerprint" => timing_fingerprint(spec),
    )
    for field in _SPEC_FIELDS
        record[String(field)] = getfield(spec, field)
    end
    return record
end

function spec_from_dict(record::AbstractDict)
    kwargs = Dict{Symbol,Any}(field => record[String(field)] for field in _SPEC_FIELDS)
    spec = TimingSpec(;
        arm=Symbol(record["arm"]),
        level=record["level"],
        budget=TimingBudget(record["budget_min"], record["budget_max"]),
        kwargs...,
    )
    if haskey(record, "fingerprint") && record["fingerprint"] != timing_fingerprint(spec)
        error("tuned spec fingerprint mismatch for $(record["arm"]): file says " *
              "$(record["fingerprint"]), recomputed $(timing_fingerprint(spec))")
    end
    return spec
end

"""
    load_tuned(path) -> (specs::Dict{Tuple{String,String},TimingSpec}, meta::Dict)

Read a tuned-parameter TOML written by tune_e3.jl; keys are (arm, regime).
Fingerprints are re-verified.
"""
function load_tuned(path::AbstractString)
    data = TOML.parsefile(path)
    get(data, "schema", "") == "e3-tuned-v1" || error("$path is not an e3-tuned-v1 file")
    specs = Dict{Tuple{String,String},TimingSpec}()
    for (arm, regimes) in data["specs"], (regime, record) in regimes
        specs[(arm, regime)] = spec_from_dict(record)
    end
    meta = Dict{String,Any}(k => v for (k, v) in data if k != "specs")
    return specs, meta
end

"""Spec for (arm, regime): tuned if available, else the untuned default."""
function arm_spec(tuned, arm::AbstractString, regime::AbstractString)
    isnothing(tuned) && return default_arm_spec(arm)
    haskey(tuned, (arm, regime)) || error("tuned file has no spec for arm $arm, regime $regime")
    return tuned[(arm, regime)]
end
