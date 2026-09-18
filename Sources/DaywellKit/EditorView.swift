import DaywellCore
import SwiftUI

struct CaptureView: View {
  @Bindable var model: AppModel
  let palette: Palette
  @FocusState private var focused: Bool
  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      TextField("Call dentist tomorrow at 2pm", text: $model.captureText, axis: .vertical)
        .textFieldStyle(.roundedBorder).focused($focused).lineLimit(2...4)
        .onSubmit { Task { await model.saveCapture() } }
      if !model.captureText.isEmpty {
        VStack(alignment: .leading, spacing: 12) {
          Text(model.capturePreview.title).font(.system(size: 15, weight: .medium))
          if let due = model.capturePreview.dueDate {
            Toggle(isOn: $model.captureUsesDate) {
              Label(
                due.formatted(
                  date: .abbreviated, time: model.capturePreview.hasTime ? .shortened : .omitted),
                systemImage: "calendar")
            }.font(.system(size: 12))
            Text(
              "Edit the phrase above to correct the date, or uncheck it to save without a deadline."
            )
            .font(.system(size: 11)).foregroundStyle(palette.secondary)
          } else {
            Text("No date detected. Try “tomorrow at 2pm” or “Friday”.")
              .font(.system(size: 11)).foregroundStyle(palette.secondary)
          }
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(
          palette.raised, in: RoundedRectangle(cornerRadius: 8))
      }
      Picker("Save to", selection: $model.captureListID) {
        ForEach(model.writableLists) { Text($0.title).tag($0.id) }
      }
      Toggle("Add to My Day", isOn: $model.captureAddToDay)
      Text("Capturing a thought doesn't have to be a commitment.").font(.system(size: 12))
        .foregroundStyle(palette.secondary)
      HStack {
        Button("Cancel") { model.route = .day }
        Spacer()
        Button("Save reminder") { Task { await model.saveCapture() } }.buttonStyle(
          .borderedProminent
        )
        .keyboardShortcut(.return, modifiers: .command).disabled(
          model.captureText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.busy)
      }
    }.padding(20).onAppear { focused = true }
  }
}

struct EditorView: View {
  @Bindable var model: AppModel
  let original: ReminderItem
  let palette: Palette
  @State private var draft: ReminderItem
  @State private var hasDate: Bool
  @State private var date: Date
  init(model: AppModel, original: ReminderItem, palette: Palette) {
    self.model = model
    self.original = original
    self.palette = palette
    _draft = State(initialValue: original)
    _hasDate = State(initialValue: original.dueDate != nil)
    _date = State(initialValue: original.dueDate ?? model.now)
  }
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        TextField("Title", text: $draft.title).textFieldStyle(.roundedBorder)
        Text("Notes").font(.system(size: 12)).foregroundStyle(palette.secondary)
        TextEditor(text: $draft.notes).font(.system(size: 13)).frame(height: 110)
          .scrollContentBackground(.hidden).padding(8).background(
            palette.raised, in: RoundedRectangle(cornerRadius: 6))
        Picker("List", selection: $draft.listID) {
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
          Button("Cancel") {
            model.editing = nil
            model.route = .day
          }
          Spacer()
          Button("Save changes") {
            draft.dueDate = hasDate ? date : nil
            if !hasDate { draft.hasDueTime = false }
            draft.listName = model.lists.first { $0.id == draft.listID }?.title ?? draft.listName
            Task { await model.saveEdit(draft, original: original) }
          }.buttonStyle(.borderedProminent).keyboardShortcut(.return, modifiers: .command)
            .disabled(
              !original.isWritable || model.busy
                || draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        Divider()
        Button("Open Apple Reminders for more options") {
          DaywellCommand.appleReminders.perform(model)
        }.font(.system(size: 12))
        Button("Delete reminder…", role: .destructive) { model.pendingDelete = original }.disabled(
          !original.isWritable)
      }.padding(20)
    }
  }
}
