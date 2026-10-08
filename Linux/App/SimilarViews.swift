import Adwaita
import Foundation

struct SimilarList: View {
  let model: WindowModel
  let pairs: [SimilarPair]

  var view: Body {
    if pairs.isEmpty {
      StatusPage(
        "No similar skills",
        icon: .custom(name: "view-dual-symbolic"),
        description: "Skill Cabinet compares the words your skills use. When two of them cover the same ground, they show up here, so you can merge them."
      )
      .vexpand()
    } else {
      ScrollView {
        List(pairs, selection: Binding { model.selectedPair } set: { id in
          model.selectedPair = id
          model.showDetail = true
        }) { pair in
          SimilarRow(pair: pair)
        }
        .style("navigation-sidebar")
      }
      .hscrollbarPolicy(.never)
      .vexpand()
    }
  }
}

struct SimilarRow: View {
  let pair: SimilarPair

  var view: Body {
    VStack(spacing: 4) {
      HStack(spacing: 6) {
        Text("\(pair.first) + \(pair.second)")
          .ellipsize()
          .heading()
          .halign(.start)
          .hexpand()
        Text("\(percent(pair.score)) alike")
          .caption()
          .numeric()
          .dimLabel()
      }
      Text("Both mention \(list(pair.sharedWords))")
        .wrap()
        .lines(2)
        .ellipsize()
        .xalign(0)
        .dimLabel()
    }
    .style("skill-row")
  }
}

func percent(_ score: Double) -> String {
  score.formatted(.percent.precision(.fractionLength(0)))
}

struct SimilarDetail: View {
  let store: AppStore
  let model: WindowModel
  let pair: SimilarPair
  let keep: Skill.ID

  private var planned: (plan: SkillInstaller.MergePlan?, problem: String?) {
    guard let kept = store.skill(keep), let merged = store.skill(pair.other(than: keep)) else { return (nil, nil) }
    do {
      return (try SkillInstaller.planMerge(merged, into: kept), nil)
    } catch {
      return (nil, error.localizedDescription)
    }
  }

  private func isDrafting(_ plan: SkillInstaller.MergePlan) -> Bool { store.busy.contains("merge:\(plan.id)") }

  var view: Body {
    let (plan, problem) = planned
    return content(plan, problem)
  }

  @ViewBuilder private func content(_ plan: SkillInstaller.MergePlan?, _ problem: String?) -> Body {
    ScrollView {
      VStack(spacing: 28) {
        VStack(spacing: 6) {
          paragraph("\(pair.first) and \(pair.second)", selectable: true).title1()
          paragraph("\(percent(pair.score)) alike. Both mention \(list(pair.sharedWords)).", selectable: true).title4().dimLabel()
        }
        HStack(spacing: 14) {
          [pair.first, pair.second].compactMap(store.skill).map { skill -> AnyView in
            SkillCard(store: store, skill: skill).hexpand()
          }
        }
        DetailSection("Merge") { mergeSection(plan, problem) }
        VStack(spacing: 4) {
          Button("They're Different Skills") { store.dismissPair(pair) }
            .halign(.start)
          paragraph("Skill Cabinet won't pair them again.").caption().dimLabel()
        }
      }
      .style("detail")
      .frame(maxWidth: 820)
    }
    .hscrollbarPolicy(.never)
    .vexpand()
    .alertDialog(
      visible: Binding { model.confirmMerge } set: { model.confirmMerge = $0 },
      heading: plan.map { "Merge \($0.merged.name) into \($0.kept.name)?" } ?? "",
      body: plan?.message(tools: store.tools) ?? "",
      id: "merge"
    )
    .response("Cancel", role: .close) {}
    .response("Merge", appearance: .suggested, role: .default) {
      guard let plan else { return }
      Task { await store.merge(plan) }
    }
  }

  @ViewBuilder private func mergeSection(_ plan: SkillInstaller.MergePlan?, _ problem: String?) -> Body {
    HStack(spacing: 10) {
      Text("Keep the name")
      ToggleGroup(
        selection: Binding { keep } set: { model.keep[pair.id] = $0 },
        values: [pair.first, pair.second],
        id: \.self,
        label: \.self
      )
    }
    .halign(.start)

    if let problem {
      paragraph(problem).dimLabel()
    } else if let plan {
      paragraph(plan.summary(tools: store.tools)).dimLabel()
      if let draft = store.mergeDrafts[plan.id] {
        HStack(spacing: 10) {
          Button("Merge into \(plan.kept.name)") { model.confirmMerge = true }
            .suggested()
            .insensitive(isDrafting(plan))
          Button("Redraft") { Task { await store.draftMerge(plan) } }
            .insensitive(isDrafting(plan))
          if isDrafting(plan) {
            Spinner()
          }
        }
        .halign(.start)
        plainTextEditor(Binding { store.mergeDrafts[plan.id] ?? draft } set: { store.mergeDrafts[plan.id] = $0 })
      } else if isDrafting(plan) {
        HStack(spacing: 8) {
          Spinner()
          Text("Writing the merged SKILL.md…").dimLabel()
        }
        .halign(.start)
      } else {
        Button("Merge with AI") { Task { await store.draftMerge(plan) } }
          .halign(.start)
        paragraph("AI writes one SKILL.md from both. You can read and edit it before anything changes.").caption().dimLabel()
      }
    }
  }
}

private struct SkillCard: View {
  let store: AppStore
  let skill: Skill

  var view: Body {
    VStack(spacing: 8) {
      paragraph(skill.name).heading()
      if !skill.description.isEmpty {
        paragraph(skill.description).lines(6).ellipsize().dimLabel()
      }
      AvailabilityBadges(available: skill.availableIn, tools: store.tools)
        .halign(.start)
      if let usage = store.usage[skill.id] {
        paragraph("Used in \(plural(usage.chats, "chat"))").caption().dimLabel()
      } else {
        paragraph("Not used in the last \(UserDefaults.standard.integer(forKey: "lookbackDays")) days").caption().dimLabel()
      }
      Button("Open SKILL.md") { Desktop.open(skill.skillFile) }
        .flat()
        .halign(.start)
    }
    .style("file-preview")
    .card()
  }
}
