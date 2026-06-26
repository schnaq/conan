import SwiftUI
import ConanCore

/// Start/stop the main project; shows its live elapsed time while running.
struct MainSectionView: View {
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var ticker: Ticker
    @State private var projectInput = ""

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
        HStack(spacing: 6) {
            TextField("project name", text: $projectInput)
                .textFieldStyle(.roundedBorder)
                .onSubmit(start)
            if !store.projects.isEmpty {
                Menu {
                    ForEach(store.projects, id: \.self) { name in
                        Button(name) { store.startMain(project: name) }
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
    }

    private var trimmed: String {
        projectInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func start() {
        guard !trimmed.isEmpty else { return }
        store.startMain(project: trimmed)
        projectInput = ""
    }
}
