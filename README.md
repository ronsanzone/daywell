# Daywell

A calm, keyboard-first macOS menu-bar companion for Apple Reminders.
Apple Reminders stores the tasks. Daywell helps you catch a thought in a second,
keep today's task in view, and feel each finish.

Working product name; trademark and distribution-name availability have not been assessed.

## Status

October 2026 rebuild (branch `rebuild/october-ux`): the capture bar, the menu-bar
ticker, today's pile, shelves as Reminders lists, the morning pull, and four themes.
Native SwiftUI/AppKit with EventKit. Ad-hoc signed and not notarized.

- [Approved functionality, including the October direction](docs/design/functionality.md)
- [Visual style guide and themes](docs/design/visual-style-guide.md)
- [Technical design, including the October architecture](docs/design/technical-design.md)
- [Verification results and remaining checks](docs/verification.md)

## Run

Requires macOS 14+ and the Swift 6 toolchain. Command Line Tools are enough.

```sh
swift test --disable-xctest
bash scripts/build-app.sh
open dist/Daywell.app
```

Try it with disposable fixture reminders (never touches EventKit):

```sh
swift build --product DaywellDev
.build/debug/DaywellDev --demo --theme waffleCat
.build/debug/DaywellDev --demo --fresh-day   # opens with the morning pull
```

The real app explains Reminders access before requesting permission. Once granted,
finishing, editing, capture, moves and deletion change Apple Reminders.

## Using it

- **⌃⌥Space** opens the capture bar over any app. Type and press ↵. Chips show the
  date and shelf it understood; `/work` picks a shelf, ⇥ cycles shelves, ⌥↵ also
  adds it to today. The bar flies into the menu bar and focus returns to your app.
- With the bar empty, **↓** moves into today's list: `x` finish, `p` pin to the menu
  bar, `r` not today, ⌘Z undo, ↵ open it in the panel. **⇥** opens the full panel.
- The **menu bar** shows the pinned task, or the first one you chose. Click its ring to
  finish it; click `+N` for the rest of today; `· undo` waits there until your next action.
- **Panel**: `j k` move, `gg G` ends, `x`/space finish, `p` pin, `a` pull from a shelf,
  `r` not today, `m` move to another shelf, `l h` open/close a shelf, `⌥↑ ⌥↓` reorder,
  `s` all shelves, `↵ e` edit, ⌘K commands, ⌘F search, `?` help, esc back then close.
- **Shelves** are Reminders lists. Apple doesn't let apps see list sections, so
  "Sort a list into shelves" (⌘K) walks a list one reminder at a time: `1–9` shelve,
  `t` today, `s` skip, `n` new shelf.
- **Morning pull**: on a fresh day, pick a few from yesterday's leftovers and the top
  of each shelf with number keys, then ↵. Unpicked leftovers go back to their shelves.
- **Services → Catch in Daywell** turns selected text in any app into reminders, one per line.
- Optional: **⌃⌥X** finishes the menu-bar task from anywhere (Settings; off by default).

Themes: **Quiet Native** (default), **Phosphor** (Amber CRT), **Waffle Cat**, **Flexoki Light**.
Each has its own finish motion, pile token and sound; sounds are off until you turn
them on. Maple Mono ships with the app under the SIL Open Font License
(`Resources/Fonts/OFL.txt`).

Repeating reminders can be finished, but when Apple Reminders advances the series,
Daywell says undo isn't available rather than moving the next occurrence back.

Your day plan is stored in `~/Library/Application Support/Daywell/day-plan.json`
with a last-good `.backup`. No companion cloud sync exists.

## Development checks

```sh
bash scripts/check.sh
```

Run `bash scripts/bootstrap-tools.sh` once if SwiftLint is missing. Ordinary checks
never access live EventKit, write personal reminders, package/install the app, or
re-sign the approved app. Development tools live in the `DaywellDev` executable,
which is never shipped:

```sh
.build/debug/DaywellDev --ui-check [--frames DIR]   # real windows, posted AppKit events, timings
.build/debug/DaywellDev --ui-check --fresh-day      # the morning pull
.build/debug/DaywellDev --snapshot DIR              # every surface in every theme
.build/debug/DaywellDev --bench                     # projection cost with years of history
```

`--live-check` changes real Reminders data in disposable lists and needs explicit
human authorization; see [verification](docs/verification.md).

Toolchain note: Swift 6.4's macOS 27 SDK turns `@State` into a macro whose plugin
ships only with Xcode. Views use the `ViewState` alias for the same property wrapper,
so Command Line Tools builds keep working.

## Project

- Local checkout: `/Users/sanzoner/code/daywell`
- Private source repository: [ronsanzone/daywell](https://github.com/ronsanzone/daywell)
