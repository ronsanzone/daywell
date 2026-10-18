import AppKit
import DaywellCore
import DaywellFixtures
import Foundation
import Testing

@testable import DaywellKit

@MainActor struct SurfaceTests {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

  func make() async throws -> (DayModel, PanelState, CaptureState, FixtureReminderStore) {
    let (store, plan) = Fixtures.demo()
    let planStore = PlanStore(url: directory.appendingPathComponent("plan.json"))
    try planStore.save(plan)
    let model = DayModel(store: store, planStore: planStore)
    await model.refresh()
    let motion = MotionState(model: model)
    return (model, PanelState(model: model, motion: motion), CaptureState(model: model), store)
  }

  func shell(_ log: @escaping (String) -> Void) -> ShellActions {
    ShellActions(openCapture: { log("capture") }, closePanel: { log("close") })
  }

  @Test func panelKeysDriveTodayWithoutTheMouse() async throws {
    let (model, panel, _, _) = try await make()
    var log: [String] = []
    let keys = PanelKeys(model: model, panel: panel, shell: shell { log.append($0) })
    panel.reconcile()
    #expect(panel.selection == .task("mitigation"))
    #expect(keys.handle(KeyInput("j")))
    #expect(panel.selection == .task("slo"))
    #expect(keys.handle(KeyInput("r")))
    #expect(!model.isChosen("slo"))
    panel.selection = .shelf("devex")
    #expect(keys.handle(KeyInput("l")))
    #expect(panel.expandedShelves.contains("devex"))
    #expect(keys.handle(KeyInput("j")))
    let pulled = try #require(panel.selectedReminderID)
    #expect(keys.handle(KeyInput("a")))
    #expect(model.isChosen(pulled))
    #expect(keys.handle(KeyInput("", special: .escape)))
    #expect(log == ["close"])
    #expect(!keys.handle(KeyInput("q")))
  }

  @Test func ggAndGJumpToTheEnds() async throws {
    let (model, panel, _, _) = try await make()
    let keys = PanelKeys(model: model, panel: panel, shell: shell { _ in })
    panel.reconcile()
    _ = keys.handle(KeyInput("G"))
    #expect(panel.selection == panel.rows.last)
    _ = keys.handle(KeyInput("g"))
    _ = keys.handle(KeyInput("g"))
    #expect(panel.selection == panel.rows.first)
  }

  @Test func morningKeysPickWithDigitsAndStartWithReturn() async throws {
    let (model, panel, _, _) = try await make()
    let keys = PanelKeys(model: model, panel: panel, shell: shell { _ in })
    panel.beginMorning()
    let flat = panel.morningFlat
    #expect(keys.handle(KeyInput("1")))
    #expect(keys.handle(KeyInput("2")))
    #expect(panel.morningPicks == [flat[0].id, flat[1].id])
    #expect(keys.handle(KeyInput("", special: .enter)))
    #expect(panel.route == .today)
    #expect(model.isChosen(flat[0].id) && model.isChosen(flat[1].id))
  }

  @Test func captureKeysOneDoorTwoRooms() async throws {
    let (model, _, capture, _) = try await make()
    var opened: [String?] = []
    var closed = 0
    let keys = CaptureKeys(
      capture: capture, model: model, close: { closed += 1 }, openPanel: { opened.append($0) },
      saved: {})
    #expect(keys.handle(KeyInput("", special: .tab)))
    #expect(opened == [nil])
    capture.text = "renew parking fri"
    let before = capture.targetListID
    #expect(keys.handle(KeyInput("", special: .tab)))
    #expect(capture.targetListID != before)
    capture.text = ""
    #expect(keys.handle(KeyInput("", special: .down)))
    #expect(capture.listIndex == 0)
    #expect(keys.handle(KeyInput("w")))  // Letters never leak into the hidden field.
    #expect(keys.handle(KeyInput("j")))
    let second = model.today.myDay[1].id
    #expect(keys.handle(KeyInput("p")))
    #expect(model.today.pinnedID == second)
    #expect(keys.handle(KeyInput("", special: .up)))
    #expect(keys.handle(KeyInput("", special: .up)))
    #expect(capture.listIndex == nil)
    #expect(!keys.handle(KeyInput("a")))  // Back in the field, letters are typing.
    #expect(keys.handle(KeyInput("", special: .escape)))
    #expect(closed == 1)
  }

  @Test func captureSubmitResolvesTheShelfAndClearsTheLine() async throws {
    let (model, _, capture, store) = try await make()
    capture.text = "Remote workstation bootstrap /dev"
    #expect(capture.targetListID == "devex")
    #expect(await capture.submit(addToDay: false))
    #expect(capture.text.isEmpty)
    #expect(
      store.items.contains { $0.title == "Remote workstation bootstrap" && $0.listID == "devex" })
    #expect(capture.caught.first?.title == "Remote workstation bootstrap")
    _ = model
  }

  @Test func everyThemeMeetsContrastTargets() {
    for id in ThemeID.allCases {
      let t = ThemeProfile.tokens(id)
      for surface in [t.background, t.raised] {
        #expect(contrastRatio(t.text, surface) >= 4.5, "\(id) text")
        #expect(contrastRatio(t.secondary, surface) >= 4.5, "\(id) secondary")
        #expect(contrastRatio(t.accent, surface) >= 3, "\(id) accent")
        for ink in t.inks { #expect(contrastRatio(ink, surface) >= 3, "\(id) ink \(ink)") }
      }
    }
  }

  @Test func storedThemeNamesSurviveTheRename() {
    #expect(ThemeID(stored: "graphite") == .quietNative)
    #expect(ThemeID(stored: "amber") == .phosphor)
    #expect(ThemeID(stored: "sage") == .quietNative)
    #expect(ThemeID(stored: nil) == .quietNative)
  }

  @Test func soundCuesAreShort() {
    let player = SoundPlayer()
    for cue in SoundCue.allCases {
      let duration = player.duration(of: cue)
      #expect(duration > 0.04 && duration < 1.2, "\(cue) \(duration)")
    }
  }

  @Test func tickerSaysTheRightThing() async throws {
    let (model, _, _, _) = try await make()
    let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
    let ticker = StatusTicker(model: model, preferences: Preferences(defaults: defaults)) {}
    #expect(ticker.text == "Create mitigation ticke…  +2")
    #expect(ticker.region(atX: 4) == .ring)
    await model.toggleCompletion("mitigation")
    #expect(
      ticker.text == "Create mitigation ticke…", "the struck title holds while the motion plays")
    try await Task.sleep(for: .milliseconds(500))
    #expect(ticker.text.hasSuffix(" · undo"))
    for task in model.today.myDay { await model.toggleCompletion(task.id) }
    try await Task.sleep(for: .milliseconds(500))
    #expect(ticker.text.hasPrefix("Day clear · "))
    NSStatusBar.system.removeStatusItem(ticker.item)
  }
}
