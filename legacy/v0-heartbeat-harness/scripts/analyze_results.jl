# LEGACY EXPLORATORY SCRIPT: not part of the publication analysis pipeline.
# It consumes historical phase outputs under `--project=analysis`; its plots
# and summaries are not paper evidence.

using CSV
using DataFrames
using Dates
ENV["GKSwstype"] = "100"
using Plots
using Printf
using Statistics

gr()
Plots.default(fontfamily="Helvetica", dpi=300)

const ROOT = normpath(joinpath(@__DIR__, ".."))
const RESULTS_DIR = joinpath(ROOT, "results")
const FIGURES_DIR = joinpath(ROOT, "figures")
const PAPER_DIR = joinpath(ROOT, "paper")
const TABLES_DIR = joinpath(PAPER_DIR, "tables")

const RAFT_HEADER = [
    :seed,
    :beta,
    :duration,
    :heartbeats_sent,
    :heartbeats_delivered,
    :false_elections,
    :safety_violations,
    :availability,
]

mkpath(RESULTS_DIR)
mkpath(FIGURES_DIR)
mkpath(TABLES_DIR)

function result_files(pattern::AbstractString)
    return sort(glob_to_files(RESULTS_DIR, pattern))
end

function glob_to_files(dir::AbstractString, pattern::AbstractString)
    re = Regex("^" * replace(replace(pattern, "." => "\\."), "*" => ".*") * "\$")
    return [joinpath(dir, name) for name in readdir(dir) if occursin(re, name)]
end

function read_raft_files(pattern::AbstractString)::DataFrame
    files = result_files(pattern)
    if isempty(files)
        return DataFrame()
    end

    frames = DataFrame[]
    for path in files
        df = CSV.read(path, DataFrame)
        missing_cols = setdiff(RAFT_HEADER, Symbol.(names(df)))
        if !isempty(missing_cols)
            error("$(path) is missing required columns: $(join(missing_cols, ", "))")
        end
        df.source_file .= basename(path)
        push!(frames, df)
    end
    return vcat(frames...; cols=:union)
end

@inline false_election_rate(false_elections, heartbeats_sent) = heartbeats_sent == 0 ? 0.0 : false_elections / heartbeats_sent
@inline timeout_scaling(beta) = sqrt((1.0 + beta) / (1.0 - beta))

function aggregate_phase(df::DataFrame; include_timeout::Bool=false)::DataFrame
    if isempty(df)
        return DataFrame()
    end

    work = copy(df)
    work.false_election_rate = false_election_rate.(work.false_elections, work.heartbeats_sent)
    if include_timeout && !(:timeout_scaling in Symbol.(names(work)))
        work.timeout_scaling = timeout_scaling.(work.beta)
    end

    grouped = groupby(work, :beta; sort=true)
    agg = combine(
        grouped,
        :availability => mean => :mean_availability,
        :availability => std0 => :std_availability,
        :false_election_rate => mean => :mean_false_election_rate,
        :false_election_rate => std0 => :std_false_election_rate,
        :safety_violations => mean => :mean_safety_violations,
    )

    if include_timeout
        timeout_agg = combine(grouped, :timeout_scaling => mean => :mean_timeout_scaling)
        agg = leftjoin(agg, timeout_agg, on=:beta)
    end

    sort!(agg, :beta)
    return agg
end

std0(x) = length(x) <= 1 ? 0.0 : std(x)

function write_aggregates(phase1::DataFrame, phase2::DataFrame)
    CSV.write(joinpath(RESULTS_DIR, "aggregated_phase1.csv"), phase1)
    CSV.write(joinpath(RESULTS_DIR, "aggregated_phase2.csv"), phase2)
end

function save_pdf_png(plot_obj, path_without_ext::AbstractString)
    savefig(plot_obj, path_without_ext * ".pdf")
    savefig(plot_obj, path_without_ext * ".png")
end

function figure2_availability(phase1::DataFrame, phase2::DataFrame)
    p = plot(
        size=(1050, 750),
        xlims=(0.0, 0.9),
        ylims=(0.0, 1.05),
        xticks=0.0:0.1:0.9,
        xlabel="Leader velocity β = v/c",
        ylabel="Availability",
        legend=:topright,
        legendfontsize=8,
        framestyle=:box,
        grid=true,
        gridstyle=:dash,
        gridlinewidth=0.5,
        dpi=300,
    )
    plot!(
        p,
        phase1.beta,
        phase1.mean_availability;
        ribbon=phase1.std_availability,
        color=:black,
        label="Fixed timeout",
        linewidth=1.5,
    )
    plot!(
        p,
        phase2.beta,
        phase2.mean_availability;
        ribbon=phase2.std_availability,
        color=:blue,
        label="T_VAT",
        linewidth=1.5,
    )
    save_pdf_png(p, joinpath(FIGURES_DIR, "figure2_availability"))
