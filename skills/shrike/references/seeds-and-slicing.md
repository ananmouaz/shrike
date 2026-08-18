# Seeds and Slicing

## Why seeds

Open-ended search ("find bugs") has no stopping condition, so it terminates when the
model runs out of enthusiasm — which is exactly when it starts inventing. Seeded
search is bounded: each seed poses a *closed question* that reading code answers yes
or no, and when the seeds are worked the pass is done.

Two layers, different jobs. **Constructs** are the grep layer: syntax found
mechanically, language-level and finite. **Invariant classes** are the reasoning
layer: the eight kinds of wrongness a change can introduce, capped at eight on purpose
(see "Keeping this bounded").

Work both against the diff and its blast radius. Ignore untouched code unless a
changed contract reaches it.

## Layer 1 — Constructs

Mechanical triggers. Find them, then ask the question.

| Construct | Question |
|---|---|
| Indexing / slicing (`a[i]`, `.substring`, `.first`) | Can the collection be empty or the index out of range here? |
| Division / modulo | Can the divisor be zero? |
| Non-null assertion (`!`, `as`, `unwrap`, `!!`) | Is there a path where the value is null? What made the author sure? |
| `await` / async boundary | What state was captured before it, and is it still valid after? Is it awaited at all? |
| Resource acquisition (open, subscribe, listen, connect) | Is release guaranteed on every exit, including throw and early return? |
| `catch` block | Swallowed? Caught type too broad? Partial state left behind? |
| Loop with a mutable accumulator or index | First iteration, last, empty input, single element. |
| Boundary operator (`<` vs `<=`) | Inclusive or exclusive, does that match the caller's assumption, and if it is a range, is the pair validated as ordered? |
| Truthiness or nullish check (`if (x)`, `x ?? d`, `if x:`) | Can the value legitimately be `0`, `""`, `false`, or explicitly cleared — and does the absent branch then swallow it? |
| `catch` / `except` on a named error type | Does the library actually raise *that* type on this path, or a sibling that escapes the handler? |
| String comparison used as identity (equality, `in`, regex, key construction) | Same case, anchoring, normalization, and null handling on both sides of the comparison? |
| Secret, connection string, or raw upstream response crossing a boundary (client bundle, CI output, log, error body) | Is it meant to be readable there? |
| Write path (update, delete, upsert, file write) | Scoped? In a transaction with the reads it depends on? Idempotent under retry? |
| External input reaching a sink (query, shell, path, HTML, redirect) | Validated at *this* boundary, or assumed validated elsewhere? |
| Authorization-relevant handler | A real check, using server-derived identity rather than a client-supplied ID? |
| Money / quantity arithmetic | Integer or float? Rounding direction? Can it go negative? |
| Cache / memo write | What invalidates it? Can it serve across a permission or tenant boundary? |
| Retry / timeout / reconnect | What if the operation succeeded but the response was lost? |
| Signature change in the diff | Every caller updated — argument order, optionality, nullability, thrown types? |
| Removed or renamed field | Every reader, including rows already persisted and clients on older versions? |
| Feature flag / new conditional path | Does the *other* branch still work? Is the flag read consistently? |
| Object / struct comparison | Reference or value equality? Does the type implement equality? |
| Date / time arithmetic | Timezone, DST, epoch units (s vs ms), clock source. |

## Layer 2 — The eight invariant classes

Ask each class's question of the change as a whole. The *shapes* are how that class
has actually shown up in reviewed code — they are illustrations to pattern-match
against, not a checklist to walk.

### A. Meaning drift — the value does not denote what its consumer assumes

**Ask:** for every value this change produces or consumes, what exactly does it
denote — unit, population, encoding, state — and does every consumer agree?

**Shapes:** join/pair rows counted as distinct entities; two different units summed
into one total; rows *attempted* reported as rows *written*; a scoped or filtered
result used as if global; money in floats; seconds vs milliseconds; local wall-clock
written into a column read as UTC; a sentinel or cleared value meaning "unbounded" on
one side and "none" on the other, or an explicit clear stored identically to
never-set so clearing silently restores the default; reference equality where value
equality was meant; an enum variant falling through to a default that means something
else; a declared media type that does not match the bytes; a list position, array
index, or rounded coordinate used as a stable identity across regeneration; an
intentional skip returned as the same value as a completed item; a label, caveat,
coverage figure, or freshness stamp computed over a different filter set or window
than the result it annotates; a schema-default sort key colliding with the intended
order.

**Kill it with:** the single definition both sides share, or a test that pins the unit.

### B. A guard with an uncovered path

**Ask:** enumerate every way into and out of the guarded region. Which path skips the
check — and which legitimate caller does the check now wrongly reject?

