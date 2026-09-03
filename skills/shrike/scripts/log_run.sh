#!/usr/bin/env bash
# Phase 6: append one run record, keyed on the head SHA.
#
# Nothing else in the workflow leaves a trace that a hunt happened, which makes two
# questions unanswerable: "was this commit reviewed?" (Phase 7 needs it) and "did
# reviewing reduce escaped bugs?" (any later eval needs it, at commit granularity —
# attribution reconstructed from a pull request cannot separate a genuine miss from a
# bug in code pushed after the report).
#
# Usage:
#   log_run.sh [--pr N] [--target STR] [--base REF] [--candidates N] [--killed N]
#              [--reported N] [--findings STR] [--sweeps STR] [--unreviewed STR]
#              [--note STR]
#   log_run.sh --last            # head SHA of the most recent record for this branch
#   log_run.sh --last --any      # ... for any branch
#
# Log path: $SHRIKE_LOG, else .agent/shrike-log.md at the repo root.
# Never fails the run: unknown numbers are written as "?".

set -uo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
LOG="${SHRIKE_LOG:-$ROOT/.agent/shrike-log.md}"

PR=""; TARGET=""; BASE=""; CAND="?"; KILLED="?"; REPORTED="?"
FINDINGS=""; SWEEPS=""; UNREVIEWED=""; NOTE=""; MODE="append"; SCOPE="branch"

while [ $# -gt 0 ]; do
  case "$1" in
    --pr)          PR="${2:-}"; shift 2 ;;
    --target)      TARGET="${2:-}"; shift 2 ;;
    --base)        BASE="${2:-}"; shift 2 ;;
    --candidates)  CAND="${2:-?}"; shift 2 ;;
    --killed)      KILLED="${2:-?}"; shift 2 ;;
    --reported)    REPORTED="${2:-?}"; shift 2 ;;
    --findings)    FINDINGS="${2:-}"; shift 2 ;;
    --sweeps)      SWEEPS="${2:-}"; shift 2 ;;
    --unreviewed)  UNREVIEWED="${2:-}"; shift 2 ;;
    --note)        NOTE="${2:-}"; shift 2 ;;
    --last)        MODE="last"; shift ;;
    --any)         SCOPE="any"; shift ;;
    -h|--help)     sed -n '2,20p' "$0"; exit 0 ;;
    *)             echo "log_run.sh: unknown argument $1" >&2; shift ;;
  esac
done

BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")

# --- --last: what the previous report covered, for Phase 7 -------------------
if [ "$MODE" = "last" ]; then
  [ -r "$LOG" ] || { echo ""; exit 0; }
  if [ "$SCOPE" = "any" ]; then
    sed -n 's/.*head=`\([0-9a-f]\{7,40\}\)`.*/\1/p' "$LOG" | tail -1
  else
    # Records carry `branch=<name>` on the same line as `head=<sha>`.
    LINE=$(grep -F "branch=\`$BRANCH\`" "$LOG" 2>/dev/null | tail -1)
    printf '%s\n' "$LINE" | sed -n 's/.*head=`\([0-9a-f]\{7,40\}\)`.*/\1/p' | tail -1
  fi
  exit 0
fi

# --- diff scope --------------------------------------------------------------
HEAD_SHA=$(git rev-parse HEAD 2>/dev/null || echo "?")
SHORT_HEAD=$(git rev-parse --short HEAD 2>/dev/null || echo "?")

if [ -z "$BASE" ]; then
  BASE=$(git merge-base HEAD main 2>/dev/null \
      || git merge-base HEAD master 2>/dev/null \
      || echo "")
fi

FILES="?"; HUNKS="?"; RANGE="?"
if [ -n "$BASE" ]; then
  RANGE="$(git rev-parse --short "$BASE" 2>/dev/null || echo "$BASE")...$SHORT_HEAD"
  FILES=$( { git diff --name-only "$BASE"...HEAD 2>/dev/null; git diff --name-only 2>/dev/null; } \
           | sort -u | sed '/^$/d' | wc -l | tr -d ' ' )
  HUNKS=$( { git diff -U0 "$BASE"...HEAD 2>/dev/null; git diff -U0 2>/dev/null; } \
           | grep '^@@' | wc -l | tr -d ' ' )
fi

# --- elapsed, from the Phase 0 stamp ----------------------------------------
STAMP="${SHRIKE_START_FILE:-/tmp/shrike-start}"
DURATION="?"
if [ -r "$STAMP" ]; then
  START=$(tr -dc '0-9' < "$STAMP" 2>/dev/null)
  NOW=$(date +%s)
  if [ -n "$START" ] && [ "$START" -gt 0 ] 2>/dev/null && [ "$NOW" -ge "$START" ]; then
    S=$((NOW - START))
    # A stamp older than a day is a leftover from an earlier session, not this run.
    if [ "$S" -gt 86400 ]; then DURATION="? (stale start stamp)"
    elif [ "$S" -ge 60 ]; then DURATION="$((S / 60))m $((S % 60))s"
    else DURATION="${S}s"; fi
  fi
fi

[ -n "$TARGET" ] || TARGET=$([ -n "$PR" ] && echo "PR #$PR" || echo "$BRANCH")
[ -n "$FINDINGS" ] || FINDINGS="?"
[ -n "$SWEEPS" ] || SWEEPS="not recorded"
[ -n "$UNREVIEWED" ] || UNREVIEWED="not stated"

mkdir -p "$(dirname "$LOG")" 2>/dev/null
if [ ! -f "$LOG" ]; then
  {
    echo "# Shrike run log"
    echo
    echo "One record per hunt, appended by \`scripts/log_run.sh\`. Keyed on the head SHA:"
    echo "a record proves which commit was hunted, so Phase 7 can diff what landed since"
    echo "and a later eval can attribute escaped bugs at commit granularity."
    echo
  } > "$LOG"
fi

{
  echo "## $(date -u +%Y-%m-%dT%H:%M:%SZ) — $TARGET"
  echo
  echo "- head=\`$HEAD_SHA\` branch=\`$BRANCH\` range=\`$RANGE\`"
  echo "- diff: $FILES files, $HUNKS hunks · duration: $DURATION"
  echo "- sweeps: $SWEEPS"
  echo "- candidates: $CAND raised → $KILLED killed → $REPORTED reported ($FINDINGS)"
  echo "- unreviewed: $UNREVIEWED"
  [ -n "$NOTE" ] && echo "- note: $NOTE"
  echo
} >> "$LOG"

echo "logged $SHORT_HEAD → $LOG"
