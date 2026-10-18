import DaywellCore
import DaywellFixtures
import Foundation
import Testing

@testable import DaywellKit

@MainActor struct DayModelTests {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  let lists = [ReminderList(id: "work", title: "Work"), ReminderList(id: "devex", title: "DevEx")]
  let now = Date()

  func item(_ id: String, list: String = "work", done: Date? = nil, due: Date? = nil)
    -> ReminderItem
  {
    ReminderItem(
      id: id, title: id.capitalized, listID: list, listName: list.capitalized, dueDate: due,
      isCompleted: done != nil, completionDate: done, externalID: "ext-\(id)")
  }

  func make(_ items: [ReminderItem], plan: DayPlan = DayPlan()) throws -> (
    DayModel, FixtureReminderStore
  ) {
    let store = FixtureReminderStore(items: items, lists: lists, defaultListID: "work")
    let planStore = PlanStore(url: directory.appendingPathComponent("plan.json"))
    try planStore.save(plan)
    return (DayModel(store: store, planStore: planStore, now: now), store)
  }

  func events(_ model: DayModel) -> () -> [FeedbackEvent.Kind] {
    var kinds: [FeedbackEvent.Kind] = []
    model.feedback.listen { kinds.append($0.kind) }
    return { kinds }
  }

  @Test func refreshLoadsOpenWorkAndTodaysCompletionsOnly() async throws {
    let old = now.addingTimeInterval(-3 * 86_400)
    let (model, store) = try make([
      item("open"), item("doneToday", done: now), item("doneLongAgo", done: old),
    ])
    await model.refresh()
    #expect(Set(model.reminders.map(\.id)) == ["open", "doneToday"])
    #expect(store.fetchedItemCount == 2)
    #expect(model.today.pile.map(\.id) == ["doneToday"])
  }

  @Test func finishStartsMotionBeforeConfirmationThenLandsOnThePile() async throws {
    var plan = DayPlan()
    plan.choose("a", on: now, calendar: .current)
    let (model, store) = try make([item("a"), item("b")], plan: plan)
    store.latency = .milliseconds(30)
    await model.refresh()
    let seen = events(model)
    let task = Task { await model.toggleCompletion("a") }
    await Task.yield()
    #expect(seen() == [.finishing])
    #expect(model.pending.contains("a"))
    await task.value
    #expect(seen().prefix(2) == [.finishing, .finished])
    #expect(model.today.pile.map(\.id) == ["a"])
    #expect(model.today.myDay.isEmpty)
    #expect(model.undo?.label == "Undo finish")
  }

  @Test func aRejectedFinishReversesAndExplains() async throws {
    var plan = DayPlan()
    plan.choose("a", on: now, calendar: .current)
    let (model, store) = try make([item("a")], plan: plan)
    await model.refresh()
    let seen = events(model)
    store.failNextSave = .changed
    await model.toggleCompletion("a")
    #expect(seen() == [.finishing, .finishFailed])
    #expect(model.reminder("a")?.isCompleted == false)
    #expect(model.error == ReminderError.changed.localizedDescription)
    #expect(model.today.pile.isEmpty)
  }

  @Test func undoReopensButNeverOverwritesALaterExternalEdit() async throws {
    let (model, store) = try make([item("a"), item("b")])
    await model.refresh()
    await model.toggleCompletion("a")
    await model.undoLast()
    #expect(model.reminder("a")?.isCompleted == false)
    await model.toggleCompletion("b")
    let index = try #require(store.items.firstIndex { $0.id == "b" })
    store.items[index].notes = "edited elsewhere"
    await model.undoLast()
    #expect(model.error == ReminderError.changed.localizedDescription)
    #expect(store.items.first { $0.id == "b" }?.isCompleted == true)
  }

  @Test func repeatingCompletionReleasesTheChoiceWithoutUnsafeUndo() async throws {
    var plan = DayPlan()
    plan.pin("r", on: now, calendar: .current)
    let (model, store) = try make([item("r", due: now)], plan: plan)
    store.repeatingIDs = ["r"]
    await model.refresh()
    await model.toggleCompletion("r")
    #expect(model.undo == nil)
    #expect(!model.plan.commitments.contains { $0.reminderID == "r" })
    #expect(model.notice?.contains("can't be undone") == true)
    #expect(model.error == nil)
  }

