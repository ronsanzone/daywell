import Foundation
import Testing

@testable import DaywellCore

@Suite struct DayPlanTests {
  let calendar: Calendar = {
    var value = Calendar(identifier: .gregorian)
    // Fixed IANA identifier supplied by macOS tzdata.
    // swiftlint:disable:next force_unwrapping
    value.timeZone = TimeZone(identifier: "America/New_York")!
    value.locale = Locale(identifier: "en_US_POSIX")
    return value
  }()

  let lists = [ReminderList(id: "list", title: "Inbox"), ReminderList(id: "other", title: "Other")]

  func date(_ value: String) -> Date {
    // All call sites pass fixed ISO-8601 fixture literals.
    // swiftlint:disable:next force_unwrapping
    ISO8601DateFormatter().date(from: value)!
  }

  func reminder(
    _ id: String, due: Date? = nil, timed: Bool = false,
    completed: Date? = nil
  ) -> ReminderItem {
    ReminderItem(
      id: id, title: id.uppercased(), listID: "list", listName: "Inbox",
      dueDate: due, hasDueTime: timed, isCompleted: completed != nil,
      completionDate: completed)
  }

  @Test func chooseDeduplicatesAndPreservesStableIdentity() {
    var plan = DayPlan()
    let now = date("2026-09-18T14:00:00Z")
    plan.choose("a", on: now, calendar: calendar)
    let original = plan.commitments[0]
    plan.choose("a", on: now, calendar: calendar)
    #expect(plan.commitments.count == 1)
    #expect(plan.commitments[0].id == original.id)
    #expect(plan.commitments[0].updatedAt == original.updatedAt)
  }

  @Test func choosingOnANewDayMovesMembershipWithoutDuplicatingIdentity() {
    var plan = DayPlan()
    plan.choose("a", on: date("2026-09-18T14:00:00Z"), calendar: calendar)
    let id = plan.commitments[0].id
    plan.choose("a", on: date("2026-10-02T14:00:00Z"), calendar: calendar)
    #expect(plan.commitments.count == 1)
    #expect(plan.commitments[0].id == id)
    #expect(plan.commitments[0].day == "2026-10-02")
  }

  @Test func pinChoosesTodayAndReplacesExistingPin() {
    var plan = DayPlan()
    let now = date("2026-09-18T14:00:00Z")
    plan.choose("a", on: now, calendar: calendar)
    plan.pin("b", on: now, calendar: calendar)
    #expect(plan.commitments.count == 2)
    #expect(plan.commitments.first(where: { $0.id == plan.pinnedCommitmentID })?.reminderID == "b")
    plan.pin("a", on: now, calendar: calendar)
    #expect(plan.pinnedCommitmentID == plan.commitments.first(where: { $0.reminderID == "a" })?.id)
  }

  @Test func releaseOnlyRemovesMembershipAndClearsItsPin() {
    var plan = DayPlan()
    let now = date("2026-09-18T14:00:00Z")
    let item = reminder("a", due: date("2026-09-20T13:00:00Z"))
    plan.pin(item.id, on: now, calendar: calendar)
    plan.release(item.id)
    #expect(plan.commitments.isEmpty)
    #expect(plan.pinnedCommitmentID == nil)
    #expect(item.dueDate == date("2026-09-20T13:00:00Z"))
  }

