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

The budget is stated and enforced in `references/seeds-and-slicing.md`, in the order
that binds: the classes stay eight, each class carries at most 12 phrase-length shapes
(~175 words), constructs stay language-level and finite, and the file stays under
~3,100 words as a backstop. Merge or delete before adding — widening an existing clause beats
appending a new one.

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

### Study 3b — the validation half

Study 3 derived shapes from one set of pull requests, so a second, unread set was pulled
immediately after — 45 more pull requests across three of the same codebases, ~205
findings, none of them consulted while writing the patches.

**The result is the point: almost everything landed on an existing clause, and a
visible share landed on clauses written hours earlier.** Async results applied without a
currency check, sibling caches left uninvalidated, local wall-clock written into a UTC
column, still-loading rendered as a real default, skip paths omitting the bookkeeping
the main path performs, guards short-circuiting part of a rerun — all previously
residual, all now absorbed on first contact with unseen code. A taxonomy that only
explains the corpus it was derived from is a description; one that catches the next
batch is a method.

Roughly a tenth of the sample was material the scope contract deliberately excludes —
dead code, duplicated helpers, dark-mode styling, grammar in a badge. Correctly not
reported is also a result.

Four things survived as genuinely uncovered. Three went in as *widenings* of existing
clauses rather than new ones, which is the behaviour the budget is supposed to produce:

1. **A client affordance disagreeing with the server check it fronts** (B). The most
   common authorization shape in the corpus by a wide margin — not "no check at all"
   but a button shown to callers the mutation rejects, or hidden from callers it would
   allow. Both directions are bugs; only one is a security bug.
2. **A missing value defaulted to the neutral or passing one** (B) — parity, full
   confidence, "no restriction" — so the case that should have been flagged reads as
   normal. Was already in the LLM reference as a model-output shape; the sample showed
   it is not LLM-specific.
3. **A dependency bump whose API the call sites no longer match** (H) — a renamed
   field, a moved export. Replaced the narrower pinned-tool-version clause.
4. **Optional chaining that guards one link and then dereferences anyway**
   (`a?.[k].m()`), and **normalizing transforms that strip every occurrence rather than
   the wrapper** — both mechanical and greppable, so both went to the construct table
   rather than a class.

Net effect on size: 86 shape clauses to 85, every class still inside 12 clauses and
~160 words. Two additions, three merges, one deletion — the null-reaching-the-use clause
went, because the construct table already asks that question.

### Study 3c — second validation round

Another 45 unread pull requests, same three codebases, deeper into their histories.
Coverage was higher still: the run kept landing on clauses *verbatim*. A guard tightened
until it rejected NULL-session admin callers. A recovery step whose own I/O threw and
took the operation down. Two sibling paths where only one emitted the side effect. `ON
CONFLICT DO UPDATE` leaving a column stale. A page-at-a-time reduction where whole-set
semantics were meant — that one arrived as a shell command whose filter ran per page.

Two shapes worth having, both cross-repo:

1. **A string that must match something defined elsewhere, where the mismatch is
   silent** (E). One codebase migrated its data layer, and every hand-written cache key
   that used to match the old generated format now matched nothing — no error, just a
   permanently cold cache and invalidations that were no-ops. The same shape had already
   shown up as test selectors pointing at renamed classes. It merged with the existing
   schema-field-name clause, since both are one string having to agree with another
   layer's, failing quietly when it doesn't.
2. **The wrong cardinality** (D). A scalar subquery on a key that permits several rows;
   an update that filled *every* empty slot where the first was meant; a summary that
   showed all-clear unless *every* item lacked its safety record. One-vs-many and
   every-vs-any are the same mistake about set size, so they are one clause.

Also widened: an affordance can disagree with the server on *limits*, not just
permission — a client that lets a reviewer select more items than the mutation accepts
is the same defect as one that shows a button the mutation rejects. And a change's own
description now counts alongside docs and runbooks as a place a claim can contradict the
code; one pull request described an admin carve-out the diff did not contain.

**Declined, and worth recording as declined:** a newly gated response still served with
public cache headers. Real, dangerous, and it appeared exactly once, in one repo. The
rule is that one occurrence is an anecdote. It stays out until a second sighting.

