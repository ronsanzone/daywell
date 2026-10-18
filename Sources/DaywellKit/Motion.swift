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
    public var leaving = false
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
  /// The finished row is fading out in place before the list closes the gap.
  public func isLeaving(_ id: String) -> Bool { lingering[id]?.leaving == true }

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
    case .finishFailed, .reopened:
      withAnimation(.easeOut(duration: 0.2)) { _ = lingering.removeValue(forKey: item.id) }
    default: break
    }
  }

  private func release(_ id: String) {
    // Unconfirmed rows stay until Apple Reminders answers either way.
    guard let entry = lingering[id] else { return }
    if entry.confirmed {
      // Fade the struck row out where it is, then let the rows below close the gap,
      // so a leaving row never overlaps its neighbour.
      // A timer, not an animation completion: completions don't fire while the
      // window is hidden, and a hidden panel must never keep a finished row.
      // The row fades and collapses in place (CollapseWhenLeaving), then is removed
      // without a transition, so no removed view ever lingers over its neighbours.
      withAnimation(.easeInOut(duration: 0.22)) { lingering[id]?.leaving = true }
      Task { [weak self] in
        try? await Task.sleep(for: .milliseconds(240))
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { _ = self?.lingering.removeValue(forKey: id) }
      }
    } else {
      Task { [weak self] in
        try? await Task.sleep(for: .milliseconds(120))
        self?.release(id)
      }
    }
  }
}

/// Fades a finished row out and closes its gap by animating its height to zero.
/// SwiftUI animates the change from the row's natural height, so no measuring is needed.
struct CollapseWhenLeaving: ViewModifier {
  let leaving: Bool

  func body(content: Content) -> some View {
    content
      .frame(height: leaving ? 0 : nil, alignment: .top)
      .opacity(leaving ? 0 : 1)
      .clipped()
  }
}

extension View {
  func collapses(when leaving: Bool) -> some View {
    modifier(CollapseWhenLeaving(leaving: leaving))
  }
}
