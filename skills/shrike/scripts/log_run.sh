#!/usr/bin/env bash
# Phase 6: append one run record, as one JSON line, keyed on repo + branch + head SHA.
#
# Why a machine-local JSONL file and not a markdown file in the repo:
#   - a record written inside a worktree died with the worktree; one file per machine
#     outlives every checkout that wrote to it;
#   - an append-only tracked file written from many branches conflicted on every
#     rebase, and `merge=union` silently dropped record lines;
#   - prose cannot be queried. "Did hunting reduce escaped bugs?" is a jq one-liner
#     over this file and a lookup of each record's head SHA.
#
# Usage:
#   log_run.sh --report FILE [--pr N] [--base REF] [--round N] [--note STR]
#       Read candidates/killed/reported, severity counts, sweep counts, the target and
#       the "Not reviewed" row from the report's run header. Flags override the report.
#       post_report.sh calls this before it posts; the report is not allowed to exist
#       without its record.
#   log_run.sh --pr N --candidates N --killed N --reported N [--findings STR]
#              [--sweeps STR] [--unreviewed STR] [--target STR] [--base REF] [--note STR]
#              [--full-hunt yes|no] [--hunks-since-full N] [--kind hunt|confirmation]
#       Same record, numbers given by hand (a run with no report file).
#   log_run.sh --last            # head SHA of the newest record for this repo + branch
#   log_run.sh --last --any      # ... for this repo, any branch
#   log_run.sh --rounds          # number of records for this repo + branch
#   log_run.sh --path            # print the log path and exit
#
# Log path: $SHRIKE_LOG, else ${XDG_STATE_HOME:-$HOME/.local/state}/shrike/runs.jsonl.
#
# Exit status: 0 recorded, or already recorded (same repo, branch, head and numbers as
# the previous record — a re-post of an unchanged report). 1 not recorded: candidates,
# killed or reported is unknown, or the line failed JSON validation. Anything that
# depends on the record (post_report.sh) stops on 1.
#
# Record fields, fixed order, one object per line:
#   ts repo branch pr target head base range prev_head files hunks secs round
#   kind hunts_in_chain full_hunt hunks_since_full
#   candidates killed reported severity{critical,high,medium}
#   sweeps{post_await,presence,effect_order,second_site,normalisation,parity,tests_run,tests_red}
#   unreviewed note

set -uo pipefail

STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
LOG="${SHRIKE_LOG:-$STATE_HOME/shrike/runs.jsonl}"

PR=""; TARGET=""; BASE=""; CAND=""; KILLED=""; REPORTED=""
FINDINGS=""; SWEEPS=""; UNREVIEWED=""; NOTE=""; REPORT=""; ROUND=""
FULL=""; HSF=""; KIND=""
MODE="append"; SCOPE="branch"

while [ $# -gt 0 ]; do
  case "$1" in
    --report)      REPORT="${2:-}"; shift 2 ;;
    --pr)          PR="${2:-}"; shift 2 ;;
    --target)      TARGET="${2:-}"; shift 2 ;;
    --base)        BASE="${2:-}"; shift 2 ;;
    --round)       ROUND="${2:-}"; shift 2 ;;
    --full-hunt)   FULL="${2:-}"; shift 2 ;;
    --hunks-since-full) HSF="${2:-}"; shift 2 ;;
    --kind)        KIND="${2:-}"; shift 2 ;;
    --candidates)  CAND="${2:-}"; shift 2 ;;
    --killed)      KILLED="${2:-}"; shift 2 ;;
    --reported)    REPORTED="${2:-}"; shift 2 ;;
    --findings)    FINDINGS="${2:-}"; shift 2 ;;
    --sweeps)      SWEEPS="${2:-}"; shift 2 ;;
    --unreviewed)  UNREVIEWED="${2:-}"; shift 2 ;;
    --note)        NOTE="${2:-}"; shift 2 ;;
    --last)        MODE="last"; shift ;;
    --rounds)      MODE="rounds"; shift ;;
    --path)        MODE="path"; shift ;;
    --any)         SCOPE="any"; shift ;;
    -h|--help)     sed -n '2,40p' "$0"; exit 0 ;;
    *)             echo "log_run.sh: unknown argument $1" >&2; shift ;;
  esac
done

[ "$MODE" = "path" ] && { echo "$LOG"; exit 0; }

