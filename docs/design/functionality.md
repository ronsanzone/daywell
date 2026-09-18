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
- Settings offer **Graphite & Taupe** (default), **Porcelain & Sage**, and **Linen & Plum**.
  These change colors, not the layout.
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
