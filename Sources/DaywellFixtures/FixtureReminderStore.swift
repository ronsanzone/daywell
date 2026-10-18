import DaywellCore
import DaywellKit
import Foundation

/// An in-memory Apple Reminders stand-in for tests, demos, snapshots and benchmarks.
/// Never touches EventKit. Mirrors the store contract: narrow fetches, optimistic
/// concurrency on saves, list moves and list creation.
@MainActor public final class FixtureReminderStore: ReminderStore {
  public var authorized = true
  public var items: [ReminderItem]
  public var lists: [ReminderList]
  public var defaultListID: String?
  /// Simulated EventKit latency per call.
  public var latency: Duration = .zero
  /// Fail the next save with this error.
  public var failNextSave: ReminderError?
  /// Gives moved reminders a new identifier, as some EventKit sources might.
  public var moveChangesIdentifier = false
  /// Repeating reminders: completing one advances its due date by a day and
  /// records a separate completed occurrence, as EventKit does.
  public var repeatingIDs: Set<String> = []
  public private(set) var fetchCount = 0
  public private(set) var fetchedItemCount = 0

  public init(items: [ReminderItem], lists: [ReminderList], defaultListID: String? = nil) {
    self.items = items
    self.lists = lists
    self.defaultListID = defaultListID ?? lists.first?.id
  }

  public func requestAccess() async throws -> Bool { authorized }

  public func fetch(completedSince: Date) async throws -> ReminderSnapshot {
    guard authorized else { throw ReminderError.denied }
    if latency > .zero { try await Task.sleep(for: latency) }
    fetchCount += 1
    let visible = items.filter {
      !$0.isCompleted || ($0.completionDate.map { $0 >= completedSince } ?? false)
    }
    fetchedItemCount = visible.count
    return ReminderSnapshot(reminders: visible, lists: lists, defaultListID: defaultListID)
  }

  public func save(_ item: ReminderItem, replacing original: ReminderItem?) async throws
    -> ReminderItem
  {
    if latency > .zero { try await Task.sleep(for: latency) }
    if let failure = failNextSave {
      failNextSave = nil
      throw failure
    }
    guard !item.title.trimmingCharacters(in: .whitespaces).isEmpty else {
      throw ReminderError.emptyTitle
    }
    guard lists.contains(where: { $0.id == item.listID && $0.isWritable }) else {
      throw ReminderError.readOnly
    }
    var result = item
    if let original {
      guard items.first(where: { $0.id == original.id }) == original else {
        throw ReminderError.changed
      }
      if repeatingIDs.contains(original.id), item.isCompleted, !original.isCompleted {
        var occurrence = original
        occurrence.id = UUID().uuidString
        occurrence.isCompleted = true
        occurrence.completionDate = item.completionDate ?? Date()
        items.append(occurrence)
        var next = original
        next.dueDate = original.dueDate.map { $0.addingTimeInterval(86_400) }
        replace(original.id, with: next)
        return next
      }
      if moveChangesIdentifier, original.listID != item.listID {
        items.removeAll { $0.id == original.id }
        result.id = UUID().uuidString
        items.append(result)
        return result
      }
      if result.isCompleted, result.completionDate == nil { result.completionDate = Date() }
      if !result.isCompleted { result.completionDate = nil }
      replace(original.id, with: result)
      return result
    }
    result.id = UUID().uuidString
    result.externalID = UUID().uuidString
    items.append(result)
    return result
  }

  private func replace(_ id: String, with item: ReminderItem) {
    if let index = items.firstIndex(where: { $0.id == id }) {
      items[index] = item
    } else {
      items.append(item)
    }
  }

  public func delete(_ original: ReminderItem) async throws {
    guard items.first(where: { $0.id == original.id }) == original else {
      throw ReminderError.changed
    }
    items.removeAll { $0.id == original.id }
  }

  public func createList(named title: String) async throws -> ReminderList {
    let list = ReminderList(id: "list-\(UUID().uuidString.prefix(8))", title: title)
    lists.append(list)
    return list
  }
}

/// Ron's own shape of work, used by the demo, snapshots and checks.
public enum Fixtures {
  @MainActor public static func demo(now: Date = Date(), history: Int = 0) -> (
    FixtureReminderStore, DayPlan
  ) {
    let calendar = Calendar.current
    // Fixture dates stay well inside the calendar's supported range.
    // swiftlint:disable force_unwrapping
    let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
    let friday = calendar.nextDate(
      after: now, matching: DateComponents(weekday: 6), matchingPolicy: .nextTime)!
    let fivePM = calendar.date(bySettingHour: 17, minute: 0, second: 0, of: now)!
    // swiftlint:enable force_unwrapping
    let lists = [
      ReminderList(id: "devex", title: "DevEx"), ReminderList(id: "inbox", title: "Inbox"),
      ReminderList(id: "work", title: "Work"),
    ]
    func item(
      _ id: String, _ title: String, _ list: String, due: Date? = nil, time: Bool = false,
      done: Date? = nil
    ) -> ReminderItem {
      ReminderItem(
        id: id, title: title, listID: list,
        listName: lists.first { $0.id == list }?.title ?? "", dueDate: due, hasDueTime: time,
        isCompleted: done != nil, completionDate: done, externalID: "ext-\(id)")
    }
    var items = [
      item("mitigation", "Create mitigation tickets for the write stalls", "work"),
      item("slo", "Look into SLO dashboard", "work", due: fivePM, time: true),
      item("qual", "Polish the program doc for qual", "work"),
      item("prototype", "Progress on prototype", "work"),
      item("design", "Progress on design doc", "work"),
      item("ticket", "Make ticket for the public API collection logic", "work"),
      item("pi", "Pi auto", "devex"),
      item("opencode", "Opencode2 auto", "devex"),
      item("session", "Open session?", "devex"),
      item("workstation", "Remote workstation", "devex"),
      item("plannotator", "Plannotator herdr native setup", "devex"),
      item("parking", "Renew parking permit", "inbox", due: friday),
      item("secprs", "Close out in-progress security PRs", "work", done: now.addingTimeInterval(-7200)),
      item("qa", "Finish prep for QA run", "work", done: now.addingTimeInterval(-3600)),
    ]
    for index in 0..<history {
      // Old completed history the narrow fetch never loads.
      items.append(
        item(
          "old-\(index)", "Archived task \(index)", ["work", "devex", "inbox"][index % 3],
          done: now.addingTimeInterval(-Double(86_400 * (1 + index % 900)))))
    }
    let store = FixtureReminderStore(items: items, lists: lists, defaultListID: "inbox")
    var plan = DayPlan()
    for id in ["mitigation", "slo", "qual", "secprs", "qa"] {
      plan.choose(id, on: now, calendar: calendar)
    }
    plan.pin("mitigation", on: now, calendar: calendar)
    plan.choose("prototype", on: yesterday, calendar: calendar)
    plan.markMorningPull(on: now, calendar: calendar)
    return (store, plan)
  }
}
