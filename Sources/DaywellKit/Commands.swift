import AppKit
import DaywellCore

/// Things the surfaces ask the shell to do (open the capture bar, close the panel).
@MainActor public struct ShellActions {
  public var openCapture: () -> Void
  public var closePanel: () -> Void
  public init(openCapture: @escaping () -> Void, closePanel: @escaping () -> Void) {
    self.openCapture = openCapture
    self.closePanel = closePanel
  }
}

/// The one command registry: palette, help, keys and buttons all use it.
public enum DaywellCommand: String, CaseIterable, Identifiable, Sendable {
  case capture, browse, finish, pin, pull, release, move, edit, reorderUp, reorderDown, undo,
    morning, shelves, newShelf, help, settings, appleReminders, quit

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .capture: "Catch something"
    case .browse: "Search reminders"
    case .finish: "Finish / reopen selected"
    case .pin: "Pin selected to the menu bar"
    case .pull: "Pull selected into My Day"
    case .release: "Not today: back to its shelf"
    case .move: "Move selected to another shelf"
    case .edit: "Edit selected"
    case .reorderUp: "Move up in My Day"
    case .reorderDown: "Move down in My Day"
    case .undo: "Undo"
    case .morning: "Pick today's few"
    case .shelves: "Open / close all shelves"
    case .newShelf: "New shelf"
    case .help: "Keyboard shortcuts"
    case .settings: "Settings"
    case .appleReminders: "Open Apple Reminders"
    case .quit: "Quit Daywell"
    }
  }

  public var symbol: String {
    switch self {
    case .capture: "plus"
    case .browse: "magnifyingglass"
    case .finish: "checkmark.circle"
    case .pin: "pin"
    case .pull: "arrow.up.circle"
    case .release: "arrow.down.circle"
    case .move: "tray.and.arrow.down"
    case .edit: "pencil"
    case .reorderUp: "arrow.up"
    case .reorderDown: "arrow.down"
    case .undo: "arrow.uturn.backward"
    case .morning: "sun.max"
    case .shelves: "books.vertical"
    case .newShelf: "folder.badge.plus"
    case .help: "keyboard"
    case .settings: "gearshape"
    case .appleReminders: "arrow.up.forward.app"
    case .quit: "power"
    }
  }

  /// Displayed shortcut.
  public var shortcut: String {
    switch self {
    case .capture: "⌃⌥Space"
    case .browse: "⌘F"
    case .finish: "x"
    case .pin: "p"
    case .pull: "a"
    case .release: "r"
    case .move: "m"
    case .edit: "↵"
    case .reorderUp: "⌥↑"
    case .reorderDown: "⌥↓"
    case .undo: "⌘Z"
    case .morning: ""
    case .shelves: "s"
    case .newShelf: ""
    case .help: "?"
    case .settings: "⌘,"
    case .appleReminders: ""
    case .quit: "⌘Q"
    }
  }

  @MainActor public func isEnabled(_ model: DayModel, _ panel: PanelState) -> Bool {
    let id = panel.selectedReminderID
    switch self {
    case .finish, .edit, .move: return id.map(model.canWrite) ?? false
    case .pin: return id.flatMap(model.reminder).map { !$0.isCompleted } ?? false
    case .pull:
      return id.map { !model.isChosen($0) && model.reminder($0)?.isCompleted == false } ?? false
    case .release:
      return id.map { id in model.plan.commitments.contains { $0.reminderID == id } } ?? false
    case .reorderUp, .reorderDown: return id.map(model.isChosen) ?? false
    case .undo: return model.undo != nil
    case .capture: return model.authorized && !model.writableLists.isEmpty
    case .newShelf: return model.authorized
    default: return true
    }
  }

  @MainActor public func perform(_ model: DayModel, _ panel: PanelState, _ shell: ShellActions) {
    guard isEnabled(model, panel) else { return }
    let id = panel.selectedReminderID
    if panel.route == .commands { panel.route = .today }
    switch self {
    case .capture: shell.openCapture()
    case .browse: panel.route = .browse
    case .finish: if let id { Task { await model.toggleCompletion(id) } }
    case .pin: if let id { model.pin(id) }
    case .pull: if let id { model.choose(id) }
    case .release: if let id { model.release(id) }
    case .move:
      if let id {
        panel.moveIndex = 0
        panel.route = .move(id)
      }
    case .edit: if let id { panel.route = .edit(id) }
    case .reorderUp: if let id { model.reorder(id, by: -1) }
    case .reorderDown: if let id { model.reorder(id, by: 1) }
    case .undo: Task { await model.undoLast() }
    case .morning: panel.beginMorning()
    case .shelves: panel.toggleAllShelves()
    case .newShelf:
      panel.newShelfName = ""
      panel.moveIndex = -1
      panel.route = .move("")
    case .help: panel.route = .help
    case .settings: panel.route = .settings
    case .appleReminders:
      if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.reminders")
      {
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
      }
      shell.closePanel()
    case .quit: NSApplication.shared.terminate(nil)
    }
  }

  public static func matching(_ query: String) -> [DaywellCommand] {
    allCases.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }
  }
}
