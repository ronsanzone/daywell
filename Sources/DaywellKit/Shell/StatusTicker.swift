import AppKit
import DaywellCore
import Observation

/// The menu-bar item: today's task as text with a clickable ring.
/// Click the ring to finish, the title to open the panel, "+N" for the rest of today.
@MainActor public final class StatusTicker: NSObject {
  public let item: NSStatusItem
  private let model: DayModel
  private let preferences: Preferences
  private let togglePanel: () -> Void
  private var ringProgress: CGFloat = 0
  private var ringTask: Task<Void, Never>?
  /// Shown briefly after a capture, e.g. "→ Work".
  private var flash: String?
  private var flashTask: Task<Void, Never>?
  /// Title kept struck through while the finish motion plays.
  private var finishing: ReminderItem?
  private var regions: [(range: ClosedRange<CGFloat>, region: Region)] = []

  public enum Region: Sendable { case ring, title, more, undo }

  /// Longest task title shown before truncating, so the menu bar doesn't jump around.
  static let maxTitleCharacters = 24

  public init(model: DayModel, preferences: Preferences, togglePanel: @escaping () -> Void) {
    self.model = model
    self.preferences = preferences
    self.togglePanel = togglePanel
    item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    super.init()
    item.button?.target = self
    item.button?.action = #selector(clicked)
    item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    item.button?.imagePosition = .imageLeading
    item.button?.setAccessibilityLabel("Daywell")
    model.feedback.listen { [weak self] event in self?.handle(event) }
    observe()
  }

  public var button: NSStatusBarButton? { item.button }

  private func observe() {
    withObservationTracking {
      render()
    } onChange: { [weak self] in
      Task { @MainActor in self?.observe() }
    }
  }

  /// What the ticker says right now. Exposed for checks.
  public var text: String {
    guard preferences.tickerShowsTask else { return "" }
    if let flash { return flash }
    let today = model.today
    if let finishing { return Self.truncate(finishing.title) }
    if today.isDayClear { return "Day clear · \(today.pile.count)" }
    guard let task = today.tickerTask else { return "Choose today" }
    var text = Self.truncate(task.title)
    let more = today.myDay.count - 1
    if more > 0 { text += "  +\(more)" }
    if case .reminder(_, let after) = model.undo, after.isCompleted { text += " · undo" }
    return text
  }

  static func truncate(_ title: String) -> String {
    title.count <= maxTitleCharacters ? title : String(title.prefix(maxTitleCharacters - 1)) + "…"
  }

