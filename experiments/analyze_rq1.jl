#!/usr/bin/env julia

# RQ1 analysis CLI: audits run completion and safety flags (H1a), the causal
# quorum bound audit (C3), and summarizes timed progress per cell across
# seeds (H1b, descriptive).
#
# This script reports evidence; it does not declare hypotheses validated.
# Confirmatory H1b/H1c tests are defined only by an RQ1 preregistration.
# The run (seed) is the experimental unit: per-cell intervals are bootstrap
# intervals over runs, never over operations within a run.
#
# Usage: julia --project=. experiments/analyze_rq1.jl results/rq1/<run-dir>/runs.tsv

using Printf
using Random
using Statistics

const REQUIRED_COLUMNS = [
    "cell", "family", "cluster_size", "beta_scale", "chi_initial", "rate_ratio",
    "disruption", "seed", "status", "safety_ok", "committed", "censored",
    "deadline_availability", "leader_availability",
]

"""Read a TSV into a vector of Dict rows keyed by header name."""
function read_tsv(path::AbstractString)
    isfile(path) || throw(ArgumentError("file not found: $path"))
    lines = collect(eachline(path))
    isempty(lines) && throw(ArgumentError("empty file: $path"))
    header = split(lines[1], '\t')
    missing_columns = setdiff(REQUIRED_COLUMNS, header)
    isempty(missing_columns) ||
        throw(ArgumentError("missing required columns: $(join(missing_columns, ", "))"))
    rows = Dict{String,String}[]
    for (number, line) in enumerate(lines[2:end])
        isempty(strip(line)) && continue
        fields = split(line, '\t')
        length(fields) == length(header) ||
            throw(ArgumentError("row $(number + 1) has $(length(fields)) fields, header has $(length(header))"))
        push!(rows, Dict(String(k) => String(v) for (k, v) in zip(header, fields)))
    end
    return rows, header
end

parse_float(value::AbstractString) = something(tryparse(Float64, value), NaN)
parse_bool(value::AbstractString) = lowercase(value) == "true"

"""Percentile bootstrap CI of the mean over runs (fixed seed)."""
function bootstrap_mean_ci(values::Vector{Float64}; draws::Int=4000, level::Float64=0.95)
    values = filter(!isnan, values)
    n = length(values)
    n == 0 && return (NaN, NaN, NaN)
    n == 1 && return (values[1], NaN, NaN)
    rng = Xoshiro(0x51)
    means = Vector{Float64}(undef, draws)
    for draw in 1:draws
        total = 0.0
        for _ in 1:n
            total += values[rand(rng, 1:n)]
        end
        means[draw] = total / n
    end
    sort!(means)
    alpha = (1 - level) / 2
    return (mean(values), quantile(means, alpha), quantile(means, 1 - alpha))
end

"""Spearman rank correlation (average ranks for ties)."""
function spearman(x::Vector{Float64}, y::Vector{Float64})
    keep = .!(isnan.(x) .| isnan.(y) .| isinf.(x) .| isinf.(y))
    x, y = x[keep], y[keep]
    length(x) < 3 && return NaN
    rank(v) = begin
        order = sortperm(v)
        ranks = similar(v)
        i = 1
        while i <= length(v)
            j = i
            while j < length(v) && v[order[j + 1]] == v[order[i]]
                j += 1
            end
            ranks[order[i:j]] .= (i + j) / 2
            i = j + 1
        end
        ranks
    end
    rx, ry = rank(x), rank(y)
    (std(rx) == 0 || std(ry) == 0) && return NaN
    return cor(rx, ry)
end

format_ci(point, lo, hi) = isnan(lo) ? @sprintf("%.3f (n=1, no CI)", point) :
                           @sprintf("%.3f [%.3f, %.3f]", point, lo, hi)

