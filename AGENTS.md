# Daywell contributor guidance

Daywell is a native macOS SwiftUI/AppKit companion for Apple Reminders. Preserve
user intent and reminder data ahead of convenience. Follow
[the development reference](docs/development.md) for examples and rationale.

## Before changing code

- Read the relevant model, store, view, and tests; do not infer behavior from a
  single call site.
- Keep the dependency direction: `Daywell` depends on `DaywellKit`, which
  depends on `DaywellCore`. Core must not import SwiftUI, AppKit, or EventKit.
- Keep `ReminderStore` as the external-reminder seam. Do not add TCA, a DI
  container, an effect framework, or a protocol for every type.
- Write a focused failing regression test before fixing behavior.

## Swift rules that matter here

- Prefer clear Swift names and concrete value types. Name operations for their
  observable result; clarity at the call site beats brevity.
- Keep one owner for persistent state, submitted operations, and native
  resources. Expose mutation only where callers legitimately edit a draft.
- Snapshot user intent before the first `await`. Actor isolation does not make a
  multi-`await` operation atomic.
- Distinguish EventKit success, local plan persistence, and refresh success.
  Never retry a successful remote creation because a later local step failed.
- Translate EventKit objects to Daywell values at the adapter and preserve
  unsupported Apple metadata by changing only edited fields.
- Use toolchain `swift format` as the only formatter. Do not hand-format around
  it or add another formatter.
- Avoid force operations. A necessary exception must be narrow and explain the
  invariant that makes it safe; never replace `try!` with silent `try?`.
- Lint proves syntax policy, not ownership, async correctness, EventKit safety,
  retain-cycle freedom, or correct behavior.

## Verification

Run the repository contract after code changes:

```sh
bash scripts/check.sh
```

Focused commands include `swift test --disable-xctest`,
`swift build --product Daywell`, and
`swift format lint --strict -r Sources Tests Package.swift`.

- Ordinary checks must never access live EventKit, write personal reminders,
  package, install, or re-sign the approved app.
- `.build/debug/Daywell --ui-check` uses disposable fixtures and requires a GUI
  session. Run it for interaction changes after building `Daywell`.
- `--live-check` changes real Reminders data. Run it only with explicit human
  authorization and the procedure in `docs/verification.md`.
- For native UI changes, verify keyboard and pointer paths, busy/error/permission
  states, and inspect fresh snapshots when appearance changes.

## Read only what your task needs

- Async writes: [submitted intent](docs/development.md#snapshot-async-intent-before-suspension)
  and [partial success](docs/development.md#represent-partial-success-honestly).
- Architecture: [types and ownership](docs/development.md#use-precise-types-and-explicit-ownership).
- Lint changes: [formatting and exceptions](docs/development.md#one-formatter-narrow-invariant-exceptions).
- Tests: [isolated regression fixtures](docs/development.md#regression-tests-first-with-isolated-fixtures).
- UI: [native verification](docs/development.md#native-ui-verification).
