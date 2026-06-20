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
            if vm.isScheduledCleaning {
                Label("Scheduled clean in progress…", systemImage: "clock.arrow.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(vm.targets) { target in
                TargetRow(target: target) { vm.clean(target) }
                    .disabled(vm.isScheduledCleaning)
            }
            Divider()
            Button("Settings…") {
                openWindow(id: XcodeCleanerApp.settingsWindowID)
                NSApp.activate()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(width: 320)
        .onAppear { vm.scanAll() }
    }
}
