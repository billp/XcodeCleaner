import Foundation

@MainActor
@Observable
final class Scheduler {
    private let vm: CleanerViewModel
    private let settings: SettingsModel
    private let runner: CommandRunning
    private var timer: Timer?

    internal(set) var lastFired: Date?
    internal(set) var pendingFire: Date?
    internal(set) var originalFire: Date?

    init(vm: CleanerViewModel, settings: SettingsModel, runner: CommandRunning = Shell()) {
        self.vm = vm
        self.settings = settings
        self.runner = runner
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.tick(now: Date()) }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func tick(now: Date) async {
        guard settings.schedulingEnabled else { return }

        if pendingFire == nil {
            guard Scheduling.shouldFire(
                now: now,
                weekday: settings.scheduleWeekday,
                hour: settings.scheduleHour,
                minute: settings.scheduleMinute,
                lastFired: lastFired
            ) else { return }
        } else if let pending = pendingFire, pending > now {
            return
        }

        let psOutput: String
        do {
            let (_, data, _) = try await runner.run("/bin/ps", ["-axo", "comm="])
            psOutput = String(data: data, encoding: .utf8) ?? ""
        } catch {
            return
        }

        let buildRunning = psOutput
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .contains { Scheduling.isBuildProcess($0) }

        if buildRunning {
            if pendingFire == nil {
                originalFire = now
            }
            if let original = originalFire, now >= Scheduling.giveUpTime(originalFire: original) {
                pendingFire = nil
                originalFire = nil
            } else {
                pendingFire = Scheduling.postponedFireTime(from: now)
            }
            return
        }

        _ = await vm.runScheduledClean(named: settings.enabledTargetNames)
        lastFired = now
        pendingFire = nil
        originalFire = nil
    }
}
