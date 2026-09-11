# Seeds and Slicing

## Why seeds

Open-ended search ("find bugs") has no stopping condition, so it terminates when the
model runs out of enthusiasm — which is exactly when it starts inventing. Seeded
search is bounded: each seed poses a *closed question* that reading code answers yes
or no, and when the seeds are worked the pass is done.

Two layers, different jobs. **Constructs** are the grep layer: syntax found
mechanically and finite — one question *per instance*. **Invariant classes** are the
reasoning layer: eight kinds of wrongness, one question *per change*. The distinction
decides recall: a class answered once clears a diff carrying nine unread instances of
a construct.

Work both against the diff and its blast radius. Ignore untouched code unless a
changed contract reaches it.

## Layer 1 — Constructs

Mechanical triggers. Find them, then ask the question.

| Construct | Question |
|---|---|
| Indexing / slicing (`a[i]`, `.substring`, `.first`) | Empty collection or index out of range? If the index is held across an await or refetch, can the list reorder under it? |
| Division / modulo | Can the divisor be zero? |
| Non-null assertion (`!`, `as`, `unwrap`, `!!`) | Is there a path where the value is null? What made the author sure? |
| `await` / async boundary | What state was captured before it, and is it still valid after? Is it awaited at all? |
| Resource acquisition (open, subscribe, listen, connect) | Is release guaranteed on every exit, including throw and early return? |
| `catch` block | Swallowed? Caught type too broad? Partial state left behind? |
| Loop with a mutable accumulator or index | First, last, empty, single element. If it skips members and returns a scalar, does the caller act on the whole set? |
| Boundary operator (`<` vs `<=`) | Inclusive or exclusive, does that match the caller's assumption, and if it is a range, is the pair validated as ordered? |
| Truthiness or nullish check (`if (x)`, `x ?? d`, `if x:`) | Can the value legitimately be `0`, `""`, `false`, or explicitly cleared — and does the absent branch then swallow it? |
| `catch` / `except` on a named error type | Does the library actually raise *that* type on this path, or a sibling that escapes the handler? |
| String comparison used as identity (equality, `in`, regex, key construction) | Same case, anchoring, normalization, and null handling on both sides of the comparison? |
| Normalizing / stripping transform (`trim`, `tr -d`, `replace`, slug) | Does it strip only the edge or wrapper it was meant to, or every occurrence anywhere in the value? |
| Optional chain or safe-navigation followed by more access (`a?.[k].m()`, `a?.b.c`) | Does the guard cover the *whole* path, or does it short-circuit one link and then dereference anyway? |
| Secret, connection string, or raw upstream response crossing a boundary (client bundle, CI output, log, error body) | Is it meant to be readable there? |
| Write path (update, delete, upsert, file write) | Scoped? Transaction, or write predicate carrying the read state? Idempotent under retry? Who else writes this row between read and write? |
| Effect registration or sink write (`register`, `subscribe`, `addObserver`, `setCustomKey`, `report`) | Is the sink live at this line, and does its only consumer read before or after it? |
| Concurrency token read for a guard (version, etag, sequence, generation) | Does every writer bump it, and does the payload it protects come from the same snapshot as the check? |
| Status or completion write (`delivered_at`, `status = 'done'`, a done latch) | Did the operation confirm the effect landed — for every member the write covers? |
| A test added or changed in the same diff | Would it fail with the production hunk it covers reverted? |
| External input reaching a sink (query, shell, path, HTML, redirect) | Validated at *this* boundary, or assumed validated elsewhere? |
| Authorization-relevant handler | A real check, using server-derived identity rather than a client-supplied ID? |
| Money / quantity arithmetic | Integer or float? Rounding direction? Can it go negative? |
| Cache / memo write | What invalidates it? Can it serve across a permission or tenant boundary? |
| Retry / timeout / deadline / budget | What if the operation succeeded but the response was lost? What runs between the clock starting and the work the budget is for? |
| Signature change in the diff | Every caller updated — argument order, optionality, nullability, thrown types? |
| Removed or renamed field | Every reader, including rows already persisted and clients on older versions? |
| Feature flag / new conditional path | Does the *other* branch still work? Is the flag read consistently? |
| Object / struct comparison | Reference or value equality? Does the type implement equality? |
| Date / time arithmetic | Timezone, DST, epoch units (s vs ms), clock source. |

## Layer 2 — The eight invariant classes

Ask each class's question of the change as a whole. The *shapes* are how that class has
shown up in reviewed code — illustrations to pattern-match against, not a checklist.

### A. Meaning drift — the value does not denote what its consumer assumes

**Ask:** for every value this change produces or consumes, what exactly does it
denote — unit, population, encoding, state — and does every consumer agree?

