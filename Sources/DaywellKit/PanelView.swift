import DaywellCore
import SwiftUI

public struct PanelView: View {
  public static let preferredSize = CGSize(width: 560, height: 660)
  @Bindable var model: AppModel
  @Bindable var preferences: Preferences
  @FocusState private var browseSearchFocused: Bool
  @State private var confirmRecovery = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var frames: [String: CGRect] = [:]
  @State private var previousFrames: [String: CGRect] = [:]
  @State private var flight: (feedback: ReminderFeedback, start: CGPoint)?
  public let isPresented: Bool
  public init(model: AppModel, preferences: Preferences, isPresented: Bool = true) {
    self.model = model
    self.preferences = preferences
    self.isPresented = isPresented
  }
  var palette: Palette { preferences.theme.colors }
  private var crtIntensity: Double { preferences.theme == .amber ? preferences.crtIntensity : 0 }
  private var motionActive: Bool {
    preferences.allowsMotion(reduceMotion: reduceMotion, isPresented: isPresented)
  }

  public var body: some View {
    VStack(spacing: 0) {
      header
      Divider().overlay(palette.secondary.opacity(0.15))
      if let error = model.error {
        HStack(alignment: .top) {
          Image(systemName: "exclamationmark.circle")
          Text(error).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
          Spacer(minLength: 0)
          Button {
            model.error = nil
          } label: {
            Image(systemName: "xmark")
          }.help("Dismiss error")
        }.padding(12).background(palette.raised)
      }
      if model.recoveryRequired {
        Button("Restore day-plan backup…") { confirmRecovery = true }
          .font(.system(size: 12)).padding(12).disabled(model.busy)
          .alert("Restore the previous day plan?", isPresented: $confirmRecovery) {
            Button("Cancel", role: .cancel) {}
            Button("Restore backup") { model.restorePlanBackup() }
          } message: {
            Text(
              "This restores the last good local plan, not Apple Reminders. The unreadable original is preserved. Newer unsupported versions are never overwritten."
            )
          }
      }
      if !model.authorized {
        permissionView
      } else {
        switch model.route {
        case .day: dayView
        case .browse: browseView
        case .patchbay:
          PatchbayView(
            model: model, palette: palette, motionActive: motionActive, intensity: crtIntensity)
        case .capture: CaptureView(model: model, palette: palette)
        case .commands: CommandPalette(model: model, palette: palette)
        case .help: shortcutHelp
        case .settings: SettingsView(model: model, preferences: preferences)
        case .edit:
          if let editing = model.editing {
            EditorView(model: model, original: editing, palette: palette).id(editing.id)
          } else {
            dayView
          }
        }
      }
      Spacer(minLength: 0)
      if model.route == .day || model.route == .browse || model.route == .patchbay {
        if let notice = model.notice {
          HStack {
            Text(notice).font(.system(size: 11)).foregroundStyle(palette.secondary)
            Spacer()
            if model.undo != nil {
              Button("Undo") { Task { await model.undoCompletion() } }.font(.system(size: 11))
            }
            Button {
              model.notice = nil
            } label: {
              Image(systemName: "xmark").font(.system(size: 9))
            }
          }.padding(.horizontal, 20).padding(.bottom, 10)
        }
        captureFooter
      }
    }
    .frame(width: Self.preferredSize.width)
    .frame(maxHeight: .infinity)
    .foregroundStyle(palette.text)
    .background(palette.background)
    .coordinateSpace(name: "daywell-panel")
    .onPreferenceChange(MotionFrames.self) { updated in
      previousFrames = frames
      frames = updated
    }
    .overlay {
      if motionActive, let flight, let end = flightDestination(flight.feedback) {
        ReminderFlight(feedback: flight.feedback, start: flight.start, end: end, palette: palette) {
          if self.flight?.feedback.id == flight.feedback.id { self.flight = nil }
        }.id(flight.feedback.id)
      }
    }
    .clipped()
    .onChange(of: model.feedback) { _, feedback in
      guard motionActive, model.authorized, let feedback,
        model.route == .day || model.route == .patchbay
      else {
        return
      }
      let key =
        feedback.kind == .reopened
        ? "done"
        : "\(model.route == .patchbay && feedback.kind == .chosen ? "source" : "row"):\(feedback.reminder.id)"
      if let rect = frames[key] ?? previousFrames[key],
        let header = frames["header"], let footer = frames["footer"],
        rect.midY > header.maxY, rect.midY < footer.minY
      {
        let x = model.route == .patchbay && feedback.kind == .chosen ? rect.maxX + 2 : rect.midX
        flight = (feedback, CGPoint(x: x, y: rect.midY))
      }
    }
    .onChange(of: motionActive) { _, _ in flight = nil }
    .onChange(of: model.route) { _, _ in flight = nil }
    .overlay {
      Rectangle().strokeBorder(palette.secondary.opacity(0.35), lineWidth: 1)
        .allowsHitTesting(false)
    }
    .overlay {
      if crtIntensity > 0 {
        CRTSurface().opacity(crtIntensity)
      }
    }
    .tint(palette.accent)
    .buttonStyle(.plain)
    .preferredColorScheme(preferences.theme.colorScheme)
    .alert(
      "Delete this reminder?",
      isPresented: Binding(
        get: { model.pendingDelete != nil }, set: { if !$0 { model.pendingDelete = nil } }),
      presenting: model.pendingDelete
    ) { original in
      Button("Cancel", role: .cancel) { model.pendingDelete = nil }
      Button("Delete from Apple Reminders", role: .destructive) {
        Task { await model.deleteConfirmed(original) }
      }
    } message: { _ in
      Text("This deletes the reminder itself, not just its place in My Day.")
    }
  }

