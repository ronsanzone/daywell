# Daywell technical design

Date: September 18, 2026.
Status: approved by Ron, with Vim-inspired keyboard navigation added.
Implementation authorized in the discovery thread on September 18, 2026.

## Recommended approach

Build a native macOS 14+ app using SwiftUI for content, AppKit for a menu-bar
status item and controlled popover/focus lifecycle, and EventKit for Apple Reminders.
Use a small Swift package for independently testable domain and parsing code,
hosted by a macOS app target. Avoid third-party dependencies initially unless a
focused prototype demonstrates that an essential behavior needs one.

Alternatives considered: SwiftUI-only menu-bar UI is smaller but gives less direct
control over focus and keyboard interactions; a web-backed shell adds complexity
without a product need. AppKit plus SwiftUI is the recommended middle ground.

The deployment floor is a proposal: macOS 14 supports the modern reminders
authorization API without coupling the product to Apple Intelligence availability.

## Responsibilities

- **Reminder store:** EventKit permissions, fetches, supported-field writes,
  change notifications, and reconciliation. Do not expose live EventKit objects
  as persisted application state.
- **Day plan:** explicit dated commitments and one pin, rollover, completion
  presentation, and decisions about visible rows.
- **Local persistence:** versioned companion records and settings, not a duplicate
  reminder database. Keep storage separate from UI state.
- **Commands:** one action registry shared by menu items, palette, shortcuts,
  and pointer controls, with availability determined by selection/context.
- **Presentation:** theme tokens, SwiftUI views, focus handling, and AppKit host.

These are responsibility boundaries, not a mandate for a separate framework or
protocol per component. Introduce a small reminder-store seam for fixture-based
tests so tests never write to Ron's real reminders.

## EventKit contract

Request full reminders access only after explaining why; denial must leave a
useful permission screen with retry/settings guidance. Declare the correct usage
description and app capabilities. Select a real writable default reminders list
as the initial inbox; let the user choose another. Do not silently create or
rename an Apple list just to make its title match Daywell's Inbox label.

Observe EventKit changes and refresh on appropriate activation points. Use the
same underlying reminder identity across My Day and deadline surfaces. On save
failure, retain user input and report the failure; never show a completed write
as successful. Write only fields the user changed, preserving recurrence, alarms,
and other existing data. Permission loss, read-only lists, deleted lists, and
externally removed reminders must be handled explicitly.

Core fields supported by the public API are sufficient. Do not depend on public
access to tags, subtasks, attachments, or Apple-specific list sections.

References:
- https://developer.apple.com/documentation/eventkit/ekreminder
- https://developer.apple.com/documentation/eventkit/ekeventstore
- https://developer.apple.com/documentation/eventkit/ekcalendaritem

Before shipping, verify recurrence completion/undo and external-change behavior
against real EventKit fixtures. Do not promise an undocumented exact-reminder
deep link: validate supported handoff options and fall back to opening Apple Reminders.

## Companion persistence with future sync in mind

Start with an atomically written, versioned Codable document in Application Support.
Expected personal-plan data is small; a database and sync engine are unnecessary now.
Keep a last-known-good recovery copy and surface write failures. Do not replace
corrupt data with an empty plan silently.

Give companion records stable UUIDs independent of Apple identifiers. Store
commitments by local calendar-day key, reminder link, ordering, and modification
timestamp. Store the single pin as a reference to a commitment. Persist theme and
global-shortcut settings separately from reminder semantics. No in-progress field.

Keep reminder linking explicit. EventKit identifiers may change and must not be
treated as globally durable sync IDs. Retain available source/list/external-ID
hints for reconciliation; never attach a commitment to a different task solely
because titles match. Preserve unresolved links for recovery rather than silently
deleting them or guessing. Identifier ambiguity is a future-sync design concern,
not justification to build cloud sync in v1.

Schema versioning, stable companion IDs, and an isolated storage boundary enable
migration later. Future cross-device identity, deletion propagation, ordering,
and conflict resolution need their own design; timestamps alone are not a sync protocol.

## Proposed behavioral defaults

- Day keys use the user's current local calendar date, not elapsed 24-hour windows.
  Recheck on activation and significant date/time changes.
- Unfinished commitments from earlier days form one recovery group, not a stack
  of daily queues. Retain original dates internally. Keep all and Choose reassign
  selected commitments to the current day; release only removes plan membership.
- A pin belongs to the active day's commitments; retaining a prior-day commitment
  can preserve its pin if there is not a newer current pin. Never auto-select a new task.
- A due task that is already chosen appears once as an active My Day row with its
  deadline metadata. The separate deadline area shows due tasks not already in My Day.
  This prevents contradictory controls for duplicate rendered tasks.
- Done today includes reminders completed today from accessible lists, including
  completions outside Daywell when EventKit exposes the completion date. Keep it
  collapsed by default. Validate this scope for large stores before finalizing.
- Undo restores the prior completion state when still applicable; it must not
  overwrite a later external edit. Deletion is a distinct confirmed action and
  must never be confused with releasing a commitment.
- Changing a due date does not implicitly create an alarm. Preserve existing
  alarm semantics unless an explicitly supported user action changes them.

