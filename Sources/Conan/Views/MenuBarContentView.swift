import SwiftUI
import AppKit
import ConanCore

/// Root of the menu-bar popover.
struct MenuBarContentView: View {
    @EnvironmentObject private var store: SessionStore
    @State private var launchAtLogin = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Conan").font(.headline)
                Spacer()
                Text("time tracker").font(.caption).foregroundStyle(.secondary)
            }

            if !store.watsonAvailable {
                watsonMissing
            } else {
                MainSectionView()
                if store.isRunning {
                    Divider()
                    SideProjectsView()
                }
                Divider()
                ReportView()
            }

            if let error = store.lastError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            Divider()
            HStack {
                Toggle("Start at login", isOn: $launchAtLogin)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .onChange(of: launchAtLogin) { newValue in
                        _ = try? LoginItem.setEnabled(newValue)
                        launchAtLogin = LoginItem.isEnabled
                    }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(width: 320)
        .onAppear {
            store.refreshProjects()
            store.refreshReport()
            launchAtLogin = LoginItem.isEnabled
        }
    }

    private var watsonMissing: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("watson not found", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text("Install watson (e.g. `brew install watson`) and reopen Conan.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
