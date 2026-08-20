#!/usr/bin/env bash
# Phase 6: the measured numbers for the report header.
# Elapsed time comes from the stamp Phase 0 wrote; everything else from git.
# Never fails the run — a missing number is printed as "?" , not an error.
#
# Usage: report_stats.sh [base-ref] [last-reviewed-sha]
#        base-ref defaults to the merge-base with main/master.
#        last-reviewed-sha defaults to the `shrike-head` stamp on the pull request's
#        existing Shrike comment when SHRIKE_PR is set and gh is available.

set -uo pipefail

STAMP="${SHRIKE_START_FILE:-/tmp/shrike-start}"
SECS=""

# --- elapsed ---
if [ -r "$STAMP" ]; then
  START=$(cat "$STAMP" 2>/dev/null | tr -dc '0-9')
  NOW=$(date +%s)
  if [ -n "$START" ] && [ "$START" -gt 0 ] 2>/dev/null && [ "$NOW" -ge "$START" ]; then
    SECS=$((NOW - START))
    if [ "$SECS" -ge 60 ]; then
      DURATION="$((SECS / 60))m $((SECS % 60))s"
    else
      DURATION="${SECS}s"
    fi
  else
    DURATION="?"
  fi
else
  DURATION="? (no start stamp — Phase 0 should write $STAMP)"
fi

# --- diff scope ---
BASE="${1:-}"
if [ -z "$BASE" ]; then
  BASE=$(git merge-base HEAD main 2>/dev/null \
      || git merge-base HEAD master 2>/dev/null \
      || echo "")
fi

FILES="?"; HUNKS="?"; RANGE="?"
if [ -n "$BASE" ]; then
  SHORT_BASE=$(git rev-parse --short "$BASE" 2>/dev/null || echo "$BASE")
  SHORT_HEAD=$(git rev-parse --short HEAD 2>/dev/null || echo HEAD)
  RANGE="${SHORT_BASE}...${SHORT_HEAD}"
  # Committed changes plus anything still in the working tree.
  # `grep -c` prints 0 and exits 1 on no match, so count with wc instead — a `|| echo 0`
  # fallback would emit a second zero.
  FILES=$( { git diff --name-only "$BASE"...HEAD 2>/dev/null; git diff --name-only 2>/dev/null; } \
           | sort -u | sed '/^$/d' | wc -l | tr -d ' ' )
  HUNKS=$( { git diff -U0 "$BASE"...HEAD 2>/dev/null; git diff -U0 2>/dev/null; } \
           | grep '^@@' | wc -l | tr -d ' ' )
fi

BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")

# --- effort per hunk: the number that exposes a skimmed pass ---
# A hunk worked honestly costs minutes. A rate far above previous runs on this repo
# means the pass was thin, not that the diff was clean.
RATE="?"
if [ -n "$SECS" ] && [ "$SECS" -gt 0 ] 2>/dev/null && [ "$HUNKS" != "?" ] \
   && [ "$HUNKS" -gt 0 ] 2>/dev/null; then
  RATE="$(( HUNKS * 3600 / SECS )) hunks/hour ($(( SECS / HUNKS ))s per hunk)"
fi

# --- what a previous report already covered, and what has landed since (Phase 7) ---
LAST="${2:-}"
if [ -z "$LAST" ] && [ -n "${SHRIKE_PR:-}" ] && command -v gh >/dev/null 2>&1; then
  R="${GH_REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)}"
  if [ -n "$R" ]; then
    LAST=$(gh api --paginate "repos/$R/issues/${SHRIKE_PR}/comments" \
             --jq '[.[] | select(.body | startswith("<!-- shrike-report -->"))] | last | .body // empty' \
           2>/dev/null | sed -n 's/.*<!-- shrike-head: \([0-9a-f]\{7,40\}\) -->.*/\1/p' | head -1)
  fi
fi

DELTA="none — this is the first report on this branch"
if [ -n "$LAST" ] && git cat-file -e "$LAST^{commit}" 2>/dev/null; then
  D_COMMITS=$(git rev-list --count "$LAST"..HEAD 2>/dev/null || echo "?")
  D_HUNKS=$( { git diff -U0 "$LAST"..HEAD 2>/dev/null; git diff -U0 2>/dev/null; } \
             | grep '^@@' | wc -l | tr -d ' ' )
  if [ "$D_COMMITS" = "0" ]; then
    DELTA="nothing pushed since the last report ($(git rev-parse --short "$LAST" 2>/dev/null))"
  else
    DELTA="$D_COMMITS commit(s) / $D_HUNKS hunk(s) since $(git rev-parse --short "$LAST" 2>/dev/null) — HUNT THIS DELTA before reporting"
  fi
elif [ -n "$LAST" ]; then
  DELTA="last reviewed sha $LAST is not in this repo — fetch it, or treat the branch as unreviewed"
fi

echo "duration:  $DURATION"
echo "rate:      $RATE"
echo "branch:    $BRANCH"
echo "range:     $RANGE"
echo "files:     $FILES"
echo "hunks:     $HUNKS"
echo "since:     $DELTA"
echo
echo "Fill the remaining header rows yourself — callers read outside the diff, peers"
echo "compared against it, which invariant classes were live and what you searched for"
echo "the ones you called n/a, the candidates raised/killed/reported counts, and any"
echo "slice you left unhunted. Report them honestly; do not round them in your favour."
