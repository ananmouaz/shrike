"""Behavior checks for cached source identity; uses isolated, temporary Git repos."""

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "skills/shrike/scripts/review_snapshot.py"


class SnapshotTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.repo = self.root / "repo"
        self.repo.mkdir()
        self.cache = self.root / "cache"
        self.git("init", "-q")
        self.git("config", "user.email", "test@example.invalid")
        self.git("config", "user.name", "Snapshot test")
        (self.repo / "code.txt").write_text("original\n")
        (self.repo / ".gitignore").write_text("ignored.txt\n")
        self.git("add", ".")
        self.git("commit", "-qm", "base")
        self.git("branch", "base")

    def git(self, *args):
        return subprocess.check_output(["git", *args], cwd=self.repo).decode().strip()

    def run_snapshot(self, *args, ok=True):
        result = subprocess.run(
            [sys.executable, str(SCRIPT), "--base", "base", "--cache-dir", str(self.cache), *args],
            cwd=self.repo, text=True, capture_output=True,
        )
        self.assertEqual(result.returncode, 0 if ok else 1, result.stderr)
        return Path(result.stdout.strip()) if ok else result.stderr

    def test_unchanged_input_reuses_bundle_without_changing_git(self):
        before = self.git("status", "--porcelain")
        first = self.run_snapshot()
        self.assertEqual(first, self.run_snapshot())
        self.assertEqual(before, self.git("status", "--porcelain"))
        self.assertEqual(self.git("rev-parse", "HEAD"), json.loads((first / "manifest.json").read_text())["head"])

    def test_staged_and_unstaged_edits_are_distinct_at_same_head(self):
        clean = self.run_snapshot()
        (self.repo / "code.txt").write_text("changed\n")
        dirty = self.run_snapshot()
        self.git("add", "code.txt")
        staged = self.run_snapshot()
        (self.repo / "code.txt").write_text("second edit\n")
        both = self.run_snapshot()
        self.assertEqual(len({clean, dirty, staged, both}), 4)
        self.assertIn("+changed", (staged / "staged.diff").read_text())
        self.assertIn("+second edit", (both / "unstaged.diff").read_text())

    def test_untracked_contents_names_modes_and_deletions_invalidate(self):
        clean = self.run_snapshot()
        path = self.repo / "new file\nwith newline.txt"
        path.write_text("first")
        first = self.run_snapshot()
        path.write_text("other")  # Same length must still invalidate.
        other = self.run_snapshot()
        path.chmod(0o755)
        executable = self.run_snapshot()
        path.rename(self.repo / "renamed.txt")
        renamed = self.run_snapshot()
        (self.repo / "renamed.txt").unlink()
        self.assertEqual(self.run_snapshot(), clean)
        self.assertEqual(len({clean, first, other, executable, renamed}), 5)

    def test_external_and_ignored_evidence_invalidate(self):
        ignored = self.repo / "ignored.txt"
        external = self.root / "provider.txt"
        ignored.write_text("config")
        external.write_text("provider v1")
        args = ("--dependency", str(ignored), "--dependency", str(external))
        first = self.run_snapshot(*args)
        ignored.write_text("changed config")
        second = self.run_snapshot(*args)
        external.write_text("provider v2")
        self.assertEqual(len({first, second, self.run_snapshot(*args)}), 3)
        external.unlink()
        self.run_snapshot(*args, ok=False)

    def test_head_base_tip_and_worktree_identity_invalidate(self):
        first = self.run_snapshot()
        self.git("commit", "--allow-empty", "-qm", "new head")
        head = self.run_snapshot()
        self.git("branch", "-f", "base", "HEAD")
        base = self.run_snapshot()
        self.assertEqual(len({first, head, base}), 3)
        other_repo = self.root / "other-worktree"
        self.git("worktree", "add", "-q", "--detach", str(other_repo), "HEAD")
        self.repo = other_repo
        self.assertNotEqual(base, self.run_snapshot())

    def test_changed_symlink_target_invalidate(self):
        link = self.repo / "link"
        link.symlink_to("code.txt")
        first = self.run_snapshot()
        link.unlink()
        link.symlink_to("missing.txt")
        self.assertNotEqual(first, self.run_snapshot())

    def test_modified_cached_evidence_is_rejected(self):
        first = self.run_snapshot()
        (first / "committed.diff").write_text("tampered")
        self.assertIn("modified", self.run_snapshot(ok=False))

    def test_output_inside_worktree_is_rejected(self):
        self.cache = self.repo / ".review"
        self.assertIn("outside", self.run_snapshot(ok=False))

    def test_invalid_base_fails_instead_of_empty_diff(self):
        self.run_snapshot("--base", "missing-branch", ok=False)

    def test_hidden_tracked_edits_are_rejected(self):
        for flag in ("assume-unchanged", "skip-worktree"):
            with self.subTest(flag=flag):
                self.git("update-index", "--" + flag, "code.txt")
                self.assertIn("manual evidence", self.run_snapshot(ok=False))
                self.git("update-index", "--no-" + flag, "code.txt")

    # --- pinned worktree -----------------------------------------------------

    def run_pin(self, target, ok=True):
        result = subprocess.run(
            [sys.executable, str(SCRIPT), "--base", "base",
             "--cache-dir", str(self.cache), "--pin", str(target)],
            cwd=self.repo, text=True, capture_output=True,
        )
        self.assertEqual(result.returncode, 0 if ok else 1, result.stderr)
        return Path(result.stdout.strip()) if ok else result.stderr

    def run_unpin(self, target):
        result = subprocess.run(
            [sys.executable, str(SCRIPT), "--cache-dir", str(self.cache), "--unpin", str(target)],
            cwd=self.repo, text=True, capture_output=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    def dirty_tree(self):
        """Staged, unstaged, untracked, executable and symlinked, all at once."""
        (self.repo / "code.txt").write_text("staged\n")
        self.git("add", "code.txt")
        (self.repo / "code.txt").write_text("staged then edited\n")
        (self.repo / "notes.txt").write_text("untracked\n")
        script = self.repo / "run.sh"
        script.write_text("#!/bin/sh\necho hi\n")
        script.chmod(0o755)
        (self.repo / "nested").mkdir()
        (self.repo / "nested" / "deep.txt").write_text("nested untracked\n")
        (self.repo / "link").symlink_to("code.txt")

    def test_pinned_tree_holds_the_captured_state_and_the_original_may_move(self):
        self.dirty_tree()
        pinned = self.run_pin(self.root / "pinned")

        self.assertEqual((pinned / "code.txt").read_text(), "staged then edited\n")
        self.assertEqual((pinned / "notes.txt").read_text(), "untracked\n")
        self.assertEqual((pinned / "nested" / "deep.txt").read_text(), "nested untracked\n")
        self.assertTrue((pinned / "run.sh").stat().st_mode & 0o111)
        self.assertEqual((pinned / "link").readlink(), Path("code.txt"))

        # The author keeps working: commit, rewrite, delete. The pin must not notice.
        (self.repo / "code.txt").write_text("author moved on\n")
        (self.repo / "notes.txt").unlink()
        self.git("add", "-A")
        self.git("commit", "-qm", "author commits mid-hunt")
        self.assertEqual((pinned / "code.txt").read_text(), "staged then edited\n")
        self.assertEqual((pinned / "notes.txt").read_text(), "untracked\n")

    def test_unpin_removes_the_worktree_and_leaves_the_list_clean(self):
        self.dirty_tree()
        target = self.root / "pinned"
        pinned = self.run_pin(target)
        self.assertIn(str(pinned), self.git("worktree", "list"))
        self.run_unpin(target)
        self.assertFalse(target.exists())
        self.assertNotIn(str(pinned), self.git("worktree", "list"))
        self.assertEqual(self.git("worktree", "list").count("\n"), 0)

    def test_pin_refuses_a_nonempty_directory_and_the_worktree_itself(self):
        occupied = self.root / "occupied"
        occupied.mkdir()
        (occupied / "something").write_text("in the way")
        self.assertIn("not empty", self.run_pin(occupied, ok=False))
        self.assertIn("outside", self.run_pin(self.repo / "inside", ok=False))

    def test_gitlink_is_rejected(self):
        self.git("update-index", "--add", "--cacheinfo",
                 "160000," + self.git("rev-parse", "HEAD") + ",submodule")
        self.assertIn("submodule", self.run_snapshot(ok=False))


if __name__ == "__main__":
    unittest.main()
