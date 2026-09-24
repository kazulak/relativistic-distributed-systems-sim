# E3 statistics library: pure functions for the preregistered E3 analysis
# (docs/PRE_REGISTRATION_E3.md §2, §5, §7, §8, §9, §11).
#
# The only I/O is `load_runs` (reads a TSV file). Everything else takes and
# returns values. The CLIs are `experiments/analyze_e3.jl` and
# `experiments/power_analysis_e3.jl`; tests are in `test/experiments/`.
#
# Design notes:
# - Columns are always read BY HEADER NAME, never by position.
# - The estimands contain no smoothing constants. A relative effect whose
#   baseline mean is zero is reported as undefined.
# - Every resampling stream is seeded from (base seed, cell, comparison,
#   purpose) with FNV-1a, so results do not depend on iteration order.
#   Streams come from `Random.Xoshiro` and are only reproducible under the
#   same Julia version.

module E3Stats

using Random
using Statistics
using Printf

export RunRow, RunTable, AnalysisConfig, AnalysisResult,
       parse_runs, load_runs, index_rows, safety_violations,
       select_best_arrival, paired_values, paired_bootstrap, signflip_pvalue,
       holm_adjust, mcnemar_exact, wilson_ci, noninferiority_delay,
       unpaired_comparison, analyze, render_report,
       power_analysis, render_power, normcdf, norminv, parse_seed_range

# ---------------------------------------------------------------------------
# Constants from the preregistration
# ---------------------------------------------------------------------------

const REQUIRED_COLUMNS = ["cell", "arm", "seed", "status", "suspicions", "election_fires",
                          "false_suspicion_rate", "detection_n", "detection_p95"]
const OPTIONAL_COLUMNS = ["leader_present_fires", "failure_reason", "safety_ok", "role"]
const ARRIVAL_ARMS = ["B3", "B4", "B5"]          # §2: best-arrival candidates
const TREATMENT_ARMS = ["P1", "P2", "P3"]        # §8: primary family
const PRIMARY_ARM = "P2"                         # §2, §4
include(joinpath(@__DIR__, "e3_seeds.jl"))
const TUNING_SEEDS = E3_TUNING_SEEDS             # §7
const REPORT_SEEDS = E3_REPORT_SEEDS             # r4 proposal; 201–224 contaminated (D-01)

const VERDICT_ELIGIBLE = "ELIGIBLE"
const VERDICT_NOT_MET = "NOT MET"
const VERDICT_NI_FAILED = "NOT MET (non-inferiority failed)"
const VERDICT_INDETERMINATE = "INDETERMINATE"
const VERDICT_UNDEFINED = "UNDEFINED (no baseline events)"

# ---------------------------------------------------------------------------
# Parsing
# ---------------------------------------------------------------------------

"""
One run of one arm on one (cell, replica seed). `rate` is the per-replica
false-suspicion rate used by the estimand, read from `rate_column`
(default `false_suspicion_rate` = suspicions / election fires, the prereg §3
definition; `suspicions_per_follower_heartbeat` is the proposed r4
alternative). `leader_present_fires` is used only as a consistency check: a
fire while exactly one leader is alive *is* a suspicion, so
suspicions / leader_present_fires is identically 1 and is never an estimand.
`NaN` means "not observed" (only allowed on non-completed runs).
"""
struct RunRow
    cell::String
    arm::String
    seed::Int
    status::String
    suspicions::Int
    election_fires::Int
    leader_present_fires::Union{Missing,Int}
    rate::Float64
    detection_n::Int
    detection_p95::Float64
    failure_reason::String
    safety_ok::Union{Missing,Bool}
    role::Union{Missing,String}
end

is_completed(r::RunRow) = r.status == "completed"

struct RunTable
    rows::Vector{RunRow}
    source::String
    columns::Vector{String}
    has_leader_present_fires::Bool
    has_safety_ok::Bool
    has_role::Bool
    has_failure_reason::Bool
end

Base.length(t::RunTable) = length(t.rows)

function _int_or_nothing(s::AbstractString)
    s = strip(s)
    isempty(s) && return nothing
    v = tryparse(Int, s)
    v === nothing || return v
    f = tryparse(Float64, s)
    (f !== nothing && isfinite(f) && isinteger(f)) && return Int(f)
    return nothing
end

function _float_or_nan(s::AbstractString)
    s = strip(s)
    isempty(s) && return NaN
    v = tryparse(Float64, s)
    return v === nothing ? NaN : v
end

function _bool_or_missing(s::AbstractString, where_::String)
    t = lowercase(strip(s))
    isempty(t) && return missing
    t in ("true", "1", "yes") && return true
    t in ("false", "0", "no") && return false
    throw(ArgumentError("$where_: cannot parse safety_ok value '$s'"))
end

"""
    parse_seed_range(s) -> UnitRange{Int}

Parse `"a:b"` or `"a-b"` into `a:b`.
"""
function parse_seed_range(s::AbstractString)
    m = match(r"^\s*(\d+)\s*[:\-]\s*(\d+)\s*$", s)
    m === nothing && throw(ArgumentError("seed range must look like 'a:b', got '$s'"))
    a, b = parse(Int, m[1]), parse(Int, m[2])
    a <= b || throw(ArgumentError("empty seed range '$s'"))
    return a:b
end

"""
    parse_runs(io; source, seeds=nothing) -> RunTable

Parse a runs TSV by header name. Required columns: $(join(REQUIRED_COLUMNS, ", ")).
Optional: $(join(OPTIONAL_COLUMNS, ", ")). `seeds` (a range or collection)
keeps only rows whose replica seed is in it. Errors on missing required
columns, ragged rows, duplicate (cell, arm, seed) rows, unparseable required
values on completed runs, and `suspicions > leader_present_fires`.
"""
function parse_runs(io::IO; source::AbstractString="<io>", seeds=nothing,
                    rate_column::AbstractString="false_suspicion_rate")
    header = String[]
    col = Dict{String,Int}()
    rows = RunRow[]
    seen = Set{Tuple{String,String,Int}}()
    for (lineno, raw) in enumerate(eachline(io))
        line = rstrip(raw, '\r')
        isempty(strip(line)) && continue
        if isempty(header)
            header = String.(strip.(split(line, '\t')))
            for (i, name) in enumerate(header)
                haskey(col, name) && throw(ArgumentError("$source: duplicate column '$name' in header"))
                col[name] = i
            end
            missing_cols = [c for c in REQUIRED_COLUMNS if !haskey(col, c)]
            isempty(missing_cols) ||
                throw(ArgumentError("$source: missing required column(s): $(join(missing_cols, ", "))"))
            continue
        end
        fields = split(line, '\t')
        length(fields) == length(header) ||
            throw(ArgumentError("$source:$lineno: expected $(length(header)) fields, got $(length(fields))"))
        get_(name) = fields[col[name]]
        where_ = "$source:$lineno"

        seed = _int_or_nothing(get_("seed"))
        seed === nothing && throw(ArgumentError("$where_: unparseable seed '$(get_("seed"))'"))
        (seeds === nothing || seed in seeds) || continue

        cell = String(strip(get_("cell")))
        arm = String(strip(get_("arm")))
        status = String(strip(get_("status")))
        key = (cell, arm, seed)
        key in seen && throw(ArgumentError("$where_: duplicate row for cell=$cell arm=$arm seed=$seed (prereg §7 forbids reruns)"))
        push!(seen, key)
        completed = status == "completed"

        susp = _int_or_nothing(get_("suspicions"))
        fires = _int_or_nothing(get_("election_fires"))
        detn = _int_or_nothing(get_("detection_n"))
        p95 = _float_or_nan(get_("detection_p95"))
        lpf = haskey(col, "leader_present_fires") ? _int_or_nothing(get_("leader_present_fires")) : nothing
        if completed
            susp === nothing && throw(ArgumentError("$where_: completed run with unparseable suspicions"))
            fires === nothing && throw(ArgumentError("$where_: completed run with unparseable election_fires"))
            detn === nothing && throw(ArgumentError("$where_: completed run with unparseable detection_n"))
            if haskey(col, "leader_present_fires") && lpf === nothing
                throw(ArgumentError("$where_: completed run with unparseable leader_present_fires"))
            end
        end
        detn_v = something(detn, 0)
        if completed && detn_v > 0 && isnan(p95)
            throw(ArgumentError("$where_: detection_n=$detn_v but detection_p95 is empty"))
        end

        if haskey(col, "leader_present_fires") && lpf !== nothing && susp !== nothing
            susp <= lpf || throw(ArgumentError("$where_: suspicions ($susp) > leader_present_fires ($lpf)"))
        end
        haskey(col, rate_column) ||
            throw(ArgumentError("$source: rate column '$rate_column' not present"))
        rate = _float_or_nan(get_(rate_column))
        # No election fires (or no follower heartbeats) means no opportunity
        # for a false suspicion: the rate is 0 (documented choice).
        if isnan(rate) && susp == 0
            rate = 0.0
        end
        completed && isnan(rate) && throw(ArgumentError("$where_: completed run without a usable false-suspicion rate"))

        push!(rows, RunRow(
            cell, arm, seed, status,
            something(susp, 0), something(fires, 0),
            lpf === nothing ? missing : lpf,
            rate, detn_v, p95,
            haskey(col, "failure_reason") ? String(strip(get_("failure_reason"))) : "",
            haskey(col, "safety_ok") ? _bool_or_missing(get_("safety_ok"), where_) : missing,
            haskey(col, "role") ? (isempty(strip(get_("role"))) ? missing : String(strip(get_("role")))) : missing,
        ))
    end
    isempty(header) && throw(ArgumentError("$source: empty file (no header)"))
    return RunTable(rows, String(source), header,
                    haskey(col, "leader_present_fires"), haskey(col, "safety_ok"),
                    haskey(col, "role"), haskey(col, "failure_reason"))
