import DaywellCore
import SwiftUI

/// The panel that drops from the menu bar.
public struct PanelView: View {
  @Bindable var model: DayModel
  @Bindable var panel: PanelState
  @Bindable var preferences: Preferences
  let motion: MotionState
  let shell: ShellActions

  public static let width: CGFloat = 420
  public static let maxHeight: CGFloat = 640

  public init(
    model: DayModel, panel: PanelState, preferences: Preferences, motion: MotionState,
    shell: ShellActions
  ) {
    self.model = model
    self.panel = panel
    self.preferences = preferences
    self.motion = motion
    self.shell = shell
  }

  public var body: some View {
    let theme = preferences.profile
    VStack(spacing: 0) {
      Group {
        if !model.authorized {
          PermissionView(model: model)
        } else {
          switch panel.route {
          case .today: TodayView(model: model, panel: panel, motion: motion, shell: shell)
          case .morning: MorningView(model: model, panel: panel)
          case .browse: BrowseView(model: model, panel: panel)
          case .commands: CommandPaletteView(model: model, panel: panel, shell: shell)
          case .help: HelpView(panel: panel)
          case .settings: SettingsView(model: model, panel: panel, preferences: preferences)
          case .move(let id): MoveView(model: model, panel: panel, reminderID: id)
          case .edit(let id):
            if let item = model.reminder(id) {
              EditorView(model: model, panel: panel, original: item).id(id)
            } else {
              Text("This reminder is no longer available.").padding(20)
            }
          }
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      StatusLine(model: model)
    }
    .frame(width: Self.width)
    .frame(maxHeight: Self.maxHeight)
    .background(theme.background)
    .overlay {
      if theme.overlay == .crt {
        CRTSurface().opacity(preferences.crtIntensity).allowsHitTesting(false)
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(theme.separator))
    .foregroundStyle(theme.text)
    .tint(theme.accent)
    .environment(\.theme, theme)
    .environment(\.colorScheme, theme.scheme)
  }
}

// MARK: Today

struct TodayView: View {
  @Bindable var model: DayModel
  @Bindable var panel: PanelState
  let motion: MotionState
  let shell: ShellActions
  @Environment(\.theme) private var theme

  var body: some View {
    VStack(spacing: 0) {
      header
      ScrollViewReader { proxy in
        ScrollView {
          VStack(alignment: .leading, spacing: 2) {
            myDay
            if !model.today.due.isEmpty { dueSection }
            if !model.today.shelves.isEmpty { shelves }
          }
          .padding(.horizontal, 8).padding(.bottom, 10)
        }
        .onChange(of: panel.selection) { _, row in
          if let row { withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(row) } }
        }
      }
      PileView(model: model, panel: panel, motion: motion)
      footer
    }
    .overlay { DayClearOverlay(model: model, motion: motion) }
  }

  private var header: some View {
    HStack(alignment: .lastTextBaseline) {
      VStack(alignment: .leading, spacing: 2) {
        Text("My Day").font(theme.font(20, .bold))
        Text(model.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
          .font(theme.font(12)).foregroundStyle(theme.secondary)
      }
      Spacer()
      Text(headerCount).font(.system(size: 12, design: .monospaced))
        .foregroundStyle(model.today.isDayClear ? theme.accent : theme.secondary)
    }
    .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 10)
  }

  private var headerCount: String {
    if model.today.isDayClear { return theme.dayClearTitle }
    let left = model.today.myDay.count
    return left == 0 ? "" : "\(left) left"
  }

  @ViewBuilder private var myDay: some View {
    let rows = motion.displayedMyDay
    if rows.isEmpty && !model.today.isDayClear {
      Button {
        panel.beginMorning()
      } label: {
        HStack(spacing: 10) {
          Image(systemName: "sun.max").foregroundStyle(theme.accent)
          Text("Choose today").font(theme.font(14, .medium))
          Spacer()
          Text("pick a few").font(theme.font(12)).foregroundStyle(theme.secondary)
        }
        .padding(12).background(theme.raised, in: RoundedRectangle(cornerRadius: 8))
      }
      .buttonStyle(.plain)
      .padding(.bottom, 6)
    }
    ForEach(rows) { item in
      TaskRow(
        item: item, row: .task(item.id), model: model, panel: panel, motion: motion,
        pinned: model.today.pinnedID == item.id
      )
      .id(PanelRow.task(item.id))
      .transition(
        .asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .identity))
    }
  }

  private var dueSection: some View {
    VStack(alignment: .leading, spacing: 2) {
      SectionHeader(
        row: .dueHeader, title: "Due", count: model.today.due.count,
        peek: model.today.due.prefix(3).map(\.title).joined(separator: " · "),
        expanded: panel.dueExpanded, panel: panel
      ) { panel.dueExpanded.toggle() }
      if panel.dueExpanded {
        ForEach(model.today.due) { item in
          TaskRow(
            item: item, row: .shelfTask(listID: "due", id: item.id), model: model, panel: panel,
            motion: motion, pinned: false, showsDue: true
          ).id(PanelRow.shelfTask(listID: "due", id: item.id))
        }
      }
    }
    .padding(.top, 8)
  }

  private var shelves: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text("SHELVES").font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(1.2)
        .foregroundStyle(theme.secondary).padding(.horizontal, 10).padding(.top, 12)
        .padding(.bottom, 2)
      ForEach(model.today.shelves) { shelf in
        let expanded = panel.expandedShelves.contains(shelf.id)
        SectionHeader(
          row: .shelf(shelf.id), title: shelf.list.title, count: shelf.items.count,
          peek: shelf.items.prefix(3).map(\.title).joined(separator: " · "),
          expanded: expanded, panel: panel
        ) {
          if expanded {
            panel.expandedShelves.remove(shelf.id)
          } else {
            panel.expandedShelves.insert(shelf.id)
          }
        }
        if expanded {
          ForEach(shelf.items) { item in
            TaskRow(
              item: item, row: .shelfTask(listID: shelf.id, id: item.id), model: model,
              panel: panel, motion: motion, pinned: false, indent: true
            ).id(PanelRow.shelfTask(listID: shelf.id, id: item.id))
          }
        }
      }
    }
  }

  private var footer: some View {
    HStack(spacing: 12) {
      Button {
        shell.openCapture()
      } label: {
        HStack(spacing: 8) {
          Image(systemName: "plus.circle").foregroundStyle(theme.secondary)
          Text("Catch something…").font(theme.font(13)).foregroundStyle(theme.secondary)
        }
      }
      .buttonStyle(.plain)
      Spacer()
      KeyHint(keys: "⌃⌥Space", label: "")
      Button {
        panel.route = .help
      } label: {
        Image(systemName: "keyboard").foregroundStyle(theme.secondary)
      }
      .buttonStyle(.plain).help("Keyboard shortcuts (?)")
      Button {
        panel.route = .settings
      } label: {
        Image(systemName: "gearshape").foregroundStyle(theme.secondary)
      }
      .buttonStyle(.plain).help("Settings (⌘,)")
    }
    .padding(.horizontal, 18).padding(.vertical, 12)
    .overlay(alignment: .top) { Rectangle().fill(theme.separator).frame(height: 1) }
  }
}

