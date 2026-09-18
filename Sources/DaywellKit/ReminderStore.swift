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

@MainActor public protocol ReminderStore: AnyObject {
  var authorized: Bool { get }
  func requestAccess() async throws -> Bool
  func fetch() async throws -> ReminderSnapshot
  func save(_ item: ReminderItem, replacing original: ReminderItem?) async throws -> ReminderItem
  func delete(_ original: ReminderItem) async throws
}

public enum ReminderError: LocalizedError {
  case denied, readOnly, missing, changed, emptyTitle
  public var errorDescription: String? {
    switch self {
    case .denied: "Reminders access is unavailable. Allow access in System Settings, then retry."
    case .readOnly: "Choose a writable Reminders list."
    case .missing: "This reminder is no longer available. Refresh to see the latest reminders."
    case .changed: "This reminder changed elsewhere. Refresh and review it before saving again."
    case .emptyTitle: "Give the reminder a title before saving."
    }
  }
}
