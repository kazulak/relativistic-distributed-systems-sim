# Analysis and legacy experiment environment

The root project is the lightweight simulator/protocol package and canonical
test environment. Plotting, tabular analysis, and dependencies used only by the
exploratory phase scripts live in this separate environment so that installing
or testing the package does not download a graphics stack.

Instantiate it explicitly:

```sh
julia --project=analysis -e 'import Pkg; Pkg.instantiate()'
```

Run a legacy script from the repository root, for example:

```sh
julia --project=analysis scripts/analyze_results.jl
```

These scripts and the existing generated results remain exploratory material;
this environment split does not promote them to publication evidence. The
analysis environment intentionally has no checked manifest while the research
pipeline, datasets, and artifact schema are still changing. Its lockfile will
be generated and checked only at artifact freeze, together with the frozen
inputs and expected outputs. Until that freeze is complete, this environment
cannot support reproducible paper results or publication claims.
