# Miss ledger

What Shrike failed to find, and what changed as a result. Entries record the *shape* of
each miss, the invariant class that now absorbs it, and the patch. Development
artifact — not shipped in the flat build (only `skills/shrike/references/*.md` is
inlined).

Findings are described in general terms only. Where a lesson came from studying real
review output, the underlying code and the specific defects stay private; what lands
here is the failure shape, which is the only part that transfers to a diff nobody has
seen yet.

## How a miss becomes a patch (read this before adding an entry)

The failure mode of a ledger like this is accretion: every bug another tool finds gets
appended as a new rule, the taxonomy grows without bound, and eventually the agent
skims a checklist instead of working a method. A 200-row seed list is worse than a
20-row one even though it "covers more".

So the rule is **generalize or don't add**:

1. Classify the miss into one of the eight invariant classes in
   `references/seeds-and-slicing.md`. Most misses are an existing class the run failed
   to *ask*, not a class that doesn't exist — that is a discipline problem, fixed in
   the workflow or the falsification pass, not by adding a rule.
2. If the class exists but has no shape resembling this bug, add one clause to that
   class's *shapes* list. Shapes are evidence; they cost one clause and no new
   question.
3. A genuinely new class must be a *kind* of wrongness, not a situation. "The value
   doesn't mean what the consumer thinks" is a kind. "This linter's allowlist fields
   default to OR" is a situation — it goes in a stack reference, or nowhere.
4. Stack- or library-specific instances go to `references/<stack>.md`.
5. Keep the specific case out of the method entirely. The test for anything entering
   the method: **would it change what a reviewer does on a diff it has never seen?**

The budget is stated and enforced in `references/seeds-and-slicing.md`: constructs stay
language-level and finite, the classes stay eight, that file stays under ~2,500 words.
Merge or delete before adding.

The two studies below were run *before* this rule existed and did accrete rows — 47 by
the end. The restructure that introduced the eight classes folded all 47 back down
while getting slightly smaller in total words. That is the shape every future study
should take.

---

## Miss — a ratio gate cleared "in isolation"

**The bug.** A majority gate of the form `count / total >= threshold`, where `total`
counted only the samples an *earlier pass in the same pipeline* had not already
discarded. Once that earlier pass cleared most of them, a handful of unrepresentative
samples became the entire denominator, the gate passed, and the operation it guarded
ran on data it should have rejected.

**What Shrike did instead.** It listed the gate's arithmetic under *Checked and
cleared* — the degenerate zero case was handled, the division was safe, the math was
internally consistent. All true, and all beside the point: the function was verified
against the pipeline's original input rather than the mutated state it actually
receives at that stage. It had even found a sibling defect in the same function, so
this was not inattention. It was isolation-scoped verification.

**Classes that now absorb it.** D (a partial population treated as complete — a filtered
denominator), C (stale state — a later pass judged against the original input).

**Patches.** The two shapes above, plus a Phase 1 question requiring each stage of a
multi-stage pipeline to be judged against what it actually receives, plus a
falsification self-check: a clearance must hold in the context the code really runs
in. "The math is internally consistent" clears nothing if those inputs never occur.

---

## Study 1 — two commercial reviewers on a shared codebase

Every pull request in one repository where two commercial review tools had both posted
findings. ~140 deduplicated findings, of which only ~6 were noise — both tools ran at
high precision.

**~90 were outside the taxonomy at the time.** The taxonomy was strong on value-level
defects (null, bounds, async, authz) and weak on *system-level* ones. The uncovered
findings clustered into:

1. **Fail-open validator code** (largest cluster) — gates, parsers, and contract
   extractors that silently pass on error, empty result, missing file, or unparsed
   input, or whose oracle proves a proxy (a name exists, a keyword is present) rather
   than the property.
2. **Checkpoints advanced past unprocessed data** — high-water marks saved after an
   aborted or capped walk; a durable queue drained only when an unrelated step
   succeeded.
3. **Partial failure conflated with success** — success UI and success returns ignoring
   aborted and error states; a default substituted for a value that is null while
   loading.
