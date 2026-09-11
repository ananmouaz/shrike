#!/usr/bin/env bash
# Phase 6: record the run, then post the report to a pull request as ONE comment.
#
# Upserts: finds the previous Shrike comment by its hidden marker and edits it in
# place, so re-running on a new push replaces the report instead of stacking copies.
#
# Records first: the report already carries every number the run record needs, so this
# script hands it to log_run.sh before posting. If the record cannot be written — the
# header lacks a Candidates row, the log path is not writable — nothing is posted and
# the exit status is 1. A report is not allowed to exist without its record; without
# one, "was this commit hunted?" is unanswerable later. A re-post of an unchanged
# report is recognised by log_run.sh and does not create a second record.
#
# Usage: post_report.sh <pr-number> <report.md>
#        post_report.sh 142 /tmp/shrike-report.md
#
# Requires: gh, authenticated, with pull-requests:write on the repo.

set -euo pipefail

PR="${1:-}"
FILE="${2:-}"
MARKER="<!-- shrike-report -->"

if [ -z "$PR" ] || [ -z "$FILE" ]; then
  echo "usage: post_report.sh <pr-number> <report.md>" >&2
  exit 2
fi
if [ ! -r "$FILE" ]; then
  echo "cannot read report file: $FILE" >&2
  exit 2
fi
if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI not found — print the report to the terminal instead" >&2
  exit 2
fi

# --- 1. the record ------------------------------------------------------------
LOGGER="$(dirname "$0")/log_run.sh"
if ! "$LOGGER" --pr "$PR" --report "$FILE"; then
  echo "post_report.sh: refusing to post — the run was not recorded (see log_run.sh above)." >&2
  echo "Fix the run header (Candidates row: 'N raised → N killed … → **N reported**') and re-run." >&2
  exit 1
fi

# --- 2. the comment -----------------------------------------------------------
REPO="${GH_REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"

REVIEWED_HEAD=$(git rev-parse HEAD 2>/dev/null || echo "unknown")

BODY_FILE=$(mktemp)
trap 'rm -f "$BODY_FILE"' EXIT
{
  printf '%s\n' "$MARKER"
  # Machine-readable stamp of the commit this report covers. A later run reads it
  # (report_stats.sh) to diff what has been pushed since, so "reviewed" always names
  # a specific commit rather than "the branch".
  printf '<!-- shrike-head: %s -->\n' "$REVIEWED_HEAD"
  cat "$FILE"
  printf '\n\n<sub>🔪 Shrike · updated in place on each push · reviewed `%s`</sub>\n' \
    "${REVIEWED_HEAD:0:8}"
} > "$BODY_FILE"

# Find an existing Shrike comment on this PR.
EXISTING=$(gh api --paginate "repos/$REPO/issues/$PR/comments" \
             --jq "[.[] | select(.body | startswith(\"$MARKER\"))] | last | .id // empty" \
           2>/dev/null || echo "")

if [ -n "$EXISTING" ]; then
  gh api -X PATCH "repos/$REPO/issues/comments/$EXISTING" \
    -F body=@"$BODY_FILE" --jq '.html_url'
  echo "updated existing Shrike comment" >&2
else
  gh api -X POST "repos/$REPO/issues/$PR/comments" \
    -F body=@"$BODY_FILE" --jq '.html_url'
  echo "posted new Shrike comment" >&2
fi
