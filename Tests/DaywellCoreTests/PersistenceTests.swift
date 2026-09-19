import Foundation
import Testing

@testable import DaywellCore

@Suite final class PersistenceTests {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

  init() throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  deinit { try? FileManager.default.removeItem(at: directory) }

  func temporaryURL() -> URL {
    directory.appendingPathComponent("plan.json")
  }

  @Test func missingFileLoadsEmptyPlan() throws {
    let store = PlanStore(url: temporaryURL())
    #expect(try store.load() == DayPlan())
  }

  @Test func roundTripsPlanAndCreatesLastGoodBackupOnReplacement() throws {
    let store = PlanStore(url: temporaryURL())
    var first = DayPlan()
    first.choose(
      "first", on: Date(timeIntervalSince1970: 1), calendar: .init(identifier: .gregorian))
    try store.save(first)
    var second = first
    second.choose(
      "second", on: Date(timeIntervalSince1970: 2), calendar: .init(identifier: .gregorian))
    try store.save(second)
    #expect(try store.load() == second)
    let backup = try JSONDecoder().decode(DayPlan.self, from: Data(contentsOf: store.backupURL))
    #expect(backup == first)
  }

  @Test func malformedExistingFileIsNotOverwritten() throws {
    let url = temporaryURL()
    let bytes = Data("not json".utf8)
    try bytes.write(to: url)
    let store = PlanStore(url: url)
    #expect(throws: Error.self) { try store.load() }
    #expect(throws: Error.self) { try store.save(DayPlan()) }
    #expect(try Data(contentsOf: url) == bytes)
  }

  @Test func unsupportedSchemaIsRejectedAndNotOverwritten() throws {
    let url = temporaryURL()
    let bytes = Data(#"{"schemaVersion":99,"commitments":[],"pinnedCommitmentID":null}"#.utf8)
    try bytes.write(to: url)
    let store = PlanStore(url: url)
    #expect(throws: PlanStoreError.unsupportedSchema(99)) { try store.load() }
    #expect(throws: Error.self) { try store.save(DayPlan()) }
    #expect(try Data(contentsOf: url) == bytes)
  }

  @Test func backupRecoveryPreservesBrokenOriginalAndBackup() throws {
    let store = PlanStore(url: temporaryURL())
    var plan = DayPlan()
    plan.choose("kept", on: Date(timeIntervalSince1970: 1), calendar: .init(identifier: .gregorian))
    try store.save(plan)
    try store.save(plan)
    let backup = try Data(contentsOf: store.backupURL)
    let broken = Data("broken".utf8)
    try broken.write(to: store.url)
    #expect(try store.restoreBackup() == plan)
    #expect(try store.load() == plan)
    #expect(try Data(contentsOf: store.backupURL) == backup)
    let preserved = try FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: nil
    )
    .filter { $0.lastPathComponent.contains("unrecovered") }
    #expect(preserved.count == 1)
    #expect(try Data(contentsOf: #require(preserved.first)) == broken)
  }

  @Test func invalidBackupNeverReplacesOriginal() throws {
    let store = PlanStore(url: temporaryURL())
    let original = Data("broken original".utf8)
    try original.write(to: store.url)
    try Data("broken backup".utf8).write(to: store.backupURL)
    #expect(throws: DecodingError.self) { try store.restoreBackup() }
    #expect(try Data(contentsOf: store.url) == original)
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).count == 2)
  }

  @Test func recoveryDoesNotDowngradeFutureSchemaOrReplaceValidPlan() throws {
    let store = PlanStore(url: temporaryURL())
    try store.save(DayPlan())
    try store.save(DayPlan())
    #expect(throws: PlanStoreError.recoveryNotNeeded) { try store.restoreBackup() }
    // A future schema may have different fields: recognize the version first.
    let future = Data(#"{"schemaVersion":99,"futureData":"keep me"}"#.utf8)
    try future.write(to: store.url)
    #expect(throws: PlanStoreError.unsupportedSchema(99)) { try store.restoreBackup() }
    #expect(try Data(contentsOf: store.url) == future)
  }
}
