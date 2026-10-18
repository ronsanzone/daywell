import DaywellCore
import Foundation
import Observation

/// Something the user did that deserves a moment: motion, a sound, a pile token.
/// Refreshes and external Reminders edits never produce events.
public struct FeedbackEvent: Equatable, Identifiable, Sendable {
  public enum Kind: Equatable, Sendable {
    /// Input accepted; motion may start before Apple Reminders confirms.
    case finishing
    /// Apple Reminders confirmed the completion.
    case finished
    /// Apple Reminders rejected the completion; reverse any motion.
    case finishFailed
    case reopened
    case captured(listTitle: String)
    case pulled
    case released(shelf: String)
    case dayClear(count: Int)
  }
  public let id: Int
  public let kind: Kind
  public let reminder: ReminderItem?
}

@MainActor @Observable public final class FeedbackCenter {
  /// The most recent event; views react to its `id` changing.
  public private(set) var latest: FeedbackEvent?
  @ObservationIgnored private var nextID = 0
  @ObservationIgnored private var listeners: [(FeedbackEvent) -> Void] = []

  public init() {}

  /// Non-view consumers (sound, the menu-bar ticker) subscribe here.
  public func listen(_ listener: @escaping (FeedbackEvent) -> Void) {
    listeners.append(listener)
  }

  func emit(_ kind: FeedbackEvent.Kind, _ reminder: ReminderItem? = nil) {
    nextID += 1
    let event = FeedbackEvent(id: nextID, kind: kind, reminder: reminder)
    latest = event
    for listener in listeners { listener(event) }
  }
}
