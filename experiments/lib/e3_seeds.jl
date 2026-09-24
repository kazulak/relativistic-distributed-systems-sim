# Authoritative E3 seed ranges, shared by the runner, the tuner, and the
# analyzer. Dependency-free so analysis code can include it without loading
# the simulator. Changing either range requires a new preregistration addendum.

"""Authoritative E3 tuning seed range (prereg §7)."""
const E3_TUNING_SEEDS = 1:200

"""
Authoritative (proposed) E3 confirmatory report seed range. Seeds 201–224 were
executed by the voided r2 pilot (docs/DEVIATIONS.md D-01), so the r3 range
201–320 is contaminated; 1001–1120 is fresh and never executed (N = 120). The
final choice is the researcher's and must be frozen in the r4 addendum.
"""
const E3_REPORT_SEEDS = 1001:1120
