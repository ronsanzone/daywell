# Approved functionality

Status: approved by Ron on September 18, 2026, with subsequent visual and naming decisions incorporated.
Source: [product discovery thread](https://ampcode.com/threads/T-01a0b56d-fed3-701e-87cc-178e8363ac7d).
Research in `research-handoff.md` is background, not an additional requirements list.

## Core daily loop

- Open the menu-bar panel to **My Day**, the user's explicitly chosen commitments.
- Make one optionally pinned task prominent. Pinning another replaces it.
  Pinning does not create an in-progress state.
- Browse or search existing Apple Reminders lists to choose commitments.
  Encourage starting with 1–3, without a cap, warning, or extra steps to add more.
- Show **Due & overdue** separately from chosen commitments. Choosing for My Day
  never changes a deadline or moves a reminder out of its existing Reminders list.
- On a new day, show unfinished prior commitments under **From yesterday**.
  Keep all, choose a few, or release commitments without deleting or rescheduling reminders.
- Put completed work in a collapsed **Done today** section, with undo of completion.
  Approved v1 exception: when Apple Reminders advances a repeating reminder to
  its next occurrence, completion remains supported but undo is unavailable in
  Daywell. Explain this explicitly rather than rescheduling the next occurrence.
  Ordinary non-repeating completion retains undo. Ron approved this limitation
  after reviewing the observed EventKit behavior on September 18, 2026.

## Capture and operations

- Natural-language capture is separate from search. Preview interpreted dates
  and times before saving; let the user correct or remove an interpretation.
- Capture defaults to a Reminders inbox with an optional **Add to My Day** choice.
  A due date alone does not create a My Day commitment.
- No mandatory triage, processing queue, or unprocessed status.
- Edit title, notes, due date/time, and list; complete and delete reminders.
  Richer settings are handled in Apple Reminders.
- Every action is keyboard-accessible. Include a configurable global shortcut,
  searchable command palette, and discoverable shortcut-help pop-up.
  Pointer interaction is also supported.
- Neutral menu-bar icon by default. Settings can enable a count of unfinished
  My Day commitments. No overdue badge or added notifications; existing Apple
  Reminders alerts remain independent.

## Appearance

- Use concept 7, **Linear Precision**, for layout and hierarchy.
- Settings offer **Quiet Native** (default, refined Graphite), **Phosphor** (Amber CRT),
  **Waffle Cat** and **Flexoki Light** (October 2026; replaces Porcelain & Sage and
  Linen & Plum). Themes change surface, type, completion motion, pile token and sound,
  never the layout or keys. See the visual style guide.
- Use open and checked completion circles, with a separate pin symbol.
- Preserve the half-filled in-progress circle in the style guide as a reserved
  future design only. Do not implement its state, actions, or persistence in v1.

## Storage and privacy

- Apple Reminders is authoritative for underlying reminders and their supported fields.
- My Day choices and the pin are companion-specific and local initially.
- Design persistence to accommodate eventual sync without losing existing choices.
  Do not implement sync now.

## Explicit exclusions

No Week commitment list, calendar timeline, dedicated rescue mode, automatic task
suggestions, AI breakdown, focus sessions, timers, Start/Pause state, mandatory
triage, or gamification. Future reminders remain available through browse/search.

## October 2026 direction: catch, ticker, pile, shelves

Source: Ron's dream-board thread, October 17–18, 2026. Market research, storyboards
and theme mocks live outside the repo (see the thread). Where this section conflicts
with an earlier one, it wins; each superseded rule is named.

**Rule change.** "No gamification" becomes **no ledger**: reward each completion in the
moment; never keep a streak, score, badge or any count that can go down against the user.

**Catch.** ⌃⌥Space opens a floating capture bar over the current app, not the panel
(supersedes "global shortcut opens the panel"). Typing captures: chips preview the parse,
`/name` or ⇥ picks a shelf, ↵ saves to the inbox, ⌥↵ also adds to My Day. On save the
bar flies into the menu bar and focus returns to the previous app. Selected text from
any app can be caught through a macOS Service, one reminder per line.

**One door, two rooms.** With the bar empty, today's tasks are listed under it in order.
↓ or ⌃n moves into that list, where j/k move, `x` completes, `p` pins, `r` releases, and
⌘Z undoes. ⇥ with the bar empty opens the full panel. Single-letter actions never apply
while the text field has focus.

**Ticker.** The menu bar shows the pinned task as text with a completion ring, or the
first My Day task in chosen order when nothing is pinned (supersedes "neutral menu-bar
icon by default"; Settings can return to the plain icon). Clicking the ring completes
the task; undo stays in the ticker until the next action. Clicking "+N" lists the other
tasks; choosing one pins it. With nothing chosen the ticker reads "Choose today"; when
everything is done it reads "Day clear · N" until midnight. No overdue counts or red.

**Pin and order.** The pin means "the task in view", not an in-progress state. My Day
keeps chosen order; ⌥↑/⌥↓ reorder in the panel. Completing the pin does not pin the next
task automatically.

**Today's pile** replaces the collapsed Done today section (supersedes "collapsed Done
today"). Each completion lands a token on a visible pile with the theme's finish motion;
finished titles are listed beneath it. The pile resets quietly at midnight.

**Shelves.** Work that isn't today lives on shelves, and each shelf is a Reminders list,
so iPhone and Siri see it. EventKit exposes no sections or tags (checked in the macOS 27
SDK headers), so Daywell cannot read sections. A one-time optional sort moves items from
a single sectioned list into shelf lists, one key per item. In the panel, shelves appear
under My Day as one-line peeks: `l` opens one in place, `a` pulls a task up into My Day
(the reminder stays in its list), `r` releases it back, `m` moves it to another shelf.

**Morning pull** replaces From yesterday on the first open of a day: simple chips for
yesterday's leftovers and the top two tasks of each shelf; pick with click or space, ↵
starts the day, Esc skips. Kept deliberately minimal; richer chip detail was tried and
rejected as too busy.

Still open, with proposed defaults: the morning pull appears only when My Day is empty or
yesterday left leftovers; an optional global ⌃⌥X completes the ticker task (off by
default). To verify before building the sort: whether a reminder keeps its identifier
when moved between lists.

## Implementation details resolved in the approved technical design

The subsequent technical-design approval settled these defaults without expanding
the product scope:

- Vim-inspired navigation alongside arrows, a searchable command palette, and
  ordinary text entry unaffected by motions. Exact bindings are documented in README.
- Start with Apple's writable default list; allow choosing an inbox in Settings.
- Include accessible reminders completed today outside Daywell in Done today.
- Show chosen due reminders once in My Day, with deadline metadata.
- Group all unfinished prior days together; use current local-calendar days.
- Target macOS 14+ with a local development app initially.

Live EventKit behavior, accessibility, and distribution still require validation;
technical-design approval does not imply that those checks have passed.
