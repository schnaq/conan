import Combine
import Foundation
import Sparkle
import SwiftUI

/// Wraps Sparkle's updater so SwiftUI can drive it: a toggle for automatic
/// checks and a "Check for Updates…" action. The updater itself is the source of
/// truth (Sparkle persists the automatic-check setting in UserDefaults).
@MainActor
final class UpdaterController: ObservableObject {
    private let controller: SPUStandardUpdaterController
    private var cancellables = Set<AnyCancellable>()

    /// Whether a manual check is currently possible (drives the button's enabled state).
    @Published private(set) var canCheckForUpdates = false
    /// Mirror of Sparkle's automatic-check setting, for the toggle.
    @Published private(set) var automaticallyChecksForUpdates: Bool

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        automaticallyChecksForUpdates = controller.updater.automaticallyChecksForUpdates

        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.canCheckForUpdates = $0 }
            .store(in: &cancellables)
    }

    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }

    /// Binding for the "Automatically check for updates" toggle; writing it
    /// updates Sparkle (which persists the choice).
    var automaticChecksBinding: Binding<Bool> {
        Binding(
            get: { self.automaticallyChecksForUpdates },
            set: { newValue in
                self.controller.updater.automaticallyChecksForUpdates = newValue
                self.automaticallyChecksForUpdates = newValue
            }
        )
    }
}
