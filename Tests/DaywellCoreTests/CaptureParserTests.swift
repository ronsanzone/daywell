import Foundation
import Testing

@testable import DaywellCore

struct CaptureParserTests {
  private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    calendar.locale = Locale(identifier: "en_US_POSIX")
    return calendar
  }()

  private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 10, _ minute: Int = 0)
    -> Date
  {
    calendar.date(
      from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
  }

  @Test func plainTitleIsTrimmedAndUninterpreted() {
    let result = CaptureParser.parse(
      "  Discuss Friday launch notes  ", now: date(2026, 9, 18), calendar: calendar)
    #expect(
      result
        == CaptureResult(
          title: "Discuss Friday launch notes", dueDate: nil, hasTime: false, interpretation: nil))
  }

  @Test func parsesTomorrowWithTimeAcrossYearBoundary() {
    let result = CaptureParser.parse(
      "Call dentist tomorrow at 2pm", now: date(2026, 12, 31, 23), calendar: calendar)
    #expect(result.title == "Call dentist")
    #expect(result.dueDate == date(2027, 1, 1, 14))
    #expect(result.hasTime)
    #expect(result.interpretation != nil)
  }

  @Test func dateOnlyTomorrowUsesStartOfDaySemantics() {
    let result = CaptureParser.parse(
      "Renew pass tomorrow", now: date(2026, 9, 18), calendar: calendar)
    #expect(result.title == "Renew pass")
    #expect(result.dueDate == date(2026, 9, 19, 0))
    #expect(!result.hasTime)
  }

  @Test func todaySupportsTwentyFourHourTimeAtBoundary() {
    let result = CaptureParser.parse(
      "Deploy today at 23:59", now: date(2026, 9, 18), calendar: calendar)
    #expect(result.title == "Deploy")
    #expect(result.dueDate == date(2026, 9, 18, 23, 59))
    #expect(result.hasTime)
  }

  @Test func weekdayMeansNextOccurrenceIncludingToday() {
    let today = CaptureParser.parse(
      "Send report friday", now: date(2026, 9, 18), calendar: calendar)
    let next = CaptureParser.parse(
      "Send report next Friday at 2:30pm", now: date(2026, 9, 18), calendar: calendar)
    #expect(today.dueDate == date(2026, 9, 18, 0))
    #expect(next.dueDate == date(2026, 9, 25, 14, 30))
  }

  @Test func noonAndMidnightAreDistinct() {
    let noon = CaptureParser.parse(
      "Lunch tomorrow at noon", now: date(2026, 9, 18), calendar: calendar)
    let midnight = CaptureParser.parse(
      "Backup tomorrow at midnight", now: date(2026, 9, 18), calendar: calendar)
    #expect(noon.dueDate == date(2026, 9, 19, 12))
    #expect(midnight.dueDate == date(2026, 9, 19, 0))
  }

  @Test func invalidTimeFallsBackWithoutPartialStripping() {
    for input in ["Call tomorrow at 13pm", "Call tomorrow at 25:00", "Call tomorrow at 2:60pm"] {
      let result = CaptureParser.parse(input, now: date(2026, 9, 18), calendar: calendar)
      #expect(result.title == input)
      #expect(result.dueDate == nil)
    }
  }

  @Test func emptyTitleAfterSuffixFallsBackToLiteral() {
    let result = CaptureParser.parse("tomorrow at 2pm", now: date(2026, 9, 18), calendar: calendar)
    #expect(result.title == "tomorrow at 2pm")
    #expect(result.dueDate == nil)
  }

  @Test func calendarArithmeticSurvivesSpringDSTChange() {
    let result = CaptureParser.parse(
      "Walk tomorrow at noon", now: date(2026, 3, 7, 20), calendar: calendar)
    #expect(result.dueDate == date(2026, 3, 8, 12))
  }

  @Test func nonexistentDSTTimeFallsBackToLiteral() {
    let input = "Wake tomorrow at 2:30am"
    let result = CaptureParser.parse(input, now: date(2026, 3, 7, 20), calendar: calendar)
    #expect(result.title == input)
    #expect(result.dueDate == nil)
  }

  @Test func ambiguousDSTTimeFallsBackToLiteral() {
    let input = "Wake tomorrow at 1:30am"
    let result = CaptureParser.parse(input, now: date(2026, 10, 31, 20), calendar: calendar)
    #expect(result.title == input)
    #expect(result.dueDate == nil)
  }

  @Test func halfHourDSTOverlapAlsoFallsBack() {
    var lordHowe = Calendar(identifier: .gregorian)
    lordHowe.timeZone = TimeZone(identifier: "Australia/Lord_Howe")!
    let now = lordHowe.date(from: DateComponents(year: 2026, month: 4, day: 4, hour: 12))!
    let input = "Wake tomorrow at 1:45am"
    let result = CaptureParser.parse(input, now: now, calendar: lordHowe)
    #expect(result.dueDate == nil)
    #expect(result.title == input)
  }
}
