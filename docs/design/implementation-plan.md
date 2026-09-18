# Daywell Implementation Plan

> Execute task-by-task with test-first behavior checks. The owning thread integrates
> and reviews work; independent domain and parser work can be delegated together.

**Goal:** A runnable native menu-bar companion implementing the approved My Day loop.
**Architecture:** SwiftUI presentation hosted by AppKit, EventKit task authority,
and a small Foundation-only core for day planning, local persistence, parsing,
and keyboard decisions. SwiftPM builds both the core and executable; a script
assembles a locally signed .app without requiring an Xcode project.
**Tech stack:** Swift 6, macOS 14+, SwiftUI, AppKit, EventKit, Carbon hotkeys, Swift Testing.
**Spec:** `technical-design.md`, `functionality.md`, `visual-style-guide.md`.

## Execution record — September 18, 2026

The checklist below is the original implementation brief. Actual delivery status:

- **Domain/storage and parser:** implemented, delegated work reviewed, regressions
  fixed and tested (inactive pins and half-hour DST overlaps included).
- **Native integration:** implemented in `Sources/DaywellKit`, with fixture-backed
  model tests in `Tests/DaywellKitTests`; EventKit adapter compiles, but live reads
  and writes were deliberately not exercised against personal reminders.
- **Keyboard/interface:** implemented and exercised through actual AppKit events;
  all three themes and representative states rendered and inspected. Whole-app
  VoiceOver and global-hotkey acceptance remain separate manual checks.
- **Packaging:** SwiftPM release executable assembled into an ad-hoc signed app.
  Full Xcode was not necessary; no system toolchain settings were changed.
- **Acceptance:** see `../verification.md` for exact checks and limits. No remote
  push, notarization, distribution, or live Reminders writes are authorized by this record.

The installed CLT lacks XCTest, so test commands below use
`swift test --disable-xctest` in the actual runs. A test-only Swift Testing package
is pinned in Package.swift. Core code has no third-party runtime dependency.

## Constraints

- No in-progress state; pin independent of completion. No cloud sync or AI.
- No access to live reminders during automated verification.
- Vim motions never consume text entry; arrows remain supported.
- No writes to the unrelated sites repository; work in the new Daywell checkout.
- No new threads available in this inherited session. Tool-invoked bounded workers
  may own separate core files; they cannot select Luna via the exposed Task interface.
- Do not push, publish, or change system developer tools without authorization.

## 1. Domain and storage

Files: `Sources/DaywellCore/Models.swift`, `DayPlan.swift`, `Persistence.swift`;
`Tests/DaywellCoreTests/DayPlanTests.swift`, `PersistenceTests.swift`.

Interfaces: `ReminderItem` holds an immutable reminder snapshot with String ID,
title, notes, listID/listName, optional dueDate/completionDate, hasDueTime,
isCompleted, isWritable, and optional externalID. `ReminderList` holds id/title/isWritable.
`DayPlan` is Codable with schemaVersion, commitments, and pinnedCommitmentID;
each commitment has UUID identity, reminder link, local day key, ordering, and timestamp.
Methods choose, release, pin, and keepPrevious do not edit reminder properties.
Projection produces My Day, due, previous, done, and unresolved memberships.
`PlanStore.load()` and `save(_:)` throw, version-check, write atomically, retain backup.

- [ ] Write tests for deduplication, pin replacement, release-not-delete, rollover
  over multiple days and DST, completed-today boundaries, unresolved links.
  Example invariant:
  ```swift
  plan.choose("a", on: now, calendar: calendar)
  plan.choose("a", on: now, calendar: calendar)
  #expect(plan.commitments.count == 1)
  #expect(reminder.dueDate == originalDeadline)
  ```
- [ ] Observe failed assertions using minimal empty implementations, then implement.
- [ ] Test persistence round-trip, malformed/unsupported schema and backup behavior;
  never overwrite a corrupt existing document as if it were an empty plan.
- [ ] Run `swift test --filter DayPlanTests` and `swift test --filter PersistenceTests`.

