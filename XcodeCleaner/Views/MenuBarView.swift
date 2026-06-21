import SwiftUI

struct MenuBarView: View {
    let vm: CleanerViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Xcode Cleaner").font(.headline)
                Spacer()
                Button("Clean All") { vm.cleanAll() }
                    .disabled(vm.isScheduledCleaning)
                Button { vm.scanAll() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
            }
            Text("Reclaimable: \(vm.totalText)")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            if let status = vm.statusText {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(status).font(.callout).bold()
                    Spacer()
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
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
            .buttonStyle(MenuRowButtonStyle())
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(MenuRowButtonStyle())
        }
        .padding(12)
        .frame(width: 320)
        .onAppear { vm.scanAll() }
    }
}
