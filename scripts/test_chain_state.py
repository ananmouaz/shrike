"""Behavior checks for the full-re-read trigger; uses isolated, temporary Git repos."""

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "skills/shrike/scripts/chain_state.py"
REPO_KEY = "synthetic/chain"


class ChainStateTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.repo = self.root / "repo"
        self.repo.mkdir()
        self.log = self.root / "runs.jsonl"
        self.git("init", "-q")
        self.git("config", "user.email", "test@example.invalid")
        self.git("config", "user.name", "Chain test")
        self.code = self.repo / "code.txt"
        self.lines = [f"line {n}\n" for n in range(1, 101)]
        self.code.write_text("".join(self.lines))
        self.git("add", ".")
        self.git("commit", "-qm", "base")
        self.branch = self.git("rev-parse", "--abbrev-ref", "HEAD")

    def git(self, *args):
        return subprocess.check_output(["git", *args], cwd=self.repo).decode().strip()

    def edit(self, *line_numbers):
        """Rewrite isolated lines. Spaced apart, so each one is its own -U0 hunk."""
        for n in line_numbers:
            self.lines[n - 1] = f"line {n} edited\n"
        self.code.write_text("".join(self.lines))

    def commit(self, message):
        self.git("add", "-A")
        self.git("commit", "-qm", message)
        return self.git("rev-parse", "HEAD")

    def record(self, **fields):
        row = {"repo": REPO_KEY, "branch": self.branch, "head": self.git("rev-parse", "HEAD")}
        row.update(fields)
        with self.log.open("a") as handle:
            handle.write(json.dumps(row) + "\n")

    def state(self, *args):
        result = subprocess.run(
            [sys.executable, str(SCRIPT), "--log", str(self.log), "--repo", REPO_KEY, *args],
            cwd=self.repo, text=True, capture_output=True,
        )
        self.assertIn(result.returncode, (0, 2), result.stderr)
        return json.loads(result.stdout), result.returncode

    def round_one(self):
        """Round 1: twenty isolated hunks against base, hunted in full."""
        self.edit(*range(1, 100, 5))
        self.commit("round 1 target")
        self.record(round=1, full_hunt=True, hunks=20, hunks_since_full=0)

    def test_drift_past_a_fifth_of_the_target_demands_a_full_re_read(self):
        self.round_one()
        self.edit(3, 13, 23)
        self.commit("round 2 fix")
        self.record(round=2, full_hunt=False)
        self.edit(33, 43)
        self.commit("round 3 fix")
        self.record(round=3, full_hunt=False)

        state, code = self.state("--gate")
        self.assertEqual(state["hunks_since_full"], 5)
        self.assertEqual(state["target_hunks"], 20)
        self.assertEqual(state["drift_pct"], 25.0)
        self.assertEqual(state["rounds_since_full"], 2)
        self.assertTrue(state["full_hunt_required"])
        self.assertIn("25.0%", state["reason"])
        self.assertEqual(code, 2)

    def test_small_drift_and_few_rounds_still_allow_a_delta_hunt(self):
        self.round_one()
        self.edit(3)
        self.commit("round 2 fix")
        self.record(round=2, full_hunt=False)

        state, code = self.state("--gate")
        self.assertEqual(state["hunks_since_full"], 1)
        self.assertEqual(state["drift_pct"], 5.0)
        self.assertFalse(state["full_hunt_required"])
        self.assertEqual(code, 0)

    def test_three_rounds_since_the_last_full_hunt_demand_one_on_their_own(self):
        self.round_one()
        for n in (2, 3, 4):
            self.record(round=n, full_hunt=False)  # no source change at all

        state, _ = self.state()
        self.assertEqual(state["hunks_since_full"], 0)
        self.assertEqual(state["rounds_since_full"], 3)
        self.assertTrue(state["full_hunt_required"])
        self.assertIn("3 hunts since the last full hunt", state["reason"])

    def test_confirmation_rounds_do_not_age_the_chain(self):
        self.round_one()
        for n in (2, 3, 4, 5):
            self.record(round=n, kind="confirmation", full_hunt=False)
        state, _ = self.state()
        self.assertEqual(state["rounds_since_full"], 0)
        self.assertFalse(state["full_hunt_required"])

        self.record(round=6, kind="hunt", full_hunt=False)
        self.record(round=7, kind="hunt", full_hunt=False)
        self.record(round=8, kind="hunt", full_hunt=False)
        state, _ = self.state()
        self.assertEqual(state["rounds_since_full"], 3)
        self.assertTrue(state["full_hunt_required"])
        self.assertIn("3 hunts since the last full hunt", state["reason"])

    def test_uncommitted_edits_count_toward_the_drift(self):
        self.round_one()
        self.record(round=2, full_hunt=False)
        self.edit(3, 13, 23, 33, 43)  # left in the working tree, never committed

        state, _ = self.state()
        self.assertEqual(state["hunks_since_full"], 5)
        self.assertTrue(state["full_hunt_required"])

    def test_a_later_full_hunt_resets_the_drift(self):
        self.round_one()
        self.edit(3, 13, 23, 33, 43)
        self.commit("round 2 fix")
        self.record(round=2, full_hunt=True, hunks=20)

        state, _ = self.state()
        self.assertEqual(state["rounds_since_full"], 0)
        self.assertEqual(state["hunks_since_full"], 0)
        self.assertFalse(state["full_hunt_required"])

    def test_records_without_the_field_anchor_on_the_first_round(self):
        """Old records predate full_hunt. They never anchor; round 1 does, by definition."""
        self.edit(*range(1, 100, 5))
        self.commit("round 1 target")
        self.record(round=1, hunks=20)
        self.edit(3, 13, 23, 33, 43)
        self.commit("round 2 fix")
        self.record(round=2)

        state, _ = self.state()
        self.assertTrue(state.get("anchor_inferred"))
        self.assertEqual(state["hunks_since_full"], 5)
        self.assertTrue(state["full_hunt_required"])
        self.assertIn("first record", state["reason"])

    def test_another_branch_is_a_different_chain(self):
        self.round_one()
        self.git("checkout", "-qb", "other")
        self.branch = "other"
        state, _ = self.state()
        self.assertEqual(state["rounds_since_full"], 0)
        self.assertIsNone(state["target_hunks"])
        self.assertIn("round 1", state["reason"])

    def test_unreadable_and_malformed_records_do_not_crash_the_helper(self):
        self.log.write_text("not json\n\n")
        state, _ = self.state()
        self.assertTrue(state["full_hunt_required"])
        self.assertIn("no record", state["reason"])


if __name__ == "__main__":
    unittest.main()