  func render() {
    guard let button = item.button else { return }
    let today = model.today
    _ = preferences.tickerShowsTask
    let font = NSFont.menuBarFont(ofSize: 0)
    if !preferences.tickerShowsTask {
      button.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "Daywell")
      button.attributedTitle = NSAttributedString()
      regions = []
      return
    }
    let style: RingImage.Style =
      finishing != nil || today.isDayClear
      ? .filled(finishing != nil ? ringProgress : 1)
      : (today.tickerTask == nil ? .dashed : .open)
    button.image = RingImage.make(style)
    let text = text
    let attributed = NSMutableAttributedString(string: " " + text, attributes: [.font: font])
    if finishing != nil {
      attributed.addAttribute(
        .strikethroughStyle, value: NSUnderlineStyle.single.rawValue,
        range: NSRange(location: 0, length: attributed.length))
    }
    if let plus = text.range(of: "  +") {
      let start = NSRange(plus, in: text).location + 1
      attributed.addAttribute(
        .foregroundColor, value: NSColor.secondaryLabelColor,
        range: NSRange(location: start, length: attributed.length - start))
    }
    button.attributedTitle = attributed
    button.setAccessibilityLabel(
      today.tickerTask.map { "Daywell: \($0.title). Click the ring to finish it." } ?? "Daywell")
    // Hit regions in button coordinates: ring image, then title, "+N", "undo".
    let ringWidth: CGFloat = 22
    func width(_ string: String) -> CGFloat {
      (string as NSString).size(withAttributes: [.font: font]).width
    }
    var regions: [(ClosedRange<CGFloat>, Region)] = [(0...ringWidth, .ring)]
    let full = " " + text
    if let plusRange = full.range(of: "  +") {
      let before = width(String(full[..<plusRange.lowerBound]))
      regions.append((ringWidth...(ringWidth + before), .title))
      if let undoRange = full.range(of: " · undo") {
        let moreEnd = width(String(full[..<undoRange.lowerBound]))
        regions.append(((ringWidth + before)...(ringWidth + moreEnd), .more))
        regions.append(((ringWidth + moreEnd)...(ringWidth + width(full) + 8), .undo))
      } else {
        regions.append(((ringWidth + before)...(ringWidth + width(full) + 8), .more))
      }
    } else if let undoRange = full.range(of: " · undo") {
      let before = width(String(full[..<undoRange.lowerBound]))
      regions.append((ringWidth...(ringWidth + before), .title))
      regions.append(((ringWidth + before)...(ringWidth + width(full) + 8), .undo))
    } else {
      regions.append((ringWidth...(ringWidth + width(full) + 8), .title))
    }
    self.regions = regions.map { (range: $0.0, region: $0.1) }
  }

  public func region(atX x: CGFloat) -> Region {
    regions.first { $0.range.contains(x) }?.region ?? .title
  }

  @objc private func clicked() {
    guard let button = item.button, let event = NSApp.currentEvent else { return }
    if event.type == .rightMouseUp {
      showMenu()
      return
    }
    let x = button.convert(event.locationInWindow, from: nil).x
    perform(region(atX: x))
  }

  /// Performs a click on a region. Public for the UI check harness.
  func perform(_ region: Region) {
    switch region {
    case .ring:
      if let task = model.today.tickerTask {
        Task { await model.toggleCompletion(task.id) }
      } else {
        togglePanel()
      }
    case .title: togglePanel()
    case .more: showMenu()
    case .undo: Task { await model.undoLast() }
    }
  }

  public func clickRing() { perform(.ring) }
  public func clickUndo() { perform(.undo) }

  private func showMenu() {
    let menu = NSMenu()
    for task in model.today.myDay {
      let entry = NSMenuItem(
        title: task.title, action: #selector(pinFromMenu(_:)), keyEquivalent: "")
      entry.target = self
      entry.representedObject = task.id
      entry.state = model.today.pinnedID == task.id ? .on : .off
      menu.addItem(entry)
    }
    if !model.today.myDay.isEmpty { menu.addItem(.separator()) }
    let open = NSMenuItem(title: "Open Daywell", action: #selector(openPanel), keyEquivalent: "")
    open.target = self
    menu.addItem(open)
    if let button = item.button {
      menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }
  }

  @objc private func pinFromMenu(_ sender: NSMenuItem) {
    guard let id = sender.representedObject as? String else { return }
    if model.today.pinnedID != id { model.pin(id) }
  }

  @objc private func openPanel() { togglePanel() }

  public func flash(_ text: String) {
    flash = text
    render()
    flashTask?.cancel()
    flashTask = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(1200))
      guard !Task.isCancelled else { return }
      self?.flash = nil
      self?.render()
    }
  }

  private func handle(_ event: FeedbackEvent) {
    switch event.kind {
    case .finishing:
      guard let reminder = event.reminder, reminder.id == model.today.tickerTask?.id else { return }
      finishing = reminder
      animateRing()
    case .finishFailed:
      finishing = nil
      ringTask?.cancel()
      render()
    case .finished:
      guard finishing?.id == event.reminder?.id else { return }
      // Hold the struck title for the length of the finish motion, then roll on.
      Task { [weak self] in
        try? await Task.sleep(for: MotionState.finishHold)
        self?.finishing = nil
        self?.render()
      }
    case .captured(let list): flash("→ \(list)")
    default: break
    }
  }

  private func animateRing() {
    ringTask?.cancel()
    ringProgress = 0
    ringTask = Task { [weak self] in
      let clock = ContinuousClock()
      let start = clock.now
      while !Task.isCancelled {
        let elapsed = (clock.now - start) / .milliseconds(220)
        let t = min(1, elapsed)
        self?.ringProgress = CGFloat(1 - pow(1 - t, 3))
        self?.render()
        if t >= 1 { return }
        try? await Task.sleep(for: .milliseconds(16))
      }
    }
  }
}

/// Template ring images for the menu bar; macOS tints them for light and dark bars.
enum RingImage {
  enum Style: Equatable {
    case open, dashed
    case filled(CGFloat)
  }

  static func make(_ style: Style) -> NSImage {
    let size = NSSize(width: 16, height: 16)
    let image = NSImage(size: size, flipped: false) { rect in
      let circle = NSBezierPath(ovalIn: rect.insetBy(dx: 2.5, dy: 2.5))
      circle.lineWidth = 1.4
      NSColor.black.setStroke()
      NSColor.black.setFill()
      switch style {
      case .open: circle.stroke()
      case .dashed:
        circle.setLineDash([2, 2], count: 2, phase: 0)
        circle.stroke()
      case .filled(let progress):
        circle.stroke()
        let inner = rect.insetBy(dx: 2.5 + 5.5 * (1 - progress), dy: 2.5 + 5.5 * (1 - progress))
        NSBezierPath(ovalIn: inner).fill()
        if progress >= 1 {
          // Knock out a check so it reads as done, not as a dot.
          NSGraphicsContext.current?.compositingOperation = .clear
          let check = NSBezierPath()
          check.move(to: NSPoint(x: 5.2, y: 8.2))
          check.line(to: NSPoint(x: 7.2, y: 6))
          check.line(to: NSPoint(x: 10.8, y: 10.4))
          check.lineWidth = 1.6
          check.lineCapStyle = .round
          check.stroke()
        }
      }
      return true
    }
    image.isTemplate = true
    return image
  }
}
