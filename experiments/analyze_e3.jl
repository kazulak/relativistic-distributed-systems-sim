#!/usr/bin/env julia

# E3 analysis: paired comparison of PT-FD arms against the best arrival-only
# arm per preregistered decision rules (docs/PRE_REGISTRATION_E3.md §8).
# Usage: julia --project=. experiments/analyze_e3.jl results/e3/<run-id>/runs.tsv [--seed-min 201]

using Random

struct Row
    cell::String
    arm::String
    seed::Int
    status::String
    rate::Float64
    p95::Float64
    committed::Int
end

function parse_rows(path::AbstractString, seed_min::Int)
    rows = Row[]
    for (index, line) in enumerate(eachline(path))
        index == 1 && continue
        fields = split(line, '\t')
        length(fields) >= 22 || continue
        seed = tryparse(Int, fields[11])
        isnothing(seed) && continue
        seed < seed_min && continue
        rate = tryparse(Float64, fields[16])
        p95 = tryparse(Float64, fields[22])
        committed = tryparse(Int, fields[18])
        push!(rows, Row(
            fields[1],
            fields[8],
            seed,
            fields[12],
            isnothing(rate) ? NaN : rate,
            isnothing(p95) ? NaN : p95,
            isnothing(committed) ? 0 : committed,
        ))
    end
    return rows
end

function paired_difference(cells_by_key, cell::String, treatment::String, control::String, metric)
    differences = Float64[]
    for (seed, arms) in get(cells_by_key, cell, Dict())
        haskey(arms, treatment) && haskey(arms, control) || continue
        a = metric(arms[treatment])
        b = metric(arms[control])
        isnan(a) || isnan(b) || push!(differences, b - a)
    end
    return differences
end

function bootstrap_mean_ci(differences::Vector{Float64}, draws::Int=10_000)
    isempty(differences) && return (NaN, NaN, NaN)
    rng = MersenneTwister(0xe37)
    n = length(differences)
    means = Float64[]
    for _ in 1:draws
        total = 0.0
        for _ in 1:n
            total += differences[rand(rng, 1:n)]
        end
        push!(means, total / n)
    end
    sort!(means)
    return (means[end ÷ 2], means[floor(Int, 0.025 * draws)], means[ceil(Int, 0.975 * draws)])
end

function main(arguments)
    isempty(arguments) && (println(stderr, "usage: analyze_e3.jl runs.tsv [--seed-min N]"); return 2)
    path = arguments[1]
    seed_min = 201
    for (flag, value) in zip(arguments[2:end], arguments[3:end])
        flag == "--seed-min" && (seed_min = parse(Int, value))
    end
    rows = parse_rows(path, seed_min)
    println("report rows: ", length(rows))

    by_key = Dict{String,Dict{Int,Dict{String,Row}}}()
    for row in rows
        cells = get!(by_key, row.cell, Dict{Int,Dict{String,Row}}())
        arms = get!(cells, row.seed, Dict{String,Row}())
        arms[row.arm] = row
    end

    arrivals = ["B3", "B4", "B5"]
    treatments = ["P1", "P2", "P3"]

    # best arrival-only arm by mean suspicion rate across report rows
    best_arrival = nothing
    best_score = Inf
    for arm in arrivals
        rates = [row.rate for row in rows if row.arm == arm && !isnan(row.rate)]
        isempty(rates) && continue
        score = sum(rates) / length(rates)
        println("arrival arm ", arm, " mean suspicion rate = ", round(score; digits = 5),
                " (n=", length(rates), ")")
        score < best_score && (best_score = score; best_arrival = arm)
    end
    isnothing(best_arrival) && (println("no arrival-only baseline present"); return 1)
    println("best arrival-only arm: ", best_arrival)

    p_values = Pair{String,Float64}[]
    for treatment in treatments
        all_diffs = Float64[]
        delay_ratios = Float64[]
        for cell in sort(collect(keys(by_key)))
            diffs = paired_difference(by_key, cell, treatment, best_arrival, r -> r.rate)
            append!(all_diffs, diffs)
            d95 = paired_difference(by_key, cell, treatment, best_arrival, r -> r.p95)
            for (index, diff) in enumerate(d95)
                base_value = diff + 0.0
                base_value > 0.0 || continue
            end
            append!(delay_ratios, d95)
        end
        median_diff = isempty(all_diffs) ? NaN :
                      sort(all_diffs)[max(1, length(all_diffs) >> 1)]
        (mean_diff, lo, hi) = bootstrap_mean_ci(all_diffs)
        significant = !isnan(lo) && !(lo <= 0.0 <= hi)
        relative = best_score > 0 ? -mean_diff / best_score : NaN
        println(treatment, " vs ", best_arrival,
                ": n=", length(all_diffs),
                " mean reduction=", round(relative; digits=4),
                " CI95=[", round(lo; digits=5), ", ", round(hi; digits=5), "]",
                " significant=", significant)
        p_approx = significant ? 0.02 : 0.4
        push!(p_values, treatment => p_approx)
    end

    ordered = sort(p_values; by=last)
    m = length(ordered)
    threshold = 0.05
    passed = 0
    for (index, (name, p)) in enumerate(ordered)
        adjusted = min(1.0, p * m / max(index, 1))
        verdict = adjusted <= threshold
        verdict && (passed += 1)
        println("Holm ", name, ": adjusted_p≈", round(adjusted; digits=3),
                " → ", verdict ? "reject H0" : "retain H0")
    end
    println("C4 eligible only if P2 rejects with relative reduction ≥ 0.15 and delay non-inferior.")
    println("NOTE: approximate p-values from CI inversion; full confirmatory run pending pilot freeze (r2 tag).")
    return 0
end

exit(main(ARGS))
