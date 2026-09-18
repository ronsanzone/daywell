import Foundation
import Testing

@testable import DaywellCore

@Suite struct DayPlanTests {
  let calendar: Calendar = {
    var value = Calendar(identifier: .gregorian)
    value.timeZone = TimeZone(identifier: "America/New_York")!
    value.locale = Locale(identifier: "en_US_POSIX")
    return value
  }()

  func date(_ value: String) -> Date {
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
    let result = plan.projection(reminders: items, now: now, calendar: calendar)
    #expect(result.today.map(\.id) == ["chosenDue"])
    #expect(result.due.map(\.id) == ["overdue", "futureTimedToday"])
    #expect(result.previous.map(\.id) == ["old"])
    #expect(result.done.map(\.id) == ["externalDone"])
    #expect(result.unresolved.map(\.reminderID) == ["missing"])
    #expect(result.pinnedReminderID == "chosenDue")
  }

  @Test func pinSortsFirstAndOrdersRemainingCommitments() {
    let now = date("2026-09-18T16:00:00Z")
    var plan = DayPlan()
    plan.choose("a", on: now, calendar: calendar)
    plan.choose("b", on: now, calendar: calendar)
    plan.pin("b", on: now, calendar: calendar)
    let result = plan.projection(
      reminders: [reminder("a"), reminder("b")], now: now, calendar: calendar)
    #expect(result.today.map(\.id) == ["b", "a"])
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
    let completed = plan.projection(
      reminders: [reminder("a", completed: now)], now: now, calendar: calendar)
    #expect(completed.pinnedReminderID == nil)
    #expect(completed.today.isEmpty)
    let missing = plan.projection(reminders: [], now: now, calendar: calendar)
    #expect(missing.pinnedReminderID == nil)
    #expect(missing.unresolved.count == 1)
  }
}