struct SectionHeader: View {
  let row: PanelRow
  let title: String
  let count: Int
  let peek: String
  let expanded: Bool
  @Bindable var panel: PanelState
  let toggle: () -> Void
  @Environment(\.theme) private var theme

  var body: some View {
    Button(action: toggle) {
      VStack(alignment: .leading, spacing: 2) {
        HStack {
          Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
            .rotationEffect(.degrees(expanded ? 90 : 0)).foregroundStyle(theme.secondary)
            .frame(width: 16)
          Text(title).font(theme.font(13, .semibold))
          Spacer()
          Text("\(count)").font(.system(size: 12, design: .monospaced))
            .foregroundStyle(theme.secondary)
        }
        if !expanded && !peek.isEmpty {
          Text(peek).font(theme.font(12)).foregroundStyle(theme.secondary).lineLimit(1)
            .padding(.leading, 24)
        }
      }
      .padding(.horizontal, 8).padding(.vertical, 7)
      .contentShape(Rectangle())
      .background(selectionBackground)
    }
    .buttonStyle(.plain)
    .id(row)
    .accessibilityLabel("\(title), \(count) open")
    .accessibilityHint(expanded ? "Collapse" : "Expand")
  }

  @ViewBuilder private var selectionBackground: some View {
    if panel.selection == row {
      RoundedRectangle(cornerRadius: 7).strokeBorder(theme.accent, lineWidth: 1.5)
    }
  }
}

