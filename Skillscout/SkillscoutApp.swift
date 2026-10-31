import SwiftUI

@main
struct SkillscoutApp: App {
  @State private var store = AppStore()

  var body: some Scene {
    Window("Skill Cabinet", id: "main") {
      ContentView()
        .environment(store)
        .task { await store.start() }
    }
    .defaultSize(width: 1180, height: 760)
    .commands {
      CommandGroup(after: .appSettings) {
        Button("Install Command Line Tool…") { CommandLineTool.install() }
      }
      CommandGroup(after: .textEditing) {
        Button("Find…") { store.searchRequests += 1 }
          .keyboardShortcut("f")
      }
    }

    Settings {
      SettingsView()
        .environment(store)
    }
  }
}
