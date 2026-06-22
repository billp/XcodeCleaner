import SwiftUI

struct MenuBarView: View {
    let cleaner: CleanerViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Xcode Cleaner").font(.headline)
                Spacer()
                Button { cleaner.scanAll() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
            }
            .padding(.horizontal, 8)
            Text("Reclaimable: \(cleaner.totalText)")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 8)
            Divider()
            if let status = cleaner.statusText {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(status).font(.callout).bold()
                    Spacer()
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            }
            ForEach(cleaner.targets) { target in
                TargetRow(target: target) { cleaner.clean(target) }
                    .disabled(cleaner.isScheduledCleaning)
                    .padding(.horizontal, 8)
            }
            Divider()
            HStack(spacing: 10) {
                Text("Clean All").font(.body)
                Spacer()
                if cleaner.isCleaningAll {
                    ProgressView(value: Double(cleaner.cleanAllCompleted),
                                 total: Double(cleaner.cleanAllTotal))
                        .progressViewStyle(.linear)
                        .frame(width: 72)
                } else {
                    Button("Clean") { cleaner.cleanAll() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(cleaner.isScheduledCleaning)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            Divider()
            VStack(spacing: 0) {
                Button("Settings…") {
                    NSApp.keyWindow?.close()   // dismiss the menu bar popover
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
        .onAppear { cleaner.scanAll() }
    }
}
