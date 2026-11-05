import SwiftUI

struct MenuBarView: View {
    let cleaner: CleanerViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                appBadge
                Text("Xcode Cleaner").font(.headline)
                Spacer()
                Button { cleaner.scanAll(force: true) } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .help("Rescan everything now")
            }
            .padding(.horizontal, 8)
            Text("Reclaimable: \(cleaner.totalText)")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 8)
            if let disk = cleaner.diskSpace {
                diskSpaceSummary(disk)
            }
            activeBuildsSummary
            Divider()
            if !cleaner.hasFullDiskAccess {
                fullDiskAccessBanner
            }
            if let pending = cleaner.pendingClean {
                activeBuildsWarning(for: pending)
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
                TargetRow(target: target) { Task { await cleaner.requestClean(target) } }
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
                    Button("Clean") { Task { await cleaner.requestCleanAll() } }
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
        .frame(width: 400)
        .onAppear {
            cleaner.refreshFullDiskAccess()
            cleaner.refreshDiskSpace()
            cleaner.scanAll()
        }
        .onDisappear {
            // A confirmation left open shouldn't fire later against a stale build list.
            cleaner.cancelPendingClean()
        }
        .task {
            // Keep the build count live while the menu is open.
            while !Task.isCancelled {
                await cleaner.refreshActiveBuilds()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    /// A small version of the app icon (gold sparkles on a graphite tile), drawn
    /// natively so it stays crisp and legible at header size — the .icns has
    /// built-in padding that shrinks the sparkles to a speck at this scale.
    private var appBadge: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        return Image(systemName: "sparkles")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(LinearGradient(colors: [Color(red: 1, green: 0.86, blue: 0.2),
                                                     Color(red: 1, green: 0.62, blue: 0.1)],
                                            startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: 24, height: 24)
            .background(LinearGradient(colors: [Color(white: 0.30), Color(white: 0.16)],
                                        startPoint: .top, endPoint: .bottom), in: shape)
            .overlay(shape.strokeBorder(.white.opacity(0.15), lineWidth: 0.5))
            .accessibilityHidden(true)
    }

    /// Free vs. total capacity of the startup volume, with a usage bar that turns
    /// red once free space drops below the low-disk threshold.
    private func diskSpaceSummary(_ disk: DiskSpace) -> some View {
        let tint = cleaner.isDiskSpaceLow ? Color.red : Color.secondary
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Disk free: \(disk.availableText) of \(disk.totalText)")
                Spacer()
                Text(disk.percentFreeText).monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(tint)
            ProgressView(value: 1 - disk.freeFraction)
                .progressViewStyle(.linear)
                .tint(cleaner.isDiskSpaceLow ? .red : .accentColor)
                .controlSize(.small)
        }
        .padding(.horizontal, 8)
        .accessibilityElement(children: .combine)
    }

    /// "3 active builds" followed by one line per build: who started it and what
    /// it's building. Highlighted while anything is building.
    private var activeBuildsSummary: some View {
        let builds = cleaner.activeBuilds
        return VStack(alignment: .leading, spacing: 3) {
            Label {
                Text(builds.isEmpty ? "No active builds"
                     : "\(builds.count) active \(builds.count == 1 ? "build" : "builds")")
            } icon: {
                Image(systemName: "hammer")
            }
            .foregroundStyle(builds.isEmpty ? Color.secondary : Color.orange)
            ForEach(builds, id: \.pid) { build in
                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•").foregroundStyle(.orange)
                        Text(build.source).foregroundStyle(.primary)
                        if let detail = build.detail {
                            Text(detail)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    if let branch = build.branch {
                        Label(branch, systemImage: "arrow.triangle.branch")
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .padding(.leading, 12)
                            .help(branch)
                    }
                }
                .padding(.leading, 22)
            }
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .help("Builds from Xcode, xcodebuild (MCP servers, scripts, fastlane) and SwiftPM")
    }

    /// Asks for confirmation before a manual clean while builds are running —
    /// deleting DerivedData or caches mid-build can make those builds fail.
    private func activeBuildsWarning(for pending: CleanerViewModel.PendingClean) -> some View {
        let builds = cleaner.activeBuilds
        let what: String = switch pending {
        case .target(let target): target.name
        case .all: "everything"
        }
        let count = builds.count == 1 ? "1 build is" : "\(builds.count) builds are"
        return VStack(alignment: .leading, spacing: 6) {
            Label("Builds are running", systemImage: "exclamationmark.triangle.fill")
                .font(.callout).bold()
                .foregroundStyle(.orange)
            Text("\(count) running right now (\(BuildDetection.summary(builds))). "
                 + "Are you sure you want to clean \(what)? The builds may fail.")
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel") { cleaner.cancelPendingClean() }
                    .keyboardShortcut(.cancelAction)
                Button("Clean Anyway", role: .destructive) { cleaner.confirmPendingClean() }
                    .tint(.orange)
                    .buttonStyle(.borderedProminent)
            }
            .controlSize(.small)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.orange.opacity(0.4), lineWidth: 0.5))
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
