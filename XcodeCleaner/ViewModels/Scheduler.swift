import Foundation

@MainActor
@Observable
final class Scheduler {
    private let vm: CleanerViewModel
    private let settings: SettingsModel
    private let runner: CommandRunning
    private let notifier: Notifying
    private var timer: Timer?

    var lastFired: Date?
    var pendingFire: Date?
    var originalFire: Date?

    init(vm: CleanerViewModel, settings: SettingsModel,
         runner: CommandRunning = Shell(), notifier: Notifying = UserNotifier()) {
        self.vm = vm
        self.settings = settings
        self.runner = runner
        self.notifier = notifier
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

        let result = await vm.runScheduledClean(named: settings.enabledTargetNames)
        settings.lastScheduledClean = now
        if result.count > 0 {
            await notifier.notifyCleanFinished(targetCount: result.count, reclaimedBytes: result.reclaimed)
        }
        lastFired = now
        pendingFire = nil
        originalFire = nil
    }
}
