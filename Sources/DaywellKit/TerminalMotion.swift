import SwiftUI

/// A decorative instrument, deliberately unrelated to task counts or network state.
struct OrbitalRelay: View {
  let active: Bool
  let color: Color
  @State private var opened = Date()

  static func angle(at elapsed: Double) -> Double {
    if elapsed < 0.7 { return -90 * (1 - eased(elapsed / 0.7)) }
    // Four seconds resting, three drifting, five resting. Each cycle aligns again.
    let phase = (elapsed - 0.7).truncatingRemainder(dividingBy: 12)
    return 360 * eased((phase - 4) / 3)
  }

  private static func eased(_ value: Double) -> Double {
    let t = min(1, max(0, value))
    return t * t * (3 - 2 * t)
  }

  var body: some View {
    Group {
      if active {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
          instrument(angle: Self.angle(at: context.date.timeIntervalSince(opened)))
        }
      } else {
        instrument(angle: 0)
      }
    }
    .frame(width: 40, height: 40)
    .background(color.opacity(0.04), in: RoundedRectangle(cornerRadius: 4))
    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(color.opacity(0.22)))
    .onChange(of: active) { _, enabled in if enabled { opened = Date() } }
    .accessibilityHidden(true)
    .allowsHitTesting(false)
  }

  private func instrument(angle: Double) -> some View {
    Canvas { context, size in
      let center = CGPoint(x: size.width / 2, y: size.height / 2)
      for (radius, rotation) in [(15.0, angle), (10.0, -2 * angle)] {
        for offset in [0.0, 180.0] {
          var arc = Path()
          arc.addArc(
            center: center, radius: radius,
            startAngle: .degrees(rotation + offset + 15),
            endAngle: .degrees(rotation + offset + 150), clockwise: false)
          context.stroke(arc, with: .color(color.opacity(radius == 15 ? 0.8 : 0.45)), lineWidth: 1)
        }
      }
      var cross = Path()
      cross.move(to: CGPoint(x: 16, y: 20))
      cross.addLine(to: CGPoint(x: 24, y: 20))
      cross.move(to: CGPoint(x: 20, y: 16))
      cross.addLine(to: CGPoint(x: 20, y: 24))
      context.stroke(cross, with: .color(color.opacity(0.65)), lineWidth: 1)
      let radians = angle * .pi / 180
      let dot = CGRect(x: 19 + cos(radians) * 15, y: 19 + sin(radians) * 15, width: 2, height: 2)
      context.fill(Path(ellipseIn: dot), with: .color(color))
    }
  }
}

struct PhosphorSelection: View {
  let selected: Bool
  let active: Bool
  let color: Color
  let intensity: Double
  @State private var departed: Date?

  var body: some View {
    ZStack {
      if selected { outline(opacity: 1) }
      if active, let departed, !selected {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
          outline(opacity: max(0, 1 - context.date.timeIntervalSince(departed) / 0.22) * 0.65)
        }
      }
    }
    .onChange(of: selected) { old, new in
      departed = active && old && !new ? Date() : nil
    }
    .onChange(of: active) { _, _ in departed = nil }
    .task(id: departed) {
      guard departed != nil else { return }
      do {
        try await Task.sleep(for: .milliseconds(230))
        departed = nil
      } catch {
        // Leaving the row cancels its short-lived trail.
      }
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  private func outline(opacity: Double) -> some View {
    RoundedRectangle(cornerRadius: 6).strokeBorder(color.opacity(opacity), lineWidth: 1)
      .shadow(color: color.opacity(opacity * intensity * 0.8), radius: intensity * 5)
  }
}

struct MotionFrames: PreferenceKey {
  static let defaultValue: [String: CGRect] = [:]
  static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
    value.merge(nextValue(), uniquingKeysWith: { _, new in new })
  }
}

extension View {
  func motionFrame(_ key: String) -> some View {
    background {
      GeometryReader { geometry in
        Color.clear.preference(
          key: MotionFrames.self, value: [key: geometry.frame(in: .named("daywell-panel"))])
      }
    }
  }
}

/// The real row updates immediately. This noninteractive trace exists only after a confirmed write.
struct ReminderFlight: View {
  let feedback: ReminderFeedback
  let start: CGPoint
  let end: CGPoint
  let palette: Palette
  let finished: () -> Void
  @State private var began = Date()

  var body: some View {
    TimelineView(.animation(minimumInterval: 1.0 / 60)) { context in
      let t = min(1, max(0, (context.date.timeIntervalSince(began) - 0.1) / 0.55))
      let progress = t * t * (3 - 2 * t)
      let path = Path { path in
        path.move(to: start)
        if feedback.kind == .chosen {
          let middle = (start.x + end.x) / 2
          path.addLine(to: CGPoint(x: middle, y: start.y))
          path.addLine(to: CGPoint(x: middle, y: end.y))
        }
        path.addLine(to: end)
      }
      let position = path.trimmedPath(from: 0, to: progress).currentPoint ?? start
      ZStack(alignment: .topLeading) {
        if feedback.kind == .chosen {
          path.stroke(palette.accent.opacity(0.3 * (1 - progress)), lineWidth: 1)
        }
        path
          .trim(from: max(0, progress - 0.3), to: progress)
          .stroke(palette.accent.opacity(0.85), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
          .shadow(color: palette.accent, radius: 5)
        if feedback.kind == .chosen {
          Circle().fill(palette.accent).frame(width: 6, height: 6)
            .shadow(color: palette.accent, radius: 7)
            .position(position).opacity(1 - pow(progress, 8))
        } else {
          HStack(spacing: 7) {
            Image(
              systemName: feedback.kind == .completed
                ? "checkmark.circle.fill" : "arrow.uturn.backward")
            Text(feedback.reminder.title).lineLimit(1)
          }
          .font(.system(size: 12, design: .monospaced))
          .padding(.horizontal, 10).padding(.vertical, 7)
          .foregroundStyle(palette.accent)
          .background(palette.background, in: RoundedRectangle(cornerRadius: 5))
          .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(palette.accent.opacity(0.8)))
          .frame(maxWidth: 240)
          .scaleEffect(feedback.kind == .completed ? 1 - progress * 0.65 : 0.4 + progress * 0.6)
          .opacity(1 - pow(progress, 4)).position(position)
        }
      }
    }
    .task {
      do {
        try await Task.sleep(for: .milliseconds(700))
        finished()
      } catch {
        // Closing the panel or disabling motion cancels feedback.
      }
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}
