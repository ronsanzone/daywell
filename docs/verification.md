# Daywell development verification

## October 2026 rebuild — source build, October 18, 2026

Environment: macOS 27 arm64, Swift 6.4 Command Line Tools. Fixture data only;
no live EventKit access, installation or re-signing of the approved app.

- `bash scripts/check.sh` passed: formatting, SwiftLint (0 violations), dependency
  boundaries, build, and **66 tests** (41 core, 25 kit).
- `DaywellDev --ui-check` (release build) passed **59 checks**, and `--ui-check
  --fresh-day` passed **9**, using AppKit events posted through the application
  queue to the real capture bar, panel and menu-bar ticker windows.
- Timings from that run: `showCapture()` to window on screen 3.0 ms median (6.1 ms
  worst, n=10); posted keypress to finish motion 5.5 ms; keypress to confirmed finish
  with 12 ms simulated EventKit latency 20 ms. `--bench`: projection with 20,000 completed reminders took 29.6 ms
  on the old all-reminders fetch, 0.013 ms on the new two-query fetch.
- Inspected snapshots of every surface in all four themes, the menu-bar ring states,
  and frame sequences of each theme's finish, the capture-bar finish and Day clear.
  Frames are view renders (`cacheDisplay`), not screen captures.
- **Not verified here:** real key focus after a physical ⌃⌥Space press (this
  harness gets no window key focus from macOS at all, even after `NSApp.activate`);
  on-screen pixels (Screen Recording isn't granted); the Services menu entry in a
  registered app; audible sounds; VoiceOver; and live EventKit. `--live-check` was
  denied Reminders access when run from the agent's process; run
  `bash scripts/live-check.sh` from a terminal to let macOS ask on Daywell's behalf.
  It also reports whether a reminder keeps its identifier when moved between lists.


Date: September 18, 2026. Environment: macOS arm64, Swift 6.2.4 Command Line Tools.
This is a local development build, not a release certification.

## Development Preview 3 release

- Re-ran `bash scripts/check.sh`: formatting, lint, boundaries, build, and all
  **71 tests passed**. Built the optimized Apple Silicon bundle as **0.1.0 (3)**.
- The packaged executable passed **58 fixture-backed native UI checks each in
  Graphite and Amber**. Inspected its fresh Amber patchbay snapshot at 85% CRT.
- Signature and metadata validation passed. Extracted the ZIP and compared its
  executable and metadata with the tested bundle. The
  [release notes](releases/v0.1.0-dev.3.md) record its SHA-256 checksum.
- Packaging/re-signing the local `dist/Daywell.app` and GitHub publication were
  authorized for this release. No installation or live EventKit access occurred.
  This remains an ad-hoc-signed, non-notarized development preview.

## Terminal motion and task patchbay — source build

- `bash scripts/check.sh` passed: formatting, SwiftLint, dependency boundaries,
  build, and **71 tests**. New regressions cover confirmed-write-only feedback,
  refresh failure after success, unconfirmed completion/Undo, local choice failure,
  duplicate choices, preserved source reminders, and the motion/accessibility policy.
- The native `--ui-check` passed **58 checks each in Graphite and Amber**. Added
  actual pointer selection in the patchbay, `b/a/r/x/⌘Z/h`, the Terminal motion
  checkbox, and explicit panel visibility lifecycle checks. Busy/read-only write
  policy is covered by model tests; this is not a full accessibility acceptance run.
- Inspected native animation keyframes at **85% CRT**: selection afterglow,
  completion contraction, Undo return, the gutter signal, and relay drift.
  The fixture-only `--motion-sequence` writes 200 PNG frames, without time injection
  into production views. Compared corresponding motion-off frames pixel-for-pixel:
  selection, completion, Undo, and choosing remain stable after their state changes.
- Inspected long-title, error, permission, empty, Graphite, and motion-off layouts.
  Source overflow stays inside its scroll view. Local captures are in
  `artifacts/terminal-motion/`, including an animated `demo.gif` and a keyframe sheet.
- **Remaining manual checks:** a physical native drag/drop, VoiceOver and full Tab
  navigation, and toggling macOS Reduce Motion itself. Its shared policy is tested,
  but the system setting was not changed. No new live EventKit, packaging,
  installation, re-signing, or release publication occurred.

## Development Preview 2 release — September 19, 2026

After explicit approval to release the complete checkout:

- Re-ran `bash scripts/check.sh`: formatting, lint, boundaries, build, and all
  **61 tests passed**. The debug native event harness passed **39 checks**.
- Built a fresh optimized Apple Silicon bundle with `bash scripts/build-app.sh`.
  Version is **0.1.0**, build **2**. The newly built bundle's fixture-only
  `--ui-check` passed the same **39 checks**.
- `codesign --verify --deep --strict` and `plutil -lint` passed. Inspected a fresh
  bundle-rendered snapshot at `artifacts/release-panel.png`.
- Packaged `Daywell-v0.1.0-dev.2-macos-arm64.zip`, extracted it again, verified its
  signature, and compared the extracted executable with the tested executable.
  The [release notes](releases/v0.1.0-dev.2.md) record the archive checksum.
- The bundle is ad-hoc signed, not notarized. No live EventKit acceptance or
  personal reminder writes occurred; no installation was performed. Replacing
  the local `dist/Daywell.app` and re-signing it were authorized for this release.

The implementation-stage entries below describe their state before packaging.

## Inline reminder lists — September 19, 2026

- `bash scripts/check.sh` passed: formatting, zero SwiftLint violations,
  dependency boundaries, build, and **61 tests**. The new regressions cover
  collapsed defaults, section toggling without data changes, grouped remaining
  reminders, read-only lists, stable counts, selection reconciliation, and
  session-only expansion state.
- `.build/debug/Daywell --ui-check` passed **39 checks**, including actual
  pointer clicks to expand/collapse a list and choose a reminder with its plus
  button, `s` expansion/collapse, skipping hidden rows, and literal `s` in capture.
  Pointer checks use logical coordinates in the fixed fixture layout, not AX
  discovery; this is not a VoiceOver or full Tab-traversal acceptance test.
- Inspected fresh native `artifacts/inline-*.png` snapshots: collapsed and
  expanded lists, all date sections open, all three themes, long/unpinned title,
  empty, error, and permission states. Overflow stays in the scroll region;
  capture stays below it. Busy/read-only action policy is covered by model tests.
- No live EventKit access, packaging, installation, or re-signing. The existing
  `dist/Daywell.app` is unchanged; use `.build/debug/Daywell --demo` to try this build
  with disposable data.

## Quality follow-up — September 19, 2026

- `bash scripts/check.sh` passed: toolchain formatting, SwiftLint 0.65.1
  (**zero violations**), Core dependency boundary scan, build, and **56 tests**.
- `.build/debug/Daywell --ui-check` passed **21 fixture-backed keyboard checks**.
- Inspected fresh day, capture, permission, and backup-recovery snapshots in
  `artifacts/quality-*.png`. The recovery control and error banner are readable.
- New regressions cover capture partial success and submitted intent, inbox
  selection, busy/read-only action policy, preserved deletion snapshots, and
  validated recovery without overwriting future schemas or corrupt evidence.
- CI is configured but not yet run remotely. Pointer-path and recovery-alert
  acceptance remain manual; model tests do not substitute for those checks.
- No live Reminders checks, app packaging, installation, or re-signing occurred.
  `dist/Daywell.app` still contains the prior build, not these source changes.

The live results below are historical evidence for the September 18 build.

## Latest live result — passed

After Ron approved the unchanged bundle, `artifacts/live-check-6.log` confirmed:

- Both identified leftovers from the crashed run and their empty test list removed.
- Capture, date/time editing, alarm/URL preservation, ordinary completion/undo,
  stale-write rejection, external refresh, and deletion passed.
- Recurring completion released the commitment, retained the completed occurrence,
  and kept the next occurrence at its advanced deadline with recurrence intact.
- Invoking unavailable undo left both occurrences unchanged.
- The final run's disposable reminders and new list were cleaned up.

No pending test-fixture cleanup remains. Do not rerun the historical recovery
command below: its target list has been removed. The existing `dist/Daywell.app`
is ready for a local hands-on trial without rebuilding or re-signing. Broader
release checks remain listed at the end of this report.

## Executed checks

- `swift format lint --strict -r Sources Tests Package.swift` — passed.
- `swift test --disable-xctest` — **43 tests in 5 suites passed**.
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

## Authorized live acceptance attempt

Ron authorized an isolated **Daywell Test** list and disposable reminders in the
discovery thread. The new `--live-check` mode requests permission before creating
anything. It never reuses an existing calendar; fixture writes and cleanup are
restricted to the newly created list and a unique per-run title prefix. The
normal local day plan and preferences are not loaded or changed by this mode.

The initial live attempt **blocked at macOS permission**, timing out before list creation.
No reminders or calendars were changed in that initial attempt. A direct executable
launch was attributed to Ghostty by TCC; the retry used LaunchServices (`open`)
to launch Daywell normally, but permission was still not granted. The runner
could not approve the native prompt through its available controls.

The release build, 41 unit/model tests, 21 fixture keyboard checks, and format lint
were rerun successfully after adding this mode. Combining `--live-check` with
`--demo` was verified to exit with status 2 before requesting access.

Resume on the Mac running Daywell after granting it Reminders permission:

```sh
mkdir -p artifacts
open -n -W --stdout "$PWD/artifacts/live-check.log" \
  --stderr "$PWD/artifacts/live-check-errors.log" \
  "$PWD/dist/Daywell.app" --args --live-check
cat artifacts/live-check.log artifacts/live-check-errors.log
```

Use the normal app launch rather than running its executable from a terminal so
macOS requests Daywell's permission, not the terminal's. `open` returning zero
only proves launch/exit; inspect the log for test and cleanup results. Permission
waits are bounded at 60 seconds. The planned checks include date-only capture,
timed editing, alarm/URL preservation, completion/undo, stale-write rejection,
external refresh, deletion, recurrence metadata, and fixture cleanup. These passed
in run 6 under the approved recurring-undo exception; see the latest result above.

### Follow-up after permission was granted

- The first authorized run created a test list, then crashed during cleanup.
  The crash report identifies a main-actor assertion inside the test harness's
  `fetch` mapping closure on `com.apple.eventkit.reminders.search`. Making the
  callback explicitly `@Sendable` fixed that crash in the next live run.
- The next run passed list discovery, date-only capture, no added alarm, title/
  notes/timed-date editing, existing alarm/URL preservation, ordinary completion
  and undo, stale-write rejection, external refresh, and deletion.
- That run failed **recurring reminder can be completed**: the adapter's saved
  snapshot was not marked completed. The later diagnostic run established why,
  as described below; recurring undo is not validated.
- Cleanup of that second run's reminders and new list passed. Its local evidence
  is `artifacts/live-check-2.log`. The first crashed run's list/fixtures may still
  remain and must be inspected before cleanup; never delete by list name alone.
- A diagnostic build now logs only test-list recurrence snapshots and identifiers
  needed to identify prior fixtures. Its launch was blocked by permission again.
  TCC logs explicitly reported a code-requirement mismatch after rebuilding the
  ad-hoc-signed app. No valid development signing identity is installed.
- After approval, `artifacts/live-check-4.log` confirmed that completing the daily
  fixture advances the original ID to the next day's deadline, still incomplete,
  and creates a separate completed reminder with a different ID. Reversing the
  original snapshots would move the next deadline backward, not undo completion.
  This run cleaned up its own fixtures and list successfully.
- The source now clears unsafe undo when EventKit returns a different completion
  state. A same-ID advance releases the current commitment and reports that undo
  is unavailable; an unconfirmed result leaves the commitment intact and reports
  an error. Ron subsequently **approved this v1 recurring-undo exception** after
  reviewing the risk; it is recorded in `design/functionality.md`.
  End-of-series and undated recurrence remain unverified.
- Before the approval decision: **43 unit/model tests**, strict format lint, and **21
  fixture keyboard checks** passed using `.build/debug/Daywell --ui-check`.
  The approved bundle was initially left unchanged to avoid another prompt.
  After approval it was rebuilt as recorded below; live validation is still pending.
- The first crashed run left exactly two identified fixtures. Pending recovery
  must verify list ID `7B78C648-D4A9-4406-A918-269029F18382`, title prefix
  `Daywell acceptance D323C1A3-9AC6-4C49-8FE2-87D8471B4ECB`, and reminder IDs
  `FF501A83-7922-43C7-A21C-EF62F1B40579` and
  `DABFFC47-13C0-4580-8869-F63960E7E011` before deleting. Delete the list only
  after verifying it is empty. Do not delete other same-named lists or reminders.
- Ron chose to defer signing setup. The latest release bundle now includes the
  safeguard and explicit fixture recovery. All **43 tests**, **21 release-bundle
  keyboard checks**, format lint, and signature verification passed. Malformed
  recovery arguments were verified to return status 2 before requesting access.
- `artifacts/live-check-5.log` records the latest attempt: permission timed out
  before fixture recovery or new list creation. No Reminders writes occurred in
  this attempt. The two earlier fixtures are still pending cleanup.
- At that point, the next action was to approve Daywell and retry the command below
  without rebuilding. Accessibility and screen-capture preflights are both false
  on the runner. No keychain, certificate, or system permission changes have been
  made by the agent.

Historical command — successfully executed; do not repeat recovery:

```sh
open -n -W --stdout "$PWD/artifacts/live-check-6.log" \
  --stderr "$PWD/artifacts/live-check-6-errors.log" \
  "$PWD/dist/Daywell.app" --args --live-check --recover-fixtures \
  7B78C648-D4A9-4406-A918-269029F18382 \
  'Daywell acceptance D323C1A3-9AC6-4C49-8FE2-87D8471B4ECB' \
  FF501A83-7922-43C7-A21C-EF62F1B40579,DABFFC47-13C0-4580-8869-F63960E7E011
```

Recovery requires all fetched entries to match the supplied reminder IDs and run
prefix in the exact list. Each object is rechecked before removal; the list is
removed only after a fresh empty query. Normal `--live-check` without recovery
arguments does not touch prior runs. Inspect logs before retrying: if recovery
already succeeded, omit its arguments on subsequent acceptance runs.

## Still not verified

- **Live EventKit:** beyond the passed isolated run, verify read-only/deleted lists,
  permission revocation, end-of-series and undated recurrence, and date-only timezone
  behavior before release. Recurring undo remains excluded when the series advances.
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

Live-test authorization covers disposable fixtures only, not unrelated personal
reminders. Ron separately authorized committing and pushing the source to a private
GitHub repository. App distribution and deployment remain outside that authorization.