end

parse_runs(s::AbstractString; kwargs...) = parse_runs(IOBuffer(s); kwargs...)

"""
    load_runs(path; seeds=nothing) -> RunTable
"""
function load_runs(path::AbstractString; seeds=nothing,
                   rate_column::AbstractString="false_suspicion_rate")
    isfile(path) || throw(ArgumentError("file not found: $path"))
    return open(io -> parse_runs(io; source=path, seeds=seeds, rate_column=rate_column), path)
end

const RowIndex = Dict{String,Dict{String,Dict{Int,RunRow}}}

"""
    index_rows(rows) -> cell => arm => seed => RunRow
"""
function index_rows(rows::AbstractVector{RunRow})
    idx = RowIndex()
    for r in rows
        arms = get!(idx, r.cell, Dict{String,Dict{Int,RunRow}}())
        seeds = get!(arms, r.arm, Dict{Int,RunRow}())
        haskey(seeds, r.seed) && throw(ArgumentError("duplicate row cell=$(r.cell) arm=$(r.arm) seed=$(r.seed)"))
        seeds[r.seed] = r
    end
    return idx
end

"""
    safety_violations(rows) -> Vector{RunRow}

Rows whose `safety_ok` is explicitly `false` (prereg §11 halt rule). Rows
without the column (`missing`) are not violations but are reported as
"unchecked" by the analyzer.
"""
safety_violations(rows::AbstractVector{RunRow}) = [r for r in rows if r.safety_ok === false]

# ---------------------------------------------------------------------------
# Small numeric helpers (no SpecialFunctions dependency)
# ---------------------------------------------------------------------------

"FNV-1a 64-bit over the joined parts; used to derive per-comparison RNG seeds."
function stream_seed(base::Integer, parts...)
    h = 0xcbf29ce484222325
    for byte in codeunits(string(base, "|", join(string.(parts), "|")))
        h = (h ⊻ UInt64(byte)) * 0x100000001b3
    end
    return h
end

stream_rng(base::Integer, parts...) = Xoshiro(stream_seed(base, parts...))

"Standard normal CDF (erfc approximation of Numerical Recipes, |rel. error| < 1.2e-7)."
function normcdf(x::Real)
    z = abs(x) / sqrt(2.0)
    t = 1.0 / (1.0 + 0.5 * z)
    erfc_ = t * exp(-z * z - 1.26551223 + t * (1.00002368 + t * (0.37409196 + t * (0.09678418 +
            t * (-0.18628806 + t * (0.27886807 + t * (-1.13520398 + t * (1.48851587 +
            t * (-0.82215223 + t * 0.17087277)))))))))
    return x >= 0 ? 1.0 - 0.5 * erfc_ : 0.5 * erfc_
end

"Standard normal quantile (Acklam's rational approximation, |error| < 1.2e-9)."
function norminv(p::Real)
    0 < p < 1 || throw(DomainError(p, "norminv needs 0 < p < 1"))
    a = (-3.969683028665376e+01, 2.209460984245205e+02, -2.759285104469687e+02,
         1.383577518672690e+02, -3.066479806614716e+01, 2.506628277459239e+00)
    b = (-5.447609879822406e+01, 1.615858368580409e+02, -1.556989798598866e+02,
         6.680131188771972e+01, -1.328068155288572e+01)
    c = (-7.784894002430293e-03, -3.223964580411365e-01, -2.400758277161838e+00,
         -2.549732539343734e+00, 4.374664141464968e+00, 2.938163982698783e+00)
    d = (7.784695709041462e-03, 3.224671290700398e-01, 2.445134137142996e+00,
         3.754408661907416e+00)
    plow = 0.02425
    if p < plow
        q = sqrt(-2log(p))
        return (((((c[1]q + c[2])q + c[3])q + c[4])q + c[5])q + c[6]) /
               ((((d[1]q + d[2])q + d[3])q + d[4])q + 1)
    elseif p <= 1 - plow
        q = p - 0.5
        r = q * q
        return (((((a[1]r + a[2])r + a[3])r + a[4])r + a[5])r + a[6])q /
               (((((b[1]r + b[2])r + b[3])r + b[4])r + b[5])r + 1)
    else
        q = sqrt(-2log(1 - p))
        return -(((((c[1]q + c[2])q + c[3])q + c[4])q + c[5])q + c[6]) /
               ((((d[1]q + d[2])q + d[3])q + d[4])q + 1)
    end
end

"Nearest-rank percentile of an already sorted vector (works with ±Inf entries)."
function pct_sorted(v::AbstractVector{<:Real}, q::Real)
    isempty(v) && return NaN
    return v[clamp(ceil(Int, q * length(v)), 1, length(v))]
end

"Relative reduction 1 − t/b of two means (or sums); -Inf when b == 0 < t, NaN when both are 0."
function rel_reduction(t::Real, b::Real)
    b > 0 && return 1.0 - t / b
    return t > 0 ? -Inf : NaN
end

"""
    holm_adjust(p) -> adjusted p-values (same order as input)

Holm step-down: with p sorted ascending p_(1) ≤ … ≤ p_(m),
adj_(i) = max_{j ≤ i} min(1, (m − j + 1)·p_(j)). Reject H_(i) iff adj_(i) ≤ α.
"""
function holm_adjust(p::AbstractVector{<:Real})
    any(x -> isnan(x) || x < 0 || x > 1, p) && throw(ArgumentError("p-values must lie in [0, 1]"))
    m = length(p)
    order = sortperm(p)                # stable: ties keep input order
    adj = zeros(Float64, m)
    running = 0.0
    for (i, k) in enumerate(order)
        running = max(running, min(1.0, (m - i + 1) * p[k]))
        adj[k] = running
    end
    return adj
end

"""
    mcnemar_exact(b, c) -> two-sided exact p-value

Exact McNemar test on the discordant counts `b` and `c` (binomial with
n = b + c, π = 1/2). Returns 1.0 when there are no discordant pairs.
"""
function mcnemar_exact(b::Integer, c::Integer)
    n = b + c
    n == 0 && return 1.0
    k = min(b, c)
    # log C(n, j) accumulated iteratively; tail = P(X ≤ k)
    logc = 0.0
    tail = 0.0
    for j in 0:k
        j > 0 && (logc += log((n - j + 1) / j))
        tail += exp(logc + n * log(0.5))
    end
    return min(1.0, 2tail)
end