One incidental result: an earlier compression pass moved a Flutter-specific clause out of
the classes, and this sample turned up that exact bug — a controller driven synchronously
during a parent's rebuild. The stack reference had it, word for word. The move was right.

**Budget, and what a word cap was measuring wrong.** These additions first pushed
`seeds-and-slicing.md` from 2,229 to 2,915 words, and the reflex was to raise the stated
cap. Measuring where the growth actually landed showed that was the wrong control: the
*questions* had not grown at all — still eight classes, still one closed question each —
while the **shape lists** went from 65 clauses to 97, and the new clauses averaged 19
words against the original 11.

That is the real degradation vector, and it has two mechanisms. A long shape list stops
being illustration and gets *walked* like a checklist, which costs recall on every kind
of wrongness the list does not happen to name. And a verbose shape reads like a finding
already written, so a superficial match to it feels like evidence — it pre-loads the
falsification pass with something that sounds proven.

So the budget is now stated in the order that binds: eight classes, then **at most 12
shapes per class and ~160 words per class**, then a total backstop. A compression pass
brought every class inside that (86 clauses, 2,737 words) without losing a distinct
shape — near-duplicates were merged, verbose clauses cut back to phrases, and the
narrowest tooling-specific shapes pushed into stack references. A total-word cap alone
would have hidden which class was bloating; a per-class cap cannot.

---

## Study 4 — head-to-head against a commercial bot on live pull requests

The first sample where Shrike and a commercial reviewer ran on the *same* pull requests
rather than on a historical corpus: nineteen pull requests over three days on one
repository, Shrike run by hand, the bot running on every push. The bot posted fourteen
findings across eight of those pull requests; eleven pull requests drew nothing from it.

The interesting number is not fourteen. It is how the fourteen partition once you check
which commit each one landed against, and whether Shrike had reported on that commit:

| Cause | Findings |
|---|---|
| No Shrike report on the pull request at all | 8 |
| Code pushed *after* the commit Shrike reported on | 3 |
| **Same commit, genuine miss** | **3** |

**So the headline result is a coverage result, not a recall result.** Eleven of fourteen
were bugs in code Shrike never read: pull requests where nobody ran it, one integration
branch nobody thought to review as its own diff, and — twice — a report posted minutes
before the next push, whose new commits contained exactly the flagged lines. A reviewer
invoked once, early, by a human who then keeps working loses to a bot triggered by the
push event, and it loses without being out-reasoned. Every mechanism here was a process
gap, and none of them was visible in the report, because a run header naming a commit
range reads as "the branch" to whoever skims it.

**The three real misses, and what they have in common.** Both files were already open in
front of the hunt; each miss was one question short of a finding.

1. A continuous-integration workflow gained a `ref` input so it could smoke an arbitrary
   branch, and its failure path still filed an incident, paged, and labelled as though
   the default branch had broken — so verifying a fix pre-merge raised a false alert.
   Shrike reported zero findings on that diff and had raised, then killed, a candidate on
   the *same expression* (whether the new default was byte-identical on a scheduled run).
   It had also declared four of the eight classes `n/a` — including B, on a file whose
   whole subject is conditional alerting.
2. A test-harness helper was changed, *by Shrike's own fix in that run*, to return a
   two-field record instead of a bare integer. One comparison site kept comparing the
   whole record against an integer, so the setup precondition of a reproduction test
   could never hold. Shrike reported eight findings on that pull request, fixed all
   eight, posted the report against the commit containing its fixes — and never re-ran
   the caller enumeration over the contract *it* had just changed.
3. An environment variable set a proxy's listen port while the container mapping stayed
   hardcoded, so any override silently pointed the suite at an unexposed port (class E,
   in a compose file, unasked).

**Classes that absorb them.** B and H for the first, H for the second, E for the third.
All three already have the shape, verbatim — "a validation, normalization, or masking
step present on one path and missing from its sibling", "a changed signature... with
callers left on the old contract". So: no new class, no new shape. Per the rule at the
top of this file, this is a discipline problem, and the patches are all workflow.

**Patches.**

1. **Phase 7 — "the diff you did not review."** Fixes applied during the run are
   unreviewed diff and get Phase 1's caller enumeration re-run over every symbol whose
   contract the fix changed. Anything pushed after the reviewed head gets hunted as a
   delta before the branch is called ready, and a rollup or integration pull request
   counts as its own diff against its own base. Whatever stays unreviewed is named in
   the report — silence reads as coverage.