end

function figure3_false_elections(phase1::DataFrame, phase2::DataFrame)
    joined = outerjoin(
        select(phase1, :beta, :mean_false_election_rate => :phase1_rate),
        select(phase2, :beta, :mean_false_election_rate => :phase2_rate),
        on=:beta,
    )
    sort!(joined, :beta)

    betas = collect(joined.beta)
    phase1_rates = max.(coalesce.(joined.phase1_rate, 0.0), 1.0e-8)
    phase2_rates = max.(coalesce.(joined.phase2_rate, 0.0), 1.0e-8)

    width = 0.018
    p = bar(
        betas .- width / 2,
        phase1_rates;
        bar_width=width,
        color=:red,
        label="Fixed timeout",
        yscale=:log10,
        xlims=(-0.025, 0.925),
        xticks=0.0:0.1:0.9,
        xlabel="Leader velocity β = v/c",
        ylabel="False elections / heartbeat",
        legend=:topright,
        legendfontsize=8,
        framestyle=:box,
        grid=true,
        gridstyle=:dash,
        gridlinewidth=0.5,
        size=(1050, 750),
        dpi=300,
    )
    bar!(
        p,
        betas .+ width / 2,
        phase2_rates;
        bar_width=width,
        color=:blue,
        label="T_VAT",
    )
    hline!(p, [1.0e-4]; color=:black, linestyle=:dash, linewidth=1.0, label="target")
    save_pdf_png(p, joinpath(FIGURES_DIR, "figure3_false_elections"))
end

function figure4_timeout_adaptation(phase2::DataFrame)
    betas = collect(phase2.beta)
    observed_d = timeout_scaling.(betas)
    measured = if :mean_timeout_scaling in Symbol.(names(phase2))
        collect(phase2.mean_timeout_scaling)
    else
        timeout_scaling.(betas)
    end
    order = sortperm(observed_d)

    p = plot(
        observed_d[order],
        timeout_scaling.(betas)[order];
        color=:black,
        label="Theory",
        linewidth=1.5,
        xlabel="Observed D = delta_t_obs / delta_tau_emit",
        ylabel="Follower timeout / base timeout",
        legend=:topleft,
        legendfontsize=8,
        framestyle=:box,
        grid=true,
        gridstyle=:dash,
        gridlinewidth=0.5,
        size=(1050, 750),
        dpi=300,
    )
    scatter!(p, observed_d, measured; color=:blue, label="Measured", markersize=4)
    save_pdf_png(p, joinpath(FIGURES_DIR, "figure4_timeout_adaptation"))
end

function row_at_beta(df::DataFrame, beta::Float64)
    matches = df[isapprox.(df.beta, beta; atol=1.0e-12, rtol=0.0), :]
    return isempty(matches) ? nothing : matches[1, :]
end

function fmt3(x)
    return ismissing(x) || isnan(Float64(x)) ? "TODO" : @sprintf("%.3f", Float64(x))
end

function fmt_sci(x)
    return ismissing(x) || isnan(Float64(x)) ? "TODO" : @sprintf("%.2e", Float64(x))
end

function phase0_summary_table(phase0::DataFrame)
    total_seeds = isempty(phase0) ? 0 : length(unique(phase0.seed))
    mean_safety = isempty(phase0) ? NaN : mean(phase0.safety_violations)
    mean_safety_text = @sprintf("%.3f", mean_safety)

    open(joinpath(TABLES_DIR, "phase0_summary.tex"), "w") do io
        println(io, "\\begin{tabular}{lr}")
        println(io, "\\hline")
        println(io, "Metric & Value \\\\")
        println(io, "\\hline")
        println(io, "Total seeds & $(total_seeds) \\\\")
        println(io, "Mean safety violations & $(mean_safety_text) \\\\")
        println(io, "Max Newton iterations & TODO \\\\")
        println(io, "Max radial error & TODO \\\\")
        println(io, "\\hline")
        println(io, "\\end{tabular}")
    end
end

function phase1_vs_phase2_table(phase1::DataFrame, phase2::DataFrame)
    open(joinpath(TABLES_DIR, "phase1_vs_phase2.tex"), "w") do io
        println(io, "\\begin{tabular}{rrr}")
        println(io, "\\hline")
        println(io, "\$\\beta\$ & Availability fixed & Availability T\\_VAT \\\\")
        println(io, "\\hline")
        for beta in (0.0, 0.3, 0.6, 0.9)
            r1 = row_at_beta(phase1, beta)
            r2 = row_at_beta(phase2, beta)
            a1 = r1 === nothing ? "TODO" : fmt3(r1.mean_availability)
            a2 = r2 === nothing ? "TODO" : fmt3(r2.mean_availability)
            println(io, @sprintf("%.1f", beta), " & ", a1, " & ", a2, " \\\\")
        end
        println(io, "\\hline")
        println(io, "\\end{tabular}")
    end
