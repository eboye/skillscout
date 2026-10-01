import SwiftUI

@main
struct SkillscoutApp: App {
  @State private var store = AppStore()

  init() {
    AppUpdater.shared.start(repository: "flaviocopes/skillscout")
  }

  var body: some Scene {
    Window("Skillscout", id: "main") {
      ContentView()
        .environment(store)
        .task {
          ControlServer.start(store: store)
          await store.start()
        }
    }
    .defaultSize(width: 1180, height: 760)
    .commands {
      CommandGroup(after: .appInfo) {
        Button("Check for Updates…") {
          AppUpdater.shared.checkForUpdates()
        }
      }
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
