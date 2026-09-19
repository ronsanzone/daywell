# Daywell: code quality, architecture, and Swift anti-slop review

Reviewed September 19, 2026. Scope: all 18 production Swift files, all 5 test files, package manifest, build script, app metadata, and relevant product/design/verification documentation. The Swift source and tests total 3,164 lines. This is a review of the current repository, not a branch diff.

**Verdict: strengthen the existing design; do not rewrite it.** Daywell already has sensible value-based domain logic, a useful EventKit seam, conservative write behavior, and meaningful regression tests. The largest gaps are incomplete operation contracts, dispersed state ownership, and checks that depend on a developer remembering to run them. Most are not formatting problems.

The findings and grades below describe the pre-fix baseline. The subsequent approved implementation is summarized at the end of this report. Initial executable probes used disposable fixture stores and temporary plan files; they were removed afterward. No live Reminders operations, app re-signing, installs, pushes, or deployments were performed during this review or implementation.

## Grades

These are engineering judgments, not measured quality scores. Scale: 5 = workable but substantial maintenance friction; 7 = sound foundation with material localized gaps; 9 = clear boundaries and strong evidence across normal and failure paths; 10 = exceptional for the project's actual scope. Grade against a small native personal app, not an enterprise framework.

- **Extensibility: 7/10.** `ReminderStore`, value snapshots, injected dates/calendars, and the three-target dependency direction make new behavior approachable. However, adding a capture option, route, or settings behavior currently crosses mutable `AppModel` properties, views, commands, and sometimes `AppDelegate`. Tighten these contracts before adding more features.
- **Readability: 7/10.** Names mostly reflect product concepts; domain methods are short and tests describe behavior. Large SwiftUI expressions, many externally writable properties, and runtime/test machinery sharing `AppMain.swift` increase the amount a reader must hold in mind. Improve responsibility boundaries, not arbitrary line counts.
- **Clean architecture: 7/10.** `DaywellCore` does not import UI or EventKit, and EventKit objects become application-owned values at the adapter. The weak spot is presentation orchestration: command availability, navigation, draft lifetime, preferences, and persistence outcomes do not have consistently enforced owners. Concrete file storage inside Core is a pragmatic compromise, not an automatic architectural violation.
- **Pragmatic decisions: 8/10.** Native frameworks, plain Swift, three targets, one useful store protocol, small JSON persistence, and no production dependency framework are good choices. The recurring-undo safeguard is honest about platform limits. Deductions are for repair paths and verification tooling lagging behind the product, not for lacking more abstractions.

## What was actually verified

- `swift test --disable-xctest`: **43 tests in 5 suites passed**.
- `swift format lint --strict -r Sources Tests Package.swift`: **passed**.
- `swift build --product Daywell`: **passed**.
- `.build/debug/Daywell --ui-check`: **21 fixture-backed keyboard checks passed**.
- Installed toolchain: Swift **6.2.4**. Neither standalone SwiftLint nor Nick Lockwood's separate SwiftFormat executable was found on PATH. The toolchain's `swift format` is already available and used.
- Additional compiled fixture probes reproduced H1 and M1 below against the existing Core/Kit object files. These were model-level reproductions, not live EventKit reproductions.
- Inspected tracked files: no committed Swift formatter configuration, SwiftLint configuration, unified check script, or GitHub CI workflow currently exists.

The prior live EventKit acceptance evidence is documented in `docs/verification.md`; it was not rerun. VoiceOver, system-delivered global hotkeys, permission revocation, large stores, end-of-series/undated recurrence, and macOS 14 compatibility remain outside this run. Passing fixture checks is not a release certification.

## Research: your own recent repositories

GitHub inspection included manifests, actual implementation/tests, lint configuration, agent guidance, and available CI. These are examples of your established practices, not instructions to copy their web architecture.

### Portfolio and Borrius Companion: the closest policy match

