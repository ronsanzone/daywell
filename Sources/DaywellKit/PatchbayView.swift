import DaywellCore
import SwiftUI

struct PatchbayView: View {
  @Bindable var model: AppModel
  let palette: Palette
  let motionActive: Bool
  let intensity: Double
  @State private var targeted = false

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("A few connections. A smaller day.")
        .font(.system(size: 14, weight: .medium))
      Text("Choose with +, drag across, or press a. Originals stay in their Apple lists.")
        .font(.system(size: 11)).foregroundStyle(palette.secondary)
        .fixedSize(horizontal: false, vertical: true)
      HStack(alignment: .top, spacing: 12) {
        VStack(alignment: .leading, spacing: 10) {
          heading("YOUR LISTS", count: model.patchbayLists.flatMap(\.items).count)
            .motionFrame("lists")
          ScrollViewReader { proxy in
            ScrollView {
              VStack(alignment: .leading, spacing: 8) {
                ForEach(model.patchbayLists) { section in
                  Text(section.list.title.uppercased())
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.secondary).padding(.top, 6)
                  ForEach(section.items) { item in
                    patchRow(item, source: true)
                      .draggable(item.id) { Text(item.title).padding(8) }
                      .id(item.id)
                  }
                  if section.items.isEmpty { empty("No unfinished reminders") }
                }
                if model.patchbayLists.isEmpty { empty("No lists available") }
              }.padding(2)
            }
            .onChange(of: model.selectedID) { _, id in
              if let id { proxy.scrollTo(id, anchor: .center) }
            }
          }
        }.frame(maxWidth: .infinity)
        Rectangle().fill(palette.accent.opacity(0.2)).frame(width: 1)
        VStack(alignment: .leading, spacing: 10) {
          heading("MY DAY", count: model.projection.today.count)
          ScrollView {
            VStack(spacing: 8) {
              ForEach(model.projection.today) { item in patchRow(item, source: false) }
              if model.projection.today.isEmpty {
                empty("Connect 1–3 reminders to begin.")
              }
              Label(targeted ? "Release to choose" : "Drop here to choose", systemImage: "plus")
                .font(.system(size: 11)).foregroundStyle(palette.accent)
                .frame(maxWidth: .infinity).padding(.vertical, 22)
                .background(palette.accent.opacity(targeted ? 0.12 : 0.03))
                .overlay(
                  RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(
                      palette.accent.opacity(targeted ? 0.8 : 0.25),
                      style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                )
            }.padding(2)
          }
          Button {
            model.doneExpanded = true
            model.route = .day
          } label: {
            Label("Done today · \(model.projection.done.count)", systemImage: "checkmark.circle")
              .font(.system(size: 11)).foregroundStyle(palette.secondary)
              .padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
          }.motionFrame("done")
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { ids, _ in
          guard ids.count == 1, let id = ids.first,
            DaywellCommand.choose.isEnabled(model, reminderID: id)
          else { return false }
          model.choose(id)
          return model.projection.today.contains { $0.id == id }
        } isTargeted: {
          targeted = $0
        }
      }
      Text("a · choose    r · release    h · back")
        .font(.system(size: 10, design: .monospaced)).foregroundStyle(palette.secondary)
    }.padding(16)
  }

  private func heading(_ text: String, count: Int) -> some View {
    HStack {
      Text(text).tracking(1.4)
      Spacer()
      Text("\(count)").monospacedDigit()
    }.font(.system(size: 11, weight: .medium, design: .monospaced))
      .foregroundStyle(palette.accent)
  }

  private func empty(_ text: String) -> some View {
    Text(text).font(.system(size: 11)).foregroundStyle(palette.secondary)
      .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
  }

  private func patchRow(_ item: ReminderItem, source: Bool) -> some View {
    let chosen = model.projection.today.contains { $0.id == item.id }
    let selected = source && model.selectedID == item.id
    return HStack(spacing: 8) {
      if !source {
        Button {
          Task { await model.complete(item.id) }
        } label: {
          Image(systemName: "circle").font(.system(size: 17, weight: .light))
        }
        .disabled(model.busy || !item.isWritable)
        .accessibilityLabel("Complete \(item.title)")
      }
      VStack(alignment: .leading, spacing: 5) {
        Text(item.title).font(.system(size: 12)).lineLimit(3)
        if source && chosen {
          Label("Chosen", systemImage: "checkmark")
            .font(.system(size: 9, design: .monospaced)).foregroundStyle(palette.accent)
        } else if !source {
          Text(item.listName).font(.system(size: 10)).foregroundStyle(palette.secondary)
        }
      }.frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { model.edit(item.id) }
        .onTapGesture { model.selectedID = item.id }
      if source {
        Button {
          model.choose(item.id)
        } label: {
          Image(systemName: chosen ? "checkmark" : "plus").frame(width: 20, height: 28)
        }
        .disabled(chosen || !DaywellCommand.choose.isEnabled(model, reminderID: item.id))
        .accessibilityLabel(chosen ? "\(item.title), chosen" : "Add \(item.title) to My Day")
        .help(chosen ? "Already in My Day" : "Add to My Day · a")
      } else {
        Button {
          model.release(item.id)
        } label: {
          Image(systemName: "minus").font(.system(size: 10)).frame(width: 16, height: 28)
        }.disabled(model.busy)
          .accessibilityLabel("Remove \(item.title) from My Day")
          .help("Remove from My Day, not Apple Reminders · r")
      }
    }
    .padding(9).frame(minHeight: 48)
    .background(palette.raised.opacity(source ? 0.6 : 1), in: RoundedRectangle(cornerRadius: 6))
    .overlay(
      PhosphorSelection(
        selected: selected, active: motionActive, color: palette.accent, intensity: intensity)
    )
    .motionFrame("\(source ? "source" : "row"):\(item.id)")
  }
}
