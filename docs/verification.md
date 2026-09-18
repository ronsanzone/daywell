# Daywell development verification

Date: September 18, 2026. Environment: macOS arm64, Swift 6.2.4 Command Line Tools.
This is a local development build, not a release certification.

## Executed checks

- `swift format lint --strict -r Sources Tests Package.swift` — passed.
- `swift test --disable-xctest` — **41 tests in 5 suites passed**.
- `bash scripts/build-app.sh` — release build and ad-hoc signed app produced at
  `dist/Daywell.app` without full Xcode or system toolchain changes.
- `codesign --verify --deep --strict dist/Daywell.app` — passed.
- `plutil -lint dist/Daywell.app/Contents/Info.plist` — passed.
- `dist/Daywell.app/Contents/MacOS/Daywell --ui-check` — **21 checks passed**
  using actual AppKit keyboard events and disposable demo reminders.

The keyboard run exercised panel opening, j/k, gg/G, pinning, capture focus,
literal j/k input, Escape, retained drafts, completion, undo, palette opening,
arrows in command search, Vim navigation outside search, command execution,
automatic reminder-search focus, capture saving, keeping previous commitments,
Settings access, and h to return. This is an app-owned smoke harness, not an
external XCUITest or proof of every possible keyboard interaction.

Core/model tests cover calendar-day and DST boundaries, single pin and membership
identity, separate deadlines, externally completed tasks, unresolved reminders,
corrupt/unsupported persistence, backup writes, capture grammar/fallbacks,
write failures, completion undo conflicts, deletion confirmation snapshots,
selection after filtering, and out-of-order refresh responses.

## Review findings corrected

The owning agent inspected the delegated domain/storage and parser implementation,
then reviewed their integration with the native app. Review was not delegated back
to the original implementers. The available worker tool could not select Luna;
no claim is made that these workers ran that model.

- Completed/missing reminders could still be projected as the active pin.
- Repeated local times assumed a one-hour DST change; Lord Howe's half-hour
  overlap now has an independent regression case and literal-title fallback.
- Pin ordering needed a strict comparator for self-comparison.
- Command-palette navigation must move commands rather than reminder rows.
- A deletion confirmation must retain its snapshot after SwiftUI dismisses the alert.
- Filtering must not leave a hidden reminder targeted by task-action keys.
- An older asynchronous fetch must not overwrite a newer refresh.
- Native startup needs a laid-out status-item window before anchoring the popover.
- The settings shortcut hint was truncated; it now wraps and was re-rendered.
- The lighter theme's text and keyboard-selection contrast was strengthened.

## Rendered review

These are actual SwiftUI/AppKit renders with demo data, not generated mockups:

- [Graphite & Taupe](screenshots/graphite.png)
- [Porcelain & Sage](screenshots/sage.png)
- [Linen & Plum](screenshots/plum.png)
- [Capture preview](screenshots/capture.png)

All three themes were inspected for readable circles, separate pin, selection,
deadline groups, reset controls, completion styling and footer. Additional local
captures in `artifacts/` cover browse, commands, expanded previous-day recovery,
settings, permission, empty My Day, shortcut help, dated/timed editing, long titles,
and an error banner. Clipping found during inspection was corrected and rechecked.

Normal primary/secondary/accent token contrast was calculated against both base
and raised surfaces using sRGB relative luminance. Minimum ratios: graphite
5.56:1, sage 4.63:1, plum 4.54:1. This does not certify native controls, disabled
states, VoiceOver or whole-app accessibility.

## Deliberately not verified yet

- **Live EventKit:** no permission prompt, personal reminder read, or live write
  was exercised. Validate capture/edit/delete and external refresh in a separately
  approved disposable Reminders list. Include read-only/deleted lists, permission
  revocation, recurrence completion/undo, alarms, and date-only timezone behavior.
- **System interaction:** global shortcut delivery from other applications,
  recording/conflicts, focus restoration across applications, and optional count
  changes need a hands-on check. Carbon registration ran during the smoke tests,
  but the tests do not simulate a system-delivered hotkey.
- **Accessibility:** full Tab traversal with macOS Keyboard Navigation, VoiceOver,
  focus indicators on all native controls, and small-display/large-text layouts.
- **Scale/platform:** large Reminders libraries, macOS 14 on real hardware,
  Intel builds, account migrations, iCloud timing, and cross-device identifiers.
- **Distribution:** app icon, Developer ID signing, hardened runtime, notarization,
  installer/update process. The current ad-hoc app is for local development only.

Do not change personal reminders or publish this app as part of these remaining
checks without explicit authorization. Nothing has been pushed or deployed.
