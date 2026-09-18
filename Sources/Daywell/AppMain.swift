import AppKit
import DaywellCore
import DaywellKit
import EventKit
import Observation
import SwiftUI

@main struct DaywellMain {
  @MainActor static func main() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
    withExtendedLifetime(delegate) {}
  }
}

final class KeyboardHostingView: NSHostingView<PanelView> {
  override var acceptsFirstResponder: Bool { true }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
  private var statusItem: NSStatusItem!
  private var popover = NSPopover()
  private var model: AppModel!
  private var preferences: Preferences!
  private var hosting: KeyboardHostingView!
  private var shortcut: GlobalShortcut!
  private var navigation = VimNavigation()
  private var monitor: Any?
  private var timer: Timer?
  private var observers: [NSObjectProtocol] = []
  private var snapshotWindow: NSWindow?
  private var temporaryDirectory: URL?
  private var demoDefaultsName: String?
  private var previousApp: NSRunningApplication?
  private var lastRoute: PanelRoute = .day
  private let arguments = CommandLine.arguments
  private var demo: Bool {
    arguments.contains("--demo") || arguments.contains("--snapshot")
      || arguments.contains("--ui-check")
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    do {
      let root: URL
      if demo {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
          "daywell-demo-\(UUID().uuidString)")
        temporaryDirectory = root
        let name = "daywell.demo.\(UUID().uuidString)"
        demoDefaultsName = name
        preferences = Preferences(defaults: UserDefaults(suiteName: name)!)
      } else {
        root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
          .appendingPathComponent("Daywell")
        preferences = Preferences()
      }
      let store: any ReminderStore = demo ? DemoReminderStore() : EventKitReminderStore()
      let planStore = PlanStore(url: root.appendingPathComponent("day-plan.json"))
      if demo { try planStore.save(DemoReminderStore.plan(now: Date())) }
      model = AppModel(store: store, planStore: planStore)
      installAppMenu()
      Task {
        await model.refresh()
        if let theme = option("--theme").flatMap(Theme.init(rawValue:)) {
          preferences.theme = theme
        }
        if arguments.contains("--snapshot") {
          await snapshot()
        } else {
          setupPanel()
          if demo || !model.authorized {
            // A newly installed status item initially has a zero-height
            // window. AppKit cannot anchor a popover until it is laid out.
            for _ in 0..<100 {
              if (statusItem.button?.window?.frame.height ?? 0) > 0 { break }
              try? await Task.sleep(for: .milliseconds(20))
            }
            togglePanel()
          }
          if arguments.contains("--ui-check") { await checkUI() }
        }
      }
    } catch {
      let alert = NSAlert(error: error)
      alert.runModal()
      NSApp.terminate(nil)
    }
  }

  private func setupPanel() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem.button?.image = NSImage(
      systemSymbolName: "checklist", accessibilityDescription: "Daywell")
    statusItem.button?.target = self
    statusItem.button?.action = #selector(togglePanel)
    statusItem.button?.toolTip = demo ? "Daywell — demo reminders" : "Daywell"
    hosting = KeyboardHostingView(rootView: PanelView(model: model, preferences: preferences))
    let controller = NSViewController()
    controller.view = hosting
    popover.contentViewController = controller
    popover.contentSize = NSSize(width: 420, height: 660)
    popover.behavior = .transient
    popover.delegate = self
    shortcut = GlobalShortcut()
    shortcut.activate = { [weak self] in self?.togglePanel() }
    observeState()
    monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      let consumed = MainActor.assumeIsolated {
        guard let self else { return false }
        return self.handle(event) == nil
      }
      return consumed ? nil : event
    }
    for name in [
      Notification.Name.EKEventStoreChanged, NSApplication.didBecomeActiveNotification,
      .NSCalendarDayChanged, NSNotification.Name.NSSystemTimeZoneDidChange,
    ] {
      observers.append(
        NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) {
          [weak self] _ in
          Task { @MainActor in await self?.refresh() }
        })
    }
    timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
      Task { @MainActor in await self?.refresh() }
    }
  }

  private func observeState() {
    withObservationTracking {
      statusItem.button?.title = preferences.showCount ? " \(model.projection.today.count)" : ""
      let result = shortcut.register(
        key: UInt32(preferences.shortcutKey), modifiers: UInt32(preferences.shortcutModifiers))
      if result != noErr {
        model.error =
          "That global shortcut couldn't be registered (\(result)). Choose another in Settings."
      }
      let inbox = preferences.inboxID
      if model.route == .capture, lastRoute != .capture, model.captureText.isEmpty,
        !inbox.isEmpty, model.writableLists.contains(where: { $0.id == inbox })
      {
        model.captureListID = inbox
      }
      lastRoute = model.route
    } onChange: { [weak self] in
      Task { @MainActor in self?.observeState() }
    }
  }

  private func refresh() async {
    model.now = Date()
    await model.refresh()
  }

  @objc private func togglePanel() {
    if popover.isShown {
      popover.performClose(nil)
      return
    }
    previousApp = NSWorkspace.shared.frontmostApplication
    Task { await refresh() }
    guard let button = statusItem.button else { return }
    NSApp.activate(ignoringOtherApps: true)
    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    hosting.window?.makeKey()
    hosting.window?.makeFirstResponder(hosting)
  }

  func popoverDidClose(_ notification: Notification) {
    // Restore focus only if Daywell still owns it; don't steal focus back
    // after the user deliberately clicked another application.
    if NSApp.isActive { previousApp?.activate(options: []) }
  }

  private func handle(_ event: NSEvent) -> NSEvent? {
    guard event.window == hosting?.window, popover.isShown else { return event }
    if event.window?.firstResponder is RecorderView { return event }
    let editing = event.window?.firstResponder is NSTextView
    let key = event.charactersIgnoringModifiers ?? ""
    if event.modifierFlags.contains(.command) {
      guard event.modifierFlags.intersection([.control, .option, .shift]).isEmpty else {
        return event
      }
      if key == "k" {
        model.route = .commands
        return nil
      }
      guard
        let command = DaywellCommand.allCases.first(where: {
          $0.keyBinding?.command == true && $0.keyBinding?.key == key.lowercased()
        }),
        !(command == .undo && editing)
      else { return event }
      command.perform(model)
      return nil
    }
    if event.keyCode == 53 {
      navigation = VimNavigation()
      if editing {
        event.window?.makeFirstResponder(hosting)
      } else if model.route != .day {
        model.route = .day
        model.editing = nil
      } else {
        popover.performClose(nil)
      }
      return nil
    }
    guard event.modifierFlags.intersection([.control, .option]).isEmpty else { return event }
    let arrows: [UInt16: String] = [125: "↓", 126: "↑", 123: "←", 124: "→"]
    let character = arrows[event.keyCode] ?? (event.characters ?? "")
    if editing {
      _ = navigation.action(for: character, isEditing: true)
      return event
    }
    if model.route != .day && (character == "h" || character == "←") {
      model.navigate(.back)
      return nil
    }
    guard model.route == .day || model.route == .browse || model.route == .commands else {
      return event
    }
    if let action = navigation.action(for: character, isEditing: false) {
      model.navigate(action)
      return nil
    }
    if character == "\r" {
      model.navigate(.open)
      return nil
    }
    if model.route == .commands { return event }
    if character == "g" { return nil }
    guard
      let command = DaywellCommand.allCases.first(where: {
        $0.keyBinding?.command == false && $0.keyBinding?.key == character
      })
    else { return event }
    command.perform(model)
    return nil
  }

  private func installAppMenu() {
    let menu = NSMenu()
    let appItem = NSMenuItem()
    let appMenu = NSMenu()
    appMenu.addItem(
      withTitle: "Quit Daywell", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    appItem.submenu = appMenu
    menu.addItem(appItem)
    let editItem = NSMenuItem()
    let edit = NSMenu(title: "Edit")
    for (title, selector, key) in [
      ("Undo", Selector(("undo:")), "z"), ("Cut", #selector(NSText.cut(_:)), "x"),
      ("Copy", #selector(NSText.copy(_:)), "c"), ("Paste", #selector(NSText.paste(_:)), "v"),
      ("Select All", #selector(NSText.selectAll(_:)), "a"),
    ] {
      edit.addItem(withTitle: title, action: selector, keyEquivalent: key)
    }
    editItem.submenu = edit
    menu.addItem(editItem)
    NSApp.mainMenu = menu
  }

  private func option(_ name: String) -> String? {
    guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else {
      return nil
    }
    return arguments[index + 1]
  }

  /// Runs in demo mode only. Posts real AppKit events through the application
  /// event queue rather than calling navigation or capture actions directly.
  private func checkUI() async {
    func check(_ value: Bool, _ label: String) {
      guard value else {
        print("FAIL: \(label)")
        exit(1)
      }
      print("PASS: \(label)")
    }
    func key(_ text: String, code: UInt16 = 0, modifiers: NSEvent.ModifierFlags = []) async {
      let event = NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: modifiers,
        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: hosting.window!.windowNumber,
        context: nil, characters: text, charactersIgnoringModifiers: text, isARepeat: false,
        keyCode: code)!
      NSApp.postEvent(event, atStart: false)
      try? await Task.sleep(for: .milliseconds(180))
    }
    try? await Task.sleep(for: .milliseconds(600))
    check(popover.isShown, "menu-bar panel opens")
    model.selectedID = "dentist"
    await key("j", code: 38)
    check(model.selectedID == "expenses", "j moves to next reminder once")
    await key("p", code: 35)
    check(model.projection.pinnedReminderID == "expenses", "p changes pin")
    await key("G", code: 5, modifiers: .shift)
    check(model.selectedID == "parking", "G selects last visible reminder")
    await key("g", code: 5)
    await key("g", code: 5)
    check(model.selectedID == "expenses", "gg selects first reminder")
    await key("n", code: 45, modifiers: .command)
    check(model.route == .capture, "Command-N opens capture")
    check(hosting.window?.firstResponder is NSTextView, "capture receives text focus")
    await key("j", code: 38)
    await key("k", code: 40)
    check(model.captureText == "jk", "j and k type literally in capture")
    await key("\u{1b}", code: 53)
    check(!(hosting.window?.firstResponder is NSTextView), "Escape leaves text entry")
    await key("\u{1b}", code: 53)
    check(model.route == .day && model.captureText == "jk", "cancel preserves capture draft")
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
      model.captureText.isEmpty && model.reminders.contains(where: { $0.title == "jk" }),
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
    await key("h", code: 4)
    check(model.route == .day, "h returns from settings")
    print("UI event checks passed using disposable demo reminders only.")
    NSApp.terminate(nil)
  }

  private func snapshot() async {
    if let route = option("--view").flatMap(PanelRoute.init(rawValue:)) { model.route = route }
    model.doneExpanded = arguments.contains("--expanded")
    model.previousExpanded = arguments.contains("--previous")
    model.selectedID = "dentist"
    if model.route == .capture { model.captureText = "Call dentist tomorrow at 2pm" }
    if model.route == .edit {
      model.editing = model.reminders.first { $0.dueDate != nil }
      model.editing?.hasDueTime = true
    }
    if arguments.contains("--empty") {
      model.reminders = []
      model.plan = DayPlan()
    }
    if arguments.contains("--permission") { model.authorized = false }
    if arguments.contains("--long-title"), !model.reminders.isEmpty {
      model.reminders[0].title =
        "Call the dentist to reschedule next week's cleaning and ask about the insurance paperwork"
    }
    if arguments.contains("--error") {
      model.error =
        "Could not save your day plan. Your reminders are unchanged. Check that your Mac has available storage, then try again."
    }
    if arguments.contains("--unpinned") { model.plan.unpin() }
    let view = KeyboardHostingView(rootView: PanelView(model: model, preferences: preferences))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 420, height: 660), styleMask: [.borderless],
      backing: .buffered, defer: false)
    window.contentView = view
    window.center()
    window.orderFront(nil)
    snapshotWindow = window
    try? await Task.sleep(for: .milliseconds(600))
    view.layoutSubtreeIfNeeded()
    do {
      guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
        throw CocoaError(.fileWriteUnknown)
      }
      view.cacheDisplay(in: view.bounds, to: bitmap)
      guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
      }
      let url = URL(fileURLWithPath: option("--snapshot") ?? "daywell.png")
      try png.write(to: url)
      print("Rendered \(url.path)")
    } catch {
      fputs("Snapshot failed: \(error)\n", stderr)
      exit(1)
    }
    NSApp.terminate(nil)
  }

  func applicationWillTerminate(_ notification: Notification) {
    if let monitor { NSEvent.removeMonitor(monitor) }
    timer?.invalidate()
    observers.forEach(NotificationCenter.default.removeObserver)
    if let temporaryDirectory { try? FileManager.default.removeItem(at: temporaryDirectory) }
    if let demoDefaultsName {
      UserDefaults.standard.removePersistentDomain(forName: demoDefaultsName)
    }
  }
}
