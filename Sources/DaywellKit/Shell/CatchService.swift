import AppKit
import DaywellCore

/// Services → "Catch in Daywell": selected text from any app becomes reminders,
/// one per non-empty line. Each line goes through the capture grammar, so dates
/// and "/shelf" work the same as in the capture bar.
@MainActor public final class CatchService: NSObject {
  private let model: DayModel

  public init(model: DayModel) { self.model = model }

  /// Lines a selection would become, in order.
  public static func lines(in text: String) -> [String] {
    text.split(whereSeparator: \.isNewline)
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .map { line in
        // Drop list bullets people copy along with the text.
        var trimmed = Substring(line)
        for marker in ["- [ ] ", "- [x] ", "- ", "* ", "• "] where trimmed.hasPrefix(marker) {
          trimmed = trimmed.dropFirst(marker.count)
        }
        return String(trimmed)
      }
      .filter { !$0.isEmpty }
  }

  /// Saves every line. Returns how many Apple Reminders confirmed.
  @discardableResult
  public func catchLines(_ text: String) async -> Int {
    var saved = 0
    for line in Self.lines(in: text) {
      let result = CaptureParser.parse(line, now: model.now, calendar: model.calendar)
      let listID =
        CaptureParser.resolveShelf(result.shelfQuery, in: model.lists)?.id ?? model.inboxListID
      if await model.capture(result, listID: listID, keepDate: true, addToDay: false) != nil {
        saved += 1
      }
    }
    return saved
  }

  /// The NSServices entry point declared in Info.plist (NSMessage "catchText").
  @objc public func catchText(
    _ pasteboard: NSPasteboard, userData: String?,
    error: AutoreleasingUnsafeMutablePointer<NSString?>
  ) {
    guard let text = pasteboard.string(forType: .string), !Self.lines(in: text).isEmpty else {
      error.pointee = "Select some text to catch." as NSString
      return
    }
    Task { await catchLines(text) }
  }
}
