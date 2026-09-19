import DaywellCore
import Foundation
import Observation

@MainActor @Observable public final class AppModel {
  public private(set) var reminders: [ReminderItem] = []
  public private(set) var lists: [ReminderList] = []
  public private(set) var plan = DayPlan()
  public var error: String?
  public var captureText = ""
  public var captureListID = ""
  public var captureAddToDay = false
  public var captureUsesDate = true
  public private(set) var authorized = false
  public private(set) var busy = false
  public var route: PanelRoute = .day {
    didSet {
      if route == .capture, oldValue != .capture, captureText.isEmpty {
        captureListID = effectiveInboxID
      }
      if route != .edit { editing = nil }
      reconcileSelection()
    }
  }
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
  public var dueExpanded = false { didSet { reconcileSelection() } }
  public private(set) var expandedListIDs: Set<String> = []
  public private(set) var editing: ReminderItem?
  public var pendingDelete: ReminderItem?
  public var notice: String?
  public private(set) var undo: (before: ReminderItem, after: ReminderItem)?
  private var storageAvailable = true
  public var recoveryRequired: Bool { !storageAvailable }
  private var refreshID = UUID()
  private var defaultListID: String?
  private let preferences: Preferences?
  private let store: any ReminderStore
  public let planStore: PlanStore
  public var now: Date
  public let calendar: Calendar
  public init(
    store: any ReminderStore, planStore: PlanStore, now: Date = Date(),
    calendar: Calendar = .autoupdatingCurrent, preferences: Preferences? = nil
  ) {
    self.store = store
    self.planStore = planStore
    self.preferences = preferences
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
  public func restorePlanBackup() {
    guard !busy, recoveryRequired else { return }
    do {
      plan = try planStore.restoreBackup()
      storageAvailable = true
      error = nil
      notice = "Day plan restored. The original file is preserved beside your day plan."
      reconcileSelection()
    } catch {
      self.error = "Could not restore the day plan: \(error.localizedDescription)"
    }
  }

  public var writableLists: [ReminderList] { lists.filter(\.isWritable) }
  private var effectiveInboxID: String {
    let preferred = preferences?.inboxID ?? ""
    return writableLists.first { $0.id == preferred }?.id
      ?? writableLists.first { $0.id == defaultListID }?.id
      ?? writableLists.first?.id ?? ""
  }
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
    // A reminder can appear in a date section and its source list; navigate each identity once.
    var seen = Set<String>()
    let dayItems =
      p.today + (dueExpanded ? p.due : [])
      + (previousExpanded ? p.previous : []) + (doneExpanded ? p.done : [])
    let listItems = dayLists.filter { expandedListIDs.contains($0.id) }.flatMap(\.items)
    return (dayItems + listItems)
      .filter { seen.insert($0.id).inserted }
  }

  public var dayLists: [ReminderListSection] {
    let chosen = Set(projection.today.map(\.id))
    let remaining = reminders.filter { !$0.isCompleted && !chosen.contains($0.id) }
      .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    let grouped = Dictionary(grouping: remaining, by: \.listID)
    return lists.map { ReminderListSection(list: $0, items: grouped[$0.id] ?? []) }
  }

  /// Keep list counts stable, but don't repeat rows already visible in the date sections.
  public func inlineListItems(_ section: ReminderListSection) -> [ReminderItem] {
    let p = projection
    let shown = Set(((dueExpanded ? p.due : []) + (previousExpanded ? p.previous : [])).map(\.id))
    return section.items.filter { !shown.contains($0.id) }
  }

  public func setListExpanded(_ id: String, expanded: Bool) {
    if expanded { expandedListIDs.insert(id) } else { expandedListIDs.remove(id) }
    reconcileSelection()
  }

  public var sectionsExpanded: Bool {
    dueExpanded || previousExpanded || doneExpanded || !expandedListIDs.isEmpty
  }