struct TaskRow: View {
  let item: ReminderItem
  let row: PanelRow
  @Bindable var model: DayModel
  @Bindable var panel: PanelState
  let motion: MotionState
  let pinned: Bool
  var indent = false
  var showsDue = false
  @Environment(\.theme) private var theme

  var body: some View {
    let finishing = motion.isFinishing(item.id)
    let filled = item.isCompleted || finishing
    let chosen = model.isChosen(item.id) && indent
    let inkIndex = model.today.pile.firstIndex { $0.id == item.id } ?? model.today.pile.count
    let ink = theme.finish == .ink ? theme.ink(inkIndex) : theme.accent
    HStack(spacing: 10) {
      Button {
        Task { await model.toggleCompletion(item.id) }
      } label: {
        RingView(filled: filled, ink: ink)
          .padding(4).contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .disabled(!model.canWrite(item.id) && !finishing)
      .accessibilityLabel(filled ? "Reopen \(item.title)" : "Finish \(item.title)")
      Text(item.title).font(theme.font(14)).lineLimit(2)
        .strikethrough(filled, color: ink)
        .foregroundStyle(filled ? theme.secondary : theme.text)
        .animation(.easeOut(duration: 0.25), value: filled)
      Spacer(minLength: 6)
      if let due = item.dueDate, showsDue || item.hasDueTime {
        Text(dueLabel(due)).font(.system(size: 11, design: .monospaced))
          .foregroundStyle(theme.secondary)
      }
      if pinned {
        Text("PIN").font(.system(size: 10, weight: .medium, design: .monospaced))
          .foregroundStyle(theme.accent)
      }
      if chosen {
        Text("TODAY").font(.system(size: 10, weight: .medium, design: .monospaced))
          .foregroundStyle(theme.accent)
      }
    }
    .padding(.leading, indent ? 18 : 4).padding(.trailing, 10).padding(.vertical, 5)
    .background(background)
    .opacity(motion.isLeaving(item.id) ? 0 : 1)
    .contentShape(Rectangle())
    .onTapGesture { panel.selection = row }
    .accessibilityElement(children: .contain)
    .accessibilityAddTraits(panel.selection == row ? .isSelected : [])
  }

  @ViewBuilder private var background: some View {
    if panel.selection == row {
      RoundedRectangle(cornerRadius: 7).strokeBorder(theme.accent, lineWidth: 1.5)
        .background(theme.raised.opacity(pinned ? 1 : 0.5), in: RoundedRectangle(cornerRadius: 7))
    } else if pinned {
      RoundedRectangle(cornerRadius: 7).fill(theme.raised)
    }
  }

  private func dueLabel(_ date: Date) -> String {
    if item.hasDueTime { return date.formatted(date: .omitted, time: .shortened) }
    return date.formatted(.dateTime.weekday(.abbreviated))
  }
}

// MARK: Pile

struct PileView: View {
  @Bindable var model: DayModel
  @Bindable var panel: PanelState
  let motion: MotionState
  @Environment(\.theme) private var theme