# --- identity: which repo, which branch --------------------------------------
# Two worktrees of one repo share a remote and must share a repo key, so the key is
# the remote's owner/name, not the checkout path.
repo_key() {
  [ -n "${SHRIKE_REPO:-}" ] && { echo "$SHRIKE_REPO"; return; }
  local url
  url=$(git remote get-url origin 2>/dev/null || git remote get-url "$(git remote 2>/dev/null | head -1)" 2>/dev/null)
  if [ -n "$url" ]; then
    printf '%s\n' "$url" \
      | sed -E 's#/+$##; s#\.git$##; s#^[a-zA-Z0-9+.-]+://[^/]+/##; s#^[^@/]+@[^:/]+:##'
    return
  fi
  basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
}
REPO=$(repo_key)
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")

# --- JSON helpers (no jq needed to write; jq validates when present) -----------
esc() {  # JSON string escape, output without the surrounding quotes
  printf '%s' "$1" | tr '\n\r\t' '   ' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}
num() {  # JSON number or null
  case "${1:-}" in
    ''|*[!0-9]*) printf 'null' ;;
    *)           printf '%s' "$1" ;;
  esac
}
str() { printf '"%s"' "$(esc "$1")"; }
bool() {  # JSON true/false, or null when neither was stated
  case "$(printf '%s' "${1:-}" | tr 'A-Z' 'a-z')" in
    yes|true|y|1)  printf 'true' ;;
    no|false|n|0)  printf 'false' ;;
    *)             printf 'null' ;;
  esac
}
opt() { [ -n "${1:-}" ] && str "$1" || printf 'null'; }

# Match records of this repo (and branch) without depending on jq. The writer below
# emits a fixed field order, so these substrings are exact.
K_REPO="\"repo\":\"$(esc "$REPO")\""
K_BRANCH="\"branch\":\"$(esc "$BRANCH")\""
records() {
  [ -r "$LOG" ] || return 0
  if [ "$SCOPE" = "any" ]; then grep -F -- "$K_REPO" "$LOG"
  else grep -F -- "$K_REPO" "$LOG" | grep -F -- "$K_BRANCH"; fi
}

# --- --last / --rounds: what the previous report covered, for Phase 7 ---------
if [ "$MODE" = "last" ]; then
  records | tail -1 | sed -n 's/.*"head":"\([0-9a-f]\{7,40\}\)".*/\1/p'
  exit 0
fi
if [ "$MODE" = "rounds" ]; then
  records | wc -l | tr -d ' '
  exit 0
fi

# --- numbers from the report header, when a report was given ------------------
# The header rows are fixed by SKILL.md's output format:
#   | **Target** | `PR #142` · `abc1234...def5678` |
#   | **Not reviewed** | ... |
#   | **Sweeps** | post-await 9 · presence 4 · effect-order 2 · second-site 6 · normalisation 3 · parity 2 · tests 2 of 2 reverted red |
#   | **Candidates** | 14 raised → 12 killed in falsification → **2 reported** |
#   | **Findings** | 🔴 0 critical · 🟠 1 high · 🟡 1 medium |
first_num_before() {  # first_num_before <word> <text>
  printf '%s\n' "$2" | grep -oE "[0-9]+ ?(\*\*)?$1" | head -1 | grep -oE '^[0-9]+'
}
row_cell() {  # row_cell <RowLabel> <file>  → the second cell of that table row
  grep -E "^\| *\*\*$1\*\* *\|" "$2" | head -1 | sed -E 's/^\| *\*\*[^*]+\*\* *\| *//; s/ *\|? *$//'
}
S_POST=""; S_PRES=""; S_EFF=""; S_SITE=""; S_NORM=""; S_PAR=""; S_TRUN=""; S_TRED=""
SEV_C=""; SEV_H=""; SEV_M=""
if [ -n "$REPORT" ]; then
  if [ ! -r "$REPORT" ]; then
    echo "log_run.sh: cannot read report $REPORT" >&2; exit 1
  fi
  CROW=$(row_cell "Candidates" "$REPORT")
  [ -n "$CAND" ]     || CAND=$(first_num_before raised "$CROW")
  [ -n "$KILLED" ]   || KILLED=$(first_num_before killed "$CROW")
  [ -n "$REPORTED" ] || REPORTED=$(first_num_before reported "$CROW")
  FROW=$(row_cell "Findings" "$REPORT")
  [ -n "$FINDINGS" ] || FINDINGS="$FROW"
  SROW=$(row_cell "Sweeps" "$REPORT")
  [ -n "$SWEEPS" ] || SWEEPS="$SROW"
  [ -n "$UNREVIEWED" ] || UNREVIEWED=$(row_cell "Not reviewed" "$REPORT")
  RROW=$(row_cell "Reviewed" "$REPORT")
  [ -n "$FULL" ] || FULL=$(printf '%s\n' "$RROW" | grep -oiE 'full re-read: ?(yes|no)' | head -1 | grep -oiE '(yes|no)$')
  [ -n "$HSF" ]  || HSF=$(printf '%s\n' "$RROW" | grep -oE '[0-9]+ since last full hunt' | head -1 | grep -oE '^[0-9]+')
  [ -n "$KIND" ] || KIND=$(printf '%s\n' "$RROW" | grep -oiE 'kind: ?(hunt|confirmation)' | head -1 | grep -oiE '(hunt|confirmation)$')
  TROW=$(row_cell "Target" "$REPORT")
  [ -n "$PR" ] || PR=$(printf '%s\n' "$TROW" | grep -oE 'PR #[0-9]+' | head -1 | tr -dc '0-9')
  [ -n "$TARGET" ] || TARGET=$(printf '%s\n' "$TROW" | sed -E 's/^`([^`]*)`.*/\1/')
