import SwiftUI
import AppKit
import ConanCore

/// Root of the menu-bar popover.
struct MenuBarContentView: View {
    @EnvironmentObject private var store: SessionStore
    @State private var launchAtLogin = false
    @AppStorage(SessionStore.remindWhenIdleDefaultsKey) private var remindWhenIdle = false

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
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Start at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { newValue in
                        _ = try? LoginItem.setEnabled(newValue)
                        launchAtLogin = LoginItem.isEnabled
                    }
                Toggle("Remind me when I'm not tracking", isOn: $remindWhenIdle)
                    .onChange(of: remindWhenIdle) { enabled in
                        if enabled { Notifier.requestAuthorization() }
                    }
                HStack {
                    Spacer()
                    Button("Quit") { NSApplication.shared.terminate(nil) }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.checkbox)
            .font(.caption)
        }
        .padding(14)
        .frame(width: 320)
        .onAppear {
            store.refreshProjects()
            store.refreshReport()
            launchAtLogin = LoginItem.isEnabled
            if remindWhenIdle { Notifier.requestAuthorization() }
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
