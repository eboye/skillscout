import Adwaita
import CAdw
import Foundation

@main
enum Launcher {
  static func main() {
    // UserDefaults names its file after the process on Linux, so this gives the app the Mac app's
    // settings domain, ~/.config/com.flaviocopes.skillscout.plist, which the command reads too.
    ProcessInfo.processInfo.processName = "com.flaviocopes.skillscout"
    MainQueue.attachToGLib()
    SkillscoutGnome.main()
  }
}

struct SkillscoutGnome: App {
  let app = AdwaitaApp(id: "com.flaviocopes.skillscout")
  let store = AppStore()
  let model = WindowModel()
  let renderer: Renderer

  init() {
    renderer = Renderer(store: store, model: model)
    gtk_window_set_default_icon_name("com.flaviocopes.skillscout")
  }

  var scene: Scene {
    Window(id: "main") { window in
      ContentView(store: store, model: model, app: app)
        .inspect { [renderer] _, data, _ in renderer.attach(data.stateManager) }
        .onAppear {
          Task { await store.start() }
          Screenshot.scheduleIfAsked(window: window, store: store, model: model, app: app)
        }
    }
    .title("Skillscout")
    .defaultSize(width: 1180, height: 760)
    .minSize(width: 360, height: 480)
    .keyboardShortcut("f".ctrl()) { _ in store.searchRequests += 1 }
    .closeShortcut()
  }
}