  public func toggleSections() {
    let expand = !sectionsExpanded
    dueExpanded = expand
    previousExpanded = expand
    doneExpanded = expand
    expandedListIDs = expand ? Set(lists.map(\.id)) : []
    reconcileSelection()
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
      defaultListID = snapshot.defaultListID
      if !writableLists.contains(where: { $0.id == captureListID }) {
        captureListID = effectiveInboxID
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
    guard DaywellCommand.choose.isEnabled(self, reminderID: id) else { return }
    updatePlan { $0.choose(id, on: now, calendar: calendar) }
  }

  public func pin(_ id: String) {
    guard DaywellCommand.pin.isEnabled(self, reminderID: id) else { return }
    updatePlan {
      if projection.pinnedReminderID == id {
        $0.unpin()
      } else {
        $0.pin(id, on: now, calendar: calendar)
      }
    }
  }

  public func release(_ id: String) {
    guard DaywellCommand.release.isEnabled(self, reminderID: id) else { return }
    updatePlan { $0.release(id) }
  }
  public func keepPrevious(_ ids: [String]) {
    guard !busy else { return }
    updatePlan { $0.keepPrevious(reminderIDs: ids, on: now, calendar: calendar) }
  }
  public func releasePrevious() {
    guard !busy else { return }
    let ids = projection.previous.map(\.id)
    updatePlan { candidate in
      for id in ids { candidate.release(id) }
    }
  }

  @discardableResult
  private func updatePlan(_ update: (inout DayPlan) -> Void) -> Bool {
    guard storageAvailable else {
      error = "The saved day plan needs recovery before it can be changed."
      return false
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
      return true
    } catch {
      if error is DecodingError || error is PlanStoreError { storageAvailable = false }
      self.error = "Could not save your day plan: \(error.localizedDescription)"
      return false
    }
  }

  public func complete(_ id: String) async {
    guard DaywellCommand.complete.isEnabled(self, reminderID: id),
      let original = reminders.first(where: { $0.id == id })
    else { return }
    busy = true
    defer { busy = false }
    do {
      var changed = original
      changed.isCompleted.toggle()
      changed.completionDate = changed.isCompleted ? now : nil
      let saved = try await store.save(changed, replacing: original)
      if saved.isCompleted != changed.isCompleted {
        // EventKit can keep the recurring series at the same ID, advance its
        // deadline, and create a separate completed occurrence. Reversing these
        // snapshots would reschedule the next occurrence, not undo completion.
        undo = nil
        notice = nil
        if changed.isCompleted, saved.id == original.id,
          let beforeDue = original.dueDate, let nextDue = saved.dueDate, nextDue > beforeDue
        {
          updatePlan { $0.release(original.id) }
          notice = "Occurrence completed. Undo unavailable for this repeating reminder."
        } else {
          error =
            "Apple Reminders did not confirm the completion change. Review the refreshed reminder before trying again."
        }
        await refresh()
        return
      }
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
    let submittedText = captureText
    let addToDay = captureAddToDay
    let usesDate = captureUsesDate
    let submittedAt = now
    busy = true
    defer { busy = false }
    do {
      let value = ReminderItem(
        id: "", title: preview.title, listID: list.id, listName: list.title,
        dueDate: usesDate ? preview.dueDate : nil,
        hasDueTime: usesDate && preview.hasTime)
      let saved = try await store.save(value, replacing: nil)
      // A confirmed write is usable even if the next fetch fails. Invalidate
      // older fetches before publishing it, and never repeat remote creation.
      refreshID = UUID()
      reminders.removeAll { $0.id == saved.id }
      reminders.append(saved)
      let planSaved =
        !addToDay
        || updatePlan {
          $0.choose(saved.id, on: submittedAt, calendar: calendar)
        }
      if captureText == submittedText, captureListID == list.id,
        captureAddToDay == addToDay, captureUsesDate == usesDate
      {
        captureText = ""
        captureUsesDate = true
        captureAddToDay = false
        if route == .capture { route = .day }
      }
      if visibleItems.contains(where: { $0.id == saved.id }) { selectedID = saved.id }
      notice =
        planSaved
        ? "Saved to \(list.title)"
        : "Saved to \(list.title), but not added to My Day. Repair the day plan, then add it from Browse."
      await refresh()
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

  public func edit(_ id: String) {
    guard DaywellCommand.edit.isEnabled(self, reminderID: id) else { return }
    editing = reminders.first { $0.id == id }
    route = .edit
  }

  public func requestDelete(_ original: ReminderItem) {
    guard DaywellCommand.delete.isEnabled(self, reminderID: original.id) else { return }
    pendingDelete = original
  }

  public func deleteConfirmed(_ confirmed: ReminderItem? = nil) async {
    guard !busy, let original = confirmed ?? pendingDelete else { return }
    busy = true
    defer { busy = false }
    do {
      try await store.delete(original)
      updatePlan { $0.release(original.id) }
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
      if let id = selectedID { edit(id) }
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

public struct ReminderListSection: Identifiable {
  public let list: ReminderList
  public let items: [ReminderItem]
  public var id: String { list.id }
}

public enum PanelRoute: String { case day, browse, capture, commands, help, settings, edit }
