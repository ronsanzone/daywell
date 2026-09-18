Pickup is inheritance: read this document and the artifacts it names instead of re-deriving them, and verify inherited claims against the real artifacts before building on them.

# Apple Reminders Companion — Research and Product Handoff

Date: 2026-09-18  
Next-session focus: continue product discovery with Ron through a one-question-at-a-time functionality interview, then produce a concise agreed functionality description. Do not implement yet.

## Goal and current state

The product idea is a native macOS app that uses Apple Reminders as its backend and adds a menu-bar item that opens a drop-down panel. It should help people with ADHD quickly understand, capture, triage, start, and complete reminders with less friction than opening the full Reminders app.

This session completed market research and analyzed three key inspirations:

1. **Barrie** for menu-bar speed, natural-language capture, keyboard operations, and visible completion.
2. **Daycard** for a calm, bounded daily card and warm visual character.
3. **Linear** for keyboard grammar, command actions, triage, hierarchy, saved views, and lifecycle concepts.

No code, product spec, or implementation plan was created. No repository files were changed. The current repository (`/Users/sanzoner/code/sites`) is an unrelated personal-sites codebase and already contains unrelated untracked files that must not be modified:

```text
?? SAN-32-cloudflare-mcp-handoff.md
?? docs/tickets/
?? goals/personal-sites-cloudflare-deploy/cloudflare-access-migration-ledger.md
```

The tree was not built or tested because this was research-only work and no code changed. No background processes or subagents are running.

### Visual comparison already produced

A three-concept menu-bar mockup compares:

- A — Now Stack
- B — Triage Deck
- C — Day Runway

Artifact: https://ampcode.com/user-content/attachments/7bf8e4e8d0d05bded0fdc7f8e331dc248670877b1efbe0e6ec759d59073158b7-file.png

The mockup was inspected. It successfully distinguishes the three models, but its blue/white visual language now feels more generic than the warmer Daycard/Linear direction discovered later.

## What is next

Run an interactive product interview with Ron. Ask exactly one consequential question at a time, preferably with 3–4 concrete choices and a recommendation. Keep a running set of accepted, rejected, and unresolved functionality. Challenge features that add setup, duplicate Apple Reminders, or create another productivity system users must maintain.

The first question had just been asked but Ron redirected before answering:

> What should opening the panel primarily accomplish?
>
> A. Capture and manage — immediately search, add, complete, or edit reminders; closest to Barrie.  
> B. Decide what to do now — show a deliberately small Today list with one current task; closest to Daycard.  
> C. Process the system — open into Inbox/Triage for quickly routing reminders; closest to Linear.  
> D. Adaptive home (recommended) — normally open to Today/current task; when unprocessed reminders accumulate, quietly surface Triage; capture is always available.

Restart with that question or improve it if Astra sees a clearer first decision. Then cover, in roughly this order:

1. Default panel job and information hierarchy.
2. Whether Today is automatic (due/overdue) or an explicit commitment list.
3. Whether the app has an Inbox/Triage concept and what enters it.
4. Reminder lifecycle: open, in progress, complete, snoozed.
5. Capture model: one search/add field, natural-language syntax, dictation, capture selected text.
6. Keyboard model: global shortcut, `Cmd-K`, navigation and action shortcuts.
7. Planning horizon: Today only vs Today + Week vs Day Runway/calendar.
8. ADHD support: Rescue Mode, smaller-step decomposition, and guilt-free reset.
9. Saved/context views: quick wins, calls, errands, low energy, waiting.
10. Detail editing and when to open Apple Reminders instead.
11. Menu-bar status/count behavior and notification philosophy.
12. Local companion metadata and privacy expectations.
13. MVP boundary and explicit non-goals.

After the interview, write a concise functionality description grouped by core loop, supporting operations, ADHD-specific support, Apple Reminders integration, and non-goals. Seek explicit approval before writing a spec or implementing.

## Research findings

### Market baseline

The market already contains strong point solutions:

- **Reminders MenuBar** already offers menu-bar access, a global shortcut, natural-language creation, search, filtering, reminder editing, configurable menu counts, and Apple Reminders sync. Merely making a compact Reminders list is not differentiated.  
  Source: https://github.com/damascenorafael/reminders-menubar
- **GoodTask** provides powerful views, filters, quick actions, boards, and calendar integration on top of Reminders. User feedback repeatedly describes it as powerful but configurable, cluttered, and sometimes overwhelming. This is the main warning against feature breadth.  
  Source: https://apps.apple.com/us/app/goodtask/id1143437985?mt=12
