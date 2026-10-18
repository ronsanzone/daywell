import AppKit
import DaywellCore
@preconcurrency import EventKit
import Observation
import SwiftUI

/// Composition root: owns the model, the menu-bar ticker, the capture bar, the panel,
/// hot keys, the day clock and refresh triggers. Nothing here activates the app.
@MainActor public final class AppController {
  public let model: DayModel
  public let preferences: Preferences
  public let motion: MotionState
  public let panelState: PanelState
  public let capture: CaptureState
  public private(set) var ticker: StatusTicker!
  public let panelWindow = FloatingPanel(level: .popUpMenu)
  public let captureWindow = FloatingPanel(level: .floating)
  private let sound = SoundPlayer()
  public private(set) var catchService: CatchService!
  private let hotKeys = HotKeys()
  private var panelKeys: PanelKeys!
  private var keyMonitor: Any?
  private var clickMonitor: Any?
  private var observers: [NSObjectProtocol] = []
  private var workspaceObservers: [NSObjectProtocol] = []
  private var midnightTimer: Timer?
  private var safetyTimer: Timer?
  private var flyTask: Task<Void, Never>?
  /// Signposts for the performance checks: when each surface last opened, and how long it took.
  public private(set) var lastOpenDuration: Duration?

  public init(store: any ReminderStore, planStore: PlanStore, preferences: Preferences) {
    FontRegistry.registerBundledFonts()
    self.preferences = preferences
    model = DayModel(store: store, planStore: planStore, preferences: preferences)
    motion = MotionState(model: model)
    panelState = PanelState(model: model, motion: motion)
    capture = CaptureState(model: model)
  }

  public var shell: ShellActions {
    ShellActions(
      openCapture: { [weak self] in
        self?.hidePanel()
        self?.showCapture()
      },
      closePanel: { [weak self] in self?.hidePanel() })
  }

  /// Builds every surface. Call once after launch.
  public func start() {
    ticker = StatusTicker(model: model, preferences: preferences) { [weak self] in
      self?.togglePanel()
    }
    panelKeys = PanelKeys(model: model, panel: panelState, shell: shell)
    panelWindow.contentViewController = FittingHostingController(
      rootView: PanelView(
        model: model, panel: panelState, preferences: preferences, motion: motion, shell: shell))
    captureWindow.contentViewController = FittingHostingController(
      rootView: CaptureBarView(
        capture: capture, model: model, preferences: preferences, motion: motion))
    observers.append(
      NotificationCenter.default.addObserver(
        forName: NSWindow.didResizeNotification, object: panelWindow, queue: .main
      ) { [weak self] _ in MainActor.assumeIsolated { self?.positionPanel() } })
    catchService = CatchService(model: model)
    NSApp.servicesProvider = catchService
    NSUpdateDynamicServices()
    installMonitors()
    installHotKeys()
    installFeedback()
    installRefreshTriggers()
    scheduleMidnight()
    Task { await model.refresh() }
  }

  // MARK: Capture bar

  public func showCapture() {
    let began = ContinuousClock.now
    flyTask?.cancel()
    model.setNow(Date())
    capture.listIndex = nil
    Task { await model.refresh() }
    positionCapture()
    captureWindow.alphaValue = 1
    captureWindow.makeKeyAndOrderFront(nil)
    lastOpenDuration = ContinuousClock.now - began
  }

  public func hideCapture() {
    guard captureWindow.isVisible else { return }
    captureWindow.orderOut(nil)
  }

  public func toggleCapture() {
    captureWindow.isVisible ? hideCapture() : showCapture()
  }

  private func positionCapture() {
    let screen =
      NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
    guard let visible = screen?.visibleFrame else { return }
    captureWindow.layoutIfNeeded()
    let size = captureWindow.frame.size
    captureWindow.setFrameOrigin(
      NSPoint(
        x: visible.midX - size.width / 2, y: visible.maxY - visible.height * 0.22 - size.height))
  }