"Wilson score 95% interval for k successes out of n."
function wilson_ci(k::Integer, n::Integer; z::Real=1.959963984540054)
    n == 0 && return (NaN, NaN)
    p = k / n
    denom = 1 + z^2 / n
    centre = (p + z^2 / (2n)) / denom
    half = z * sqrt(p * (1 - p) / n + z^2 / (4n^2)) / denom
    return (max(0.0, centre - half), min(1.0, centre + half))
end

# ---------------------------------------------------------------------------
# Best-arrival selection (tuning data only)
# ---------------------------------------------------------------------------

"""
    select_best_arrival(tuning_rows; arms=["B3","B4","B5"]) -> NamedTuple

Choose best-arrival on TUNING rows by mean false-suspicion rate. Only
completed runs are used. The score of an arm is the mean over cells of its
per-cell mean rate, restricted to cells where every candidate arm has at
least one completed run (so all arms are scored on the same cells). Ties
break in the order of `arms`. Also returns a per-cell choice (the same rule
applied cell by cell) for the per-cell scope sensitivity option.
"""
function select_best_arrival(rows::AbstractVector{RunRow}; arms::AbstractVector{<:AbstractString}=ARRIVAL_ARMS)
    isempty(rows) && throw(ArgumentError("best-arrival selection needs tuning rows; none were given"))
    idx = index_rows(rows)
    percell = Dict{String,Dict{String,Float64}}()
    for (cell, byarm) in idx
        means = Dict{String,Float64}()
        for a in arms
            haskey(byarm, a) || continue
            vals = [r.rate for r in values(byarm[a]) if is_completed(r)]
            isempty(vals) || (means[a] = mean(vals))
        end
        percell[cell] = means
    end
    common = sort([c for (c, m) in percell if all(a -> haskey(m, a), arms)])
    isempty(common) && throw(ArgumentError("no tuning cell has completed runs for all of $(join(arms, ", "))"))
    scores = Dict(a => mean(percell[c][a] for c in common) for a in arms)
    best = arms[argmin([scores[a] for a in arms])]   # argmin returns the first minimum
    per_cell = Dict{String,String}()
    for c in common
        per_cell[c] = arms[argmin([percell[c][a] for a in arms])]
    end
    return (best=String(best), scores=scores, n_cells=length(common), cells=common, per_cell=per_cell,
            per_cell_means=percell)
end

# ---------------------------------------------------------------------------
# Pairing and resampling
# ---------------------------------------------------------------------------

"""
    paired_values(idx, cell, t_arm, b_arm; policy=:pairwise_exclude, metric=:rate)

Pair treatment and baseline runs on replica seed within `cell`.
`policy = :pairwise_exclude` drops a pair when either run is not completed;
`:include_failed` keeps recorded values of failed runs (sensitivity).
`metric = :rate` pairs false-suspicion rates; `:delay_p95` pairs
`detection_p95` over pairs where both runs have `detection_n > 0`.
Returns `(seeds, t, b, excluded_status, absent, no_value)`.
"""
function paired_values(idx::RowIndex, cell::AbstractString, t_arm::AbstractString, b_arm::AbstractString;
                       policy::Symbol=:pairwise_exclude, metric::Symbol=:rate)
    policy in (:pairwise_exclude, :include_failed) || throw(ArgumentError("unknown status policy $policy"))
    byarm = get(idx, cell, Dict{String,Dict{Int,RunRow}}())
    tr = get(byarm, t_arm, Dict{Int,RunRow}())
    br = get(byarm, b_arm, Dict{Int,RunRow}())
    seeds = Int[]; t = Float64[]; b = Float64[]
    excluded = 0; absent = 0; novalue = 0
    for s in sort(collect(union(keys(tr), keys(br))))
        if !(haskey(tr, s) && haskey(br, s))
            absent += 1
            continue
        end
        x, y = tr[s], br[s]
        if policy == :pairwise_exclude && !(is_completed(x) && is_completed(y))
            excluded += 1
            continue
        end
        if metric == :rate
            vx, vy = x.rate, y.rate
        elseif metric == :delay_p95
            if x.detection_n > 0 && y.detection_n > 0
                vx, vy = x.detection_p95, y.detection_p95
            else
                vx, vy = NaN, NaN
            end
        else
            throw(ArgumentError("unknown metric $metric"))
        end
        if isnan(vx) || isnan(vy)
            novalue += 1
            continue
        end
        push!(seeds, s); push!(t, vx); push!(b, vy)
    end
    return (seeds=seeds, t=t, b=b, excluded_status=excluded, absent=absent, no_value=novalue)
end

"""
    paired_bootstrap(t, b; resamples, rng) -> NamedTuple

Paired cluster bootstrap over replicas: each resample draws replica indices
with replacement and keeps each replica's (t, b) pair together. Returns the
sorted bootstrap distributions of the relative reduction 1 − mean(t*)/mean(b*)
(undefined resamples, where both means are 0, are dropped and counted) and of
the absolute reduction mean(b*) − mean(t*).
"""
function paired_bootstrap(t::AbstractVector{<:Real}, b::AbstractVector{<:Real}; resamples::Int=10_000, rng::AbstractRNG)
    n = length(t)
    n == length(b) || throw(ArgumentError("paired vectors differ in length"))
    n >= 1 || throw(ArgumentError("paired bootstrap needs at least one pair"))
    rel = Float64[]; sizehint!(rel, resamples)
    diff = Vector{Float64}(undef, resamples)
    undefined = 0
    for r in 1:resamples
        st = 0.0; sb = 0.0
        @inbounds for _ in 1:n
            i = rand(rng, 1:n)
            st += t[i]; sb += b[i]
        end
        diff[r] = (sb - st) / n
        x = rel_reduction(st, sb)
        isnan(x) ? (undefined += 1) : push!(rel, x)
    end
    sort!(rel); sort!(diff)
    return (rel=rel, diff=diff, rel_undefined=undefined, resamples=resamples)
end

"""
    signflip_pvalue(d; resamples, rng) -> two-sided p-value

Paired sign-flip permutation test of H0: the within-replica arm labels are
exchangeable (so mean(d) = 0, equivalently relative reduction = 0), with
statistic |Σ d|. Exact enumeration for n ≤ 13; otherwise Monte Carlo with
the (count + 1)/(R + 1) correction, which keeps the test valid.
"""
function signflip_pvalue(d::AbstractVector{<:Real}; resamples::Int=10_000, rng::AbstractRNG)
    n = length(d)
    n == 0 && return 1.0
    obs = abs(sum(d))
    obs == 0 && return 1.0
    tol = 1e-10 * max(1.0, obs)
    if n <= 13
        count = 0
        for mask in 0:(2^n - 1)
            s = 0.0
            for i in 1:n
                s += ((mask >> (i - 1)) & 1) == 1 ? -d[i] : d[i]
            end
            abs(s) >= obs - tol && (count += 1)
        end
        return count / 2^n
    end
    count = 0
    for _ in 1:resamples
        s = 0.0
        @inbounds for i in 1:n
            s += rand(rng, Bool) ? d[i] : -d[i]
        end
        abs(s) >= obs - tol && (count += 1)
    end
    return (count + 1) / (resamples + 1)
end

# ---------------------------------------------------------------------------
# Comparisons
# ---------------------------------------------------------------------------

struct Comparison
    cell::String
    treatment::String
    baseline::String
    n_pairs::Int
    excluded_status::Int
    absent::Int
    mean_t::Float64
    mean_b::Float64
    baseline_events::Int          # total suspicions in the baseline arm over used pairs
    rel::Float64                  # 1 − mean_t/mean_b; NaN when mean_b == 0 (undefined)
    rel_ci::Tuple{Float64,Float64}
    rel_boot_undefined::Int
    diff::Float64                 # mean_b − mean_t (positive = treatment better)
    diff_ci::Tuple{Float64,Float64}
    p::Float64                    # two-sided sign-flip p for H0: no difference
end

rel_defined(c::Comparison) = c.mean_b > 0