function generate_summary(rows::Vector{Dict{String,String}}, header, tsv_path::String)
    total = length(rows)
    total == 0 && return "Empty dataset"
    has_bound_audit = "audited_writes" in header
    has_failure_reason = "failure_reason" in header

    completed = count(r -> r["status"] == "completed", rows)
    clean = count(r -> r["status"] == "completed" && parse_bool(r["safety_ok"]), rows)
    failed = filter(r -> r["status"] != "completed", rows)

    io = IOBuffer()
    println(io, "# RQ1 evaluation summary")
    println(io)
    println(io, "Dataset: `$(basename(dirname(tsv_path)))/$(basename(tsv_path))`  ")
    println(io, "Runs analyzed: **$(total)**; cells: $(length(unique(r["cell"] for r in rows))); ",
            "seeds per cell: $(join(sort(unique(length(filter(r -> r["cell"] == c, rows)) for c in unique(r["cell"] for r in rows))), "/"))")
    println(io)
    println(io, "This summary is descriptive. It reports evidence but declares no hypothesis ",
            "validated; confirmatory RQ1 tests are defined by a preregistration.")
    println(io)

    println(io, "## 1. Run completion and safety flags (H1a)")
    println(io)
    println(io, "| Check | Observed |")
    println(io, "|---|---|")
    println(io, "| Runs completed | $(completed)/$(total) |")
    println(io, "| Completed with all safety oracles clean | $(clean)/$(total) |")
    println(io, "| Runs not completed (failed/invalid) | $(length(failed)) |")
    println(io)
    if !isempty(failed)
        println(io, "Non-completed runs are reported, not dropped. A run that failed before the ",
                "censor horizon was not fully audited by the safety oracles.")
        println(io)
        reasons = Dict{String,Int}()
        for r in failed
            key = r["status"] * ": " * (has_failure_reason ? first(r["failure_reason"], 120) : "(reason not recorded)")
            reasons[key] = get(reasons, key, 0) + 1
        end
        for (reason, n) in sort(collect(reasons); by=last, rev=true)
            println(io, "- $(n) × $(reason)")
        end
        println(io)
    end

    println(io, "## 2. Causal quorum bound audit (C3)")
    println(io)
    if has_bound_audit
        audited = sum(parse(Int, r["audited_writes"]) for r in rows)
        runs_with_writes = count(r -> parse(Int, r["audited_writes"]) > 0, rows)
        bound_ok = count(r -> parse_bool(r["causal_bound_ok"]), rows)
        margins = filter(!isnan, [parse_float(r["min_causal_margin"]) for r in rows if parse(Int, r["audited_writes"]) > 0])
        println(io, "| Check | Observed |")
        println(io, "|---|---|")
        println(io, "| Runs with clean bound audit | $(bound_ok)/$(total) |")
        println(io, "| Committed writes audited | $(audited) (in $(runs_with_writes) runs) |")
        println(io, "| Runs with no committed write (audit vacuous) | $(total - runs_with_writes) |")
        if isempty(margins)
            println(io, "| Minimum margin over audited writes | not defined (no audited writes) |")
        else
            @printf(io, "| Minimum margin over audited writes | %.6g client proper time |\n", minimum(margins))
        end
    else
        println(io, "Not available: this TSV predates the `audited_writes` column (schema v1). ",
                "Its margin column reported 0.0 for runs without committed writes, so it cannot ",
                "support a bound audit (docs/DEVIATIONS.md D-08).")
    end
    println(io)

    println(io, "## 3. Timed progress per cell (descriptive)")
    println(io)
    println(io, "Deadline availability = committed / (committed + censored) per run; the table ",
            "shows the mean over runs with a 95 % percentile bootstrap interval over runs.")
    println(io)
    println(io, "| Cell | n | β | χ | D_sr | Disruption | Runs | Deadline availability | Leader availability | Not completed |")
    println(io, "|---|---|---|---|---|---|---|---|---|---|")
    cell_ids = unique(r["cell"] for r in rows)
    cell_means = Dict{String,Float64}()
    for cell in cell_ids
        cell_rows = filter(r -> r["cell"] == cell, rows)
        first_row = cell_rows[1]
        availability = [parse_float(r["deadline_availability"]) for r in cell_rows if r["status"] == "completed"]
        leader = [parse_float(r["leader_availability"]) for r in cell_rows if r["status"] == "completed"]
        point, lo, hi = bootstrap_mean_ci(availability)
        lpoint, llo, lhi = bootstrap_mean_ci(leader)
        cell_means[cell] = point
        @printf(io, "| `%s` | %s | %+.2f | %.3f | %.3f | %s | %d | %s | %s | %d |\n",
            cell, first_row["cluster_size"], parse_float(first_row["beta_scale"]),
            parse_float(first_row["chi_initial"]), parse_float(first_row["rate_ratio"]),
            first_row["disruption"], length(cell_rows),
            format_ci(point, lo, hi), format_ci(lpoint, llo, lhi),
            count(r -> r["status"] != "completed", cell_rows))
    end
    println(io)

    println(io, "## 4. Exploratory association with candidate explanatory variables")
    println(io)
    println(io, "Spearman rank correlation between per-cell mean deadline availability and each ",
            "start-of-measurement descriptor. Exploratory only: no multiplicity control, ",
            "descriptors are correlated by construction, and this is not the H1b test.")
    println(io)
    firsts = Dict(c => rows[findfirst(r -> r["cell"] == c, rows)] for c in cell_ids)
    y = [cell_means[c] for c in cell_ids]
    println(io, "| Descriptor | Spearman ρ with mean availability |")
    println(io, "|---|---|")
    for (label, column, transform) in (
        ("χ (quorum RTT / θ_min)", "chi_initial", identity),
        ("D_sr (rate ratio)", "rate_ratio", identity),
        ("abs(β)", "beta_scale", abs),
    )
        x = [transform(parse_float(firsts[c][column])) for c in cell_ids]
        @printf(io, "| %s | %.3f |\n", label, spearman(x, y))
    end
    println(io)
    return String(take!(io))
end

function main(arguments)
    isempty(arguments) && (println(stderr, "usage: julia --project=. experiments/analyze_rq1.jl runs.tsv"); return 2)
    path = arguments[1]
    rows, header = read_tsv(path)
    println("Loaded ", length(rows), " run records from ", path)

    summary_text = generate_summary(rows, header, path)
    println()
    println(summary_text)

    summary_file = joinpath(dirname(path), "SUMMARY.md")
    open(summary_file, "w") do io
        write(io, summary_text)
    end
    println("Wrote summary to: ", summary_file)
    all_clean = all(r -> r["status"] == "completed" && parse_bool(r["safety_ok"]), rows) &&
                (!("causal_bound_ok" in header) || all(r -> parse_bool(r["causal_bound_ok"]), rows))
    return all_clean ? 0 : 1
end

if abspath(PROGRAM_FILE) == @__FILE__
    exit(main(ARGS))
end
