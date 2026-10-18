# Daywell development reference

This is the detailed reference behind the short repository rules in
[`AGENTS.md`](../AGENTS.md). Use only the sections relevant to the task. Daywell
already has useful boundaries: value logic in `DaywellCore`, orchestration and
the `ReminderStore` seam in `DaywellKit`, and the native host in `Daywell`.
Strengthen those boundaries rather than adding layers.

## Safe check contract

The normal repository check is:

```sh
bash scripts/check.sh
```

If required developer tools are missing, run the explicit bootstrap script and
then rerun the check:

```sh
bash scripts/bootstrap-tools.sh
bash scripts/check.sh
```

Useful focused checks are:

```sh
swift format lint --strict -r Sources Tests Package.swift
swift build --product Daywell
swift test --disable-xctest
.build/debug/DaywellDev --ui-check
```

The first three are ordinary, noninteractive checks. They must never initialize
a live EventKit store, read or write personal reminders, package/install the
app, or re-sign an already approved app. `--ui-check` is separate because it
needs a macOS GUI session; it drives the real AppKit/SwiftUI application with
disposable fixture data.

`--live-check` is not a routine check and must never run in ordinary CI. It
creates and deletes real Reminders fixtures and requires explicit human
authorization. Follow the launch and cleanup instructions in
[`verification.md`](verification.md#authorized-live-acceptance-attempt).

## Snapshot async intent before suspension

`@MainActor` protects isolated memory access, but another main-actor task may run
at every `await`. Values describing the submitted operation must therefore be
captured before its first suspension. Decide separately whether the UI remains
editable while busy and what navigation should happen on completion.

Bad—later UI changes can alter an operation already in progress:

```swift
let saved = try await store.save(draft, replacing: nil)
await refresh()
if captureAddToDay { choose(saved.id) }
```

Good—the submitted intent is stable across suspension:

```swift
let submittedDraft = draft
let shouldAddToDay = captureAddToDay
let saved = try await store.save(submittedDraft, replacing: nil)
if shouldAddToDay {
  // Apply the confirmed identity without rereading mutable form state.
}
await refresh()
```

Snapshot only operation inputs, not every property. Tests for this rule should
control suspension with a continuation or another explicit synchronization
point, mutate the form while suspended, then prove the submitted choice wins.
Do not use sleeps to approximate ordering.

## Represent partial success honestly

Apple Reminders, the local day-plan document, and a subsequent refresh are three
different effects. A successful remote save is durable even if local persistence
or reconciliation fails. Never report complete success, erase useful recovery
information, or repeat remote creation merely because a later stage failed.

Bad—refresh failure silently prevents the requested local update, while retrying
the whole method risks a duplicate reminder:

```swift
let saved = try await store.save(value, replacing: nil)
await refresh()
choose(saved.id)
notice = "Saved"
```

Good—model stages and outcomes precisely (names here are illustrative, not an
API requirement):

```swift
let saved = try await store.save(value, replacing: nil)
let planResult = persistDayChoice(for: saved)
let refreshResult = await reconcileReminders()
report(remoteSaved: saved, planResult: planResult, refreshResult: refreshResult)
```

Tests should independently cover remote failure, remote success plus local-plan
failure, remote success plus fetch failure, and retry behavior that proves no
duplicate remote reminder is created. Preserve the confirmed reminder identity
and list/external hints needed for reconciliation. Keep absent, stale, failed,
and empty states distinct when the product treats them differently.

## Use precise types and explicit ownership

- Domain logic consumes `ReminderItem`, `ReminderList`, `DayPlan`, and other
  application-owned values. Convert `EKReminder` and `EKCalendar` once in the
  EventKit adapter.
- Keep one source of truth. Loaded reminders, authorization, persisted plan, and
  native resources should not be publicly writable merely to make a call site
  convenient. Bindings are appropriate for real draft editing.
- Prefer enums or result values that retain meaningful states over booleans or
  strings that collapse them. Do not invent a general framework when a local
  enum or small value is enough.
- Pair native resource acquisition with release in the owning lifetime. An
  AppKit/Carbon callback token being `Any` is framework reality, not permission
  to erase types elsewhere.

Bad:

```swift
public var reminders: [ReminderItem] = [] // every caller can replace loaded state
func finish(_ succeeded: Bool)            // which stage succeeded?
```

Better:

```swift
public private(set) var reminders: [ReminderItem] = []
enum PlanWriteResult { case saved, failed(PlanStoreError) }
```

Choose names according to the
[Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/):
clarity at the point of use is more important than brevity. Use product terms
(`commitment`, `reminder`, `capture`, `day plan`) consistently. Name a method for
the result it owns—`refreshReminders()` is clearer than `doUpdate()`—but avoid
inflated names, redundant type words, and generic `Manager`/`Helper` buckets.

## One formatter; narrow invariant exceptions

Toolchain `swift format` is the only formatting authority. Configuration belongs
in `.swift-format`; do not add Nick Lockwood's SwiftFormat or hand-maintain a
second style. SwiftLint should remain a small allowlist of high-confidence safety
rules, not an architecture engine or a formatting competitor.

Prefer checked operations for fallible input:

```swift
guard let day = calendar.date(from: components) else {
  throw ParseError.invalidDate
}
```

When an unchecked operation is genuinely guaranteed, scope it to the smallest
expression and state the invariant:

```swift
// Fixture construction fixes these components to a valid Gregorian date.
// swiftlint:disable:next force_unwrapping
let now = calendar.date(from: fixtureComponents)!
```

Bad:

```swift
let now = calendar.date(from: components)! // "should never fail"
try? planStore.save(plan)                   // hides a user-visible failure
// swiftlint:disable force_unwrapping
```

Framework bridges, literal regular expressions, fixed fixture dates,
`@preconcurrency import EventKit`, and `MainActor.assumeIsolated` each require
different evidence. Explain that evidence locally. Do not use a file-wide lint
disable or change `try!` to `try?` just to satisfy a rule.

Formatting and lint cannot prove that actor-reentrant code preserves intent,
that separate writes have a sound partial-success contract, that EventKit
metadata survives an edit, that callback ownership is safe, or that a test
asserts useful behavior. Review and tests must establish those properties.

## Regression tests first, with isolated fixtures

For a bug, first add the smallest test that fails for the observed reason. Assert
the externally meaningful result and important retained state, not internal call
counts alone. Use asymmetric data so swapped IDs, lists, dates, or ordering cannot
accidentally pass. Inject failures at the actual boundary and control async order
explicitly.

Good test shape:

```swift
@Test func submittedChoiceSurvivesRefreshFailure() async throws {
  try await withModel { model, store in
    model.captureText = "Call dentist"
    model.captureAddToDay = true
    store.failNextFetch = true

    await model.saveCapture()

    #expect(store.items.count == 2) // remote creation happened once
    #expect(model.plan.commitments.count == 1)
    #expect(model.error != nil)     // reconciliation failure remains visible
  }
}
```

The exact fixture API should match the implemented seam; do not add production
APIs solely to make a mock convenient. Prefer real `DayPlan`/`PlanStore` behavior
in a temporary directory and the existing `ReminderStore` seam.

Every test owns and removes its files, preferences suite, continuations, and
global/native registrations. A helper should return an owned fixture or run a
closure with `defer` cleanup; it should not leak a new directory from each call.
Parallel tests must not share fixed paths or process-global defaults. Serialize
only a suite that truly owns unavoidable shared state.

Bad:

```swift
func temporaryURL() -> URL {
  FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
  // No owner removes it.
}
```

Good:

```swift
try await withTemporaryDirectory { directory in
  let store = PlanStore(url: directory.appending(path: "plan.json"))
  // The helper removes directory in defer.
}
```

Use awaited operations, checked continuations, or bounded readiness conditions;
do not use blind sleeps or unbounded `while ... { await Task.yield() }` loops.

## Native UI verification

Unit tests prove domain and orchestration contracts. For changed interactions,
also build the executable and run fixture-backed native checks:

```sh
swift build --product Daywell
.build/debug/DaywellDev --ui-check
```

Verify both keyboard and pointer entry points when they share an action. Exercise
busy, error, empty, read-only, and permission states relevant to the change. If
appearance changes, create and inspect fresh snapshots using the options in the
README rather than trusting compilation. Native controls need real focus,
keyboard traversal, menu/command availability, and accessibility review; a
model-only test is not a substitute. Conversely, `--ui-check` does not prove
live EventKit behavior, cross-application global hotkeys, VoiceOver acceptance,
or release readiness.

## Sources and conventions

Primary guidance:

- [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/)
- [The Swift Programming Language: Concurrency](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency/)
- [Apple: Managing model data in your app](https://developer.apple.com/documentation/swiftui/managing-model-data-in-your-app)
- [swift-format configuration](https://github.com/swiftlang/swift-format/blob/main/Documentation/Configuration.md)
- [SwiftLint](https://github.com/realm/SwiftLint)
- [Swift Testing: asynchronous code](https://github.com/swiftlang/swift-testing/blob/main/Sources/Testing/Testing.docc/testing-asynchronous-code.md)
- [Swift Testing: parallelization](https://github.com/swiftlang/swift-testing/blob/main/Sources/Testing/Testing.docc/Parallelization.md)

The selective Portfolio/Borrius conventions are: validate at boundaries, keep
ownership small and explicit, make exceptions name their invariant, use one
check contract in local development and CI, and test external failures without
discarding evidence. See their
[Portfolio guidance](https://github.com/ronsanzone/portfolio/blob/main/AGENTS.md)
and [Borrius Companion guidance](https://github.com/ronsanzone/borrius-companion/blob/main/AGENTS.md).
Daywell applies those principles with native Swift and its existing targets; it
does not import their TypeScript/Effect architecture.
