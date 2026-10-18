import Foundation

/// What a line typed into the capture bar means. The UI shows each interpreted part
/// as a removable chip; nothing here is saved until the user presses Return.
public struct CaptureResult: Equatable, Sendable {
  public let title: String
  public let dueDate: Date?
  public let hasTime: Bool
  /// The literal date phrase that was interpreted, e.g. "tmrw at 2pm".
  public let datePhrase: String?
  /// The text after "/" naming a shelf, e.g. "work" from "/work".
  public let shelfQuery: String?

  public init(
    title: String, dueDate: Date?, hasTime: Bool, datePhrase: String? = nil,
    shelfQuery: String? = nil
  ) {
    self.title = title
    self.dueDate = dueDate
    self.hasTime = hasTime
    self.datePhrase = datePhrase
    self.shelfQuery = shelfQuery
  }
}

public enum CaptureParser {
  // Grammar, case-insensitive, deterministic:
  //   <title> [/shelf] [<day> [[at] <time>]]
  // The shelf token "/name" may appear anywhere; the last one wins.
  // <day>: today | tomorrow | tmrw | tmr | [next] <weekday or 3-letter weekday>
  // <time>: noon | midnight | h[:mm]am/pm | HH:mm
  // The date phrase must end the line. Invalid dates, DST gaps or overlaps, and
  // phrases with no title stay literal in the title; nothing is guessed.
  public static func parse(
    _ input: String,
    now: Date = Date(),
    calendar: Calendar = Calendar.current
  ) -> CaptureResult {
    var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
    var shelfQuery: String?
    let range = NSRange(text.startIndex..., in: text)
    if let match = shelfToken.matches(in: text, range: range).last,
      let whole = Range(match.range, in: text), let name = Range(match.range(at: 1), in: text)
    {
      let candidate = String(text[name])
      let remaining = (text[..<whole.lowerBound] + " " + text[whole.upperBound...])
        .trimmingCharacters(in: .whitespacesAndNewlines)
      if !remaining.isEmpty {
        shelfQuery = candidate
        text = remaining.replacingOccurrences(of: "  ", with: " ")
      }
    }
    return parseDate(text, shelfQuery: shelfQuery, now: now, calendar: calendar)
  }

