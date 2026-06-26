import SwiftUI
import ConanCore

/// Start/stop the main project (with optional tags); shows its live elapsed
/// time and tags while running.
struct MainSectionView: View {
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var ticker: Ticker
    @State private var projectInput = ""
    @State private var tagsInput = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Main project")
            if let main = store.main {
                running(main)
            } else {
                idle
            }
        }
    }

    private func running(_ main: MainSession) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(main.project).font(.headline)
                if !main.tags.isEmpty {
                    Text(main.tags.map { "#\($0)" }.joined(separator: " "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(TimeFormat.clock(store.mainElapsed(asOf: ticker.now)))
                    .font(.system(.title2, design: .monospaced))
                    .contentTransition(.numericText())
            }
            Spacer()
            Button("Stop all") { store.stopAll() }
                .buttonStyle(.borderedProminent)
                .tint(.red)
        }
    }

    private var idle: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                TextField("project name", text: $projectInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(start)
                if !store.recentCombos.isEmpty || !store.projects.isEmpty {
                    Menu {
                        if !store.recentCombos.isEmpty {
                            Section("Recent") {
                                ForEach(store.recentCombos) { combo in
                                    Button(combo.display) { startCombo(combo) }
                                }
                            }
                        }
                        if !store.projects.isEmpty {
                            Section("Projects") {
                                ForEach(store.projects, id: \.self) { name in
                                    Button(name) { startCombo(ProjectTags(project: name, tags: [])) }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 28)
                }
                Button("Start", action: start)
                    .buttonStyle(.borderedProminent)
                    .disabled(trimmed.isEmpty)
            }
            TextField("tags (optional, space-separated)", text: $tagsInput)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .onSubmit(start)
        }
    }

    private var trimmed: String {
        projectInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func start() {
        guard !trimmed.isEmpty else { return }
        startNamed(trimmed)
    }

    private func startNamed(_ name: String) {
        store.startMain(project: name, tags: Tags.parse(tagsInput))
        projectInput = ""
        tagsInput = ""
    }

    /// Start a remembered project+tags variant from the chooser (its tags are
    /// authoritative — the free-text tags field is ignored).
    private func startCombo(_ combo: ProjectTags) {
        store.startMain(project: combo.project, tags: combo.tags)
        projectInput = ""
        tagsInput = ""
    }
}