**Shapes:** a validator that fails open on error, empty result, missing file, or
unparsed input; an oracle — or a test, eval, or verification query — whose pass
condition proves a proxy (name exists, keyword present, any recent row) rather than
the property it names; an empty filter that degrades to match-everything instead of
match-nothing; a presence check written as truthiness, so `0`, `""`, `false`, or a
deliberately cleared value takes the absent branch; a nullable column compared with
`= false` or `!= x`, silently dropping NULL rows; a `catch`/`except` naming a type the
library does not raise here, so the intended retry or park never runs; a null reaching
the use on one branch; authorization derived from a client-supplied identity, or
evaluated on the impersonated user where the real actor was meant; a resource released
only on the happy path; a flag set on one event and cleared only on another; a busy
lock covering the submit buttons but not the paths that unmount the form; a
`continue`/skip that omits the bookkeeping write the main path performs; an
already-ran guard that short-circuits some of a rerun's effects but not others; a
newly tightened guard that now rejects service jobs, admin flows, or NULL-session
callers.

**Kill it with:** the guard on that specific path, or the type that makes the bad
value unrepresentable.

### C. Stale state — what was read is not what exists

**Ask:** between the moment this state was captured and the moment it is used, what
else can change it?

**Shapes:** state captured before an `await` and used after; an async result applied
without checking that the session, file, or key it was requested for is still the
current one; a ref or cache read by a same-turn callback that only updates on the next
render; a later pipeline pass judged against the original input rather than what
earlier passes left behind; a gate on one async source while reading from another that
resolves separately; a draft or expansion flag keyed to an identity that changed
underneath it; a reset performed in an effect, so the first paint still shows the
previous state (a leftover *armed* destructive confirm is the dangerous case); a
terminal or in-flight marker never cleared on the early-return path, so the flow
cannot be re-entered; a write that invalidates the query it obviously affects but not
the sibling views computed from the same rows; a process-global reset by an older
instance's teardown; a cache with no invalidation on logout, tenant switch, or
permission change; a checkpoint written from a snapshot taken before an abort.

**Kill it with:** the mechanism that re-reads, re-keys, or invalidates.

### D. A partial population treated as complete

**Ask:** is the set this operates on the whole set, and what happens to the members
outside it?

**Shapes:** an aggregate computed over page one of a paginated read; a per-page
reduction where whole-set semantics were intended; a ratio whose denominator is itself
filtered, so a handful of unrepresentative members decide the gate; a cap applied
*before* the filter that should have preceded it, so the eligible tail never makes the
window; a cap that drops the tail while a cursor advances past it anyway; a dedupe or
group-by that keeps one member wholesale and discards fields only the others carried;
a group whose members are all excluded producing no row at all, leaving a stale prior
value reading as current.

**Kill it with:** the loop that exhausts the source, or explicit handling of the
excluded remainder.

### E. Duplicated truth

**Ask:** what else in the repo encodes this same fact or rule, and did the change
update all of them?

**Shapes:** a default in the client and again in a database function; a default,
constraint, or normalization enforced only in the ORM or application layer and
bypassed by raw SQL, a bulk insert, or a migration that writes the table directly; the
same predicate in a badge and in the filter it describes; a string key duplicating a
schema field name, where the two disagree and the lookup silently returns its default,
leaving the branch dead; docs or a runbook naming an enum value the schema rejects; a
new route, action, or endpoint added outside the matcher, middleware, or capability
gate that covers its neighbours; a validation, normalization, or masking step present
on one path and missing from its sibling; a scheduled wake-up computed from a boundary
the predicate it triggers evaluates strictly, so the run it schedules changes nothing;
a precedence order that disagrees between two levels of aggregation; a predicate
computed over merged inputs and then applied to each subset separately.

**Kill it with:** a grep for the old literal or rule showing every copy changed — or
showing there is only one.

### F. Failure that does not degrade

**Ask:** for each way this can fail, what does the caller observe, and what state is
left behind?

**Shapes:** returning success because a local precondition holds while the remote step
failed; error conflated with empty, so a transient failure renders as "nothing here";
still-loading conflated with a real default; an access or capability lookup that falls
back to a permissive default when the lookup itself fails; a memoized promise, client,
or cache entry that stores its own rejection, making one transient failure permanent;
a recovery or repair handler whose own I/O can throw and take the whole operation
down; a fallback that re-issues work the primary already retried to exhaustion,
unpaced and concurrent; a retry counter incremented past its cap, so the re-armed row
can never be selected again; a drain loop whose exit depends on rows leaving the
selection, so one permanently failing item spins forever; an irreversible external
effect (mail, webhook, payment, label) issued before the local row that records it
commits; a destructive consume (pop, clear, mark-done) before the dependent operation
commits; a fire-and-forget write whose loss is invisible; one source's error gating
another's error UI, so nothing is shown at all.

**Kill it with:** the branch that surfaces, retries, or compensates for it.

### G. Ordering assumed rather than enforced

**Ask:** what ordering does this depend on, and what actually guarantees it?