  /// After a confirmed save, the bar shrinks into the menu bar and disappears.
  private func flyCaptureAway() {
    guard captureWindow.isVisible, let button = ticker.button, let window = button.window else {
      hideCapture()
      return
    }
    if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
      hideCapture()
      return
    }
    let target = window.convertToScreen(button.convert(button.bounds, to: nil))
    let start = captureWindow.frame
    let end = NSRect(x: target.midX - 40, y: target.minY - 10, width: 80, height: 10)
    flyTask?.cancel()
    flyTask = Task { [weak self] in
      let clock = ContinuousClock()
      let began = clock.now
      while !Task.isCancelled {
        let t = min(1, (clock.now - began) / .milliseconds(300))
        let eased = 1 - pow(1 - t, 3)
        let frame = NSRect(
          x: start.minX + (end.minX - start.minX) * eased,
          y: start.minY + (end.minY - start.minY) * eased,
          width: start.width + (end.width - start.width) * eased,
          height: start.height + (end.height - start.height) * eased)
        self?.captureWindow.setFrame(frame, display: true)
        self?.captureWindow.alphaValue = 1 - eased
        if t >= 1 { break }
        try? await Task.sleep(for: .milliseconds(16))
      }
      self?.captureWindow.orderOut(nil)
      self?.captureWindow.setFrame(start, display: false)
      self?.captureWindow.alphaValue = 1
    }
  }

  // MARK: Panel

  public func togglePanel() {
    panelWindow.isVisible ? hidePanel() : showPanel()
  }

  public func showPanel(selecting reminderID: String? = nil) {
    let began = ContinuousClock.now
    hideCapture()
    model.setNow(Date())
    Task { await model.refresh() }
    if panelState.route != .today { panelState.route = .today }
    if model.today.wantsMorningPull && model.authorized { panelState.beginMorning() }
    if let reminderID { panelState.selection = .task(reminderID) } else { panelState.reconcile() }
    positionPanel()
    panelWindow.makeKeyAndOrderFront(nil)
    ticker.button?.highlight(true)
    lastOpenDuration = ContinuousClock.now - began
  }

  public func hidePanel() {
    guard panelWindow.isVisible else { return }
    panelWindow.orderOut(nil)
    ticker.button?.highlight(false)
    panelKeys.reset()
  }

  private func positionPanel() {
    guard let button = ticker.button, let window = button.window, let screen = window.screen
    else { return }
    let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
    let size = panelWindow.frame.size
    let x = max(
      screen.visibleFrame.minX,
      min(anchor.maxX - size.width, screen.visibleFrame.maxX - size.width))
    panelWindow.setFrameTopLeftPoint(NSPoint(x: x, y: screen.visibleFrame.maxY - 4))
  }

  // MARK: Keys and clicks

  private func installMonitors() {
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
      let used = MainActor.assumeIsolated { self?.route(event) ?? false }
      return used ? nil : event
    }
    clickMonitor = NSEvent.addGlobalMonitorForEvents(
      matching: [.leftMouseDown, .rightMouseDown]
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.hidePanel()
        self?.hideCapture()
      }
    }
  }

  /// Routes a key press to the surface that has focus. Returns true when consumed.
  public func route(_ event: NSEvent) -> Bool {
    let input = Self.keyInput(event)
    if event.window === captureWindow {
      return captureKeys.handle(input)
    }
    if event.window === panelWindow {
      if event.window?.firstResponder is RecorderView { return false }
      return panelKeys.handle(input)
    }
    return false
  }

  public var captureKeys: CaptureKeys {
    CaptureKeys(
      capture: capture, model: model, close: { [weak self] in self?.hideCapture() },
      openPanel: { [weak self] id in self?.showPanel(selecting: id) },
      saved: { [weak self] in self?.flyCaptureAway() })
  }

  public func handlePanelKey(_ input: KeyInput) -> Bool { panelKeys.handle(input) }

  static func keyInput(_ event: NSEvent) -> KeyInput {
    let specials: [UInt16: KeyInput.Special] = [
      126: .up, 125: .down, 123: .left, 124: .right, 36: .enter, 76: .enter, 53: .escape,
      48: .tab, 49: .space, 51: .delete,
    ]
    let flags = event.modifierFlags
    var special = specials[event.keyCode]
    // Space is only special when not typing into a field.
    let editing = event.window?.firstResponder is NSTextView
    if special == .space && editing { special = nil }
    return KeyInput(
      event.charactersIgnoringModifiers ?? "", special: special,
      command: flags.contains(.command), option: flags.contains(.option),
      control: flags.contains(.control), shift: flags.contains(.shift), isEditing: editing)
  }

  private func installHotKeys() {
    hotKeys.onPress(.capture) { [weak self] in self?.toggleCapture() }
    hotKeys.onPress(.finish) { [weak self] in
      guard let self, let task = self.model.today.tickerTask else { return }
      Task { await self.model.toggleCompletion(task.id) }
    }
    observeHotKeys()
  }

  private func observeHotKeys() {
    withObservationTracking {
      let status = hotKeys.register(
        .capture, key: UInt32(preferences.shortcutKey),
        modifiers: UInt32(preferences.shortcutModifiers))
      if status != noErr {
        model.error =
          "That shortcut couldn't be registered (\(status)). Choose another in Settings."
      }
      // ⌃⌥X: key code 7, Control + Option.
      hotKeys.register(.finish, key: preferences.finishHotKeyEnabled ? 7 : nil, modifiers: 6144)
    } onChange: { [weak self] in
      Task { @MainActor in self?.observeHotKeys() }
    }
  }

  // MARK: Feedback, refresh, clock

  private func installFeedback() {
    model.feedback.listen { [weak self] event in
      guard let self, self.preferences.soundEnabled else { return }
      switch event.kind {
      case .finished: self.sound.play(self.preferences.profile.sound)
      case .dayClear: self.sound.play(.chord)
      case .captured: self.sound.play(.drop)
      default: break
      }
    }
  }

  private func installRefreshTriggers() {
    let center = NotificationCenter.default
    observers.append(
      center.addObserver(forName: .EKEventStoreChanged, object: nil, queue: .main) {
        [weak self] _ in Task { @MainActor in await self?.model.refresh() }
      })
    for name in [
      Notification.Name.NSCalendarDayChanged, .NSSystemClockDidChange,
      .NSSystemTimeZoneDidChange,
    ] {
      observers.append(
        center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
          MainActor.assumeIsolated { self?.tick() }
        })
    }
    workspaceObservers.append(
      NSWorkspace.shared.notificationCenter.addObserver(
        forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
      ) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } })
    // EventKit notifies on changes; this is only a backstop for missed notifications.
    safetyTimer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in
      Task { @MainActor in await self?.model.refresh() }
    }
  }

  private func tick() {
    model.setNow(Date())
    Task { await model.refresh() }
    scheduleMidnight()
  }

  /// Fires at the next local midnight so "Day clear" and the pile reset on time.
  private func scheduleMidnight() {
    midnightTimer?.invalidate()
    let calendar = Calendar.autoupdatingCurrent
    guard
      let midnight = calendar.nextDate(
        after: Date(), matching: DateComponents(hour: 0, minute: 0, second: 1),
        matchingPolicy: .nextTime)
    else { return }
    let timer = Timer(fire: midnight, interval: 0, repeats: false) { [weak self] _ in
      MainActor.assumeIsolated { self?.tick() }
    }
    RunLoop.main.add(timer, forMode: .common)
    midnightTimer = timer
  }

  public func stop() {
    if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
    observers.forEach(NotificationCenter.default.removeObserver)
    workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
    midnightTimer?.invalidate()
    safetyTimer?.invalidate()
  }
}
