import Carbon
import DaywellCore
import SwiftUI

// MARK: Morning pull

struct MorningView: View {
  @Bindable var model: DayModel
  @Bindable var panel: PanelState
  @Environment(\.theme) private var theme

  var body: some View {
    let flat = panel.morningFlat
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline) {
        Text(greeting).font(theme.font(20, .bold))
        Spacer()
        KeyHint(keys: "esc", label: "skip")
      }
      Text("Pick a few. The rest stay where they are.").font(theme.font(13))
        .foregroundStyle(theme.secondary)
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          ForEach(panel.morningChoices, id: \.section) { section in
            VStack(alignment: .leading, spacing: 6) {
              Text(section.section.uppercased())
                .font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(1.2)
                .foregroundStyle(theme.secondary)
              FlowLayout(spacing: 6) {
                ForEach(section.items) { item in
                  let index = flat.firstIndex { $0.id == item.id } ?? 0
                  Chip(
                    title: item.title, picked: panel.morningPicks.contains(item.id),
                    focused: panel.morningIndex == index, number: index + 1
                  ) {
                    panel.morningIndex = index
                    panel.toggleMorningPick(item.id)
                  }
                }
              }
            }
          }
        }
      }
      HStack {
        Text(
          panel.morningPicks.isEmpty
            ? "Nothing picked yet" : "\(panel.morningPicks.count) for today"
        )
        .font(theme.font(12)).foregroundStyle(theme.accent)
        .contentTransition(.numericText())
        Spacer()
        Button("Start the day ↵") {
          model.startDay(picking: panel.morningPicks)
          panel.route = .today
        }
        .buttonStyle(.borderedProminent)
      }
    }
    .padding(18)
    .animation(.snappy(duration: 0.18), value: panel.morningPicks)
  }

  private var greeting: String {
    let hour = Calendar.current.component(.hour, from: model.now)
    return hour < 12 ? "Good morning" : (hour < 17 ? "Good afternoon" : "Good evening")
  }
}

struct Chip: View {
  let title: String
  let picked: Bool
  let focused: Bool
  let number: Int
  let action: () -> Void
  @Environment(\.theme) private var theme

  var body: some View {
    Button(action: action) {
      HStack(spacing: 6) {
        if number <= 9 {
          Text("\(number)").font(.system(size: 10, design: .monospaced))
            .foregroundStyle(picked ? theme.background.opacity(0.7) : theme.secondary)
        }
        Text(title + (picked ? " ✓" : "")).font(theme.font(13)).lineLimit(1)
      }
      .padding(.horizontal, 10).padding(.vertical, 6)
      .foregroundStyle(picked ? theme.background : theme.text)
      .background(picked ? theme.highlight : .clear, in: RoundedRectangle(cornerRadius: 7))
      .overlay(
        RoundedRectangle(cornerRadius: 7).strokeBorder(
          focused ? theme.accent : theme.separator, lineWidth: focused ? 1.5 : 1))
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(picked ? .isSelected : [])
  }
}

/// Wraps chips onto as many lines as needed.
struct FlowLayout: Layout {
  var spacing: CGFloat = 6
  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    arrange(proposal: proposal, subviews: subviews).size
  }
  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    for (index, point) in arrange(proposal: proposal, subviews: subviews).points.enumerated() {
      subviews[index].place(
        at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
    }
  }
  private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (
    size: CGSize, points: [CGPoint]
  ) {
    let width = proposal.width ?? .infinity
    var points: [CGPoint] = []
    var x: CGFloat = 0
    var y: CGFloat = 0
    var line: CGFloat = 0
    var used: CGFloat = 0
    for subview in subviews {
      let size = subview.sizeThatFits(.unspecified)
      if x > 0, x + size.width > width {
        x = 0
        y += line + spacing
        line = 0
      }
      points.append(CGPoint(x: x, y: y))
      x += size.width + spacing
      used = max(used, x - spacing)
      line = max(line, size.height)
    }
    return (CGSize(width: min(used, width), height: y + line), points)
  }
}

// MARK: Move to shelf / new shelf

struct MoveView: View {
  @Bindable var model: DayModel
  @Bindable var panel: PanelState
  let reminderID: String
  @Environment(\.theme) private var theme
  @FocusState private var naming: Bool

