import SwiftUI
import AppKit
import ConanCore

/// Root of the menu-bar popover.
struct MenuBarContentView: View {
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var updater: UpdaterController
    @State private var launchAtLogin = false
    @State private var reportRange: ReportRange = .today
    @AppStorage(SessionStore.remindWhenIdleDefaultsKey) private var remindWhenIdle = false
    @AppStorage(SessionStore.hideMenuBarClockDefaultsKey) private var hideClock = false

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
                Picker("", selection: $reportRange) {
                    Text("Today").tag(ReportRange.today)
                    Text("Week").tag(ReportRange.week)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                if reportRange == .today {
                    ReportView()
                } else {
                    WeekReportView()
                }
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
                Toggle("Hide timer in menu bar", isOn: $hideClock)
                Toggle("Automatically check for updates", isOn: updater.automaticChecksBinding)
                HStack(spacing: 10) {
                    Text(AppInfo.version)
                        .foregroundStyle(.secondary)
                    Button("Check for Updates…") { updater.checkForUpdates() }
                        .buttonStyle(.borderless)
                        .disabled(!updater.canCheckForUpdates)
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
            store.reconcile()   // reflect a terminal `watson start`/`stop` right away
            store.refreshProjects()
            store.refreshReport()
            launchAtLogin = LoginItem.isEnabled
            if remindWhenIdle { Notifier.requestAuthorization() }
        }
    }

    private enum ReportRange {
        case today, week
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
