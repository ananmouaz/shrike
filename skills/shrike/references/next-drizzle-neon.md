# Next.js / TypeScript / Drizzle / Neon failure modes

Apply as seeds, then trace and falsify. A pattern match is a question, not a finding.

## Server/client boundary

- **Secret leakage into the client bundle.** A module reading `process.env.SECRET`
  imported (transitively) by a `'use client'` component, or a secret passed as a prop.
  Trace the import chain. Critical when confirmed.
- Server-only code (`db`, `fs`, node builtins) reaching a client component — usually a
  build error, sometimes a runtime one in edge runtime.
- Data passed from a server component to a client component that includes fields the
  user should not see. Serialized props are visible in the HTML payload. Check what
  the query actually selects, not what the component renders.
- `'use server'` action treated as trusted: **server actions are public HTTP
  endpoints.** Every action needs its own authz check and input validation regardless
  of which component calls it. A check in the calling page is not a check.

## Auth and authorization

- Route handler / server action with no authz check at all — enumerate every handler
  in the diff.
- Trusting a client-supplied user or tenant ID instead of deriving it from the session.
  Backward-slice the ID used in the `where` clause to its origin. If it came from the
  request body or a query param, that is an IDOR. Critical.
- Middleware assumed to protect a path that its matcher does not actually cover —
  read the `matcher` config and compare it against the route.
- Authz check present but the query does not scope by it (checked `isAdmin`, then
  queried without a tenant filter).

## React / async

- `useEffect` fetch without cleanup or `AbortController` — out-of-order responses
  overwrite newer data. Requires a realistic ordering scenario to report.
- Stale closure in a callback with a wrong or empty dependency array, where the
  captured value is used to compute something written back.
- **`router.refresh()` refreshes server props while local `useState` does not.** A
  form initialized from props keeps the pre-refresh value; if a concurrency guard is
  computed from the *fresh* props and the payload comes from the *stale* state, the
  guard passes and writes the stale value back — the check certifies the write it
  should have blocked.
- **`x || fallback` on numeric or boolean edit defaults.** A stored `0` or `false`
  takes the fallback, so opening a form and saving it without changes silently rewrites
  the value. Use `??`, and check what the field's zero legitimately means.
- **Optimistic override map consulted by truthiness.** `overrides[id] || server` erases
  a legitimate `0`, `""`, or `false` the user just set; and an override never cleared on
  refetch keeps showing the local value after the server has recorded a newer decision.
  Test presence with `id in overrides`, and clear on the refetch that supersedes it.
- **A `describe*` / `summarize*` / `diff*` helper used as a save gate.** A headline
  differ that skips nested or per-item fields reports "no changes" for an edit made in
  a raw JSON view, so Save stays disabled or the payload is dropped. Ask what the
  helper omits before accepting it as the predicate.
- State update after unmount on an async resolution.
- Missing `await` on a promise whose completion the next statement depends on;
  unhandled rejection in a route handler taking down the request.

## Drizzle

- **`update` or `delete` without `where`**, or with a `where` that does not constrain
  by owner/tenant. Mass-mutation risk. Critical. Also check dynamically-built
  conditions: an `and(...conditions)` where `conditions` can be empty produces an
  unscoped statement.
- Multi-statement invariants without `db.transaction` — the classic being "check
  balance, then deduct". Read-then-write across two statements is a race unless it is
  in a transaction with appropriate isolation, or done in a single atomic statement.
- N+1: a query inside a `for`/`map` over rows. Report only with a realistic row count;
  otherwise it is a performance opinion.
- Join with a missing or wrong condition producing a cross product, or a `leftJoin`
  whose null right side is dereferenced without a check.
- `.returning()` omitted where the caller uses the result; result shape assumed to be
  a single object when the API returns an array.
- Raw SQL (`sql\`\``) built by string interpolation of user input rather than
  parameter placeholders — injection. Check whether the value is interpolated into the
  template or passed as a parameter.
- Unbounded query with no `limit` on a table that grows without bound.
- Schema/migration mismatch: a column added in the schema file with no migration, or a
  non-nullable column added without a default against a populated table.

