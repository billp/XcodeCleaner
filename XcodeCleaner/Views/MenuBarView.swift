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
            .padding(.horizontal, 8)
            Text("Reclaimable: \(vm.totalText)")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 8)
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
                    .padding(.horizontal, 8)
            }
            Divider()
            HStack(spacing: 10) {
                Text("Clean All").font(.body)
                Spacer()
                Button("Clean") { vm.cleanAll() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(vm.isScheduledCleaning)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            Divider()
            VStack(spacing: 0) {
                Button("Settings…") {
                    openWindow(id: XcodeCleanerApp.settingsWindowID)
                    NSApp.activate()
                }
                .buttonStyle(MenuRowButtonStyle())
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(MenuRowButtonStyle())
            }
        }
        .padding(12)
        .frame(width: 320)
        .onAppear { vm.scanAll() }
    }
}
