# Flutter / Dart failure modes

Apply as seeds, then trace and falsify like anything else. Presence of a pattern is
a *question*, not a finding.

## Async and lifecycle

- **`BuildContext` across an `await` gap.** Any use of `context` after an `await`
  inside a `State` method. Rebuttal to check: `if (!mounted) return;` or
  `if (!context.mounted)` between the await and the use. Symptom: exception or a
  navigation/snackbar landing on a dead tree after the user backs out mid-request.
- **`setState` / `notifyListeners` after dispose.** Async callback resolves after the
  widget is gone. Check for the `mounted` guard and for cancellation in `dispose()`.
- **Missing `dispose()`.** For every `AnimationController`, `TextEditingController`,
  `ScrollController`, `FocusNode`, `StreamSubscription`, `Timer`, `ValueNotifier`,
  platform channel handler. Forward-slice from construction to teardown. Symptom:
  leak plus callbacks firing on stale state.
- **Unawaited futures.** Fire-and-forget async calls. Two separate defects hide here:
  errors vanish silently (no `catchError`, no zone handler), and ordering is not what
  the author assumed. Check whether the result is needed before the next line runs.
- **`initState` doing async work** without guarding against completion after dispose,
  or reading `InheritedWidget`/`Provider` (needs `didChangeDependencies`).
- **Not cancelling a subscription on rebuild** — `listen()` called in `build()` or in a
  method that runs repeatedly, accumulating subscriptions.

## Null safety and types

- Unjustified `!` — backward-slice to establish nullability. The author's confidence
  is not evidence.
- `late` fields read before assignment on some path (especially error paths and
  early returns in `initState`).
- `as` casts on dynamic data — JSON decoding is the common source. A shape change on
  the server side produces a runtime cast error, not a compile error.
- `??` and `?.` chains that mask a real absent-value case by substituting a default
  that is wrong downstream (e.g. `?? 0` on a balance).

## State management

- Stale closure capturing an old value in a callback registered once.
- Provider/Riverpod/Bloc: reading state after an await without re-reading; emitting on
  a closed Bloc/sink; `context.read` vs `context.watch` misuse causing a missed rebuild
  (only a bug if it produces observably wrong UI state — otherwise out of scope).
- State mutated in place where the framework compares by identity, so no rebuild fires.
- **`AsyncValue.value ?? default`** — `.value` is null both while loading and after an
  error, so the default silently substitutes for real data in both states. Check what
  the default does downstream (a stale reward amount, a wrong threshold).
- **Derived state gated on one provider, read from another.** Gating on
  `providerA.hasValue` then reading `providerB` assumes they resolve together; they
  don't. The read can see loading/stale data the gate never checked.
- **`didUpdateWidget` (or `build`) synchronously driving a controller** —
  `jumpToItem`/`animateTo` firing an `onChanged` that calls `setState` during the
  parent's rebuild is reentrancy: debug assert, or silently dropped frame state.
- **Provider/container dispose resetting a process-global.** A `ref.onDispose` that
  nulls a static/global (token reader, service locator entry) clobbers whatever a
  newer container already installed there.

## Data and persistence

- **Money and points as `double`.** Any currency, balance, or reward-point value in
  floating point is a defect: accumulation drifts and comparisons fail. Should be
  integer minor units. High severity in anything user-facing and financial.
- Local cache written without invalidation on logout or account switch — leaks one
  user's data into another session. Critical.
- Missing migration handling for a changed persisted shape (Hive/Isar/SharedPreferences/
  sqflite): old records on disk still have the old shape after an app update.

## Network and idempotency

- **Double submission.** Tap handlers that fire a mutating request without disabling
  the control or guarding an in-flight flag. Especially: claiming a reward, submitting
  a payment, redeeming points. Check for both a UI guard and a server-side idempotency
  key — a UI-only guard fails on retry.
- Retry logic that re-sends a non-idempotent mutation after a timeout where the
  original may have succeeded.
- Response parsed without checking the status code; error bodies deserialized as
  success shapes.
- No timeout on an HTTP call, leaving the UI in a permanent loading state.

## Platform

- Permission result not handled for the denied / permanently-denied branches.
- Deep link / route argument cast without validation.
- Platform-conditional code where one platform branch is untested and takes a
  different, wrong path.

## Deterministic tools to run first (Phase 0)

```bash
dart analyze
dart format --output=none --set-exit-if-changed .   # informational only, never report
flutter test
```

Anything `dart analyze` reports is its finding, not yours. Do not restate it.