- **Due** owns persistent reminders and rapid postponement.  
  Source: https://www.dueapp.com/
- **Structured** makes the day visible as a timeline.  
  Source: https://structured.app/
- **Tiimo** targets executive-function needs with visual schedules, focus timers, task breakdown, and flexible planning.  
  Source: https://www.tiimoapp.com/
- **Things** demonstrates calm presentation and progressive disclosure, but uses its own task system rather than Apple Reminders.  
  Source: https://culturedcode.com/things/

The identified market gap is an **executive-function layer over existing Apple Reminders**, focused on three questions:

1. What should I do now?
2. How do I begin?
3. How do I recover when the system becomes overdue or overwhelming?

### Apple/EventKit capability boundary

Apple's public EventKit API supports core reminder properties:

- Title
- Notes
- Reminder list/calendar
- Start and due date components
- Priority
- Completion and completion date
- Alarms, including structured location alarms
- Recurrence rules
- URL and location inherited from `EKCalendarItem`

Official sources:

- https://developer.apple.com/documentation/eventkit/ekreminder
- https://developer.apple.com/documentation/eventkit/ekcalendaritem

Do not assume public EventKit access to newer Apple Reminders concepts such as tags, subtasks, sections, or attachments. Product concepts must not depend on complete access to those features.

Companion-only concepts may require private local/iCloud metadata linked to an EventKit reminder identifier:

- In-progress state
- Custom ordering
- Estimated duration
- Energy requirement
- Surface-after/snooze time that does not alter the true deadline
- Today/this-week commitment
- Processed/unprocessed state

The rule should be: Apple Reminders remains authoritative for the reminder; companion metadata augments it and must never be necessary to recover the underlying task.

## Inspiration 1: Barrie

Official site: https://getbarrie.com/  
Demo video: https://getbarrie.com/assets/demo.mp4  
About: https://getbarrie.com/about  
Privacy: https://getbarrie.com/privacy

Official positioning:

> Barrie is the menu bar companion to Apple Reminders. It is not a new to-do app.

Barrie is a native macOS utility for macOS 14+, sold for €7.50 once after a two-day trial. It has no account or reminder server; data stays in Apple Reminders and iCloud.

### Observed demo flow

The demo was inspected frame by frame:

1. A menu-bar panel opens over Apple Reminders.
2. A persistent field reads “Search or add a reminder.”
3. Typing `renew the passport friday !` creates live date and priority chips.
4. Submitting immediately adds the reminder and updates Apple Reminders.
5. Typing `pick up flowers @albert heijn` opens a location suggestion and Apple Maps geofence preview.
6. Completing several reminders collapses rows, provides an Undo action, decreases the active count, and increases “Done today.”

### Best Barrie concepts

- Live menu-bar counts for overdue/today/due-now/etc.; a clear day becomes a checkmark.
- One field combines filtering and creation.
- Natural-language parsing previews dates, times, lists, locations, priority, recurrence, and batches as chips before creation.
- Keyboard-first operations: filter by typing, Space to complete, Enter to edit, Command-Delete to delete.
- Global shortcut and a panel that does not steal focus.
- “Add to Barrie” macOS Service captures selected text from any app.
- Completed work remains in a Done Today section.
- Panel can be pinned and resized.
- Privacy and adoption story: no migration, account, server, or separate sync.

### Product lesson

Barrie already provides much of the original baseline extremely well. A product that stops at Barrie's functionality is not meaningfully differentiated.

## Inspiration 2: Daycard

X announcement: https://x.com/OmarShahine/status/2100603820019777709  
Official site: https://omarknows.app/daycard/  
Press kit: https://omarknows.app/daycard/press/  
App Store: https://apps.apple.com/app/id6802847587  
Screenshot: https://omarknows.app/daycard/assets/screenshot/daycard-today-framed.png

Official positioning:

> Reminders, one day at a time.

Daycard is available on iPhone, iPad, and Mac for OS 26+. It turns Apple Reminders into one calm daily card while preserving Reminders as the source of truth.

### Functionality

- Today: unfinished due/overdue work plus only reminders completed today.
- Next: future reminders grouped by date.
- Someday: ideas stored in an optional Someday Reminders list.
- Lists: access to the underlying Reminders lists.
- Open, in-progress, and complete states.
- Custom ordering synced privately through iCloud.
- Natural-language capture and dictation using on-device Apple Foundation Models with a parser fallback.
- Rich details: notes, links, location, priority, dates, alerts, recurrence.
- Widgets and sharing.
- No account, ads, analytics SDK, tracking, or developer-operated cloud.

### Visual language

