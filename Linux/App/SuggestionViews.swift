import Adwaita
import Foundation

struct SuggestionList: View {
  let store: AppStore
  let model: WindowModel
  let suggestions: [Suggestion]

  var view: Body {
    if suggestions.isEmpty {
      StatusPage(
        store.isAnalyzing ? "Analyzing…" : "No suggestions yet",
        icon: .custom(name: "dialog-information-symbolic"),
        description: store.isAnalyzing
          ? "Reading your \(min(store.prompts.count, Analyzer.maxMessages)) most recent messages. This takes a minute or two."
          : "Skillscout reads your recent messages and finds tasks you ask for again and again."
      ) {
        if store.isAnalyzing {
          Spinner()
        } else {
          Button("Analyze Now") { Task { await store.analyze() } }
            .pill()
            .suggested()
            .halign(.center)
            .insensitive(store.prompts.isEmpty)
        }
      }
      .vexpand()
    } else {
      ScrollView {
        List(suggestions, id: \.id.uuidString, selection: Binding { model.selectedSuggestion } set: { id in
          model.selectedSuggestion = id
          model.showDetail = true
        }) { suggestion in
          SuggestionRow(suggestion: suggestion)
        }
        .style("navigation-sidebar")
      }
      .hscrollbarPolicy(.never)
      .vexpand()
    }
  }
}

struct SuggestionRow: View {
  let suggestion: Suggestion

  var view: Body {
    VStack(spacing: 4) {
      HStack(spacing: 8) {
        Text(suggestion.title)
          .ellipsize()
          .heading()
          .halign(.start)
          .hexpand()
        if suggestion.savedTo != nil {
          Text("Saved").captionHeading().success()
        } else if suggestion.draft != nil {
          Text("Draft").captionHeading().dimLabel()
        }
      }
      Text(suggestion.summary)
        .wrap()
        .lines(2)
        .ellipsize()
        .xalign(0)
        .dimLabel()
      HStack(spacing: 4) {
        Text("Asked \(suggestion.examples.count) times")
          .caption()
          .dimLabel()
          .halign(.start)
          .hexpand()
        ForEach(suggestion.tools) { ToolBadge(tool: $0) }
          .orientation(.horizontal)
          .style("badge-row")
      }
    }
    .style("skill-row")
  }
}

struct SuggestionDetail: View {
  let store: AppStore
  let suggestion: Suggestion

  private var isDrafting: Bool { store.busy.contains("draft:\(suggestion.id)") }

  private var saveEverywhereNote: String {
    let shared = SkillRoot.all[0]
    let readers = store.tools.filter(shared.readBy.contains).map(\.name)
    let links = SkillInstaller.linkTargets(for: store.tools).map { "\(Paths.abbreviate($0.skillsFolder)) for \($0.name)" }
    var note = "All tools saves it in \(Paths.abbreviate(shared.url))"
    if !readers.isEmpty { note += ", which \(list(readers)) read" }
    if !links.isEmpty { note += ", and links it into \(list(links))" }
    return note + "."
  }

  var view: Body {
    ScrollView {
      VStack(spacing: 28) {
        VStack(spacing: 8) {
          paragraph(suggestion.title, selectable: true).title1()
          paragraph(suggestion.summary, selectable: true).title4()
          paragraph(suggestion.why, selectable: true).dimLabel()
          HStack(spacing: 6) {
            Text("Asked \(suggestion.examples.count) times in \(plural(suggestion.projects.count, "project"))")
              .dimLabel()
            ForEach(suggestion.tools) { ToolBadge(tool: $0) }
              .orientation(.horizontal)
              .style("badge-row")
          }
          .halign(.start)
        }
        DetailSection("Skill") { draftSection }
        DetailSection("Messages that match") {
          ForEach(Array(suggestion.examples.prefix(40))) { prompt in
            VStack(spacing: 4) {
              HStack(spacing: 6) {
                ToolBadge(tool: prompt.tool)
                Text(prompt.project).captionHeading()
                Text(prompt.date.formatted(.dateTime.day().month().year())).caption().dimLabel()
              }
              .halign(.start)
              paragraph(prompt.text, selectable: true)
                .lines(6)
                .ellipsize()
              Separator()
                .padding(6, .top)
            }
          }
        }
        Button("Dismiss This Idea") { store.dismiss(suggestion.id) }
          .destructive()
          .halign(.start)
      }
      .style("detail")
      .frame(maxWidth: 820)
    }
    .hscrollbarPolicy(.never)
    .vexpand()
  }

  @ViewBuilder private var draftSection: Body {
    if let draft = suggestion.draft {
      plainTextEditor(
        Binding { suggestion.draft ?? draft } set: { store.updateDraft(suggestion.id, $0) },
        editable: suggestion.savedTo == nil
      )
      if let saved = suggestion.savedTo {
        paragraph("Saved to \(Paths.abbreviate(URL(fileURLWithPath: saved)))").success()
      } else {
        HStack(spacing: 10) {
          SplitButton()
            .label("Save to All Tools")
            .clicked { Task { await store.save(suggestion.id, to: .everywhere(store.tools)) } }
            .menuModel {
              MenuSection {
                store.tools.map { tool -> AnyView in
                  MenuButton("Save to \(tool.name) only") {
                    Task { await store.save(suggestion.id, to: .tool(tool)) }
                  }
                }
              }
            }
            .suggested()
          Button("Redraft") { Task { await store.draft(suggestion.id) } }
            .insensitive(isDrafting)
          if isDrafting {
            Spinner()
          }
        }
        .halign(.start)
        paragraph(saveEverywhereNote).caption().dimLabel()
      }
    } else if isDrafting {
      HStack(spacing: 8) {
        Spinner()
        Text("Writing the SKILL.md…").dimLabel()
      }
      .halign(.start)
    } else {
      Button("Draft the Skill with AI") { Task { await store.draft(suggestion.id) } }
        .halign(.start)
    }
  }
}
