public enum NavigationAction: Equatable, Sendable {
  case next, previous, first, last, back, open
}

public struct VimNavigation: Sendable {
  private var pendingG = false
  public init() {}
  public mutating func action(for key: String, isEditing: Bool) -> NavigationAction? {
    guard !isEditing else {
      pendingG = false
      return nil
    }
    let wasG = pendingG
    pendingG = key == "g" && !wasG
    switch key {
    case "j", "↓": return .next
    case "k", "↑": return .previous
    case "g": return wasG ? .first : nil
    case "G": return .last
    case "h", "←": return .back
    case "l", "→": return .open
    default: return nil
    }
  }
}
