import Foundation
import Testing

@testable import DaywellCore

@Suite struct PersistenceTests {
  func temporaryURL() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent("plan.json")
  }

  @Test func missingFileLoadsEmptyPlan() throws {
    let store = PlanStore(url: try temporaryURL())
    #expect(try store.load() == DayPlan())
  }

  @Test func roundTripsPlanAndCreatesLastGoodBackupOnReplacement() throws {
    let store = PlanStore(url: try temporaryURL())
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
    let url = try temporaryURL()
    let bytes = Data("not json".utf8)
    try bytes.write(to: url)
    let store = PlanStore(url: url)
    #expect(throws: Error.self) { try store.load() }
    #expect(throws: Error.self) { try store.save(DayPlan()) }
    #expect(try Data(contentsOf: url) == bytes)
  }

  @Test func unsupportedSchemaIsRejectedAndNotOverwritten() throws {
    let url = try temporaryURL()
    let bytes = Data(#"{"schemaVersion":99,"commitments":[],"pinnedCommitmentID":null}"#.utf8)
    try bytes.write(to: url)
    let store = PlanStore(url: url)
    #expect(throws: PlanStoreError.unsupportedSchema(99)) { try store.load() }
    #expect(throws: Error.self) { try store.save(DayPlan()) }
    #expect(try Data(contentsOf: url) == bytes)
  }
}
