# Daywell

A calm, keyboard-first macOS menu-bar companion for Apple Reminders.
Apple Reminders stores the tasks. Daywell helps you choose a manageable day.

Working product name; trademark and distribution-name availability have not been assessed.

## Status

Local development build of the approved v1, September 18, 2026. Native SwiftUI
and AppKit interface with EventKit integration, fixture-based verification,
and three themes. The isolated live Reminders acceptance run passed, including
the approved recurring-undo safeguard and fixture cleanup. Not notarized or
release-ready: broader integration and full accessibility acceptance remain.

- [Approved functionality](docs/design/functionality.md)
- [Visual style guide and saved references](docs/design/visual-style-guide.md)
- [Approved technical design](docs/design/technical-design.md)
- [Verification results and remaining checks](docs/verification.md)
- [Inherited research, not requirements](docs/design/research-handoff.md)

## Run

Requires macOS 14+ and Swift 6.2.4. Command Line Tools are sufficient for this
SwiftPM development build; full Xcode is not required. The first build downloads
the pinned Swift Testing dependency used only by tests.

```sh
swift test --disable-xctest
bash scripts/build-app.sh
open dist/Daywell.app --args --demo
```

Demo mode uses disposable fixture reminders and temporary preferences. It never
creates an EventKit store or reads personal reminders. Quit the demo before
starting the real app:

```sh
open dist/Daywell.app
```

The real app explains Reminders access before requesting permission. Once granted,
completion, editing, capture and deletion change Apple Reminders. Only grant
access when ready to test against your own data. The bundle is ad-hoc signed for
local development, not a portable notarized download.

## Keyboard

- Control–Option–Space: open/close from anywhere; configurable in Settings.
- `j/k`, arrows: next/previous; `gg/G`: first/last; `h/l`: back/open.
- `p`: pin; `a`: choose for My Day; `r`: release; `x`: complete/reopen; `d`: Done today.
- ⌘N: capture; ⌘F: browse/search; ⌘K: commands; ⌘,: settings; `?`: help.
- ⌘Return: save capture/edit; ⌘Z: undo completion outside text entry.
- Escape leaves text entry, then returns to My Day, then closes the panel.
- Letters always type normally inside fields. Tab traverses native controls;
  macOS Keyboard Navigation may be needed for all controls.

Repeating reminders can be completed, but when Apple Reminders advances the
series, Daywell explicitly reports that undo is unavailable. It does not move
the next occurrence backward to imitate undo. Ordinary completion retains undo.

Capture recognizes a **terminal English suffix**: `today`, `tomorrow`, a weekday,
or `next <weekday>`, optionally followed by `at noon`, `at midnight`, `at 2pm`,
`at 2:30pm`, or `at 14:30`. A bare weekday includes today; `next` excludes today.
Unsupported phrases and ambiguous/nonexistent DST times remain literal titles.
The preview lets you change the phrase or remove its deadline before saving.

My Day membership never changes a reminder's deadline or list. Companion choices
are stored in `~/Library/Application Support/Daywell/day-plan.json`, with a
last-good `.backup`; settings use UserDefaults. No companion cloud sync exists.

## Development checks

```sh
swift build --product Daywell
.build/debug/Daywell --ui-check
mkdir -p artifacts
.build/debug/Daywell --snapshot artifacts/graphite.png --theme graphite --expanded
.build/debug/Daywell --snapshot artifacts/capture.png --view capture
```

Snapshot options include `--theme graphite|sage|plum`, `--view
day|browse|capture|commands|help|settings|edit`, `--previous`, `--empty`,
`--permission`, `--long-title`, `--error`, and `--unpinned`.
These render the actual SwiftUI interface with disposable demo data.
`--ui-check` posts AppKit keyboard events through the running application.
It is not a substitute for live EventKit, cross-application hotkey, or VoiceOver tests.

An explicit `--live-check` mode creates a new **Daywell Test** list, exercises the
real EventKit adapter using disposable reminders, then cleans up its own fixtures.
It changes real Reminders data and must only be run with authorization. Launch it
through `open` so macOS attributes the permission request to Daywell rather than
the terminal. See the [live acceptance instructions](docs/verification.md#authorized-live-acceptance-attempt).
Ordinary operations and the recurring-completion safeguard passed live checks.
Earlier crashed-run fixtures and the final run's fixtures were cleaned up;
see the verification report for coverage and remaining release checks.

## Project

- Local checkout: `/Users/sanzoner/code/daywell`
- Private source repository: [ronsanzone/daywell](https://github.com/ronsanzone/daywell)
- [Personal Amp project](https://ampcode.com/@user_01KXFD6ZER08KBZSCQQ8YG7VM4/daywell)
- [Discovery and approval thread](https://ampcode.com/threads/T-01a0b56d-fed3-701e-87cc-178e8363ac7d)

The original Amp remote is retained as `origin`; the private GitHub repository is
the `github` remote. The existing discovery thread has not been moved or reassociated.
