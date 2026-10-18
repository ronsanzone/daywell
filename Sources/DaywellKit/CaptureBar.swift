import DaywellCore
import Observation
import SwiftUI

/// State for the floating capture bar: the draft line and the quick list under it.
@MainActor @Observable public final class CaptureState {
  public var text = "" {
    didSet {
      if text.isEmpty {
        dateRemoved = false
        shelfOverrideID = nil
      }
    }
  }
  /// The user removed the date chip; save without a deadline.
  public var dateRemoved = false
  /// ⇥ picked a shelf explicitly.
  public var shelfOverrideID: String?
  /// nil while typing; an index into My Day while acting on the quick list.
  public var listIndex: Int?
  public private(set) var caught: [ReminderItem] = []
  public private(set) var saving = false

  @ObservationIgnored let model: DayModel

  public init(model: DayModel) { self.model = model }

  public var result: CaptureResult {
    CaptureParser.parse(text, now: model.now, calendar: model.calendar)
  }

  public var targetListID: String {
    shelfOverrideID ?? CaptureParser.resolveShelf(result.shelfQuery, in: model.lists)?.id
      ?? model.inboxListID
  }

  public var hasDraft: Bool { !text.trimmingCharacters(in: .whitespaces).isEmpty }

  /// ⇥ while typing: the next writable shelf.
  public func cycleShelf() {
    let lists = model.writableLists
    guard !lists.isEmpty else { return }
    let index = lists.firstIndex { $0.id == targetListID } ?? -1
    shelfOverrideID = lists[(index + 1) % lists.count].id
  }

  /// Saves the line. Returns true when Apple Reminders confirmed it.
  public func submit(addToDay: Bool) async -> Bool {
    let result = result
    guard hasDraft, !saving, !result.title.isEmpty else { return false }
    let submitted = text
    let listID = targetListID
    saving = true
    defer { saving = false }
    guard
      let item = await model.capture(
        result, listID: listID, keepDate: !dateRemoved, addToDay: addToDay)
    else { return false }
    // Don't wipe a line the user started typing while the save was in flight.
    if text == submitted { text = "" }
    caught.insert(item, at: 0)
    caught = Array(caught.prefix(3))
    Task { [weak self] in
      try? await Task.sleep(for: .seconds(4))
      self?.caught.removeAll { $0.id == item.id }
    }
    return true
  }
}

public struct CaptureBarView: View {
  @Bindable var capture: CaptureState
  @Bindable var model: DayModel
  @Bindable var preferences: Preferences
  let motion: MotionState
  @FocusState private var focused: Bool

  public static let width: CGFloat = 620

  public init(
    capture: CaptureState, model: DayModel, preferences: Preferences, motion: MotionState
  ) {
    self.capture = capture
    self.model = model
    self.preferences = preferences
    self.motion = motion
  }

  public var body: some View {
    let theme = preferences.profile
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 12) {
          Image(systemName: "plus.circle").font(.system(size: 18)).foregroundStyle(theme.accent)
          TextField("Catch something…", text: $capture.text)
            .textFieldStyle(.plain).font(theme.font(19)).focused($focused)
            .disabled(capture.listIndex != nil)
            .accessibilityLabel("Catch a reminder")
        }
        if capture.hasDraft { chips(theme) }
      }
      .padding(.horizontal, 18).padding(.vertical, 14)
      if !motion.displayedMyDay.isEmpty || !capture.caught.isEmpty {
        Rectangle().fill(theme.separator).frame(height: 1)
        quickList(theme)
      }
      Rectangle().fill(theme.separator).frame(height: 1)
      hints(theme).padding(.horizontal, 18).padding(.vertical, 9)
    }
    .frame(width: Self.width)
    .background(theme.background.opacity(0.97))
    .clipShape(RoundedRectangle(cornerRadius: 14))
    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(theme.separator))
    .foregroundStyle(theme.text)
    .environment(\.theme, theme)
    .environment(\.colorScheme, theme.scheme)
    .onAppear { focused = capture.listIndex == nil }
    .onChange(of: capture.listIndex) { _, index in focused = index == nil }
  }

  private func chips(_ theme: ThemeProfile) -> some View {
    let result = capture.result
    return HStack(spacing: 6) {
      if let due = result.dueDate, !capture.dateRemoved {
        Button {
          capture.dateRemoved = true
        } label: {
          Text(
            "\(due.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))\(result.hasTime ? " · " + due.formatted(date: .omitted, time: .shortened) : "")  ×"
          )
        }
        .buttonStyle(ChipStyle(kind: .date))
        .accessibilityLabel("Due date, remove")
      }
      ForEach(model.writableLists) { list in
        Button(list.title) { capture.shelfOverrideID = list.id }
          .buttonStyle(ChipStyle(kind: list.id == capture.targetListID ? .on : .off))
      }
      Spacer(minLength: 0)
    }
    .font(theme.font(12))
    .lineLimit(1)
  }

  private func quickList(_ theme: ThemeProfile) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      ForEach(capture.caught) { item in
        Text("Caught · \(item.title) → \(item.listName)").font(theme.font(12))
          .foregroundStyle(theme.secondary).padding(.horizontal, 8).padding(.vertical, 3)
          .transition(.move(edge: .top).combined(with: .opacity))
      }
      ForEach(Array(motion.displayedMyDay.enumerated()), id: \.element.id) { index, item in
        let finishing = motion.isFinishing(item.id)
        HStack(spacing: 10) {
          RingView(filled: item.isCompleted || finishing, ink: ink(theme, item), size: 14)
          Text(item.title).font(theme.font(13)).lineLimit(1)
            .strikethrough(finishing, color: theme.accent)
            .foregroundStyle(finishing ? theme.secondary : theme.text)
          Spacer()
          if model.today.pinnedID == item.id {
            Text("PIN").font(.system(size: 10, weight: .medium, design: .monospaced))
              .foregroundStyle(theme.accent)
          }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background {
          if capture.listIndex == index {
            RoundedRectangle(cornerRadius: 7).strokeBorder(theme.accent, lineWidth: 1.5)
          }
        }
      }
    }
    .padding(.horizontal, 10).padding(.vertical, 8)
    .animation(.easeOut(duration: 0.2), value: capture.caught.map(\.id))
  }

  private func ink(_ theme: ThemeProfile, _ item: ReminderItem) -> Color {
    theme.finish == .ink ? theme.ink(model.today.pile.count) : theme.accent
  }

  private func hints(_ theme: ThemeProfile) -> some View {
    HStack(spacing: 14) {
      if capture.listIndex != nil {
        KeyHint(keys: "x", label: "finish")
        KeyHint(keys: "p", label: "pin")
        KeyHint(keys: "r", label: "not today")
        KeyHint(keys: "⌘Z", label: "undo")
        KeyHint(keys: "esc", label: "back")
      } else if capture.hasDraft {
        KeyHint(keys: "↵", label: "save")
        KeyHint(keys: "⌥↵", label: "save to today")
        KeyHint(keys: "⇥", label: "shelf")
        KeyHint(keys: "/name", label: "shelf")
      } else {
        KeyHint(keys: "type", label: "to catch")
        KeyHint(keys: "↓", label: "act on today")
        KeyHint(keys: "⇥", label: "full panel")
      }
      Spacer()
    }
  }
}

