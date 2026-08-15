# review-rules.md

Copy this to the **root of a project repo** (not the skills repo). The bug hunter
reads it before writing its report. This is the learning loop that replaces
CodeRabbit's per-org memory — it's the difference between a tool that gets more
accurate over months and one that repeats the same wrong comment forever.

Two kinds of entries.

## Suppressions

Patterns you've dismissed and don't want to see again. Add one every time you reject
a finding, with the reason — the reason matters, because in six months you won't
remember whether it was wrong or just annoying.

```markdown
- Don't flag missing `await` on `analytics.track()` — fire-and-forget is intentional.
- Don't flag missing authz under `app/api/public/**` — that tree is deliberately open.
- Don't flag `late` fields in generated `*.g.dart` files.
```

## Invariants

The higher-value half. These kill false positives *and* generate real findings when
violated — you're teaching the reviewer the rules of your codebase, which is exactly
the institutional knowledge a general-purpose model cannot infer.

```markdown
- All money and coin balances are integer minor units. Any `double` or `number`
  holding currency is a bug, no exceptions.
- Every route under `app/(admin)` is authz-gated by middleware — don't re-flag those.
- Reward claims must carry an idempotency key. A claim mutation without one is Critical.
- User-facing timestamps are stored UTC and converted at the edge. Storing local time
  is a bug.
- Anything reading `process.env` must be server-only. An env read reachable from a
  `'use client'` module is Critical.
```

## Notes

- Commit it. It compounds, and it's worth more than the skill itself after a while.
- Keep it short. If it grows past ~40 lines, some entries have stopped being real —
  prune the ones you can't justify.
- Invariants written as **"X is a bug"** work better than **"be careful about X"**.
  The first is checkable; the second is a mood.