  @Test func projectionSeparatesTodayDuePreviousDoneAndUnresolved() {
    let now = date("2026-09-18T16:00:00Z")  // noon EDT
    var plan = DayPlan()
    plan.choose("chosenDue", on: now, calendar: calendar)
    plan.choose("old", on: date("2026-09-16T16:00:00Z"), calendar: calendar)
    plan.choose("missing", on: date("2026-09-17T16:00:00Z"), calendar: calendar)
    plan.pin("chosenDue", on: now, calendar: calendar)
    let items = [
      reminder("normal"),
      reminder("chosenDue", due: date("2026-09-18T04:00:00Z")),
      reminder("overdue", due: date("2026-09-17T20:00:00Z"), timed: true),
      reminder("futureTimedToday", due: date("2026-09-19T02:00:00Z"), timed: true),
      reminder("tomorrowDateOnly", due: date("2026-09-19T04:00:00Z")),
      reminder("old"),
      reminder("externalDone", completed: date("2026-09-18T14:00:00Z")),
      reminder("oldDone", completed: date("2026-09-17T14:00:00Z")),
    ]
    let result = Today.build(
      plan: plan, reminders: items, lists: lists, now: now, calendar: calendar)
    #expect(result.myDay.map(\.id) == ["chosenDue"])
    #expect(result.due.map(\.id) == ["overdue", "futureTimedToday"])
    #expect(result.leftovers.map(\.id) == ["old"])
    #expect(result.pile.map(\.id) == ["externalDone"])
    #expect(result.unresolved.map(\.reminderID) == ["missing"])
    #expect(result.pinnedID == "chosenDue")
  }

  @Test func pinSortsFirstAndOrdersRemainingCommitments() {
    let now = date("2026-09-18T16:00:00Z")
    var plan = DayPlan()
    plan.choose("a", on: now, calendar: calendar)
    plan.choose("b", on: now, calendar: calendar)
    plan.pin("b", on: now, calendar: calendar)
    let result = Today.build(
      plan: plan, reminders: [reminder("a"), reminder("b")], lists: lists, now: now,
      calendar: calendar)
    #expect(result.myDay.map(\.id) == ["b", "a"])
  }

  @Test func keepPreviousMovesOnlySelectedAndPreservesFutureMembership() {
    let now = date("2026-11-01T17:00:00Z")  // after DST boundary month rollover
    var plan = DayPlan()
    plan.choose("old", on: date("2026-10-30T16:00:00Z"), calendar: calendar)
    plan.choose("future", on: date("2026-11-03T17:00:00Z"), calendar: calendar)
    plan.keepPrevious(reminderIDs: ["old"], on: now, calendar: calendar)
    #expect(plan.commitments.first(where: { $0.reminderID == "old" })?.day == "2026-11-01")
    #expect(plan.commitments.first(where: { $0.reminderID == "future" })?.day == "2026-11-03")
  }

  @Test func dateKeysRespectInjectedCalendarAcrossDST() {
    var plan = DayPlan()
    plan.choose("before", on: date("2026-03-08T06:30:00Z"), calendar: calendar)
    plan.choose("after", on: date("2026-03-08T07:30:00Z"), calendar: calendar)
    #expect(plan.commitments.map(\.day) == ["2026-03-08", "2026-03-08"])
  }

  @Test func externallyCompletedOrMissingReminderIsNotAnActivePin() {
    let now = date("2026-09-18T16:00:00Z")
    var plan = DayPlan()
    plan.pin("a", on: now, calendar: calendar)
    let completed = Today.build(
      plan: plan, reminders: [reminder("a", completed: now)], lists: lists, now: now,
      calendar: calendar)
    #expect(completed.pinnedID == nil)
    #expect(completed.myDay.isEmpty)
    let missing = Today.build(plan: plan, reminders: [], lists: lists, now: now, calendar: calendar)
    #expect(missing.pinnedID == nil)
    #expect(missing.unresolved.count == 1)
  }

  @Test func todayCountsFinishedCommitmentsAndDayClear() {
    let now = date("2026-09-18T16:00:00Z")
    var plan = DayPlan()
    plan.choose("a", on: now, calendar: calendar)
    plan.choose("b", on: now, calendar: calendar)
    let half = Today.build(
      plan: plan, reminders: [reminder("a", completed: now), reminder("b")], lists: lists,
      now: now, calendar: calendar)
    #expect(half.finishedCommitments == 1 && !half.isDayClear)
    #expect(half.tickerTask?.id == "b")
    let all = Today.build(
      plan: plan, reminders: [reminder("a", completed: now), reminder("b", completed: now)],
      lists: lists, now: now, calendar: calendar)
    #expect(all.isDayClear && all.tickerTask == nil)
    let none = Today.build(
      plan: DayPlan(), reminders: [], lists: lists, now: now, calendar: calendar)
    #expect(!none.isDayClear)
  }

