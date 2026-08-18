# Python backend failure modes — SQLAlchemy, Alembic, asyncio, pooled workers

For Python services, data pipelines, and orchestrators. Apply as seeds, then trace and
falsify. A pattern match is a question, not a finding.

## Where the language itself hides the defect

- **`except SomeError` that the library does not raise here.** Python's exception
  hierarchy is not a contract you can infer from names. `httpx.TimeoutException` is not
  a `TimeoutError`; `pytz`'s `AmbiguousTimeError` / `NonExistentTimeError` are not
  `ValueError`; `requests` can surface a read timeout as `ConnectionError`. When the
  handler exists to mark work *transient and retryable*, a missed type silently
  reclassifies it as permanent. Read the library's raise sites, and diff sibling
  handlers — when two workers disagree on which errors are transient, one is wrong.
- **A broad `except Exception` upstream of a narrower handler that mattered.** It
  swallows the signal a sibling deliberately re-raises.
- **Indentation as control flow.** A `break`, `continue`, or `return` at the loop's
  indentation level rather than inside its `if` makes the loop single-pass or the
  branch dead. Same for a dedented `else` that becomes a `for ... else`.
- **Truthiness on config and cursors.** `if os.getenv("FLAG")` is true for `"0"` and
  `"false"`; `os.getenv("X", default)` does not apply the default to an *empty* value;
  `str(v) if v else None` writes NULL for a legitimate `0`.
- **`.get()` on something that is not a dict** — a Pydantic model (v2 models have no
  `.get`), a JSON body that parsed to a list or string, a driver column that arrives
  already deserialized. Also `d.get(k, default)` returning `None` when the key exists
  with a null value, then handed to a function that assumes `str`.
- **A dict key that no schema emits.** After `model_dump()`, a lookup keyed on a field
  name the model does not define returns the default forever, and the branch behind it
  is dead code. Grep the model definition for the literal key.
- **Naive vs aware `datetime`.** `datetime.now()` without `timezone.utc`, compared or
  written against a `timestamptz` column; `localize()` on an already-aware value;
  a `.isoformat()` string assigned to a `datetime` field.

## SQLAlchemy

- **Client-side `Column(default=...)` is not applied by multi-row Core inserts**, nor
  by raw SQL, nor by a migration writing the table directly. Any NOT NULL column whose
  value lives only in the ORM breaks the moment something else writes the row.
- **`session.commit()` ends the transaction and resets connection-level execution
  options**, including an isolation level the caller set. Committing mid-iteration over
  a result set can also invalidate the cursor.
- `text()` binding: a Python list in `IN :param` does not expand without
  `bindparam(expanding=True)`; `$1`-style placeholders are not SQLAlchemy syntax;
  a `dict` into a JSON column needs a typed bind.
- `.scalars()` on a multi-column `select` silently keeps only the first column.
- `Row` objects are not hashable — building a `set` of them raises at runtime.
- Lazy resource init (`if self._client is None: self._client = ...`) inside a
  thread-pooled resource is a check-then-set race.
- Relationship access inside a loop without `joinedload`/`selectinload` — correctness
  only when the session may already be closed or the attribute is expired.

## Alembic and schema changes

- **Editing a revision that has already been applied somewhere.** Adding DDL to an
  existing revision, or re-parenting `down_revision`, leaves every database stamped at
  that revision permanently missing the change while `upgrade head` reports success.
  New behavior needs a new revision id. Check the docstring's `Revises:` against the
  `down_revision` variable — a mismatch is the same defect in miniature.
- Two revisions sharing a `down_revision` — `upgrade head` fails on multiple heads.
- `op.add_column` with `autoincrement=True` does not emit `SERIAL` or a sequence
  default; an integer PK added this way rejects inserts that omit the column.
- `default=` in a migration is Python-side only; a database-level default needs
  `server_default=` (and enum literals must be quoted).
- Adding a NOT NULL column without `server_default` breaks every raw-SQL insert
  elsewhere in the repo that does not name it — grep for inserts into that table.
- `downgrade()` that mirrors `upgrade()` in the same order rather than the reverse:
  dropping a column before its foreign key, or a schema before its tables.
- A unique constraint or partial index over a **nullable** column does not enforce
  uniqueness in PostgreSQL — NULLs are distinct.
- A backfill that resets a status column but not the retry counter, timestamp, or
  watermark the selection query also filters on. Read the selection predicate, then
  check every column it names.

## Pools, processes, and pipelines

- `ProcessPoolExecutor` without `mp_context=spawn` on Linux: forked workers inherit
  locked mutexes from a multithreaded parent and deadlock. If one call site sets it and
  another does not, the inconsistency is the finding.
- Arguments to pool workers must be picklable — compiled matchers, sessions, and
  closures are not.
- `as_completed` loops without a global bound, or per-future and global timeout limits
  configured so the global one always trips first, turning a handled timeout into an
  unhandled error.
- A worker's own error handling bypassed by work done *before* its `try` — the
  download, the client construction, the parse.
- A trigger, sensor, or schedule whose predicate is narrower than the work the job it
  starts performs, so a backlog of the uncounted kind never runs.
- A node added to the graph but not to the job selection or schedule that materializes
  it — the definition loads clean and the asset simply never runs.
