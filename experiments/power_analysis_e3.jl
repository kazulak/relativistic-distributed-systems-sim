#!/usr/bin/env julia

# E3 Power Analysis & Sample Size Determination
#
# Implements the pre-registered sample size procedure from docs/PRE_REGISTRATION_E3.md §9:
# N = ceil(2 * (z_0.975 + z_0.80)^2 * sigma^2 / (ln 0.85)^2),
# rounded up to a multiple of 10, capped at 120.
#
# Usage: julia --project=. experiments/power_analysis_e3.jl results/e3/<pilot-dir>/runs.tsv

using Printf
using Statistics

struct PilotRow
    cell::String
    arm::String
    seed::Int
    rate::Float64
    p95::Float64
    committed::Int
end

function parse_pilot_tsv(path::AbstractString)
    isfile(path) || throw(ArgumentError("file not found: $path"))
    rows = PilotRow[]
    for (index, line) in enumerate(eachline(path))
        index == 1 && continue
        fields = split(line, '\t')
        length(fields) >= 22 || continue
        seed = tryparse(Int, fields[11])
        isnothing(seed) && continue
        rate = tryparse(Float64, fields[16])
        p95 = tryparse(Float64, fields[22])
        committed = tryparse(Int, fields[18])
        push!(rows, PilotRow(
            fields[1],
            fields[8],
            seed,
            isnothing(rate) ? NaN : rate,
            isnothing(p95) ? NaN : p95,
            isnothing(committed) ? 0 : committed,
        ))
    end
    return rows
end

function compute_sample_size(sigma::Float64; delta::Float64=0.15, alpha::Float64=0.05, power::Float64=0.80)
    z_alpha = 1.959963984540054  # z_0.975
    z_beta = 0.8416212335729143   # z_0.80
    effect = abs(log(1.0 - delta)) # ln(0.85)
    raw_n = 2.0 * (z_alpha + z_beta)^2 * (sigma^2) / (effect^2)
    # Round up to multiple of 10, capped at 120 (per preregistration §9)
    rounded = ceil(Int, raw_n / 10.0) * 10
    clamped = clamp(max(rounded, 10), 10, 120)
    return (raw_n, clamped)
end

function main(arguments)
    isempty(arguments) && (println(stderr, "usage: julia --project=. experiments/power_analysis_e3.jl runs.tsv"); return 2)
    path = arguments[1]
    rows = parse_pilot_tsv(path)
    println("Loaded ", length(rows), " pilot runs from: ", path)

    # Group by cell and seed
    by_cell_seed = Dict{String,Dict{Int,Dict{String,PilotRow}}}()
    for row in rows
        cells = get!(by_cell_seed, row.cell, Dict{Int,Dict{String,PilotRow}}())
        arms = get!(cells, row.seed, Dict{String,PilotRow}())
        arms[row.arm] = row
    end

    println()
    println("# Pre-Registration Addendum r3: Pilot Power Analysis & Sample Size Freeze")
    println()
    println("Pre-registered specification: 80% power at \$\\delta = 15\\%\$ (\$\\alpha = 0.05\$, two-sided):")
    println("\$\$N = \\left\\lceil \\frac{2 (z_{0.975} + z_{0.80})^2 \\sigma^2}{(\\ln 0.85)^2} \\right\\rceil\$\$")
    println()
    println("| Cell ID | Replicas | Treatment Arm | Baseline Arm | \$\\sigma_{\\ln \\text{ratio}}\$ | Raw \$N\$ | Frozen \$N\$ |")
    println("|---|---|---|---|---|---|---|")

    max_n = 0
    smoothing = 1e-4

    for (cell, seeds_map) in sort(collect(by_cell_seed); by=first)
        treatment = "P2"
        # Find best arrival baseline (lowest mean rate across these seeds)
        arrival_arms = ["B4", "B5"]
        best_arrival = "B4"
        best_mean = Inf
        for a in arrival_arms
            rates = [s[a].rate for s in values(seeds_map) if haskey(s, a) && !isnan(s[a].rate)]
            if !isempty(rates)
                m = mean(rates)
                if m < best_mean
                    best_mean = m
                    best_arrival = a
                end
            end
        end

        log_ratios = Float64[]
        for (seed, arms) in seeds_map
            (haskey(arms, treatment) && haskey(arms, best_arrival)) || continue
            r_treat = arms[treatment].rate
            r_base = arms[best_arrival].rate
            (isnan(r_treat) || isnan(r_base)) && continue
            push!(log_ratios, log((r_treat + smoothing) / (r_base + smoothing)))
        end

        if length(log_ratios) >= 3
            cell_sigma = std(log_ratios)
            raw_n, frozen_n = compute_sample_size(cell_sigma)
            max_n = max(max_n, frozen_n)
            @printf("| `%s` | %d | %s | %s | %.4f | %.1f | **%d** |\n",
                cell, length(log_ratios), treatment, best_arrival, cell_sigma, raw_n, frozen_n)
        else
            @printf("| `%s` | %d | %s | %s | N/A | N/A | (insufficient data) |\n",
                cell, length(log_ratios), treatment, best_arrival)
        end
    end

    overall_n = max(max_n, 40)
    println()
    println("### Authoritative Sample Size Determination")
    println("- Maximum calculated \$N\$ across representative cells: **$(overall_n)**")
    println("- **Frozen Report Replications per Cell**: `N = $(overall_n)`")
    println()
    return 0
end

exit(main(ARGS))