Both actually depend on Effect 3.22.1. Their guidance explicitly says to use Effect for I/O and typed failures where useful, and ordinary functions for deterministic logic:

- [Portfolio AGENTS.md](https://github.com/ronsanzone/portfolio/blob/main/AGENTS.md)
- [Borrius Companion AGENTS.md](https://github.com/ronsanzone/borrius-companion/blob/main/AGENTS.md)

Concrete practices worth preserving:

1. **Validation belongs at the boundary.** Portfolio's [HTTP decoder](https://github.com/ronsanzone/portfolio/blob/main/app/src/server/http.ts) and Borrius's [request schemas](https://github.com/ronsanzone/borrius-companion/blob/main/app/src/server/schemas.ts) validate unknown input instead of casting it into legitimacy. For Daywell: validate persisted documents and preferences, and translate EventKit objects once into domain values. `Codable` checks representation, not every domain invariant.
2. **Small explicit ownership boundaries.** Client/server/shared/parser directories have named responsibilities. For Daywell, the existing Core/Kit/App targets already provide most of this separation. Do not add a framework per feature.
3. **Exceptions must name the invariant.** Both vendor Dillon Mulroy's generic and Effect anti-slop rules; their [lint configuration](https://github.com/ronsanzone/portfolio/blob/main/app/oxlint.config.ts) rejects type erasure, unsafe assertions, module mocking, and unhandled asynchronous work. Swift's equivalent is explicit actor/ownership contracts and local explanations for necessary unsafe operations—not banning framework-required `Any` tokens.
4. **One check contract, also used in CI.** Borrius's [scripts](https://github.com/ronsanzone/borrius-companion/blob/main/app/package.json) compose typechecking, lint, formatting, and tests; its [workflow](https://github.com/ronsanzone/borrius-companion/blob/main/.github/workflows/check.yml) also verifies vendored lint rules. Daywell needs the same repeatability with Swift-native tools.
5. **Prove external behavior.** Portfolio's [runtime adapter test](https://github.com/ronsanzone/portfolio/blob/main/app/test/cloudflare-runtime.test.ts) checks a real boundary; Borrius's [queue tests](https://github.com/ronsanzone/borrius-companion/blob/main/app/test/queue.test.ts) distinguish success, malformed input, and retryable failure. Daywell's capture write/refresh/plan sequence deserves that level of outcome testing.

### MongoBench and Oura Dashboard: useful counterexamples

The inspected manifests and source searches did **not** show Effect usage in either repository. Do not classify every recent TypeScript project as Effect-based.

- MongoBench's [report tests](https://github.com/ronsanzone/mongobench/blob/main/tests/report.test.ts) distinguish unknown, failed, completed, and successful outcomes. Its [container tests](https://github.com/ronsanzone/mongobench/blob/main/tests/native-container.test.ts) exercise rollback and cleanup failure. Transfer: a successful Reminders write is not proof of a successful local plan update; cleanup failure should remain visible.
- Oura's [pure calculations](https://github.com/ronsanzone/oura-dashboard/blob/main/packages/shared/src/index.ts) retain unavailable results instead of fabricating zero; its [HTTP tests](https://github.com/ronsanzone/oura-dashboard/blob/main/apps/dashboard-worker/test/http.test.ts) exercise bounded input and invalid encoding. Transfer: preserve absent/failed/stale distinctions without inventing a general effect system.

**Your consistent house style is evidence-preserving contracts and pragmatic boundaries, not maximum framework adoption.**

## Research: primary Swift and anti-slop sources

### Dillon Mulroy and Kit Langton

- [dmmulroy/anti-slop](https://github.com/dmmulroy/anti-slop): opinionated rules against low-evidence types, unsafe assertions, module mocking, and unnecessary complexity. The project explicitly encourages adapting policy. Borrow its requirement for evidence and narrow exceptions; do not translate TypeScript `unknown`, `typeof`, object spread, or Effect constructor restrictions into Swift regexes.
- [kitlangton/skills](https://github.com/kitlangton/skills): the public repository inspected exposes Effect and Code Walkthrough skills, not a Swift-specific anti-slop skill. Its [service guidance](https://github.com/kitlangton/skills/blob/main/skills/effect/references/SERVICES_LAYERS.md) emphasizes intentional interfaces/lifetimes; its [testing guidance](https://github.com/kitlangton/skills/blob/main/skills/effect/references/TESTING.md) favors explicit synchronization over sleeps; its [walkthrough guidance](https://github.com/kitlangton/skills/blob/main/skills/code-walkthrough/SKILL.md) requires running the narrowest proving check before explaining behavior.

### Swift and Apple: the baseline, not an architecture fashion

- [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/): “Clarity at the point of use” and “Clarity is more important than brevity.” Apply this to intent-revealing operations and outcome types, not longer names everywhere.
- [Apple: Managing model data](https://developer.apple.com/documentation/swiftui/managing-model-data-in-your-app) and [Model data](https://developer.apple.com/documentation/swiftui/model-data): a source of truth, `@Observable` models, bindings for legitimate editing, and local state for view-specific data. This supports Daywell's current Observation approach. It does not require a view model per view or TCA.
- [Swift concurrency](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency/): `await` marks a possible suspension point. Main-actor isolation prevents concurrent memory access; it does not make a multi-await operation atomic. Capture submitted intent before suspension and deliberately reconcile afterward.
- [swift-format configuration](https://github.com/swiftlang/swift-format/blob/main/Documentation/Configuration.md) and [rules](https://github.com/swiftlang/swift-format/blob/main/Documentation/RuleDocumentation.md): one formatting authority, explicit configuration, and a documented distinction between lint-only and autofixable rules. The locally installed defaults currently leave `NeverForceUnwrap`, `NeverUseForceTry`, and `NeverUseImplicitlyUnwrappedOptionals` disabled. “Format lint passed” does not imply unsafe-operation review passed.
- [SwiftLint](https://github.com/realm/SwiftLint): useful syntax checks, but not proof of architecture, correct actor behavior, safe EventKit writes, or absence of retain cycles. Pin the adopted release and confirm rule support in that release; upstream main can move.

### Concrete exemplar: KeyboardShortcuts

[sindresorhus/KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) is unusually relevant: SwiftPM, SwiftUI wrappers, AppKit/Carbon integration, and native shortcut lifecycle.

- Its [package](https://github.com/sindresorhus/KeyboardShortcuts/blob/main/Package.swift) stays small rather than introducing many architectural targets.
- Its [hotkey owner](https://github.com/sindresorhus/KeyboardShortcuts/blob/main/Sources/KeyboardShortcuts/HotKey.swift) pairs registration with teardown; [monitor utilities](https://github.com/sindresorhus/KeyboardShortcuts/blob/main/Sources/KeyboardShortcuts/Utilities.swift) use explicit start/stop ownership.
- Its [SwiftUI recorder](https://github.com/sindresorhus/KeyboardShortcuts/blob/main/Sources/KeyboardShortcuts/Recorder.swift) is a narrow bridge to the actual AppKit control, not a duplicate implementation.
- Its [SwiftLint configuration](https://github.com/sindresorhus/KeyboardShortcuts/blob/main/.swiftlint.yml) uses `only_rules`; [lint CI](https://github.com/sindresorhus/KeyboardShortcuts/blob/main/.github/workflows/swiftlint.yml) makes policy executable. Borrow the allowlist principle, not its full large rule set or tabs.
- Its [recorder tests](https://github.com/sindresorhus/KeyboardShortcuts/blob/main/Tests/KeyboardShortcutsTests/RecorderLayoutTests.swift) exercise real AppKit sizing/focus behavior with adjacent cleanup. This is a better next testing exemplar than adding more generic mocks.

Do not copy its process-global state into Daywell, or replace the current hotkey implementation with a dependency solely to conform to an exemplar. Plash was considered but its current public repository no longer exposes the app source; it is not used as architectural evidence.

### Concrete exemplar: isowords, selectively

Point-Free's isowords [file client](https://github.com/pointfreeco/isowords/blob/main/Sources/FileClient/Client.swift), [live implementation](https://github.com/pointfreeco/isowords/blob/main/Sources/FileClient/LiveKey.swift), and [test implementation](https://github.com/pointfreeco/isowords/blob/main/Sources/FileClient/TestKey.swift) show how small effect boundaries enable focused tests.

Daywell already achieves the important part with `ReminderStore`. Keep that protocol; do not replace it with closure clients just for stylistic consistency, introduce TCA, or copy isowords's package count. Add a storage failure seam only if existing temporary-file tests cannot exercise a real needed case.

### Swift Testing: deterministic and honest tests

The project's existing Swift Testing choice is appropriate. The [parallelization guide](https://github.com/swiftlang/swift-testing/blob/main/Sources/Testing/Testing.docc/Parallelization.md) supports isolated fixtures and narrow serialization for genuinely shared state. The [async testing guide](https://github.com/swiftlang/swift-testing/blob/main/Sources/Testing/Testing.docc/testing-asynchronous-code.md) supports explicit confirmations; confirmations themselves do not magically wait for arbitrary callbacks—the operation must be awaited or bridged. Use bounded completion/readiness checks, not blind delays. [Parameterized tests](https://github.com/swiftlang/swift-testing/blob/main/Sources/Testing/Testing.docc/ParameterizedTesting.md) can improve diagnostics for the capture grammar's equivalent cases without multiplying boilerplate.

## Findings

No critical defect was established. “Confirmed by trace” below means the code path was inspected, not that a live macOS scenario was exercised.

### H1. Capture can lose the requested My Day membership after a successful reminder write

**Severity: High. Lens: correctness / partial-success contract.** [AppModel.swift:209–238](../Sources/DaywellKit/AppModel.swift#L209-L238), [choose:116–119](../Sources/DaywellKit/AppModel.swift#L116-L119).

The save succeeds, then `refresh()` catches its own failure, then `choose(saved.id)` requires the new reminder to exist in the refreshed array. On fetch failure it does not, so the chosen membership is silently skipped. The draft and `captureAddToDay` are cleared and a “Saved to Inbox” notice is shown alongside the refresh error. The reminder survives, but the user's complete requested operation did not finish and cannot be recovered from the retained draft.

**Evidence:** compiled fixture reproduction produced `stored=1, commitments=0, notice=Saved to Inbox` with Add to My Day selected and the post-save fetch throwing.

Current control flow:

```swift
let saved = try await store.save(value, replacing: nil)
captureText = ""
await refresh()                         // catches errors; caller gets no outcome
if captureAddToDay { choose(saved.id) } // requires refreshed reminder to exist
```

Recommended control flow, illustrative rather than an implemented API:

```swift
let addToDay = captureAddToDay
let saved = try await store.save(value, replacing: nil)
// Clear only the submitted draft, because the remote reminder now exists.
// If requested, persist membership from this confirmed saved value.
// Return/report the local save outcome separately; never repeat remote creation.
await refresh() // reconciliation must not be a prerequisite for that membership
```

The local save function must communicate success/failure, not only mutate an error string. Preserve the returned reminder's identity/link hints. Report “reminder saved, day-plan update failed” when appropriate. Tests must cover remote failure, remote success plus fetch failure, remote success plus local failure, and retry without duplicate reminder creation.

### M1. Capture reads mutable submission intent after suspension

**Severity: Medium. Lens: actor reentrancy / ownership.** [AppModel.swift:209–238](../Sources/DaywellKit/AppModel.swift#L209-L238), [EditorView.swift:34–47](../Sources/DaywellKit/EditorView.swift#L34-L47).

`captureAddToDay` is read after `await refresh()`, while the toggle remains enabled. Changing it during the fetch changes the already-submitted operation. Cancel/navigation can also occur while the operation is running, but completion unconditionally switches the route to `.day`.

**Evidence:** a continuation-controlled fetch reproduced a submission with Add to My Day enabled ending with zero commitments after the toggle changed while refresh was suspended. This suspension point exists in the real EventKit adapter; the reproduction used a fake and did not require real reminders.

Snapshot submitted options before the first await; give busy UI and post-save navigation one deliberate policy. A second probe showed draft erasure if a store suspends inside `save`, but the current EventKit save body has no internal await. Treat that second result as a latent protocol-contract risk, not a demonstrated current live-store bug.

### M2. Returning to “Apple Reminders default” can retain the old custom inbox

**Severity: Medium. Lens: information leakage / correctness.** [AppMain.swift:149–155](../Sources/Daywell/AppMain.swift#L149-L155), [AppModel.swift:98–102](../Sources/DaywellKit/AppModel.swift#L98-L102), [SettingsView.swift:31–34](../Sources/DaywellKit/SettingsView.swift#L31-L34).

The settings option encodes Apple default as an empty string. On capture entry, the app delegate applies only a nonempty custom ID. Refresh picks the actual default only when the current capture list is invalid. Therefore: use custom list A, finish capture, select Apple default B in settings, open a fresh capture; valid A remains selected.

**Evidence:** confirmed by the two guards and their settings binding; not exercised via UI automation in this review. Resolve the effective inbox in one capture-entry operation, retaining an existing list only for an actual retained draft. Test custom → Apple default and a disappeared custom list with distinct A/B fixtures.

### M3. Recovery copy exists, but recovery has no usable application path

**Severity: Medium. Lens: completeness / failure ownership.** [Persistence.swift:14–47](../Sources/DaywellCore/Persistence.swift#L14-L47), [AppModel.swift:44–48](../Sources/DaywellKit/AppModel.swift#L44-L48), [143–160](../Sources/DaywellKit/AppModel.swift#L143-L160).

On a load failure the model correctly preserves the file and disables local changes. However, the app neither offers validated backup recovery nor tells the user how to perform it. `storageAvailable` remains false for that model's lifetime, even if a file is manually repaired. A backup is not yet a recovery workflow.

**Evidence:** confirmed by source inspection; existing tests already establish that corrupt/unsupported data is not overwritten. Add explicit recovery instructions or a small confirmed recovery action, preserving the corrupt original. Never silently replace an unknown future schema with an older backup. Test recovery with good/bad backup and unsupported schema separately.

### M4. Command policy and domain mutation are not consistently owned

**Severity: Medium. Lens: repetition / overexposure.** [Commands.swift:71–104](../Sources/DaywellKit/Commands.swift#L71-L104), [PanelView.swift:259–283](../Sources/DaywellKit/PanelView.swift#L259-L283), [AppModel.swift:5–35](../Sources/DaywellKit/AppModel.swift#L5-L35).

The command registry rejects editing a read-only reminder and rejects all commands while busy. Double-click and several menu handlers directly set editing/route or mutate the plan with different availability rules. Save still checks writability, so this is not evidence of unauthorized writes; it is inconsistent interaction policy. Publicly writable `plan`, `reminders`, `lists`, authorization, and busy state also let callers bypass the intended persistence/refresh contracts.

**Evidence:** confirmed by comparing these action paths. Keep bindings for genuine drafts, search, and selection. Make loaded/persisted state read-only to outside callers where practical. Centralize shared action preconditions in existing model operations or a narrow command context supporting an explicit reminder ID; do not force row actions to mutate global selection just to reuse a command.

### M5. Production lifecycle and verification mechanics share the app delegate

**Severity: Medium. Lens: mixed responsibilities / readability.** [AppMain.swift:23–428](../Sources/Daywell/AppMain.swift#L23-L428).

Startup, notifications, focus, keyboard routing, preferences observation, fixture flags, a 21-check event harness, and snapshot construction live together. `checkUI` and `snapshot` alone occupy roughly a third of the file. Reading or changing native lifecycle behavior unnecessarily exposes the reader to verification machinery. Hard sleeps in event checks also make slow environments harder to diagnose.

**Evidence:** confirmed by source structure. Extract cohesive verification support while preserving the same executable entry points; use debug-only compilation or a support target only when packaging needs justify it. Keep the native host and its lifecycle together. Replace event sleeps with bounded waits for the specific expected state where practical, retaining actual AppKit event delivery.

### M6. No executable repository-wide quality contract

**Severity: Medium. Lens: regression prevention.** [README.md](../README.md), [Package.swift](../Package.swift), [scripts/build-app.sh](../scripts/build-app.sh).

Formatting and tests currently pass, but the repository provides separate commands and a packaging script, not one required check or committed CI. The packaging script does not run tests/lint. It also re-signs the app, which the verification history shows can affect permission attribution; it should not be the default lint/test command.

**Evidence:** confirmed by tracked file inventory and baseline execution. Add one safe local check contract and a macOS CI equivalent, following Portfolio/Borrius. Keep interactive fixture UI checks separately callable and live Reminders writes explicitly opt-in.

### Lower-priority concerns and limits

- **Projection recomputation — performance/readability.** [AppModel.swift:50–73](../Sources/DaywellKit/AppModel.swift#L50-L73), [PanelView.swift:139–239](../Sources/DaywellKit/PanelView.swift#L139-L239). `projection` rebuilds maps/filters/sorts; views request it repeatedly, including per row. The adapter also fetches completed and incomplete reminders across accessible lists. This is real repeated work, but no slow UI was measured. Benchmark a representative large fixture before adding caches; first reuse a projection within a render and narrow subview inputs. Do not claim a demonstrated production performance defect.
- **Hotkey lifetime/rollback — resource ownership.** [GlobalShortcut.swift:10–38](../Sources/Daywell/GlobalShortcut.swift#L10-L38). Handler installation status and rollback status are ignored; there is no explicit teardown despite an unretained callback context. The current object is held for the app lifetime, so no current deallocation crash was established. Pair acquisition/release before expanding its lifecycle; test failed registration and failed restoration through a minimal API seam if needed. KeyboardShortcuts is the relevant exemplar.
- **Persisted invariants — boundary validation.** [Persistence.swift:42–47](../Sources/DaywellCore/Persistence.swift#L42-L47) checks decoding/schema version, not duplicate commitment identities, invalid day strings, or a dangling pin. No normal writer producing these was found. Document and validate the invariants that matter when treating the document as untrusted input; do not build a general schema framework.
- **Date identity — compatibility risk.** [DayPlan.swift:153–156](../Sources/DaywellCore/DayPlan.swift#L153-L156) stores year/month/day without calendar identity or era, using the supplied calendar. Switching the user's calendar system can reinterpret persisted ordering. Tests use Gregorian calendars. Define the supported storage calendar policy before changing serialization; do not silently migrate existing day strings.
- **Test hygiene.** [PersistenceTests.swift:7–12](../Tests/DaywellCoreTests/PersistenceTests.swift#L7-L12) creates temporary directories without cleanup. Some error tests accept any error and the refresh-order test spins with unbounded `Task.yield()`. Use owned fixture cleanup, specific expected failures, and bounded synchronization. Keep these secondary to missing behavior tests.
- **State representation.** `route == .edit` and `editing == nil` are representable and handled with a fallback view; this hides rather than prevents inconsistent navigation state. An associated-value edit destination would make that invariant explicit, but only adopt it as part of the navigation ownership cleanup, not a sweeping enum rewrite.

## Proposed Swift-native guardrails

### Automated: small, deterministic, low-noise

1. **Retain toolchain `swift format` as the only formatter.** Commit a `.swift-format` matching the current two-space/100-column style. No simultaneous SwiftFormat/SwiftLint layout rewrites. Pin/document the toolchain; do not copy upstream-main configuration options unsupported by Swift 6.2.4.
2. **Add pinned SwiftLint with an explicit `only_rules` allowlist.** Initial candidates: `force_cast`, `force_try`, `force_unwrapping`, `unhandled_throwing_task`, `private_swiftui_state`, `duplicate_imports`, `blanket_disable_command`, and `superfluous_disable_command`. Verify support and findings against the selected release before committing the configuration. These are candidate policies, not claimed results of a SwiftLint run.
3. **Handle invariant exceptions locally.** Literal regex construction, fixed fixture dates, AppKit setup storage, `@preconcurrency import EventKit`, `MainActor.assumeIsolated`, and Carbon's unretained pointer need different reasoning. Prefer checked code where inputs can fail; otherwise document the actual safety invariant near the exception. Never replace `try!` with a silent `try?` merely to turn a check green. Fixture/test exceptions should remain scoped.
4. **Use Swift 6 compilation as the concurrency gate.** The package already requests Swift tools 6.0 and builds with Swift 6.2.4. Run project builds with warnings treated as errors after assessing dependency noise. Do not add an obsolete collection of concurrency flags or blanket `@unchecked Sendable` workarounds.
5. **One safe check script:** formatter lint → SwiftLint strict lint → build → `swift test --disable-xctest`. Match CI to the validated toolchain and CLI-testing setup. CI should have read-only permissions and cancel superseded runs. Never run `--live-check` in ordinary CI; keep `--ui-check` on an executor with a real GUI session.
6. **A tiny dependency-boundary check, if useful:** Core must not import SwiftUI, AppKit, EventKit, or DaywellKit. The package graph already prevents target cycles; a small import check addresses framework drift, not a generalized architectural rule engine. Account for attributed imports such as `@preconcurrency import` if scripting it.

Do not initially adopt every opt-in rule, arbitrary file/function length caps, documentation quotas, required protocols, magic-number bans, or a regex-based “no slop” plugin. Defer `unused_import`/`unused_declaration` analyzer integration until its compiler-log setup and AppKit runtime false positives are understood. Promote vetted rules to blocking checks rather than accumulating a permanent warning backlog or a blanket baseline file.

### Review-only: the things a linter cannot establish

- One owner for each persistent value, submitted operation, and native resource.
- Snapshot user intent before `await`; explicitly decide which UI state may change afterward.
- Treat remote success, local persistence success, and successful refresh as distinct outcomes.
- Keep EventKit objects and unsafe framework assumptions at adapters; domain behavior uses values.
- Preserve metadata by updating only edited fields. Keep the approved recurring-undo exception.
- Keep unavailable/error/stale distinct from empty/success where the product needs the distinction.
- Prefer plain functions and existing seams. Every new abstraction must remove actual repeated policy or isolate a tested boundary.
- Test the observable result with asymmetric fixtures, injected failures, and controlled ordering—not only “no crash,” success notices, or mocks that reproduce the implementation.

This belongs in a short repository guidance file alongside the executable checks. A custom agent skill is optional later; it should invoke real checks and explain these contracts, not duplicate tooling in prose.

## Recommended implementation order

1. **Guardrails only.** Add formatter configuration, curated pinned lint, a safe check script, CI, and concise repository guidance. Keep any formatter-only diff separate from behavior changes. Establish the noise level before deciding on additional rules.
2. **Capture contract and inbox correctness.** Write failing regressions for H1/M1/M2; preserve submitted options; apply confirmed saved values without depending on refresh; report partial success precisely; resolve capture defaults in one owner. Verify that retries never duplicate remote reminders.
3. **Tighten ownership, preserve behavior.** Limit externally mutable loaded state; unify action preconditions; extract verification machinery from the native lifecycle. Keep the existing target graph and ReminderStore protocol. Avoid simultaneous feature redesign.
4. **Recovery and lifecycle hardening.** Define and test safe plan recovery; address hotkey acquisition/rollback/teardown and test cleanup. Any persistence format change requires explicit migration tests.
5. **Reverify the actual product.** Run all check gates and the fixture keyboard harness. For changed UI interactions, exercise pointer and keyboard paths plus busy/error/permission states. If appearance changes, inspect fresh renders. Live EventKit acceptance remains a separate authorized fixture-only run; do not rebuild/re-sign the approved bundle merely to run lint.

Do not promise a score increase from passing a linter. The desired improvement is that a new feature has one obvious owner, failures retain the user's intent, and the repository itself proves its important contracts.

## Considered and deliberately not recommended

- **TCA, a DI container, or an Effect-like Swift abstraction:** no demonstrated need; the existing store seam is already effective.
- **A database/cloud-sync rewrite:** the small atomic document is appropriate; solve recovery rather than replacing storage.
- **A protocol for every class or new target per feature:** increases navigation and coupling without an independent consumer/test requirement.
- **Blanket bans on `Any`, `try?`, or force unwraps:** AppKit tokens, disposable cleanup, and validated constants differ materially from unchecked user input. Require evidence, not token substitution.
- **Removing the Swift Testing dependency as “bloat”:** the documented Command Line Tools environment requires the pinned test-only package. It is not a production architectural dependency.
- **Calling the existing tests shallow:** DST ambiguity, half-hour overlaps, stale writes, out-of-order refresh, and recurring undo already have meaningful cases. Fill the cross-operation gaps rather than replacing the suite.
- **Automatic identifier relinking:** retaining unresolved commitments is safer than guessing by title. Persisted external/list hints are deliberate future reconciliation data, not necessarily dead fields.
- **More architectural layers as the goal:** the best parts of this code are precisely where the abstractions are few, useful, and explicit.

## Implementation follow-up — September 19, 2026

Implemented H1 and M1–M6 without changing the three-target architecture:

- Capture snapshots submitted intent, applies confirmed reminder identities before
  refresh, and reports local-plan failure without encouraging duplicate creation.
- Fresh capture resolves preferred inbox → Apple default → writable fallback;
  retained drafts keep their list.
- Explicit, confirmed backup recovery validates both documents, preserves corrupt
  bytes, rejects future schemas, and re-enables plan changes without a restart.
- Loaded/persisted state is externally read-only; row and keyboard operations use
  the same action preconditions. Deletion retains the snapshot the user reviewed.
- Fixture setup, snapshots, and the keyboard harness live in `DevelopmentChecks`,
  not the app delegate. Native event pacing remains in that smoke harness;
  the model's refresh-order regression now uses explicit async signals.
- Pinned SwiftLint 0.65.1, toolchain formatting, a narrow dependency import check,
  one safe `scripts/check.sh`, macOS CI, and progressively disclosed contributor
  guidance are in place. Temporary test files and fake-store callbacks have owners.

Verification: the complete local check passes with **56 tests in 5 suites** and
**zero SwiftLint violations**; **21 fixture AppKit keyboard checks** pass.
Fresh normal-day, capture, permission, and recovery snapshots were inspected.
Recovery persistence is tested at the store/model boundaries; the native recovery
confirmation and row-menu pointer paths still need hands-on acceptance.
The added CI workflow has not run remotely. No live EventKit acceptance was rerun,
and the installed/ad-hoc-signed bundle was not rebuilt or re-signed.

Remaining follow-ups are the lower-priority projection benchmark, hotkey
registration/teardown hardening, semantic document invariants, and a supported
calendar identity/migration policy. These were not silently folded into this
change. The baseline grades are retained rather than treating lint success as an
automatic architectural score increase.