  private static func parseDate(
    _ literal: String, shelfQuery: String?, now: Date, calendar: Calendar
  ) -> CaptureResult {
    let fallback = CaptureResult(
      title: literal, dueDate: nil, hasTime: false, shelfQuery: shelfQuery)
    guard
      let match = suffix.firstMatch(in: literal, range: NSRange(literal.startIndex..., in: literal)),
      let titleRange = Range(match.range(at: 1), in: literal),
      let dayRange = Range(match.range(at: 2), in: literal),
      let phraseStart = Range(match.range(at: 2), in: literal)?.lowerBound
    else { return fallback }

    let title = String(literal[titleRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty,
      let day = resolveDay(String(literal[dayRange]).lowercased(), now: now, calendar: calendar)
    else { return fallback }
    let phrase = String(literal[phraseStart...])

    guard match.range(at: 3).location != NSNotFound else {
      return CaptureResult(
        title: title, dueDate: calendar.startOfDay(for: day), hasTime: false,
        datePhrase: phrase, shelfQuery: shelfQuery)
    }
    guard let timeRange = Range(match.range(at: 3), in: literal),
      let time = parseTime(String(literal[timeRange]).lowercased()),
      let dueDate = strictDate(day: day, hour: time.hour, minute: time.minute, calendar: calendar)
    else { return fallback }
    return CaptureResult(
      title: title, dueDate: dueDate, hasTime: true, datePhrase: phrase, shelfQuery: shelfQuery)
  }

  // Constant patterns; parser tests exercise their compilation.
  // swiftlint:disable:next force_try
  private static let shelfToken = try! NSRegularExpression(
    pattern: #"(?:^|\s)/([\p{L}\p{N}][\p{L}\p{N}_\-]*)(?=\s|$)"#)

  private static let weekdays =
    "monday|tuesday|wednesday|thursday|friday|saturday|sunday|mon|tue|tues|wed|thu|thur|thurs|fri|sat|sun"

  // swiftlint:disable:next force_try
  private static let suffix = try! NSRegularExpression(
    pattern:
      #"^(.+?)\s+((?:next\s+)?(?:\#(weekdays))|today|tomorrow|tmrw|tmr)(?:\s+(?:at\s+)?(noon|midnight|\d{1,2}(?::\d{2})?\s*(?:am|pm)|\d{1,2}:\d{2}))?$"#,
    options: [.caseInsensitive]
  )

  private static func resolveDay(_ text: String, now: Date, calendar: Calendar) -> Date? {
    let start = calendar.startOfDay(for: now)
    if text == "today" { return start }
    if ["tomorrow", "tmrw", "tmr"].contains(text) {
      return calendar.date(byAdding: .day, value: 1, to: start)
    }
    let isNext = text.hasPrefix("next ")
    let name = (isNext ? String(text.dropFirst(5)) : text).trimmingCharacters(in: .whitespaces)
    let prefixes = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
    guard let index = prefixes.firstIndex(where: { name.hasPrefix($0) }) else { return nil }
    let current = calendar.component(.weekday, from: start)
    var distance = (index + 1 - current + 7) % 7
    if isNext, distance == 0 { distance = 7 }
    return calendar.date(byAdding: .day, value: distance, to: start)
  }

  private static func parseTime(_ text: String) -> (hour: Int, minute: Int)? {
    let compact = text.replacingOccurrences(of: " ", with: "")
    if compact == "noon" { return (12, 0) }
    if compact == "midnight" { return (0, 0) }

    if compact.hasSuffix("am") || compact.hasSuffix("pm") {
      let isPM = compact.hasSuffix("pm")
      let clock = compact.dropLast(2).split(separator: ":", omittingEmptySubsequences: false)
      guard clock.count <= 2, let rawHour = Int(clock[0]), (1...12).contains(rawHour) else {
        return nil
      }
      let minute = clock.count == 2 ? Int(clock[1]) : 0
      guard let minute, (0...59).contains(minute) else { return nil }
      return ((rawHour % 12) + (isPM ? 12 : 0), minute)
    }

    let clock = compact.split(separator: ":", omittingEmptySubsequences: false)
    guard clock.count == 2, let hour = Int(clock[0]), let minute = Int(clock[1]),
      (0...23).contains(hour), (0...59).contains(minute)
    else { return nil }
    return (hour, minute)
  }

  private static func strictDate(day: Date, hour: Int, minute: Int, calendar: Calendar) -> Date? {
    let dayParts = calendar.dateComponents([.era, .year, .month, .day], from: day)
    var requested = dayParts
    requested.hour = hour
    requested.minute = minute
    requested.second = 0
    guard let date = calendar.date(from: requested) else { return nil }
    let fields: Set<Calendar.Component> = [.era, .year, .month, .day, .hour, .minute, .second]
    guard calendar.dateComponents(fields, from: date) == requested else { return nil }

    // Foundation's repeatedTimePolicy does not distinguish every half-hour
    // overlap. Compare the actual zone-offset change, not an assumed hour.
    let zone = calendar.timeZone
    let delta =
      zone.secondsFromGMT(for: date.addingTimeInterval(-86400))
      - zone.secondsFromGMT(for: date.addingTimeInterval(86400))
    if delta > 0 {
      for offset in [-delta, delta] {
        if calendar.dateComponents(fields, from: date.addingTimeInterval(Double(offset)))
          == requested
        {
          return nil
        }
      }
    }
    return date
  }

  /// Picks the shelf a "/query" names: exact title, then prefix, then contains.
  public static func resolveShelf(_ query: String?, in lists: [ReminderList]) -> ReminderList? {
    guard let query = query?.lowercased(), !query.isEmpty else { return nil }
    let writable = lists.filter(\.isWritable)
    return writable.first { $0.title.lowercased() == query }
      ?? writable.first { $0.title.lowercased().hasPrefix(query) }
      ?? writable.first { $0.title.lowercased().contains(query) }
  }
}
