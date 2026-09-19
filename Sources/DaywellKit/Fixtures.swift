import DaywellCore
import Foundation

/// Explicit opt-in demo data. This store never creates an EKEventStore or touches personal reminders.
@MainActor public final class DemoReminderStore: ReminderStore {
  public var authorized = true
  public var items: [ReminderItem]
  public init(now: Date = Date()) {
    // Demo dates are within the calendar's supported range.
    // swiftlint:disable:next force_unwrapping
    let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
    items = [
      ReminderItem(
        id: "dentist", title: "Call dentist", notes: "Ask about a cleaning", listID: "personal",
        listName: "Personal"),
      ReminderItem(id: "expenses", title: "Submit expenses", listID: "work", listName: "Work"),
      ReminderItem(
        id: "prescription", title: "Pick up prescription", listID: "personal", listName: "Personal"),
      ReminderItem(
        id: "invoice", title: "Send invoice", listID: "work", listName: "Work", dueDate: yesterday),
      ReminderItem(
        id: "parking", title: "Renew parking", listID: "personal", listName: "Personal",
        dueDate: now),
      ReminderItem(
        id: "plants", title: "Water the plants", listID: "personal", listName: "Personal"),
      ReminderItem(id: "read", title: "Read the proposal", listID: "work", listName: "Work"),
      ReminderItem(
        id: "checkup", title: "Book annual checkup", listID: "personal", listName: "Personal",
        isCompleted: true, completionDate: now),
      ReminderItem(
        id: "bill", title: "Pay electricity bill", listID: "personal", listName: "Personal",
        isCompleted: true, completionDate: now),
    ]
  }
  public func requestAccess() async throws -> Bool { authorized }
  public func fetch() async throws -> ReminderSnapshot {
    ReminderSnapshot(
      reminders: items,
      lists: [
        ReminderList(id: "personal", title: "Personal"), ReminderList(id: "work", title: "Work"),
      ], defaultListID: "personal")
  }
  public func save(_ item: ReminderItem, replacing original: ReminderItem?) async throws
    -> ReminderItem
  {
    if let original, items.first(where: { $0.id == original.id }) != original {
      throw ReminderError.changed
    }
    var result = item
    if original == nil { result.id = UUID().uuidString }
    items.removeAll { $0.id == result.id }
    items.append(result)
    return result
  }
  public func delete(_ original: ReminderItem) async throws {
    guard items.first(where: { $0.id == original.id }) == original else {
      throw ReminderError.changed
    }
    items.removeAll { $0.id == original.id }
  }
  public static func plan(now: Date) -> DayPlan {
    var plan = DayPlan()
    for id in ["dentist", "expenses", "prescription"] {
      plan.choose(id, on: now, calendar: .current)
    }
    plan.pin("dentist", on: now, calendar: .current)
    // Demo dates are within the calendar's supported range.
    // swiftlint:disable:next force_unwrapping
    let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
    for id in ["plants", "read"] { plan.choose(id, on: yesterday, calendar: .current) }
    return plan
  }
}