2. **`n/a` now needs evidence.** Declaring a class inapplicable is the cheapest possible
   way to lose a bug: it closes a question without reading anything, asserted when the
   diff is least understood. An `n/a` must state what was searched for and found absent,
   not "no guards here".
3. **Find the peer.** A Phase 1 step: for every behavior the change introduces, name the
   nearest thing already doing that job — sibling helper, the same feature in another
   package, the previous pull request that fixed this class, the linked issue's
   acceptance criteria — and state where the change diverges. This is the one place the
   bot showed a real method edge: nearly every finding it posted in the sample cited a
   peer that already did it right. Class E covered the shape; nothing had told the hunt
   to go *look* for the counterpart.
4. **Coverage honesty on large diffs.** The two runs in the sample that reported honestly
   differ starkly in effort per hunk: 44 hunks in 28 minutes raised 23 candidates, while
   106 hunks in 8 minutes raised 11 — a fifth the candidate rate per hunk. The 5-finding
   cap cannot distinguish a clean diff from a skimmed one, so the report now carries
   hunks-per-hour and a *not reviewed* row, and the workflow says to slice a diff above
   roughly 60 hunks and hunt each slice to the same depth — or declare the remainder.
5. **Non-product code is in scope for slicing.** Five of the fourteen were in workflow
   YAML, a compose file, a test harness, and shell scripts. A hunt aimed at product logic
   stops looking there, and the scope contract's exclusion of *test coverage opinions* is
   easy to over-read as excluding test and infrastructure code itself. It does not: a
   harness that cannot fail, an alert that fires on the wrong branch, and a script that
   leaves production files reverted after Ctrl-C are all correctness bugs.

**Also worth recording: the bot's precision was high in this sample.** Every finding
whose disposition was checked had a commit fixing it, and none of the fourteen read as a
false positive on inspection. The economics stated at the top
of `SKILL.md` still hold — a false positive costs more than a miss — but this sample says
the miss side of that trade is being paid mostly at the process layer, not the method
layer, and process is cheaper to fix than recall.

---

## Study 5 — a 78-run cohort, and why the corpus outranks the numbers

The largest sample so far, and the first one assembled by asking the opposite question:
not "what did the reviewer find" but **"did running Shrike reduce what escaped?"** Every
hunt recoverable from agent transcripts in one repository over a month — 78 runs across
48 pull requests, against 176 merged in the window — set beside every inline finding a
commercial reviewer posted on those same pull requests. Thirty-seven of its findings
landed on pull requests a hunt had already cleared.

**The outcome number is inconclusive, and that is the honest headline.** Per pull
request the hunted cohort drew 0.79 findings against 1.26 unhunted, one-sided
permutation p=0.032. It does not survive two checks:

1. **Size normalization.** Within the same era the two cohorts sit at 0.32 and 0.37
   findings per thousand changed lines — noise. The per-pull-request gap is mostly
   *hunted pull requests were bigger, and big diffs carry fewer findings per line*.
2. **Attribution sensitivity.** Only 21 of the 78 runs could be tied to a branch with
   certainty. That verified subset sits at 0.65 findings per thousand lines —
   indistinguishable from never running it at all.

Compliance was partial too: pull requests averaged 3.7 commits against 1.7 runs, so most
pushes shipped with no hunt. So this study throws the cohort arithmetic away and treats
the 37 as a corpus. **An improvement pass must not start from "it already works."**

**Attribution was per pull request, which hides the split Study 4 measured.** A finding
on a *pull request* that was hunted is not the same thing as a finding on the *commit*
that was hunted. Study 4's smaller sample split fourteen findings 8 / 3 / 3 between "no
run at all", "code pushed after the report", and "same commit, genuine miss" — so an
unknown and probably large share of these 37 are coverage, not recall, and the two have
different fixes. Nothing in the workflow recorded which commit had been hunted, so the
split could not be recovered here. That is the first patch, and it is the one that makes
the next eval repeatable.

