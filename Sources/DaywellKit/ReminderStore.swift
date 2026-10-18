import DaywellCore
import Foundation

public struct ReminderSnapshot: Sendable {
  public var reminders: [ReminderItem]
  public var lists: [ReminderList]
  public var defaultListID: String?
  public init(reminders: [ReminderItem], lists: [ReminderList], defaultListID: String?) {
    self.reminders = reminders
    self.lists = lists
    self.defaultListID = defaultListID
  }
}

/// The one seam between Daywell and Apple Reminders. Tests and fixtures implement it;
/// production uses `EventKitReminderStore`.
@MainActor public protocol ReminderStore: AnyObject {
  var authorized: Bool { get }
  func requestAccess() async throws -> Bool
  /// Open reminders in every list, plus reminders completed at or after `completedSince`.
  /// Older completed history is never fetched.
  func fetch(completedSince: Date) async throws -> ReminderSnapshot
  /// Saves only the fields that differ from `original`. Changing `listID` moves the reminder.
  func save(_ item: ReminderItem, replacing original: ReminderItem?) async throws -> ReminderItem
  func delete(_ original: ReminderItem) async throws
  func createList(named title: String) async throws -> ReminderList
}

public enum ReminderError: LocalizedError, Equatable {
  case denied, readOnly, missing, changed, emptyTitle, noListSource
  public var errorDescription: String? {
    switch self {
    case .denied: "Reminders access is unavailable. Allow access in System Settings, then retry."
    case .readOnly: "Choose a writable Reminders list."
    case .missing: "This reminder is no longer available. Refresh to see the latest reminders."
    case .changed: "This reminder changed elsewhere. Refresh and review it before saving again."
    case .emptyTitle: "Give the reminder a title before saving."
    case .noListSource: "Apple Reminders has no account that can hold a new list."
    }
  }
}
