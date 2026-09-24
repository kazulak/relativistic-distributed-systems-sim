#!/usr/bin/env julia

# Exit nonzero unless an E3 completion.json reports zero failed, invalid, and
# error runs and an unhalted sweep. Used by CI after the E3 smoke sweep.
#
# Usage: julia experiments/check_completion.jl <run-dir>/completion.json


function count_of(text::AbstractString, key::AbstractString)
    m = match(Regex("\"" * key * "\":\\s*(\\d+)"), text)
    return m === nothing ? nothing : parse(Int, m.captures[1])
end

function main(arguments)
    length(arguments) == 1 || (println(stderr, "usage: check_completion.jl completion.json"); return 2)
    text = read(arguments[1], String)
    ok = true
    for key in ("completed", "failed", "invalid", "error")
        value = count_of(text, key)
        println(key, " = ", something(value, "missing"))
        if key == "completed"
            (value === nothing || value == 0) && (ok = false)
        else
            (value === nothing || value != 0) && (ok = false)
        end
    end
    occursin("\"halted\": null", text) || (println("sweep halted"); ok = false)
    println(ok ? "completion check passed" : "completion check FAILED")
    return ok ? 0 : 1
end

if abspath(PROGRAM_FILE) == @__FILE__
    exit(main(ARGS))
end
