import AppKit
import DaywellCore
import DaywellFixtures
import DaywellKit

/// Drives the real windows with AppKit events posted through the application queue,
/// the same path a keyboard takes. Asserts outcomes, records timings, and optionally
/// writes frame sequences of the key motions.
@MainActor final class UICheck {
  let controller: AppController
  let store: FixtureReminderStore
  let frames: URL?
  var passed = 0
  var failures: [String] = []
  var timings: [String: [Duration]] = [:]
  var model: DayModel { controller.model }

  init(controller: AppController, store: FixtureReminderStore, frames: URL?) {
    self.controller = controller
    self.store = store
    self.frames = frames
    if let frames { try? FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true) }
  }

  func check(_ condition: Bool, _ label: String) {
    if condition {
      passed += 1
      print("PASS: \(label)")
    } else {
      failures.append(label)
      print("FAIL: \(label)")
    }
  }

  func wait(_ milliseconds: Int) async { try? await Task.sleep(for: .milliseconds(milliseconds)) }

  /// Posts a real key-down event to the window, through NSApp's event queue.
  func key(
    _ characters: String, code: UInt16 = 0, modifiers: NSEvent.ModifierFlags = [],
    to window: NSWindow, settle: Int = 60
  ) async {
    guard
      let event = NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: modifiers,
        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
        context: nil, characters: characters, charactersIgnoringModifiers: characters,
        isARepeat: false, keyCode: code)
    else {
      check(false, "construct key event \(characters)")
      return
    }
    NSApp.postEvent(event, atStart: false)
    await wait(settle)
  }

  func type(_ text: String, into window: NSWindow) async {
    for character in text { await key(String(character), to: window, settle: 8) }
    await wait(80)
  }

  static let codes: [String: UInt16] = [
    "return": 36, "escape": 53, "tab": 48, "down": 125, "up": 126, "left": 123, "right": 124,
    "space": 49, "x": 7, "p": 35, "r": 15, "a": 0, "j": 38, "k": 40, "l": 37, "h": 4, "m": 46,
    "s": 1, "z": 6, "1": 18, "2": 19, "3": 20,
  ]

  func press(_ name: String, modifiers: NSEvent.ModifierFlags = [], to window: NSWindow, settle: Int = 80)
    async
  {
    let characters: String
    switch name {
    case "return": characters = "\r"
    case "escape": characters = "\u{1b}"
    case "tab": characters = "\t"
    case "space": characters = " "
    case "down": characters = String(UnicodeScalar(NSDownArrowFunctionKey)!)
    case "up": characters = String(UnicodeScalar(NSUpArrowFunctionKey)!)
    case "left": characters = String(UnicodeScalar(NSLeftArrowFunctionKey)!)
    case "right": characters = String(UnicodeScalar(NSRightArrowFunctionKey)!)
    default: characters = name
    }
    await key(characters, code: Self.codes[name] ?? 0, modifiers: modifiers, to: window, settle: settle)
  }

  func time(_ label: String, _ duration: Duration) { timings[label, default: []].append(duration) }

  /// Writes a frame sequence of a window while an action plays.
  func record(_ name: String, window: NSWindow, frames count: Int = 30, every ms: Int = 16) async {
    guard let directory = frames, let view = window.contentView else { return }
    let folder = directory.appendingPathComponent(name)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    for index in 0..<count {
      if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(
          to: folder.appendingPathComponent(String(format: "%03d.png", index)))
      }
      await wait(ms)
    }
  }

  func run() async -> Int32 {
    let panel = controller.panelWindow
    let bar = controller.captureWindow
    await wait(300)
    let frontmostBefore = NSWorkspace.shared.frontmostApplication?.processIdentifier
    let me = ProcessInfo.processInfo.processIdentifier

    // 1. The menu bar shows the pinned task, truncated, with the rest counted.
    check(model.today.tickerTask?.id == "mitigation", "ticker task is the pinned task")
    check(
      controller.ticker.text == "Create mitigation ticke…  +2",
      "ticker shows the pinned title, truncated to 24, plus the count (\(controller.ticker.text))")

    // 2. The capture bar opens without activating Daywell.
    for _ in 0..<10 {
      let start = ContinuousClock.now
      controller.showCapture()
      time("capture bar open (hotkey handler → window on screen)", ContinuousClock.now - start)
      if !bar.isVisible { check(false, "capture bar is on screen when the handler returns") }
      controller.hideCapture()
      await wait(30)
    }
    controller.showCapture()
    await wait(150)
    check(bar.isVisible && bar.canBecomeKey, "capture bar is on screen and can take keyboard focus")
    // This harness runs without a user event, so macOS grants no window key focus at all
    // (a plain window after NSApp.activate isn't key either). Real key focus after the
    // hot key is a manual check; events here are delivered to the window directly.
    print("NOTE: key focus granted by macOS: \(bar.isKeyWindow) (needs a real hot-key press)")
    check(bar.styleMask.contains(.nonactivatingPanel), "capture bar is a non-activating panel")
    check(!NSRunningApplication.current.isActive, "Daywell never becomes the active app")
    if let frontmostBefore, frontmostBefore != me {
      check(
        NSWorkspace.shared.frontmostApplication?.processIdentifier == frontmostBefore,
        "the previously frontmost app stays frontmost while typing")
    }

    // 3. Typing shows the parse as chips, picks a shelf with /work, and saves on Return.
    await type("ask sean re qa run tmrw at 2pm /work", into: bar)
    let result = controller.capture.result
    check(controller.capture.text == "ask sean re qa run tmrw at 2pm /work", "typed text reaches the field")
    check(result.title == "ask sean re qa run", "title is what's left after date and shelf")
    check(result.hasTime && result.dueDate != nil, "\"tmrw at 2pm\" becomes a timed due date")
    check(controller.capture.targetListID == "work", "\"/work\" targets the Work shelf")
    await record("capture-save", window: bar, frames: 4)
    let saveStart = ContinuousClock.now
    await press("return", to: bar, settle: 30)
    for _ in 0..<40 where !store.items.contains(where: { $0.title == "ask sean re qa run" }) {
      await wait(10)
    }
    time("capture Return → saved in Reminders", ContinuousClock.now - saveStart)
    let saved = store.items.first { $0.title == "ask sean re qa run" }
    check(saved?.listID == "work" && saved?.hasDueTime == true, "capture saved to Work with its time")
    check(controller.ticker.text == "→ Work", "ticker flashes where it landed (\(controller.ticker.text))")
    await wait(450)
    check(!bar.isVisible, "capture bar flies away after the save")

    // 4. One door, two rooms: ↓ enters today's list; p pins; x finishes with motion first.
    controller.showCapture()
    await wait(120)
    await press("down", to: bar)
    check(controller.capture.listIndex == 0, "↓ moves from the field into today's list")
    await press("j", to: bar)
    check(controller.capture.listIndex == 1, "j moves down the list")
    await press("p", to: bar)
    check(model.today.pinnedID == "slo", "p pins the selected task")
    await wait(1300)  // Let the "→ Work" flash finish.
    check(controller.ticker.text.hasPrefix("Look into SLO dashboard"), "pinning changes the menu bar task")
    controller.capture.listIndex = 0
    let pileBefore = model.today.pile.count
    var finishingAt: ContinuousClock.Instant?
    var finishedAt: ContinuousClock.Instant?
    model.feedback.listen { event in
      if event.kind == .finishing, finishingAt == nil { finishingAt = .now }
      if event.kind == .finished, finishedAt == nil { finishedAt = .now }
    }
    let pressed = ContinuousClock.now
    await press("x", to: bar, settle: 0)
    let frameTask = Task { await self.record("finish-capture-bar", window: bar, frames: 36) }
    await wait(700)
    _ = await frameTask.value
    if let finishingAt { time("keypress → finish motion starts", finishingAt - pressed) }
    if let finishedAt { time("keypress → Reminders confirmed (12 ms simulated latency)", finishedAt - pressed) }
    check(finishingAt != nil, "finish motion starts on the keypress")
    check(model.today.pile.count == pileBefore + 1, "the finished task lands on today's pile")
    check(model.reminder("slo")?.isCompleted == true, "the reminder is completed in Reminders")
    await press("escape", to: bar)
    await press("escape", to: bar)
    check(!bar.isVisible, "esc leaves the list, then closes the bar")

    // 5. Ticker: the ring finishes the shown task; undo waits in the ticker.
    check(controller.ticker.region(atX: 8) == .ring, "the ticker's left edge is the ring")
    let tickerTask = model.today.tickerTask?.id
    controller.ticker.clickRing()
    await wait(600)
    check(tickerTask.flatMap { model.reminder($0)?.isCompleted } == true, "clicking the ring finishes the ticker task")
    check(controller.ticker.text.contains("· undo"), "undo waits in the menu bar (\(controller.ticker.text))")
    controller.ticker.clickUndo()
    await wait(300)
    check(tickerTask.flatMap { model.reminder($0)?.isCompleted } == false, "undo in the menu bar reopens it")

    // 6. The panel: keyboard only.
    controller.showPanel()
    await wait(250)
    check(panel.isVisible && panel.canBecomeKey, "panel opens and can take keyboard focus")
    check(panel.styleMask.contains(.nonactivatingPanel), "panel is non-activating too")
    check(!NSRunningApplication.current.isActive, "opening the panel doesn't activate Daywell")
    let first = model.today.myDay.first?.id
    check(controller.panelState.selection == first.map { .task($0) }, "selection starts on the first task")
    await press("j", to: panel)
    let second = model.today.myDay.dropFirst().first?.id
    await press("down", modifiers: .option, to: panel)
    check(model.today.myDay.first?.id == first && model.today.myDay.last?.id == second, "⌥↓ reorders My Day")
    await press("z", modifiers: .command, to: panel, settle: 150)
    check(model.today.myDay.dropFirst().first?.id == second, "⌘Z undoes the reorder")
    controller.panelState.selection = second.map { .task($0) }
    let workCount = model.today.shelves.first { $0.id == "work" }?.items.count ?? 0
    await press("r", to: panel)
    check(second.map { !model.isChosen($0) } == true, "r takes the task off today")
    check(
      (model.today.shelves.first { $0.id == "work" }?.items.count ?? 0) == workCount + 1,
      "it reappears on its shelf")
    controller.panelState.selection = .shelf("devex")
    await press("l", to: panel)
    check(controller.panelState.expandedShelves.contains("devex"), "l opens a shelf in place")
    await press("j", to: panel)
    let pulled = controller.panelState.selectedReminderID
    await press("a", to: panel)
    check(pulled.map(model.isChosen) == true, "a pulls a shelf task into My Day")
    await press("h", to: panel)
    check(!controller.panelState.expandedShelves.contains("devex"), "h closes the shelf")
    controller.panelState.selection = pulled.map { .task($0) }
    await press("m", to: panel)
    check(controller.panelState.route == .move(pulled ?? ""), "m opens the shelf chooser")
    let targetIndex = model.writableLists.firstIndex { $0.id == "work" } ?? 0
    controller.panelState.moveIndex = targetIndex
    await press("return", to: panel, settle: 200)
    check(pulled.flatMap(model.reminder)?.listID == "work", "↵ moves it to the chosen shelf")
    check(pulled.map(model.isChosen) == true, "its My Day choice follows the move")
    await press("s", to: panel)
    check(!controller.panelState.expandedShelves.isEmpty, "s opens all shelves")
    await press("s", to: panel)
    await press("?", to: panel)
    check(controller.panelState.route == .help, "? opens keyboard help")
    await press("escape", to: panel)
    check(controller.panelState.route == .today, "esc goes back")

    // 7. A failed save reverses the motion and says why.
    controller.panelState.selection = model.today.myDay.first.map { .task($0.id) }
    let failing = controller.panelState.selectedReminderID
    store.failNextSave = .changed
    await press("x", to: panel, settle: 500)
    check(failing.flatMap(model.reminder)?.isCompleted == false, "a rejected finish leaves the task open")
    check(failing.map { !controller.motion.isFinishing($0) } == true, "the finish motion reverses")
    check(model.error != nil, "the error explains what happened")
    model.error = nil

    // 8. Finishing everything: Day clear, once.
    var dayClears = 0
    model.feedback.listen { event in if case .dayClear = event.kind { dayClears += 1 } }
    let clearRecord = Task { await self.record("day-clear", window: panel, frames: 50, every: 30) }
    while let task = model.today.myDay.first {
      controller.panelState.selection = .task(task.id)
      await press("x", to: panel, settle: 480)
    }
    _ = await clearRecord.value
    check(model.today.isDayClear, "everything chosen is finished")
    check(dayClears == 1, "Day clear plays once")
    check(controller.ticker.text.hasPrefix("Day clear · "), "the menu bar says Day clear (\(controller.ticker.text))")
    await press("escape", to: panel)
    check(!panel.isVisible, "esc closes the panel")

    // 10. Every theme renders the finish without errors.
    for theme in ThemeID.allCases {
      controller.preferences.theme = theme
      controller.showPanel()
      await wait(150)
      if let id = model.today.myDay.first?.id {
        controller.panelState.selection = .task(id)
        let recorder = Task { await self.record("finish-\(theme.rawValue)", window: panel, frames: 30) }
        await press("x", to: panel, settle: 0)
        _ = await recorder.value
        check(model.reminder(id)?.isCompleted == true, "\(theme.rawValue): finish works")
        await press("z", modifiers: .command, to: panel, settle: 200)
      }
      controller.hidePanel()
    }

    printTimings()
    print("\(passed) passed, \(failures.count) failed")
    for failure in failures { print("  failed: \(failure)") }
    return failures.isEmpty ? 0 : 1
  }

  /// Run with --fresh-day: nothing chosen today, yesterday's leftover waiting.
  func runMorning() async -> Int32 {
    let panel = controller.panelWindow
    await wait(300)
    check(model.today.wantsMorningPull, "a fresh day with leftovers wants the morning pull")
    check(controller.ticker.text == "Choose today", "the menu bar invites a pick (\(controller.ticker.text))")
    controller.showPanel()
    await wait(250)
    check(controller.panelState.route == .morning, "opening the panel starts with the morning pull")
    let flat = controller.panelState.morningFlat
    check(flat.first?.id == "prototype", "yesterday's leftover comes first")
    await record("morning", window: panel, frames: 3)
    await press("2", to: panel)
    await press("4", to: panel)
    check(controller.panelState.morningPicks.count == 2, "number keys pick chips")
    await record("morning-picked", window: panel, frames: 3)
    await press("return", to: panel, settle: 250)
    check(model.today.myDay.count == 2, "Start the day makes the picks today's tasks")
    check(!model.isChosen("prototype") && model.plan.commitments.allSatisfy { $0.reminderID != "prototype" },
      "the unpicked leftover goes back to its shelf")
    check(!model.today.wantsMorningPull, "the pull doesn't ask again today")
    check(controller.ticker.text != "Choose today", "the menu bar now shows today's first task")
    await press("escape", to: panel)
    print("\(passed) passed, \(failures.count) failed")
    for failure in failures { print("  failed: \(failure)") }
    return failures.isEmpty ? 0 : 1
  }

  func printTimings() {
    for (label, samples) in timings.sorted(by: { $0.key < $1.key }) {
      let sorted = samples.sorted()
      let median = sorted[sorted.count / 2]
      let worst = sorted.last ?? median
      print("TIMING \(label): median \(Bench.format(median)), worst \(Bench.format(worst)), n=\(samples.count)")
    }
  }
}
