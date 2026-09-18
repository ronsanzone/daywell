import SwiftUI

struct CommandPalette: View {
  @Bindable var model: AppModel
  let palette: Palette
  @FocusState private var searching: Bool
  var commands: [DaywellCommand] { model.matchingCommands }
  var body: some View {
    VStack(spacing: 12) {
      HStack {
        Image(systemName: "magnifyingglass").foregroundStyle(palette.secondary)
        TextField("Search commands…", text: $model.commandQuery).textFieldStyle(.plain).focused(
          $searching
        )
        .onSubmit { activate() }
      }.padding(12).background(palette.raised, in: RoundedRectangle(cornerRadius: 7))
      ScrollViewReader { proxy in
        ScrollView {
          VStack(spacing: 3) {
            ForEach(Array(commands.enumerated()), id: \.element.id) { offset, command in
              Button {
                command.perform(model)
              } label: {
                HStack(spacing: 12) {
                  Image(systemName: command.symbol).frame(width: 18)
                  Text(command.title)
                  Spacer()
                  Text(command.shortcut).font(.system(size: 11)).foregroundStyle(palette.secondary)
                }.font(.system(size: 13)).padding(11)
                  .background(
                    model.commandIndex == offset ? palette.raised : Color.clear,
                    in: RoundedRectangle(cornerRadius: 5)
                  )
                  .opacity(command.isEnabled(model) ? 1 : 0.45)
              }.disabled(!command.isEnabled(model)).id(offset)
            }
          }
        }.onChange(of: model.commandIndex) { _, value in proxy.scrollTo(value) }
      }
      Text("↑ ↓ Navigate    ↵ Run command    Esc Back").font(.system(size: 11)).foregroundStyle(
        palette.secondary)
    }.padding(16)
      .onAppear {
        model.commandQuery = ""
        model.commandIndex = 0
        searching = true
      }
      .onChange(of: model.commandQuery) { _, _ in model.commandIndex = 0 }
      .onKeyPress(.downArrow) {
        model.navigate(.next)
        return .handled
      }
      .onKeyPress(.upArrow) {
        model.navigate(.previous)
        return .handled
      }
  }
  private func activate() { model.navigate(.open) }
}