- Warm cream/off-white surfaces rather than clinical white.
- Near-monochrome palette with muted tan accents.
- Large editorial date typography.
- One dominant rounded card.
- Numbered rows create a finite sequence.
- Generous vertical rhythm and soft separators.
- Completed and deferred work remains visible with a strikethrough.
- Progress is descriptive (“1 of 5 done”), not gamified.
- Add Task is integrated into the card.
- Calm is created through whitespace and bounded scope.

### Product lesson

Daycard is stronger than the initial blue/white mock in visual taste. It provides an emotional and visual model, but its full-app daily ritual is not itself the desired menu-bar operating model.

## Inspiration 3: Linear

Product: https://linear.app/  
Design refresh: https://linear.app/now/behind-the-latest-design-refresh  
Triage: https://linear.app/docs/triage  
Inbox: https://linear.app/docs/inbox  
Filters: https://linear.app/docs/filters  
Cycles: https://linear.app/docs/use-cycles  
Issue creation: https://linear.app/docs/creating-issues

### Visual principles

- “Don’t compete for attention you haven’t earned.”
- Main work remains prominent while orientation/navigation recedes.
- Warm gray/charcoal neutrals instead of cold blue-black.
- Small semantic status icons and restrained accent colors.
- Compact, highly predictable rows.
- Secondary metadata is muted and fixed in position.
- Borders and separators are softened so structure is felt rather than seen.
- Contextual controls avoid permanent chrome.
- Linear creates calm through hierarchy rather than Daycard-style whitespace.

### Operational principles

- `C` creates from anywhere.
- `Cmd-K` exposes contextual commands.
- Keyboard sequences navigate globally; J/K or arrows navigate lists.
- Context provides sensible defaults during creation.
- Triage forces a small set of decisions: accept, duplicate, decline, or snooze.
- Priority Inbox separates what requires attention from everything else.
- My Issues distinguishes personal commitments from shared/global work.
- Saved filters create focused reusable views.
- Cycles bound work into recurring time windows, automate routine, and roll unfinished work forward.
- Drafts preserve interrupted capture.

### Mapping to a personal Reminders app

| Linear | Reminders companion |
| --- | --- |
| Issue | Reminder |
| Team/project | Reminders list |
| Description | Notes |
| Priority | Reminder priority |
| Due date | Reminder due date |
| Recurring issue | Recurring reminder |
| Backlog | Undated reminders |
| My Issues | Today's personal commitments |
| Triage | New/unprocessed reminders |
| Status | Open/completed plus local in-progress |
| Cycle | A locally curated week |
| Saved view | Context lens: Calls, Quick Wins, Errands, Low Energy |
| Snooze | Local surface-after time, preserving the real due date |
| Command menu | Universal reminder action palette |

### What not to borrow from Linear

- Team/assignee concepts
- Issue identifiers
- Multi-column project boards
- Deep nested sidebars
- Configurable workflow builders
- Multiple status taxonomies
- Analytics, productivity scoring, or burndown charts
- Projects, initiatives, milestones, releases, and roadmaps
- Rich label systems that require maintenance

These optimize organizational coordination and would increase personal executive-function load.

## Ten UX concepts previously explored

1. **Now Stack** — one dominant Now task, followed by Next and Later.
2. **Triage Chute** — process one reminder at a time into Do Now, Today, Pick a Time, Someday, or Delete.
3. **Rescue Mode** — “I’m stuck” asks available capacity and offers one plausible task, a smaller step, or another choice.
4. **Day Runway** — reminders on a visual timeline among calendar commitments.
5. **Momentum Deck** — card stack with fast complete/defer/split controls.
6. **Command Bar** — Spotlight-like text interface for capture, search, and management.
7. **Context Lens** — Quick Wins, At Home, Going Out, Calls, Low Energy, Deep Focus.
8. **Focus Capsule** — one reminder, optional timer, notes/first step, finish/pause/reschedule.
9. **Guilt-Free Reset** — neutral recovery flow for overdue reminders with previewable bulk actions and Undo.
10. **Adaptive Drop-Down** — Today by default, with explicit transitions into planning or recovery modes when warranted.

The pre-Linear recommendation was Now Stack + Rescue Mode + Guilt-Free Reset with a Command Bar. Later research refined the synthesis toward Barrie + Daycard + Linear.

## Current product synthesis

The strongest formula reached so far is:

