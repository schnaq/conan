import SwiftUI
import ConanCore

/// Add side projects at a percentage and stop them individually. Each shows its
/// live accrued time (percent × elapsed since it was switched on).
struct SideProjectsView: View {
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var ticker: Ticker
    @State private var newName = ""
    @State private var newPercent = 10.0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Side projects")

            ForEach(store.sideProjects) { side in
                row(side)
            }

            HStack(spacing: 6) {
                TextField("project", text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                percentField
                Button("Add", action: add)
                    .disabled(trimmedName.isEmpty)
            }
        }
    }

    private func row(_ side: SideProject) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(side.name)
                Text("\(Int((side.percent * 100).rounded()))%  ·  \(TimeFormat.clock(store.sideAccrued(side, asOf: ticker.now)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
            Button { store.stopSide(side.id) } label: {
                Image(systemName: "stop.circle.fill")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.red)
        }
    }

    private var percentField: some View {
        HStack(spacing: 2) {
            TextField("", value: $newPercent, format: .number)
                .frame(width: 34)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
            Text("%").foregroundStyle(.secondary)
            Stepper("", value: $newPercent, in: 1...100, step: 5)
                .labelsHidden()
        }
    }

    private var trimmedName: String {
        newName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func add() {
        guard !trimmedName.isEmpty, newPercent > 0 else { return }
        store.addSide(project: trimmedName, percent: newPercent / 100.0)
        newName = ""
    }
}
