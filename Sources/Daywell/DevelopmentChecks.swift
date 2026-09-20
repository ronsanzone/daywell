import AppKit
import DaywellCore
import DaywellKit
import SwiftUI

/// Explicit fixture-only tooling. Never constructs an EventKit store.
@MainActor enum DevelopmentChecks {
  static func makeStore(arguments: [String], planStore: PlanStore) throws -> DemoReminderStore {
    let store = DemoReminderStore()
    var plan = DemoReminderStore.plan(now: Date())
    if arguments.contains("--empty") {
      store.items = []
      plan = DayPlan()
    }
    if arguments.contains("--permission") { store.authorized = false }
    if arguments.contains("--long-title"), !store.items.isEmpty {
      store.items[0].title =
        "Call the dentist to reschedule next week's cleaning and ask about the insurance paperwork"
    }
    if arguments.contains("--unpinned") { plan.unpin() }
    if option("--view", in: arguments) == "edit",
      let index = store.items.firstIndex(where: { $0.dueDate != nil })
    {
      store.items[index].hasDueTime = true
    }
    try planStore.save(plan)
    if arguments.contains("--recovery") {
      try planStore.save(plan)
      try Data("unreadable demo plan".utf8).write(to: planStore.url)
    }
    return store
  }

  static func option(_ name: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else {
      return nil
    }
    return arguments[index + 1]
  }