4. **Pagination and cap truncation** — first-page-only aggregates; per-page reductions
   where whole-set semantics were intended.
5. **Duplicated constant and predicate drift** — a default in application code and again
   in a database function; a backfill predicate disagreeing with the runtime check.
6. **Sibling-path omission** — a new route missing from a parallel exemption list; one
   of two paths missing a side effect; an enum variant falling through to a default.
7. **Concurrency and lifecycle** — a process-global clobbered by an older instance's
   teardown; fixed-sleep synchronization; destructive consume before commit.
8. **Migration hazards** — cascade reach, the concurrent-write window, partial
   conflict-update column sets.
9. **Guard over-restriction** — a tightened auth check breaking legitimate
   non-user callers.
10. **Tool and config semantics** — a pinned version lacking the config keys in use,
    field-combination defaults (OR where AND was assumed), env vars read but never set.

---

## Study 2 — three more codebases, and the first validation

The most recent bot-reviewed pull requests across three unrelated repositories — a
backend data/extraction pipeline, an analytics dashboard, and a SaaS platform with an
AI chat layer. ~123 findings, 1 noise, from a single commercial reviewer.

**Validation: ~60% were already covered, and every one of those landed on a seed added
in study 1.** The expansion transferred to codebases it was never derived from.
Coverage tracked how backend-shaped the work was — highest on the pipeline repo, lowest
on the most UI-heavy one.

The residual clustered into UI-state and semantic-labelling defects the taxonomy had no
mechanical prompt for:

1. **Count unit versus label** (largest) — join/pair rows rendered as distinct
   entities, two units summed into one total, a count reporting rows attempted rather
   than rows written, a scoped result used as if global.
2. **Labels asserting what the data contradicts** — an explanatory note naming the
   wrong cause, a caveat attached to a clause it does not qualify, a state-agnostic
   prefix that misreads one status as another.
3. **Draft state keyed to a changeable identity** — an editor's local state surviving a
   switch of the entity it belongs to; an expansion flag never reset on reopen; a reset
   performed in an effect, so the first paint still shows a leftover armed confirm.
4. **Cross-source render gating** — one query's error hiding another's loaded rows;
   error UI and its retry gated behind a query that never settles; an imperative
   refetch running a deliberately disabled query.
5. **Navigation target scope** — links dropping the filters the current view implies; a
   call-to-action opening an editor that excludes the option it offered.
6. **Dismissal-handler side effects** — an outside-press dismissal committing the action
   the user was in the middle of replacing; a guard flag set on one event and cleared
   only on another.
7. **Key and namespace collision** — lossy normalization collapsing distinct inputs to
   one key; a namespace overlapping another environment's, whose cleanup then deleted
   resources it did not own.

**Scope boundary confirmed, not widened.** A handful of residual findings were
deliberately left out of scope: skeleton-height mismatch, scroll position after an
insert, duplicate accessible names, a styling bug with visual-only effect. The scope
contract now names those classes explicitly so runs do not drift into reporting them —
with the carve-out that a surface *asserting something false about the data* is a
correctness defect and stays in scope.

**Also added.** `references/llm-integration.md`, for code calling a model provider:
hardcoded media types on multimodal parts, reasoning blocks persisted without the
metadata replay requires, cancellation signals not threaded into nested calls,
framework error contracts assumed rather than read, and stale pricing constants.

---

## Study 3 — depth pass, five codebases, four languages

The two earlier studies read the most recent reviewed pull requests. This one went
*backwards* through the history of five codebases — a Python data/orchestration
service, two TypeScript web applications, a Flutter client with a TypeScript admin
surface, and a browser-based capture tool — reading several hundred more findings in
batches. The point was no longer coverage of a repo but **recurrence across repos**: a
shape seen once is an anecdote, a shape seen in three unrelated codebases in two
languages is a seed.

Roughly two thirds landed on shapes already present. What follows is only what
recurred *and* generalized. Each became one clause, folded into the class it belongs
to — the taxonomy stayed at eight.

