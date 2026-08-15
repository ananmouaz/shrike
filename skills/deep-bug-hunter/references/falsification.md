# Falsification

This is the pass that separates a useful reviewer from a noisy one. Most of the value
of the whole skill is here.

Switch persona completely. In Phases 1–3 you were looking for problems. Here you are a
senior engineer who thinks the reviewer is wrong and intends to prove it. Read each
candidate as if a colleague you find slightly annoying wrote it.

## Procedure

For each candidate, in order:

1. **Restate it as a falsifiable claim.** "On input X, line N does Y, which is wrong."
   If it cannot be stated this way, it is not a bug — it is an opinion. Delete.
2. **Generate the strongest rebuttal**, not a token one. Ask: what would have to be
   true for this code to be correct? Then go look for that thing.
3. **Go read the code that would contain the rebuttal.** Not reason about it. Read it.
4. **Verdict.** Rebuttal found → delete. Rebuttal ruled out by reading code → survives
   as Confirmed/Probable. Rebuttal could not be checked → the candidate is at most
   Probable, and the unchecked rebuttal must be named in the report.

## Standard rebuttals to check

- **Guarded upstream.** A caller, middleware, validator, or schema parse already
  rejects the bad input. Check the actual boundary, not the nearest function.
- **Unrepresentable.** The type system, an enum, or a branded type makes the bad value
  impossible. Nullability annotations count if the language enforces them.
- **Unreachable in practice.** The dangerous path requires a caller that does not
  exist. Enumerate the callers before claiming this — and note that "no caller today"
  is weak for exported/public API.
- **Framework handles it.** The runtime disposes it, retries it, wraps it in a
  transaction, cancels it on unmount, or guarantees ordering. Confirm the specific
  guarantee; do not assume one exists because it usually does.
- **Already tested.** A test covers this exact case. Find it and read it — a test with
  a matching *name* that does not actually assert the behavior is not a rebuttal.
- **Intentional.** A comment, a config, or a domain rule says this is deliberate. If
  intentional but still dangerous, it is at most Medium and must be framed as such.
- **Pre-existing.** The bug is not introduced by this change. Still reportable if
  Critical, but must be labeled pre-existing — mislabeling it as a regression destroys
  trust in the whole report.

## Classes that need extra evidence

These are where models hallucinate most. Do not report them at normal evidence
standards; they require a reproduction or an explicit code citation of the missing
synchronization.

- **Race conditions and concurrency.** Requires: two named concurrent entry points, the
  specific interleaving, the shared mutable state, and confirmation that no lock,
  queue, single-threaded event loop, or atomic operation prevents it. In a
  single-threaded runtime (Dart isolate, JS event loop), a claimed race must involve
  an actual `await` interleaving point — say which.
- **Performance and complexity claims.** Requires a measurement or a concrete data
  scale from the codebase. "This is O(n²)" is not a bug without knowing n.
- **"Unreachable" / "dead code".** Requires exhaustive caller enumeration.
- **Memory leaks in GC languages.** Requires naming the specific retaining reference.
- **Library version behavior.** Requires checking the actual pinned version in the
  lockfile.
- **Anything depending on runtime configuration you cannot see.** Environment
  variables, feature flags, infra settings, database contents. Either read the config
  or do not claim it.

## Self-check before writing the report

Ask these about the report as a whole:

- Would a competent author of this code accept every one of these, or roll their eyes
  at any of them? Delete the eye-roll ones.
- Did I report anything a linter or the compiler would have caught? Remove it.
- Did I hedge anywhere ("might", "could potentially", "consider whether")? Hedged
  findings are unfalsified findings. Either close the gap or delete.
- Is any finding really a preference wearing a bug costume?
- If exactly one of these is wrong, which one is it? That one probably is. Re-examine
  it, and delete it unless you can close it.