- **Barrie supplies the interaction engine:** menu-bar access, global shortcut, combined search/add, natural-language chips, direct manipulation, keyboard speed, and visible completion.
- **Daycard supplies the emotional surface:** warm restrained visual style, bounded Today card, visible completed work, descriptive progress, and low-pressure language.
- **Linear supplies the operational grammar:** triage, command palette, predictable row anatomy, contextual actions, personal commitments, saved views, and a lightweight work lifecycle.
- **The new product must supply the differentiator:** ADHD-oriented support for choosing, starting, and recovering.

Candidate internal thesis:

> Apple Reminders stores everything. This app helps you act on it.

Candidate product description:

> A fast, ADHD-friendly execution layer for Apple Reminders. Capture anything from the menu bar, triage it with a few keystrokes, choose a realistic day or week, and move reminders from open to in progress to done—without migrating to another task system.

Candidate panel structure, not yet approved:

```text
Menu bar: 3 today · 1 overdue

Inbox 2       Today 5       Week
────────────────────────────────
◐  Call dentist              10m
○  Submit expenses      Work 2pm
○  Pick up prescription  Errand
●  Take vitamins             Done
────────────────────────────────
Search or add a reminder…   ⌘K
```

Potential contextual command set:

- Complete reminder
- Start working
- Move to Today
- Move to Friday
- Snooze until afternoon
- Set priority
- Move to list
- Open in Apple Reminders
- Break into smaller steps

## Decisions made and why

These are research-level conclusions, not yet approved product requirements:

1. **Apple Reminders remains the source of truth.** Migration and another account/system directly conflict with the low-friction ADHD goal.
2. **A plain menu-bar Reminders client is insufficient differentiation.** Barrie and Reminders MenuBar already cover it.
3. **The product should optimize execution, not task storage or project management.** The gap is deciding, starting, and recovering.
4. **Progress should remain visible without streaks or guilt.** Done Today is useful; productivity scoring is not.
5. **Keyboard and pointer interactions must both be first-class.** Linear/Barrie speed should not make the product inaccessible to ordinary mouse users.
6. **Progressive disclosure is essential.** GoodTask demonstrates the overwhelm risk of exposing all power at once.
7. **Do not silently rewrite reminder semantics.** Local snooze or commitment metadata should not change a true deadline unless the user explicitly chooses to reschedule.
8. **Warm restrained visual language is preferred over the generic blue SaaS appearance in the first mock.** Daycard and Linear are the stronger visual references.

## Open questions

Nothing below is settled. Resolve these through the interview:

1. Is the default surface Today, Capture/Search, Triage, or adaptive?
2. Does Today mean due/overdue automatically, an explicit commitment list, or a mixture?
3. How many commitments should Today encourage, if any limit exists?
4. What enters Inbox/Triage: all new reminders, only undated reminders, externally created reminders, or optional items?
5. Is in-progress state valuable enough to justify companion metadata?
6. Should Week exist at all, or does it create too much planning overhead?
7. Is Day Runway/calendar context part of v1 or an attractive distraction?
8. Should Rescue Mode automatically suggest a task, ask for capacity, or only break down a selected task?
9. Should task decomposition use AI, deterministic prompts, or neither in v1?
10. What does Guilt-Free Reset do automatically versus only preview?
11. Which menu-bar count is calming rather than anxiety-producing?
12. What notification behavior adds value beyond Apple Reminders without duplicating it?
13. Which saved views deserve product-level support versus user configuration?
14. Should local metadata sync via private iCloud, remain local to one Mac, or be avoided initially?
15. Is this a Mac-only utility, or should an iPhone companion eventually expose Today/Rescue?
16. What is the minimum useful v1 that distinguishes the product from Barrie?

## Environment facts

- Current local workspace: `/Users/sanzoner/code/sites`
- Runner ID: `de9210b2-a9d5-4e0c-a385-535aa41e31dd`
- The repository is unrelated to the proposed reminders app. Do not scaffold into it until Ron chooses a repository/location and approves a design.
- Current Amp thread: https://ampcode.com/threads/T-01a0b547-6478-702c-86b4-32b7be8c1d1f
- No credentials, ports, services, test processes, or app code are involved yet.
- X MCP was unavailable in the source session. Public X post metadata was recovered through X oEmbed and product sites. Do not claim the complete Davey Heuser tweet history was read.

## Suggested skills

- Continue with **brainstorming** for the architectural product interview. Respect its implementation approval gate.
- Use **frontend-design** only after the product direction is approved and visual exploration begins.
- Use **create-prd** or a design/spec workflow only after the functionality set is agreed.
- Use **writing-plans** only after an approved design/spec exists.

## Next-agent kickoff

Tell Ron you have inherited the research and will continue one decision at a time. Ask the first high-leverage functionality question, record the answer, and continue the interview without prematurely producing a specification or code.
