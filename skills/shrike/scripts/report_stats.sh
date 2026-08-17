#!/usr/bin/env bash
# Phase 6: the measured numbers for the report header.
# Elapsed time comes from the stamp Phase 0 wrote; everything else from git.
# Never fails the run — a missing number is printed as "?" , not an error.
#
# Usage: report_stats.sh [base-ref]
#        base-ref defaults to the merge-base with main/master.

set -uo pipefail

STAMP="${SHRIKE_START_FILE:-/tmp/shrike-start}"

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

echo "duration:  $DURATION"
echo "branch:    $BRANCH"
echo "range:     $RANGE"
echo "files:     $FILES"
echo "hunks:     $HUNKS"
echo
echo "Fill the remaining header rows yourself — callers read outside the diff,"
echo "which invariant classes were live, and the candidates raised/killed/reported"
echo "counts are yours to report honestly. Do not round them in your favour."
