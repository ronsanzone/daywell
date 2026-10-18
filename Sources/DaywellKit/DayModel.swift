import DaywellCore
import Foundation
import Observation

/// The single owner of reminders, the day plan, and every action that changes them.
/// UI state (routes, selection, text drafts) lives with each surface, not here.
@MainActor @Observable public final class DayModel {
  public private(set) var reminders: [ReminderItem] = []
  public private(set) var lists: [ReminderList] = []
  public private(set) var plan = DayPlan()
  /// Derived once per change of reminders, lists, plan, or day; read freely.
  public private(set) var today = Today()
  public private(set) var authorized = false
  public private(set) var now: Date
  public var error: String?
  public var notice: String?
  public private(set) var undo: UndoAction?
  /// Reminders with a write in flight; their rows show progress and refuse new writes.
  public private(set) var pending: Set<String> = []
  public let feedback = FeedbackCenter()
  public var recoveryRequired: Bool { !storageAvailable }

  public let calendar: Calendar
  public let planStore: PlanStore
  @ObservationIgnored private let store: any ReminderStore
  @ObservationIgnored private let preferences: Preferences?
  @ObservationIgnored private var storageAvailable = true
  @ObservationIgnored private var refreshID = UUID()
  @ObservationIgnored private var defaultListID: String?

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
    recompute()
  }

  // MARK: Derived

  public var writableLists: [ReminderList] { lists.filter(\.isWritable) }

  public var inboxListID: String {
    let preferred = preferences?.inboxID ?? ""
    return writableLists.first { $0.id == preferred }?.id
      ?? writableLists.first { $0.id == defaultListID }?.id
      ?? writableLists.first?.id ?? ""
  }

  public func reminder(_ id: String) -> ReminderItem? { reminders.first { $0.id == id } }
  public func isChosen(_ id: String) -> Bool { today.myDay.contains { $0.id == id } }
  public func canWrite(_ id: String) -> Bool {
    !pending.contains(id) && (reminder(id)?.isWritable ?? false)
  }

  private func recompute() {
    today = Today.build(
      plan: plan, reminders: reminders, lists: lists, now: now, calendar: calendar)
  }

  // MARK: Clock and refresh

  /// Called by the day clock at local midnight and on time or zone changes.
  public func setNow(_ date: Date) {
    let dayChanged = DayPlan.dayKey(for: date, calendar: calendar) != today.dayKey
    now = date
    if dayChanged {
      undo = nil
      recompute()
    }
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
      recompute()
      return
    }
    do {
      let snapshot = try await store.fetch(completedSince: calendar.startOfDay(for: now))
      // A later refresh or a confirmed write supersedes this result.
      guard refreshID == requestID, store.authorized else { return }
      // Keep optimistic local state for reminders whose writes are still in flight.
      var merged = snapshot.reminders.filter { !pending.contains($0.id) }
      merged += reminders.filter { pending.contains($0.id) }
      reminders = merged
      lists = snapshot.lists
      defaultListID = snapshot.defaultListID
      healUnresolved()
      recompute()
    } catch {
      if refreshID == requestID { self.error = error.localizedDescription }
    }
  }

  /// Re-link commitments whose Apple identifier changed (for example after a move
  /// between lists) using the external identifier recorded when they were chosen.
  private func healUnresolved() {
    let byID = Set(reminders.map(\.id))
    var candidate = plan
    var changed = false
    for commitment in plan.commitments where !byID.contains(commitment.reminderID) {
      guard let external = commitment.externalID,
        let match = reminders.first(where: { $0.externalID == external })
      else { continue }
      candidate.relink(from: commitment.reminderID, to: match.id)
      changed = true
    }
    if changed { _ = savePlan(candidate) }
  }

  // MARK: Plan actions (local, synchronous, undoable)

  public func choose(_ id: String) {
    guard let item = reminder(id), !item.isCompleted, !isChosen(id) else { return }
    if updatePlan({ $0.choose(id, on: now, calendar: calendar) }) {
      feedback.emit(.pulled, item)
    }
  }

  /// Puts a task back on its shelf. Nothing changes in Apple Reminders.
  public func release(_ id: String) {
    guard plan.commitments.contains(where: { $0.reminderID == id }) else { return }
    let item = reminder(id)
    if updatePlan({ $0.release(id) }) {
      feedback.emit(.released(shelf: item?.listName ?? ""), item)
    }
  }

  /// Pins a task so the menu bar shows it; pinning the pinned task unpins it.
  public func pin(_ id: String) {
    guard let item = reminder(id), !item.isCompleted else { return }
    updatePlan {
      if today.pinnedID == id { $0.unpin() } else { $0.pin(id, on: now, calendar: calendar) }
    }
  }

  public func reorder(_ id: String, by offset: Int) {
    let ids = today.myDay.map(\.id)
    updatePlan { $0.reorder(id, by: offset, among: ids, on: now) }
  }

  /// The morning pull: picked tasks become today's, unpicked leftovers go back to
  /// their shelves, and the pull doesn't ask again today.
  public func startDay(picking ids: [String]) {
    let leftovers = Set(today.leftovers.map(\.id))
    updatePlan { candidate in
      candidate.keepPrevious(
        reminderIDs: ids.filter(leftovers.contains), on: now, calendar: calendar)
      for id in ids where !leftovers.contains(id) {
        candidate.choose(id, on: now, calendar: calendar)
      }
      for id in leftovers where !ids.contains(id) { candidate.release(id) }
      candidate.markMorningPull(on: now, calendar: calendar)
    }
  }

  public func skipMorningPull() {
    updatePlan(undoable: false) { $0.markMorningPull(on: now, calendar: calendar) }
  }

  @discardableResult
  private func updatePlan(undoable: Bool = true, _ update: (inout DayPlan) -> Void) -> Bool {
    var candidate = plan
    update(&candidate)
    guard candidate != plan else { return true }
    let before = plan
    guard savePlan(candidate) else { return false }
    if undoable { undo = .plan(before: before) }
    return true
  }

  private func savePlan(_ proposed: DayPlan) -> Bool {
    guard storageAvailable else {
      error = "The saved day plan needs recovery before it can be changed."
      return false
    }
    var candidate = proposed
    let byID = Dictionary(reminders.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    for index in candidate.commitments.indices {
      if let item = byID[candidate.commitments[index].reminderID] {
        candidate.commitments[index].externalID = item.externalID
        candidate.commitments[index].listID = item.listID
      }
    }
    do {
      try planStore.save(candidate)
      plan = candidate
      recompute()
      return true
    } catch {
      if error is DecodingError || error is PlanStoreError { storageAvailable = false }
      self.error = "Could not save your day plan: \(error.localizedDescription)"
      return false
    }
  }

  public func restorePlanBackup() {
    guard recoveryRequired else { return }
    do {
      plan = try planStore.restoreBackup()
      storageAvailable = true
      error = nil
      notice = "Day plan restored. The original file is preserved beside your day plan."
      recompute()
    } catch {
      self.error = "Could not restore the day plan: \(error.localizedDescription)"
    }
  }

  // MARK: Reminder actions (Apple Reminders writes)

  /// Completes or reopens a reminder. Motion starts at once (`.finishing`); the
  /// pile, the ticker and the sound wait for Apple Reminders to confirm.
  public func toggleCompletion(_ id: String) async {
    guard canWrite(id), let original = reminder(id) else { return }
    let wasDayClear = today.isDayClear
    let completing = !original.isCompleted
    if completing { feedback.emit(.finishing, original) }
    pending.insert(id)
    defer { pending.remove(id) }
    var changed = original
    changed.isCompleted = completing
    changed.completionDate = completing ? Date() : nil
    do {
      let saved = try await store.save(changed, replacing: original)
      guard saved.isCompleted == completing else {
        handleUnconfirmedCompletion(original: original, saved: saved, completing: completing)
        await refresh()
        return
      }
      undo = .reminder(before: original, after: saved)
      publish(saved)
      feedback.emit(completing ? .finished : .reopened, saved)
      if completing, !wasDayClear, today.isDayClear {
        feedback.emit(.dayClear(count: today.pile.count))
      }
    } catch {
      if completing { feedback.emit(.finishFailed, original) }
      self.error = error.localizedDescription
    }
  }

  private func handleUnconfirmedCompletion(
    original: ReminderItem, saved: ReminderItem, completing: Bool
  ) {
    // EventKit can keep a recurring series at the same ID, advance its deadline,
    // and create a separate completed occurrence. Reversing these snapshots would
    // reschedule the next occurrence, not undo completion.
    undo = nil
    if completing, saved.id == original.id,
      let beforeDue = original.dueDate, let nextDue = saved.dueDate, nextDue > beforeDue
    {
      publish(saved)
      updatePlan(undoable: false) { $0.release(original.id) }
      feedback.emit(.finished, original)
      notice =
        "Done. Next one \(nextDue.formatted(date: .abbreviated, time: .omitted)); repeating reminders can't be undone here."
    } else {
      if completing { feedback.emit(.finishFailed, original) }
      error =
        "Apple Reminders did not confirm the change. Review the refreshed reminder before trying again."
    }
  }

  public func undoLast() async {
    guard let action = undo else { return }
    switch action {
    case .plan(let before):
      undo = nil
      if savePlan(before) { notice = nil }
    case .reminder(let before, let after):
      guard !pending.contains(after.id) else { return }
      pending.insert(after.id)
      defer { pending.remove(after.id) }
      do {
        // The store rejects this if the reminder changed elsewhere since.
        let saved = try await store.save(before, replacing: after)
        undo = nil
        publish(saved)
        if saved.isCompleted != after.isCompleted {
          feedback.emit(saved.isCompleted ? .finished : .reopened, saved)
        }
      } catch { self.error = error.localizedDescription }
    }
  }

  /// Saves a captured line. Returns the reminder once Apple Reminders confirmed it.
  public func capture(
    _ result: CaptureResult, listID: String, keepDate: Bool, addToDay: Bool
  ) async -> ReminderItem? {
    guard !result.title.isEmpty else {
      error = ReminderError.emptyTitle.localizedDescription
      return nil
    }
    guard let list = writableLists.first(where: { $0.id == listID }) else {
      error = ReminderError.readOnly.localizedDescription
      return nil
    }
    let submittedAt = now
    do {
      let value = ReminderItem(
        id: "", title: result.title, listID: list.id, listName: list.title,
        dueDate: keepDate ? result.dueDate : nil, hasDueTime: keepDate && result.hasTime)
      let saved = try await store.save(value, replacing: nil)
      publish(saved)
      if addToDay {
        updatePlan(undoable: false) { $0.choose(saved.id, on: submittedAt, calendar: calendar) }
      }
      feedback.emit(.captured(listTitle: list.title), saved)
      return saved
    } catch {
      self.error = error.localizedDescription
      return nil
    }
  }

  /// Moves a reminder to another list (shelf). Its My Day choice follows it.
  public func move(_ id: String, toList listID: String) async {
    guard canWrite(id), let original = reminder(id), original.listID != listID,
      let list = writableLists.first(where: { $0.id == listID })
    else { return }
    pending.insert(id)
    defer { pending.remove(id) }
    var changed = original
    changed.listID = list.id
    changed.listName = list.title
    do {
      let saved = try await store.save(changed, replacing: original)
      if saved.id != original.id {
        updatePlan(undoable: false) { $0.relink(from: original.id, to: saved.id) }
        reminders.removeAll { $0.id == original.id }
      }
      undo = .reminder(before: original.with(id: saved.id), after: saved)
      publish(saved)
    } catch { self.error = error.localizedDescription }
  }

  public func createShelf(named title: String) async -> ReminderList? {
    do {
      let list = try await store.createList(named: title)
      lists.append(list)
      lists.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
      recompute()
      return list
    } catch {
      self.error = error.localizedDescription
      return nil
    }
  }

  public func saveEdit(_ value: ReminderItem, original: ReminderItem) async -> Bool {
    guard canWrite(original.id) else { return false }
    pending.insert(original.id)
    defer { pending.remove(original.id) }
    do {
      let saved = try await store.save(value, replacing: original)
      publish(saved)
      return true
    } catch {
      self.error = error.localizedDescription
      return false
    }
  }

  public func delete(_ original: ReminderItem) async -> Bool {
    guard canWrite(original.id) else { return false }
    pending.insert(original.id)
    defer { pending.remove(original.id) }
    do {
      try await store.delete(original)
      refreshID = UUID()
      reminders.removeAll { $0.id == original.id }
      updatePlan(undoable: false) { $0.release(original.id) }
      recompute()
      return true
    } catch {
      self.error = error.localizedDescription
      return false
    }
  }

  /// Confirmed writes are authoritative even if the next fetch fails or is stale.
  private func publish(_ saved: ReminderItem) {
    refreshID = UUID()
    reminders.removeAll { $0.id == saved.id }
    reminders.append(saved)
    recompute()
  }
}

/// One undoable step. Undo stays available until the next undoable action.
public enum UndoAction: Equatable, Sendable {
  case plan(before: DayPlan)
  case reminder(before: ReminderItem, after: ReminderItem)

  public var label: String {
    switch self {
    case .plan: "Undo"
    case .reminder(let before, let after):
      before.listID != after.listID
        ? "Undo move" : (after.isCompleted ? "Undo finish" : "Undo reopen")
    }
  }
}

extension ReminderItem {
  func with(id: String) -> ReminderItem {
    var copy = self
    copy.id = id
    return copy
  }
}
