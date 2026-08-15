#!/usr/bin/env bash
# Phase 0: run whatever deterministic analyzers this repo actually has.
# Never fails the run — a missing tool is information, not an error.
# Usage: static_pass.sh [path]   (defaults to current directory)

set -uo pipefail
ROOT="${1:-.}"
cd "$ROOT" || { echo "cannot cd to $ROOT"; exit 0; }

hr() { printf '\n===== %s =====\n' "$1"; }
has() { command -v "$1" >/dev/null 2>&1; }
run() { echo "\$ $*"; "$@" 2>&1 | tail -n 200; echo "[exit ${PIPESTATUS[0]}]"; }

hr "REPO"
echo "root: $(pwd)"
[ -d .git ] && {
  echo "branch: $(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
  echo "--- changed vs merge-base with main/master ---"
  BASE=$(git merge-base HEAD main 2>/dev/null || git merge-base HEAD master 2>/dev/null || echo "")
  if [ -n "$BASE" ]; then
    git diff --stat "$BASE"...HEAD
  else
    git diff --stat HEAD~1 2>/dev/null || echo "(no diff base found)"
  fi
}

# ---------- Dart / Flutter ----------
if [ -f pubspec.yaml ]; then
  hr "DART ANALYZE"
  if has dart; then run dart analyze
  elif has flutter; then run flutter analyze
  else echo "dart/flutter not installed"; fi
fi

# ---------- Node / TypeScript ----------
if [ -f package.json ]; then
  if [ -f tsconfig.json ]; then
    hr "TSC --noEmit"
    if has npx; then run npx --no-install tsc --noEmit; else echo "npx not available"; fi
  fi
  if ls .eslintrc* eslint.config.* >/dev/null 2>&1; then
    hr "ESLINT"
    has npx && run npx --no-install eslint . --max-warnings=0
  fi
  if grep -q '"drizzle-kit"' package.json 2>/dev/null; then
    hr "DRIZZLE-KIT CHECK"
    has npx && run npx --no-install drizzle-kit check
  fi
fi

# ---------- Other ecosystems ----------
[ -f go.mod ]      && { hr "GO VET";      has go     && run go vet ./...; }
[ -f Cargo.toml ]  && { hr "CARGO CHECK"; has cargo  && run cargo check --all-targets; }
if ls pyproject.toml requirements.txt >/dev/null 2>&1; then
  hr "RUFF";  has ruff  && run ruff check .
  hr "MYPY";  has mypy  && run mypy . --ignore-missing-imports
fi

# ---------- Cross-language ----------
if has semgrep; then
  hr "SEMGREP (auto config)"
  run semgrep --config=auto --error --quiet --max-target-bytes 1000000 .
fi

# ---------- Secrets smell test (cheap, high value) ----------
hr "HARDCODED SECRET SMELL"
if has rg; then
  rg -n --hidden --glob '!.git' --glob '!*.lock' \
     -e '(api[_-]?key|secret|password|token|private[_-]?key)\s*[:=]\s*["'"'"'][A-Za-z0-9/+_-]{16,}' \
     . 2>/dev/null | head -n 40 || echo "(none found)"
else
  grep -rEn --exclude-dir=.git --exclude-dir=node_modules \
    '(api[_-]?key|secret|password|token|private[_-]?key)[[:space:]]*[:=][[:space:]]*["'"'"'][A-Za-z0-9/+_-]{16,}' \
    . 2>/dev/null | head -n 40 || echo "(none found)"
fi

hr "DONE"
echo "Reminder: findings above belong to the tools. Do NOT restate them as your own."
echo "Use them only to (a) skip that class of hunting and (b) locate shaky areas."
