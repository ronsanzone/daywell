# Daywell

A calm, keyboard-first macOS menu-bar companion for Apple Reminders.
Apple Reminders stores the tasks. Daywell helps you choose a manageable day.

Working product name; trademark and distribution-name availability have not been assessed.

## Status

[Development Preview 3](https://github.com/ronsanzone/daywell/releases/tag/v0.1.0-dev.3):
Amber CRT, the Orbital Relay, selection and completion animations, and a task
patchbay alongside existing inline lists, safer capture, and backup recovery.
Native SwiftUI/AppKit with four themes and EventKit integration. A prior build
passed isolated live Reminders acceptance; this preview was verified with
disposable fixtures, not a new live run.
Ad-hoc signed and not notarized; broader integration and full accessibility
acceptance remain. See the [release notes](docs/releases/v0.1.0-dev.3.md).

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
- `b`: open the task patchbay: source lists on the left, My Day on the right.
- `s`: expand/collapse all secondary sections and lists. Click a heading, or
  focus it with Tab and press Space, to toggle one section.
- ⌘N: capture; ⌘F: browse/search; ⌘K: commands; ⌘,: settings; `?`: help.
- ⌘Return: save capture/edit; ⌘Z: undo completion outside text entry.
- Escape leaves text entry, then returns to My Day, then closes the panel.
- Letters always type normally inside fields. Tab traverses native controls;
  macOS Keyboard Navigation may be needed for all controls.

My Day stays visible above inline **Your Lists**. Due & overdue, From yesterday,
Done today, and each list start collapsed on launch; expansion is session-only.
List counts and collapsed previews include unfinished reminders not in My Day.
Expanded lists offer **+** to choose a reminder without changing its deadline or
source list. Rows already visible in an expanded date section are referenced
rather than repeated. Capture remains fixed below the scrolling content.

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
If the plan is unreadable, use **Restore day-plan backup…** and confirm recovery.
Recovery validates the backup and preserves the corrupt original beside the plan;
it never replaces a newer unsupported schema or changes Apple Reminders.

## Amber CRT experiment

The source build includes an opt-in **Amber CRT · experimental** theme in Settings.
It adds amber colors, phosphor-style text/selection glow, and a Metal-generated
scanline, grain, and vignette surface. The intensity slider defaults to 65%; 0%
removes that texture and glow. Graphite remains the default.

**Terminal motion** adds a small decorative Orbital Relay beside My Day, a 220 ms
selection afterglow, and completion/Undo traces after confirmed saves. The relay
aligns on opening and rests between slow rotations; it conveys no task or sync
status. Turn motion off independently of CRT intensity in Settings. macOS Reduce
Motion also disables it, and closing the panel stops the animation timelines.

The **task patchbay** is available in every theme. Use its header button or `b`,
then choose with **+**, `a`, or drag a reminder to the right pane. Source reminders
stay in their Apple lists and show **Chosen**; the right-hand minus removes only
the local My Day commitment. Amber sends a brief signal across the gutter after
the plan saves. Existing inline lists and ⌘F search remain available.

Try it without installing or re-signing the approved app, and without live Reminders:

```sh
swift build --product Daywell
.build/debug/Daywell --demo --theme amber --crt-intensity 0.85
```

The shader compiles at runtime (no offline Metal compiler required) and generates
a static texture when its surface is created or resized. The texture itself has
no continuous render loop, flicker, or distortion; optional motion uses separate
SwiftUI timelines. Text entry remains native. If Metal is unavailable, an
on-screen notice explains the texture fallback.
Demo preferences are disposable. Use Settings in a normal source-built session to
persist a theme; the existing installed release has not been updated by this experiment.

## Development checks

```sh
bash scripts/check.sh
```

If required development tools are missing, run
`bash scripts/bootstrap-tools.sh` explicitly, then rerun the check. Ordinary
checks never access live EventKit, write personal reminders, package/install the
app, or re-sign the approved app. See the
[development reference](docs/development.md) for focused commands and Swift
conventions.

Fixture-backed native UI checks and snapshots are separate:

```sh
swift build --product Daywell
.build/debug/Daywell --ui-check
mkdir -p artifacts
.build/debug/Daywell --snapshot artifacts/graphite.png --theme graphite --expanded
.build/debug/Daywell --snapshot artifacts/capture.png --view capture
```

Snapshot options include `--theme graphite|sage|plum|amber`, `--crt-intensity 0…1`, `--view
day|browse|patchbay|capture|commands|help|settings|edit`, `--previous`, `--due`, `--lists`, `--empty`,
`--permission`, `--long-title`, `--error`, `--recovery`, and `--unpinned`.
These render the actual SwiftUI interface with disposable demo data.
`--lists` opens the inline lists; `--due` opens Due & overdue.
`--no-motion` renders with terminal motion disabled. To capture native animation
frames (selection, completion, Undo, patchbay choice, and relay drift):

```sh
.build/debug/Daywell --snapshot artifacts/terminal-final.png \
  --theme amber --crt-intensity 0.85 --motion-sequence artifacts/terminal-frames
```

The sequence writes 200 PNG frames at a target 20 fps using disposable reminders.
`--ui-check` posts AppKit keyboard and pointer events through the running application.
It is not a substitute for live EventKit, cross-application hotkey, or VoiceOver tests.

An explicit `--live-check` mode creates a new **Daywell Test** list, exercises the
real EventKit adapter using disposable reminders, then cleans up its own fixtures.
It changes real Reminders data and requires explicit human authorization. Launch it
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

The private GitHub repository is `origin`; the original Amp remote is retained as
`amp`. The existing discovery thread has not been moved or reassociated.
