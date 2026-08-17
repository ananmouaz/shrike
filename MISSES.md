# Miss ledger

Regression list of real bugs Shrike failed to find on live runs, plus corpus studies
of competing reviewers' findings. Each entry records the miss, why the skill missed
it, the category, and the patch that covers the category. Development artifact — not
shipped in the flat build (only `skills/deep-bug-hunter/references/*.md` is inlined).

## 2026-08-17 — corpus study 2: karajan, dashboard, platform (45 PRs, Cursor-only)

Second corpus pass over three more repos, and the first **validation** of the seed
expansion from study 1. Cluster: the 15 most recent bot-reviewed PRs in each of
`karajan` (Python data/anonymization/LLM-extraction pipeline), `dashboard` (B2B
analytics/compliance UI), `platform` (SaaS analytics + AI chat). No Macroscope in
these repos — Cursor BugBot only. **123 findings, 1 noise** (28 High, 73 Medium, 22
Low). Boilerplate note: Cursor comment bodies are ~85% markup (fix-in-cursor
buttons, base64 deep links, billing notices); strip on `DESCRIPTION START/END` and
`LOCATIONS START/END` markers before analysis.

**Validation result: 74/123 (60%) were covered by the post-study-1 taxonomy, and
every one of those 74 was caught by a seed added in study 1 (20–34).** Coverage by
repo tracked how backend-shaped the work was: karajan 76% covered, platform 46%,
dashboard 57%. The residual concentrated in UI-state and semantic-labelling defects
the taxonomy had no mechanical prompt for.

Residual clusters, added as 13 new seeds:

1. **Count unit vs label** (~10, largest) — pair/join-row counts rendered as
   distinct entities, two units summed in one badge, a returned count reporting
   rows attempted rather than rows written, a scoped query result used as global.
2. **Label/caveat asserting something the data contradicts** (~4) — an explanatory
   note naming the wrong cause, a caveat attached to the clause it doesn't qualify,
   a state-agnostic prefix that misreads pending as completed. In scope because the
   surface misinforms, not because the wording is imperfect.
3. **Local/draft state keyed to a changeable identity** (~5) — drafts surviving a
   company switch with no re-key, expansion flags never reset on modal reopen,
   step reset done in an effect so the first paint shows a leftover armed confirm.
4. **Cross-source render gating** (~4) — one query's error hiding another's loaded
   rows, error UI and retry gated behind a query that never settles, imperative
   `refetch()` running an `enabled: false` query.
5. **Navigation/link target scope** (~4) — tab links dropping deep-link params, a
   CTA opening an editor that filters out the offered option, "reset" restoring a
   hardcoded default over a deep-link-forced one.
6. **Dismissal-handler side effects** (~3) — outside-press dismissal committing the
   action the user was replacing; a `pointerdown` guard flag cleared only on click.
7. **Key/namespace collision** (2) — lossy slug normalization collapsing distinct
   branches; a renamed preview namespace overlapping CI's, whose cleanup then
   deleted shared databases.
8. Singles worth seeds: cleared bulk-limit control meaning "all" rather than
   "none"; in-flight write unmounted by a filter change the busy lock didn't cover;
   a predicate built over merged rule kinds applied per kind; a skip path omitting
   the linkage row the non-skip path writes; a repair handler whose own unguarded
   `await` fails the whole turn.

Also extended: seed 14 (retry) with fallback fan-out after the primary exhausted its
retries; seed 31 (migration) with duplicate `down_revision` heads and a DDL lock held
across a long backfill in the same transaction.

**New reference `llm-integration.md`** — both LLM-heavy repos produced defects with
no home: hardcoded `mime_type` on multimodal parts, reasoning-block signatures not
round-tripped on replay, `abortSignal` missing on repair calls, AI SDK error
contract assumed rather than read, stale hardcoded per-token pricing. SKILL.md now
directs to it in addition to the language checklist whenever a diff touches prompt
construction, tool calling, streaming, or model config.

**Scope boundary confirmed, not widened.** ~6 uncovered findings were deliberately
out of scope: Suspense-fallback height mismatch (x2), scroll position after
inserting a form, duplicate `aria-label`s, a Tailwind arbitrary-variant escaping bug
with visual-only effect, and a preset highlighting on hover-preview. The scope
contract in SKILL.md and the adapter now name these classes explicitly so future
runs don't drift into reporting them — with the carve-out that a surface asserting
something false about the data is a correctness defect.

Corpus: `study/karajan-dashboard-platform-corpus-2026-08-17.json`.

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