  /// Posts AppKit events through the application queue, not model actions.
  static func checkUI(
    model: AppModel, preferences: Preferences, hosting: KeyboardHostingView,
    panel: NSPanel, button: NSStatusBarButton
  ) async {
    func check(_ value: Bool, _ label: String) {
      guard value else {
        print("FAIL: \(label)")
        exit(1)
      }
      print("PASS: \(label)")
    }
    func key(_ text: String, code: UInt16 = 0, modifiers: NSEvent.ModifierFlags = []) async {
      guard let window = hosting.window,
        let event = NSEvent.keyEvent(
          with: .keyDown, location: .zero, modifierFlags: modifiers,
          timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
          context: nil, characters: text, charactersIgnoringModifiers: text, isARepeat: false,
          keyCode: code)
      else {
        print("FAIL: could not construct keyboard event")
        exit(1)
      }
      NSApp.postEvent(event, atStart: false)
      try? await Task.sleep(for: .milliseconds(180))
    }
    func click(x: CGFloat, fromTop y: CGFloat) async {
      // Logical points in the fixed 560-point fixture layout, checked against
      // native snapshots. SwiftUI does not expose AX children in this in-process harness.
      let point = hosting.convert(
        NSPoint(x: x, y: hosting.isFlipped ? y : hosting.bounds.height - y), to: nil)
      for type: NSEvent.EventType in [.leftMouseDown, .leftMouseUp] {
        guard
          let event = NSEvent.mouseEvent(
            with: type, location: point, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber,
            context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)
        else {
          print("FAIL: could not construct pointer event")
          exit(1)
        }
        NSApp.postEvent(event, atStart: false)
      }
      try? await Task.sleep(for: .milliseconds(250))
    }
    try? await Task.sleep(for: .milliseconds(600))
    check(panel.isVisible, "menu-bar panel opens")
    check(hosting.bounds.width == 560, "panel content is 560 points wide")
    check(hosting.window is NSPanel, "shell uses a custom panel rather than a popover")
    check(panel.styleMask == .borderless, "shell has no title bar or popover chrome")
    check(
      panel.frame.maxY == button.window?.frame.minY,
      "panel is flush beneath menu bar (panel \(panel.frame.maxY), anchor \(button.window?.frame.minY ?? -1))"
    )
    check(panel.isKeyWindow, "borderless panel accepts keyboard focus")
    check(!model.sectionsExpanded, "secondary sections and lists start collapsed")
    await click(x: 60, fromTop: 437)
    check(model.expandedListIDs == ["personal"], "pointer opens an individual list")
    check(
      model.visibleItems.contains(where: { $0.id == "parking" }), "opened list exposes reminders")
    await click(x: 502, fromTop: 475)
    check(
      model.projection.today.contains(where: { $0.id == "parking" }), "list plus chooses reminder")
    model.release("parking")
    try? await Task.sleep(for: .milliseconds(250))
    await click(x: 60, fromTop: 437)
    check(model.expandedListIDs.isEmpty, "pointer closes an individual list")
    panel.makeFirstResponder(hosting)
    await key("s", code: 1)
    check(
      model.dueExpanded && model.previousExpanded && model.doneExpanded
        && model.expandedListIDs == ["personal", "work"],
      "s expands date sections and all lists")
    await key("s", code: 1)
    check(!model.sectionsExpanded, "s collapses all sections again")
    await key("b", code: 11)
    check(model.route == .patchbay, "b opens task patchbay")
    await click(x: 246, fromTop: 344)
    check(
      model.projection.today.contains { $0.id == "parking" },
      "patchbay plus chooses a reminder")
    check(
      model.patchbayLists.flatMap(\.items).contains { $0.id == "parking" },
      "chosen reminder remains in its source list")
    model.selectedID = "parking"
    panel.makeFirstResponder(hosting)
    await key("r", code: 15)
    check(model.route == .patchbay, "release stays in patchbay")
    await key("a", code: 0)
    check(model.projection.today.contains { $0.id == "parking" }, "a chooses in patchbay")
    await key("x", code: 7)
    check(
      model.route == .patchbay && model.reminders.first { $0.id == "parking" }?.isCompleted == true,
      "x completes without leaving patchbay")
    await key("z", code: 6, modifiers: .command)
    check(
      model.route == .patchbay
        && model.reminders.first { $0.id == "parking" }?.isCompleted == false,
      "Undo reopens without leaving patchbay")
    model.selectedID = "parking"
    await key("r", code: 15)
    await key("h", code: 4)
    model.selectedID = "dentist"
    await key("j", code: 38)
    check(model.selectedID == "expenses", "j moves to next reminder once")
    await key("p", code: 35)
    check(model.projection.pinnedReminderID == "expenses", "p changes pin")
    await key("G", code: 5, modifiers: .shift)
    check(model.selectedID == "prescription", "G skips collapsed sections")
    await key("g", code: 5)
    await key("g", code: 5)
    check(model.selectedID == "expenses", "gg selects first reminder")
    await key("n", code: 45, modifiers: .command)
    check(model.route == .capture, "Command-N opens capture")
    check(hosting.window?.firstResponder is NSTextView, "capture receives text focus")
    await key("j", code: 38)
    await key("k", code: 40)
    await key("s", code: 1)
    check(model.captureText == "jks", "j, k and s type literally in capture")
    check(!model.sectionsExpanded, "typing s does not expand sections")
    await key("\u{1b}", code: 53)
    check(!(hosting.window?.firstResponder is NSTextView), "Escape leaves text entry")
    await key("\u{1b}", code: 53)
    check(model.route == .day && model.captureText == "jks", "cancel preserves capture draft")
    await key("x", code: 7)
    check(
      model.reminders.first(where: { $0.id == "expenses" })?.isCompleted == true,
      "x completes selected reminder")
    await key("z", code: 6, modifiers: .command)
    check(
      model.reminders.first(where: { $0.id == "expenses" })?.isCompleted == false,
      "Command-Z undoes completion")
    await key("k", code: 40, modifiers: .command)
    check(model.route == .commands, "Command-K opens palette")
    await key("\u{f701}", code: 125)
    check(model.commandIndex == 1, "Down arrow moves command selection during search")
    await key("\u{1b}", code: 53)
    await key("j", code: 38)
    check(model.commandIndex == 2, "j moves command selection outside text entry")
    await key("k", code: 40)
    await key("\r", code: 36)
    check(model.route == .browse, "Return executes selected palette command")
    await key("j", code: 38)
    check(model.search == "j", "search receives text focus rather than consuming motions")
    await key("n", code: 45, modifiers: .command)
    await key("\r", code: 36, modifiers: .command)
    check(
      model.captureText.isEmpty && model.reminders.contains(where: { $0.title == "jks" }),
      "Command-Return saves the retained capture draft")
    await key("k", code: 40, modifiers: .command)
    for (character, code): (String, UInt16) in [
      ("k", 40), ("e", 14), ("e", 14), ("p", 35), (" ", 49), ("a", 0), ("l", 37), ("l", 37),
    ] {
      await key(character, code: code)
    }
    await key("\r", code: 36)
    check(
      model.projection.previous.isEmpty
        && model.projection.today.contains(where: { $0.id == "plants" }),
      "search and Return keep previous commitments")
    await key(",", code: 43, modifiers: .command)
    check(model.route == .settings, "Command-comma opens settings")
    let originalTheme = preferences.theme
    await click(x: 160, fromTop: 287)
    check(preferences.theme == .amber, "pointer selects Amber CRT")
    await click(x: 510, fromTop: 346)
    check(preferences.crtIntensity > 0.9, "pointer increases CRT intensity through surface overlay")
    let pointerIntensity = preferences.crtIntensity
    func findSlider(in view: NSView) -> NSSlider? {
      if let slider = view as? NSSlider { return slider }
      return view.subviews.lazy.compactMap { findSlider(in: $0) }.first
    }
    guard let slider = findSlider(in: hosting) else {
      check(false, "CRT slider is a native control")
      return
    }
    // Establish the focus reached via Tab with macOS Keyboard Navigation enabled,
    // without changing the user's system-wide keyboard preference.
    check(panel.makeFirstResponder(slider), "CRT slider accepts keyboard focus")
    await key("\u{f702}", code: 123)
    check(
      model.route == .settings && preferences.crtIntensity < pointerIntensity,
      "Left arrow adjusts focused CRT slider instead of navigating back")
    await click(x: 30, fromTop: 346)
    check(preferences.crtIntensity == 0, "zero intensity turns off CRT effects")
    check(panel.makeFirstResponder(slider), "CRT slider retains keyboard availability at zero")
    await key("\u{f703}", code: 124)
    check(preferences.crtIntensity > 0, "Right arrow re-enables CRT effects")
    await click(x: 37, fromTop: 397)
    check(!preferences.terminalMotion, "pointer disables terminal motion independently of CRT")
    await click(x: 37, fromTop: 397)
    check(preferences.terminalMotion, "pointer restores terminal motion")
    await click(x: 160, fromTop: 143)
    check(preferences.theme == .graphite, "pointer switches back to Graphite")
    preferences.theme = originalTheme
    panel.makeFirstResponder(hosting)
    await key("h", code: 4)
    check(model.route == .day, "h returns from settings")
    await key("\u{1b}", code: 53)
    check(!panel.isVisible, "Escape dismisses the panel")
    check(!hosting.rootView.isPresented, "closing explicitly suspends decorative motion")
    button.performClick(nil)
    try? await Task.sleep(for: .milliseconds(300))
    check(panel.isVisible && panel.isKeyWindow, "status button reopens and focuses panel")
    check(hosting.rootView.isPresented, "reopening restores the motion lifecycle")
    button.performClick(nil)
    check(!panel.isVisible, "status button toggles panel closed")
    button.performClick(nil)
    try? await Task.sleep(for: .milliseconds(300))
    let sheet = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled],
      backing: .buffered, defer: false)
    panel.beginSheet(sheet, completionHandler: nil)
    if let click = NSEvent.mouseEvent(
      with: .leftMouseDown, location: NSPoint(x: 10, y: 10), modifierFlags: [],
      timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: sheet.windowNumber,
      context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
    {
      NSApp.postEvent(click, atStart: false)
    }
    try? await Task.sleep(for: .milliseconds(180))
    check(panel.isVisible, "clicking a confirmation sheet keeps the panel open")
    panel.endSheet(sheet)
    sheet.orderOut(nil)
    let outside = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 50, height: 50), styleMask: [.borderless],
      backing: .buffered, defer: false)
    guard
      let click = NSEvent.mouseEvent(
        with: .leftMouseDown, location: .zero, modifierFlags: [],
        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: outside.windowNumber,
        context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
    else {
      print("FAIL: could not construct outside click")
      exit(1)
    }
    NSApp.postEvent(click, atStart: false)
    try? await Task.sleep(for: .milliseconds(180))
    check(!panel.isVisible, "click outside panel dismisses it")
    print("UI event checks passed using disposable demo reminders only.")
    NSApp.terminate(nil)
  }

  static func snapshot(model: AppModel, preferences: Preferences, arguments: [String]) async {
    if let route = option("--view", in: arguments).flatMap(PanelRoute.init(rawValue:)) {
      model.route = route
    }
    model.doneExpanded = arguments.contains("--expanded")
    model.previousExpanded = arguments.contains("--previous")
    model.dueExpanded = arguments.contains("--due")
    if arguments.contains("--lists") {
      for list in model.lists { model.setListExpanded(list.id, expanded: true) }
    }
    model.selectedID = "dentist"
    if model.route == .capture { model.captureText = "Call dentist tomorrow at 2pm" }
    if model.route == .edit, let item = model.reminders.first(where: { $0.dueDate != nil }) {
      model.edit(item.id)
    }
    if arguments.contains("--error") {
      model.error =
        "Could not save your day plan. Your reminders are unchanged. Check that your Mac has available storage, then try again."
    }
    if arguments.contains("--no-motion") { preferences.terminalMotion = false }
    let view = KeyboardHostingView(rootView: PanelView(model: model, preferences: preferences))
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: PanelView.preferredSize), styleMask: [.borderless],
      backing: .buffered, defer: false)
    window.contentView = view
    window.center()
    window.orderFront(nil)
    defer { window.orderOut(nil) }
    try? await Task.sleep(for: .milliseconds(600))
    do {
      if let directory = option("--motion-sequence", in: arguments) {
        let destination = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let clock = ContinuousClock()
        let began = clock.now
        for frame in 0..<200 {
          switch frame {
          case 8: model.selectedID = "expenses"
          case 26: await model.complete("expenses")
          case 50: await model.undoCompletion()
          case 74: model.route = .patchbay
          case 96: model.choose("parking")
          default: break
          }
          try await clock.sleep(until: began + .milliseconds(frame * 50))
          try writeSnapshot(
            view, to: destination.appendingPathComponent(String(format: "%03d.png", frame)))
        }
        print("Rendered native motion sequence in \(directory)")
      }
      let url = URL(fileURLWithPath: option("--snapshot", in: arguments) ?? "daywell.png")
      try writeSnapshot(view, to: url)
      print("Rendered \(url.path)")
    } catch {
      fputs("Snapshot failed: \(error)\n", stderr)
      exit(1)
    }
    NSApp.terminate(nil)
  }

  private static func writeSnapshot(_ view: NSView, to url: URL) throws {
    view.layoutSubtreeIfNeeded()
    guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
      throw CocoaError(.fileWriteUnknown)
    }
    view.cacheDisplay(in: view.bounds, to: bitmap)
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
      throw CocoaError(.fileWriteUnknown)
    }
    try png.write(to: url)
  }
}
