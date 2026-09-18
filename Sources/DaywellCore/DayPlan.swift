import Foundation

public struct Commitment: Codable, Equatable, Sendable {
  public var id: UUID
  public var reminderID: String
  public var day: String
  public var order: Int
  public var updatedAt: Date
  public var externalID: String?
  public var listID: String?

  public init(
    id: UUID = UUID(), reminderID: String, day: String, order: Int,
    updatedAt: Date, externalID: String? = nil, listID: String? = nil
  ) {
    self.id = id
    self.reminderID = reminderID
    self.day = day
    self.order = order
    self.updatedAt = updatedAt
    self.externalID = externalID
    self.listID = listID
  }
}

public struct DayProjection: Equatable, Sendable {
  public var today: [ReminderItem]
  public var due: [ReminderItem]
  public var previous: [ReminderItem]
  public var done: [ReminderItem]
  public var unresolved: [Commitment]
  public var pinnedReminderID: String?

  public init(
    today: [ReminderItem] = [], due: [ReminderItem] = [],
    previous: [ReminderItem] = [], done: [ReminderItem] = [],
    unresolved: [Commitment] = [], pinnedReminderID: String? = nil
  ) {
    self.today = today
    self.due = due
    self.previous = previous
    self.done = done
    self.unresolved = unresolved
    self.pinnedReminderID = pinnedReminderID
  }
}

public struct DayPlan: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = 1
  public var schemaVersion: Int
  public var commitments: [Commitment]
  public var pinnedCommitmentID: UUID?

  public init() {
    schemaVersion = Self.currentSchemaVersion
    commitments = []
    pinnedCommitmentID = nil
  }

  public mutating func choose(_ reminderID: String, on date: Date, calendar: Calendar) {
    let day = Self.dayKey(for: date, calendar: calendar)
    if let index = commitments.firstIndex(where: { $0.reminderID == reminderID }) {
      guard commitments[index].day != day else { return }
      commitments[index].day = day
      commitments[index].order = nextOrder(on: day)
      commitments[index].updatedAt = date
      return
    }
    commitments.append(
      Commitment(
        reminderID: reminderID, day: day,
        order: nextOrder(on: day), updatedAt: date))
  }

  public mutating func release(_ reminderID: String) {
    let removedIDs = Set(commitments.filter { $0.reminderID == reminderID }.map(\.id))
    commitments.removeAll { $0.reminderID == reminderID }
    if let pinnedCommitmentID, removedIDs.contains(pinnedCommitmentID) {
      self.pinnedCommitmentID = nil
    }
  }

  public mutating func pin(_ reminderID: String, on date: Date, calendar: Calendar) {
    choose(reminderID, on: date, calendar: calendar)
    pinnedCommitmentID = commitments.first { $0.reminderID == reminderID }?.id
  }

  public mutating func unpin() {
    pinnedCommitmentID = nil
  }

  public mutating func keepPrevious(reminderIDs: [String], on date: Date, calendar: Calendar) {
    let selected = Set(reminderIDs)
    let today = Self.dayKey(for: date, calendar: calendar)
    for index in commitments.indices
    where selected.contains(commitments[index].reminderID)
      && commitments[index].day < today
    {
      commitments[index].day = today
      commitments[index].order = nextOrder(on: today, excluding: index)
      commitments[index].updatedAt = date
    }
  }

  public func projection(
    reminders: [ReminderItem], now: Date,
    calendar: Calendar
  ) -> DayProjection {
    let todayKey = Self.dayKey(for: now, calendar: calendar)
    let byID = Dictionary(reminders.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let active = commitments.filter { $0.day == todayKey }.sorted(by: commitmentOrder)
    let prior = commitments.filter { $0.day < todayKey }.sorted(by: commitmentOrder)
    let visibleToday = active.compactMap { byID[$0.reminderID] }.filter { !$0.isCompleted }
    let todayIDs = Set(active.map(\.reminderID))
    let previous = prior.compactMap { byID[$0.reminderID] }.filter { !$0.isCompleted }
    let unresolved = commitments.filter { byID[$0.reminderID] == nil }
    let due = reminders.filter { reminder in
      guard !reminder.isCompleted, !todayIDs.contains(reminder.id),
        let dueDate = reminder.dueDate
      else { return false }
      return Self.dayKey(for: dueDate, calendar: calendar) <= todayKey
    }
    let done = reminders.filter { reminder in
      guard reminder.isCompleted, let completionDate = reminder.completionDate else { return false }
      return Self.dayKey(for: completionDate, calendar: calendar) == todayKey
    }
    let pinnedReminderID: String? = pinnedCommitmentID.flatMap { pinnedID in
      guard let id = active.first(where: { $0.id == pinnedID })?.reminderID,
        visibleToday.contains(where: { $0.id == id })
      else { return nil }
      return id
    }
    return DayProjection(
      today: visibleToday, due: due, previous: previous, done: done,
      unresolved: unresolved, pinnedReminderID: pinnedReminderID)
  }

  private func commitmentOrder(_ lhs: Commitment, _ rhs: Commitment) -> Bool {
    if lhs.id == rhs.id { return false }
    if lhs.id == pinnedCommitmentID { return true }
    if rhs.id == pinnedCommitmentID { return false }
    if lhs.day != rhs.day { return lhs.day < rhs.day }
    return lhs.order < rhs.order
  }

  private func nextOrder(on day: String, excluding excludedIndex: Int? = nil) -> Int {
    commitments.indices
      .filter { $0 != excludedIndex && commitments[$0].day == day }
      .map { commitments[$0].order }
      .max().map { $0 + 1 } ?? 0
  }

  private static func dayKey(for date: Date, calendar: Calendar) -> String {
    let components = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", components.year!, components.month!, components.day!)
  }
}