1. **Comparison strength mismatched to the identity being tested** (A). Case-sensitive
   here and case-folded there; an unanchored substring where a prefix was meant; a
   normalization that collapses distinct keys, or fails to collapse equal ones. The
   single most repeated shape in the corpus, in every language present.
2. **Truthiness standing in for presence** (B). `0`, `""`, `false`, and *explicitly
   cleared* all taking the absent branch — a cleared field silently restoring the
   default, a zero cursor persisted as NULL, an opt-out env var read as opt-in. Its
   database sibling: a predicate on a nullable column written `= false`, which drops
   the NULLs. Its filter sibling: an empty query degrading to match-*everything*.
3. **Handlers typed on exceptions the library does not raise there** (B). Timeouts
   that are not the language's timeout type, domain errors outside the caught
   hierarchy. Always the same consequence: work meant to be retried is recorded as
   permanently failed. Frequently visible as two sibling workers disagreeing about
   which errors are transient.
4. **Positional identity** (A). An array index, a list order, or a rounded coordinate
   used as a stable key across regeneration — cached verdicts keyed to a slot, drafts
   keyed to an index, ids that collide when two items round to the same cell.
5. **Async results applied without a currency check** (C, G). A response landing after
   the session, file, or selection it was requested for has changed; two runs writing
   one slot with no generation counter, so the slower earlier one wins; and the mirror
   image, an early return on a staleness check that skips the cleanup the happy path
   performs, leaving a spinner or lock set forever.
6. **Sibling paths that drift** (E). A gate, validation, normalization, or masking step
   applied on one route and missing from the parallel one — a region endpoint next to
   a full-document endpoint, a table view next to a card view, a new action added
   outside the matcher covering its neighbours. This is where the authorization
   findings clustered; almost none were "no check at all", nearly all were "checked
   here, not there".
7. **Redaction that downstream code still keys on** (A, E). A field nulled or
   substituted for one class of caller, while the code that sorts, filters, groups, or
   deduplicates by it collapses distinct entities into one bucket, or leaks the raw
   value on the path nobody updated.
8. **Failure states that cannot be left** (F). A memoized promise caching its own
   rejection; a retry counter incremented past its cap so the re-armed row can never be
   selected again; a drain loop whose exit condition is "no more matching rows" while
   one permanently failing row keeps matching.
9. **Partial idempotency on rerun** (B, H). An already-ran guard that short-circuits
   some of a second run's effects but not others; a reset or backfill that misses the
   columns the selection predicate actually reads; an already-applied migration or
   one-shot script edited in place, so databases stamped at it never receive the
   change.
10. **Defaults and constraints that live in only one layer** (E). Enforced by the ORM
    and bypassed by raw SQL or a bulk insert; a uniqueness rule expressed over a
    nullable column, which the database does not enforce at all.
11. **Metrics computed over a different population than the thing they describe** (A,
    D). A coverage or freshness figure with a different filter set than the query it
    annotates; a cap applied before the filter that should have preceded it; a dedupe
    that keeps one member wholesale and drops fields only the others carried.

**Language support.** One of the five codebases is Python, and its failure modes were
distinctive enough to earn `references/python-backend.md`: exception-hierarchy
assumptions, indentation-as-control-flow, ORM defaults skipped by bulk and raw writes,
migration-chain hazards, and fork-vs-spawn worker pools. The deterministic pass already
ran the Python analyzers; the checklist is what was missing.

**Scope, again.** The residual left deliberately unreported was almost entirely dead
code, redundant helpers, duplicated blocks, and performance speculation — the scope
contract now names those explicitly. One carve-out was added in the other direction: a
change that leaves a control **unreachable or unactivatable** is a correctness defect,
even though the labelling of that control is not.

**Budget.** These additions pushed `seeds-and-slicing.md` past its stated 2,500-word
cap. Prose was compressed and clauses merged; the stated budget moved to 3,000 with the
same enforcement, and the preference for *widening an existing clause over appending a
new one* is now written into the file. The classes remain eight.