function compare_paired(idx::RowIndex, cell, t_arm, b_arm; policy, resamples, rng_seed, purpose="primary")
    pv = paired_values(idx, cell, t_arm, b_arm; policy=policy, metric=:rate)
    n = length(pv.t)
    if n == 0
        return Comparison(cell, t_arm, b_arm, 0, pv.excluded_status, pv.absent, NaN, NaN, 0,
                          NaN, (NaN, NaN), 0, NaN, (NaN, NaN), 1.0)
    end
    byarm = idx[cell]
    events = sum(byarm[b_arm][s].suspicions for s in pv.seeds)
    mt, mb = mean(pv.t), mean(pv.b)
    boot = paired_bootstrap(pv.t, pv.b; resamples=resamples, rng=stream_rng(rng_seed, cell, t_arm, b_arm, purpose, "boot"))
    rel = mb > 0 ? 1.0 - mt / mb : NaN
    rel_ci = mb > 0 ? (pct_sorted(boot.rel, 0.025), pct_sorted(boot.rel, 0.975)) : (NaN, NaN)
    diff_ci = (pct_sorted(boot.diff, 0.025), pct_sorted(boot.diff, 0.975))
    p = signflip_pvalue(pv.b .- pv.t; resamples=resamples, rng=stream_rng(rng_seed, cell, t_arm, b_arm, purpose, "signflip"))
    return Comparison(cell, t_arm, b_arm, n, pv.excluded_status, pv.absent, mt, mb, events,
                      rel, rel_ci, mb > 0 ? boot.rel_undefined : 0, mb - mt, diff_ci, p)
end

struct NonInferiority
    cell::String
    treatment::String
    baseline::String
    n_pairs::Int
    detections_t::Int
    detections_b::Int
    estimable::Bool
    reason::String
    rel_change::Float64               # mean p95_t / mean p95_b − 1 (positive = treatment slower)
    upper::Float64                    # one-sided 95% bootstrap upper bound
    p::Float64                        # one-sided p for H0: rel_change ≥ margin
end

"""
    noninferiority_delay(t, b; margin=0.05, alpha=0.05, min_pairs=10, resamples, rng)

P2 non-inferiority on p95 crash-detection delay (prereg §2): estimand
mean(p95_T)/mean(p95_B) − 1 over replica pairs where both arms detected at
least one crash. H0: change ≥ +margin; H1: change < +margin. `upper` is the
one-sided (1 − alpha) percentile bootstrap bound; the p-value is the
bootstrap-inverted p = (#{change* ≥ margin} + 1)/(R + 1), consistent with the
bound. Fewer than `min_pairs` pairs → not estimable (never "passes").
"""
function noninferiority_delay(t::AbstractVector{<:Real}, b::AbstractVector{<:Real}; margin::Real=0.05,
                              alpha::Real=0.05, min_pairs::Int=10, resamples::Int=10_000, rng::AbstractRNG)
    n = length(t)
    if n < min_pairs
        return (estimable=false, reason="NOT ESTIMABLE: $n paired replicas with crash detections in both arms (< $min_pairs)",
                rel_change=NaN, upper=NaN, p=1.0, n=n)
    end
    mb = mean(b)
    if !(mb > 0)
        return (estimable=false, reason="NOT ESTIMABLE: baseline mean p95 delay is not positive",
                rel_change=NaN, upper=NaN, p=1.0, n=n)
    end
    est = mean(t) / mb - 1
    draws = Float64[]
    for _ in 1:resamples
        st = 0.0; sb = 0.0
        for _ in 1:n
            i = rand(rng, 1:n); st += t[i]; sb += b[i]
        end
        sb > 0 ? push!(draws, st / sb - 1) : push!(draws, Inf)
    end
    sort!(draws)
    upper = pct_sorted(draws, 1 - alpha)
    p = (count(>=(margin), draws) + 1) / (resamples + 1)
    return (estimable=true, reason="", rel_change=est, upper=upper, p=p, n=n)
end

function compare_ni(idx::RowIndex, cell, t_arm, b_arm; policy, resamples, rng_seed, margin, alpha, min_pairs)
    pv = paired_values(idx, cell, t_arm, b_arm; policy=policy, metric=:delay_p95)
    byarm = get(idx, cell, Dict{String,Dict{Int,RunRow}}())
    dt = sum((r.detection_n for r in values(get(byarm, t_arm, Dict{Int,RunRow}())) if is_completed(r)); init=0)
    db = sum((r.detection_n for r in values(get(byarm, b_arm, Dict{Int,RunRow}())) if is_completed(r)); init=0)
    ni = noninferiority_delay(pv.t, pv.b; margin=margin, alpha=alpha, min_pairs=min_pairs, resamples=resamples,
                              rng=stream_rng(rng_seed, cell, t_arm, b_arm, "ni"))
    return NonInferiority(cell, t_arm, b_arm, ni.n, dt, db, ni.estimable, ni.reason, ni.rel_change, ni.upper, ni.p)
end

"""
    unpaired_comparison(t, b; resamples, rng)

Unpaired sensitivity analysis (prereg §5): each arm is resampled
independently; percentile CIs for the relative and absolute reductions and a
two-sided label-permutation p-value for the difference in means.
"""
function unpaired_comparison(t::AbstractVector{<:Real}, b::AbstractVector{<:Real}; resamples::Int=10_000, rng::AbstractRNG)
    nt, nb = length(t), length(b)
    (nt == 0 || nb == 0) && return (n_t=nt, n_b=nb, rel=NaN, rel_ci=(NaN, NaN), diff=NaN, diff_ci=(NaN, NaN), p=1.0)
    mt, mb = mean(t), mean(b)
    rel = Float64[]; diff = Vector{Float64}(undef, resamples)
    for r in 1:resamples
        st = 0.0; sb = 0.0
        for _ in 1:nt; st += t[rand(rng, 1:nt)]; end
        for _ in 1:nb; sb += b[rand(rng, 1:nb)]; end
        diff[r] = sb / nb - st / nt
        x = rel_reduction(st / nt, sb / nb)
        isnan(x) || push!(rel, x)
    end
    sort!(rel); sort!(diff)
    pooled = vcat(collect(Float64, t), collect(Float64, b))
    obs = abs(mb - mt)
    tol = 1e-10 * max(1.0, obs)
    hits = 0
    for _ in 1:resamples
        shuffle!(rng, pooled)
        d = mean(@view pooled[nt+1:end]) - mean(@view pooled[1:nt])
        abs(d) >= obs - tol && (hits += 1)
    end
    p = obs == 0 ? 1.0 : (hits + 1) / (resamples + 1)
    return (n_t=nt, n_b=nb,
            rel=mb > 0 ? 1 - mt / mb : NaN,
            rel_ci=mb > 0 ? (pct_sorted(rel, 0.025), pct_sorted(rel, 0.975)) : (NaN, NaN),
            diff=mb - mt, diff_ci=(pct_sorted(diff, 0.025), pct_sorted(diff, 0.975)), p=p)
end

# ---------------------------------------------------------------------------
# Full analysis
# ---------------------------------------------------------------------------

Base.@kwdef struct AnalysisConfig
    resamples::Int = 10_000
    rng_seed::UInt64 = 0x00000000000000e3
    alpha::Float64 = 0.05
    delta::Float64 = 0.15                 # §2 minimum relative reduction
    ni_margin::Float64 = 0.05             # §2 non-inferiority margin (relative)
    ni_min_pairs::Int = 10                # not preregistered; r4 item
    status_policy::Symbol = :pairwise_exclude
    best_arrival_scope::Symbol = :global  # :global or :per_cell
    treatments::Vector{String} = copy(TREATMENT_ARMS)
    primary::String = PRIMARY_ARM
    arrival_arms::Vector{String} = copy(ARRIVAL_ARMS)
    tuning_seed_range::UnitRange{Int} = TUNING_SEEDS
    report_seed_range::UnitRange{Int} = REPORT_SEEDS
end

struct CellResult
    cell::String
    baseline::String
    comparisons::Vector{Comparison}
    ni::NonInferiority
    family::Vector{String}          # hypothesis labels in the Holm family
    family_p::Vector{Float64}
    family_p_holm::Vector{Float64}
    superiority_met::Bool
    verdict::String
    verdict_reason::String
end

struct MissingnessRow
    cell::String
    treatment::String
    baseline::String
    both_present::Int
    t_failed_b_ok::Int
    t_ok_b_failed::Int
    both_failed::Int
    p_mcnemar::Float64
end

