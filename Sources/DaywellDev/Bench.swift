import DaywellCore
import DaywellFixtures
import DaywellKit
import Foundation

/// Measures the data path the ticker and panel depend on, with years of completed history.
@MainActor enum Bench {
  static func run() {
    let now = Date()
    let calendar = Calendar.current
    let startOfDay = calendar.startOfDay(for: now)
    for history in [0, 5_000, 20_000] {
      let (store, plan) = Fixtures.demo(now: now, history: history)
      let everything = store.items
      // What the old fetch loaded: every reminder ever, including all completed history.
      let narrow = everything.filter {
        !$0.isCompleted || ($0.completionDate.map { $0 >= startOfDay } ?? false)
      }
      let old = median {
        _ = Today.build(
          plan: plan, reminders: everything, lists: store.lists, now: now, calendar: calendar)
      }
      let new = median {
        _ = Today.build(
          plan: plan, reminders: narrow, lists: store.lists, now: now, calendar: calendar)
      }
      print(
        "BENCH history=\(history): old fetch maps \(everything.count) reminders, projection \(format(old)); new fetch maps \(narrow.count), projection \(format(new))"
      )
    }
  }

  static func median(_ body: () -> Void) -> Duration {
    let clock = ContinuousClock()
    var samples: [Duration] = []
    for _ in 0..<25 {
      let start = clock.now
      body()
      samples.append(clock.now - start)
    }
    return samples.sorted()[samples.count / 2]
  }

  static func format(_ duration: Duration) -> String {
    let ms =
      Double(duration.components.attoseconds) / 1e15 + Double(duration.components.seconds) * 1000
    return String(format: "%.3f ms", ms)
  }
}
