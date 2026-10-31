import Adwaita
import CAdw
import Foundation

@main
enum Launcher {
  static func main() {
    // Before anything reads the settings or the data folder.
    AppID.adoptFormerData()
    _ = Flatpak.isSandboxed  // Inside a Flatpak, moves the temporary folder where host CLIs can see it.
    MainQueue.attachToGLib()
    SkillscoutGnome.main()
  }
}

struct SkillscoutGnome: App {
  let app = AdwaitaApp(id: AppID.current)
  let store = AppStore()
  let model = WindowModel()
  let renderer: Renderer

  init() {
    renderer = Renderer(store: store, model: model)
    // GApplication hands a second launch over to the copy that's already open. A test or a
    // screenshot runs against a made-up home, so it must never reach the Skillscout you have open.
    let environment = ProcessInfo.processInfo.environment
    if environment["SKILLSCOUT_TEST"] != nil || environment["SKILLSCOUT_SCREENSHOT"] != nil {
      let flags = g_application_get_flags(app.pointer?.cast()).rawValue | GApplicationFlags.APPLICATION_NON_UNIQUE.rawValue
      g_application_set_flags(app.pointer?.cast(), GApplicationFlags(rawValue: flags))
    }
    gtk_window_set_default_icon_name("io.github.eboye.skillscout")
  }

  var scene: Scene {
    Window(id: "main") { window in
      ContentView(store: store, model: model, app: app)
        .inspect { [renderer] _, data, _ in renderer.attach(data.stateManager) }
        .onAppear {
          AppIcons.addSearchPaths()
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
