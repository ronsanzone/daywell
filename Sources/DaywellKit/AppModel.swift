import DaywellCore
import Foundation
import Observation

@MainActor @Observable public final class AppModel {
  public var reminders: [ReminderItem] = []
  public var lists: [ReminderList] = []
  public var plan = DayPlan()
  public var error: String?
  public var captureText = ""
  public var captureListID = ""
  public var captureAddToDay = false
  public var captureUsesDate = true
  public var authorized = false
  public var busy = false
  public var route: PanelRoute = .day { didSet { reconcileSelection() } }
  public var selectedID: String?
  public var search = "" { didSet { reconcileSelection() } }
  public var commandQuery = ""
  public var commandIndex = 0
  public var matchingCommands: [DaywellCommand] {
    DaywellCommand.allCases.filter {
      commandQuery.isEmpty || $0.title.localizedCaseInsensitiveContains(commandQuery)
    }
  }
  public var browseListID = "" { didSet { reconcileSelection() } }
  public var doneExpanded = false { didSet { reconcileSelection() } }
  public var previousExpanded = false { didSet { reconcileSelection() } }
  public var editing: ReminderItem?
  public var pendingDelete: ReminderItem?
  public var notice: String?
  public private(set) var undo: (before: ReminderItem, after: ReminderItem)?
  private var storageAvailable = true
  private var refreshID = UUID()
  public let store: any ReminderStore
  public let planStore: PlanStore
  public var now: Date
  public let calendar: Calendar
  public init(
    store: any ReminderStore, planStore: PlanStore, now: Date = Date(),
    calendar: Calendar = .autoupdatingCurrent
  ) {
    self.store = store
    self.planStore = planStore
    self.now = now
    self.calendar = calendar
    authorized = store.authorized
    do { plan = try planStore.load() } catch {
      self.error = "Your day plan could not be loaded: \(error.localizedDescription)"
      storageAvailable = false
    }
  }
  public var projection: DayProjection {
    plan.projection(reminders: reminders, now: now, calendar: calendar)
  }
  public var capturePreview: CaptureResult {
    CaptureParser.parse(captureText, now: now, calendar: calendar)
  }
  public var writableLists: [ReminderList] { lists.filter(\.isWritable) }
  public var browsed: [ReminderItem] {
    reminders.filter {
      !$0.isCompleted && (browseListID.isEmpty || $0.listID == browseListID)
        && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)
          || $0.notes.localizedCaseInsensitiveContains(search))
    }
    .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
  }
  public var visibleItems: [ReminderItem] {
    if route == .browse { return browsed }
    let p = projection
    // A prior commitment may also be overdue; navigate each identity once.
    var seen = Set<String>()
    return (p.today + p.due + (previousExpanded ? p.previous : []) + (doneExpanded ? p.done : []))
      .filter { seen.insert($0.id).inserted }
  }

  public func requestAccess() async {
    do {
      authorized = try await store.requestAccess()
      if authorized { await refresh() } else { error = ReminderError.denied.localizedDescription }
    } catch { self.error = error.localizedDescription }
  }

  public func refresh() async {
    let requestID = UUID()
    refreshID = requestID
    authorized = store.authorized
    guard authorized else {
      reminders = []
      lists = []
      return
    }
    do {
      let snapshot = try await store.fetch()
      guard refreshID == requestID, store.authorized else { return }
      reminders = snapshot.reminders
      lists = snapshot.lists
      if !writableLists.contains(where: { $0.id == captureListID }) {
        captureListID =
          snapshot.defaultListID.flatMap { id in writableLists.first { $0.id == id }?.id }
          ?? writableLists.first?.id ?? ""
      }
      reconcileSelection()
    } catch {
      if refreshID == requestID { self.error = error.localizedDescription }
    }
  }

  private func reconcileSelection() {
    guard route == .day || route == .browse else { return }
    if !visibleItems.contains(where: { $0.id == selectedID }) {
      selectedID = visibleItems.first?.id
    }
  }

  public func choose(_ id: String) {
    guard reminders.contains(where: { $0.id == id && !$0.isCompleted }) else { return }
    updatePlan { $0.choose(id, on: now, calendar: calendar) }
  }

  public func pin(_ id: String) {
    guard reminders.contains(where: { $0.id == id && !$0.isCompleted }) else { return }
    updatePlan {
      if projection.pinnedReminderID == id {
        $0.unpin()
      } else {
        $0.pin(id, on: now, calendar: calendar)
      }
    }
  }

  public func release(_ id: String) { updatePlan { $0.release(id) } }
  public func keepPrevious(_ ids: [String]) {
    updatePlan { $0.keepPrevious(reminderIDs: ids, on: now, calendar: calendar) }
  }
  public func releasePrevious() {
    let ids = projection.previous.map(\.id)
    updatePlan { candidate in
      for id in ids { candidate.release(id) }
    }
  }

  private func updatePlan(_ update: (inout DayPlan) -> Void) {
    guard storageAvailable else {
      error = "The saved day plan needs recovery before it can be changed."
      return
    }
    var candidate = plan
    update(&candidate)
    for index in candidate.commitments.indices {
      if let item = reminders.first(where: { $0.id == candidate.commitments[index].reminderID }) {
        candidate.commitments[index].externalID = item.externalID
        candidate.commitments[index].listID = item.listID
      }
    }
    do {
      try planStore.save(candidate)
      plan = candidate
      reconcileSelection()
    } catch { self.error = "Could not save your day plan: \(error.localizedDescription)" }
  }

  public func complete(_ id: String) async {
    guard !busy, let original = reminders.first(where: { $0.id == id }) else { return }
    busy = true
    defer { busy = false }
    do {
      var changed = original
      changed.isCompleted.toggle()
      changed.completionDate = changed.isCompleted ? now : nil
      let saved = try await store.save(changed, replacing: original)
      undo = (original, saved)
      if saved.isCompleted && projection.pinnedReminderID == id { updatePlan { $0.unpin() } }
      await refresh()
      notice = saved.isCompleted ? "Reminder completed" : "Reminder reopened"
    } catch { self.error = error.localizedDescription }
  }

  public func undoCompletion() async {
    guard !busy, let undo else { return }
    busy = true
    defer { busy = false }
    do {
      _ = try await store.save(undo.before, replacing: undo.after)
      self.undo = nil
      notice = nil
      await refresh()
    } catch { self.error = error.localizedDescription }
  }

  public func saveCapture() async {
    let preview = capturePreview
    guard !busy else { return }
    guard !preview.title.isEmpty else {
      error = ReminderError.emptyTitle.localizedDescription
      return
    }
    guard let list = writableLists.first(where: { $0.id == captureListID }) else {
      error = ReminderError.readOnly.localizedDescription
      return
    }
    busy = true
    defer { busy = false }
    do {
      let value = ReminderItem(
        id: "", title: preview.title, listID: list.id, listName: list.title,
        dueDate: captureUsesDate ? preview.dueDate : nil,
        hasDueTime: captureUsesDate && preview.hasTime)
      let saved = try await store.save(value, replacing: nil)
      // The reminder already exists once save succeeds, even if the local
      // day-plan write fails. Clear capture to prevent accidental duplication.
      captureText = ""
      captureUsesDate = true
      await refresh()
      if captureAddToDay { choose(saved.id) }
      captureAddToDay = false
      route = .day
      if visibleItems.contains(where: { $0.id == saved.id }) { selectedID = saved.id }
      notice = "Saved to \(list.title)"
    } catch { self.error = error.localizedDescription }
  }

  public func saveEdit(_ value: ReminderItem, original: ReminderItem) async {
    guard !busy else { return }
    busy = true
    defer { busy = false }
    do {
      _ = try await store.save(value, replacing: original)
      editing = nil
      route = .day
      await refresh()
    } catch { self.error = error.localizedDescription }
  }

  public func deleteConfirmed(_ confirmed: ReminderItem? = nil) async {
    guard !busy, let original = confirmed ?? pendingDelete else { return }
    busy = true
    defer { busy = false }
    do {
      try await store.delete(original)
      release(original.id)
      pendingDelete = nil
      editing = nil
      route = .day
      await refresh()
    } catch { self.error = error.localizedDescription }
  }

  public func navigate(_ action: NavigationAction) {
    if route == .commands {
      switch action {
      case .next: commandIndex = min(commandIndex + 1, max(0, matchingCommands.count - 1))
      case .previous: commandIndex = max(0, commandIndex - 1)
      case .first: commandIndex = 0
      case .last: commandIndex = max(0, matchingCommands.count - 1)
      case .back: route = .day
      case .open:
        if matchingCommands.indices.contains(commandIndex) {
          matchingCommands[commandIndex].perform(self)
        }
      }
      return
    }
    let items = visibleItems
    switch action {
    case .back:
      route = .day
      editing = nil
    case .open:
      if let item = reminders.first(where: { $0.id == selectedID }) {
        editing = item
        route = .edit
      }
    case .first: selectedID = items.first?.id
    case .last: selectedID = items.last?.id
    case .next, .previous:
      guard !items.isEmpty else {
        selectedID = nil
        return
      }
      let index = items.firstIndex { $0.id == selectedID } ?? (action == .next ? -1 : items.count)
      selectedID = items[min(max(index + (action == .next ? 1 : -1), 0), items.count - 1)].id
    }
  }
}

public enum PanelRoute: String { case day, browse, capture, commands, help, settings, edit }