fi
SEV_C=$(first_num_before critical "$FINDINGS")
SEV_H=$(first_num_before high "$FINDINGS")
SEV_M=$(first_num_before medium "$FINDINGS")
sweep_n() { printf '%s\n' "$2" | grep -oE "$1 [0-9]+" | head -1 | grep -oE '[0-9]+$'; }
S_POST=$(sweep_n 'post-await' "$SWEEPS")
S_PRES=$(sweep_n 'presence' "$SWEEPS")
S_EFF=$(sweep_n 'effect-order' "$SWEEPS")
S_SITE=$(sweep_n 'second-site' "$SWEEPS")
S_NORM=$(sweep_n 'normalisation' "$SWEEPS")
S_PAR=$(sweep_n 'parity' "$SWEEPS")
S_TRED=$(printf '%s\n' "$SWEEPS" | grep -oE 'tests [0-9]+' | head -1 | grep -oE '[0-9]+$')
S_TRUN=$(printf '%s\n' "$SWEEPS" | grep -oE 'tests [0-9]+ (of|/) ?[0-9]+' | head -1 | grep -oE '[0-9]+$')

# The gate. A record without these three is a note, not a record.
MISSING=""
case "$CAND"     in ''|*[!0-9]*) MISSING="$MISSING --candidates" ;; esac
case "$KILLED"   in ''|*[!0-9]*) MISSING="$MISSING --killed" ;; esac
case "$REPORTED" in ''|*[!0-9]*) MISSING="$MISSING --reported" ;; esac
if [ -n "$MISSING" ]; then
  echo "log_run.sh: not recorded — unknown:$MISSING. Pass them, or give --report with a" >&2
  echo "run header whose Candidates row reads 'N raised → N killed … → **N reported**'." >&2
  exit 1
fi

# --- diff scope --------------------------------------------------------------
HEAD_SHA=$(git rev-parse HEAD 2>/dev/null || echo "")
SHORT_HEAD=$(git rev-parse --short HEAD 2>/dev/null || echo "?")
if [ -z "$BASE" ]; then
  BASE=$(git merge-base HEAD main 2>/dev/null || git merge-base HEAD master 2>/dev/null || echo "")
fi
BASE_SHA=""; FILES=""; HUNKS=""; RANGE=""
if [ -n "$BASE" ]; then
  BASE_SHA=$(git rev-parse "$BASE" 2>/dev/null || echo "")
  RANGE="$(git rev-parse --short "$BASE" 2>/dev/null || echo "$BASE")...$SHORT_HEAD"
  FILES=$( { git diff --name-only "$BASE"...HEAD 2>/dev/null; git diff --name-only 2>/dev/null; } \
           | sort -u | sed '/^$/d' | wc -l | tr -d ' ' )
  HUNKS=$( { git diff -U0 "$BASE"...HEAD 2>/dev/null; git diff -U0 2>/dev/null; } \
           | grep '^@@' | wc -l | tr -d ' ' )
fi

# The head the previous round on this branch covered — round N hunts prev_head..HEAD.
PREV_HEAD=$(records | tail -1 | sed -n 's/.*"head":"\([0-9a-f]\{7,40\}\)".*/\1/p')
[ -n "$ROUND" ] || ROUND=$(( $(records | wc -l | tr -d ' ') + 1 ))

# A confirmation round verifies the previous hunt's fixes and does not spend the round
# budget; `hunts_in_chain` is what SHRIKE_MAX_ROUNDS is measured against. A record
# written before this field existed was a hunt, so absence counts as one.
case "$(printf '%s' "$KIND" | tr 'A-Z' 'a-z')" in
  confirmation) KIND="confirmation" ;;
  hunt)         KIND="hunt" ;;
  *)            KIND="" ;;
