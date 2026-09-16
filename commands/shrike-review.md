---
description: Forensic high-precision bug hunt on a diff, PR, branch, or file
---

Invoke the `shrike` skill and run a full bug hunt on: $ARGUMENTS

If no target was given, hunt the current working diff (uncommitted changes plus
commits not yet on the default branch).

Follow the skill's scope contract exactly: report only correctness bugs backed by
a concrete failure scenario. Zero findings is a valid, successful result.

Review handoff and output:

- Stamp the start time in Phase 0 (use a chain-specific `SHRIKE_START_FILE`) and use
  `scripts/report_stats.sh` in Phase 6, so the run header carries a measured
  duration, file/hunk counts, hunks-per-hour, and the candidates raised → killed →
  reported line. Never estimate those numbers. On a pull request, run it as
  `SHRIKE_PR=<pr> scripts/report_stats.sh` — it then reports what has been pushed
  since the previous report, which Phase 7 requires you to hunt.
- Print the full report in the terminal. If the target is a pull request, post the
  same markdown as one PR comment with `scripts/post_report.sh <pr> <report.md>` —
  it upserts, so re-runs replace the previous report instead of stacking copies, and
  stamps the reviewed commit in the comment.
- The run record is written from the report. `post_report.sh` does it before posting
  and refuses to post if it fails; with no pull request, run
  `scripts/log_run.sh --report <report.md>` yourself before printing. The record is one
  JSON line in `${XDG_STATE_HOME:-~/.local/state}/shrike/runs.jsonl`, keyed on repo,
  branch, and head SHA — what lets Phase 7 (and any later question about what escaped)
  tell a miss on reviewed code apart from a bug pushed after the report.
- Issue independent tool calls together in one message: the five sweep greps, the
  per-symbol caller greps, the second-site file opens. The run is latency-bound on
  round-trips.
- Close each credible candidate's reachable sibling states before handing off fixes.
  Read `references/review-reuse.md`; give the fixer all survivors and family triggers,
  including those beyond the five displayed findings.
- For another round, pass the evidence bundle and coverage ledger to the fresh
  reviewer. Review the changed dependency slice plus prior triggers and siblings at
  full depth; reuse only validated unaffected coverage. Missing ledger or uncertain
  dependency boundary means widening the hunt. Include dirty and untracked changes.
- Do not stop at Phase 6 if fixes or a moving target remain unreviewed. Zero new
  findings is not clean without complete original coverage and verified fixes.
  `SHRIKE_MAX_ROUNDS` (default 3) is a handoff budget, never clearance; an explicit
  project continuation policy takes precedence. Count rounds in this chain.
