import SwiftUI
import ConanCore

/// Weekly committed time per project (ISO week, Monday-start) with ‹ ›
/// navigation — made for transferring totals into other tools by hand.
struct WeekReportView: View {
    @EnvironmentObject private var store: SessionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionHeader("Week · watson")
                Spacer()
                Button { store.shiftWeek(by: -1) } label: {
                    Image(systemName: "chevron.left")
                }
                Text(weekLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Button { store.shiftWeek(by: 1) } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(store.weekOffset == 0)
                Button { store.refreshWeekReport() } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)

            if let report = store.weekReport, !report.projects.isEmpty {
                ReportBody(report: report)
            } else if store.weekReport == nil {
                Text("Loading…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("No tracked time this week.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { store.refreshWeekReport() }
    }

    /// "13.11.–19.11." from the report's timespan (`to` is exclusive).
    private var weekLabel: String {
        guard let report = store.weekReport else { return "" }
        let iso = ISO8601DateFormatter()
        guard let from = iso.date(from: report.timespan.from),
              let to = iso.date(from: report.timespan.to)
        else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM."
        let lastDay = to.addingTimeInterval(-86_400)
        return "\(formatter.string(from: from))–\(formatter.string(from: lastDay))"
    }
}
