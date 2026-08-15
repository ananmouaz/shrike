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
- Optional chaining that silently produces `undefined` where a default was intended,
  then flows into arithmetic (`undefined + 1` → `NaN`) or a query.

## Money, counters, idempotency

- Currency or point balances in floating point — use integer minor units. High.
- Increment implemented as read-modify-write in application code rather than an atomic
  SQL update. Concurrent requests lose updates.
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
