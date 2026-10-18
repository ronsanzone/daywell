import AppKit
import DaywellCore
import DaywellKit
import SwiftUI

/// Renders real windows to PNG: every surface in every theme.
@MainActor enum Snapshots {
  static func run(controller: AppController, directory: URL) async {
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let model = controller.model
    for theme in ThemeID.allCases {
      controller.preferences.theme = theme
      let name = theme.rawValue
      controller.showPanel()
      await settle()
      write(controller.panelWindow, to: directory, "\(name)-panel-today")
      controller.panelState.expandedShelves = ["devex"]
      controller.panelState.pileExpanded = true
      await settle()
      write(controller.panelWindow, to: directory, "\(name)-panel-shelves-pile")
      controller.panelState.expandedShelves = []
      controller.panelState.pileExpanded = false
      controller.panelState.beginMorning()
      if let first = controller.panelState.morningFlat.first {
        controller.panelState.toggleMorningPick(first.id)
      }
      await settle()
      write(controller.panelWindow, to: directory, "\(name)-panel-morning")
      controller.panelState.route = .today
      controller.hidePanel()
      controller.capture.text = "ask sean re qa run tmrw at 2pm /work"
      controller.showCapture()
      await settle()
      write(controller.captureWindow, to: directory, "\(name)-capture-draft")
      controller.capture.text = ""
      controller.capture.listIndex = 1
      await settle()
      write(controller.captureWindow, to: directory, "\(name)-capture-list")
      controller.capture.listIndex = nil
      controller.hideCapture()
      if let button = controller.ticker.button {
        write(view: button, to: directory, "\(name)-ticker")
      }
    }
    _ = model
    // Menu-bar ring states, drawn as macOS tints template images on a light menu bar.
    for (name, style) in [
      ("open", RingImage.Style.open), ("dashed", .dashed), ("half", .filled(0.5)),
      ("done", .filled(1)),
    ] {
      let image = RingImage.make(style)
      let size = NSSize(width: 64, height: 64)
      let canvas = NSImage(size: size, flipped: false) { rect in
        NSColor.white.setFill()
        rect.fill()
        image.draw(in: rect.insetBy(dx: 8, dy: 8))
        return true
      }
      if let tiff = canvas.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
        let png = bitmap.representation(using: .png, properties: [:])
      {
        try? png.write(to: directory.appendingPathComponent("ring-\(name).png"))
      }
    }
    print("Snapshots written to \(directory.path)")
  }

  static func settle() async { try? await Task.sleep(for: .milliseconds(450)) }

  static func write(_ window: NSWindow, to directory: URL, _ name: String) {
    guard let view = window.contentView else { return }
    write(view: view, to: directory, name)
  }

  static func write(view: NSView, to directory: URL, _ name: String) {
    view.layoutSubtreeIfNeeded()
    guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
    view.cacheDisplay(in: view.bounds, to: bitmap)
    guard let png = bitmap.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: directory.appendingPathComponent("\(name).png"))
  }
}
