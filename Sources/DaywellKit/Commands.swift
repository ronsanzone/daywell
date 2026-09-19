import AppKit

public enum DaywellCommand: String, CaseIterable, Identifiable {
  case capture, browse, choose, pin, complete, edit, release, undo, reset, done, keepAll,
    releaseAll, delete, help, settings, appleReminders, quit, sections
  public var id: String { rawValue }
  public var title: String {
    switch self {
    case .capture: "Add reminder"
    case .browse: "Search reminders"
    case .choose: "Add selected to My Day"
    case .pin: "Pin / unpin selected reminder"
    case .complete: "Complete / reopen reminder"
    case .edit: "Edit selected reminder"
    case .release: "Remove from My Day"
    case .undo: "Undo completion"
    case .reset: "Review previous commitments"
    case .done: "Show / hide Done today"
    case .sections: "Expand / collapse all sections"
    case .keepAll: "Keep all previous commitments"
    case .releaseAll: "Release previous commitments"
    case .delete: "Delete selected reminder…"
    case .help: "Show keyboard shortcuts"
    case .settings: "Settings"
    case .appleReminders: "Open Apple Reminders"
    case .quit: "Quit Daywell"
    }
  }
  public var symbol: String {
    switch self {
    case .capture: "plus"
    case .browse: "magnifyingglass"
    case .choose: "sun.max"
    case .pin: "pin"
    case .complete: "checkmark.circle"
    case .edit: "pencil"
    case .release: "minus.circle"
    case .undo: "arrow.uturn.backward"
    case .reset: "arrow.counterclockwise"
    case .help: "keyboard"
    case .settings: "gearshape"
    case .done: "checkmark.circle.fill"
    case .sections: "list.bullet.indent"
    case .keepAll: "sun.max"
    case .releaseAll: "minus.circle"
    case .delete: "trash"
    case .appleReminders: "arrow.up.forward.app"
    case .quit: "power"
    }
  }
  public var keyBinding: (key: String, command: Bool)? {
    switch self {
    case .capture: ("n", true)
    case .browse: ("f", true)
    case .choose: ("a", false)
    case .pin: ("p", false)
    case .complete: ("x", false)
    case .edit: ("e", false)
    case .release: ("r", false)
    case .undo: ("z", true)
    case .help: ("?", false)
    case .settings: (",", true)
    case .quit: ("q", true)
    case .done: ("d", false)
    case .sections: ("s", false)
    case .reset, .appleReminders, .keepAll, .releaseAll, .delete: nil
    }
  }
  public var shortcut: String {
    guard let binding = keyBinding else { return "" }
    if self == .edit { return "e / ↵ / l" }
    return binding.command ? "⌘ \(binding.key.uppercased())" : binding.key
  }
  @MainActor public func isEnabled(_ model: AppModel, reminderID: String? = nil) -> Bool {
    guard !model.busy else { return false }
    let id = reminderID ?? model.selectedID
    switch self {
    case .pin, .choose:
      return model.reminders.contains { $0.id == id && !$0.isCompleted }
    case .complete, .edit, .delete:
      return model.reminders.contains { $0.id == id && $0.isWritable }
    case .release: return model.plan.commitments.contains { $0.reminderID == id }
    case .undo: return model.undo != nil
    case .capture: return model.authorized && !model.writableLists.isEmpty
    case .sections: return model.authorized
    case .keepAll, .releaseAll: return !model.projection.previous.isEmpty
    default: return true
    }
  }
  @MainActor public func perform(_ model: AppModel) {
    guard isEnabled(model) else { return }
    switch self {
    case .capture: model.route = .capture
    case .browse: model.route = .browse
    case .choose:
      if let id = model.selectedID { model.choose(id) }
      model.route = .day
    case .pin:
      if let id = model.selectedID { model.pin(id) }
      model.route = .day
    case .complete:
      if let id = model.selectedID { Task { await model.complete(id) } }
      model.route = .day
    case .edit:
      if let id = model.selectedID { model.edit(id) }
    case .release:
      if let id = model.selectedID { model.release(id) }
      model.route = .day
    case .undo:
      Task { await model.undoCompletion() }
      model.route = .day
    case .reset:
      model.previousExpanded = true
      model.route = .day
    case .done:
      model.doneExpanded.toggle()
      model.route = .day
    case .sections:
      model.toggleSections()
      model.route = .day
    case .keepAll:
      model.keepPrevious(model.projection.previous.map(\.id))
      model.route = .day
    case .releaseAll:
      model.releasePrevious()
      model.route = .day
    case .delete:
      if let original = model.reminders.first(where: { $0.id == model.selectedID }) {
        model.requestDelete(original)
      }
    case .help: model.route = .help
    case .settings: model.route = .settings
    case .appleReminders:
      if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.reminders")
      {
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
      }
    case .quit: NSApplication.shared.terminate(nil)
    }
  }
}
