import Foundation

public struct CaptureResult: Equatable, Sendable {
  public let title: String
  public let dueDate: Date?
  public let hasTime: Bool
  public let interpretation: String?

  public init(title: String, dueDate: Date?, hasTime: Bool, interpretation: String?) {
    self.title = title
    self.dueDate = dueDate
    self.hasTime = hasTime
    self.interpretation = interpretation
  }
}

public enum CaptureParser {
  // Accepted (case-insensitive) grammar is a non-empty title followed by:
  //   today | tomorrow | [next] <weekday>
  // and optionally "at" plus noon, midnight, h[[:]mm]am/pm, or HH:mm.
  // Only a terminal suffix is considered. Invalid input, DST gaps/overlaps, and
  // date phrases without a title are returned literally and wholly unparsed.
  public static func parse(
    _ input: String,
    now: Date = Date(),
    calendar: Calendar = Calendar.current
  ) -> CaptureResult {
    let literal = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard
      let match = suffix.firstMatch(
        in: literal,
        range: NSRange(literal.startIndex..., in: literal)
      ), let titleRange = Range(match.range(at: 1), in: literal),
      let dayRange = Range(match.range(at: 2), in: literal)
    else {
      return fallback(literal)
    }

    let title = String(literal[titleRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty else { return fallback(literal) }

    let dayText = String(literal[dayRange]).lowercased()
    guard let day = resolveDay(dayText, now: now, calendar: calendar) else {
      return fallback(literal)
    }

    let hasTime = match.range(at: 3).location != NSNotFound
    if !hasTime {
      return CaptureResult(
        title: title,
        dueDate: calendar.startOfDay(for: day),
        hasTime: false,
        interpretation: "Due \(dayText) (date only)"
      )
    }

    guard let timeRange = Range(match.range(at: 3), in: literal),
      let time = parseTime(String(literal[timeRange]).lowercased()),
      let dueDate = strictDate(day: day, hour: time.hour, minute: time.minute, calendar: calendar)
    else {
      return fallback(literal)
    }
    return CaptureResult(
      title: title,
      dueDate: dueDate,
      hasTime: true,
      interpretation: "Due \(dayText) at \(String(literal[timeRange]))"
    )
  }

  private static let suffix = try! NSRegularExpression(
    pattern:
      #"^(.+?)\s+((?:next\s+)?(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday)|today|tomorrow)(?:\s+at\s+(noon|midnight|\d{1,2}(?::\d{2})?\s*(?:am|pm)|\d{1,2}:\d{2}))?$"#,
    options: [.caseInsensitive]
  )

  private static func fallback(_ title: String) -> CaptureResult {
    CaptureResult(title: title, dueDate: nil, hasTime: false, interpretation: nil)
  }

  private static func resolveDay(_ text: String, now: Date, calendar: Calendar) -> Date? {
    let start = calendar.startOfDay(for: now)
    if text == "today" { return start }
    if text == "tomorrow" { return calendar.date(byAdding: .day, value: 1, to: start) }

    let isNext = text.hasPrefix("next ")
    let weekdayName = isNext ? String(text.dropFirst(5)) : text
    let names = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
    guard let index = names.firstIndex(of: weekdayName) else { return nil }
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
}
