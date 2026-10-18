import AppKit
import SwiftUI

/// A panel that takes keyboard focus without activating Daywell, so the app you were
/// in stays frontmost and gets focus back the moment the panel closes.
public final class FloatingPanel: NSPanel {
  public init(level: NSWindow.Level) {
    super.init(
      contentRect: NSRect(x: 0, y: 0, width: 420, height: 300),
      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    self.level = level
    isFloatingPanel = true
    becomesKeyOnlyIfNeeded = false
    hidesOnDeactivate = false
    isOpaque = false
    backgroundColor = .clear
    hasShadow = true
    isMovable = false
    collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient]
    animationBehavior = .none
  }

  public override var canBecomeKey: Bool { true }
  public override var canBecomeMain: Bool { false }
}

/// Hosts SwiftUI content and reports its preferred size, so panels fit their content.
final class FittingHostingController<Content: View>: NSHostingController<Content> {
  override init(rootView: Content) {
    super.init(rootView: rootView)
    sizingOptions = [.preferredContentSize]
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { nil }
}