**Shapes:** read-then-write across two statements with no transaction or atomic
update; two async runs writing the same slot with no sequence or generation check, so
the slower earlier one lands last; a `max`, `sort`, or window function over a key that
ties in practice, the winner decided by input order; a client documented as not
thread-safe shared across a pool; two jobs that each reconcile the same table
destructively, so each deletes rows the other owns; a fixed sleep or cron offset
standing in for a signal; a dismissal handler committing an action while the click
that dismissed it also fires; a mutation issued twice because only the UI guard
exists; a gate false on first render and set in a later effect; two processes on
independent schedules whose windows can overlap; a controller driven synchronously
during a parent's rebuild.

**Kill it with:** the lock, transaction, idempotency key, explicit sequencing, or
single-threaded guarantee.

### H. Blast radius not followed

**Ask:** what outside this change depends on what the change altered?

**Shapes:** a changed signature, nullability, or return shape with callers left on the
old contract; a test double or fixture still returning the old shape, so the suite
passes vacuously; a removed or renamed field still read by persisted rows or older
clients; a migration whose `CASCADE` reaches tables nobody enumerated, or whose window
misses concurrently written rows; an already-applied migration or one-shot script
edited in place, so every database stamped at it never receives the change; `ON
CONFLICT DO UPDATE` leaving unset columns stale, or `DO NOTHING` where the row's values
must be refreshed; two migration revisions sharing a parent, so `upgrade head` fails; a
DDL lock held across a long backfill in the same transaction; a reset or backfill that
misses the columns the selection predicate actually reads, so the rows it meant to
re-arm stay excluded; a helper whose name promises a narrower scope than what it
deletes; a new node added to a pipeline or graph but not to the job, schedule, or
selection that must materialize it; a key or namespace that now collides with another
environment, whose cleanup then deletes what it does not own; a composite key whose
missing components default to the empty string, collapsing unrelated items into one
bucket; a navigation target that drops the scope the current view implies; a pinned
tool version that lacks the config keys the change uses.

**Kill it with:** an enumeration of the dependents, each shown handled.

## Keeping this bounded

The eight classes are the whole semantic taxonomy and are meant to stay eight. When a
bug turns up that this file did not catch, the fix is almost never a new row.

1. **Express it as an instance of an existing class**, adding one clause to that
   class's *shapes* list only if the shape is genuinely absent. Shapes are evidence.
2. **If it fits no class, name the invariant it violates in one sentence first.** A
   ninth class must be a *kind* of wrongness, not a *situation*: "the value doesn't
   mean what the consumer thinks" is a kind; "this linter's allowlist fields default
   to OR" is a situation, and belongs in a stack reference or nowhere.
3. **Stack- and library-specific instances go in `references/<stack>.md`**, never here.
4. **Budget:** constructs stay language-level; classes stay eight; this file stays
   under ~3,000 words (`wc -w`). Past that it stops being a method and becomes a
   checklist, and a checklist gets skimmed instead of worked. Merge or delete before
   adding — prefer widening an existing clause to appending a new one.

The test for any addition: **would this line change what a reviewer does on a diff it
has never seen?** If it only describes a bug that already happened, it is a corpus
entry, not a seed.

## Backward slicing

Use when the question is *"can this value be bad at this point?"*

1. Identify the variable and the exact line.
2. Find every assignment reaching it — locally, then parameters, then fields.
3. For parameters, go up to every caller. `rg -n "functionName\("` and read each hit.
4. Collect every guard on each path: null checks, early returns, asserts, type
   narrowing, boundary validation, schema parsing.
5. The finding survives only if **at least one complete path** exists from an entry
   point to the seed with no guard on it. Name that path.

Stop conditions that kill the finding: the type system forbids the bad value; a
validator at the boundary rejects it; every caller passes a literal or guarded value.

## Forward slicing

Use when the question is *"is this always released / committed / awaited / cleaned up?"*

1. Identify the acquisition point.
2. Enumerate every exit from the enclosing scope: normal return, each early return,
   each `throw`/rejection, cancellation, and the framework's teardown path.
3. Check each exit for the matching release. `finally`, `defer`, `using`, `dispose()`,
   framework auto-cleanup.
4. The finding survives only if at least one exit path is missing the release.

A single missing exit path is enough — but you must name it.

## Cross-file tracing: practical commands

```bash
rg -n "\bsymbolName\b" --type dart --type ts     # all references
rg -n "symbolName\s*\(" -A3                      # call sites with context
rg -n "class\s+ClassName|interface\s+ClassName"  # definition
git log -p -S "symbolName" -- path/              # when/why it changed
git diff main...HEAD --stat                      # blast radius of the branch
```

Prefer an LSP / "go to references" if the environment has one — grep misses dynamic
dispatch and over-matches common names.

## Blast radius heuristic

Rank where to spend effort:

1. Callers of changed public functions (highest yield — the bug is usually here)
2. The changed lines themselves
3. Persistence and serialization touching changed shapes
4. Tests modified in the same diff (a test edited to accommodate new behavior often
   documents a regression the author rationalized)
5. Anything the diff *deleted* — deletions are under-reviewed and remove guards
