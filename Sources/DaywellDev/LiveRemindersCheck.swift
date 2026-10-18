import AppKit
import DaywellCore
import DaywellKit
import EventKit

/// Explicit opt-in acceptance run. Fixture recovery additionally requires an
/// exact list ID, unique run prefix, and reminder IDs supplied by the caller.
@MainActor enum LiveRemindersCheck {
  static func run() async -> Int32 {
    let recovery: (listID: String, prefix: String, ids: Set<String>)?
    if let index = CommandLine.arguments.firstIndex(of: "--recover-fixtures") {
      let values = Array(CommandLine.arguments.dropFirst(index + 1))
      guard values.count == 3, !values[0].isEmpty,
        values[1].hasPrefix("Daywell acceptance "),
        UUID(uuidString: String(values[1].dropFirst("Daywell acceptance ".count))) != nil,
        !values[2].isEmpty
      else {
        print(
          "Recovery requires an exact list ID, Daywell acceptance UUID prefix, and comma-separated reminder IDs."
        )
        return 2
      }
      recovery = (values[0], values[1], Set(values[2].split(separator: ",").map(String.init)))
    } else {
      recovery = nil
    }
    let adapter = EventKitReminderStore()
    print(
      "LIVE CHECK: requesting Reminders access; writes are restricted to disposable test fixtures."
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
    var createdShelf: EKCalendar?
    var failed = false
    do {
      guard try await adapter.requestAccess() else { throw ReminderError.denied }
      permissionTimeout.cancel()
      print("PASS: native Reminders permission granted")
      await measureFetch(fixtures)
      if let recovery {
        guard let list = fixtures.calendar(withIdentifier: recovery.listID),
          list.title == "Daywell Test",
          let entries = await fetch(in: list, store: fixtures, prefix: recovery.prefix),
          entries.allSatisfy({ $0.owned && recovery.ids.contains($0.id) })
        else {
          throw CheckFailure(
            message: "Recovery list or fixture identity did not match; nothing removed.")
        }
        // Revalidate each fetched object before deletion, and never delete a
        // calendar unless a fresh query confirms it is empty.
        for entry in entries {
          guard let reminder = fixtures.calendarItem(withIdentifier: entry.id) as? EKReminder,
            reminder.calendar.calendarIdentifier == recovery.listID,
            reminder.title?.hasPrefix(recovery.prefix) == true
          else { throw CheckFailure(message: "Recovery fixture changed; stopped cleanup.") }
          try fixtures.remove(reminder, commit: true)
        }
        guard let remaining = await fetch(in: list, store: fixtures, prefix: recovery.prefix),
          remaining.isEmpty
        else { throw CheckFailure(message: "Recovery list is not verified empty; kept it intact.") }
        try fixtures.removeCalendar(list, commit: true)
        print(
          "PASS: recovered \(entries.count) identified prior fixtures and removed their empty test list"
        )
      }
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
      print("Test list ID: \(list.calendarIdentifier); fixture prefix: \(prefix)")
      fflush(stdout)

      // Construct after list creation so the adapter's EventKit cache starts
      // with the test calendar already present.
      let store = EventKitReminderStore()
      let initial = try await store.fetch(completedSince: Calendar.current.startOfDay(for: Date()))
      try check(
        initial.lists.contains { $0.id == list.calendarIdentifier && $0.isWritable },
        "new list is visible and writable through the app adapter")
      let calendar = Calendar.current
      guard
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date()))
      else {
        throw CocoaError(.validationMissingMandatoryProperty)
      }
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
      let afterDelete = try await store.fetch(
        completedSince: Calendar.current.startOfDay(for: Date()))
      try check(
        !afterDelete.reminders.contains { $0.id == item.id },
        "confirmed deletion removes only the disposable reminder")

      // Moving between lists: does the reminder keep its identifier, and does its
      // My Day choice follow it? The first-run section sort depends on this.
      let shelf = try await store.createList(named: "Daywell Test Shelf")
      createdShelf = fixtures.calendar(withIdentifier: shelf.id)
      try check(createdShelf != nil, "store.createList creates a new writable list")
      let movable = try await store.save(
        ReminderItem(
          id: "", title: "\(prefix) movable", listID: list.calendarIdentifier,
          listName: list.title), replacing: nil)
      let moveDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString)
      defer { try? FileManager.default.removeItem(at: moveDirectory) }
      let moveModel = DayModel(
        store: store, planStore: PlanStore(url: moveDirectory.appendingPathComponent("plan.json")))
      await moveModel.refresh()
      moveModel.choose(movable.id)
      await moveModel.move(movable.id, toList: shelf.id)
      let moved = moveModel.reminders.first { $0.title == movable.title }
      print(
        "RESULT: identifier \(moved?.id == movable.id ? "SURVIVES" : "CHANGES") when a reminder moves between lists (before \(movable.id), after \(moved?.id ?? "missing"))"
      )
      try check(moved?.listID == shelf.id, "move puts the reminder in the target list")
      await moveModel.refresh()
      try check(
        moveModel.today.myDay.contains { $0.title == movable.title },
        "the My Day choice follows the moved reminder after a fresh fetch")
      if let moved { try await store.delete(moved) }