**How the 37 classify.** By defect class, largest cluster first: post-await state and
lost updates (10), a legal `0`/`""`/partial set read as absent (6), input-normalization
edges (5), a side effect that never fires (4), declared-but-never-consumed drift (4), a
status written without verifying the effect (3), other (5). Twenty-two of the 37 matched a
shape already written in `seeds-and-slicing.md`, several of them verbatim — which by the
rule at the top of this file makes them a discipline problem, not a taxonomy problem.

### The structural finding: per-instance defects asked as a per-change question

Twenty of the 37 sit in three families that are *mechanically enumerable* — an
`await` followed by a use of state captured before it, a guard deciding whether a value
was supplied, an effect registered relative to its only consumer's read. Every one of
those already had a construct row, a class, or both. They were missed anyway, and the
mechanism is structural rather than lazy:

> An invariant class is **one question asked of the whole change**, and one answer
> closes it. These defects are **one per instance**. A diff can honestly satisfy "is
> there stale state here?" on the first `await` that looks fine and still carry nine
> unread ones.

The same asymmetry explains why the constructs layer under-performed: it is described as
the grep layer, but nothing required the grep to *produce a list*. "Checked the async
boundaries" and "enumerated eleven `await`s, nine safe, two candidates" are different
acts that read identically in a report.

**Patch — four enumerated sweeps (`SKILL.md`, Phase 3).** Post-await state, presence and
absence, effect order, and test power. Each defines its population, requires a verdict
per row, and reports an instance count in the run header. `post-await 0` on an async diff
is now visibly a skipped sweep rather than a clean one, the same way the hunks-per-hour
row made a skimmed pass visible. The falsification self-check asks whether each sweep
produced a list or a conclusion.

**Patch — test power as the fourth sweep.** For every test added or changed in the diff:
revert the production hunk it covers, run it, and record whether it went red. Where
reverting is impractical, name the assertion that would fail and the input that reaches
it, and check the fixtures actually contain a case of the class under test — a setup
filter that excludes every input the regression would produce is the recurring shape, and
it reads as a passing test forever. The strongest catch in this whole window was exactly
that: a test rewritten into a decoy, admitting only a subset that excluded the case the
change existed to protect, on a diff the commercial reviewer had cleared twice. **A test
that tests nothing is an absence** — there is no wrong line to annotate — so a
diff-comment reviewer structurally cannot report it, and fixing it cannot move a
findings-per-pull-request metric either. Which is the argument for measuring recall
against a corpus and a tautology-detection rate instead of another tool's comment count.

**Patch — a run record (`scripts/log_run.sh`).** One record per hunt appended to
`.agent/shrike-log.md`, keyed on the head SHA: target, range, files/hunks, duration,
sweep counts, candidates raised/killed/reported, and what was left unreviewed. Phase 7
reads `--last` to find the commit the previous report covered without needing the pull
request comment, and `report_stats.sh` falls back to it when `gh` is unavailable. Its
second purpose is the one this study needed: escaped bugs become attributable at commit
granularity instead of being reverse-engineered from transcripts.

**Patch — the replaced code is the peer (Phase 1).** A rewrite inherits every constraint
the old implementation encoded and restates none of them. One finding in the sample was a
default that a sibling module's comments record as incompatible with the regional
endpoint the rewrite advertises; another was a predicate a later migration had already
tightened in the parallel function. Both are class E, both were one file read away, and
the peer step said to look sideways at siblings without saying to look *backwards* at
what the change replaces.

### What the taxonomy actually lacked

Eight clauses, all folded into existing classes; still eight classes.

1. **G** — an effect emitted before its sink is initialized, or registered after its
   only consumer has read: it silently no-ops. This is the entire "side effect that
   never fires" cluster, and it is an ordering defect, not a missing-guard one.
2. **F** — a done-marker latched on an attempt whose effect never landed, so nothing
   retries it. The latch is what turns a dropped write into a permanent one.
3. **F** — a batch whose result cannot express per-member outcome, so the caller stamps
   every member done. Covers most of the "status written without verifying" cluster:
   the callee skips rows and returns success, the caller marks the whole page delivered.
4. **G** — a generation guard some writers never bump, or read fresh while the payload
   it protects stays stale. Both directions defeat optimistic concurrency while looking
   like they enforce it; the second is nastier, because the check passing is what
   authorizes the stale write.
5. **B** — the mirror of the truthiness shape: a bare null check counting `""`, `[]`, or
   a half-filled record as filled. The class had presence-written-as-truthiness for
   years; the inverse (absence written as null-only) is just as common and produces
   confident empty output.
