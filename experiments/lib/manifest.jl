# Shared run-manifest helpers for experiment runners.
#
# Provenance rules (see docs/DEVIATIONS.md, D-07):
# - the manifest records the HEAD commit *and* whether the working tree was
#   dirty when the run started, together with a digest of the diff;
# - confirmatory runs refuse to start from a dirty tree;
# - the manifest is valid JSON written by one escaping routine.

using Dates
using SHA

function _git(arguments::Vector{String})
    try
        return readchomp(pipeline(`git $arguments`; stderr=devnull))
    catch
        return nothing
    end
end

"""
    git_provenance()

Return `(sha, dirty, diff_sha256)` for the repository containing the current
working directory. `dirty` covers tracked-file modifications and untracked
files outside ignored paths; `diff_sha256` digests `git diff HEAD` plus the
untracked-file list so a dirty run can still be matched to its source state.
"""
function git_provenance()
    sha = _git(["rev-parse", "HEAD"])
    isnothing(sha) && return (sha="unknown", dirty=true, diff_sha256="unknown")
    status = something(_git(["status", "--porcelain"]), "?")
    dirty = !isempty(strip(status))
    diff = something(_git(["diff", "HEAD"]), "") * "\n" * status
    return (sha=sha, dirty=dirty, diff_sha256=bytes2hex(sha256(diff)))
end

"""
    require_clean_tree(provenance; confirmatory)

Throw when a confirmatory run is requested from a dirty working tree.
"""
function require_clean_tree(provenance; confirmatory::Bool)
    if confirmatory && provenance.dirty
        error("confirmatory runs require a clean working tree at a committed SHA " *
              "(HEAD=$(provenance.sha)); commit or stash changes first")
    end
    return nothing
end

_json_escape(s::AbstractString) = replace(
    String(s),
    "\\" => "\\\\",
    "\"" => "\\\"",
    "\n" => "\\n",
    "\r" => "\\r",
    "\t" => "\\t",
)

_json(value::AbstractString) = "\"" * _json_escape(value) * "\""
_json(value::Symbol) = _json(String(value))
_json(value::Bool) = value ? "true" : "false"
_json(value::Integer) = string(value)
_json(value::AbstractFloat) = isfinite(value) ? repr(Float64(value)) : "null"
_json(::Nothing) = "null"
_json(value::AbstractRange) = _json(string(value))
_json(value::AbstractVector) = "[" * join((_json(v) for v in value), ", ") * "]"
function _json(value::AbstractDict)
    keys_sorted = sort!(collect(keys(value)); by=string)
    return "{" * join((_json(string(k)) * ": " * _json(value[k]) for k in keys_sorted), ", ") * "}"
end
_json(value::NamedTuple) = _json(Dict(string(k) => v for (k, v) in pairs(value)))

"""
    write_manifest(path, fields::AbstractDict)

Write `fields` plus standard provenance keys (`git_sha`, `git_dirty`,
`git_diff_sha256`, `julia`, `started`) as JSON.
"""
function write_manifest(path::AbstractString, fields::AbstractDict; provenance=git_provenance())
    record = Dict{String,Any}(string(k) => v for (k, v) in fields)
    record["git_sha"] = provenance.sha
    record["git_dirty"] = provenance.dirty
    record["git_diff_sha256"] = provenance.diff_sha256
    record["julia"] = string(VERSION)
    record["started"] = Dates.format(now(), "yyyy-mm-ddTHH:MM:SS")
    open(path, "w") do io
        println(io, _json(record))
    end
    return record
end

"""Escape a TSV cell: tabs/newlines in free-text fields would corrupt rows."""
tsv_cell(value) = replace(string(value), '\t' => ' ', '\n' => ' ', '\r' => ' ')
