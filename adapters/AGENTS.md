# AGENTS.md — bug review section

Append this to the `AGENTS.md` at the root of the repo you want reviewed. Codex reads
`AGENTS.md` automatically; several other agents have adopted the same convention.

Because `AGENTS.md` is always-loaded context rather than on-demand, keep the entry
**thin** — a pointer plus the non-negotiables. Putting the full workflow here would
burn context on every unrelated task.

---

## Bug review

When asked to review a PR, review a diff, check a branch before merge, find bugs,
check for regressions, or answer "did I break anything" / "is this safe to merge":

**Read `.agents/shrike.prompt.md` and follow it exactly.** Do not improvise a code
review instead. Do not skip Phase 4 (falsification) — it is the phase that makes the
output worth reading.

Non-negotiables, restated here so they survive even if the file isn't read:

- **Correctness bugs only.** No style, naming, formatting, refactoring suggestions,
  documentation notes, test-coverage opinions, or "consider" comments. Ever.
- **Every finding needs a concrete failure scenario:** a specific trigger, the path
  through the code, and an observable wrong outcome. No hedging. If you'd write
  "might" or "could potentially", delete the finding instead.
- **Zero findings is a valid and common result.** Say so plainly and stop. Do not pad
  the report to look productive.
- **Cap at 5 findings**, ranked by severity.
- Anything the compiler or linter already reports is theirs, not yours. Don't restate it.

Project invariants and dismissed false positives live in `review-rules.md` at the repo
root. Read it before reporting.
