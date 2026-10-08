import Adwaita
import CAdw
import Foundation

/// A tool's name in its color, or struck through when the skill doesn't load there.
struct ToolBadge: View {
  let tool: Tool
  var active = true

  var view: Body {
    Text(tool.shortName)
      .style("tool-badge")
      .style("tool-\(tool.rawValue)", active: active)
      .style("tool-inactive", active: !active)
      .tooltip(active ? "Available in \(tool.name)" : "Not available in \(tool.name)")
      .valign(.center)
  }
}

/// The row of small badges in the skill list, one per tool you use.
struct AvailabilityBadges: View {
  let available: Set<Tool>
  let tools: [Tool]

  var view: Body {
    ForEach(tools) { tool in
      Text(tool.code)
        .style("tool-icon")
        .style("tool-\(tool.rawValue)", active: available.contains(tool))
        .style("tool-inactive", active: !available.contains(tool))
        .tooltip(available.contains(tool) ? "Available in \(tool.name)" : "Not available in \(tool.name)")
    }
    .orientation(.horizontal)
    .style("badge-row")
    .valign(.center)
  }
}

/// A heading over a block of the detail pane.
struct DetailSection: View {
  let title: String
  let content: Body

  init(_ title: String, @ViewBuilder content: () -> Body) {
    self.title = title
    self.content = content()
  }

  var view: Body {
    VStack(spacing: 10) {
      Text(title)
        .heading()
        .halign(.start)
      content
    }
  }
}

/// A label that wraps, starts at the left, and can be selected like the SwiftUI text it replaces.
@MainActor
func paragraph(_ text: String, selectable: Bool = false) -> Label {
  Text(text)
    .wrap()
    .xalign(0)
    .selectable(selectable)
}

/// A monospaced editor for SKILL.md files. GTK has no smart quotes or dashes, so the commands in a
/// skill stay as typed, which is what `PlainTextEditor` makes sure of on the Mac.
@MainActor
func plainTextEditor(_ text: Binding<String>, editable: Bool = true, minHeight: Int = 380) -> AnyView {
  TextEditor(text: text)
    .innerPadding(12)
    .wrapMode(.wordCharacter)
    .monospace()
    .inspect { storage, _ in
      gtk_text_view_set_editable(storage.opaquePointer?.cast(), editable.cBool)
      gtk_text_view_set_cursor_visible(storage.opaquePointer?.cast(), editable.cBool)
    }
    .frame(minHeight: minHeight)
    .card()
}

/// Finder's jobs, through GTK, which goes through the desktop portal when there is one.
@MainActor
enum Desktop {
  static func reveal(_ url: URL) {
    launch(url) { launcher in gtk_file_launcher_open_containing_folder(launcher, nil, nil, nil, nil) }
  }

  static func open(_ url: URL) {
    launch(url) { launcher in gtk_file_launcher_launch(launcher, nil, nil, nil, nil) }
  }

  private static func launch(_ url: URL, _ action: (OpaquePointer?) -> Void) {
    let file = g_file_new_for_path(url.path)
    let launcher = gtk_file_launcher_new(file)
    action(launcher)
    g_object_unref(launcher?.cast())
    g_object_unref(file?.cast())
  }
}

/// The app's own icons, in Linux/icons. Installed, they're in the hicolor theme next to the app;
/// in a build from the repo, the icon theme looks for them in the repo itself.
@MainActor
enum AppIcons {
  private static var added = false

  static func addSearchPaths() {
    guard !added, let display = gdk_display_get_default(), let theme = gtk_icon_theme_get_for_display(display) else { return }
    added = true
    let installed = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
      .deletingLastPathComponent().deletingLastPathComponent().appending(path: "share/icons")
    // GTK takes loose icons straight from a search path, and themes from its subfolders.
    let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "icons/scalable/actions")
    for folder in [installed, repo] where FileManager.default.fileExists(atPath: folder.path) {
      gtk_icon_theme_add_search_path(theme, folder.path)
    }
  }
}

/// The badge colors, and a few spacing rules libadwaita has no style class for.
let appCSS: String = {
  var css = """
  .tool-badge { font-size: 0.75em; font-weight: 700; padding: 1px 7px; border-radius: 999px; }
  .tool-icon { font-size: 0.68em; font-weight: 700; min-width: 20px; padding: 2px 0; border-radius: 5px; }
  .badge-row { border-spacing: 3px; }
  .tool-inactive { color: alpha(currentColor, 0.45); box-shadow: inset 0 0 0 1px alpha(currentColor, 0.25); text-decoration-line: line-through; }
  .tool-icon.tool-inactive { text-decoration-line: none; }
  .skill-row { padding: 8px 4px; }
  .status-panel { padding: 12px; }
  .detail { padding: 28px; }
  .file-preview { padding: 14px; }
  """
  for tool in Tool.allCases {
    css += "\n.tool-\(tool.rawValue) { color: \(tool.color); background-color: alpha(\(tool.color), 0.15); }"
  }
  return css
}()