struct AnalysisResult
    config::AnalysisConfig
    tuning_source::String
    report_source::String
    tuning_seeds::Tuple{Int,Int}
    report_seeds::Tuple{Int,Int}
    confirmatory_eligible::Bool
    eligibility_notes::Vector{String}
    halted::Bool
    violations::Vector{RunRow}
    safety_checked::Bool
    best::Any
    cells::Vector{CellResult}
    status_counts::Dict{Tuple{String,String},Tuple{Int,Int}}   # (cell, arm) => (total, non-completed)
    failure_reasons::Dict{String,Int}
    missingness::Vector{MissingnessRow}
    missingness_pooled::Dict{String,Tuple{Int,Int,Float64}}    # treatment => (b, c, p)
    differential_missingness_flag::Bool
    cross_cell_holm::Vector{Tuple{String,String,Float64,Float64}}  # (cell, hypothesis, p, adj)
    unpaired::Vector{Tuple{String,String,String,Any}}              # (cell, treatment, baseline, result)
    alt_policy::Symbol
    alt_policy_comparisons::Vector{Comparison}
    aggregate::Dict{String,Int}
    overall_verdict::String
end

_seed_span(rows) = isempty(rows) ? (0, -1) : (minimum(r.seed for r in rows), maximum(r.seed for r in rows))

function _cell_verdict(cfg::AnalysisConfig, primary::Comparison, primary_adj::Float64, ni::NonInferiority, ni_adj::Float64)
    if primary.n_pairs == 0
        return false, VERDICT_INDETERMINATE, "no paired replicas for $(primary.treatment) vs $(primary.baseline)"
    end
    if !rel_defined(primary)
        return false, VERDICT_UNDEFINED, "baseline mean false-suspicion rate is 0; relative reduction undefined"
    end
    sup = primary_adj <= cfg.alpha && primary.rel >= cfg.delta && primary.rel_ci[1] > 0
    if !sup
        why = String[]
        primary_adj <= cfg.alpha || push!(why, @sprintf("Holm p = %.4g > %.2g", primary_adj, cfg.alpha))
        primary.rel >= cfg.delta || push!(why, @sprintf("relative reduction %.3f < δ = %.2f", primary.rel, cfg.delta))
        primary.rel_ci[1] > 0 || push!(why, "95% CI does not exclude 0")
        return false, VERDICT_NOT_MET, join(why, "; ")
    end
    if !ni.estimable
        return true, VERDICT_INDETERMINATE, "superiority met but non-inferiority on p95 detection delay " * ni.reason
    end
    if ni_adj <= cfg.alpha
        return true, VERDICT_ELIGIBLE, "superiority and non-inferiority met"
    end
    return true, VERDICT_NI_FAILED, @sprintf("non-inferiority Holm p = %.4g; upper bound %+.3f vs margin %+.2f",
                                             ni_adj, ni.upper, cfg.ni_margin)
end

"""
    analyze(tuning::RunTable, report::RunTable, cfg=AnalysisConfig()) -> AnalysisResult

Run the preregistered E3 analysis. Best-arrival is selected on `tuning` only.
Refuses (ArgumentError) when tuning data is empty, when tuning and report
replica seeds overlap, or when a `role` column contradicts the split. When any
row (tuning or report) has `safety_ok == false`, returns a halted result with
no verdicts (prereg §11).
"""
function analyze(tuning::RunTable, report::RunTable, cfg::AnalysisConfig=AnalysisConfig())
    isempty(tuning.rows) && throw(ArgumentError("no tuning rows: best-arrival must be selected on tuning traces (prereg §2, §7); refusing to analyze"))
    isempty(report.rows) && throw(ArgumentError("no report rows"))
    cfg.status_policy in (:pairwise_exclude, :include_failed) || throw(ArgumentError("unknown status policy $(cfg.status_policy)"))
    cfg.best_arrival_scope in (:global, :per_cell) || throw(ArgumentError("unknown best-arrival scope $(cfg.best_arrival_scope)"))
    overlap = intersect(Set(r.seed for r in tuning.rows), Set(r.seed for r in report.rows))
    isempty(overlap) || throw(ArgumentError("tuning and report replica seeds overlap ($(length(overlap)) seeds, e.g. $(minimum(overlap))); refusing to analyze"))
    bad_t = [r for r in tuning.rows if !ismissing(r.role) && r.role != "tuning"]
    isempty(bad_t) || throw(ArgumentError("tuning input contains $(length(bad_t)) rows with role != tuning"))
    bad_r = [r for r in report.rows if !ismissing(r.role) && r.role != "report"]
    isempty(bad_r) || throw(ArgumentError("report input contains $(length(bad_r)) rows with role != report"))

    notes = String[]
    ts, rs = _seed_span(tuning.rows), _seed_span(report.rows)
    ts[1] >= first(cfg.tuning_seed_range) && ts[2] <= last(cfg.tuning_seed_range) ||
        push!(notes, "tuning seeds $(ts[1])–$(ts[2]) are outside the preregistered tuning range $(cfg.tuning_seed_range)")
    rs[1] >= first(cfg.report_seed_range) && rs[2] <= last(cfg.report_seed_range) ||
        push!(notes, "report seeds $(rs[1])–$(rs[2]) are outside the preregistered report range $(cfg.report_seed_range)")
    cfg.status_policy == :pairwise_exclude || push!(notes, "non-default run-status policy $(cfg.status_policy)")
    cfg.best_arrival_scope == :global || push!(notes, "non-default best-arrival scope $(cfg.best_arrival_scope)")
    cfg.resamples >= 10_000 || push!(notes, "fewer than the preregistered 10k bootstrap resamples ($(cfg.resamples))")
    safety_checked = tuning.has_safety_ok && report.has_safety_ok
    safety_checked || push!(notes, "safety_ok column absent: §11 halt rule cannot be checked from these files")

    violations = vcat(safety_violations(tuning.rows), safety_violations(report.rows))
    halted = !isempty(violations)
    eligible = isempty(notes) && !halted

    status_counts = Dict{Tuple{String,String},Tuple{Int,Int}}()
    reasons = Dict{String,Int}()
    for r in report.rows
        tot, bad = get(status_counts, (r.cell, r.arm), (0, 0))
        status_counts[(r.cell, r.arm)] = (tot + 1, bad + !is_completed(r))
        if !is_completed(r)
            key = isempty(r.failure_reason) ? "status=$(r.status)" : "status=$(r.status): $(r.failure_reason)"
            reasons[key] = get(reasons, key, 0) + 1
        end
    end

    empty_result(best) = AnalysisResult(cfg, tuning.source, report.source, ts, rs, false, notes, true, violations,
        safety_checked, best, CellResult[], status_counts, reasons, MissingnessRow[], Dict{String,Tuple{Int,Int,Float64}}(),
        false, Tuple{String,String,Float64,Float64}[], Tuple{String,String,String,Any}[], cfg.status_policy,
        Comparison[], Dict{String,Int}(), "HALTED: safety_ok == false on $(length(violations)) row(s); no verdicts (prereg §11)")
    halted && return empty_result(nothing)

    best = select_best_arrival(tuning.rows; arms=cfg.arrival_arms)
    idx = index_rows(report.rows)
    cells = sort(collect(keys(idx)))
    results = CellResult[]
    missingness = MissingnessRow[]
    unpaired = Tuple{String,String,String,Any}[]
    alt = cfg.status_policy == :pairwise_exclude ? :include_failed : :pairwise_exclude
    alt_comparisons = Comparison[]
    for cell in cells
        baseline = if cfg.best_arrival_scope == :global
            best.best
        else
            haskey(best.per_cell, cell) || throw(ArgumentError("per-cell best-arrival: cell $cell has no tuning data for all arrival arms"))
            best.per_cell[cell]
        end
        comps = [compare_paired(idx, cell, t, baseline; policy=cfg.status_policy, resamples=cfg.resamples, rng_seed=cfg.rng_seed)
                 for t in cfg.treatments]
        ni = compare_ni(idx, cell, cfg.primary, baseline; policy=cfg.status_policy, resamples=cfg.resamples,
                        rng_seed=cfg.rng_seed, margin=cfg.ni_margin, alpha=cfg.alpha, min_pairs=cfg.ni_min_pairs)
        labels = vcat(["$(c.treatment) superiority" for c in comps], ["$(cfg.primary) non-inferiority"])
        ps = vcat([c.p for c in comps], [ni.p])
        adj = holm_adjust(ps)
        k = findfirst(c -> c.treatment == cfg.primary, comps)
        k === nothing && throw(ArgumentError("primary arm $(cfg.primary) not among treatments"))
        sup, verdict, why = _cell_verdict(cfg, comps[k], adj[k], ni, adj[end])
        push!(results, CellResult(cell, baseline, comps, ni, labels, ps, adj, sup, verdict, why))

        byarm = idx[cell]
        for t in cfg.treatments
            tr = get(byarm, t, Dict{Int,RunRow}()); br = get(byarm, baseline, Dict{Int,RunRow}())
            both = intersect(keys(tr), keys(br))
            b_ = count(s -> !is_completed(tr[s]) && is_completed(br[s]), both)
            c_ = count(s -> is_completed(tr[s]) && !is_completed(br[s]), both)
            bf = count(s -> !is_completed(tr[s]) && !is_completed(br[s]), both)
            push!(missingness, MissingnessRow(cell, t, baseline, length(both), b_, c_, bf, mcnemar_exact(b_, c_)))

            use(r) = cfg.status_policy == :include_failed ? !isnan(r.rate) : is_completed(r)
            tv = [r.rate for r in values(tr) if use(r)]
            bv = [r.rate for r in values(br) if use(r)]
            push!(unpaired, (cell, t, baseline, unpaired_comparison(tv, bv; resamples=cfg.resamples,
                                                                    rng=stream_rng(cfg.rng_seed, cell, t, baseline, "unpaired"))))
            push!(alt_comparisons, compare_paired(idx, cell, t, baseline; policy=alt, resamples=cfg.resamples,
                                                  rng_seed=cfg.rng_seed, purpose="alt-policy"))
        end
    end

    pooled = Dict{String,Tuple{Int,Int,Float64}}()
    for t in cfg.treatments
        b_ = sum((m.t_failed_b_ok for m in missingness if m.treatment == t); init=0)
        c_ = sum((m.t_ok_b_failed for m in missingness if m.treatment == t); init=0)
        pooled[t] = (b_, c_, mcnemar_exact(b_, c_))
    end
    flag = any(m.p_mcnemar < 0.05 for m in missingness) || any(v[3] < 0.05 for v in values(pooled))

    # Exploratory: Holm across every (cell, hypothesis) in the report.
    labels = Tuple{String,String}[]; ps = Float64[]
    for c in results, (l, p) in zip(c.family, c.family_p)
        push!(labels, (c.cell, l)); push!(ps, p)
    end
    adj_all = isempty(ps) ? Float64[] : holm_adjust(ps)
    cross = [(labels[i][1], labels[i][2], ps[i], adj_all[i]) for i in eachindex(ps)]

    agg = Dict{String,Int}()
    for c in results
        agg[c.verdict] = get(agg, c.verdict, 0) + 1
    end
    agg["superiority met"] = count(c -> c.superiority_met, results)
    agg["NI estimable"] = count(c -> c.ni.estimable, results)

    K = length(results)
    n_elig = get(agg, VERDICT_ELIGIBLE, 0)
    n_ind = get(agg, VERDICT_INDETERMINATE, 0)
    overall = if all(c -> !c.ni.estimable, results) && agg["superiority met"] > 0
        "INDETERMINATE: $(cfg.primary) non-inferiority on p95 crash-detection delay is NOT ESTIMABLE in every cell; C4 cannot be granted"
    elseif n_elig > 0
        "C4 criteria met in $n_elig/$K cells (how cell verdicts aggregate into one C4 verdict is not preregistered; see per-cell table)"
    elseif n_ind > 0
        "INDETERMINATE in $n_ind/$K cells, no cell ELIGIBLE: C4 not granted"
    else
        "C4 criteria not met in any of $K cells: H-primary fails in every cell (C7 path, prereg §2)"
    end
    eligible || (overall = "[NOT CONFIRMATORY] " * overall)

    return AnalysisResult(cfg, tuning.source, report.source, ts, rs, eligible, notes, false, violations, safety_checked,
                          best, results, status_counts, reasons, missingness, pooled, flag, cross, unpaired, alt,
                          alt_comparisons, agg, overall)
