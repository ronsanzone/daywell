import DaywellCore
@preconcurrency import EventKit
import Foundation

@MainActor public final class EventKitReminderStore: ReminderStore {
  private let eventStore = EKEventStore()
  public init() {}
  public var authorized: Bool { EKEventStore.authorizationStatus(for: .reminder) == .fullAccess }

  public func requestAccess() async throws -> Bool {
    try await eventStore.requestFullAccessToReminders()
  }

  public func fetch(completedSince: Date) async throws -> ReminderSnapshot {
    guard authorized else { throw ReminderError.denied }
    let calendars = eventStore.calendars(for: .reminder)
    // Two narrow queries instead of every reminder ever completed: open work, and
    // today's completions (which are today's pile). EventKit runs them concurrently.
    let predicates = [
      eventStore.predicateForIncompleteReminders(
        withDueDateStarting: nil, ending: nil, calendars: calendars),
      eventStore.predicateForCompletedReminders(
        withCompletionDateStarting: completedSince, ending: nil, calendars: calendars),
    ]
    let items = try await fetchAll(predicates)
    return ReminderSnapshot(
      reminders: items,
      lists: calendars.map(Self.list).sorted {
        $0.title.localizedStandardCompare($1.title) == .orderedAscending
      },
      defaultListID: eventStore.defaultCalendarForNewReminders()?.calendarIdentifier)
  }

  private func fetchAll(_ predicates: [NSPredicate]) async throws -> [ReminderItem] {
    try await withCheckedThrowingContinuation { continuation in
      let collector = FetchCollector(expected: predicates.count, continuation: continuation)
      for predicate in predicates {
        // EventKit calls back off the main thread; values are mapped there.
        eventStore.fetchReminders(matching: predicate) { reminders in
          collector.add(reminders.map { $0.map(Self.snapshot) })
        }
      }
    }
  }

  public func save(_ item: ReminderItem, replacing original: ReminderItem?) async throws
    -> ReminderItem
  {
    guard authorized else { throw ReminderError.denied }
    guard !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw ReminderError.emptyTitle
    }
    guard let list = eventStore.calendar(withIdentifier: item.listID),
      list.allowsContentModifications
    else { throw ReminderError.readOnly }
    let reminder: EKReminder
    if let original {
      reminder = try existing(original)
    } else {
      reminder = EKReminder(eventStore: eventStore)
    }
    // Only mutate edited properties; never recreate existing reminders or
    // replace their recurrence, alarms, URLs, or unsupported Apple metadata.
    if original == nil || original?.title != item.title { reminder.title = item.title }
    if original == nil || original?.notes != item.notes { reminder.notes = item.notes }
    if original == nil || original?.listID != item.listID { reminder.calendar = list }
    if original == nil || original?.dueDate != item.dueDate
      || original?.hasDueTime != item.hasDueTime
    {
      if let due = item.dueDate {
        var fields: Set<Calendar.Component> = [.year, .month, .day]
        if item.hasDueTime { fields.formUnion([.hour, .minute]) }
        var components = Calendar.current.dateComponents(fields, from: due)
        if item.hasDueTime { components.timeZone = Calendar.current.timeZone }
        reminder.dueDateComponents = components
      } else {
        reminder.dueDateComponents = nil
      }
    }
    if original == nil || original?.isCompleted != item.isCompleted {
      reminder.isCompleted = item.isCompleted
    }
    try eventStore.save(reminder, commit: true)
    return Self.snapshot(reminder)
  }

  public func delete(_ original: ReminderItem) async throws {
    guard authorized else { throw ReminderError.denied }
    let reminder = try existing(original)
    try eventStore.remove(reminder, commit: true)
  }

  public func createList(named title: String) async throws -> ReminderList {
    guard authorized else { throw ReminderError.denied }
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw ReminderError.emptyTitle }
    guard let source = eventStore.defaultCalendarForNewReminders()?.source else {
      throw ReminderError.noListSource
    }
    let calendar = EKCalendar(for: .reminder, eventStore: eventStore)
    calendar.title = trimmed
    calendar.source = source
    try eventStore.saveCalendar(calendar, commit: true)
    return Self.list(calendar)
  }

  private func existing(_ original: ReminderItem) throws -> EKReminder {
    guard let reminder = eventStore.calendarItem(withIdentifier: original.id) as? EKReminder else {
      throw ReminderError.missing
    }
    _ = reminder.refresh()
    guard reminder.calendar.allowsContentModifications else { throw ReminderError.readOnly }
    guard Self.snapshot(reminder) == original else { throw ReminderError.changed }
    return reminder
  }

  nonisolated private static func list(_ calendar: EKCalendar) -> ReminderList {
    ReminderList(
      id: calendar.calendarIdentifier, title: calendar.title,
      isWritable: calendar.allowsContentModifications)
  }

  nonisolated static func snapshot(_ reminder: EKReminder) -> ReminderItem {
    var calendar = Calendar.current
    let components = reminder.dueDateComponents
    if let zone = components?.timeZone { calendar.timeZone = zone }
    return ReminderItem(
      id: reminder.calendarItemIdentifier, title: reminder.title ?? "Untitled reminder",
      notes: reminder.notes ?? "", listID: reminder.calendar.calendarIdentifier,
      listName: reminder.calendar.title, dueDate: components.flatMap { calendar.date(from: $0) },
      hasDueTime: components?.hour != nil, isCompleted: reminder.isCompleted,
      completionDate: reminder.completionDate,
      isWritable: reminder.calendar.allowsContentModifications,
      externalID: reminder.calendarItemExternalIdentifier)
  }
}

/// Joins concurrent EventKit fetch callbacks into one result.
private final class FetchCollector: @unchecked Sendable {
  private let lock = NSLock()
  private var remaining: Int
  private var items: [ReminderItem] = []
  private var failed = false
  private let continuation: CheckedContinuation<[ReminderItem], Error>

  init(expected: Int, continuation: CheckedContinuation<[ReminderItem], Error>) {
    remaining = expected
    self.continuation = continuation
  }

  func add(_ batch: [ReminderItem]?) {
    lock.lock()
    defer { lock.unlock() }
    guard !failed else { return }
    guard let batch else {
      failed = true
      continuation.resume(throwing: ReminderError.denied)
      return
    }
    items += batch
    remaining -= 1
    if remaining == 0 { continuation.resume(returning: items) }
  }
}
