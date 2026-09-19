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

final class MenuBarPanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
  private var statusItem: NSStatusItem!
  private let panel = MenuBarPanel(
    contentRect: NSRect(origin: .zero, size: PanelView.preferredSize),
    styleMask: [.borderless], backing: .buffered, defer: false)
  private var model: AppModel!
  private var preferences: Preferences!
  private var hosting: KeyboardHostingView!
  private var shortcut: GlobalShortcut!
  private var navigation = VimNavigation()
  private var monitor: Any?
  private var outsideClickMonitor: Any?
  private var timer: Timer?
  private var observers: [NSObjectProtocol] = []
  private var temporaryDirectory: URL?
  private var demoDefaultsName: String?
  private var previousApp: NSRunningApplication?
  private let arguments = CommandLine.arguments
  private var demo: Bool {
    arguments.contains("--demo") || arguments.contains("--snapshot")
      || arguments.contains("--ui-check")
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    if arguments.contains("--live-check") {
      guard !demo else {
        fputs("Do not combine --live-check with demo, snapshot or UI-check mode.\n", stderr)
        exit(2)
      }
      Task { exit(await LiveRemindersCheck.run()) }
      return
    }
    do {
      let root: URL
      if demo {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
          "daywell-demo-\(UUID().uuidString)")
        temporaryDirectory = root
        let name = "daywell.demo.\(UUID().uuidString)"
        demoDefaultsName = name
        guard let defaults = UserDefaults(suiteName: name) else {
          throw CocoaError(.fileWriteUnknown)
        }
        preferences = Preferences(defaults: defaults)
      } else {
        root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
          .appendingPathComponent("Daywell")
        preferences = Preferences()
      }
      let planStore = PlanStore(url: root.appendingPathComponent("day-plan.json"))
      let store: any ReminderStore =
        demo
        ? try DevelopmentChecks.makeStore(arguments: arguments, planStore: planStore)
        : EventKitReminderStore()
      model = AppModel(store: store, planStore: planStore, preferences: preferences)
      installAppMenu()
      Task {
        await model.refresh()
        if let theme = DevelopmentChecks.option("--theme", in: arguments).flatMap(
          Theme.init(rawValue:))
        {
          preferences.theme = theme
        }
        if demo,
          let intensity = DevelopmentChecks.option("--crt-intensity", in: arguments).flatMap(
            Double.init)
        {
          preferences.crtIntensity = intensity
        }
        if arguments.contains("--snapshot") {
          await DevelopmentChecks.snapshot(
            model: model, preferences: preferences, arguments: arguments)
        } else {
          setupPanel()
          if demo || !model.authorized {
            // A newly installed status item initially has a zero-height
            // window. Wait for its screen position before placing the panel.
            for _ in 0..<100 {
              if let window = statusItem.button?.window,
                window.frame.height > 0, window.screen != nil
              {
                break
              }
              try? await Task.sleep(for: .milliseconds(20))
            }
            togglePanel()
          }
          if arguments.contains("--ui-check") {
            guard let button = statusItem.button else {
              fputs("UI check requires a status button.\n", stderr)
              exit(1)
            }
            await DevelopmentChecks.checkUI(
              model: model, preferences: preferences, hosting: hosting, panel: panel, button: button
            )
          }
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
    panel.contentView = hosting
    panel.level = .popUpMenu
    panel.hasShadow = true
    panel.isMovable = false
    panel.hidesOnDeactivate = false
    panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
    observers.append(
      NotificationCenter.default.addObserver(
        forName: NSWindow.didMoveNotification, object: statusItem.button?.window, queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated {
          guard let self, self.panel.isVisible else { return }
          self.positionPanel()
        }
      })
    shortcut = GlobalShortcut()
    shortcut.activate = { [weak self] in self?.togglePanel() }
    observeState()
    monitor = NSEvent.addLocalMonitorForEvents(
      matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
    ) { [weak self] event in
      let consumed = MainActor.assumeIsolated {
        guard let self else { return false }
        if event.type != .keyDown {
          if event.window != self.panel && event.window?.sheetParent != self.panel
            && event.window?.parent != self.panel
            && event.window != self.statusItem.button?.window
          {
            self.dismissPanel(restoreFocus: false)
          }
          return false
        }
        return self.handle(event) == nil
      }
      return consumed ? nil : event
    }
    outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
      matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.dismissPanel(restoreFocus: false) }
    }
    for name in [
      NSApplication.didResignActiveNotification,
      NSApplication.didChangeScreenParametersNotification,
    ] {
      observers.append(
        NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) {
          [weak self] _ in
          MainActor.assumeIsolated { self?.dismissPanel(restoreFocus: false) }
        })
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
    } onChange: { [weak self] in
      Task { @MainActor in self?.observeState() }
    }
  }

  private func refresh() async {
    model.now = Date()
    await model.refresh()
  }

  @objc private func togglePanel() {
    if panel.isVisible {
      dismissPanel()
      return
    }
    previousApp = NSWorkspace.shared.frontmostApplication
    Task { await refresh() }
    positionPanel()
    NSApp.activate(ignoringOtherApps: true)
    panel.makeKeyAndOrderFront(nil)
    panel.makeFirstResponder(hosting)
    statusItem.button?.highlight(true)
  }

  private func positionPanel() {
    guard let button = statusItem.button, let window = button.window,
      let screen = window.screen
    else { return }
    let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
    let size = PanelView.preferredSize
    let height = min(size.height, screen.visibleFrame.height)
    let x = max(
      screen.visibleFrame.minX, min(anchor.maxX - size.width, screen.visibleFrame.maxX - size.width)
    )
    panel.setFrame(
      NSRect(x: x, y: screen.visibleFrame.maxY - height, width: size.width, height: height),
      display: true)
  }

  private func dismissPanel(restoreFocus: Bool = true) {
    guard panel.isVisible else { return }
    panel.orderOut(nil)
    statusItem.button?.highlight(false)
    navigation = VimNavigation()
    // Restore focus only if Daywell still owns it; don't steal focus back
    // after the user deliberately clicked another application.
    if restoreFocus && NSApp.isActive { previousApp?.activate(options: []) }
    previousApp = nil
  }

  private func handle(_ event: NSEvent) -> NSEvent? {
    guard event.window == hosting?.window, panel.isVisible else { return event }
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
      } else {
        dismissPanel()
      }
      return nil
    }
    // Native sliders own arrow keys; don't interpret Left as navigation back.
    if event.window?.firstResponder is NSSlider { return event }
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

  func applicationWillTerminate(_ notification: Notification) {
    if let monitor { NSEvent.removeMonitor(monitor) }
    if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
    timer?.invalidate()
    observers.forEach(NotificationCenter.default.removeObserver)
    if let temporaryDirectory { try? FileManager.default.removeItem(at: temporaryDirectory) }
    if let demoDefaultsName {
      UserDefaults.standard.removePersistentDomain(forName: demoDefaultsName)
    }
  }
}
