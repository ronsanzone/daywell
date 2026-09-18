import Testing

@testable import DaywellCore

struct NavigationTests {
  @Test func vimMovesAndArrowsAgreeButNeverConsumeText() {
    var navigation = VimNavigation()
    #expect(navigation.action(for: "j", isEditing: false) == .next)
    #expect(navigation.action(for: "k", isEditing: false) == .previous)
    #expect(navigation.action(for: "j", isEditing: true) == nil)
    #expect(navigation.action(for: "h", isEditing: true) == nil)
    #expect(navigation.action(for: "↓", isEditing: false) == .next)
    #expect(navigation.action(for: "↑", isEditing: false) == .previous)
  }

  @Test func firstRequiresTwoGsAndTypingOrOtherKeysResetSequence() {
    var navigation = VimNavigation()
    #expect(navigation.action(for: "g", isEditing: false) == nil)
    #expect(navigation.action(for: "g", isEditing: false) == .first)
    #expect(navigation.action(for: "G", isEditing: false) == .last)
    _ = navigation.action(for: "g", isEditing: false)
    _ = navigation.action(for: "a", isEditing: true)
    #expect(navigation.action(for: "g", isEditing: false) == nil)
    _ = navigation.action(for: "j", isEditing: false)
    #expect(navigation.action(for: "g", isEditing: false) == nil)
  }
}
