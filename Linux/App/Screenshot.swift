import Adwaita
import CAdw
import Foundation

/// The Linux side of scripts/screenshot.sh: with SKILLSCOUT_SCREENSHOT set to a PNG path, the app
/// opens on the section and item in SKILLSCOUT_SIDEBAR and SKILLSCOUT_SELECT, waits for the skills
/// and chats to load, saves the window to the PNG, and quits. SKILLSCOUT_DARK=1 picks dark style.
/// Point HOME at a made-up home first, never at real skills and chats.
enum Screenshot {
  @MainActor
  static func scheduleIfAsked(window: AdwaitaWindow, store: AppStore, model: WindowModel, app: AdwaitaApp) {
    let environment = ProcessInfo.processInfo.environment
    guard let path = environment["SKILLSCOUT_SCREENSHOT"] else { return }
    // A made-up home can't see the icon theme you picked, so use the stock one, or SKILLSCOUT_ICON_THEME.
    var theme = GValue()
    g_value_init(&theme, GType(16 << 2))  // G_TYPE_STRING, a macro Swift can't import
    g_value_set_string(&theme, environment["SKILLSCOUT_ICON_THEME"] ?? "Adwaita")
    g_object_set_property(gtk_settings_get_default()?.cast(), "gtk-icon-theme-name", &theme)
    g_value_unset(&theme)
    // Dialogs open with an animation that can stall while the window is covered, so skip it.
    var animations = GValue()
    g_value_init(&animations, GType(5 << 2))  // G_TYPE_BOOLEAN
    g_value_set_boolean(&animations, 0)
    g_object_set_property(gtk_settings_get_default()?.cast(), "gtk-enable-animations", &animations)
    g_value_unset(&animations)
    if environment["SKILLSCOUT_DARK"] == "1" {
      adw_style_manager_set_color_scheme(adw_style_manager_get_default(), .ADW_COLOR_SCHEME_FORCE_DARK)
    } else {
      adw_style_manager_set_color_scheme(adw_style_manager_get_default(), .ADW_COLOR_SCHEME_FORCE_LIGHT)
    }

    Task { @MainActor in
      for _ in 0..<100 where store.skills.isEmpty || store.isLoadingPrompts {
        try? await Task.sleep(for: .milliseconds(100))
      }
      select(environment["SKILLSCOUT_SIDEBAR"] ?? "all", environment["SKILLSCOUT_SELECT"], store: store, model: model)
      try? await Task.sleep(for: .milliseconds(1500))

      if openMenu, let button = menuButton(in: window.pointer?.cast()) {
        gtk_menu_button_popup(OpaquePointer(button))
        try? await Task.sleep(for: .milliseconds(500))
        // A popover is a surface of its own, so it gets its own picture.
        if let popover = gtk_menu_button_get_popover(OpaquePointer(button)) {
          _ = save(UnsafeMutablePointer(OpaquePointer(popover)), to: path.replacingOccurrences(of: ".png", with: "-popover.png"))
        }
      }
      saveAfterPaint(window: window, to: path) { app.quit() }
    }
  }

  @MainActor private static var afterPaint: SignalData?
  @MainActor private static var openMenu = false

  /// The first menu button in the window, which is the main menu in the sidebar's header bar.
  @MainActor
  private static func menuButton(in widget: UnsafeMutablePointer<GtkWidget>?) -> UnsafeMutablePointer<GtkWidget>? {
    guard let widget else { return nil }
    if String(cString: gtk_widget_get_css_name(widget)) == "menubutton" { return widget }
    var child = gtk_widget_get_first_child(widget)
    while let current = child {
      if let found = menuButton(in: current) { return found }
      child = gtk_widget_get_next_sibling(current)
    }
    return nil
  }

  /// A widget only has something to draw right after GTK paints it, so this waits for a frame.
  @MainActor
  private static func saveAfterPaint(window: AdwaitaWindow, to path: String, then done: @escaping () -> Void) {
    guard let toplevel = window.pointer?.cast() as UnsafeMutablePointer<GtkWidget>?,
          let clock = gtk_widget_get_frame_clock(toplevel)
    else { return done() }
    var attempts = 0
    let data = SignalData {
      attempts += 1
      if attempts > 8 && save(toplevel, to: path) || attempts > 30 {
        afterPaint = nil
        done()
      } else {
        gtk_widget_queue_draw(toplevel)
      }
    }
    data.connect(pointer: UnsafeMutableRawPointer(clock), signal: "after-paint", type: .noArgs)
    afterPaint = data
    gtk_widget_queue_draw(toplevel)
  }

  @MainActor
  private static func select(_ section: String, _ item: String?, store: AppStore, model: WindowModel) {
    switch section {
    case "missing": model.sidebar = .missing
    case "unused": model.sidebar = .unused
    case "suggestions": model.sidebar = .suggestions
    case "similar": model.sidebar = .similar
    case let tool where tool.hasPrefix("tool:"): model.sidebar = Tool(rawValue: String(tool.dropFirst(5))).map(SidebarItem.tool) ?? .allSkills
    default: model.sidebar = .allSkills
    }
    guard let item else { return }
    switch model.sidebar {
    case .suggestions: model.selectedSuggestion = store.suggestions.first { $0.name == item || $0.title == item }?.id.uuidString ?? ""
    case .similar: model.selectedPair = store.similar.first { $0.first == item || $0.second == item }?.id ?? ""
    default: model.selectedSkill = item
    }
    model.showList = true
    model.showDetail = true

    let skill = store.skill(item)
    switch ProcessInfo.processInfo.environment["SKILLSCOUT_OPEN"] {
    case "rename": store.renaming = skill
    case "edit": store.editing = skill
    case "uninstall": store.removal = skill.map(Removal.uninstall)
    case "preferences": model.showPreferences = true
    case "about": model.showAbout = true
    case "menu": openMenu = true
    default: break
    }
  }

  @MainActor
  private static func save(_ toplevel: UnsafeMutablePointer<GtkWidget>, to path: String) -> Bool {

    let width = Double(gtk_widget_get_width(toplevel))
    let height = Double(gtk_widget_get_height(toplevel))
    let paintable = gtk_widget_paintable_new(toplevel)
    defer { g_object_unref(paintable?.cast()) }
    let snapshot = gtk_snapshot_new()
    gdk_paintable_snapshot(paintable, snapshot, width, height)
    guard let node = gtk_snapshot_free_to_node(snapshot) else { return false }
    defer { gsk_render_node_unref(node) }
    guard let renderer = gtk_native_get_renderer(OpaquePointer(toplevel)),
          let texture = gsk_renderer_render_texture(renderer, node, nil)
    else { return false }
    defer { g_object_unref(texture.cast()) }
    return gdk_texture_save_to_png(texture, path) != 0
  }
}
