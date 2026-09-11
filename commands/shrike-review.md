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
- Do not stop at Phase 6 if you fixed anything or the branch moved. Phase 7 exists
  because a report is only true of the commit range in its header. A round after the
  first hunts only the delta since the last recorded head, and the loop stops after
  `SHRIKE_MAX_ROUNDS` rounds (default 3) with what is still open named in the report.