  var body: some View {
    let lists = model.writableLists
    VStack(alignment: .leading, spacing: 10) {
      Text(reminderID.isEmpty ? "New shelf" : "Move to shelf").font(theme.font(18, .bold))
      if let item = model.reminder(reminderID) {
        Text(item.title).font(theme.font(13)).foregroundStyle(theme.secondary).lineLimit(1)
      }
      if !reminderID.isEmpty {
        ForEach(Array(lists.enumerated()), id: \.element.id) { index, list in
          Button {
            Task { await model.move(reminderID, toList: list.id) }
            panel.route = .today
          } label: {
            HStack {
              Text(list.title).font(theme.font(14))
              Spacer()
              if model.reminder(reminderID)?.listID == list.id {
                Text("here").font(theme.font(11)).foregroundStyle(theme.secondary)
              }
            }
            .padding(9)
            .overlay(
              RoundedRectangle(cornerRadius: 7).strokeBorder(
                panel.moveIndex == index ? theme.accent : .clear, lineWidth: 1.5)
            )
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
        }
      }
      HStack {
        Image(systemName: "plus").foregroundStyle(theme.secondary)
        TextField("New shelf name", text: $panel.newShelfName).textFieldStyle(.plain)
          .font(theme.font(14)).focused($naming)
      }
      .padding(9)
      .overlay(
        RoundedRectangle(cornerRadius: 7).strokeBorder(
          panel.moveIndex >= lists.count || reminderID.isEmpty ? theme.accent : theme.separator,
          lineWidth: 1.5))
      Text("Shelves are Reminders lists, so your iPhone and Siri see them too.")
        .font(theme.font(11)).foregroundStyle(theme.secondary)
      Spacer()
    }
    .padding(18)
    .onAppear { if reminderID.isEmpty { naming = true } }
    .onChange(of: panel.moveIndex) { _, index in naming = index >= lists.count }
  }
}

// MARK: Browse

struct BrowseView: View {
  @Bindable var model: DayModel
  @Bindable var panel: PanelState
  @Environment(\.theme) private var theme
  @FocusState private var searching: Bool

  private var results: [ReminderItem] {
    let query = panel.search
    return model.reminders.filter {
      !$0.isCompleted
        && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)
          || $0.notes.localizedCaseInsensitiveContains(query))
    }
    .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Image(systemName: "magnifyingglass").foregroundStyle(theme.secondary)
        TextField("Search reminders", text: $panel.search).textFieldStyle(.plain)
          .font(theme.font(14)).focused($searching)
      }
      .padding(10).background(theme.raised, in: RoundedRectangle(cornerRadius: 8))
      ScrollView {
        VStack(alignment: .leading, spacing: 2) {
          ForEach(results) { item in
            HStack {
              Text(item.title).font(theme.font(14)).lineLimit(1)
              Spacer()
              Text(item.listName).font(theme.font(11)).foregroundStyle(theme.secondary)
              Button(model.isChosen(item.id) ? "Today ✓" : "Pull") { model.choose(item.id) }
                .font(theme.font(11)).disabled(model.isChosen(item.id))
            }
            .padding(.vertical, 5)
          }
        }
      }
      KeyHint(keys: "esc", label: "back")
    }
    .padding(18)
    .onAppear { searching = true }
  }
}

// MARK: Command palette and help

struct CommandPaletteView: View {
  @Bindable var model: DayModel
  @Bindable var panel: PanelState
  let shell: ShellActions
  @Environment(\.theme) private var theme
  @FocusState private var searching: Bool

  var body: some View {
    let commands = DaywellCommand.matching(panel.commandQuery)
    VStack(spacing: 10) {
      HStack {
        Image(systemName: "command").foregroundStyle(theme.secondary)
        TextField("Search commands", text: $panel.commandQuery).textFieldStyle(.plain)
          .font(theme.font(14)).focused($searching)
      }
      .padding(10).background(theme.raised, in: RoundedRectangle(cornerRadius: 8))
      ScrollView {
        VStack(spacing: 2) {
          ForEach(Array(commands.enumerated()), id: \.element.id) { offset, command in
            Button {
              panel.route = .today
              command.perform(model, panel, shell)
            } label: {
              HStack(spacing: 12) {
                Image(systemName: command.symbol).frame(width: 18)
                Text(command.title).font(theme.font(13))
                Spacer()
                Text(command.shortcut).font(.system(size: 11, design: .monospaced))
                  .foregroundStyle(theme.secondary)
              }
              .padding(9)
              .background(
                panel.commandIndex == offset ? theme.raised : .clear,
                in: RoundedRectangle(cornerRadius: 6)
              )
              .opacity(command.isEnabled(model, panel) ? 1 : 0.45)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain).disabled(!command.isEnabled(model, panel))
          }
        }
      }
    }
    .padding(16)
    .onAppear {
      panel.commandQuery = ""
      panel.commandIndex = 0
      searching = true
    }
    .onChange(of: panel.commandQuery) { _, _ in panel.commandIndex = 0 }
  }
}

