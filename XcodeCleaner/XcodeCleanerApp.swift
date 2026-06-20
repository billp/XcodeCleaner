import SwiftUI

@main
struct XcodeCleanerApp: App {
    var body: some Scene {
        MenuBarExtra("Xcode Cleaner", systemImage: "trash") {
            Text("Xcode Cleaner")
                .padding()
        }
        .menuBarExtraStyle(.window)
    }
}