**Shapes:** join/pair rows counted as distinct entities; two units summed into one
total; rows *attempted* reported as rows *written*; a scoped or filtered result used
as if global; money in floats, seconds vs milliseconds, local wall-clock in a UTC
column; a cleared value stored identically to never-set, or a sentinel meaning
"unbounded" on one side and "none" on the other; reference equality where value
equality was meant, or an index, order, or rounded coordinate used as identity across
regeneration; an enum variant falling through to a default meaning something else; a
declared media type that does not match the bytes; a budget or deadline measured from
a start that includes work it was never meant to cover; an intentional skip returned
as a completed item; a label, coverage figure, or freshness stamp computed over a
different filter set than the result it annotates.

**Kill it with:** the single definition both sides share, or a test that pins the unit.

### B. A guard with an uncovered path

**Ask:** enumerate every way into and out of the guarded region. Which path skips the
check — and which legitimate caller does the check now wrongly reject?

**Shapes:** a validator failing open on error, empty result, or unparsed input; an
oracle proving a proxy (a name exists, a keyword is present), not the property; an
empty filter degrading to match-everything; presence checked as truthiness (`0`, `""`,
`false`, cleared), as a bare null check counting `""` and half-filled records as
filled, as `= false` on a nullable column, or defaulted to the neutral value; a gate
keyed on a lossy projection of what it guards, so an edit its summary cannot describe
reads as no edit; a `catch`/`except` naming a type the library never raises here, so
the retry never runs; authorization from a client-supplied identity, or enforced only by an
affordance the server disagrees with — on permission, limits, or an exit the handler
rejects; a flag or lock cleared on one event only,
missing the paths that unmount or abort; a `continue`/skip omitting the bookkeeping
write the main path performs; an already-ran guard short-circuiting some of a rerun's
effects but not others; a tightened guard now rejecting service jobs, admin flows, or
NULL-session callers.

**Kill it with:** the guard on that specific path, or the type that makes the bad
value unrepresentable.

### C. Stale state — what was read is not what exists

**Ask:** between the moment this state was captured and the moment it is used, what
else can change it?

**Shapes:** state captured before an `await` and used after, or an async result applied
without checking its session or key is still current; a guard reading the source while
the payload reads a local copy of it; a ref read by a same-turn callback that only updates on the next render; a later pipeline pass judged against the
original input, not what earlier passes left; a gate on one async source while reading
another that resolves separately; a draft or expansion flag keyed to an identity that
changed underneath it; a reset performed in an effect, so the first paint still shows
the previous state — a leftover *armed* confirm; a terminal or
in-flight marker never cleared on the early-return path, so the flow cannot be
re-entered; a write invalidating the obvious query but not
the sibling views over the same rows; a process-global reset by an older instance's
teardown; a cache with no invalidation on logout, tenant switch, or permission change;
a checkpoint written from a snapshot taken before an abort.

**Kill it with:** the mechanism that re-reads, re-keys, or invalidates.

### D. A partial population treated as complete

**Ask:** is the set this operates on the whole set, and what happens to the members
outside it?

**Shapes:** an aggregate computed over page one of a paginated read; a per-page
reduction where whole-set semantics were intended; a ratio whose denominator is itself
filtered, so a few unrepresentative members decide the gate; a cap applied *before* the
filter that should have preceded it, so the eligible tail never enters the window; a
cap that drops the tail while a cursor advances past it anyway; a dedupe that keeps one
member wholesale and discards fields only the others carried; the wrong cardinality —
one row assumed where the key permits several, every match written where the first was
meant, `every` used where `any` was; a group whose members are all excluded producing no
row at all, leaving a stale prior value reading as current.

**Kill it with:** the loop that exhausts the source, or explicit handling of the
excluded remainder.

### E. Duplicated truth

**Ask:** what else in the repo encodes this same fact or rule, and did the change
update all of them?

**Shapes:** a default in the client and again in a database function; a default or
constraint enforced only in the application layer, bypassed by raw SQL or a bulk write;
the same predicate in a badge and in the filter it describes; a string that must match
something defined elsewhere — a schema field, a generated cache key, a selector — where
the mismatch is silent: a default returned, a no-op invalidation, a dead branch; a field
the reader keys on that its producers leave unset, so the fallback becomes the norm;
docs, a runbook, or the
change's own description asserting behaviour the code does not implement; a new route or
action added outside the matcher, middleware, or gate covering its neighbours; a
validation, normalization, or masking step present on one path and missing from its
sibling; a wake-up scheduled at a boundary the predicate it triggers evaluates strictly,
so the run changes nothing; a precedence order disagreeing between two levels of
aggregation; a predicate computed over merged inputs then applied to each subset
separately.

**Kill it with:** a grep for the old literal or rule showing every copy changed — or
showing there is only one.

### F. Failure that does not degrade

**Ask:** for each way this can fail, what does the caller observe, and what state is
left behind?

