import SwiftUI

@main
struct XcodeCleanerApp: App {
    @State private var vm: CleanerViewModel
    @State private var settings: SettingsModel
    private let scheduler: Scheduler
    private let notifier: UserNotifier

    init() {
        let vm = CleanerViewModel()
        let settings = SettingsModel()
        let notifier = UserNotifier()
        _vm = State(initialValue: vm)
        _settings = State(initialValue: settings)
        self.notifier = notifier
        scheduler = Scheduler(vm: vm, settings: settings, notifier: notifier)
        scheduler.start()
        Task { await requestSchedulingAuthorizationIfNeeded(settings: settings, notifier: notifier) }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(vm: vm)
        } label: {
            Image(systemName: "sparkles")
                .symbolEffect(.variableColor.iterative, isActive: vm.isBusy)
        }
        .menuBarExtraStyle(.window)

        // A dedicated Window scene (not the Settings scene) — the Settings scene
        // is unreliable when opened from a MenuBarExtra in an LSUIElement app.
        Window("Xcode Cleaner Settings", id: Self.settingsWindowID) {
            SettingsView(vm: vm, settings: settings, notifier: notifier)
        }
        .windowResizability(.contentSize)
    }

    static let settingsWindowID = "settings"
}