esac
PRIOR_HUNTS=$(records | grep -vc '"kind":"confirmation"' || true)
case "$PRIOR_HUNTS" in ''|*[!0-9]*) PRIOR_HUNTS=0 ;; esac
if [ "$KIND" = "confirmation" ]; then HUNTS="$PRIOR_HUNTS"; else HUNTS=$((PRIOR_HUNTS + 1)); fi

# --- elapsed, from the Phase 0 stamp ----------------------------------------
STAMP="${SHRIKE_START_FILE:-/tmp/shrike-start}"
SECS=""
if [ -r "$STAMP" ]; then
  START=$(tr -dc '0-9' < "$STAMP" 2>/dev/null)
  NOW=$(date +%s)
  if [ -n "$START" ] && [ "$START" -gt 0 ] 2>/dev/null && [ "$NOW" -ge "$START" ]; then
    SECS=$((NOW - START))
    # A stamp older than a day is a leftover from an earlier session, not this run.
    [ "$SECS" -gt 86400 ] && SECS=""
  fi
fi

[ -n "$TARGET" ] || TARGET=$([ -n "$PR" ] && echo "PR #$PR" || echo "$BRANCH")

# --- the record --------------------------------------------------------------
LINE=$(printf '{"ts":%s,"repo":%s,"branch":%s,"pr":%s,"target":%s,"head":%s,"base":%s,"range":%s,"prev_head":%s,"files":%s,"hunks":%s,"secs":%s,"round":%s,"kind":%s,"hunts_in_chain":%s,"full_hunt":%s,"hunks_since_full":%s,"candidates":%s,"killed":%s,"reported":%s,"severity":{"critical":%s,"high":%s,"medium":%s},"sweeps":{"post_await":%s,"presence":%s,"effect_order":%s,"second_site":%s,"normalisation":%s,"parity":%s,"tests_run":%s,"tests_red":%s},"unreviewed":%s,"note":%s}' \
  "$(str "$(date -u +%Y-%m-%dT%H:%M:%SZ)")" "$(str "$REPO")" "$(str "$BRANCH")" \
  "$(num "$PR")" "$(str "$TARGET")" "$(opt "$HEAD_SHA")" "$(opt "$BASE_SHA")" \
  "$(opt "$RANGE")" "$(opt "$PREV_HEAD")" "$(num "$FILES")" "$(num "$HUNKS")" \
  "$(num "$SECS")" "$(num "$ROUND")" "$(opt "$KIND")" "$(num "$HUNTS")" "$(bool "$FULL")" "$(num "$HSF")" "$(num "$CAND")" "$(num "$KILLED")" "$(num "$REPORTED")" \
  "$(num "$SEV_C")" "$(num "$SEV_H")" "$(num "$SEV_M")" \
  "$(num "$S_POST")" "$(num "$S_PRES")" "$(num "$S_EFF")" "$(num "$S_SITE")" "$(num "$S_NORM")" "$(num "$S_PAR")" \
  "$(num "$S_TRUN")" "$(num "$S_TRED")" \
  "$(opt "$UNREVIEWED")" "$(opt "$NOTE")")

if command -v jq >/dev/null 2>&1; then
  if ! printf '%s\n' "$LINE" | jq -e . >/dev/null 2>&1; then
    echo "log_run.sh: not recorded — the record is not valid JSON:" >&2
    printf '%s\n' "$LINE" >&2
    exit 1
  fi
fi

# A re-post of an unchanged report is not a second run.
LAST_LINE=$(records | tail -1)
if [ -n "$LAST_LINE" ] && [ -n "$HEAD_SHA" ] \
   && printf '%s' "$LAST_LINE" | grep -qF -- "\"head\":\"$HEAD_SHA\"" \
   && printf '%s' "$LAST_LINE" | grep -qF -- "\"candidates\":$CAND,\"killed\":$KILLED,\"reported\":$REPORTED,"; then
  echo "already recorded $SHORT_HEAD ($REPO $BRANCH, round $((ROUND - 1))) → $LOG"
  exit 0
fi

mkdir -p "$(dirname "$LOG")" 2>/dev/null || { echo "log_run.sh: cannot create $(dirname "$LOG")" >&2; exit 1; }
printf '%s\n' "$LINE" >> "$LOG" || { echo "log_run.sh: cannot write $LOG" >&2; exit 1; }
echo "logged $SHORT_HEAD ($REPO $BRANCH, round $ROUND) → $LOG"
