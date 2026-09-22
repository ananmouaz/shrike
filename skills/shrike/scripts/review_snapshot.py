#!/usr/bin/env python3
"""Save reusable Git evidence, not a review verdict. Prints the bundle directory.

Run from the target worktree with --base REF. Repeat with identical arguments
before recording a review: the directory must match. --dependency FILE adds
ignored/external inputs (e.g. installed provider source or review instructions).
Requires Python 3.9+ and Git. No checkout/index mutations, no external commands
from Git diff drivers. Submodules and unresolved merges require manual evidence.

--pin DIR builds a detached worktree at HEAD in DIR and replays the captured
staged, unstaged and untracked contents on top, so the hunt reads a tree that
cannot move under it. It prints the pinned path on stdout and the bundle path on
stderr. The author commits while the hunt runs; without a pin, the recapture at
the end no longer matches and the whole round is voided after it has paid for its
checks. Hunt in the pinned tree; recapture the ORIGINAL worktree, without --pin,
only at the end, and report the drift rather than discarding the round.
The pin also clones the author's gitignored build caches (SHRIKE_WARM_DIRS,
default ".dart_tool node_modules .venv target") so its first test run is warm
instead of paying a dependency fetch and a cold compile.
--unpin DIR removes that worktree.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
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


def read_untracked(path):
    """Identity plus bytes. The bundle stores the bytes so a pin can replay them."""
    mode = path.lstat().st_mode
    if stat.S_ISLNK(mode):
        return {"kind": "symlink", "target": os.readlink(path)}, None
    if not stat.S_ISREG(mode):
        raise ValueError(f"not a regular file: {path}")
    data = path.read_bytes()
    return ({"kind": "file", "sha256": digest(data), "executable": bool(mode & 0o111)}, data)


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
    blobs = {}
    for name in git("ls-files", "--others", "--exclude-standard", "-z").split(b"\0"):
        if name:
            path = os.fsdecode(name)
            untracked[path], data = read_untracked(root / path)
            if data is not None:
                blobs[untracked[path]["sha256"]] = data
    # External symlink targets must be named too: hashing the link alone is not
    # evidence for the provider implementation it points at.
    extra = {str(path): file_identity(path) for path in dependencies}
    state = {
        "version": 2, "worktree": str(root), "head": head, "base_ref": base_ref,
        "base_tip": base_tip, "merge_base": base, "index_sha256": digest(index),
        "artifacts": {name: digest(data) for name, data in artifacts.items()},
        "untracked": untracked, "dependencies": extra,
    }
    return state, artifacts, blobs


def pin(root, target, state, bundle):
    """A detached worktree at HEAD with the captured dirty state replayed on top.

    The pinned tree is what the hunt reads. It is a checkout, not the reviewed
    worktree, so the author can commit, rebase or stash without voiding the round.
    """
    if target.exists() and any(target.iterdir()):
        raise ValueError(f"pin directory is not empty: {target}")
    if target == root or root in target.parents or target in root.parents:
        raise ValueError("pin directory must be outside the reviewed worktree")
    git("worktree", "add", "--detach", str(target), state["head"])
    # staged.diff is index-vs-HEAD and unstaged.diff is worktree-vs-index, so this
    # order rebuilds the captured tree; either may legitimately be empty.
    for name in ("staged.diff", "unstaged.diff"):
        patch = bundle / name
        if patch.stat().st_size:
            git("-C", str(target), "apply", "--binary", "--whitespace=nowarn", str(patch))
    for path, identity in state["untracked"].items():
        destination = (target / path)
        if target not in destination.resolve().parents:
            raise ValueError(f"untracked path escapes the pin directory: {path}")
        destination.parent.mkdir(parents=True, exist_ok=True)
        if identity["kind"] == "symlink":
            destination.symlink_to(identity["target"])
            continue
        destination.write_bytes((bundle / "untracked" / identity["sha256"]).read_bytes())
        if identity["executable"]:
            destination.chmod(destination.stat().st_mode | 0o111)
    warm(root, target)
    return target


WARM_DIRS = set(os.environ.get("SHRIKE_WARM_DIRS", ".dart_tool node_modules .venv target").split())


def clone(source, destination):
    """Copy a directory, sharing blocks where the filesystem can (APFS, btrfs, xfs).

    A copy, never a hard link: a compiler rewriting a cache file in place inside
    the pin would otherwise edit the author's tree through the shared inode.
    """
    flags = ["-Rc"] if sys.platform == "darwin" else ["-R", "--reflink=auto"]
    try:
        subprocess.run(["cp", *flags, str(source), str(destination)], check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except (OSError, subprocess.CalledProcessError):
        shutil.rmtree(destination, ignore_errors=True)
        shutil.copytree(source, destination, symlinks=True, copy_function=shutil.copyfile)


def warm(root, target):
    """Clone the reviewed tree's ignored build caches into the pin.

    `worktree add` leaves ignored directories behind, so a bare pin pays `pub get`
    plus a cold compile (about 80 seconds on a Flutter project) before its first
    test runs. Every match is an ignored directory, so nothing tracked is duplicated.
    """
    if not WARM_DIRS:
        return
    listing = git("ls-files", "--others", "--ignored", "--exclude-standard", "--directory", "-z")
    for entry in listing.split(b"\0"):
        relative = os.fsdecode(entry).rstrip("/")
        if not relative or Path(relative).name not in WARM_DIRS:
            continue
        source, destination = root / relative, target / relative
        if source.is_symlink() or not source.is_dir() or destination.exists():
            continue
        destination.parent.mkdir(parents=True, exist_ok=True)
        clone(source, destination)
        # The copy must read as newer than the fresh checkout beside it, or the
        # tool's own staleness check (pub compares package_config.json against
        # pubspec.lock) discards the cache it was given.
        for directory, _, names in os.walk(destination):
            for name in names:
                try:
                    os.utime(os.path.join(directory, name), None, follow_symlinks=False)
                except OSError:
                    pass


def unpin(target):
    git("worktree", "remove", "--force", str(target))
    git("worktree", "prune")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base")
    parser.add_argument("--dependency", action="append", default=[], type=Path)
    parser.add_argument("--cache-dir", type=Path, default=Path(
        os.environ.get("XDG_CACHE_HOME", str(Path.home() / ".cache"))) / "shrike" / "evidence")
    parser.add_argument("--pin", type=Path, help="build a fixed worktree here and print its path")
    parser.add_argument("--unpin", type=Path, help="remove the worktree at this path and exit")
    args = parser.parse_args()
    # Resolve paths before moving from a subdirectory to the repo root.
    dependencies = sorted({path.absolute() for path in args.dependency})
    # resolve(), not absolute(): the repo root is resolved, and on macOS /var is a
    # symlink to /private/var, so an unresolved pin path never compares equal to it.
    pin_at = args.pin.resolve() if args.pin else None
    unpin_at = args.unpin.resolve() if args.unpin else None
    cache = args.cache_dir.resolve()
    root = Path(os.fsdecode(git("rev-parse", "--show-toplevel")).removesuffix("\n")).resolve()
    os.chdir(root)
    if unpin_at:
        unpin(unpin_at)
        return
    if args.base is None:
        raise ValueError("--base is required unless --unpin is given")
    if cache == root or root in cache.parents:
        raise ValueError("cache must be outside the reviewed worktree")
    state, artifacts, blobs = collect(args.base, dependencies)
    if collect(args.base, dependencies)[0] != state:
        raise ValueError("inputs changed during capture; wait for edits to finish and retry")
    manifest = encoded(state)
    bundle = cache / digest(manifest)
    files = {**artifacts, "manifest.json": manifest,
             **{f"untracked/{name}": data for name, data in blobs.items()}}
    cache.mkdir(parents=True, exist_ok=True, mode=0o700)
    if not bundle.exists():
        with tempfile.TemporaryDirectory(prefix=".capture-", dir=cache) as tmp:
            for name, data in files.items():
                path = Path(tmp) / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(data)
            try:
                os.rename(tmp, bundle)
            except OSError:
                if not bundle.is_dir():
                    raise
    # Detect incomplete or edited cache entries rather than silently trusting them.
    if any((bundle / name).read_bytes() != data for name, data in files.items()):
        raise ValueError(f"cached evidence was modified: {bundle}")
    if pin_at:
        print(bundle, file=sys.stderr)
        print(pin(root, pin_at, state, bundle))
        return
    print(bundle)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"review_snapshot: {error}", file=sys.stderr)
        sys.exit(1)
