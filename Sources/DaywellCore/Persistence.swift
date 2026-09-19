import Foundation

public enum PlanStoreError: LocalizedError, Equatable {
  case unsupportedSchema(Int)
  case recoveryNotNeeded

  public var errorDescription: String? {
    switch self {
    case .unsupportedSchema(let version):
      "Day plan version \(version) is not supported. Use a compatible Daywell version; the file was not changed."
    case .recoveryNotNeeded:
      "The current day plan is valid. Backup recovery was not needed."
    }
  }
}

public struct PlanStore: Sendable {
  public let url: URL

  public var backupURL: URL { url.appendingPathExtension("backup") }

  public init(url: URL) { self.url = url }

  public func load() throws -> DayPlan {
    guard FileManager.default.fileExists(atPath: url.path) else { return DayPlan() }
    return try decodePlan(from: Data(contentsOf: url))
  }

  public func restoreBackup() throws -> DayPlan {
    let backup = try Data(contentsOf: backupURL)
    let recovered = try decodePlan(from: backup)
    if FileManager.default.fileExists(atPath: url.path) {
      let original = try Data(contentsOf: url)
      do {
        _ = try decodePlan(from: original)
        throw PlanStoreError.recoveryNotNeeded
      } catch is DecodingError {
        // Preserve the exact corrupt bytes before replacing them. Future
        // schemas and I/O failures propagate instead of permitting rollback.
        let preserved = url.appendingPathExtension("unrecovered-\(UUID().uuidString)")
        try original.write(to: preserved, options: .atomic)
      }
    }
    try backup.write(to: url, options: .atomic)
    return recovered
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
    struct Version: Decodable { let schemaVersion: Int }
    let decoder = JSONDecoder()
    let version = try decoder.decode(Version.self, from: data).schemaVersion
    guard version == DayPlan.currentSchemaVersion else {
      throw PlanStoreError.unsupportedSchema(version)
    }
    return try decoder.decode(DayPlan.self, from: data)
  }
}
