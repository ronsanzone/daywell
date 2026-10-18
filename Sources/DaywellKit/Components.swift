import DaywellCore
import SwiftUI

/// The completion ring. Each theme fills it its own way; timing is shared (~300 ms).
struct RingView: View {
  @Environment(\.theme) private var theme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let filled: Bool
  var ink: Color?
  var size: CGFloat = 16
  @ViewState private var pop: CGFloat = 1

  var body: some View {
    let color = ink ?? theme.accent
    ZStack {
      shape.strokeBorder(filled ? color : theme.secondary, lineWidth: 1.5)
      shape.fill(color).scaleEffect(filled ? 1 : 0.2).opacity(filled ? 1 : 0)
      Check().trim(from: 0, to: filled ? 1 : 0)
        .stroke(theme.background, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
        .padding(size * 0.24)
    }
    .frame(width: size, height: size)
    .shadow(color: theme.finish == .flare && filled ? color.opacity(0.9) : .clear, radius: 5)
    .animation(reduceMotion ? nil : animation, value: filled)
    .scaleEffect(pop)
    .onChange(of: filled) { _, isFilled in
      guard isFilled, !reduceMotion, theme.finish != .flare else { return }
      withAnimation(.spring(response: 0.12, dampingFraction: 0.5)) { pop = 1.25 }
      withAnimation(.spring(response: 0.22, dampingFraction: 0.7).delay(0.12)) { pop = 1 }
    }
    .accessibilityHidden(true)
  }

  private var shape: AnyInsettableShape {
    theme.ring == .square
      ? AnyInsettableShape(RoundedRectangle(cornerRadius: 2)) : AnyInsettableShape(Circle())
  }

  private var animation: Animation {
    switch theme.finish {
    case .spring, .ink: .spring(response: 0.26, dampingFraction: 0.62)
    case .flare: .easeOut(duration: 0.18)
    }
  }
}

struct Check: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.05))
    path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.maxY - rect.height * 0.1))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.1))
    return path
  }
}

/// Type-erased insettable shape so a theme can switch ring geometry.
struct AnyInsettableShape: InsettableShape {
  private let pathBuilder: @Sendable (CGRect) -> Path
  private let insetBuilder: @Sendable (CGFloat) -> AnyInsettableShape
  init<S: InsettableShape & Sendable>(_ shape: S) {
    pathBuilder = { shape.path(in: $0) }
    insetBuilder = { AnyInsettableShape(shape.inset(by: $0)) }
  }
  func path(in rect: CGRect) -> Path { pathBuilder(rect) }
  func inset(by amount: CGFloat) -> AnyInsettableShape { insetBuilder(amount) }
}

/// One object on today's pile.
struct PileToken: View {
  @Environment(\.theme) private var theme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let index: Int
  let fresh: Bool

  var body: some View {
    let color = theme.finish == .ink ? theme.ink(index) : (fresh ? theme.highlight : theme.accent)
    Group {
      switch theme.token {
      case .roundedSquare: RoundedRectangle(cornerRadius: 4).fill(color).frame(width: 16, height: 16)
      case .bar:
        Rectangle().fill(color).frame(width: 8, height: 16)
          .shadow(color: color.opacity(0.8), radius: fresh ? 6 : 3)
      case .dot: Circle().fill(color).frame(width: 14, height: 14)
      }
    }
    .overlay {
      if fresh && theme.token != .bar {
        RoundedRectangle(cornerRadius: theme.token == .dot ? 9 : 6)
          .stroke(color.opacity(0.35), lineWidth: 3).padding(-3)
      }
    }
    .transition(
      reduceMotion
        ? .opacity
        : .asymmetric(
          insertion: .modifier(
            active: DropModifier(offset: -18, scale: 0.6, opacity: 0),
            identity: DropModifier(offset: 0, scale: 1, opacity: 1)),
          removal: .opacity))
  }
}

private struct DropModifier: ViewModifier {
  let offset: CGFloat
  let scale: CGFloat
  let opacity: Double
  func body(content: Content) -> some View {
    content.offset(y: offset).scaleEffect(scale).opacity(opacity)
  }
}

/// Small rounded key glyph used in hints.
struct KeyHint: View {
  @Environment(\.theme) private var theme
  let keys: String
  let label: String
  var body: some View {
    HStack(spacing: 4) {
      Text(keys).font(.system(size: 10.5, weight: .medium, design: .monospaced))
        .padding(.horizontal, 4).padding(.vertical, 1)
        .background(theme.raised, in: RoundedRectangle(cornerRadius: 3))
      Text(label).font(theme.font(11)).foregroundStyle(theme.secondary)
    }
  }
}