struct HelpView: View {
  @Bindable var panel: PanelState
  @Environment(\.theme) private var theme
  private let groups: [(String, [(String, String)])] = [
    (
      "Anywhere",
      [("⌃⌥Space", "Catch something; ↓ acts on today; ⇥ opens this panel")]
    ),
    (
      "Today",
      [
        ("j k ↑ ↓", "Move"), ("gg G", "First, last"), ("x / space", "Finish or reopen"),
        ("p", "Pin to the menu bar"), ("a", "Pull into My Day"), ("r", "Not today"),
        ("m", "Move to another shelf"), ("l h", "Open, close a shelf"),
        ("⌥↑ ⌥↓", "Reorder My Day"), ("s", "Open or close all shelves"), ("↵ e", "Edit"),
        ("⌘Z", "Undo"), ("⌘K", "Commands"), ("⌘F", "Search"), ("esc", "Back, then close"),
      ]
    ),
  ]
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        Text("Keyboard").font(theme.font(18, .bold))
        ForEach(groups, id: \.0) { group in
          VStack(alignment: .leading, spacing: 6) {
            Text(group.0.uppercased()).font(.system(size: 10, weight: .medium, design: .monospaced))
              .tracking(1.2).foregroundStyle(theme.secondary)
            ForEach(group.1, id: \.0) { key, action in
              HStack(alignment: .top) {
                Text(key).font(.system(size: 12, design: .monospaced)).frame(
                  width: 96, alignment: .leading)
                Text(action).font(theme.font(13))
              }
            }
          }
        }
      }
      .padding(18)
    }
  }
}

// MARK: Editor

struct EditorView: View {
  @Bindable var model: DayModel
  @Bindable var panel: PanelState
  let original: ReminderItem
  @Environment(\.theme) private var theme
  @ViewState private var draft: ReminderItem
  @ViewState private var hasDate: Bool
  @ViewState private var date: Date
  @ViewState private var confirmingDelete = false

  init(model: DayModel, panel: PanelState, original: ReminderItem) {
    self.model = model
    self.panel = panel
    self.original = original
    _draft = ViewState(initialValue: original)
    _hasDate = ViewState(initialValue: original.dueDate != nil)
    _date = ViewState(initialValue: original.dueDate ?? model.now)
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        TextField("Title", text: $draft.title).textFieldStyle(.roundedBorder)
        Text("Notes").font(theme.font(12)).foregroundStyle(theme.secondary)
        TextEditor(text: $draft.notes).font(theme.font(13)).frame(height: 90)
          .scrollContentBackground(.hidden).padding(6)
          .background(theme.raised, in: RoundedRectangle(cornerRadius: 6))
        Picker("Shelf", selection: $draft.listID) {
          ForEach(model.writableLists) { Text($0.title).tag($0.id) }
        }
        Toggle("Due date", isOn: $hasDate)
        if hasDate {
          DatePicker("Date", selection: $date, displayedComponents: .date)
          Toggle("Include time", isOn: $draft.hasDueTime)
          if draft.hasDueTime {
            DatePicker("Time", selection: $date, displayedComponents: .hourAndMinute)
          }
        }
        HStack {
          Button("Cancel") { panel.route = .today }
          Spacer()
          Button("Save") {
            var value = draft
            value.dueDate = hasDate ? date : nil
            if !hasDate { value.hasDueTime = false }
            value.listName = model.lists.first { $0.id == value.listID }?.title ?? value.listName
            Task {
              if await model.saveEdit(value, original: original) { panel.route = .today }
            }
          }
          .buttonStyle(.borderedProminent).keyboardShortcut(.return, modifiers: .command)
          .disabled(
            !model.canWrite(original.id)
              || draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        Divider()
        if confirmingDelete {
          HStack {
            Text("Delete from Apple Reminders?").font(theme.font(12))
            Spacer()
            Button("Keep") { confirmingDelete = false }
            Button("Delete", role: .destructive) {
              Task { if await model.delete(original) { panel.route = .today } }
            }
          }
        } else {
          Button("Delete reminder…", role: .destructive) { confirmingDelete = true }
            .font(theme.font(12)).disabled(!model.canWrite(original.id))
        }
      }
      .padding(18)
    }
  }
}

