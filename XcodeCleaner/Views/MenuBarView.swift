import SwiftUI

struct MenuBarView: View {
    let vm: CleanerViewModel
    @Environment(\.openSettings) private var openSettings

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
            Button("Settings…") { openSettings() }
                .buttonStyle(.borderless)
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
        }
        .padding(12)
        .frame(width: 320)
        .onAppear { vm.scanAll() }
    }
}
