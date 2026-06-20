import SwiftUI

struct MenuBarView: View {
    let vm: CleanerViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Xcode Cleaner").font(.headline)
                Spacer()
                Button { vm.scanAll() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
            }
            Text("Reclaimable: \(vm.totalText)")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            ForEach(vm.targets) { target in
                TargetRow(target: target) { vm.clean(target) }
            }
            Divider()
            Button("Settings…") {
                // Open the dedicated Window scene, then bring the (accessory) app
                // forward so the window actually appears in front.
                openWindow(id: XcodeCleanerApp.settingsWindowID)
                NSApp.activate()
            }
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        .padding(12)
        .frame(width: 320)
        .onAppear { vm.scanAll() }
    }
}