6. **B** — a gate keyed on a lossy projection of what it guards, so an edit its summary
   cannot describe reads as no edit.
7. **E** — a field the reader keys on that its producers leave unset, so the fallback
   becomes the norm. Merged into the silent-mismatch clause: same failure, one side
   absent rather than misspelled.
8. **A** — a budget or deadline measured from a start that includes work it was never
   meant to cover.

Widenings rather than clauses: a read-then-write needs *a write predicate carrying the
state the decision was read from* (a compare-and-set, not just a transaction); an
affordance can disagree with the server by **offering an exit the handler rejects**, not
only by showing a button it refuses; and a clear or teardown sequenced *before* the bump
that would drop in-flight writes belongs beside the generation-guard shape.

Four construct rows were added, because these three families need a grep handle and not
just a class: effect registration or sink write, a concurrency token read for a guard, a
status or completion write, and a test changed in the same diff.

**Stack references.** Flutter/Dart: invalidating an `autoDispose` provider something is
already awaiting (the awaiter can hang with no error, and a `.timeout()` at the await
site fails that await open while leaving the shared future pending, so a second await
blocks again after the irreversible step in between); `AsyncValue.when` discarding
retained data on a failed refresh; a context used after the navigation that removed its
route — including the case where the change deleted an incidental `await` that was
providing the ordering; route observers reading a name most routes never set; crash
reports and custom keys emitted before the reporter's SDK is initialized, plus the latch
that makes the loss permanent. TypeScript/Next: an ISO shape plus a non-`NaN` `Date` is
not calendar validation; `||` on numeric edit defaults dropping a stored `0`; server
props refreshed while local form state is not; a version column one writer never bumps.

**Declined, recorded as declined.** A numeric answer routed through a free-text path,
burning a per-session budget and a model round-trip where a sibling path already sent it
structured: real, but it is a peer divergence the existing step covers, so it earns no
shape. And expected pre-auth failures recorded as genuine errors by a lifecycle trigger
wired without the precondition its original call site had: kept, but as a stack-reference
instance rather than a class shape, since it is framework-flavoured.

**Budget accounting, stated because the last study made it a control.**
`seeds-and-slicing.md` entered this pass at 2,836 words — already 86 over the stated
2,750 backstop, drifted there by the Phase 7 work, which is itself an argument for
measuring before adding. It leaves at ~3,104: eight classes, 8–12 shape clauses each, no
clause longer than ~33 words. The budget is now written as the two controls that actually
bind — **12 clauses per class, each a phrase rather than a sentence** — with the
per-class word figure (~175) derived from them and the total restated as a ~3,100
backstop. A fifth rule was added above it: if the class already had the shape, the fix is
not in that file at all; patch the workflow that failed to ask the question and add
nothing. Two thirds of this study's misses resolve that way, and a file that grows on
those is a file that will be skimmed.

---

## Study 6 — the High-severity residual on hunted pull requests

Study 5 measured findings per pull request and found the outcome inconclusive. This
pass asked a narrower question of the same repository, four weeks on: **stratified by
severity and by diff size, what does a commercial reviewer still post on pull requests a
hunt had already covered?** The answer splits cleanly. On hunted pull requests the bot's
Medium-severity rate fell (0.50 per pull request against 0.68 unhunted); its
High-severity rate did not move (0.28 against 0.27). Thirteen High findings landed on
hunted code in the window. The Highs are why the bot cannot be retired, and they
concentrate in six shapes.

**The meta-pattern: twelve of the thirteen name two or three locations.** Not one
defective line — a *relationship* between a changed line and something that did not
change: a second writer of the same row, the source a local copy was seeded from, a
sibling enforcement site, another caller of a merged path, the prelude before a clock
starts. Every sweep in the workflow enumerated a population drawn from the diff. These
bugs live in the join between the diff and the code around it, and nothing required the
hunt to open the other side of that join before falsification began.

**How the six shapes classify against the taxonomy.**

1. *Check-then-act with a second writer and no compare-and-swap* — another request,
   admin, isolate, or queued callback writes the same row between the read and the
   write. Class G, verbatim: "read-then-write with no ... write predicate carrying the
   state the decision was read from", plus the generation-guard and
   clear-before-bump clauses. Sweep 1 did not reach it because the read and the write
   sat in one synchronous block; the interleaving point was in another actor.
