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
| Retry, timeout, or reconnection logic | What happens if the operation actually succeeded but the response was lost? |
| Signature change in the diff | Every caller — updated or not? Argument order, optionality, nullability, thrown types. |
| Removed or renamed field | Every reader — including serialized data already in the database, and clients on older versions. |
| Feature flag / conditional new path | Does the *other* branch still work? Is the flag read consistently? |
| Comparison of objects/structs | Reference or value equality? Does the type implement equality? |
| Date/time arithmetic | Timezone, DST, epoch units (s vs ms), and clock source. |

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
