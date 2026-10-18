import DaywellCore
import Foundation

/// A key press, independent of AppKit so routing is testable.
public struct KeyInput: Sendable {
  public enum Special: Sendable { case up, down, left, right, enter, escape, tab, space, delete }
  public var characters: String
  public var special: Special?
  public var command = false
  public var option = false
  public var control = false
  public var shift = false
  /// A text field has focus; plain letters belong to it.
  public var isEditing = false

  public init(
    _ characters: String, special: Special? = nil, command: Bool = false, option: Bool = false,
    control: Bool = false, shift: Bool = false, isEditing: Bool = false
  ) {
    self.characters = characters
    self.special = special
    self.command = command
    self.option = option
    self.control = control
    self.shift = shift
    self.isEditing = isEditing
  }
}

/// Maps keys to actions in the panel. Returns true when the key was used.
@MainActor public final class PanelKeys {
  let model: DayModel
  let panel: PanelState
  let shell: ShellActions
  var navigation: VimNavigation

  /// Forgets a half-typed "gg" when the panel closes.
  public func reset() { navigation = VimNavigation() }

  public init(model: DayModel, panel: PanelState, shell: ShellActions) {
    self.model = model
    self.panel = panel
    self.shell = shell
    navigation = VimNavigation()
  }

  public func handle(_ key: KeyInput) -> Bool {
    if key.command && !key.option && !key.control {
      switch key.characters.lowercased() {
      case "z" where !key.isEditing: run(.undo)
      case "k": panel.route = .commands
      case "f": run(.browse)
      case "n": run(.capture)
      case ",": run(.settings)
      case "q": run(.quit)
      default: return false
      }
      return true
    }
    switch panel.route {
    case .today: return handleToday(key)
    case .morning: return handleMorning(key)
    case .move(let id): return handleMove(key, id: id)
    case .sort(let listID): return handleSort(key, listID: listID)
    case .commands: return handleCommands(key)
    case .browse, .edit, .settings, .help:
      if key.special == .escape {
        panel.route = .today
        return true
      }
      return false
    }
  }

  private func handleToday(_ key: KeyInput) -> Bool {
    if key.option, key.special == .up || key.special == .down {
      run(key.special == .up ? .reorderUp : .reorderDown)
      return true
    }
    guard !key.option, !key.control else { return false }
    switch key.special {
    case .escape:
      navigation = VimNavigation()
      shell.closePanel()
      return true
    case .enter:
      if case .task = panel.selection { run(.edit) } else { panel.open() }
      return true
    case .space:
      if case .pileHeader = panel.selection {
        panel.pileExpanded.toggle()
      } else if case .shelf(let id) = panel.selection {
        if panel.expandedShelves.contains(id) { panel.close() } else { panel.open() }
      } else {
        run(.finish)
      }
      return true
    default: break
    }
    let character = Self.navigationCharacter(key)
    if let action = navigation.action(for: character, isEditing: false) {
      switch action {
      case .next: panel.move(1)
      case .previous: panel.move(-1)
      case .first: panel.selectFirst()
      case .last: panel.selectLast()
      case .open: panel.open()
      case .back: panel.close()
      }
      return true
    }
    if character == "g" { return true }
    let commands: [String: DaywellCommand] = [
      "x": .finish, "p": .pin, "a": .pull, "r": .release, "m": .move, "e": .edit,
      "s": .shelves, "?": .help,
    ]
    guard let command = commands[character] else { return false }
    run(command)
    return true
  }