  @Test func pileIsOrderedByCompletionTime() {
    let now = date("2026-09-18T16:00:00Z")
    let items = [
      reminder("late", completed: date("2026-09-18T15:00:00Z")),
      reminder("early", completed: date("2026-09-18T13:00:00Z")),
    ]
    let result = Today.build(
      plan: DayPlan(), reminders: items, lists: lists, now: now, calendar: calendar)
    #expect(result.pile.map(\.id) == ["early", "late"])
  }

  @Test func shelvesHoldOpenWorkNotAlreadyChosen() {
    let now = date("2026-09-18T16:00:00Z")
    var plan = DayPlan()
    plan.choose("chosen", on: now, calendar: calendar)
    var other = reminder("elsewhere")
    other.listID = "other"
    let items = [
      reminder("chosen"), reminder("zeta"), reminder("alpha"),
      reminder("dated", due: date("2026-09-20T16:00:00Z")), reminder("done", completed: now), other,
    ]
    let result = Today.build(
      plan: plan, reminders: items, lists: lists, now: now, calendar: calendar)
    #expect(result.shelves.map(\.id) == ["list", "other"])
    #expect(result.shelves[0].items.map(\.id) == ["dated", "alpha", "zeta"])
    #expect(result.shelves[1].items.map(\.id) == ["elsewhere"])
  }

  @Test func morningPullWantsAnEmptyDayOrLeftoversOncePerDay() {
    let now = date("2026-09-18T16:00:00Z")
    let yesterday = date("2026-09-17T16:00:00Z")
    var plan = DayPlan()
    plan.choose("old", on: yesterday, calendar: calendar)
    let items = [reminder("old"), reminder("other")]
    #expect(
      Today.build(plan: plan, reminders: items, lists: lists, now: now, calendar: calendar)
        .wantsMorningPull)
    plan.markMorningPull(on: now, calendar: calendar)
    #expect(
      !Today.build(plan: plan, reminders: items, lists: lists, now: now, calendar: calendar)
        .wantsMorningPull)
    var chosen = DayPlan()
    chosen.choose("other", on: now, calendar: calendar)
    #expect(
      !Today.build(plan: chosen, reminders: items, lists: lists, now: now, calendar: calendar)
        .wantsMorningPull)
  }

  @Test func reorderMovesWithinTodayAndClamps() {
    let now = date("2026-09-18T16:00:00Z")
    var plan = DayPlan()
    for id in ["a", "b", "c"] { plan.choose(id, on: now, calendar: calendar) }
    plan.reorder("c", by: -1, among: ["a", "b", "c"], on: now)
    let order = { (plan: DayPlan) in
      Today.build(
        plan: plan, reminders: [self.reminder("a"), self.reminder("b"), self.reminder("c")],
        lists: self.lists, now: now, calendar: self.calendar
      ).myDay.map(\.id)
    }
    #expect(order(plan) == ["a", "c", "b"])
    plan.reorder("a", by: -5, among: order(plan), on: now)
    #expect(order(plan) == ["a", "c", "b"])
  }

  @Test func relinkMovesACommitmentToItsNewIdentifier() {
    let now = date("2026-09-18T16:00:00Z")
    var plan = DayPlan()
    plan.pin("old-id", on: now, calendar: calendar)
    plan.relink(from: "old-id", to: "new-id")
    let result = Today.build(
      plan: plan, reminders: [reminder("new-id")], lists: lists, now: now, calendar: calendar)
    #expect(result.pinnedID == "new-id")
    #expect(result.unresolved.isEmpty)
  }

  @Test func versionOnePlansWithoutTheMorningFieldStillDecode() throws {
    let json = #"{"schemaVersion":1,"commitments":[],"pinnedCommitmentID":null}"#
    let plan = try JSONDecoder().decode(DayPlan.self, from: Data(json.utf8))
    #expect(plan.morningPullDay == nil)
  }
}
