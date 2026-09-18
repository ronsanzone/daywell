import Foundation

public enum PlanStoreError: Error, Equatable {
  case unsupportedSchema(Int)
}

public struct PlanStore: Sendable {
  public let url: URL

  public var backupURL: URL { url.appendingPathExtension("backup") }

  public init(url: URL) { self.url = url }

  public func load() throws -> DayPlan {
    guard FileManager.default.fileExists(atPath: url.path) else { return DayPlan() }
    return try decodePlan(from: Data(contentsOf: url))
  }

  public func save(_ plan: DayPlan) throws {
    guard plan.schemaVersion == DayPlan.currentSchemaVersion else {
      throw PlanStoreError.unsupportedSchema(plan.schemaVersion)
    }
    let fileManager = FileManager.default
    var previousData: Data?
    if fileManager.fileExists(atPath: url.path) {
      let data = try Data(contentsOf: url)
      _ = try decodePlan(from: data)
      previousData = data
    }
    try fileManager.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(plan)
    if let previousData {
      try previousData.write(to: backupURL, options: .atomic)
    }
    try data.write(to: url, options: .atomic)
  }

  private func decodePlan(from data: Data) throws -> DayPlan {
    let plan = try JSONDecoder().decode(DayPlan.self, from: data)
    guard plan.schemaVersion == DayPlan.currentSchemaVersion else {
      throw PlanStoreError.unsupportedSchema(plan.schemaVersion)
    }
    return plan
  }
}
