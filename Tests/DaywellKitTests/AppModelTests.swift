import DaywellCore
import Foundation
import Testing

@testable import DaywellKit

@MainActor final class TestStore: ReminderStore {
  var authorized = true
  var failWrites = false
  var advanceCompletions = false
  var ignoreCompletion = false
  var items = [ReminderItem(id: "a", title: "Dentist", listID: "inbox", listName: "Inbox")]
  var fetchHandler: (() async -> ReminderSnapshot)?
  func requestAccess() async throws -> Bool { authorized }
  func fetch() async throws -> ReminderSnapshot {
    if let fetchHandler { return await fetchHandler() }
    return ReminderSnapshot(
      reminders: items, lists: [ReminderList(id: "inbox", title: "Inbox")], defaultListID: "inbox")
  }
  func save(_ item: ReminderItem, replacing original: ReminderItem?) async throws -> ReminderItem {
    if failWrites { throw ReminderError.readOnly }
    if let original, items.first(where: { $0.id == original.id }) != original {
      throw ReminderError.changed
    }
    if let original, item.isCompleted && !original.isCompleted {
      if ignoreCompletion { return original }
      if advanceCompletions, let due = original.dueDate {
        var occurrence = item
        occurrence.id = "completed-\(original.id)"
        items.append(occurrence)
        var next = original
        next.dueDate = due.addingTimeInterval(86400)
        items[items.firstIndex(where: { $0.id == original.id })!] = next
        return next
      }
    }
    var saved = item
    if original == nil { saved.id = UUID().uuidString }
    items.removeAll { $0.id == saved.id }
    items.append(saved)
    return saved
  }
  func delete(_ original: ReminderItem) async throws { items.removeAll { $0.id == original.id } }
}

