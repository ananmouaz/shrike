#!/usr/bin/env python3
"""Decide whether the next round of this review chain must be a FULL re-read.

A round after the first hunts `<previous head>..HEAD` and reuses the prior ledger.
That is cheap and it is how a wrong clearance survives: whatever round 1 cleared
wrongly stays cleared for every later round, because no later round ever looks at
it again. This helper bounds that exposure. It reads the run records `log_run.sh`
writes, finds the last FULL hunt of the chain, and reports the drift since it:

  * `hunks_since_full` — hunks changed between that round's head and the current
    tree, working-tree edits included;
  * `rounds_since_full` — records written since it.

A full re-read is required when the drift exceeds `--max-drift-pct` of the hunk
count the last full hunt covered, or when `--max-rounds-since-full` rounds have
passed. A full re-read re-hunts the WHOLE original target with the prior ledger's
verdicts hidden: its coverage rows may be reused to scope the work, never to
answer it.

Usage:
  chain_state.py                 # JSON on stdout, exit 0
  chain_state.py --explain       # one human line instead of JSON
  chain_state.py --gate          # exit 2 when a full re-read is required

Records without `full_hunt` predate this helper. They cannot prove a full hunt
happened, so they never anchor one; the chain's first record does, since round 1
hunts the whole target by definition.
"""

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys


def git(*args, cwd=None):
    result = subprocess.run(
        ["git", "--no-optional-locks", *args], cwd=cwd,
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True,
    )
    return result.stdout.strip() if result.returncode == 0 else ""


def repo_key():
    """The key `log_run.sh` writes: the remote's owner/name, not the checkout path.

    Two worktrees of one repository share a chain, so they must share a key.
    """
    if os.environ.get("SHRIKE_REPO"):
        return os.environ["SHRIKE_REPO"]
    url = git("remote", "get-url", "origin")
    if not url:
        first = git("remote").split("\n")[0]
        url = git("remote", "get-url", first) if first else ""
    if url:
        url = re.sub(r"/+$", "", url)
        url = re.sub(r"\.git$", "", url)
        url = re.sub(r"^[a-zA-Z0-9+.-]+://[^/]+/", "", url)
        url = re.sub(r"^[^@/]+@[^:/]+:", "", url)
        return url
    top = git("rev-parse", "--show-toplevel")
    return Path(top or os.getcwd()).name


def log_path(explicit):
    if explicit:
        return Path(explicit)
    if os.environ.get("SHRIKE_LOG"):
        return Path(os.environ["SHRIKE_LOG"])
    state = os.environ.get("XDG_STATE_HOME") or str(Path.home() / ".local" / "state")
    return Path(state) / "shrike" / "runs.jsonl"


def records(path, repo, branch):
    """Chain records for this repo and branch, oldest first. Unparsable lines are skipped."""
    if not path.is_file():
        return []
    found = []
    for line in path.read_text(errors="replace").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            row = json.loads(line)
        except ValueError:
            continue
        if row.get("repo") == repo and row.get("branch") == branch:
            found.append(row)
    return found


def count_hunks(*ranges):
    """Hunks in each diff, summed. Mirrors log_run.sh: -U0, count the @@ headers."""
    total = 0
    for args in ranges:
        out = git("diff", "-U0", *args)
        total += sum(1 for line in out.split("\n") if line.startswith("@@"))
    return total


def assess(chain, max_drift_pct, max_rounds):
    if not chain:
        return {
            "rounds_since_full": 0, "hunks_since_full": 0, "target_hunks": None,
            "drift_pct": None, "full_hunt_required": True,
            "reason": "no record for this chain — the next round is round 1 and hunts the whole target",
        }

    # The anchor is the last round that re-read everything. A record with no
    # `full_hunt` field predates the flag and cannot prove one, so only the chain's
    # first record anchors by construction.
    anchor_at = 0
    for i, row in enumerate(chain):
        if row.get("full_hunt") is True:
            anchor_at = i
    anchor = chain[anchor_at]
    inferred = anchor.get("full_hunt") is not True

    rounds_since = len(chain) - anchor_at - 1
    head = anchor.get("head")
    if head:
        hunks_since = count_hunks((f"{head}..HEAD",), ("HEAD",))
    else:
        hunks_since = count_hunks(("HEAD",))

    target = anchor.get("hunks")
    target = target if isinstance(target, int) and target > 0 else None
    drift = round(100.0 * hunks_since / target, 1) if target else None

    reasons = []
    if drift is not None and drift > max_drift_pct:
        reasons.append(
            f"{drift}% of the original target's hunks changed since the last full hunt "
            f"({hunks_since} of {target}, limit {max_drift_pct}%)"
        )
    if rounds_since >= max_rounds:
        reasons.append(f"{rounds_since} rounds since the last full hunt (limit {max_rounds})")
    if target is None and hunks_since:
        reasons.append(
            f"the last full hunt recorded no hunk count, so {hunks_since} hunks of drift "
            "cannot be measured against it"
        )

    state = {
        "rounds_since_full": rounds_since,
        "hunks_since_full": hunks_since,
        "target_hunks": target,
        "drift_pct": drift,
        "full_hunt_required": bool(reasons),
        "reason": "; ".join(reasons) or "within both limits — the next round may hunt the delta",
    }
    if inferred:
        state["anchor_inferred"] = True
        state["reason"] += " (anchored on the chain's first record: no round recorded full_hunt)"
    return state


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--log", help="run record file; default $SHRIKE_LOG or the state dir")
    parser.add_argument("--repo", help="override the repo key")
    parser.add_argument("--branch", help="override the branch name")
    parser.add_argument("--max-drift-pct", type=float, default=20.0)
    parser.add_argument("--max-rounds-since-full", type=int, default=3)
    parser.add_argument("--explain", action="store_true", help="one human line instead of JSON")
    parser.add_argument("--gate", action="store_true", help="exit 2 when a full re-read is required")
    args = parser.parse_args()

    repo = args.repo or repo_key()
    branch = args.branch or git("rev-parse", "--abbrev-ref", "HEAD") or "?"
    chain = records(log_path(args.log), repo, branch)
    state = assess(chain, args.max_drift_pct, args.max_rounds_since_full)

    if args.explain:
        verdict = "FULL re-read required" if state["full_hunt_required"] else "delta hunt allowed"
        print(f"{verdict}: {state['reason']}")
    else:
        print(json.dumps(state, indent=2, sort_keys=True))
    if args.gate and state["full_hunt_required"]:
        return 2
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError) as error:
        print(f"chain_state: {error}", file=sys.stderr)
        sys.exit(1)
