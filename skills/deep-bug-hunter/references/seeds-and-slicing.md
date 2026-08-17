# Seeds and Slicing

## Why seeds

Open-ended search ("find bugs") has no stopping condition, so it terminates when the
model runs out of enthusiasm — which is exactly when it starts inventing. Seed-based
search is bounded: enumerate the constructs where defects actually concentrate, and
each one poses a *closed question* that reading code can answer yes or no.

Work the seed list against the diff and its immediate blast radius. Ignore seeds in
untouched code unless a changed contract reaches them.

## Seed taxonomy

Each seed is a construct plus the question it forces you to answer.

| Seed | Question to resolve by reading |
|---|---|
| Indexing / slicing (`a[i]`, `.substring`, `.first`, `[0]`) | Can the collection be empty, or the index out of range, at this point? |
| Division / modulo | Can the divisor be zero? |
| Non-null assertion (`!`, `as`, `unwrap`, `!!`, non-null cast) | Is there a path where the value is null here? What made the author sure? |
| `await` / async boundary | What state was captured before it? Is it still valid after? Is the future awaited at all? |
| Resource acquisition (open, subscribe, listen, allocate, connect, controller construction) | Is release guaranteed on *every* exit path, including throw and early return? |
| `catch` block | Is the error swallowed? Is the caught type too broad? Does the recovery path leave partial state? |
| Loop with a mutable accumulator or index | Boundary: first iteration, last iteration, empty input, single element. |
| Comparison / boundary operator (`<` vs `<=`) | Is the endpoint inclusive or exclusive, and does that match the caller's assumption? |
| Write path (update, delete, upsert, file write) | Is it scoped? Is it in a transaction with the reads it depends on? Is it idempotent under retry? |
| External input reaching a sink (query, shell, path, HTML, redirect) | Is it validated at *this* boundary, or is validation assumed to have happened elsewhere? |
| Authorization-relevant handler | Is there an actual check, and does it use server-derived identity rather than a client-supplied ID? |
| Money / quantity arithmetic | Integer or float? Rounding direction? Can it go negative? |
| Cache / memo write | What invalidates it? Can it serve data across a permission or tenant boundary? |
| Retry, timeout, or reconnection logic | What happens if the operation actually succeeded but the response was lost? Does a fallback path re-issue the work *after* the primary already exhausted its own retries — unpaced and concurrent — re-tripping the same rate limit it was meant to escape? |
| Signature change in the diff | Every caller — updated or not? Argument order, optionality, nullability, thrown types. |
| Removed or renamed field | Every reader — including serialized data already in the database, and clients on older versions. |
| Feature flag / conditional new path | Does the *other* branch still work? Is the flag read consistently? |
| Comparison of objects/structs | Reference or value equality? Does the type implement equality? |
| Date/time arithmetic | Timezone, DST, epoch units (s vs ms), and clock source. |
| Ratio / majority / fraction gate (`count/total >= threshold`) | What population does the denominator actually represent? If it is filtered (opaque-only, non-null-only, valid-only, non-deleted), can the filter shrink it until a handful of unrepresentative samples decide the gate? Checking `total >= 1` is not enough — is there a minimum *absolute* sample size? |
| Later stage of a multi-pass pipeline over shared mutable data | What did the earlier passes already do to this data? Judge this stage's guards, sampling, and thresholds against the mutated state it actually receives — a stage verified in isolation against the original input can be broken by whatever ran before it. |
| Validator / checker / gate code (CI check, verification script, parser, contract extractor) | What input makes it pass when it shouldn't? Enumerate the fail-open paths — error/exception, empty result, missing file, unparsed or unrecognized syntax, silently filtered-out item — and ask whether the oracle proves the property or only a proxy (name exists, keyword present, any recent row). A guard that can silently skip is a guard that isn't there. |
| Checkpoint / cursor / high-water mark write | Can it advance past data that was skipped, capped, aborted, or failed? Is draining a durable pending queue gated on the success of an unrelated step, so one failure strands the queue? |
| Success signal (`return true`, success UI, completion state) | Enumerate the partial states — error, aborted, still-loading, empty-because-error — and confirm each reaches the failure path instead of being conflated with success or empty. A `?? default` on a value that is null while loading or errored counts. |
| Paginated or limit-capped read feeding a decision or aggregate | Computed over all pages or just the first? Does a per-page reduction (`--paginate` piped into `group_by`/`last`) break whole-set semantics? What happens to items beyond the cap? |
| Constant, default, or predicate defined in more than one place (client + SQL function, two screens, doc + schema, code + config) | Did the diff update every copy? Grep for the old literal value before clearing this. |
| New variant / route / branch added to an existing flow | Is every parallel registry, allowlist, exemption list, switch default, and sibling path updated? If the change skips or bypasses a step, which side effects only fired inside that step? |
| Process-global mutable state (static field, singleton, module-level cache) | Who else writes or resets it? Can teardown of an old instance clobber state a newer instance already installed? |
| Fixed sleep, cron offset, or single poll used as synchronization | What happens when the other side is slower than the delay? |
| Destructive consume (pop, clear, mark-done, dequeue) | Does it happen before the operation that needs the value commits? A failure after the consume loses the item permanently. |
| Migration or backfill touching existing rows | Are `ON DELETE CASCADE` chains reachable from the statement enumerated? Can rows written concurrently with the migration window be missed by both old and new paths? On `ON CONFLICT DO UPDATE`: which columns are *not* set, and what stale state survives? Does the backfill's completeness predicate match the runtime check's? Does this revision share a parent (`down_revision`) with another, leaving the history with two heads so `upgrade head` fails on deploy? Does a DDL statement take a heavy lock that is then held for the whole transaction while a long data backfill runs in the same migration? |
| Guard added or tightened (auth, version floor, validity check) | Enumerate existing legitimate callers — service jobs, internal/admin paths, NULL-session owner connections — that now fail. Over-restriction is a bug too. |
| Ordering relied on without an explicit sort, or a sort key with a schema default | Is the order guaranteed by a query or comparator, or merely incidental? Do default/sentinel values (0, empty string) collide with the intended ordering? |
| Tool / config invocation (pinned versions, config keys, env vars) | Does the pinned tool version support the keys and flags used? Are field-combination default semantics what the author assumed (OR vs AND)? Is every env var the code reads actually set in the environment that runs it? |
| Count, total, or aggregate that reaches a label, badge, API result, or another count | What is *one unit* of this number — an entity, or a pair/join row? Does every consumer (label, tooltip, sum, caller) mean the same unit, and are two different units ever added together? Does a returned count report rows *attempted* rather than rows actually written (pre-dedupe input length vs merge result)? If the query was scoped or filtered, is the result being used as if it were global? |
| Grouped aggregate or snapshot rebuild | What does a group whose every member is excluded produce — a zero row, or no row at all? If no row, does a stale prior value survive in the destination and read as current? |
| Label, tooltip, header note, or caveat that makes a factual claim about the data it sits next to | Does the claim hold on *every* branch and state that renders it — the other enum values, the pending/rejected variants, the sibling conditional that also shows this text? Is the caveat attached to the clause it actually qualifies? (This is not a wording preference: the test is whether the text asserts something the data contradicts.) |
| Local, draft, or expansion state derived from a prop, selected entity, or modal open | Is it reset — or the component re-keyed — when that identity changes (row switch, tenant/company switch, modal reopen)? Does it resync when the source prop changes underneath an open editor? Is the reset done in an effect, so the first paint after reopen still shows the previous state (a leftover *armed* destructive confirm is the dangerous case)? |
| Render gated on one async source while reading from another | Which query does each gate actually observe? Can an unrelated source's error hide data that loaded fine, or gate the error UI and its retry control behind a query that never settles? Does an imperative `refetch()` run a query that was deliberately `enabled: false`? |
| Navigation target, link href, or "reset to default" action | Does the target carry the scope, filters, and query params the current view implies, or drop them? Can it land on an empty or unreachable state — a hub with nothing in scope, an editor that filters out the very option the CTA offered? Does "reset" restore the deep-link-forced default, or a hardcoded one? |
| Derived key, slug, tag, or branch/namespace name | Can two distinct inputs normalize to the same key (every non-alphanumeric replaced by one separator)? Does the namespace overlap another environment's, so this system's cleanup deletes resources it does not own? |
| Cleared / empty value in a filter, limit, or bulk-action control | Does empty mean "no constraint" (match everything) or "match nothing"? Confirm which the query does, and what the control's label implies — on a bulk destructive action these differ by the whole table. |
| In-flight mutation whose form or control lives inside a filterable, searchable, or paginated list | Does the busy guard cover every path that can unmount the form mid-write — filter change, search keystroke, navigation — or only the submit buttons? |
| Predicate, precedence order, or classification computed once over merged inputs, then applied per subset | Does it agree at every level it is applied (pair vs entity, per-kind vs combined)? Dismissing or resolving one kind must not clear or retain the other's. |
| Early-return / `continue` / skip path inside a loop that also writes bookkeeping | Which side effects does the non-skip path perform that the skip path omits — link rows, annotations, counters, audit records? A skipped item that silently loses its linkage breaks later cleanup that relies on it. |
| Recovery, repair, fallback, or error-handler path that itself performs I/O | What happens when *it* fails? An unguarded await inside a repair hook turns a recoverable error into a failed request. Is the caller's cancellation/abort signal threaded into this call too, or does it keep running (and billing) after the user cancels? |
| Dismissal handler (outside-press, blur, escape) that commits a side effect | Enumerate the event ordering when the click that dismisses also lands on another control: does the dismissal commit an action the user was in the middle of replacing? Is a guard flag set on `pointerdown` cleared on *every* path, including dismissals that never produce a click? |

## Backward slicing

Use when the question is *"can this value be bad at this point?"*

1. Identify the variable and the exact line.
2. Find every assignment reaching it — locally, then parameters, then fields.
3. For parameters, go up to every caller. `rg -n "functionName\("` and read each hit.
4. Collect every guard on each path: null checks, early returns, asserts, type
   narrowing, validation at a boundary, schema parsing.
5. The finding survives only if **at least one complete path** exists from an entry
   point to the seed with no guard on it. Name that path.

Stop conditions that kill the finding: the type system forbids the bad value; a
validator at the boundary rejects it; every caller passes a literal or a guarded
value.

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
4. Tests that were modified in the same diff (a test edited to accommodate new
   behavior often documents a regression the author rationalized)
5. Anything the diff *deleted* — deletions are under-reviewed and remove guards