## Postgres functions / RPC (Supabase-style)

- **`SECURITY DEFINER` without `SET search_path`.** Unqualified table references inside
  the function can be shadowed by caller-created temp tables — privilege escalation.
  Check every definer function in the diff for an explicit `SET search_path`.
- **Definer RPC callable by any authenticated user** with no caller-identity check
  inside the function body. The GRANT is the exposure; the check must be internal
  (`auth.uid()` compared against the row owner), not assumed from the client.
- **The same eligibility rule in two SQL functions**, a checker and the mutation that
  should agree with it. Tightening one and leaving the other on the weak predicate
  lets the mutation pass what the checker rejects. `rg` every function referencing the
  column; a comment saying they match is not evidence — read both bodies.
- **A predicate in SQL and its twin in TypeScript disagree at the edges.** `coins > 0`
  accepts `0.25` where `Math.round(coins) > 0` rejects it. `NULL > 0` is `NULL`, so
  `WHERE NOT (coins > 0)` drops NULL rows entirely while the JavaScript `!(coins > 0)`
  is `true` for `null` and keeps them. `numeric` compares exactly; the `number` that
  read it is a float. Put both texts in the parity row and walk `0`, `0.5`, `null`,
  empty and max across each.
- **Guard tightened to require a JWT** breaking legitimate NULL-JWT callers — owner
  connections, service-role jobs, admin approval flows. Enumerate the non-user callers
  before clearing a new auth guard.

## Neon / serverless Postgres

- Connection created per request without pooling, or a pooled client held across
  invocations in a way the runtime does not support. Check which driver is imported
  (`@neondatabase/serverless` HTTP vs a pooled TCP client) and whether transactions are
  even supported on that path — the HTTP driver does not support interactive
  transactions, so a `db.transaction` on it is a real defect.
- Long-running transaction in a function with a short execution limit.
- Cold-start work inside the handler that assumes warm state from a previous
  invocation (module-scope caches are not guaranteed to persist).

## TypeScript

- `as` / `as any` / `as unknown as` hiding a shape mismatch that becomes a runtime
  `undefined` access. Backward-slice to what the value actually is.
- Non-null `!` on something that can be absent (array `.find()`, `Map.get`,
  `params` lookups, env vars).
- Zod/valibot schema and the TS type drifting apart — the schema is what runs.
- `JSON.parse` results treated as typed without validation.
- **An ISO shape plus a non-`NaN` `Date` is not calendar validation.** V8 rolls
  `2026-02-30` and `2026-13-01` over into valid dates, so a regex-and-parse check
  accepts days that do not exist. Compare the parsed components back to the input.
- Optional chaining that silently produces `undefined` where a default was intended,
  then flows into arithmetic (`undefined + 1` → `NaN`) or a query.
- **`Number`, `parseFloat` and `parseInt` disagree on the same string.** `Number('')`
  and `Number('  ')` are `0`, so an empty field reads as a real zero; `parseFloat('1,5')`
  is `1`, silently truncating a comma decimal that `Number('1,5')` rejects as `NaN`; and
  `parseInt` stops at the first non-digit, so `parseInt('5kg')` is `5`. In the
  normalisation sweep, name which one the code calls before recording its outputs.

## Money, counters, idempotency

- Currency or point balances in floating point — use integer minor units. High.
- Increment implemented as read-modify-write in application code rather than an atomic
  SQL update. Concurrent requests lose updates.
- **Optimistic concurrency via a version column, with a writer that does not bump it.**
  The guard can only detect writes that touch the version, so a partial write path (a
  kill switch flipping one column, a background reconciler) is invisible to it and gets
  overwritten by the next guarded save. Enumerate every writer of the row, not every
  reader of the version.
- Webhook or payment handler with no idempotency key — replays double-apply. Critical
  in a rewards/payments context.

## Deterministic tools to run first (Phase 0)

```bash
npx tsc --noEmit
npx eslint . --max-warnings=0
npm test
npx drizzle-kit check    # if the project uses it
```

Do not report anything these tools already emit.