      let recurring = EKReminder(eventStore: fixtures)
      recurring.calendar = list
      recurring.title = "\(prefix) recurring"
      recurring.dueDateComponents = calendar.dateComponents([.year, .month, .day], from: tomorrow)
      recurring.addRecurrenceRule(
        EKRecurrenceRule(
          recurrenceWith: .daily, interval: 1, end: EKRecurrenceEnd(occurrenceCount: 3)))
      try fixtures.save(recurring, commit: true)
      let beforeRecurring = try await snapshot(recurring.calendarItemIdentifier, in: store)
      let planDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString)
      defer { try? FileManager.default.removeItem(at: planDirectory) }
      let model = DayModel(
        store: store, planStore: PlanStore(url: planDirectory.appendingPathComponent("plan.json")))
      await model.refresh()
      model.pin(beforeRecurring.id)
      await model.toggleCompletion(beforeRecurring.id)
      try check(
        model.error == nil && model.undo == nil
          && !model.plan.commitments.contains { $0.reminderID == beforeRecurring.id },
        "auto-advanced recurrence releases its commitment and offers no unsafe undo")
      let recurringState = try await store.fetch(
        completedSince: Calendar.current.startOfDay(for: Date()))
      let occurrences = recurringState.reminders.filter { $0.listID == list.calendarIdentifier }
      try check(
        occurrences.count == 2
          && occurrences.contains {
            $0.id != beforeRecurring.id && $0.isCompleted && $0.dueDate == tomorrow
          }, "EventKit retains the completed occurrence separately")
      try check(
        occurrences.contains {
          $0.id == beforeRecurring.id && !$0.isCompleted
            && $0.dueDate == calendar.date(byAdding: .day, value: 1, to: tomorrow)
        }, "the next occurrence remains at its advanced deadline")
      await model.undoLast()
      let afterNoUndo = try await store.fetch(
        completedSince: Calendar.current.startOfDay(for: Date())
      ).reminders.filter {
        $0.listID == list.calendarIdentifier
      }
      try check(
        afterNoUndo.sorted { $0.id < $1.id } == occurrences.sorted { $0.id < $1.id },
        "unavailable undo does not reschedule or duplicate either occurrence")
      for oldList in recurringState.lists
      where oldList.title == "Daywell Test" && oldList.id != list.calendarIdentifier {
        let oldFixtures = recurringState.reminders.filter { $0.listID == oldList.id }
        print("Pre-existing test list \(oldList.id): \(oldFixtures.count) items")
        for old in oldFixtures where old.title.hasPrefix("Daywell acceptance ") {
          print("Prior fixture: \(old.id) \(old.title)")
        }
      }
      fflush(stdout)
      _ = recurring.refresh()
      try check(
        recurring.recurrenceRules?.first?.frequency == .daily,
        "auto-advanced completion preserves recurrence metadata")
    } catch {
      failed = true
      print("FAIL/BLOCKED: \(error.localizedDescription)")
      fflush(stdout)
    }

    if let shelf = createdShelf {
      do {
        let remaining = await fetch(in: shelf, store: fixtures, prefix: prefix)
        for entry in remaining ?? [] where entry.owned {
          if let reminder = fixtures.calendarItem(withIdentifier: entry.id) as? EKReminder {
            try fixtures.remove(reminder, commit: true)
          }
        }
        if let final = await fetch(in: shelf, store: fixtures, prefix: prefix), final.isEmpty {
          try fixtures.removeCalendar(shelf, commit: true)
          print("PASS: the disposable test shelf was removed")
        } else {
          throw CheckFailure(message: "Test shelf not verified empty; left it intact")
        }
      } catch {
        failed = true
        print("CLEANUP REQUIRED: \(error.localizedDescription)")
      }
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

  /// Read-only: how long the old everything-fetch takes versus the two narrow fetches.
  private static func measureFetch(_ store: EKEventStore) async {
    let calendars = store.calendars(for: .reminder)
    let clock = ContinuousClock()
    func run(_ predicate: NSPredicate) async -> Int {
      await withCheckedContinuation { continuation in
        store.fetchReminders(matching: predicate) { @Sendable in
          continuation.resume(returning: $0?.count ?? 0)
        }
      }
    }
    func runConcurrently(_ predicates: [NSPredicate]) async -> Int {
      await withCheckedContinuation { continuation in
        let counter = Counter(expected: predicates.count, continuation: continuation)
        for predicate in predicates {
          store.fetchReminders(matching: predicate) { @Sendable in counter.add($0?.count ?? 0) }
        }
      }
    }
    for round in 1...3 {
      let oldStart = clock.now
      let all = await run(store.predicateForReminders(in: calendars))
      let oldTime = clock.now - oldStart
      let newStart = clock.now
      let narrow = await runConcurrently([
        store.predicateForIncompleteReminders(
          withDueDateStarting: nil, ending: nil, calendars: calendars),
        store.predicateForCompletedReminders(
          withCompletionDateStarting: Calendar.current.startOfDay(for: Date()), ending: nil,
          calendars: calendars),
      ])
      let newTime = clock.now - newStart
      print(
        "MEASURE round \(round): all-reminders fetch \(all) items in \(oldTime); open+today fetch \(narrow) items in \(newTime)"
      )
    }
    fflush(stdout)
  }

  private static func snapshot(_ id: String, in store: EventKitReminderStore) async throws
    -> ReminderItem
  {
    guard
      let item = try await store.fetch(completedSince: Calendar.current.startOfDay(for: Date()))
        .reminders.first(where: { $0.id == id })
    else {
      throw ReminderError.missing
    }
    return item
  }

  private static func fetch(in list: EKCalendar, store: EKEventStore, prefix: String) async -> [(
    id: String, owned: Bool
  )]? {
    await withCheckedContinuation { continuation in
      store.fetchReminders(matching: store.predicateForReminders(in: [list])) {
        @Sendable reminders in
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
    fflush(stdout)
  }

  private struct CheckFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
  }
}

private final class Counter: @unchecked Sendable {
  private let lock = NSLock()
  private var remaining: Int
  private var total = 0
  private let continuation: CheckedContinuation<Int, Never>
  init(expected: Int, continuation: CheckedContinuation<Int, Never>) {
    remaining = expected
    self.continuation = continuation
  }
  func add(_ count: Int) {
    lock.lock()
    defer { lock.unlock() }
    total += count
    remaining -= 1
    if remaining == 0 { continuation.resume(returning: total) }
  }
}
