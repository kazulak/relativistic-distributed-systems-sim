#!/usr/bin/env julia

using RelativisticDistributedSystemsSim
using RelativisticDistributedSystemsSim.Research

const FAMILY_BY_NAME = Dict(
    "control" => ColocatedControl,
    "static" => SeparatedStaticBaseline,
    "receding" => AsymmetricRecedingInertial,
    "accelerating" => AcceleratingBaseline,
    "stress" => PartitionDropStress,
)

function usage(io::IO=stdout)
    println(io, "usage: julia --project=. experiments/run_rq1.jl FAMILY [CLUSTER_SIZE] [SEED]")
    println(io, "FAMILY: control | static | receding | accelerating | stress | all")
end

function main(arguments)
    isempty(arguments) && (usage(stderr); return 2)
    family_name = lowercase(arguments[1])
    cluster_size = length(arguments) >= 2 ? parse(Int, arguments[2]) : 3
    seed = length(arguments) >= 3 ? parse(UInt64, arguments[3]) : UInt64(1)
    if family_name == "all"
        for config in rq1_scenarios(cluster_size=cluster_size)
            print_run_summary(run_scenario(config; seed=seed))
            println()
        end
        return 0
    end
    family = get(FAMILY_BY_NAME, family_name, nothing)
    if isnothing(family)
        usage(stderr)
        return 2
    end
    result = run_scenario(canonical_scenario(family; cluster_size=cluster_size); seed=seed)
    print_run_summary(result)
    return result.status == :completed ? 0 : 1
end

exit(main(ARGS))