end

# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------

_f(x; d=4) = isnan(x) ? "n/a" : isinf(x) ? (x > 0 ? "+Inf" : "-Inf") : string(round(x; digits=d))
_ci(t; d=4) = "[" * _f(t[1]; d=d) * ", " * _f(t[2]; d=d) * "]"
_p(p) = isnan(p) ? "n/a" : p < 1e-4 ? @sprintf("%.1e", p) : @sprintf("%.4f", p)

"""
    render_report(res::AnalysisResult) -> String (Markdown)
"""
function render_report(res::AnalysisResult)
    cfg = res.config
    io = IOBuffer()
    pr(args...) = println(io, args...)
    pr("# E3 analysis report")
    pr()
    if res.halted
        pr("> **HALTED — NO VERDICTS.** $(length(res.violations)) run(s) report `safety_ok = false`. ",
           "Prereg §11: any safety-flag failure on any arm halts E3 entirely pending root cause.")
        pr()
        pr("| cell | arm | seed | status | failure_reason |")
        pr("|---|---|---|---|---|")
        for r in res.violations
            pr("| `$(r.cell)` | $(r.arm) | $(r.seed) | $(r.status) | $(r.failure_reason) |")
        end
        return String(take!(io))
    end
    if res.confirmatory_eligible
        pr("> **CONFIRMATORY-ELIGIBLE INPUT.** Sections marked CONFIRMATORY implement prereg §2/§8 decision rules.")
    else
        pr("> **NOT CONFIRMATORY — EXERCISE / DIAGNOSTIC OUTPUT ONLY.** Reasons:")
        for n in res.eligibility_notes
            pr(">  - ", n)
        end
    end
    pr()
    pr("- Tuning input: `$(res.tuning_source)` (seeds $(res.tuning_seeds[1])–$(res.tuning_seeds[2]))")
    pr("- Report input: `$(res.report_source)` (seeds $(res.report_seeds[1])–$(res.report_seeds[2]))")
    pr("- Run-status policy: `$(cfg.status_policy)`; best-arrival scope: `$(cfg.best_arrival_scope)`")
    pr("- Bootstrap/permutation resamples: $(cfg.resamples); base RNG seed: 0x", string(cfg.rng_seed; base=16))
    pr("- Safety halt check (§11): ", res.safety_checked ? "passed (no `safety_ok = false` rows)" :
       "**unchecked** (no `safety_ok` column)")
    pr()

    pr("## 1. Best-arrival selection (tuning data only)")
    pr()
    pr("Mean over $(res.best.n_cells) common tuning cells of the per-cell mean false-suspicion rate (completed runs only).")
    pr()
    pr("| arm | score |")
    pr("|---|---|")
    for a in cfg.arrival_arms
        pr("| $a$(a == res.best.best ? " **(selected)**" : "") | $(_f(res.best.scores[a]; d=6)) |")
    end
    pr()

    pr("## 2. Run status and missingness (report data)")
    pr()
    arms = sort(unique(k[2] for k in keys(res.status_counts)))
    pr("| arm | runs | non-completed | rate | Wilson 95% CI |")
    pr("|---|---|---|---|---|")
    for a in arms
        tot = sum(v[1] for (k, v) in res.status_counts if k[2] == a)
        bad = sum(v[2] for (k, v) in res.status_counts if k[2] == a)
        lo, hi = wilson_ci(bad, tot)
        pr("| $a | $tot | $bad | $(_f(bad / tot)) | [$(_f(lo)), $(_f(hi))] |")
    end
    pr()
    if !isempty(res.failure_reasons)
        pr("Non-completed runs by status/reason: ",
           join(["$k × $v" for (k, v) in sort(collect(res.failure_reasons); by=first)], "; "))
        pr()
    end
    pr("Differential missingness vs the baseline (exact McNemar on replicas where exactly one arm did not complete; pooled over cells is descriptive):")
    pr()
    pr("| treatment | T failed & B ok | T ok & B failed | pooled exact McNemar p | cells with p < 0.05 |")
    pr("|---|---|---|---|---|")
    for t in cfg.treatments
        b_, c_, p = res.missingness_pooled[t]
        k = count(m -> m.treatment == t && m.p_mcnemar < 0.05, res.missingness)
        pr("| $t | $b_ | $c_ | $(_p(p)) | $k |")
    end
    pr()
    pr(res.differential_missingness_flag ?
       "**WARNING: differential missingness detected** (some McNemar p < 0.05). The pairwise-exclusion estimand may be biased; see the alternate-policy sensitivity in §6." :
       "No differential missingness detected at the 0.05 screening level.")
    pr()
    per_cell_fail = [(c, a, v) for ((c, a), v) in res.status_counts if v[2] > 0]
    if !isempty(per_cell_fail)
        pr("<details><summary>Per cell × arm non-completed counts ($(length(per_cell_fail)) nonzero)</summary>")
        pr()
        pr("| cell | arm | non-completed / runs |")
        pr("|---|---|---|")
        for (c, a, v) in sort(per_cell_fail)
            pr("| `$c` | $a | $(v[2]) / $(v[1]) |")
        end
        pr()
        pr("</details>")
        pr()
    end

    pr("## 3. CONFIRMATORY — primary family per cell (prereg §8)")
    pr()
    pr("Family per cell: {P1, P2, P3} superiority vs best-arrival (two-sided paired sign-flip p) + $(cfg.primary) non-inferiority (one-sided). ",
       "Holm step-down within cell, α = $(cfg.alpha). Relative reduction = 1 − mean_T/mean_B over paired replicas; ",
       "absolute reduction = mean_B − mean_T; 95% paired cluster-bootstrap percentile CIs.")
    pr()
    pr("| cell | B* | T | n | excl. | mean_B | mean_T | rel. reduction [95% CI] | abs. reduction [95% CI] | p | p_Holm |")
    pr("|---|---|---|---|---|---|---|---|---|---|---|")
    for c in res.cells, (i, cp) in enumerate(c.comparisons)
        relstr = rel_defined(cp) ? "$(_f(cp.rel; d=3)) $(_ci(cp.rel_ci; d=3))" : "undefined (mean_B = 0)"
        pr("| `$(c.cell)` | $(c.baseline) | $(cp.treatment) | $(cp.n_pairs) | $(cp.excluded_status + cp.absent) | ",
           "$(_f(cp.mean_b; d=5)) | $(_f(cp.mean_t; d=5)) | $relstr | $(_f(cp.diff; d=5)) $(_ci(cp.diff_ci; d=5)) | ",
           "$(_p(cp.p)) | $(_p(c.family_p_holm[i])) |")
    end
    pr()
    pr("### $(cfg.primary) non-inferiority on p95 crash-detection delay (margin +$(round(Int, 100cfg.ni_margin))% relative, one-sided 95%)")
    pr()
    pr("| cell | pairs | detections T / B | rel. change | one-sided upper | p | p_Holm | status |")
    pr("|---|---|---|---|---|---|---|---|")
    for c in res.cells
        ni = c.ni
        status = ni.estimable ? (c.family_p_holm[end] <= cfg.alpha ? "non-inferior" : "not shown") : "NOT ESTIMABLE"
        pr("| `$(c.cell)` | $(ni.n_pairs) | $(ni.detections_t) / $(ni.detections_b) | $(_f(ni.rel_change; d=3)) | ",
           "$(_f(ni.upper; d=3)) | $(_p(ni.p)) | $(_p(c.family_p_holm[end])) | $status |")
    end
    pr()
    if all(c -> !c.ni.estimable, res.cells)
        pr("**Non-inferiority is NOT ESTIMABLE in every cell** (no or too few replica pairs with crash detections). ",
           "It enters Holm with p = 1 and no cell can be ELIGIBLE.")
        pr()
    end
    pr("### Per-cell C4 verdicts")
    pr()
    pr("Rule: ELIGIBLE iff $(cfg.primary) superiority Holm p ≤ α **and** point relative reduction ≥ $(cfg.delta) **and** ",
       "95% CI lower bound > 0 **and** non-inferiority Holm p ≤ α. Mean_B = 0 → UNDEFINED. Superiority met but NI not estimable → INDETERMINATE.")
    pr()
    pr("| cell | verdict | reason |")
    pr("|---|---|---|")
    for c in res.cells
        pr("| `$(c.cell)` | $(c.verdict) | $(c.verdict_reason) |")
    end
    pr()

    pr("## 4. DESCRIPTIVE aggregate (not a p-value; no pooling across cells)")
    pr()
    K = length(res.cells)
    for (k, v) in sort(collect(res.aggregate); by=first)
        pr("- $k: $v / $K cells")
    end
    pr()
    pr("**Overall C4 status:** ", res.overall_verdict)
    pr()

    pr("## 5. EXPLORATORY — cross-cell Holm (all cells × 4 hypotheses in one family)")
    pr()
    pr("Stricter than the preregistered per-cell family; reported as a sensitivity only.")
    pr()
    rej = [x for x in res.cross_cell_holm if x[4] <= cfg.alpha]
    pr("Hypotheses rejected at α = $(cfg.alpha): $(length(rej)) of $(length(res.cross_cell_holm)).")
    for x in rej
        pr("- `$(x[1])` $(x[2]): p = $(_p(x[3])), adj = $(_p(x[4]))")
    end
    pr()

    pr("## 6. EXPLORATORY — sensitivity analyses")
    pr()
    pr("### 6a. Unpaired (arms resampled independently; label-permutation p) — mandatory per prereg §5")
    pr()
    pr("| cell | T vs B* | n_T / n_B | rel. reduction [95% CI] | abs. reduction [95% CI] | p (unpaired) |")
    pr("|---|---|---|---|---|---|")
    for (cell, t, b, u) in res.unpaired
        relstr = isnan(u.rel) ? "undefined" : "$(_f(u.rel; d=3)) $(_ci(u.rel_ci; d=3))"
        pr("| `$cell` | $t vs $b | $(u.n_t) / $(u.n_b) | $relstr | $(_f(u.diff; d=5)) $(_ci(u.diff_ci; d=5)) | $(_p(u.p)) |")
    end
    pr()
    pr("### 6b. Alternate run-status policy `$(res.alt_policy)` (paired, unadjusted)")
    pr()
    pr("| cell | T vs B* | n | rel. reduction [95% CI] | p |")
    pr("|---|---|---|---|---|")
    for cp in res.alt_policy_comparisons
        relstr = rel_defined(cp) ? "$(_f(cp.rel; d=3)) $(_ci(cp.rel_ci; d=3))" : "undefined"
        pr("| `$(cp.cell)` | $(cp.treatment) vs $(cp.baseline) | $(cp.n_pairs) | $relstr | $(_p(cp.p)) |")
    end
    pr()
    return String(take!(io))
