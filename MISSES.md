# Miss ledger

Regression list of real bugs Shrike failed to find on live runs, plus corpus studies
of competing reviewers' findings. Each entry records the miss, why the skill missed
it, the category, and the patch that covers the category. Development artifact — not
shipped in the flat build (only `skills/deep-bug-hunter/references/*.md` is inlined).

## 2026-08-17 — corpus study: axess-intelligence/rewado, 23 dual-bot PRs

Studied every PR (#782–#861) where both Cursor BugBot and Macroscope posted findings:
140 deduplicated findings (85 cursor, 103 macroscope raw), only 6 judged noise. 90
findings were NOT covered by Shrike's then-current seed taxonomy — the taxonomy was
strong on value-level defects (null, bounds, async, authz) and weak on
*system-level* ones. Dominant uncovered clusters, each patched as a new seed in
`references/seeds-and-slicing.md` (mirrored in `adapters/bug-hunt.prompt.md`):

1. **Fail-open validator/checker code** (~15 findings) — CI gates, parsers,
   contract extractors that silently pass on error/empty/unparsed input, or whose
   oracle proves a proxy (name-only match, keyword presence) instead of the property.
2. **Checkpoint advanced past unprocessed data** (~5) — high-water marks saved after
   aborted/capped/failed walks; pending-queue draining gated on an unrelated success.
3. **Partial failure conflated with success** (~8) — success UI/return ignoring
   aborted/error/still-loading states; `?? default` on null-while-loading.
4. **Pagination/cap truncation** (~5) — first-page-only aggregates, per-page
   reductions breaking whole-set semantics.
5. **Duplicated constant/default/predicate drift** (~7) — client vs SQL function,
   two screens, doc vs schema.
6. **Sibling-path/registry omission** (~7) — new route not in exemption list, one of
   two parallel paths missing a side effect, enum variant falling through defaults.
7. **Concurrency/lifecycle** (~10) — process-global clobbered by old-instance
   dispose, fixed-sleep synchronization, destructive consume before commit,
   double/under-count across overlapping ops.
8. **Migration/backfill hazards** (~6) — CASCADE data loss, concurrent-write window,
   partial ON CONFLICT updates, backfill predicate vs runtime predicate mismatch.
9. **Guard over-restriction** (~2) — tightened auth breaking NULL-JWT service callers.
10. **Tool/config semantics** (~7) — pinned version lacking config keys, OR-vs-AND
    defaults, unset env vars, wrong environment target.

Stack files also extended: `flutter-dart.md` (AsyncValue.value ?? default,
cross-provider desync, didUpdateWidget reentrancy, dispose clobbering globals);
`next-drizzle-neon.md` (new Postgres RPC section: SECURITY DEFINER search_path,
in-function caller-identity checks, NULL-JWT caller enumeration).

Raw classified corpus: `study/rewado-corpus-2026-08-17.json` (140 findings, per-finding class + seed-coverage tags) — usable as an eval set: rerun Shrike on these PRs and diff against it.

## 2026-08-17 — upload repo, `fix/forced-dark-card-captures`

**Bug (found by Cursor BugBot, after Shrike's pass):**
`features/upload/lib/embedded-image-cleanup.ts` — the `MIN_RING_FRACTION` majority
gate in `transparentizeEdgeChrome` divides by `ringCount`, which counts *opaque*
ring pixels only. `transparentizeNearWhite` runs earlier in the pipeline and clears
most of a light chrome frame to alpha 0; the few opaque edge pixels left are photo
content touching the crop, they become the entire denominator, the gate passes, and
the flood fill treats the photo edge as chrome and clears into the attachment (up
to the cleared-area cap).

**What Shrike did instead:** listed "Ring/bucket math in transparentizeEdgeChrome —
… dominant average divides by count≥1 … verified" under Checked and cleared. It
checked the degenerate `count == 0` case and internal consistency, but judged the
function against the *original* image, never against the post-`transparentizeNearWhite`
alpha state it actually receives. Ironically it did find the sibling flood-fill bug
in the same function — the miss was not lack of attention to the function, it was
isolation-scoped verification.

**Miss categories:**
1. *Filtered-denominator ratio gate* — `count/total` where `total` is itself
   filtered (opaque-only / non-null-only / valid-only); the filter can shrink the
   population until a handful of unrepresentative samples decide the gate.
2. *Multi-pass pipeline over shared mutable data* — a later stage verified against
   the original input instead of the state earlier stages leave behind.
3. *Isolation-only "checked and cleared"* — a clearance whose evidence never
   involved the runtime context.

**Patches (this commit):**
- `references/seeds-and-slicing.md`: added two seeds — ratio/majority gate with
  filtered denominator; later stage of a multi-pass pipeline.
- `SKILL.md` Phase 1: added pipeline-state question — verify each stage against
  what it actually receives, not the original input.
- `references/falsification.md` self-check: isolation-only clearances must be
  re-checked in context before being listed.