2. *Derived local state never resynced to its source*, and its sharper form: a guard
   reading the prop while the payload reads the local copy. The stack reference had
   the `router.refresh()` instance; class C had no general clause. One shape added.
3. *One of N sibling enforcement sites updated.* Class E verbatim, and the Phase 1 peer
   step already said to find the peer — for *behaviour the change introduces*, not for
   a predicate it tightens. Two sub-shapes cost two of the three: merging two paths
   that had different failure behaviour (one clause added to H), and a display helper
   reused as a correctness predicate (class B had "a gate keyed on a lossy projection",
   verbatim).
4. *Aggregate success hiding per-item skips.* Class F verbatim: "a batch result that
   cannot express per-member outcome, so the caller stamps every member done."
5. *Identity by position across a refetch.* Class A verbatim: "an index, order, or
   rounded coordinate used as identity across regeneration."
6. *A budget whose start includes unbudgeted work.* Class A verbatim — the clause Study
   5 added.

So four of six were written down word for word, one sat in a stack reference, and one
was the peer step applied to the wrong population. By the rule at the top of this file
that is a discipline result, and the patch is workflow.

**Patch — a fifth enumerated sweep, "second site" (`SKILL.md`, Phase 3).** Population:
every write whose value or decision came from an earlier read; every local copy seeded
from a source; every predicate the diff tightens, loosens, merges, or replaces; every
loop that skips inside a scalar-returning function; every deadline or share-of-total
budget. Per row, the requirement is the same: **name the other participant and open
it** — the second writer and the predicate, version, or lock binding it; the source and
the resync, and whether guard and payload read the same copy; every sibling
implementation of the rule, whole-repo grep, each marked carried-forward or diverged;
the caller acting on the whole set after the return; the prelude between clock start
and budgeted work. A name, a comment asserting agreement, or a same-sounding helper
does not close a row. The count goes in the run header as `second-site N`, so a zero on
a diff that writes a row or changes a predicate is visible as a skipped sweep.

**Patch — sweep 1 widened.** Its population now names an array index or list position
explicitly, and the interleaving point includes a refetch, a filter change, or an open
sheet, not only an `await` in the same function.

**Patch — constructs.** Four rows widened rather than added: indexing (held across a
refetch), loop (a skip inside a scalar-returning function), write path (who else writes
the row between the read and the write), and retry/timeout, now retry/timeout/deadline/
budget (what runs before the budgeted work).

**Patch — falsification self-check.** For every candidate or clearance that turns on a
writer, guard, or predicate: was the second site opened, or was a comment taken as a
rebuttal?

**Stack references.** Flutter/Dart: a budget whose clock starts before the isolate is
warm; sign-out racing a queued persist; two link handlers merged so one's fallback
reaches the other's callers. TypeScript/Next: an optimistic override map consulted by
truthiness; a `describe*`/`diff*` helper used as a save gate; the same eligibility rule
in two SQL functions with only one tightened.

**Not a rule gap, recorded as such.** One of the thirteen — a report emitted before its
sink was initialized, with a latch set on the attempt — is sweep 3 word for word,
including the "attempt or confirmation?" clause. The rule existed and the bug escaped.
No pattern fixes that; it is a compliance failure, and the only lever is the sweep count
in the header being read by the human.

**How to tell whether this worked.** Do not measure total findings — that number moves
with diff size, which Study 5 established. Measure **High-severity findings per hunted
pull request**. Baseline: 0.28, statistically identical to the 0.27 on unhunted pull
requests. Retire the bot only after roughly twenty consecutive hunted pull requests at
zero.

**Budget accounting.** `seeds-and-slicing.md` entered at 3,104 words, already at the
backstop. Class C was at twelve clauses, so its first two — state captured before an
`await`, and an async result applied without a currency check — merged into one before
the guard-versus-payload shape went in. Class H went from ten clauses to eleven. Eight
classes, none above twelve clauses or ~180 words. The file leaves at ~3,164 — about 60
over the backstop, all of it in the four widened construct rows, after trimming six
verbose clauses to pay for them. The per-class controls held; the total did not, and
that is recorded rather than the cap being moved.