end

# ---------------------------------------------------------------------------
# Power analysis (PROPOSED revision of prereg §9)
# ---------------------------------------------------------------------------

"""
    power_analysis(rows; ...) -> NamedTuple

Per cell and treatment: paired differences d_i = r_B − r_T over replica pairs
(both completed), σ_d = SD(d), Δ = δ·mean_B, required
N = (z_{1−α/2} + z_{power})²·σ_d²/Δ² and achieved power at `n_target`,
power(N) = Φ(Δ√N/σ_d − z_{1−α/2}) + Φ(−Δ√N/σ_d − z_{1−α/2}); also the same at
α/m (the first Holm step with m = 4). The ratio estimand's per-replica SD is
estimated as SD_boot(1 − mean_T*/mean_B*)·√n from a paired bootstrap. Cells
with mean_B = 0 are flagged "no events: effect undefined". No smoothing
constants and no floors.
"""
function power_analysis(rows::AbstractVector{RunRow}; treatments=TREATMENT_ARMS, arrival_arms=ARRIVAL_ARMS,
                        alpha=0.05, power=0.80, delta=0.15, n_target=120, holm_m=4,
                        resamples=10_000, rng_seed::Integer=0xe3)
    best = select_best_arrival(rows; arms=arrival_arms)
    B = best.best
    idx = index_rows(rows)
    za = norminv(1 - alpha / 2); zb = norminv(power); za_m = norminv(1 - alpha / (2holm_m))
    pw(lam, z) = normcdf(lam - z) + normcdf(-lam - z)
    out = []
    for cell in sort(collect(keys(idx))), t in treatments
        pv = paired_values(idx, cell, t, B; policy=:pairwise_exclude, metric=:rate)
        n = length(pv.t)
        mb = n > 0 ? mean(pv.b) : NaN
        mt = n > 0 ? mean(pv.t) : NaN
        d = pv.b .- pv.t
        sd_d = n >= 2 ? std(d) : NaN
        nolog = count(i -> pv.t[i] == 0 || pv.b[i] == 0, 1:n)
        status = ""; Δ = NaN; nreq = NaN; p120 = NaN; p120m = NaN; sd_rel = NaN; nreq_rel = NaN; p120_rel = NaN
        if n < 2
            status = "insufficient pairs"
        elseif !(mb > 0)
            status = "no events: effect undefined"
        else
            Δ = delta * mb
            if sd_d == 0
                status = "degenerate: zero variance of paired differences"
                nreq = 0.0; p120 = 1.0; p120m = 1.0
            else
                nreq = (za + zb)^2 * sd_d^2 / Δ^2
                lam = Δ * sqrt(n_target) / sd_d
                p120 = pw(lam, za); p120m = pw(lam, za_m)
            end
            boot = paired_bootstrap(pv.t, pv.b; resamples=resamples, rng=stream_rng(rng_seed, cell, t, B, "power"))
            finite = filter(isfinite, boot.rel)
            b_event_replicas = count(>(0), pv.b)
            # The ratio SD is only meaningful when every resample defines the
            # ratio (no mean_B* = 0) and baseline events come from ≥ 2 replicas;
            # otherwise the bootstrap SD is degenerate (e.g. exactly 0).
            if b_event_replicas >= 2 && boot.rel_undefined == 0 && length(finite) == length(boot.rel)
                sd_rel = std(finite) * sqrt(n)
                if sd_rel > 1e-12
                    nreq_rel = (za + zb)^2 * sd_rel^2 / delta^2
                    p120_rel = pw(delta * sqrt(n_target) / sd_rel, za)
                else
                    sd_rel = NaN
                end
            end
            isnan(sd_rel) && (status = (isempty(status) ? "" : status * "; ") * "ratio SD not estimable (baseline events in < 2 replicas or mean_B* = 0 in some resamples)")
        end
        push!(out, (cell=cell, treatment=t, baseline=B, n=n, excluded=pv.excluded_status + pv.absent,
                    mean_b=mb, mean_t=mt, sd_d=sd_d, Δ=Δ, n_required=nreq, power_target=p120, power_target_holm=p120m,
                    sd_rel=sd_rel, n_required_rel=nreq_rel, power_target_rel=p120_rel, undefined_logratio=nolog,
                    status=status))
    end
    return (best=best, rows=out, z_alpha=za, z_power=zb, z_alpha_holm=za_m, alpha=alpha, power=power,
            delta=delta, n_target=n_target, holm_m=holm_m)
