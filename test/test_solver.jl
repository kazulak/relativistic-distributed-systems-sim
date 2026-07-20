# Backward-compatible entry point for the former standalone solver test command.
# The maintained physics suite now exercises the installed package API through
# the canonical test runner.
ENV["RDS_TEST_GROUP"] = "physics"
include("runtests.jl")