@MainActor struct AppModelTests {
  func withModel(_ body: (AppModel, TestStore) async throws -> Void) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = TestStore()
    let model = AppModel(
      store: store, planStore: PlanStore(url: directory.appendingPathComponent("plan.json")))
    await model.refresh()
    try await body(model, store)
  }

  @Test func completionFailureDoesNotClearPinOrPretendSuccess() async throws {
    try await withModel { model, store in
      model.pin("a")
      store.failWrites = true
      await model.complete("a")
      #expect(model.projection.pinnedReminderID == "a")
      #expect(model.reminders.first?.isCompleted == false)
      #expect(model.error != nil)
    }
  }

  @Test func completeAndUndoUpdatesRealFixtureAndLocalPin() async throws {
    try await withModel { model, store in
      model.pin("a")
      await model.complete("a")
      #expect(store.items.first?.isCompleted == true)
      #expect(model.projection.pinnedReminderID == nil)
      await model.undoCompletion()
      #expect(store.items.first?.isCompleted == false)
      #expect(model.projection.today.map(\.id) == ["a"])
    }
  }

  @Test func failedCaptureRetainsDraftAndDoesNotAddCommitment() async throws {
    try await withModel { model, store in
      store.failWrites = true
      model.captureText = "Call tomorrow at 2pm"
      model.captureAddToDay = true
      await model.saveCapture()
      #expect(model.captureText == "Call tomorrow at 2pm")
      #expect(model.plan.commitments.isEmpty)
      #expect(model.error != nil)
    }
  }

  @Test func captureDueDateDoesNotAutomaticallyChooseToday() async throws {
    try await withModel { model, store in
      model.captureText = "Renew pass tomorrow"
      await model.saveCapture()
      #expect(store.items.count == 2)
      #expect(store.items.last?.title == "Renew pass")
      #expect(store.items.last?.dueDate != nil)
      #expect(model.plan.commitments.isEmpty)
      #expect(model.captureText.isEmpty)
    }
  }

  @Test func releasePersistsWithoutDeletingAndReloadRestoresChoices() async throws {
    try await withModel { model, store in
      model.choose("a")
      let reloaded = AppModel(store: store, planStore: model.planStore)
      #expect(reloaded.plan.commitments.map(\.reminderID) == ["a"])
      model.release("a")
      #expect(store.items.count == 1)
      let saved = try model.planStore.load()
      #expect(saved.commitments.isEmpty)
    }
  }

  @Test func undoDoesNotOverwriteSubsequentExternalChange() async throws {
    try await withModel { model, store in
      await model.complete("a")
      store.items[0].title = "Changed elsewhere"
      await model.undoCompletion()
      #expect(store.items[0].isCompleted)
      #expect(store.items[0].title == "Changed elsewhere")
      #expect(model.error != nil)
    }
  }

  @Test func commandPaletteCanEditSelectionFromBrowseNotYetChosen() async throws {
    try await withModel { model, _ in
      model.selectedID = "a"
      model.route = .commands
      DaywellCommand.edit.perform(model)
      #expect(model.route == .edit)
      #expect(model.editing?.id == "a")
    }
  }

  @Test func localWriteFailureNeverPretendsCommitmentWasSaved() async throws {
    try await withModel { model, store in
      try FileManager.default.createDirectory(
        at: model.planStore.url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Data("broken".utf8).write(to: model.planStore.url)
      model.choose("a")
      #expect(model.plan.commitments.isEmpty)
      #expect(model.error != nil)
      #expect(store.items.count == 1)
    }
  }

  @Test func settingsPersistWithoutChangingPlanOrReminders() {
    let name = "daywell.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    let preferences = Preferences(defaults: defaults)
    #expect(preferences.theme == .graphite)
    #expect(!preferences.showCount)
    preferences.theme = .plum
    preferences.showCount = true
    preferences.shortcutKey = 2
    let reloaded = Preferences(defaults: defaults)
    #expect(reloaded.theme == .plum)
    #expect(reloaded.showCount)
    #expect(reloaded.shortcutKey == 2)
  }

  @Test func paletteExposesDoneAndDeletionWithoutDeletingImmediately() async throws {
    try await withModel { model, store in
      DaywellCommand.allCases.first { $0.title == "Show / hide Done today" }?.perform(model)
      #expect(model.doneExpanded)
      model.selectedID = "a"
      DaywellCommand.allCases.first { $0.title == "Delete selected reminder…" }?.perform(model)
      #expect(model.pendingDelete?.id == "a")
      #expect(store.items.count == 1)
    }
  }

  @Test func paletteNavigationUsesCommandsRatherThanReminderRows() async throws {
    try await withModel { model, _ in
      model.route = .commands
      model.navigate(.next)
      #expect(model.commandIndex == 1)
      model.navigate(.open)
      #expect(model.route == .browse)
    }
  }

  @Test func confirmedDeletionSurvivesAlertDismissal() async throws {
    try await withModel { model, store in
      let confirmed = store.items[0]
      model.pendingDelete = nil
      await model.deleteConfirmed(confirmed)
      #expect(store.items.isEmpty)
    }
  }

  @Test func filteringNeverLeavesAHiddenReminderSelected() async throws {
    try await withModel { model, store in
      store.items.append(
        ReminderItem(id: "b", title: "Buy milk", listID: "inbox", listName: "Inbox"))
      await model.refresh()
      model.route = .browse
      model.selectedID = "a"
      model.search = "milk"
      #expect(model.selectedID == "b")
      model.search = "no matching reminder"
      #expect(model.selectedID == nil)
      model.route = .commands
      #expect(!DaywellCommand.complete.isEnabled(model))
    }
  }

  @Test func lateFetchCannotOverwriteNewerRefresh() async throws {
    try await withModel { model, store in
      var pending: [CheckedContinuation<ReminderSnapshot, Never>] = []
      store.fetchHandler = { await withCheckedContinuation { pending.append($0) } }
      let older = Task { await model.refresh() }
      while pending.count < 1 { await Task.yield() }
      let newer = Task { await model.refresh() }
      while pending.count < 2 { await Task.yield() }
      var edited = store.items[0]
      edited.title = "Newer edit"
      pending[1].resume(
        returning: ReminderSnapshot(reminders: [edited], lists: [], defaultListID: nil))
      await newer.value
      pending[0].resume(
        returning: ReminderSnapshot(reminders: store.items, lists: [], defaultListID: nil))
      await older.value
      #expect(model.reminders.first?.title == "Newer edit")
    }
  }

  @Test func autoAdvancedOccurrenceReleasesChoiceAndCannotUndoNextOccurrence() async throws {
    try await withModel { model, store in
      store.items[0].dueDate = Date(timeIntervalSince1970: 1_790_000_000)
      store.items.append(ReminderItem(id: "b", title: "Ordinary task", listID: "inbox"))
      await model.refresh()
      await model.complete("b")
      #expect(model.undo != nil)
      model.pin("a")
      store.advanceCompletions = true
      await model.complete("a")
      #expect(model.undo == nil)
      #expect(!model.plan.commitments.contains { $0.reminderID == "a" })
      #expect(model.projection.pinnedReminderID == nil)
      #expect(
        model.reminders.first { $0.id == "a" }?.dueDate
          == Date(timeIntervalSince1970: 1_790_086_400))
      #expect(model.reminders.first { $0.id == "completed-a" }?.isCompleted == true)
      #expect(model.notice == "Occurrence completed. Undo unavailable for this repeating reminder.")
      let after = store.items
      await model.undoCompletion()
      #expect(store.items == after)
    }
  }

  @Test func unconfirmedCompletionDoesNotReleaseChoiceOrClaimSuccess() async throws {
    try await withModel { model, store in
      model.pin("a")
      store.ignoreCompletion = true
      await model.complete("a")
      #expect(model.undo == nil)
      #expect(model.projection.pinnedReminderID == "a")
      #expect(model.notice == nil)
      #expect(model.error != nil)
    }
  }
}
