using Test

module RQ1ToolingUnderTest
include(joinpath(@__DIR__, "..", "..", "experiments", "run_rq1.jl"))
end

module AnalyzeRQ1UnderTest
include(joinpath(@__DIR__, "..", "..", "experiments", "analyze_rq1.jl"))
end

@testset "experiment manifest helper" begin
    M = RQ1ToolingUnderTest
    provenance = M.git_provenance()
    @test provenance.sha isa AbstractString
    @test provenance.dirty isa Bool
    @test length(provenance.diff_sha256) == 64 || provenance.diff_sha256 == "unknown"

    @test_throws ErrorException M.require_clean_tree(
        (sha="abc", dirty=true, diff_sha256="x"); confirmatory=true)
    @test isnothing(M.require_clean_tree((sha="abc", dirty=true, diff_sha256="x"); confirmatory=false))
    @test isnothing(M.require_clean_tree((sha="abc", dirty=false, diff_sha256="x"); confirmatory=true))

    @test M._json("a\"b\\c\td") == "\"a\\\"b\\\\c\\td\""
    @test M._json(Dict("b" => 1, "a" => Any[true, nothing, NaN])) == "{\"a\": [true, null, null], \"b\": 1}"
    @test M.tsv_cell("x\ty\nz") == "x y z"

    mktempdir() do dir
        path = joinpath(dir, "manifest.json")
        record = M.write_manifest(path, Dict("run_id" => "t");
            provenance=(sha="deadbeef", dirty=false, diff_sha256="00"))
        text = read(path, String)
        @test occursin("\"git_sha\": \"deadbeef\"", text)
        @test occursin("\"git_dirty\": false", text)
        @test record["run_id"] == "t"
    end
end

@testset "run_rq1 sweep options" begin
    M = RQ1ToolingUnderTest
    options = M.parse_sweep_options(["--seeds", "5:9", "--out", "x", "--confirmatory", "--prereg", "tag"])
    @test options.seeds == 5:9
    @test options.out_dir == "x"
    @test options.confirmatory
    @test options.prereg == "tag"
    @test isnothing(redirect_stderr(devnull) do
        M.parse_sweep_options(["--bogus", "1"])
    end)
    @test isnothing(redirect_stderr(devnull) do
        M.parse_sweep_options(["--seeds"])
    end)
    defaults = M.parse_sweep_options(String[])
    @test isnothing(defaults.seeds) && !defaults.confirmatory && defaults.prereg == "none"

    # Guards: confirmatory needs a prereg tag; existing output dirs are refused.
    @test_throws ArgumentError M.run_sweep("e1-smoke", nothing; confirmatory=true)
    mktempdir() do dir
        @test_throws ArgumentError redirect_stdout(devnull) do
            M.run_sweep("e1-smoke", dir; seeds=1:1)
        end
    end
end

@testset "run_rq1 smoke sweep and analyzer" begin
    M = RQ1ToolingUnderTest
    A = AnalyzeRQ1UnderTest
    mktempdir() do dir
        out = joinpath(dir, "smoke")
        redirect_stdout(devnull) do
            M.run_sweep("e2-smoke", out; seeds=1:1)
        end
        rows, header = A.read_tsv(joinpath(out, "runs.tsv"))
        @test length(rows) == length(M.build_e2_cells("smoke"))
        @test header == M.RQ1_HEADER
        for row in rows
            audited = parse(Int, row["audited_writes"])
            margin = parse(Float64, row["min_causal_margin"])
            # A run without audited writes must not report a numeric margin.
            @test audited > 0 ? !isnan(margin) : isnan(margin)
        end
        summary = A.generate_summary(rows, header, joinpath(out, "runs.tsv"))
        @test occursin("Committed writes audited", summary)
        @test !occursin("Validated", summary)
        @test !occursin("Supported", summary)
    end
end

@testset "analyze_rq1 statistics helpers" begin
    A = AnalyzeRQ1UnderTest
    point, lo, hi = A.bootstrap_mean_ci([1.0, 1.0, 1.0])
    @test point == 1.0 && lo == 1.0 && hi == 1.0
    point, lo, hi = A.bootstrap_mean_ci([0.5])
    @test point == 0.5 && isnan(lo)
    @test isnan(A.bootstrap_mean_ci(Float64[])[1])
    @test A.spearman([1.0, 2.0, 3.0, 4.0], [10.0, 20.0, 30.0, 40.0]) ≈ 1.0
    @test A.spearman([1.0, 2.0, 3.0, 4.0], [4.0, 3.0, 2.0, 1.0]) ≈ -1.0
    @test isnan(A.spearman([1.0, 1.0, 1.0], [1.0, 2.0, 3.0]))
end
