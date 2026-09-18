import Foundation

public struct ReminderItem: Identifiable, Codable, Equatable, Sendable {
  public var id: String
  public var title: String
  public var notes: String
  public var listID: String
  public var listName: String
  public var dueDate: Date?
  public var hasDueTime: Bool
  public var isCompleted: Bool
  public var completionDate: Date?
  public var isWritable: Bool
  public var externalID: String?

  public init(
    id: String, title: String, notes: String = "", listID: String = "",
    listName: String = "", dueDate: Date? = nil, hasDueTime: Bool = false,
    isCompleted: Bool = false, completionDate: Date? = nil,
    isWritable: Bool = true, externalID: String? = nil
  ) {
    self.id = id
    self.title = title
    self.notes = notes
    self.listID = listID
    self.listName = listName
    self.dueDate = dueDate
    self.hasDueTime = hasDueTime
    self.isCompleted = isCompleted
    self.completionDate = completionDate
    self.isWritable = isWritable
    self.externalID = externalID
  }
}

public struct ReminderList: Identifiable, Codable, Equatable, Sendable {
  public var id: String
  public var title: String
  public var isWritable: Bool

  public init(id: String, title: String, isWritable: Bool = true) {
    self.id = id
    self.title = title
    self.isWritable = isWritable
  }
}
