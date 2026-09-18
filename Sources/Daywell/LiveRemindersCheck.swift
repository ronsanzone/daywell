import AppKit
import DaywellCore
import DaywellKit
import EventKit

/// Explicit opt-in acceptance run. Never reuses an existing list or writes to
/// existing reminders. Only the newly created calendar is eligible for cleanup.
@MainActor enum LiveRemindersCheck {
  static func run() async -> Int32 {
    let adapter = EventKitReminderStore()
    print(
      "LIVE CHECK: requesting Reminders access for Daywell; existing reminders will not be changed."
    )
    fflush(stdout)
    let permissionTimeout = Task {
      try? await Task.sleep(for: .seconds(60))
      guard !Task.isCancelled, !adapter.authorized else { return }
      print(
        "BLOCKED: approve Daywell in macOS Privacy & Security > Reminders, then rerun --live-check."
      )
      fflush(stdout)
      exit(2)
    }
    defer { permissionTimeout.cancel() }

    let fixtures = EKEventStore()
    let prefix = "Daywell acceptance \(UUID().uuidString)"
    var testList: EKCalendar?
    var failed = false
    do {
      guard try await adapter.requestAccess() else { throw ReminderError.denied }
      permissionTimeout.cancel()
      print("PASS: native Reminders permission granted")
      guard let source = fixtures.defaultCalendarForNewReminders()?.source else {
        throw CheckFailure(
          message: "No default Reminders account is available; no test list created.")
      }
      let list = EKCalendar(for: .reminder, eventStore: fixtures)
      list.title = "Daywell Test"
      list.source = source
      try fixtures.saveCalendar(list, commit: true)
      testList = list
      print("Created a new isolated Daywell Test list. Existing same-named lists are untouched.")
      fflush(stdout)

      // Construct after list creation so the adapter's EventKit cache starts
      // with the test calendar already present.
      let store = EventKitReminderStore()
      let initial = try await store.fetch()
      try check(
        initial.lists.contains { $0.id == list.calendarIdentifier && $0.isWritable },
        "new list is visible and writable through the app adapter")
      let calendar = Calendar.current
      let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date()))!
      var item = try await store.save(
        ReminderItem(
          id: "", title: "\(prefix) capture", notes: "Disposable fixture",
          listID: list.calendarIdentifier, listName: list.title, dueDate: tomorrow), replacing: nil)
      try check(
        !item.id.isEmpty && item.dueDate == tomorrow && !item.hasDueTime,
        "capture saves a date-only reminder")
      guard let native = fixtures.calendarItem(withIdentifier: item.id) as? EKReminder else {
        throw ReminderError.missing
      }
      try check(native.alarms?.isEmpty != false, "capture creates no additional alarm")

      let alarmDate = tomorrow.addingTimeInterval(14 * 3600)
      native.addAlarm(EKAlarm(absoluteDate: alarmDate))
      native.url = URL(string: "https://example.com/daywell-disposable-fixture")
      try fixtures.save(native, commit: true)
      item = try await snapshot(item.id, in: store)
      var edited = item
      edited.title = "\(prefix) edited"
      edited.notes = "Edited through Daywell"
      edited.dueDate = tomorrow.addingTimeInterval(15 * 3600 + 30 * 60)
      edited.hasDueTime = true
      item = try await store.save(edited, replacing: item)
      try check(
        item.title == edited.title && item.notes == edited.notes && item.dueDate == edited.dueDate
          && item.hasDueTime, "title, notes and timed deadline round-trip")
      _ = native.refresh()
      try check(
        native.alarms?.first?.absoluteDate == alarmDate
          && native.url?.absoluteString == "https://example.com/daywell-disposable-fixture",
        "editing preserves the existing alarm and URL")

      let beforeCompletion = item
      var completed = item
      completed.isCompleted = true
      let afterCompletion = try await store.save(completed, replacing: item)
      try check(
        afterCompletion.isCompleted && afterCompletion.completionDate != nil,
        "completion is persisted by EventKit")
      item = try await store.save(beforeCompletion, replacing: afterCompletion)
      try check(
        !item.isCompleted && item.completionDate == nil, "completion undo reopens the same reminder"
      )

