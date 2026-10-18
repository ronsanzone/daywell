import AppKit
import DaywellCore
import DaywellKit

/// The shipping app: Apple Reminders, the user's plan file, standard preferences.
/// Demo, snapshot and check modes live in the separate DaywellDev executable.
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
  private var controller: AppController?

  func applicationDidFinishLaunching(_ notification: Notification) {
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Daywell")
    let controller = AppController(
      store: EventKitReminderStore(),
      planStore: PlanStore(url: support.appendingPathComponent("day-plan.json")),
      preferences: Preferences())
    controller.start()
    self.controller = controller
    if !controller.model.authorized { controller.showPanel() }
  }

  func applicationWillTerminate(_ notification: Notification) { controller?.stop() }
}

MainActor.assumeIsolated {
  let app = NSApplication.shared
  let delegate = AppDelegate()
  app.delegate = delegate
  app.setActivationPolicy(.accessory)
  withExtendedLifetime(delegate) { app.run() }
}
