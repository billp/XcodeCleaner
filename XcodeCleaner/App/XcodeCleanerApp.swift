import SwiftUI
import AppKit

@main
struct XcodeCleanerApp: App {
    @State private var cleaner: CleanerViewModel
    @State private var settings: SettingsViewModel
    private let scheduler: SchedulerViewModel
    private let notifier: UserNotifier

    init() {
        Self.terminateOtherInstances()
        let cleaner = CleanerViewModel()
        let settings = SettingsViewModel()
        let notifier = UserNotifier()
        _cleaner = State(initialValue: cleaner)
        _settings = State(initialValue: settings)
        self.notifier = notifier
        scheduler = SchedulerViewModel(vm: cleaner, settings: settings, notifier: notifier)
        scheduler.start()
        settings.reconcileLaunchAtLogin()
        Task { await settings.requestSchedulingAuthorizationIfNeeded(notifier: notifier) }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(cleaner: cleaner)
        } label: {
            Image(systemName: "sparkles")
                .symbolEffect(.variableColor.iterative, isActive: cleaner.isScheduledCleaning)
        }
        .menuBarExtraStyle(.window)

        // A dedicated Window scene (not the Settings scene) — the Settings scene
        // is unreliable when opened from a MenuBarExtra in an LSUIElement app.
        Window("Xcode Cleaner Settings", id: Self.settingsWindowID) {
            SettingsView(cleaner: cleaner, settings: settings, notifier: notifier)
        }
        .windowResizability(.contentSize)
    }

    static let settingsWindowID = "settings"

    /// Ensure a single running instance: terminate any other copies sharing this
    /// bundle identifier so relaunching (from Xcode or the CLI) replaces the old
    /// one instead of stacking another menu-bar icon.
    private static func terminateOtherInstances() {
        let me = NSRunningApplication.current
        for app in NSWorkspace.shared.runningApplications
        where app.bundleIdentifier == me.bundleIdentifier
            && app.processIdentifier != me.processIdentifier {
            app.forceTerminate()
        }
    }
}
