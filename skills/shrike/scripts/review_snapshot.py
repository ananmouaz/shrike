#!/usr/bin/env python3
"""Save reusable Git evidence, not a review verdict. Prints the bundle directory.

Run from the target worktree with --base REF. Repeat with identical arguments
before recording a review: the directory must match. --dependency FILE adds
ignored/external inputs (e.g. installed provider source or review instructions).
Requires Python 3.9+ and Git. No checkout/index mutations, no external commands
from Git diff drivers. Submodules and unresolved merges require manual evidence.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile


def digest(data):
    return hashlib.sha256(data).hexdigest()


def encoded(value):
    return (json.dumps(value, sort_keys=True, ensure_ascii=True, indent=2) + "\n").encode()


def git(*args):
    return subprocess.run(
        ["git", "--no-optional-locks", *args], check=True, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    ).stdout


def file_identity(path):
    mode = path.lstat().st_mode
    if stat.S_ISLNK(mode):
        return {"kind": "symlink", "target": os.readlink(path)}
    if not stat.S_ISREG(mode):
        raise ValueError(f"not a regular file: {path}")
    with path.open("rb") as source:
        h = hashlib.sha256()
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            h.update(chunk)
    return {"kind": "file", "sha256": h.hexdigest(), "executable": bool(mode & 0o111)}


def collect(base_ref, dependencies):
    root = Path(os.fsdecode(git("rev-parse", "--show-toplevel")).removesuffix("\n")).resolve()
    head = git("rev-parse", "HEAD").decode().strip()
    base_tip = git("rev-parse", "--verify", base_ref + "^{commit}").decode().strip()
    base = git("merge-base", head, base_tip).decode().strip()
    index = git("ls-files", "--stage", "-z")
    for entry in git("ls-files", "-v", "-z").split(b"\0"):
        if entry and (entry[:1].islower() or entry[:1] == b"S"):
            raise ValueError("assume-unchanged or skip-worktree entry: use manual evidence")
    for entry in index.split(b"\0"):
        if not entry:
            continue
        mode, _, stage = entry.split(b"\t", 1)[0].split()
        if mode == b"160000" or stage != b"0":
            raise ValueError("submodule or unresolved merge: use manual evidence; no cache clearance")
    diff = ("diff", "--no-ext-diff", "--no-textconv", "--binary", "--no-renames")
    artifacts = {
        "committed.diff": git(*diff, base, head, "--"),
        "staged.diff": git(*diff, "--cached", head, "--"),
        "unstaged.diff": git(*diff, "--"),
    }
    untracked = {}
    for name in git("ls-files", "--others", "--exclude-standard", "-z").split(b"\0"):
        if name:
            path = os.fsdecode(name)
            untracked[path] = file_identity(root / path)
    # External symlink targets must be named too: hashing the link alone is not
    # evidence for the provider implementation it points at.
    extra = {str(path): file_identity(path) for path in dependencies}
    state = {
        "version": 1, "worktree": str(root), "head": head, "base_ref": base_ref,
        "base_tip": base_tip, "merge_base": base, "index_sha256": digest(index),
        "artifacts": {name: digest(data) for name, data in artifacts.items()},
        "untracked": untracked, "dependencies": extra,
    }
    return state, artifacts


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", required=True)
    parser.add_argument("--dependency", action="append", default=[], type=Path)
    parser.add_argument("--cache-dir", type=Path, default=Path(
        os.environ.get("XDG_CACHE_HOME", str(Path.home() / ".cache"))) / "shrike" / "evidence")
    args = parser.parse_args()
    # Resolve dependencies before moving from a subdirectory to the repo root.
    dependencies = sorted({path.absolute() for path in args.dependency})
    cache = args.cache_dir.resolve()
    root = Path(os.fsdecode(git("rev-parse", "--show-toplevel")).removesuffix("\n")).resolve()
    if cache == root or root in cache.parents:
        raise ValueError("cache must be outside the reviewed worktree")
    os.chdir(root)
    state, artifacts = collect(args.base, dependencies)
    if collect(args.base, dependencies)[0] != state:
        raise ValueError("inputs changed during capture; wait for edits to finish and retry")
    manifest = encoded(state)
    bundle = cache / digest(manifest)
    files = {**artifacts, "manifest.json": manifest}
    cache.mkdir(parents=True, exist_ok=True, mode=0o700)
    if not bundle.exists():
        with tempfile.TemporaryDirectory(prefix=".capture-", dir=cache) as tmp:
            for name, data in files.items():
                (Path(tmp) / name).write_bytes(data)
            try:
                os.rename(tmp, bundle)
            except OSError:
                if not bundle.is_dir():
                    raise
    # Detect incomplete or edited cache entries rather than silently trusting them.
    if any((bundle / name).read_bytes() != data for name, data in files.items()):
        raise ValueError(f"cached evidence was modified: {bundle}")
    print(bundle)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"review_snapshot: {error}", file=sys.stderr)
        sys.exit(1)