struct ChipStyle: ButtonStyle {
  enum Kind { case date, on, off }
  let kind: Kind
  @Environment(\.theme) private var theme
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .padding(.horizontal, 8).padding(.vertical, 3)
      .foregroundStyle(kind == .on ? theme.background : (kind == .date ? theme.highlight : theme.secondary))
      .background(background, in: RoundedRectangle(cornerRadius: 6))
      .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(border))
      .opacity(configuration.isPressed ? 0.7 : 1)
  }
  private var background: Color {
    switch kind {
    case .date: theme.accent.opacity(0.18)
    case .on: theme.highlight
    case .off: .clear
    }
  }
  private var border: Color {
    switch kind {
    case .date: theme.accent.opacity(0.45)
    case .on: .clear
    case .off: theme.separator
    }
  }
}

/// Keys for the capture bar. Returns true when used.
@MainActor public struct CaptureKeys {
  let capture: CaptureState
  let model: DayModel
  let close: () -> Void
  let openPanel: (_ reminderID: String?) -> Void
  let saved: () -> Void

  public init(
    capture: CaptureState, model: DayModel, close: @escaping () -> Void,
    openPanel: @escaping (_ reminderID: String?) -> Void, saved: @escaping () -> Void
  ) {
    self.capture = capture
    self.model = model
    self.close = close
    self.openPanel = openPanel
    self.saved = saved
  }

  public func handle(_ key: KeyInput) -> Bool {
    let myDay = model.today.myDay
    if let index = capture.listIndex {
      return handleList(key, index: index, myDay: myDay)
    }
    switch key.special {
    case .escape:
      close()
      return true
    case .enter:
      guard capture.hasDraft else { return true }
      let addToDay = key.option
      Task {
        if await capture.submit(addToDay: addToDay) { saved() }
      }
      return true
    case .tab:
      if capture.hasDraft { capture.cycleShelf() } else { openPanel(nil) }
      return true
    case .down:
      guard !myDay.isEmpty else { return false }
      capture.listIndex = 0
      return true
    default: break
    }
    if key.control && key.characters == "n" && !myDay.isEmpty {
      capture.listIndex = 0
      return true
    }
    if key.command && key.characters == "z" && !capture.hasDraft {
      Task { await model.undoLast() }
      return true
    }
    return false
  }

  private func handleList(_ key: KeyInput, index: Int, myDay: [ReminderItem]) -> Bool {
    guard !myDay.isEmpty else {
      capture.listIndex = nil
      return false
    }
    let id = myDay[min(index, myDay.count - 1)].id
    switch key.special {
    case .escape:
      capture.listIndex = nil
      return true
    case .up:
      capture.listIndex = index == 0 ? nil : index - 1
      return true
    case .down:
      capture.listIndex = min(index + 1, myDay.count - 1)
      return true
    case .enter:
      openPanel(id)
      return true
    case .tab:
      openPanel(nil)
      return true
    default: break
    }
    if key.command && key.characters == "z" {
      Task { await model.undoLast() }
      return true
    }
    if key.control && key.characters == "p" {
      capture.listIndex = index == 0 ? nil : index - 1
      return true
    }
    if key.control && key.characters == "n" {
      capture.listIndex = min(index + 1, myDay.count - 1)
      return true
    }
    switch key.characters {
    case "j": capture.listIndex = min(index + 1, myDay.count - 1)
    case "k": capture.listIndex = index == 0 ? nil : index - 1
    case "x", " ": Task { await model.toggleCompletion(id) }
    case "p": model.pin(id)
    case "r": model.release(id)
    default: return true  // Letters never fall through into the hidden text field.
    }
    return true
  }
}
