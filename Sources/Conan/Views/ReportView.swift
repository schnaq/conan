import SwiftUI
import ConanCore

/// Today's committed time per project, from `watson report --day --json`.
struct ReportView: View {
    @EnvironmentObject private var store: SessionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionHeader("Today · watson")
                Spacer()
                Button { store.refreshReport() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }

            if let report = store.todayReport, !report.projects.isEmpty {
                ForEach(report.projects.sorted { $0.time > $1.time }) { project in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(project.name)
                            Spacer()
                            Text(TimeFormat.human(project.time))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .font(.callout)
                        ForEach(project.tags.sorted { $0.time > $1.time }, id: \.name) { tag in
                            HStack {
                                Text("#\(tag.name)")
                                Spacer()
                                Text(TimeFormat.human(tag.time))
                                    .monospacedDigit()
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 12)
                        }
                    }
                }
                Divider()
                HStack {
                    Text("Total").fontWeight(.semibold)
                    Spacer()
                    Text(TimeFormat.human(report.time))
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
                .font(.callout)
            } else {
                Text("No tracked time today yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if store.isRunning {
                Text("The current session is written to watson when you stop.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
