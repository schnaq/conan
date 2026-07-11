import SwiftUI
import ConanCore

/// The project → tags → total breakdown shared by the today and week reports.
struct ReportBody: View {
    let report: WatsonReport

    var body: some View {
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
    }
}
