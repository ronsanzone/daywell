import Carbon
import SwiftUI

struct SettingsView: View {
  @Bindable var model: AppModel
  @Bindable var preferences: Preferences
  @State private var recording = false
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        VStack(alignment: .leading, spacing: 12) {
          Text("Appearance").font(.system(size: 13, weight: .semibold))
          ForEach(Theme.allCases) { theme in
            Button {
              preferences.theme = theme
            } label: {
              HStack(spacing: 10) {
                Circle().fill(theme.colors.background).overlay(
                  Circle().stroke(theme.colors.accent, lineWidth: 2)
                ).frame(width: 18, height: 18)
                Text(theme.title)
                Spacer()
                if theme == preferences.theme { Image(systemName: "checkmark") }
              }.padding(9).background(
                preferences.theme == theme ? preferences.theme.colors.raised : .clear,
                in: RoundedRectangle(cornerRadius: 6))
            }
          }
          if preferences.theme == .amber {
            VStack(alignment: .leading, spacing: 6) {
              HStack {
                Text("CRT intensity")
                Spacer()
                Text(preferences.crtIntensity, format: .percent.precision(.fractionLength(0)))
                  .monospacedDigit()
              }.font(.system(size: 12))
              Slider(value: $preferences.crtIntensity, in: 0...1, step: 0.05)
                .accessibilityLabel("CRT intensity")
                .accessibilityValue(preferences.crtIntensity.formatted(.percent))
              Text("0%: amber only · 100%: full phosphor. Static texture; no flicker or motion.")
                .font(.system(size: 11)).foregroundStyle(preferences.theme.colors.secondary)
                .fixedSize(horizontal: false, vertical: true)
              Toggle("Terminal motion", isOn: $preferences.terminalMotion)
                .font(.system(size: 12)).padding(.top, 8)
              Text(
                "Orbital relay, focus trails, and confirmed-action traces. Respects Reduce Motion; pauses when closed."
              )
              .font(.system(size: 11)).foregroundStyle(preferences.theme.colors.secondary)
              .fixedSize(horizontal: false, vertical: true)
            }.padding(.horizontal, 9)
          }
        }
        Toggle("Show unfinished My Day count in menu bar", isOn: $preferences.showCount).font(
          .system(size: 12))
        Picker("Default inbox", selection: $preferences.inboxID) {
          Text("Apple Reminders default").tag("")
          ForEach(model.writableLists) { Text($0.title).tag($0.id) }
        }
        VStack(alignment: .leading, spacing: 10) {
          Text("Open Daywell from anywhere").font(.system(size: 13, weight: .semibold))
          Button(recording ? "Press a shortcut…" : "Record global shortcut") { recording = true }
            .buttonStyle(.bordered)
          Text(
            "Use Control, Option, or Command with a key. Default: Control–Option–Space. Escape cancels recording."
          )
          .font(.system(size: 11)).foregroundStyle(preferences.theme.colors.secondary)
          .fixedSize(horizontal: false, vertical: true)
          if recording {
            ShortcutRecorder(preferences: preferences, recording: $recording).frame(height: 1)
          }
          Button("Restore default shortcut") {
            preferences.shortcutKey = 49
            preferences.shortcutModifiers = 6144
          }
          .font(.system(size: 11))
        }
        Text(
          "Daywell stores your day plan on this Mac. Apple Reminders handles your tasks and their existing alerts."
        )
        .font(.system(size: 12)).foregroundStyle(preferences.theme.colors.secondary)
        Button("Quit Daywell") { DaywellCommand.quit.perform(model) }.font(.system(size: 12))
      }.padding(20)
    }
  }
}

private struct ShortcutRecorder: NSViewRepresentable {
  let preferences: Preferences
  @Binding var recording: Bool
  func makeNSView(context: Context) -> RecorderView {
    let view = RecorderView()
    view.record = { event in
      if event.keyCode == 53 {
        recording = false
        return
      }
      let flags = event.modifierFlags
      guard !flags.intersection([.command, .control, .option]).isEmpty else { return }
      var modifiers = 0
      if flags.contains(.command) { modifiers |= cmdKey }
      if flags.contains(.control) { modifiers |= controlKey }
      if flags.contains(.option) { modifiers |= optionKey }
      if flags.contains(.shift) { modifiers |= shiftKey }
      preferences.shortcutKey = Int(event.keyCode)
      preferences.shortcutModifiers = modifiers
      recording = false
    }
    return view
  }
  func updateNSView(_ view: RecorderView, context: Context) {
    DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
  }
}

public final class RecorderView: NSView {
  var record: ((NSEvent) -> Void)?
  public override var acceptsFirstResponder: Bool { true }
  public override func keyDown(with event: NSEvent) { record?(event) }
  public override func performKeyEquivalent(with event: NSEvent) -> Bool {
    record?(event)
    return true
  }
}