## Natural-language capture

Start with a local, deterministic parser for a documented English subset: common
relative dates, weekdays, and optional times, with plain-title fallback. Always
show interpreted fields and allow correction/removal. Ambiguous input stays
editable rather than being silently committed to a guessed deadline.

Investigate Foundation date detection with real examples before choosing the
parser implementation. The parser accepts an injected clock, calendar, and time
zone for tests. Cover date-only reminders, tomorrow across month/year boundaries,
weekdays, AM/PM, and DST boundaries. No remote model or Apple Intelligence requirement.

## Keyboard and panel behavior

Register a user-configurable global shortcut using a supported macOS mechanism
that does not require broad keyboard monitoring if possible. Validate conflicts,
focus restoration, Escape behavior, and interaction with text editing. Avoid
intercepting unmodified task-action keys while typing in inputs.

Use Vim-inspired j/k navigation, gg/G first/last, and h/l back/expand alongside
standard arrows, activation, and Escape conventions. Never intercept Vim motions
in editable text. Exact action bindings are defined in one command registry, not
the inconsistent generated-image keycaps. All capture, edit, reset, theme, list,
and command operations must be reachable by keyboard, with VoiceOver labels and
visible focus.

## Build environment and first delivery

Swift 6.2.4 is available on the initial Mac. Full Xcode was not found at the usual
application path and `xcodebuild` fails under Command Line Tools. Implementation
verified that SwiftPM can nevertheless compile the native app, render SwiftUI,
and run AppKit keyboard-event checks on this machine. `scripts/build-app.sh`
assembles and ad-hoc signs a local `.app`; no toolchain settings were changed.
Because the installed tools lack XCTest/Testing, the package pins Swift Testing
6.2.4 as a test-only dependency and uses `swift test --disable-xctest`.
This is not Xcode UI-test, notarization, or live EventKit verification.

After design approval, implement in these increments:

1. Domain/persistence tests and a runnable fixture-backed menu-bar shell.
2. Permission/read integration, choose My Day, pin, complete, external refresh,
   and relaunch persistence: one real end-to-end slice.
3. Browse/search, capture with interpretation preview, essential editing, reset,
   and Done today with safe undo.
4. Full command coverage, shortcut help, three themes, settings, and accessibility.
5. Real rendered review, permission and failure paths, and controlled live Reminders checks.

Use asymmetric fixtures and boundary tests, not snapshot-only tests. In live
verification, create only clearly disposable test reminders in a user-approved
test destination; do not modify unrelated personal reminders.

## Delegation

Ron authorized subthreads where useful and Luna on xhigh for discrete parallel
work. This inherited thread cannot create further threads. Do not bypass that
restriction with the CLI or another mechanism. If a later execution context has
the capability, use isolated assignments with disjoint file ownership, integrate
their diffs, and review/test locally. Keep EventKit integration and end-to-end
verification with the owning checkout. No delegation is required to write this design.

## Approval record

Ron approved the technical design and edge-case behavior, requested Vim-inspired
motions, and authorized the build. Proceed with a recorded implementation plan.

## October 2026 architecture

Approved by Ron on October 18, 2026, after the dream-board audit. Supersedes the
single-popover shell and color-only themes above; the EventKit contract, companion
persistence and capture safety rules still apply.

- **Targets.** `DaywellCore` (pure: `DayPlan`, `Today` projection, capture grammar),
  `DaywellKit` (`DayModel`, EventKit adapter, views, themes, AppKit shell), `Daywell`
  (a thin `main.swift`), and the never-shipped `DaywellFixtures` and `DaywellDev`
  (demo, snapshots, UI check, benchmarks, live check).
- **Fetch.** Two concurrent EventKit queries: open reminders, and reminders completed
  since local midnight (which are today's pile). Completed history is never loaded.
- **One owner.** `DayModel` owns reminders, the plan and every action. `Today` is
  derived once per change of reminders, plan, lists or day, then read by the ticker,
  the capture bar and the panel. UI state lives in `PanelState` and `CaptureState`.
- **Motion before confirmation.** A finish emits `.finishing` on the keypress so the
  ring fills at once; the pile, the ticker roll, sound and Day clear wait for Apple
  Reminders to confirm (`.finished`), and a rejection emits `.finishFailed` to reverse
  the motion. Nothing is reported as saved before it is.
- **Undo.** One slot, kept until the next undoable action: plan changes, finish and
  reopen, and moves. It never overwrites a later external edit.
- **Shell.** Two non-activating panels (capture bar, panel) take keys without making
  Daywell the active app, so the previous app keeps focus. Carbon hot keys: capture
  (configurable) and optional finish (⌃⌥X). `StatusTicker` draws the task text with a
  hit-tested ring, a `+N` menu and a fixed truncation length.
- **Moves.** Changing a reminder's list may change its identifier; the plan re-links
  by the external identifier on refresh and immediately after a move.
- **Themes.** `ThemeProfile` sets palette, type, ring, finish style, pile token, sound
  and Day clear text, injected through the SwiftUI environment. Sounds are synthesized
  at launch into memory; Maple Mono ships in the bundle under the OFL.
