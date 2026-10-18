import DaywellCore
import Foundation
import Observation

public enum PanelRoute: Equatable, Sendable {
  case today, morning, browse, settings, commands, help
  case edit(String)
  /// Choosing a shelf for a reminder (m).
  case move(String)
}

/// A row the keyboard can land on in the Today view.
public enum PanelRow: Hashable, Sendable {
  case task(String)
  case dueHeader
  case shelf(String)
  case shelfTask(listID: String, id: String)
  case pileHeader
  case pileTask(String)

  public var reminderID: String? {
    switch self {
    case .task(let id), .pileTask(let id), .shelfTask(_, let id): id
    default: nil
    }
  }
}

/// View state for the panel only. Domain state lives in `DayModel`.
@MainActor @Observable public final class PanelState {
  public var route: PanelRoute = .today { didSet { if route != oldValue { reconcile() } } }
  public var selection: PanelRow?
  public var expandedShelves: Set<String> = [] { didSet { reconcile() } }
  public var dueExpanded = false { didSet { reconcile() } }
  public var pileExpanded = false { didSet { reconcile() } }
  public var search = ""
  public var commandQuery = ""
  public var commandIndex = 0
  public var moveIndex = 0
  public var newShelfName = ""
  /// Chips chosen in the morning pull.
  public var morningPicks: [String] = []
  public var morningIndex = 0

  @ObservationIgnored let model: DayModel
  @ObservationIgnored let motion: MotionState

  public init(model: DayModel, motion: MotionState) {
    self.model = model
    self.motion = motion
  }

  /// Rows in keyboard order for the Today view.
  public var rows: [PanelRow] {
    let today = model.today
    var rows = motion.displayedMyDay.map { PanelRow.task($0.id) }
    if !today.due.isEmpty {
      rows.append(.dueHeader)
      if dueExpanded { rows += today.due.map { .shelfTask(listID: "due", id: $0.id) } }
    }
    for shelf in today.shelves {
      rows.append(.shelf(shelf.id))
      if expandedShelves.contains(shelf.id) {
        rows += shelf.items.map { .shelfTask(listID: shelf.id, id: $0.id) }
      }
    }
    if !today.pile.isEmpty {
      rows.append(.pileHeader)
      if pileExpanded { rows += today.pile.map { .pileTask($0.id) } }
    }
    return rows
  }

  public var selectedReminderID: String? { selection?.reminderID }

  public func reconcile() {
    guard route == .today else { return }
    let rows = rows
    if let selection, rows.contains(selection) { return }
    selection = rows.first
  }

  public func move(_ step: Int) {
    let rows = rows
    guard !rows.isEmpty else {
      selection = nil
      return
    }
    let index = selection.flatMap(rows.firstIndex(of:)) ?? (step > 0 ? -1 : rows.count)
    selection = rows[min(max(index + step, 0), rows.count - 1)]
  }

  public func selectFirst() { selection = rows.first }
  public func selectLast() { selection = rows.last }

  /// l / →: open the shelf or section under the cursor.
  public func open() {
    switch selection {
    case .shelf(let id): expandedShelves.insert(id)
    case .dueHeader: dueExpanded = true
    case .pileHeader: pileExpanded = true
    case .task(let id), .shelfTask(_, let id), .pileTask(let id): route = .edit(id)
    case nil: break
    }
  }

  /// h / ←: close the shelf or section the cursor is in.
  public func close() {
    switch selection {
    case .shelf(let id), .shelfTask(let id, _):
      if id == "due" {
        dueExpanded = false
        selection = .dueHeader
      } else {
        expandedShelves.remove(id)
        selection = .shelf(id)
      }
    case .dueHeader: dueExpanded = false
    case .pileHeader, .pileTask:
      pileExpanded = false
      selection = .pileHeader
    default: break
    }
  }

  public func toggleAllShelves() {
    let ids = Set(model.today.shelves.map(\.id))
    expandedShelves = expandedShelves.isEmpty ? ids : []
  }

  /// Chips offered by the morning pull: leftovers, then the top two of each shelf.
  public var morningChoices: [(section: String, items: [ReminderItem])] {
    let today = model.today
    var sections: [(String, [ReminderItem])] = []
    if !today.leftovers.isEmpty { sections.append(("From yesterday", today.leftovers)) }
    let leftoverIDs = Set(today.leftovers.map(\.id))
    for shelf in today.shelves {
      let top = shelf.items.filter { !leftoverIDs.contains($0.id) }.prefix(2)
      if !top.isEmpty { sections.append((shelf.list.title, Array(top))) }
    }
    return sections
  }

  public var morningFlat: [ReminderItem] { morningChoices.flatMap(\.items) }

  public func beginMorning() {
    morningPicks = []
    morningIndex = 0
    route = .morning
  }

  public func toggleMorningPick(_ id: String) {
    if let index = morningPicks.firstIndex(of: id) {
      morningPicks.remove(at: index)
    } else {
      morningPicks.append(id)
    }
  }
}
