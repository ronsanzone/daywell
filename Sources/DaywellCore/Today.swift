import Foundation

/// A Reminders list shown as a shelf: open work that isn't on today's desk.
public struct Shelf: Identifiable, Equatable, Sendable {
  public var list: ReminderList
  /// Open reminders in this list, excluding those already chosen for today.
  public var items: [ReminderItem]
  public var id: String { list.id }

  public init(list: ReminderList, items: [ReminderItem]) {
    self.list = list
    self.items = items
  }
}

/// Everything every surface (menu-bar ticker, capture bar, panel) shows about today.
/// Derived only; computed once per change of reminders, plan, or day.
public struct Today: Equatable, Sendable {
  public var dayKey: String
  /// Today's open commitments: the pin first, then the order the user chose.
  public var myDay: [ReminderItem]
  public var pinnedID: String?
  /// Reminders completed today in any accessible list, oldest completion first.
  public var pile: [ReminderItem]
  /// How many of today's commitments are finished.
  public var finishedCommitments: Int
  /// Open commitments left over from earlier days.
  public var leftovers: [ReminderItem]
  /// Open reminders due today or earlier that aren't in My Day.
  public var due: [ReminderItem]
  public var shelves: [Shelf]
  public var unresolved: [Commitment]
  public var wantsMorningPull: Bool

  /// The task the menu bar shows.
  public var tickerTask: ReminderItem? { myDay.first }
  /// Everything chosen for today is finished.
  public var isDayClear: Bool { myDay.isEmpty && finishedCommitments > 0 }

  public init(
    dayKey: String = "", myDay: [ReminderItem] = [], pinnedID: String? = nil,
    pile: [ReminderItem] = [], finishedCommitments: Int = 0, leftovers: [ReminderItem] = [],
    due: [ReminderItem] = [], shelves: [Shelf] = [], unresolved: [Commitment] = [],
    wantsMorningPull: Bool = false
  ) {
    self.dayKey = dayKey
    self.myDay = myDay
    self.pinnedID = pinnedID
    self.pile = pile
    self.finishedCommitments = finishedCommitments
    self.leftovers = leftovers
    self.due = due
    self.shelves = shelves
    self.unresolved = unresolved
    self.wantsMorningPull = wantsMorningPull
  }

  public static func build(
    plan: DayPlan, reminders: [ReminderItem], lists: [ReminderList],
    now: Date, calendar: Calendar
  ) -> Today {
    let todayKey = DayPlan.dayKey(for: now, calendar: calendar)
    var byID: [String: ReminderItem] = [:]
    byID.reserveCapacity(reminders.count)
    for reminder in reminders where byID[reminder.id] == nil { byID[reminder.id] = reminder }

    let order: (Commitment, Commitment) -> Bool = { lhs, rhs in
      if lhs.id == plan.pinnedCommitmentID { return rhs.id != plan.pinnedCommitmentID }
      if rhs.id == plan.pinnedCommitmentID { return false }
      if lhs.day != rhs.day { return lhs.day < rhs.day }
      return lhs.order < rhs.order
    }
    let active = plan.commitments.filter { $0.day == todayKey }.sorted(by: order)
    let prior = plan.commitments.filter { $0.day < todayKey }.sorted(by: order)

    var myDay: [ReminderItem] = []
    var finished = 0
    for commitment in active {
      guard let item = byID[commitment.reminderID] else { continue }
      if item.isCompleted { finished += 1 } else { myDay.append(item) }
    }
    let chosen = Set(active.map(\.reminderID))
    let leftovers = prior.compactMap { byID[$0.reminderID] }.filter { !$0.isCompleted }
    let unresolved = plan.commitments.filter { byID[$0.reminderID] == nil }

    var pile: [ReminderItem] = []
    var due: [ReminderItem] = []
    var open: [String: [ReminderItem]] = [:]
    for reminder in reminders {
      if reminder.isCompleted {
        if let completed = reminder.completionDate,
          DayPlan.dayKey(for: completed, calendar: calendar) == todayKey
        {
          pile.append(reminder)
        }
        continue
      }
      guard !chosen.contains(reminder.id) else { continue }
      if let dueDate = reminder.dueDate,
        DayPlan.dayKey(for: dueDate, calendar: calendar) <= todayKey
      {
        due.append(reminder)
      }
      open[reminder.listID, default: []].append(reminder)
    }
    pile.sort { ($0.completionDate ?? .distantPast) < ($1.completionDate ?? .distantPast) }
    due.sort { ($0.dueDate ?? .distantPast) < ($1.dueDate ?? .distantPast) }
    let shelves = lists.map { list in
      Shelf(
        list: list,
        items: (open[list.id] ?? []).sorted(by: Self.shelfOrder))
    }

    let pinnedID = plan.pinnedCommitmentID.flatMap { pinned in
      active.first { $0.id == pinned }.flatMap { commitment in
        myDay.contains { $0.id == commitment.reminderID } ? commitment.reminderID : nil
      }
    }
    let hasSomethingToPull = !leftovers.isEmpty || shelves.contains { !$0.items.isEmpty }
    let wantsMorningPull =
      plan.morningPullDay != todayKey && hasSomethingToPull
      && (active.isEmpty || !leftovers.isEmpty)

    return Today(
      dayKey: todayKey, myDay: myDay, pinnedID: pinnedID, pile: pile,
      finishedCommitments: finished, leftovers: leftovers, due: due, shelves: shelves,
      unresolved: unresolved, wantsMorningPull: wantsMorningPull)
  }

  /// Dated work first (soonest first), then undated by title.
  static func shelfOrder(_ lhs: ReminderItem, _ rhs: ReminderItem) -> Bool {
    switch (lhs.dueDate, rhs.dueDate) {
    case (let left?, let right?) where left != right: return left < right
    case (.some, nil): return true
    case (nil, .some): return false
    default: return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }
  }
}
