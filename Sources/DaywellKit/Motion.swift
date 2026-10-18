import DaywellCore
import Observation
import SwiftUI

/// Keeps a finished row on screen just long enough for its finish motion to play,
/// even though Apple Reminders usually confirms faster than the motion lasts.
@MainActor @Observable public final class MotionState {
  public struct Lingering: Equatable {
    public let item: ReminderItem
    public let index: Int
    public var confirmed: Bool
  }
  /// Rows mid-finish, keyed by reminder ID, with the position they occupied.
  public private(set) var lingering: [String: Lingering] = [:]
  /// Pile tokens that just landed; drives the drop animation.
  public private(set) var landed: Set<String> = []
  /// Increments once per finish; themes that cycle inks use it.
  public private(set) var finishCount = 0
  public private(set) var dayClearPulse = 0
  /// How long a finishing row stays visible. Matches the ring and strike motion.
  public static let finishHold: Duration = .milliseconds(420)
  @ObservationIgnored private let model: DayModel

  public init(model: DayModel) {
    self.model = model
    model.feedback.listen { [weak self] event in self?.handle(event) }
  }

  public func isFinishing(_ id: String) -> Bool { lingering[id] != nil }

  /// My Day as displayed: confirmed state plus rows still finishing.
  public var displayedMyDay: [ReminderItem] {
    var rows = model.today.myDay
    for entry in lingering.values.sorted(by: { $0.index < $1.index })
    where !rows.contains(where: { $0.id == entry.item.id }) {
      rows.insert(entry.item, at: min(entry.index, rows.count))
    }
    return rows
  }

  private func handle(_ event: FeedbackEvent) {
    guard let item = event.reminder else {
      if case .dayClear = event.kind { dayClearPulse += 1 }
      return
    }
    switch event.kind {
    case .finishing:
      let index = model.today.myDay.firstIndex { $0.id == item.id } ?? 0
      lingering[item.id] = Lingering(item: item, index: index, confirmed: false)
      Task { [weak self] in
        try? await Task.sleep(for: Self.finishHold)
        self?.release(item.id)
      }
    case .finished:
      finishCount += 1
      landed.insert(item.id)
      if lingering[item.id] != nil { lingering[item.id]?.confirmed = true }
      Task { [weak self] in
        try? await Task.sleep(for: .milliseconds(700))
        self?.landed.remove(item.id)
      }
    case .finishFailed:
      withAnimation(.easeOut(duration: 0.2)) { _ = lingering.removeValue(forKey: item.id) }
    default: break
    }
  }

  private func release(_ id: String) {
    // Unconfirmed rows stay until Apple Reminders answers either way.
    guard let entry = lingering[id] else { return }
    if entry.confirmed {
      withAnimation(.easeInOut(duration: 0.22)) { _ = lingering.removeValue(forKey: id) }
    } else {
      Task { [weak self] in
        try? await Task.sleep(for: .milliseconds(120))
        self?.release(id)
      }
    }
  }
}