      _ = native.refresh()
      native.notes = "External fixture edit"
      try fixtures.save(native, commit: true)
      do {
        _ = try await store.save(edited, replacing: item)
        throw CheckFailure(message: "Stale write unexpectedly overwrote an external change")
      } catch ReminderError.changed {
        print("PASS: stale write rejects an external edit")
      }
      item = try await snapshot(item.id, in: store)
      try check(item.notes == "External fixture edit", "refresh sees the external edit")
      try await store.delete(item)
      let afterDelete = try await store.fetch()
      try check(
        !afterDelete.reminders.contains { $0.id == item.id },
        "confirmed deletion removes only the disposable reminder")

      let recurring = EKReminder(eventStore: fixtures)
      recurring.calendar = list
      recurring.title = "\(prefix) recurring"
      recurring.dueDateComponents = calendar.dateComponents([.year, .month, .day], from: tomorrow)
      recurring.addRecurrenceRule(
        EKRecurrenceRule(
          recurrenceWith: .daily, interval: 1, end: EKRecurrenceEnd(occurrenceCount: 3)))
      try fixtures.save(recurring, commit: true)
      let beforeRecurring = try await snapshot(recurring.calendarItemIdentifier, in: store)
      var recurringDone = beforeRecurring
      recurringDone.isCompleted = true
      let savedRecurring = try await store.save(recurringDone, replacing: beforeRecurring)
      try check(savedRecurring.isCompleted, "recurring reminder can be completed")
      let reopenedRecurring = try await store.save(beforeRecurring, replacing: savedRecurring)
      try check(!reopenedRecurring.isCompleted, "recurring completion can be undone")
      _ = recurring.refresh()
      try check(
        recurring.recurrenceRules?.first?.frequency == .daily,
        "completion and undo preserve recurrence metadata")
    } catch {
      failed = true
      print("FAIL/BLOCKED: \(error.localizedDescription)")
    }

    if let list = testList {
      do {
        let remaining = await fetch(in: list, store: fixtures, prefix: prefix)
        guard let remaining else {
          throw CheckFailure(message: "Could not inspect fixtures for safe cleanup")
        }
        // Recurrence may produce a second reminder. Only this run's unique
        // prefix in this run's new calendar authorizes removing it.
        for entry in remaining where entry.owned {
          guard let reminder = fixtures.calendarItem(withIdentifier: entry.id) as? EKReminder,
            reminder.calendar.calendarIdentifier == list.calendarIdentifier,
            reminder.title?.hasPrefix(prefix) == true
          else { continue }
          try fixtures.remove(reminder, commit: true)
        }
        guard let final = await fetch(in: list, store: fixtures, prefix: prefix), final.isEmpty
        else {
          throw CheckFailure(
            message:
              "Test list contains unowned reminders or cannot be verified empty; left it intact")
        }
        try fixtures.removeCalendar(list, commit: true)
        print("PASS: disposable reminders and the newly created test list cleaned up")
      } catch {
        failed = true
        print("CLEANUP REQUIRED: \(error.localizedDescription)")
      }
    }
    fflush(stdout)
    return failed ? 1 : 0
  }

  private static func snapshot(_ id: String, in store: EventKitReminderStore) async throws
    -> ReminderItem
  {
    guard let item = try await store.fetch().reminders.first(where: { $0.id == id }) else {
      throw ReminderError.missing
    }
    return item
  }

  private static func fetch(in list: EKCalendar, store: EKEventStore, prefix: String) async -> [(
    id: String, owned: Bool
  )]? {
    await withCheckedContinuation { continuation in
      store.fetchReminders(matching: store.predicateForReminders(in: [list])) { reminders in
        continuation.resume(
          returning: reminders?.map {
            ($0.calendarItemIdentifier, $0.title?.hasPrefix(prefix) == true)
          })
      }
    }
  }

  private static func check(_ condition: Bool, _ label: String) throws {
    guard condition else { throw CheckFailure(message: label) }
    print("PASS: \(label)")
  }

  private struct CheckFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
  }
}