  private func handleMorning(_ key: KeyInput) -> Bool {
    let flat = panel.morningFlat
    switch key.special {
    case .escape:
      model.skipMorningPull()
      panel.route = .today
      return true
    case .enter:
      model.startDay(picking: panel.morningPicks)
      panel.route = .today
      return true
    case .space:
      if flat.indices.contains(panel.morningIndex) {
        panel.toggleMorningPick(flat[panel.morningIndex].id)
      }
      return true
    case .down, .right:
      panel.morningIndex = min(panel.morningIndex + 1, max(flat.count - 1, 0))
      return true
    case .up, .left:
      panel.morningIndex = max(panel.morningIndex - 1, 0)
      return true
    default: break
    }
    switch key.characters {
    case "j", "l": panel.morningIndex = min(panel.morningIndex + 1, max(flat.count - 1, 0))
    case "k", "h": panel.morningIndex = max(panel.morningIndex - 1, 0)
    case let digit where Int(digit).map({ (1...9).contains($0) }) == true:
      // Digits toggle the Nth chip.
      if let number = Int(digit), flat.indices.contains(number - 1) {
        panel.morningIndex = number - 1
        panel.toggleMorningPick(flat[number - 1].id)
      }
    default: return false
    }
    return true
  }

  private func handleMove(_ key: KeyInput, id: String) -> Bool {
    let lists = model.writableLists
    switch key.special {
    case .escape:
      panel.route = panel.returnRoute ?? .today
      panel.returnRoute = nil
      return true
    case .enter:
      if id.isEmpty || panel.moveIndex == lists.count {
        let name = panel.newShelfName
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return true }
        let model = model
        let panel = panel
        Task {
          if let list = await model.createShelf(named: name), !id.isEmpty {
            await model.move(id, toList: list.id)
          }
          panel.route = panel.returnRoute ?? .today
          panel.returnRoute = nil
        }
      } else if lists.indices.contains(panel.moveIndex) {
        let target = lists[panel.moveIndex].id
        Task { await model.move(id, toList: target) }
        panel.route = .today
      }
      return true
    case .down:
      panel.moveIndex = min(panel.moveIndex + 1, lists.count)
      return true
    case .up:
      panel.moveIndex = max(panel.moveIndex - 1, 0)
      return true
    default: break
    }
    guard !key.isEditing else { return false }
    switch key.characters {
    case "j": panel.moveIndex = min(panel.moveIndex + 1, lists.count)
    case "k": panel.moveIndex = max(panel.moveIndex - 1, 0)
    default: return false
    }
    return true
  }

  private func handleSort(_ key: KeyInput, listID: String) -> Bool {
    guard let current = panel.sortQueue.first else {
      if key.special == .escape || key.special == .enter { panel.route = .today }
      return true
    }
    let advance = {
      self.panel.sortQueue.removeFirst()
      self.panel.sortDone += 1
    }
    switch key.special {
    case .escape, .enter:
      panel.route = .today
      return true
    case .right:
      advance()
      return true
    default: break
    }
    switch key.characters {
    case "s":
      advance()
    case "t":
      model.choose(current)
      advance()
    case "n":
      panel.newShelfName = ""
      panel.moveIndex = -1
      panel.returnRoute = .sort(listID)
      panel.route = .move("")
    case let digit where Int(digit).map({ (1...9).contains($0) }) == true:
      let targets = panel.sortTargets(from: listID)
      guard let number = Int(digit), targets.indices.contains(number - 1) else { return true }
      let target = targets[number - 1].id
      advance()
      Task { await model.move(current, toList: target) }
    default: return false
    }
    return true
  }

  private func handleCommands(_ key: KeyInput) -> Bool {
    let matches = DaywellCommand.matching(panel.commandQuery)
    switch key.special {
    case .escape: panel.route = .today
    case .down: panel.commandIndex = min(panel.commandIndex + 1, max(matches.count - 1, 0))
    case .up: panel.commandIndex = max(panel.commandIndex - 1, 0)
    case .enter:
      if matches.indices.contains(panel.commandIndex) {
        let command = matches[panel.commandIndex]
        panel.route = .today
        command.perform(model, panel, shell)
      }
    default: return false
    }
    return true
  }

  private func run(_ command: DaywellCommand) { command.perform(model, panel, shell) }

  static func navigationCharacter(_ key: KeyInput) -> String {
    switch key.special {
    case .down: "↓"
    case .up: "↑"
    case .left: "←"
    case .right: "→"
    default: key.characters
    }
  }
}
