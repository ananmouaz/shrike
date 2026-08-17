#!/usr/bin/env bash
# Phase 6: post the report to a pull request as ONE comment.
#
# Upserts: finds the previous Shrike comment by its hidden marker and edits it in
# place, so re-running on a new push replaces the report instead of stacking copies.
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

REPO="${GH_REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"

BODY_FILE=$(mktemp)
trap 'rm -f "$BODY_FILE"' EXIT
{
  printf '%s\n' "$MARKER"
  cat "$FILE"
  printf '\n\n<sub>🔪 Shrike · updated in place on each push</sub>\n'
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
