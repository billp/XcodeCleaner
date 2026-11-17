import Foundation
import AppKit

@MainActor
@Observable
final class SchedulerViewModel {
    private let vm: CleanerViewModel
    private let settings: SettingsViewModel
    private let buildDetector: BuildDetecting
    private let notifier: Notifying
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?

    var lastFired: Date?
    var pendingFire: Date?
    var originalFire: Date?

    init(vm: CleanerViewModel, settings: SettingsViewModel,
         buildDetector: BuildDetecting = BuildDetector(), notifier: Notifying = UserNotifier()) {
        self.vm = vm
        self.settings = settings
        self.buildDetector = buildDetector
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
        await checkLowDiskSpace(now: now)
        await checkSchedule(now: now)
    }

    /// When enabled and free space is below `LowDiskMath.threshold`, cleans the
    /// selected targets (at most once per `LowDiskMath.cooldown`). It doesn't
    /// wait for builds to finish — with agents building all day there may never
    /// be a quiet moment, and the disk filling up breaks those builds anyway.
    /// Instead it leaves alone the folders running builds are using.
    func checkLowDiskSpace(now: Date) async {
        guard settings.lowDiskCleanEnabled, !vm.isScheduledCleaning else { return }
        guard let space = vm.refreshDiskSpace(),
              LowDiskMath.shouldClean(space: space, lastRun: settings.lastLowDiskClean, now: now)
        else { return }
        // Can't tell what builds are using → try again next tick.
        guard (try? await buildDetector.pathsInUse()) != nil else { return }

        settings.lastLowDiskClean = now
        // Re-asked before each entry; a failed read mid-clean spares nothing new.
        let result = await vm.runScheduledClean(named: settings.enabledTargetNames, trigger: .lowDisk,
                                                sparing: { [buildDetector] in
                                                    (try? await buildDetector.pathsInUse()) ?? []
                                                })
        if result.count > 0 {
            await notifier.notifyCleanFinished(targetCount: result.count, reclaimedBytes: result.reclaimed,
                                               trigger: .lowDisk)
        }
    }

    private func checkSchedule(now: Date) async {
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
        guard let buildRunning = await isBuildRunning() else { return }

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
            await notifier.notifyCleanFinished(targetCount: result.count, reclaimedBytes: result.reclaimed,
                                               trigger: .scheduled)
        }
        lastFired = now
        pendingFire = nil
        originalFire = nil
    }

    /// Whether any build (Xcode, xcodebuild, SwiftPM, …) is running; `nil` if
    /// the process list couldn't be read.
    private func isBuildRunning() async -> Bool? {
        guard let builds = try? await buildDetector.activeBuilds() else { return nil }
        return !builds.isEmpty
    }
}