end

function _nstr(x)
    isnan(x) && return "n/a"
    isinf(x) && return "Inf"
    return string(ceil(Int, x))
end

"""
    render_power(pa; source, seeds) -> String (Markdown)
"""
function render_power(pa; source::AbstractString="", seeds::AbstractString="")
    io = IOBuffer()
    pr(args...) = println(io, args...)
    pr("# E3 pilot power analysis — PROPOSED revision")
    pr()
    pr("> **PROPOSED, NOT ADOPTED.** The preregistered §9 formula (N = ⌈2(z_{0.975}+z_{0.80})²σ²/(ln 0.85)²⌉ on per-replica ",
       "log-ratios) is superseded **only if** a new preregistration addendum adopts this procedure. Nothing here changes the frozen N.")
    pr()
    pr("- Pilot input: `$source`", isempty(seeds) ? "" : " (seeds $seeds)")
    pr("- Best-arrival (among $(join(ARRIVAL_ARMS, "/")), mean over common cells of per-cell mean rate): **$(pa.best.best)** — scores: ",
       join(["$a = $(_f(pa.best.scores[a]; d=6))" for a in sort(collect(keys(pa.best.scores)))], ", "))
    pr("- Why not the §9 formula: a per-replica log-ratio ln(r_T/r_B) is undefined whenever either rate is 0; ",
       "the previous script replaced it with ln((r_T+1e-4)/(r_B+1e-4)), whose SD is an artifact of the constant. ",
       "Share of paired replicas with an undefined log-ratio (all cells, all treatments): ",
       let tot = sum(r.n for r in pa.rows), u = sum(r.undefined_logratio for r in pa.rows)
           "$u / $tot ($(_f(100u / max(tot, 1); d=1))%)."
       end)
    pr()
    pr("**Formula (paired, normal approximation):** with d_i = r_B,i − r_T,i, σ_d = SD(d), Δ = $(pa.delta)·mean_B,")
    pr()
    pr("N = (z_{1−α/2} + z_{power})² · σ_d² / Δ²,  power(N) = Φ(Δ√N/σ_d − z_{1−α/2}) + Φ(−Δ√N/σ_d − z_{1−α/2})")
    pr()
    pr(@sprintf("with α = %.2f (z = %.4f), power = %.2f (z = %.4f). `power@%d (α/%d)` uses z = %.4f, the first Holm step of the %d-hypothesis family. ",
                pa.alpha, pa.z_alpha, pa.power, pa.z_power, pa.n_target, pa.holm_m, pa.z_alpha_holm, pa.holm_m))
    pr("Ratio-estimand columns use σ_rel = SD_boot(1 − mean_T*/mean_B*)·√n (paired bootstrap at pilot n) in the same formula with Δ = $(pa.delta). ",
       "No smoothing constants, no floors, no caps applied to N.")
    pr()
    for t in unique(r.treatment for r in pa.rows)
        rs = [r for r in pa.rows if r.treatment == t]
        pr("## $t vs $(pa.best.best)")
        pr()
        pr("| cell | n | mean_B | mean_T | σ_d | Δ | N req. | power@$(pa.n_target) | power@$(pa.n_target) (α/$(pa.holm_m)) | σ_rel | N req. (ratio) | power@$(pa.n_target) (ratio) | note |")
        pr("|---|---|---|---|---|---|---|---|---|---|---|---|---|")
        for r in rs
            pr("| `$(r.cell)` | $(r.n) | $(_f(r.mean_b; d=5)) | $(_f(r.mean_t; d=5)) | $(_f(r.sd_d; d=5)) | $(_f(r.Δ; d=5)) | ",
               "$(_nstr(r.n_required)) | $(_f(r.power_target; d=3)) | $(_f(r.power_target_holm; d=3)) | $(_f(r.sd_rel; d=3)) | ",
               "$(_nstr(r.n_required_rel)) | $(_f(r.power_target_rel; d=3)) | $(r.status) |")
        end
        pr()
        defined = [r for r in rs if !isnan(r.power_target)]
        noev = count(r -> r.status == "no events: effect undefined", rs)
        pr("**Summary ($t):** $(length(rs)) cells; $noev with no baseline events (effect undefined); ",
           "$(length(defined)) with defined power. ")
        if !isempty(defined)
            pws = sort([r.power_target for r in defined])
            nr = [r.n_required for r in defined]
            pr(@sprintf("Power@%d: min %.3f, median %.3f, max %.3f; %d/%d cells ≥ %.2f; %d/%d cells need N > %d (max N req. %s).",
                        pa.n_target, pws[1], median(pws), pws[end], count(>=(pa.power), pws), length(pws), pa.power,
                        count(>(pa.n_target), nr), length(nr), pa.n_target, _nstr(maximum(nr))))
        end
        pr()
    end
    pr("Caveats: the normal approximation is rough for zero-inflated rates at small N; pilot σ_d is estimated from ",
       "≤ 24 replicas per cell; power is for the paired mean-difference test, which has the same null as the relative-reduction test ",
       "but does not account for the additional δ ≥ 15% point-estimate requirement of the C4 rule.")
    return String(take!(io))
end

end # module