  @Test func dayClearIsAnnouncedOnceWhenTheLastChosenTaskFinishes() async throws {
    var plan = DayPlan()
    plan.choose("a", on: now, calendar: .current)
    plan.choose("b", on: now, calendar: .current)
    let (model, _) = try make([item("a"), item("b")], plan: plan)
    await model.refresh()
    let seen = events(model)
    await model.toggleCompletion("a")
    #expect(!seen().contains(.dayClear(count: 1)))
    await model.toggleCompletion("b")
    #expect(seen().filter { if case .dayClear = $0 { true } else { false } }.count == 1)
    #expect(model.today.isDayClear)
  }

  @Test func captureUsesTheShelfDateAndTodayChoice() async throws {
    let (model, store) = try make([])
    await model.refresh()
    let result = CaptureParser.parse("ask sean tomorrow at 2pm /dev", now: now)
    let devex = CaptureParser.resolveShelf(result.shelfQuery, in: model.lists)
    #expect(devex?.id == "devex")
    let saved = await model.capture(result, listID: "devex", keepDate: true, addToDay: true)
    #expect(saved?.listID == "devex" && saved?.hasDueTime == true)
    #expect(model.today.myDay.map(\.title) == ["ask sean"])
    let undated = await model.capture(
      CaptureParser.parse("water plants friday", now: now), listID: "work", keepDate: false,
      addToDay: false)
    #expect(undated?.dueDate == nil)
    #expect(store.items.count == 2)
  }

  @Test func movingKeepsTheTodayChoiceEvenWhenTheIdentifierChanges() async throws {
    let (model, store) = try make([item("a")])
    store.moveChangesIdentifier = true
    await model.refresh()
    model.choose("a")
    await model.move("a", toList: "devex")
    let moved = try #require(model.reminders.first { $0.title == "A" })
    #expect(moved.id != "a" && moved.listID == "devex")
    #expect(model.today.myDay.map(\.id) == [moved.id])
    #expect(model.undo?.label == "Undo move")
  }

  @Test func refreshHealsACommitmentByExternalIdentifier() async throws {
    var plan = DayPlan()
    plan.choose("old-id", on: now, calendar: .current)
    plan.commitments[0].externalID = "ext-shared"
    var renamed = item("new-id")
    renamed.externalID = "ext-shared"
    let (model, _) = try make([renamed], plan: plan)
    await model.refresh()
    #expect(model.today.myDay.map(\.id) == ["new-id"])
    #expect(model.today.unresolved.isEmpty)
  }

  @Test func startDayKeepsPicksAndPutsTheRestBack() async throws {
    var plan = DayPlan()
    let yesterday = now.addingTimeInterval(-86_400)
    plan.choose("left1", on: yesterday, calendar: .current)
    plan.choose("left2", on: yesterday, calendar: .current)
    let (model, _) = try make([item("left1"), item("left2"), item("shelf")], plan: plan)
    await model.refresh()
    #expect(model.today.wantsMorningPull)
    model.startDay(picking: ["left2", "shelf"])
    #expect(Set(model.today.myDay.map(\.id)) == ["left2", "shelf"])
    #expect(!model.plan.commitments.contains { $0.reminderID == "left1" })
    #expect(!model.today.wantsMorningPull)
  }

  @Test func planUndoRestoresTheEarlierPlan() async throws {
    let (model, _) = try make([item("a"), item("b")])
    await model.refresh()
    model.choose("a")
    model.choose("b")
    model.release("b")
    await model.undoLast()
    #expect(model.isChosen("b"))
  }

  @Test func aCorruptPlanNeedsRecoveryAndRestoresFromBackup() async throws {
    let (model, _) = try make([item("a")])
    await model.refresh()
    model.choose("a")
    model.choose("a")
    try Data("not json".utf8).write(to: model.planStore.url)
    let reopened = DayModel(
      store: FixtureReminderStore(items: [item("a")], lists: lists), planStore: model.planStore)
    #expect(reopened.recoveryRequired)
    await reopened.refresh()
    reopened.choose("a")
    #expect(reopened.error?.contains("recovery") == true)
    reopened.restorePlanBackup()
    #expect(!reopened.recoveryRequired)
  }

  @Test func aStaleFetchCannotOverwriteAConfirmedWrite() async throws {
    let (model, store) = try make([item("a")])
    await model.refresh()
    store.latency = .milliseconds(40)
    let slowRefresh = Task { await model.refresh() }
    try await Task.sleep(for: .milliseconds(5))
    store.latency = .zero
    await model.toggleCompletion("a")
    await slowRefresh.value
    #expect(model.reminder("a")?.isCompleted == true)
  }
}
