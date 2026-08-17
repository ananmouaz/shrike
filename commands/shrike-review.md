---
description: Forensic high-precision bug hunt on a diff, PR, branch, or file
---

Invoke the `shrike` skill and run a full bug hunt on: $ARGUMENTS

If no target was given, hunt the current working diff (uncommitted changes plus
commits not yet on the default branch).

Follow the skill's scope contract exactly: report only correctness bugs backed by
a concrete failure scenario. Zero findings is a valid, successful result.

Two things about the output:

- Stamp the start time in Phase 0 (`date +%s > /tmp/shrike-start`) and use
  `scripts/report_stats.sh` in Phase 6, so the run header carries a measured
  duration, file/hunk counts, and the candidates raised → killed → reported line.
  Never estimate those numbers.
- Print the full report in the terminal. If the target is a pull request, post the
  same markdown as one PR comment with `scripts/post_report.sh <pr> <report.md>` —
  it upserts, so re-runs replace the previous report instead of stacking copies.
