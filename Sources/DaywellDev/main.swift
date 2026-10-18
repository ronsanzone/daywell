import AppKit
import DaywellCore
import DaywellFixtures
import DaywellKit

/// Development entry point. Never shipped; never uses EventKit except `--live-check`.
///   --demo [--theme ID] [--fresh-day]   Run the real UI against fixtures.
///   --snapshot DIR                      Render every surface in every theme to PNG.
///   --ui-check [--frames DIR]           Drive real windows with AppKit events; assert; time.
///   --bench                             Projection and fetch-size benchmarks.
///   --live-check                        Opt-in Apple Reminders acceptance (writes disposable lists).
@MainActor final class DevDelegate: NSObject, NSApplicationDelegate {
  let arguments = CommandLine.arguments
  var controller: AppController?
  var temporary: URL?
  var defaultsName: String?

  func applicationDidFinishLaunching(_ notification: Notification) {
    if arguments.contains("--live-check") {
      Task { exit(await LiveRemindersCheck.run()) }
      return
    }
    if arguments.contains("--bench") {
      Bench.run()
      exit(0)
    }
    do {
      let (controller, store) = try makeController()
      self.controller = controller
      controller.start()
      Task {
        await controller.model.refresh()
        if let directory = option("--snapshot") {
          await Snapshots.run(controller: controller, directory: URL(fileURLWithPath: directory))
          NSApp.terminate(nil)
        } else if arguments.contains("--ui-check") {
          let frames = option("--frames").map { URL(fileURLWithPath: $0) }
          let check = UICheck(controller: controller, store: store, frames: frames)
          let code =
            arguments.contains("--fresh-day") ? await check.runMorning() : await check.run()
          cleanUp()
          exit(code)
        } else {
          controller.showPanel()
        }
      }
    } catch {
      print("Could not start: \(error)")
      exit(1)
    }
  }

  func makeController() throws -> (AppController, FixtureReminderStore) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "daywell-dev-\(UUID().uuidString)")
    temporary = root
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let name = "daywell.dev.\(UUID().uuidString)"
    defaultsName = name
    guard let defaults = UserDefaults(suiteName: name) else { throw CocoaError(.fileWriteUnknown) }
    let preferences = Preferences(defaults: defaults)
    if let theme = option("--theme").flatMap(ThemeID.init(rawValue:)) { preferences.theme = theme }
    let (store, seeded) = Fixtures.demo()
    var plan = seeded
    if arguments.contains("--fresh-day") {
      // Nothing chosen today and yesterday's leftovers waiting: the morning pull appears.
      plan.commitments.removeAll { $0.reminderID != "prototype" }
      plan.morningPullDay = nil
      plan.pinnedCommitmentID = nil
    }
    let planStore = PlanStore(url: root.appendingPathComponent("day-plan.json"))
    try planStore.save(plan)
    store.latency = .milliseconds(12)
    return (AppController(store: store, planStore: planStore, preferences: preferences), store)
  }

  func option(_ name: String) -> String? {
    guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else {
      return nil
    }
    return arguments[index + 1]
  }

  func cleanUp() {
    controller?.stop()
    if let temporary { try? FileManager.default.removeItem(at: temporary) }
    if let defaultsName { UserDefaults.standard.removePersistentDomain(forName: defaultsName) }
  }

  func applicationWillTerminate(_ notification: Notification) { cleanUp() }
}

MainActor.assumeIsolated {
  let app = NSApplication.shared
  let delegate = DevDelegate()
  app.delegate = delegate
  app.setActivationPolicy(.accessory)
  withExtendedLifetime(delegate) { app.run() }
}