  private var header: some View {
    HStack(spacing: 12) {
      if model.route != .day {
        Button {
          model.route = .day
        } label: {
          Image(systemName: "chevron.left")
        }
        .help("Back to My Day · h / Escape")
      }
      if preferences.theme == .amber, model.route == .day || model.route == .patchbay {
        OrbitalRelay(active: motionActive, color: palette.accent)
      }
      VStack(alignment: .leading, spacing: 4) {
        Text(title).font(
          .system(
            size: 21, weight: .semibold,
            design: preferences.theme == .amber ? .monospaced : .default)
        )
        .lineLimit(1).minimumScaleFactor(0.8)
        .shadow(color: palette.accent.opacity(crtIntensity * 0.7), radius: crtIntensity * 5)
        Text(model.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
          .font(.system(size: 12)).foregroundStyle(palette.secondary)
      }.motionFrame("myday")
      Spacer()
      Button {
        DaywellCommand.patchbay.perform(model)
      } label: {
        Image(systemName: "point.3.connected.trianglepath.dotted")
      }.help("Task patchbay · b").accessibilityLabel("Task patchbay")
      Button {
        model.route = .browse
      } label: {
        Image(systemName: "magnifyingglass")
      }.help("Search reminders · ⌘F")
      Button {
        model.route = .commands
      } label: {
        Text("⌘ K").font(.system(size: 11, weight: .medium)).padding(.horizontal, 7).padding(
          .vertical, 5
        ).background(palette.raised, in: RoundedRectangle(cornerRadius: 5))
      }
      .help("Commands · ⌘K")
    }.padding(.horizontal, 20).padding(.vertical, 16).motionFrame("header")
  }

  private var title: String {
    switch model.route {
    case .day: "My Day"
    case .browse: "Reminders"
    case .patchbay: "Task patchbay"
    case .capture: "Quick capture"
    case .commands: "Commands"
    case .help: "Keyboard shortcuts"
    case .settings: "Settings"
    case .edit: "Edit reminder"
    }
  }

  private var dayView: some View {
    ScrollViewReader { proxy in
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          if model.projection.today.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
              Text("A little room for your day.").font(.system(size: 16, weight: .medium))
              Text("Choose 1–3 reminders to begin. You can always add more.").font(
                .system(size: 13)
              ).foregroundStyle(palette.secondary)
              Button("Choose reminders") { model.route = .patchbay }.padding(.top, 4)
            }.padding(.vertical, 22).padding(.horizontal, 8)
          }
          ForEach(model.projection.today) { reminder in row(reminder) }
          if !model.projection.due.isEmpty {
            sectionDivider
            disclosure(
              "Due & overdue", count: model.projection.due.count, expanded: $model.dueExpanded
            )
            .padding(.horizontal, 8).padding(.vertical, 12)
            if model.dueExpanded {
              ForEach(model.projection.due) { reminder in row(reminder, showDue: true) }
            }
          }
          if !model.projection.previous.isEmpty {
            sectionDivider
            HStack {
              disclosure(
                "From yesterday", count: model.projection.previous.count,
                expanded: $model.previousExpanded)
              Spacer()
              Button("Keep all") { model.keepPrevious(model.projection.previous.map(\.id)) }.font(
                .system(size: 11))
              Button("Choose") { model.previousExpanded = true }.font(.system(size: 11))
            }.padding(.horizontal, 8).padding(.vertical, 12)
            if model.previousExpanded {
              ForEach(model.projection.previous) { reminder in
                HStack {
                  row(reminder)
                  Button("Keep") { model.keepPrevious([reminder.id]) }.font(.system(size: 11))
                  Button {
                    model.release(reminder.id)
                  } label: {
                    Image(systemName: "minus.circle")
                  }.help("Release commitment")
                }
              }
              Button("Release all previous commitments") { model.releasePrevious() }
                .font(.system(size: 11)).foregroundStyle(palette.secondary).padding(8)
            }
          }
          sectionDivider
          disclosure(
            "Done today", count: model.projection.done.count, expanded: $model.doneExpanded
          )
          .padding(.horizontal, 8).padding(.vertical, 14)
          .motionFrame("done")
          if model.doneExpanded { ForEach(model.projection.done) { reminder in row(reminder) } }
          inlineLists
          if !model.projection.unresolved.isEmpty {
            Text(
              "\(model.projection.unresolved.count) saved commitment(s) could not be linked to a reminder. Your plan is preserved."
            )
            .font(.system(size: 11)).foregroundStyle(palette.secondary).padding(8)
          }
        }.padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 8)
      }.onChange(of: model.selectedID) { _, id in if let id { proxy.scrollTo(id, anchor: .center) }
      }
    }
  }

  private var inlineLists: some View {
    VStack(alignment: .leading, spacing: 0) {
      sectionDivider
      HStack {
        Text("YOUR LISTS").font(.system(size: 11, weight: .medium))
        Spacer()
        Text("Not in My Day").font(.system(size: 11))
      }.foregroundStyle(palette.secondary).padding(.horizontal, 8).padding(.vertical, 12)
        .motionFrame("lists")
      ForEach(model.dayLists) { section in
        let expanded = model.expandedListIDs.contains(section.id)
        let items = model.inlineListItems(section)
        VStack(alignment: .leading, spacing: 0) {
          disclosure(
            section.list.title, count: section.items.count,
            expanded: Binding(
              get: { model.expandedListIDs.contains(section.id) },
              set: { model.setListExpanded(section.id, expanded: $0) })
          )
          .padding(.horizontal, 8).padding(.vertical, 10)
          if expanded {
            ForEach(items) { item in
              row(item, showChoose: true)
            }
            let shownAbove = section.items.count - items.count
            if shownAbove > 0 {
              listSummary("\(shownAbove) shown in the sections above")
            } else if section.items.isEmpty {
              listSummary("No other unfinished reminders")
            }
          } else {
            listSummary(
              section.items.isEmpty
                ? "No other unfinished reminders"
                : section.items.prefix(2).map(\.title).joined(separator: " · "))
          }
          Divider().overlay(palette.secondary.opacity(0.1))
        }
      }
      if model.dayLists.isEmpty {
        listSummary("No reminder lists available")
      }
    }
  }

  private func listSummary(_ text: String) -> some View {
    Text(text).font(.system(size: 11)).foregroundStyle(palette.secondary)
      .lineLimit(1).padding(.leading, 29).padding(.trailing, 8).padding(.bottom, 10)
      .help(text)
  }

  private var browseView: some View {
    VStack(spacing: 12) {
      TextField("Search reminders…", text: $model.search).textFieldStyle(.roundedBorder)
        .accessibilityLabel("Search reminders")
        .focused($browseSearchFocused)
        .onAppear { browseSearchFocused = true }
      Picker("List", selection: $model.browseListID) {
        Text("All lists").tag("")
        ForEach(model.lists) { Text($0.title).tag($0.id) }
      }
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(spacing: 2) {
            if model.browsed.isEmpty {
              Text("No matching reminders").foregroundStyle(palette.secondary).padding(20)
            }
            ForEach(model.browsed) { item in
              HStack(spacing: 0) {
                row(item)
                Button {
                  model.choose(item.id)
                } label: {
                  Image(
                    systemName: model.projection.today.contains(where: { $0.id == item.id })
                      ? "checkmark" : "plus")
                }.help("Add to My Day · a").padding(8)
              }
            }
          }
        }.onChange(of: model.selectedID) { _, id in
          if let id { proxy.scrollTo(id, anchor: .center) }
        }
      }
    }.padding(16)
  }

  private func row(_ reminder: ReminderItem, showDue: Bool = false, showChoose: Bool = false)
    -> some View
  {
    let selected = model.selectedID == reminder.id
    let pinned = model.projection.pinnedReminderID == reminder.id
    return HStack(spacing: 11) {
      Button {
        Task { await model.complete(reminder.id) }
      } label: {
        Image(systemName: reminder.isCompleted ? "checkmark.circle.fill" : "circle")
          .font(.system(size: 18, weight: .light))
          .foregroundStyle(reminder.isCompleted ? palette.secondary : palette.text.opacity(0.85))
      }.disabled(!reminder.isWritable || model.busy)
        .accessibilityLabel(
          reminder.isCompleted ? "Reopen \(reminder.title)" : "Complete \(reminder.title)")
      VStack(alignment: .leading, spacing: 4) {
        Text(reminder.title).font(.system(size: 14)).strikethrough(reminder.isCompleted)
          .foregroundStyle(reminder.isCompleted ? palette.secondary : palette.text)
          .shadow(color: palette.accent.opacity(crtIntensity * 0.55), radius: crtIntensity * 3)
          .lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
        if pinned && !reminder.notes.isEmpty {
          Text(reminder.notes).font(.system(size: 11)).foregroundStyle(palette.secondary).lineLimit(
            2)
        }
      }.contentShape(Rectangle())
        .onTapGesture(count: 2) {
          model.selectedID = reminder.id
          model.edit(reminder.id)
        }
        .onTapGesture { model.selectedID = reminder.id }
      if let due = reminder.dueDate, showDue || !reminder.isCompleted {
        Text(dueLabel(due, timed: reminder.hasDueTime)).font(.system(size: 11)).foregroundStyle(
          palette.secondary)
      }
      if pinned {
        Image(systemName: "pin.fill").font(.system(size: 11)).foregroundStyle(palette.accent)
          .accessibilityLabel("Pinned")
      }
      if showChoose {
        Button {
          model.choose(reminder.id)
        } label: {
          Image(systemName: "plus").font(.system(size: 12))
        }
        .disabled(!DaywellCommand.choose.isEnabled(model, reminderID: reminder.id))
        .accessibilityLabel("Add \(reminder.title) to My Day")
        .help("Add to My Day · a")
      }
      Menu {
        Button("Add to My Day") { model.choose(reminder.id) }
          .disabled(!DaywellCommand.choose.isEnabled(model, reminderID: reminder.id))
        Button(pinned ? "Unpin" : "Pin") { model.pin(reminder.id) }
          .disabled(!DaywellCommand.pin.isEnabled(model, reminderID: reminder.id))
        Button("Edit") { model.edit(reminder.id) }
          .disabled(!DaywellCommand.edit.isEnabled(model, reminderID: reminder.id))
        Button("Remove from My Day") { model.release(reminder.id) }
          .disabled(!DaywellCommand.release.isEnabled(model, reminderID: reminder.id))
        Divider()
        Button("Delete reminder…", role: .destructive) { model.requestDelete(reminder) }
          .disabled(!DaywellCommand.delete.isEnabled(model, reminderID: reminder.id))
      } label: {
        Image(systemName: "ellipsis").font(.system(size: 12)).foregroundStyle(palette.secondary)
      }
      .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Reminder actions")
    }
    .padding(.horizontal, 8).padding(.vertical, pinned ? 13 : 10)
    .background(selected ? palette.raised : Color.clear, in: RoundedRectangle(cornerRadius: 6))
    .overlay(
      PhosphorSelection(
        selected: selected, active: motionActive, color: palette.accent, intensity: crtIntensity)
    )
    .motionFrame("row:\(reminder.id)")
    .id(reminder.id)
  }

  private func flightDestination(_ feedback: ReminderFeedback) -> CGPoint? {
    let chosen = model.projection.today.contains { $0.id == feedback.reminder.id }
    let key =
      feedback.kind == .completed
      ? "done"
      : "\(model.route == .patchbay && !chosen ? "source" : "row"):\(feedback.reminder.id)"
    guard let rect = frames[key] ?? frames[chosen ? "myday" : "lists"] else { return nil }
    let x = model.route == .patchbay && feedback.kind == .chosen ? rect.minX - 2 : rect.midX
    return CGPoint(x: x, y: rect.midY)
  }

  private func dueLabel(_ date: Date, timed: Bool) -> String {
    if model.calendar.isDate(date, inSameDayAs: model.now) {
      return timed ? date.formatted(date: .omitted, time: .shortened) : "Today"
    }
    if let yesterday = model.calendar.date(byAdding: .day, value: -1, to: model.now),
      model.calendar.isDate(date, inSameDayAs: yesterday)
    {
      return "Yesterday"
    }
    return date.formatted(.dateTime.month(.abbreviated).day())
  }
  private var sectionDivider: some View {
    Divider().overlay(palette.secondary.opacity(0.1)).padding(.top, 6)
  }
  private func disclosure(_ title: String, count: Int, expanded: Binding<Bool>) -> some View {
    Button {
      expanded.wrappedValue.toggle()
    } label: {
      HStack(spacing: 9) {
        Image(systemName: expanded.wrappedValue ? "chevron.down" : "chevron.right").font(
          .system(size: 9, weight: .semibold)
        ).frame(width: 12)
        Text(title).font(.system(size: 12))
        Text("\(count)").font(.system(size: 11)).foregroundStyle(palette.secondary)
        Spacer(minLength: 0)
      }
      .contentShape(Rectangle())
    }.accessibilityLabel(title)
      .accessibilityValue("\(count), \(expanded.wrappedValue ? "Expanded" : "Collapsed")")
      .help("Expand or collapse \(title) · Tab then Space")
  }
  private var captureFooter: some View {
    VStack(spacing: 12) {
      Divider()
      Button {
        DaywellCommand.capture.perform(model)
      } label: {
        HStack(spacing: 10) {
          Image(systemName: "plus.circle").font(.system(size: 20, weight: .light))
          Text(model.captureText.isEmpty ? "Add a reminder…" : model.captureText).font(
            .system(size: 13)
          ).lineLimit(1)
          Spacer()
          Text("⌘ N").font(.system(size: 10))
        }.foregroundStyle(palette.secondary).padding(.vertical, 3)
      }.disabled(!model.authorized)
      HStack {
        Text("j / k to navigate").font(.system(size: 10)).foregroundStyle(palette.secondary)
        if model.route == .day {
          Button {
            DaywellCommand.sections.perform(model)
          } label: {
            Text(model.sectionsExpanded ? "s · collapse sections" : "s · expand sections")
              .font(.system(size: 10))
          }
          .disabled(!DaywellCommand.sections.isEnabled(model))
          .help("Expand / collapse all sections · s")
        }
        Spacer()
        Button {
          model.route = .help
        } label: {
          Image(systemName: "keyboard")
        }.help("Keyboard shortcuts · ?")
        Button {
          model.route = .settings
        } label: {
          Image(systemName: "gearshape")
        }.help("Settings · ⌘,")
      }
    }.padding(.horizontal, 20).padding(.bottom, 16).motionFrame("footer")
  }
  private var permissionView: some View {
    VStack(alignment: .leading, spacing: 18) {
      Image(systemName: "checklist").font(.system(size: 32, weight: .light))
      Text("Your reminders. A smaller day.").font(.system(size: 19, weight: .semibold))
      Text(
        "Daywell needs access to Apple Reminders to show and edit your tasks. Your reminders stay in Apple Reminders; your daily choices stay on this Mac."
      )
      .font(.system(size: 13)).foregroundStyle(palette.secondary)
      Button("Allow Reminders access") { Task { await model.requestAccess() } }.buttonStyle(
        .borderedProminent)
      Button("Open Privacy Settings") {
        NSWorkspace.shared.open(
          URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders")!)
      }
      Button("Retry") { Task { await model.refresh() } }
    }.padding(24)
  }
  private var shortcutHelp: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        Text("Vim-inspired, not Vim-required.").font(.system(size: 14, weight: .medium))
        Text(
          "Motions work outside text fields. Press Escape to leave a field. Arrow keys and Tab work too."
        )
        .font(.system(size: 12)).foregroundStyle(palette.secondary)
        helpRow("Next / previous reminder", "j / k    ↓ / ↑")
        helpRow("First / last reminder", "gg / G")
        helpRow("Back / open details", "h / l    ← / →")
        helpRow("Command palette", "⌘ K")
        ForEach(DaywellCommand.allCases.filter { !$0.shortcut.isEmpty }) { command in
          helpRow(command.title, command.shortcut)
        }
      }.padding(20)
    }
  }
  private func helpRow(_ label: String, _ keys: String) -> some View {
    HStack {
      Text(label)
      Spacer()
      Text(keys).foregroundStyle(palette.secondary)
    }.font(.system(size: 12))
  }
}
