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

/// Companion-only choices: which reminders are today's commitments, their order,
/// and the single pin. Apple Reminders stays authoritative for the reminders.
public struct DayPlan: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = 1
  public var schemaVersion: Int
  public var commitments: [Commitment]
  public var pinnedCommitmentID: UUID?
  /// The day key on which the morning pull was last shown or dismissed.
  /// Optional and additive, so version 1 files decode unchanged.
  public var morningPullDay: String?

  public init() {
    schemaVersion = Self.currentSchemaVersion
    commitments = []
    pinnedCommitmentID = nil
    morningPullDay = nil
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

  /// Pinning makes a task "the one in view". It chooses the task for today if needed.
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

  /// Moves a commitment up (negative) or down (positive) among today's commitments.
  public mutating func reorder(
    _ reminderID: String, by offset: Int, among orderedIDs: [String], on date: Date
  ) {
    guard let from = orderedIDs.firstIndex(of: reminderID), offset != 0 else { return }
    let to = min(max(from + offset, 0), orderedIDs.count - 1)
    guard to != from else { return }
    var ids = orderedIDs
    ids.remove(at: from)
    ids.insert(reminderID, at: to)
    for (order, id) in ids.enumerated() {
      if let index = commitments.firstIndex(where: { $0.reminderID == id }) {
        commitments[index].order = order
        commitments[index].updatedAt = date
      }
    }
  }

  /// Re-links a commitment whose Apple identifier changed, without guessing by title.
  public mutating func relink(from oldID: String, to newID: String) {
    guard oldID != newID, !commitments.contains(where: { $0.reminderID == newID }) else { return }
    for index in commitments.indices where commitments[index].reminderID == oldID {
      commitments[index].reminderID = newID
    }
  }

  public mutating func markMorningPull(on date: Date, calendar: Calendar) {
    morningPullDay = Self.dayKey(for: date, calendar: calendar)
  }

  func nextOrder(on day: String, excluding excludedIndex: Int? = nil) -> Int {
    commitments.indices
      .filter { $0 != excludedIndex && commitments[$0].day == day }
      .map { commitments[$0].order }
      .max().map { $0 + 1 } ?? 0
  }

  public static func dayKey(for date: Date, calendar: Calendar) -> String {
    let components = calendar.dateComponents([.year, .month, .day], from: date)
    // All three components were explicitly requested from a Date.
    // swiftlint:disable:next force_unwrapping
    return String(format: "%04d-%02d-%02d", components.year!, components.month!, components.day!)
  }
}