## 2. Capture parsing (independent of task 1)

Files: `Sources/DaywellCore/CaptureParser.swift`, `Tests/DaywellCoreTests/CaptureParserTests.swift`.
Interface: `CaptureParser.parse(_:now:calendar:) -> CaptureResult`, whose public
fields are title, dueDate, hasTime, and optional interpretation. No other core types required.

- [ ] Write and observe failing assertions for plain text, tomorrow at 2pm,
  date-only tomorrow, weekdays, month/year rollover, noon/midnight and DST.
  ```swift
  let result = CaptureParser.parse("Call dentist tomorrow at 2pm", now: friday, calendar: ny)
  #expect(result.title == "Call dentist")
  #expect(ny.component(.hour, from: result.dueDate!) == 14)
  ```
- [ ] Implement conservative English suffix parsing. Invalid or ambiguous times
  remain literal titles, not incorrect dates. Document the accepted grammar.
- [ ] Run `swift test --filter CaptureParserTests`.

## 3. Native integration and transactional presentation model

Files: `Sources/Daywell/ReminderStore.swift`, `AppModel.swift`, `Fixtures.swift`;
`Tests/DaywellTests/AppModelTests.swift`; add executable/test targets in Package.swift.

- [ ] Test with a fixture reminder store: save failure preserves capture draft;
  completing a pinned task clears its active pin only after successful store write;
  refresh preserves unresolved commitments; resetting never deletes a reminder.
- [ ] Implement a @MainActor reminder-store interface and EventKit adapter using
  permission request, fetch, writable-list validation, field-level saves, and
  change notification refresh. Do not query personal data in tests.
- [ ] Implement AppModel state shared by UI and commands. Persist a candidate plan
  before displaying local changes; surface errors. Guard completion undo against
  changed snapshots. Keep deletion distinct and confirmed.
- [ ] Provide an explicit `--demo` fixture mode and `--snapshot` rendering mode.

## 4. Keyboard, settings, and interface

Files: `Sources/DaywellCore/Navigation.swift`, `Tests/DaywellCoreTests/NavigationTests.swift`;
`Sources/Daywell/Theme.swift`, `PanelView.swift`, `CommandPalette.swift`,
`EditorView.swift`, `SettingsView.swift`, `AppMain.swift`, `GlobalShortcut.swift`.

- [ ] Write failing navigation tests distinguishing typing from navigation,
  one g from gg, G from g, and first/last bounds.
- [ ] Implement My Day, browse/search, deadlines, reset, done, capture preview,
  editing, command palette, shortcut help, and settings with native controls.
- [ ] Use j/k, gg/G, h/l and arrows outside text fields. Cmd-K palette, Cmd-N capture,
  Cmd-F search; action keys and help derive from one registry. Escape goes back.
- [ ] Implement theme choice, optional count, and configurable global key with
  modifiers via Carbon registration. Failed registration must be visible.
- [ ] Render all three themes and representative non-default states. Inspect
  screenshots, then correct layout/contrast issues and re-render.

## 5. App bundle and acceptance

Files: `scripts/build-app.sh`, `Resources/Info.plist`, `README.md`,
`docs/verification.md`.

- [ ] Build executable with SwiftPM, bundle usage description and LSUIElement,
  locally ad-hoc sign .app. No notarization/distribution claims.
- [ ] Run `swift test`, `swift build`, bundle verification and fixture smoke tests.
- [ ] Verify live rendered keyboard/capture/reset behavior where runner permits;
  record exactly which live EventKit permission/write checks remain unperformed.
- [ ] Save inspected screenshots and supply phone-reviewable images in the thread.
- [ ] Review diff, document run commands, and commit local implementation.

## Self-review

Every approved feature maps to tasks 1–5. EventKit write tests use fixtures until
Ron approves a live disposable reminder destination. UI verification must use
actual SwiftUI rendering, not generated design imagery. A built app is not proof
of granted permissions, live iCloud sync, notarization, or full keyboard accessibility.
