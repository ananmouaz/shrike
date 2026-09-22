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
- **A time budget whose clock starts before the isolate is warm.** A walk or sync given
  a share of a total deadline, measured from a stamp taken before cold isolate boot,
  session restore, or consent, can have its whole share consumed by that prelude and
  never run. Name the prelude's worst case and compare it to the share.
- **Sign-out or account switch racing a queued persist.** A debounced or queued write
  from the previous session lands after the clear, so the signed-out state carries the
  old user's data; the same shape as a kill-switch checked against a snapshot cached
  at start-up while the remote value it guards has already changed.

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

When a candidate involves loading/error/value selection, apply the family matrix in
`review-reuse.md` before handing off fixes. Validate the installed provider version
and options; the patterns below are seeds, not universal framework guarantees.

- Stale closure capturing an old value in a callback registered once.
- Provider/Riverpod/Bloc: reading state after an await without re-reading; emitting on
  a closed Bloc/sink; `context.read` vs `context.watch` misuse causing a missed rebuild
  (only a bug if it produces observably wrong UI state — otherwise out of scope).
- State mutated in place where the framework compares by identity, so no rebuild fires.
- **`AsyncValue.value ?? default`** — check when the pinned implementation returns
  null, retains a value or throws, and whether resolved null is a legal value. A
  default can conflate distinct states downstream (a wrong amount or threshold).
- **Derived state gated on one provider, read from another.** Gating on
  `providerA.hasValue` then reading `providerB` assumes they resolve together; they
  don't. The read can see loading/stale data the gate never checked.
- **`didUpdateWidget` (or `build`) synchronously driving a controller** —
  `jumpToItem`/`animateTo` firing an `onChanged` that calls `setState` during the
  parent's rebuild is reentrancy: debug assert, or silently dropped frame state.
- **`ref.invalidate` on a provider something is already awaiting.** Invalidating an
  `autoDispose` provider while another frame holds `ref.read(p.future)` can leave that
  future never completing — the awaiter hangs, with no error to surface. Worse in
  combination with a `.timeout()` at the await site: the timeout fails *that* await
  open but does not complete the underlying future, so a second await of the same
  future blocks again — and anything irreversible done in between (a consumed share
  buffer, a cleared plugin intent) is already gone.
- **`AsyncValue.when` on a refresh path.** Trace which branch its version and options
  select while refreshing or failing with retained data, including retained null.
  Compare with the intended contract and sibling screens; replacing retained content
  with an error placeholder is a candidate only when that behavior is wrong.
- **A lifecycle trigger added without the precondition its original call site had.**
  A check rewired to `AppLifecycleState.resumed` also runs pre-auth; if the provider
  behind it requires a user id, every signed-out resume throws, and an error recorder
  in that path turns expected failures into crash-reporter noise that reads as a real
  outage.
- **Provider/container dispose resetting a process-global.** A `ref.onDispose` that
  nulls a static/global (token reader, service locator entry) clobbers whatever a
  newer container already installed there.

## Navigation and reporting

- **`context.go` / `pop` and then using the same context.** A dialog, snackbar, or
  sheet shown from the context of the route the navigation just removed races the
  teardown and can be dropped silently. If the previous version had an `await` between
  the two, the change deleted the ordering that made it work — an incidental await is
  load-bearing exactly until someone removes it.
- **Route observers reading `route.settings.name`.** Routes declared with `builder` and
  no `name` all report the fallback, so a crash-context or analytics observer records
  `(unnamed)` for most screens. Read how the routes in the table are actually declared,
  not the one example that sets a name.
- **Crash reports and custom keys emitted before Firebase is initialized.**
  `recordError` and `setCustomKey` no-op until the SDK is up (implementations may
  buffer keys; none buffer errors), so anything reported from `install()` or early
  bootstrap is dropped. Then check the latch: a flag marking a key "already synced",
  set on that dropped write, means a later ready SDK never receives it either.

## Data and persistence

- **Money and points as `double`.** Any currency, balance, or reward-point value in
  floating point is a defect: accumulation drifts and comparisons fail. Should be
  integer minor units. High severity in anything user-facing and financial.
- Local cache written without invalidation on logout or account switch — leaks one
  user's data into another session. Critical.
- Missing migration handling for a changed persisted shape (Hive/Isar/SharedPreferences/
  sqflite): old records on disk still have the old shape after an app update.
- **A form `validator:` and the server's constraint are one rule in two places.** A Dart
  validator rejecting a `0` the API accepts, or a `TextInputFormatter` capping a field
  shorter than the column allows, hides the disagreement for as long as this app is the
  only writer — then a web admin, a script, or a replayed request writes the value the
  form could never produce. Put both texts in the parity row; the boundary that
  separates them is almost always `0`, empty, or max length.

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
- **Two link or intent handlers merged into one.** The survivor's fallback — navigate
  home on an unparseable link, say — now applies to links the other path used to pass
  through untouched, so an OAuth callback or external URL arriving there is redirected.
  Enumerate both old caller sets and state each one's new failure behaviour.
- Platform-conditional code where one platform branch is untested and takes a
  different, wrong path.
- **Text from a `TextField` is not ASCII.** iOS and Android smart punctuation substitute
  a curly apostrophe (`’`, U+2019) for `'` and an en dash for `--`, so a negation guard,
  a `split`, or a `replaceAll` written with the ASCII apostrophe stops matching real
  input while every test fixture still passes. In the normalisation sweep, run the
  apostrophe input in both forms.

## Deterministic tools to run first (Phase 0)

```bash
dart analyze
dart format --output=none --set-exit-if-changed .   # informational only, never report
flutter test
```

Anything `dart analyze` reports is its finding, not yours. Do not restate it.