end

function write_placeholders(phase1::DataFrame, phase2::DataFrame)
    knee = "TODO"
    for row in eachrow(sort(phase1, :beta))
        if row.mean_availability < 0.5
            knee = @sprintf("%.2f", row.beta)
            break
        end
    end

    p2_09 = row_at_beta(phase2, 0.9)
    avail09 = p2_09 === nothing ? "TODO" : fmt3(p2_09.mean_availability)
    false09 = p2_09 === nothing ? "TODO" : fmt_sci(p2_09.mean_false_election_rate)

    open(joinpath(PAPER_DIR, "placeholders.tex"), "w") do io
        println(io, "\\newcommand{\\PhaseOneKneeBeta}{$knee}")
        println(io, "\\newcommand{\\PhaseTwoAvailabilityAt09}{$avail09}")
        println(io, "\\newcommand{\\PhaseTwoFalseElectionRate}{$false09}")
    end
end

function write_summary(phase0::DataFrame, phase1::DataFrame, phase2::DataFrame)
    phase3_files = result_files("phase3_causal_*.csv")
    phase0_safety = isempty(phase0) ? 0 : sum(phase0.safety_violations)
    phase0_seeds = isempty(phase0) ? 0 : length(unique(phase0.seed))

    p1_09 = row_at_beta(phase1, 0.9)
    p2_09 = row_at_beta(phase2, 0.9)

    p1_avail_mean = p1_09 === nothing ? NaN : Float64(p1_09.mean_availability)
    p1_avail_std = p1_09 === nothing ? NaN : Float64(p1_09.std_availability)
    p2_avail_mean = p2_09 === nothing ? NaN : Float64(p2_09.mean_availability)
    p2_avail_std = p2_09 === nothing ? NaN : Float64(p2_09.std_availability)
    p2_false_mean = p2_09 === nothing ? NaN : Float64(p2_09.mean_false_election_rate)
    p1_avail_text = @sprintf("%.6f", p1_avail_mean)
    p1_std_text = @sprintf("%.6f", p1_avail_std)
    p2_avail_text = @sprintf("%.6f", p2_avail_mean)
    p2_std_text = @sprintf("%.6f", p2_avail_std)
    p2_false_text = @sprintf("%.6e", p2_false_mean)

    safety_pass = phase0_safety == 0
    phase1_pass = !isnan(p1_avail_mean) && p1_avail_mean < 0.05
    phase2_pass = !isnan(p2_false_mean) && p2_false_mean < 0.0001

    open(joinpath(RESULTS_DIR, "SUMMARY.md"), "w") do io
        println(io, "# Results Summary")
        println(io)
        println(io, "Phase0: safety_violations = $(phase0_safety) across $(phase0_seeds) seeds")
        println(io, "Phase1 beta=0.9: availability = $(p1_avail_text) ± $(p1_std_text)")
        println(io, "Phase2 beta=0.9: availability = $(p2_avail_text) ± $(p2_std_text), false_elections = $(p2_false_text)")
        println(io)
        println(io, "Criteria:")
        println(io, "- safety=0: ", safety_pass ? "PASS" : "FAIL")
        println(io, "- phase1 availability <0.05: ", phase1_pass ? "PASS" : "FAIL")
        println(io, "- phase2 false_elections <0.0001: ", phase2_pass ? "PASS" : "FAIL")
        if isempty(phase3_files)
            println(io)
            println(io, "Phase3: no phase3_causal CSV present; phase3 analysis skipped.")
        else
            println(io)
            println(io, "Phase3: found $(length(phase3_files)) phase3_causal CSV file(s).")
        end
    end
end

function main()
    phase0 = read_raft_files("phase0_baseline_*.csv")
    phase1_raw = read_raft_files("phase1_degradation_*.csv")
    phase2_raw = read_raft_files("phase2_tvat_*.csv")

    if isempty(phase1_raw)
        error("No results/phase1_degradation_*.csv files found")
    end
    if isempty(phase2_raw)
        error("No results/phase2_tvat_*.csv files found")
    end

    phase1 = aggregate_phase(phase1_raw)
    phase2 = aggregate_phase(phase2_raw; include_timeout=true)

    write_aggregates(phase1, phase2)
    figure2_availability(phase1, phase2)
    figure3_false_elections(phase1, phase2)
    figure4_timeout_adaptation(phase2)
    phase0_summary_table(phase0)
    phase1_vs_phase2_table(phase1, phase2)
    write_placeholders(phase1, phase2)
    write_summary(phase0, phase1, phase2)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