  var body: some View {
    let pile = model.today.pile
    if !pile.isEmpty {
      VStack(alignment: .leading, spacing: 8) {
        Button {
          panel.pileExpanded.toggle()
        } label: {
          HStack {
            Text("Today's pile").font(theme.font(13, .semibold))
            Spacer()
            Text("\(pile.count) finished").font(theme.font(12)).foregroundStyle(theme.accent)
              .contentTransition(.numericText())
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        HStack(spacing: 6) {
          ForEach(Array(pile.enumerated()), id: \.element.id) { index, item in
            PileToken(index: index, fresh: motion.landed.contains(item.id))
          }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.55), value: pile.map(\.id))
        if panel.pileExpanded {
          ForEach(pile) { item in
            TaskRow(
              item: item, row: .pileTask(item.id), model: model, panel: panel, motion: motion,
              pinned: false
            ).id(PanelRow.pileTask(item.id))
          }
        } else {
          Text(pile.map(\.title).joined(separator: " · ")).font(theme.font(12))
            .foregroundStyle(theme.secondary).lineLimit(2)
        }
      }
      .padding(.horizontal, 18).padding(.vertical, 12)
      .background(theme.raised.opacity(0.55))
      .overlay(alignment: .top) { Rectangle().fill(theme.separator).frame(height: 1) }
      .overlay {
        if panel.selection == .pileHeader {
          RoundedRectangle(cornerRadius: 6).strokeBorder(theme.accent, lineWidth: 1.5).padding(4)
        }
      }
      .id(PanelRow.pileHeader)
      .accessibilityElement(children: .contain)
      .accessibilityLabel("Today's pile, \(pile.count) finished")
    }
  }
}

struct DayClearOverlay: View {
  @Bindable var model: DayModel
  let motion: MotionState
  @Environment(\.theme) private var theme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @ViewState private var visible = false

  var body: some View {
    ZStack {
      if visible {
        VStack(spacing: 6) {
          Text(theme.dayClearTitle).font(theme.font(30, .bold))
            .foregroundStyle(theme.highlight)
            .shadow(color: theme.overlay == .crt ? theme.accent : .clear, radius: 10)
          Text("\(model.today.pile.count) finished · resets quietly at midnight")
            .font(theme.font(12)).foregroundStyle(theme.secondary)
        }
        .padding(24)
        .background(theme.background.opacity(0.92), in: RoundedRectangle(cornerRadius: 14))
        .transition(reduceMotion ? .opacity : .scale(scale: 0.8).combined(with: .opacity))
      }
    }
    .allowsHitTesting(false)
    .onChange(of: motion.dayClearPulse) { _, _ in
      withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { visible = true }
      Task {
        try? await Task.sleep(for: .seconds(1.8))
        withAnimation(.easeOut(duration: 0.4)) { visible = false }
      }
    }
  }
}

/// Undo, notices and errors, one line at the bottom of every route.
struct StatusLine: View {
  @Bindable var model: DayModel
  @Environment(\.theme) private var theme

  var body: some View {
    if let error = model.error {
      HStack(alignment: .top, spacing: 8) {
        Image(systemName: "exclamationmark.circle")
        Text(error).font(theme.font(12)).fixedSize(horizontal: false, vertical: true)
        Spacer()
        if model.recoveryRequired {
          Button("Restore backup") { model.restorePlanBackup() }.font(theme.font(12))
        }
        Button("Dismiss") { model.error = nil }.font(theme.font(12)).buttonStyle(.plain)
          .foregroundStyle(theme.accent)
      }
      .padding(.horizontal, 18).padding(.vertical, 10).background(theme.raised)
    } else if let undo = model.undo {
      HStack {
        Text(model.notice ?? "").font(theme.font(12)).foregroundStyle(theme.secondary).lineLimit(1)
        Spacer()
        Button {
          Task { await model.undoLast() }
        } label: {
          Text("\(undo.label)  ⌘Z").font(theme.font(12))
        }
        .buttonStyle(.plain).foregroundStyle(theme.accent)
      }
      .padding(.horizontal, 18).padding(.vertical, 8)
    } else if let notice = model.notice {
      Text(notice).font(theme.font(12)).foregroundStyle(theme.secondary)
        .padding(.horizontal, 18).padding(.vertical, 8).frame(
          maxWidth: .infinity, alignment: .leading)
    }
  }
}

struct PermissionView: View {
  @Bindable var model: DayModel
  @Environment(\.theme) private var theme
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Daywell works with Apple Reminders").font(theme.font(18, .bold))
      Text(
        "It reads your lists so you can choose a manageable day, and it saves what you catch and finish back to Reminders. Your plan stays on this Mac."
      )
      .font(theme.font(13)).foregroundStyle(theme.secondary)
      Button("Allow Reminders access") { Task { await model.requestAccess() } }
        .buttonStyle(.borderedProminent)
      Button("Open Privacy & Security settings") {
        if let url = URL(
          string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders")
        {
          NSWorkspace.shared.open(url)
        }
      }
      .font(theme.font(12))
    }
    .padding(22)
  }
}
