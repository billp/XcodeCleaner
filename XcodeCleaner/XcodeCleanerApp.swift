import SwiftUI

@main
struct XcodeCleanerApp: App {
    var body: some Scene {
        MenuBarExtra("Xcode Cleaner", systemImage: "trash") {
            MenuBarView()
        }
        .menuBarExtraStyle(.window)
    }
}
