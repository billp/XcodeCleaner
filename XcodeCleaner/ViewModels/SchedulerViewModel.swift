import Foundation
import AppKit

@MainActor
@Observable
final class SchedulerViewModel {
    private let vm: CleanerViewModel
    private let settings: SettingsViewModel
    private let runner: CommandRunning
    private let notifier: Notifying
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?

    var lastFired: Date?
    var pendingFire: Date?
    var originalFire: Date?

    init(vm: CleanerViewModel, settings: SettingsViewModel,
         runner: CommandRunning = CommandRunner(), notifier: Notifying = UserNotifier()) {
        self.vm = vm
        self.settings = settings
        self.runner = runner
        self.notifier = notifier
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.tick(now: Date()) }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.checkMissedScheduleOnWake(now: Date()) }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
    }

    func tick(now: Date) async {
        guard settings.schedulingEnabled else { return }

        if pendingFire == nil {
            guard ScheduleMath.shouldFire(
                now: now,
                weekday: settings.scheduleWeekday,
                hour: settings.scheduleHour,
                minute: settings.scheduleMinute,
                lastFired: lastFired
            ) else { return }
        } else if let pending = pendingFire, pending > now {
            return
        }

        await attemptClean(now: now)
    }

    /// On wake, check if a scheduled clean was missed while the Mac was asleep.
    /// If the most recent scheduled slot has passed and hasn't been fired yet,
    /// run the clean immediately (with the usual build-process guard).
    ///
    /// `now` is injectable (defaulting to the wall clock) so this stays testable
    /// against a fixed reference date, exactly like `tick(now:)`.
    func checkMissedScheduleOnWake(now: Date = Date()) async {
        guard settings.schedulingEnabled else { return }
        guard let slot = ScheduleMath.lastScheduledSlot(
            before: now,
            weekday: settings.scheduleWeekday,
            hour: settings.scheduleHour,
            minute: settings.scheduleMinute
        ) else { return }
        if let lastFired, lastFired >= slot { return }
        await attemptClean(now: now)
    }

    /// Checks for running build processes and either fires the clean or
    /// postpones by one hour (up to 24 hours from the original fire time).
    private func attemptClean(now: Date) async {
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
            .contains { ScheduleMath.isBuildProcess($0) }

        if buildRunning {
            if pendingFire == nil {
                originalFire = now
            }
            if let original = originalFire, now >= ScheduleMath.giveUpTime(originalFire: original) {
                pendingFire = nil
                originalFire = nil
            } else {
                pendingFire = ScheduleMath.postponedFireTime(from: now)
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
