# Daywell visual style guide

Status: layout approved September 18, 2026; themes revised October 18, 2026.
Exact metrics below are proposed starting tokens, not pixel-level user approvals.
Generated images are design references, not runnable UI or behavior-verification evidence.

## Primary reference: Linear Precision

![Approved layout reference](references/07-linear-precision.png)

Use its compact, predictable rows; aligned status-icon column; restrained date;
subtle separators; secondary metadata; trailing contextual actions; and keyboard
command palette with shortcut help. Keep the native menu-bar utility scale.
Do not add a desktop-project sidebar or a grid of cards.

The hierarchy is My Day commitments (one optional pin), Due & overdue,
From yesterday, Done today, and a separate capture control. Completed rows use
subdued but readable text and strikethrough. Done today is collapsed by default;
the reference expands it to demonstrate completion styling. (October 2026: today's
pile replaces the collapsed section; see functionality.md.)

## Themes

October 18, 2026: Ron chose four selectable themes from the dream-board theme mocks.
Each fills the same slots (surface, type, ring, finish motion, pile token, sound,
Day clear) and never changes layout or keys. Porcelain & Sage and Linen & Plum are
retired. Finish motions last about 300 ms, sounds are opt-in, and all motion
respects Reduce Motion.

### Quiet Native — default (refined Graphite & Taupe)

- Background `#242527`, raised `#2D2F32`, text `#E8E7E3`, secondary `#AAACAE`,
  accent `#B6A48F`, highlight `#E3D3BF`. SF Pro.
- Finish: ring fills taupe with one spring overshoot; check strokes in; strike draws
  left to right. Token: rounded taupe square, newest glows highlight. Sound: soft "tock".

### Phosphor — Amber CRT, committed

- Existing Amber tokens: background `#130E08`, raised `#251A0E`, text `#FFDBA8`,
  secondary `#E0BD8C`, accent `#FFBB59`.
- Finish: the row flares bright and settles; ring becomes a lit block; the Orbital Relay
  makes one orbit per completion. Token: phosphor bar. Sound: short 880 Hz beep.
  Text fields stay outside the CRT layer, as today.

### Waffle Cat — from Ron's Ghostty theme (dark)

- Background `#292025`, deep `#1F181C`, raised `#362D30`, text `#FFF4D8`,
  secondary `#A58C82`, accent `#C87D2A`, highlight `#E4C56D`. Maple Mono, falling back
  to the system monospaced face.
- Finish: ring fills caramel with one small spring; caramel strike. Token: rounded
  caramel square, newest glows honey. Sound: soft "pat". Keep it plain: palette only,
  no waffle motifs.
- Contrast: secondary on raised is 4.24:1; use secondary text on the background only,
  or lighten it on raised rows.

### Flexoki Light — from Ron's dotfiles (light)

- Background `#FFFCF0`, page `#F2F0E5`, rules `#DAD8CE`, text `#100F0F`,
  secondary `#6F6E69`, accent `#205EA6`. Maple Mono.
- Finish: each completion takes the next Flexoki ink (red, orange, yellow, green, cyan,
  blue, purple, magenta) for its ring and strike; the pile becomes a row of ink dots.
- Contrast: the 400-level yellow `#D0A215` (2.3:1) and cyan `#3AA99F` (2.8:1) fail 3:1
  on the background. Use Flexoki's 600-level inks for rings and tokens; verify the
  exact values against the official palette before shipping.

### Menu bar limits

A status item gets an attributed title and a small template image. Themes keep the
ticker plain and put their character in the panel and capture bar. Ring animation in
the menu bar, if any, uses image frames. This is inferred from AppKit and not yet
tested in Daywell.

Graphite and Amber tokens are implemented; Waffle Cat and Flexoki Light are proposed
and still need the contrast checks noted above. Keyboard selection uses a full-opacity accent outline, separate
from the pin symbol. Normal primary/secondary/accent text is checked against both
background and raised surfaces; disabled states and native controls still require
the complete accessibility acceptance pass. Aim for at least 4.5:1 normal text and
3:1 meaningful non-text controls; do not infer whole-app compliance from token ratios.

## Typography and geometry

Starting proposal: system SF Pro; 14-point task text, 12–13-point secondary labels,
20-point semibold My Day heading. Use proportional body text and native keycaps.
No oversized editorial heading in the approved layout.

Start with a roughly 400-point-wide popover, 36-point single-line task rows,
16-point side padding, and 16-point status symbols. Allow multiline content and
scrolling within available screen height. Keep capture reachable when lists grow.
Validate these dimensions in a real rendered panel rather than copying image pixels.

## Circle and pin grammar

- **Open:** thin empty ring. Actual v1 reminder completion state.
- **Done:** filled circle containing a contrasting check. Actual v1 completion state.
- **Pinned:** independent pin symbol and restrained row emphasis. At most one current pin.
- **In progress:** half-filled circle, **reserved only**. No v1 control, command,
  domain state, stored field, or menu-bar indicator may imply it is implemented.

Shape carries meaning independently of color. Accessibility labels must expose
completion and pinning separately. A pinned task can be completed without ever
passing through an in-progress state.

## Interaction styling

- Distinguish keyboard focus from pinned emphasis; they are not interchangeable.
- Keyboard selection is visible in every theme and never only a subtle text-color change.
- Context actions appear on keyboard focus as well as pointer hover.
- Search and capture remain separate. Show removable/editable date interpretation
  before saving natural-language input.
- Command palette actions show relevant shortcuts; shortcut help is itself keyboard-accessible.
- The menu bar shows the ticker task as text by default (October 2026); no red
  badges or overdue counts.
- Completion feedback is animated per theme ("no ledger"): reward the act, but no
  streaks, scores, urgency colors for ordinary overdue work, or timers. Respect reduced motion.

## Corrections to generated references

- Replace reference 7's half-filled reminder circle with an open circle in v1;
  retain the separate pin. Use a neutral app glyph in the menu bar.
- Do not copy its red overdue date. Use readable, neutral secondary text.
- Generated shortcut bindings are illustrative and inconsistent between images;
  the implementation must define one reviewed command registry.
- From yesterday's collapsed disclosure points right, not down as drawn in 7.
- Remove marketing copy, reference-sheet labels, and generated text errors.
- Removing from My Day means removing a commitment, never deleting a reminder;
  use a minus/removal symbol, not a trash icon.

## Required rendered review

Inspect all four themes with keyboard focus, pinned and unpinned tasks, long titles,
empty My Day, overdue items, yesterday reset, expanded Done today, command palette,
shortcut help, natural-language preview, and permission/error states. Capture and
inspect real screenshots when the app exists. These mockups do not satisfy that check.