// MARK: Settings

struct SettingsView: View {
  @Bindable var model: DayModel
  @Bindable var panel: PanelState
  @Bindable var preferences: Preferences
  @Environment(\.theme) private var theme
  @ViewState private var recording = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        VStack(alignment: .leading, spacing: 8) {
          Text("Theme").font(theme.font(13, .semibold))
          ForEach(ThemeID.allCases) { id in
            let profile = ThemeProfile.named(id)
            Button {
              preferences.theme = id
            } label: {
              HStack(spacing: 10) {
                Circle().fill(profile.background)
                  .overlay(Circle().strokeBorder(profile.accent, lineWidth: 3))
                  .frame(width: 20, height: 20)
                VStack(alignment: .leading, spacing: 1) {
                  Text(profile.title).font(theme.font(13))
                  Text(profile.summary).font(theme.font(11)).foregroundStyle(theme.secondary)
                }
                Spacer()
                if id == preferences.theme { Image(systemName: "checkmark") }
              }
              .padding(8)
              .background(
                id == preferences.theme ? theme.raised : .clear,
                in: RoundedRectangle(cornerRadius: 7)
              )
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
          }
          if preferences.theme == .phosphor {
            HStack {
              Text("CRT intensity").font(theme.font(12))
              Slider(value: $preferences.crtIntensity, in: 0...1, step: 0.05)
            }
          }
        }
        Toggle("Sounds when you finish", isOn: $preferences.soundEnabled).font(theme.font(12))
        Toggle("Show the current task in the menu bar", isOn: $preferences.tickerShowsTask)
          .font(theme.font(12))
        Toggle(
          "⌃⌥X finishes the menu-bar task from anywhere", isOn: $preferences.finishHotKeyEnabled
        )
        .font(theme.font(12))
        Picker("Catch into", selection: $preferences.inboxID) {
          Text("Reminders default").tag("")
          ForEach(model.writableLists) { Text($0.title).tag($0.id) }
        }
        .font(theme.font(12))
        VStack(alignment: .leading, spacing: 8) {
          Text("Capture shortcut").font(theme.font(13, .semibold))
          Button(recording ? "Press a shortcut…" : "Record shortcut") { recording = true }
          if recording {
            ShortcutRecorder(preferences: preferences, recording: $recording).frame(height: 1)
          }
          Button("Restore ⌃⌥Space") {
            preferences.shortcutKey = 49
            preferences.shortcutModifiers = 6144
          }
          .font(theme.font(11))
        }
        Text(
          "Your day plan stays on this Mac. Apple Reminders keeps your tasks, lists and alerts."
        )
        .font(theme.font(11)).foregroundStyle(theme.secondary)
        Button("Quit Daywell") { NSApplication.shared.terminate(nil) }.font(theme.font(12))
      }
      .padding(18)
    }
  }
}

struct ShortcutRecorder: NSViewRepresentable {
  let preferences: Preferences
  @Binding var recording: Bool
  func makeNSView(context: Context) -> RecorderView {
    let view = RecorderView()
    view.record = { event in
      if event.keyCode == 53 {
        recording = false
        return
      }
      let flags = event.modifierFlags
      guard !flags.intersection([.command, .control, .option]).isEmpty else { return }
      var modifiers = 0
      if flags.contains(.command) { modifiers |= cmdKey }
      if flags.contains(.control) { modifiers |= controlKey }
      if flags.contains(.option) { modifiers |= optionKey }
      if flags.contains(.shift) { modifiers |= shiftKey }
      preferences.shortcutKey = Int(event.keyCode)
      preferences.shortcutModifiers = modifiers
      recording = false
    }
    return view
  }
  func updateNSView(_ view: RecorderView, context: Context) {
    DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
  }
}

public final class RecorderView: NSView {
  var record: ((NSEvent) -> Void)?
  public override var acceptsFirstResponder: Bool { true }
  public override func keyDown(with event: NSEvent) { record?(event) }
  public override func performKeyEquivalent(with event: NSEvent) -> Bool {
    record?(event)
    return true
  }
}

// MARK: Sort a list into shelves

struct SortView: View {
  @Bindable var model: DayModel
  @Bindable var panel: PanelState
  let listID: String
  @Environment(\.theme) private var theme

