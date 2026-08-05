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
            if !cleaner.hasFullDiskAccess {
                fullDiskAccessBanner
            }
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
        .onAppear {
            cleaner.refreshFullDiskAccess()
            cleaner.scanAll()
        }
    }

    /// Shown until the user grants Full Disk Access. Scanning `~` for `.build`
    /// folders otherwise walks into TCC-protected locations (other apps' data,
    /// Trash, Desktop/Documents/Downloads) and macOS prompts for each one.
    private var fullDiskAccessBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "lock.shield")
                Text("Grant Full Disk Access").font(.callout).bold()
                Spacer()
            }
            Text("Lets XcodeCleaner scan for .build folders without repeated system permission prompts.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Privacy Settings…") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }
}
