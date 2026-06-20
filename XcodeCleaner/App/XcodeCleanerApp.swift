import SwiftUI

@main
struct XcodeCleanerApp: App {
    @State private var vm: CleanerViewModel
    @State private var settings: SettingsModel
    private let scheduler: Scheduler

    init() {
        let vm = CleanerViewModel()
        let settings = SettingsModel()
        _vm = State(initialValue: vm)
        _settings = State(initialValue: settings)
        scheduler = Scheduler(vm: vm, settings: settings)
        scheduler.start()
    }

    var body: some Scene {
        MenuBarExtra("Xcode Cleaner", systemImage: "sparkles") {
            MenuBarView(vm: vm)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(vm: vm, settings: settings)
        }
    }
}