  var body: some View {
    let targets = panel.sortTargets(from: listID)
    let total = panel.sortDone + panel.sortQueue.count
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .firstTextBaseline) {
        Text("Sort into shelves").font(theme.font(18, .bold))
        Spacer()
        Text("\(panel.sortDone) of \(total)").font(.system(size: 12, design: .monospaced))
          .foregroundStyle(theme.secondary)
      }
      ProgressView(value: Double(panel.sortDone), total: Double(max(total, 1))).tint(theme.accent)
      if let id = panel.sortQueue.first, let item = model.reminder(id) {
        Text(item.title).font(theme.font(20, .bold)).lineLimit(3)
          .id(id).transition(.push(from: .trailing))
        FlowLayout(spacing: 6) {
          ForEach(Array(targets.enumerated()), id: \.element.id) { index, list in
            Chip(title: list.title, picked: false, focused: false, number: index + 1) {
              panel.sortQueue.removeFirst()
              panel.sortDone += 1
              Task { await model.move(id, toList: list.id) }
            }
          }
        }
        HStack(spacing: 14) {
          KeyHint(keys: "1–9", label: "shelve")
          KeyHint(keys: "t", label: "today")
          KeyHint(keys: "s", label: "skip")
          KeyHint(keys: "n", label: "new shelf")
          KeyHint(keys: "esc", label: "done")
        }
      } else {
        Text("Shelves ready").font(theme.font(24, .bold)).foregroundStyle(theme.highlight)
        Text("Everything you sorted is on its shelf. Your iPhone and Siri see the same lists.")
          .font(theme.font(13)).foregroundStyle(theme.secondary)
        KeyHint(keys: "↵", label: "back to today")
      }
      if targets.isEmpty {
        Text("No shelves yet. Press n to name your first one.").font(theme.font(12))
          .foregroundStyle(theme.secondary)
      }
      Spacer(minLength: 0)
    }
    .padding(18)
    .animation(.snappy(duration: 0.2), value: panel.sortQueue.first)
  }
}

/// The one-time suggestion for people who keep everything in one sectioned list.
struct ShelfSuggestion: View {
  @Bindable var panel: PanelState
  @Bindable var preferences: Preferences
  let list: ReminderList
  let count: Int
  @Environment(\.theme) private var theme

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("All \(count) reminders are in \(list.title).").font(theme.font(13, .semibold))
      Text(
        "Apple doesn't let apps see list sections, so shelves need their own lists. Sorting takes one key per reminder."
      )
      .font(theme.font(12)).foregroundStyle(theme.secondary).fixedSize(
        horizontal: false, vertical: true)
      HStack {
        Button("Sort into shelves") {
          preferences.shelfSortOffered = true
          panel.beginSort(list.id)
        }
        .buttonStyle(.borderedProminent)
        Button("Not now") { preferences.shelfSortOffered = true }.buttonStyle(.plain)
          .foregroundStyle(theme.secondary)
      }
      .font(theme.font(12))
    }
    .padding(12)
    .background(theme.raised, in: RoundedRectangle(cornerRadius: 8))
  }
}

/// Phosphor's instrument: it makes one slow orbit for every task you finish.
struct OrbitalRelay: View {
  let finishes: Int
  @Environment(\.theme) private var theme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @ViewState private var angle: Double = 0

  var body: some View {
    Canvas { context, size in
      let center = CGPoint(x: size.width / 2, y: size.height / 2)
      for (radius, rotation, opacity) in [(13.0, angle, 0.85), (8.0, -2 * angle, 0.5)] {
        for offset in [0.0, 180.0] {
          var arc = Path()
          arc.addArc(
            center: center, radius: radius, startAngle: .degrees(rotation + offset + 15),
            endAngle: .degrees(rotation + offset + 150), clockwise: false)
          context.stroke(arc, with: .color(theme.accent.opacity(opacity)), lineWidth: 1)
        }
      }
      let radians = angle * .pi / 180
      let dot = CGRect(
        x: center.x - 1 + cos(radians) * 13, y: center.y - 1 + sin(radians) * 13, width: 2,
        height: 2)
      context.fill(Path(ellipseIn: dot), with: .color(theme.highlight))
    }
    .frame(width: 34, height: 34)
    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(theme.accent.opacity(0.22)))
    .accessibilityHidden(true)
    .onChange(of: finishes) { _, _ in
      guard !reduceMotion else { return }
      withAnimation(.easeInOut(duration: 1.2)) { angle += 360 }
    }
  }
}