**Shapes:** returning success because a local precondition holds while the remote step
failed, or latching a done-marker on an attempt whose effect never landed, so nothing
retries it; error conflated with empty, so a transient failure renders as "nothing
here"; still-loading conflated with a real default; an access lookup falling
back to a permissive default when the lookup fails; a memoized promise or client
storing its own rejection, making one transient failure permanent; a recovery handler
whose own I/O can throw and take the operation down; a fallback re-issuing work the
primary already retried to exhaustion, unpaced and concurrent; a retry counter
incremented past its cap, so the re-armed row is never selected again; a drain loop
whose exit depends on rows leaving the selection, so one failing item spins forever; an
irreversible effect — mail, webhook, payment, destructive consume — landing before the
row recording it commits; a fire-and-forget write whose loss is invisible, or a batch
result that cannot express per-member outcome, so the caller stamps every member done;
one source's error gating another's error UI.

**Kill it with:** the branch that surfaces, retries, or compensates for it.

### G. Ordering assumed rather than enforced

**Ask:** what ordering does this depend on, and what actually guarantees it?

**Shapes:** read-then-write with no transaction, atomic update, or write predicate
carrying the state the decision was read from; two async runs writing one slot with no
sequence check, so the slower earlier one lands last; a generation guard some writers
never bump, or read fresh while the payload it protects stays stale — the check passes,
the stale write lands; a clear or teardown sequenced before the bump that would drop
in-flight writes; an effect emitted before its sink is initialized, or registered after
its only consumer read — it silently no-ops; a `max`, `sort`, or window over a key that
ties, the winner decided by input order; a client documented as not thread-safe shared
across a pool; a fixed sleep or cron offset standing in for a signal, or two independently
scheduled jobs whose windows overlap over the same rows; a dismissal handler committing an action
while the click that dismissed it also fires; a mutation issued twice because only the UI
guard exists; a gate false on first render and set in a later effect.

**Kill it with:** the lock, transaction, idempotency key, explicit sequencing, or
single-threaded guarantee.

### H. Blast radius not followed

**Ask:** what outside this change depends on what the change altered?

**Shapes:** a changed signature, nullability, return shape, or removed field with
callers, persisted rows, older clients, or test doubles left on the old contract, a
stale double passing the suite vacuously; a dependency bump whose API the call sites no
longer match — renamed field, moved export, vanished config key; a migration
whose `CASCADE` reaches unenumerated tables, whose window misses concurrent writes, or
locks DDL across a backfill; an applied migration or one-shot script edited in place —
databases stamped at it never get it; `ON CONFLICT DO UPDATE` leaving unset columns
stale, `DO NOTHING` where values must refresh; a reset or backfill missing the columns
the selection predicate reads; a helper deleting more than its name promises; two paths merged, the survivor's
failure behaviour reaching the other's callers; a node
added to a graph but not the job that runs it; a key colliding with
another environment's, so cleanup deletes what it does not own, or with unrelated items
on empty-string defaults; a navigation target dropping the current view's scope.

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
4. **If the class already had the shape, the fix is not here at all.** A miss on a
   shape written down verbatim is a discipline failure — patch the workflow that
   failed to *ask* it (see the enumerated sweeps in `SKILL.md` Phase 3), and add
   nothing to this file.
5. **Budget, in the order that binds.** Classes stay eight. **At most 12 shape clauses
   per class, each a phrase, not a sentence (~25 words).** Those two bind: a long list
   gets walked like a checklist, and a verbose shape reads like a finding already
   written, so a superficial match feels like evidence. Per-class words follow from
   them (~175); over that while inside 12 phrase-length clauses, cut words, not shapes.
   Total under ~3,100 (`wc -w`) as a backstop. Merge or delete before adding — widening
   an existing clause beats appending a new one.

The test for any addition: **would this line change what a reviewer does on a diff it
has never seen?** If it only describes a bug that already happened, it is a corpus
entry, not a seed.

## Backward slicing

Use when the question is *"can this value be bad at this point?"*

1. Identify the variable and the exact line.
2. Find every assignment reaching it — locally, then parameters, then fields. For
   parameters, go up to every caller (`rg -n "functionName\("`) and read each hit.
3. Collect every guard on each path: null checks, early returns, asserts, type
   narrowing, boundary validation, schema parsing.
4. The finding survives only if **at least one complete path** exists from an entry
   point to the seed with no guard on it. Name that path.

Stop conditions that kill it: the type system forbids the bad value; a validator at the
boundary rejects it; every caller passes a literal or guarded value.

## Forward slicing

Use when the question is *"is this always released / committed / awaited / cleaned up?"*

1. Identify the acquisition point.
2. Enumerate every exit from the enclosing scope: normal return, each early return,
   each `throw`/rejection, cancellation, and the framework's teardown path.
3. Check each exit for the matching release — `finally`, `defer`, `using`, `dispose()`,
   framework auto-cleanup. One exit missing it is enough, but you must name that exit.

## Cross-file tracing: practical commands

```bash
rg -n "\bsymbolName\b"                # all references
rg -n "symbolName\s*\(" -A3           # call sites with context
git log -p -S "symbolName" -- path/   # when and why it changed
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
