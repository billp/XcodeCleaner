import SwiftUI

struct SettingsView: View {
    let cleaner: CleanerViewModel
    @Bindable var settings: SettingsViewModel
    let notifier: Notifying

    init(cleaner: CleanerViewModel, settings: SettingsViewModel, notifier: Notifying) {
        self.cleaner = cleaner
        self.settings = settings
        self.notifier = notifier
    }

    var body: some View {
        TabView {
            GeneralTab(settings: settings)
                .tabItem { Label("General", systemImage: "gearshape") }
            ScheduleTab(cleaner: cleaner, settings: settings, notifier: notifier)
                .tabItem { Label("Auto-Clean", systemImage: "clock") }
        }
        .frame(width: 480, height: 460)
    }
}

private struct GeneralTab: View {
    @Bindable var settings: SettingsViewModel

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Start Xcode Cleaner automatically when you log in.")
                    if let error = settings.launchAtLoginError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Section("Scheduled cleaning") {
                if settings.schedulingEnabled {
                    LabeledContent("Next run", value: settings.nextRunText ?? "—")
                    LabeledContent("Targets") {
                        Text(settings.enabledTargetNames.isEmpty
                             ? "None selected"
                             : settings.enabledTargetNames.sorted().joined(separator: ", "))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                } else {
                    LabeledContent("Status", value: "Disabled")
                    Text("Turn on scheduling in the Auto-Clean tab.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Last scheduled clean",
                               value: settings.lastRunText ?? "Never")
            }

            Section("Low disk space cleaning") {
                LabeledContent("Status", value: settings.lowDiskCleanEnabled ? "Enabled" : "Disabled")
                LabeledContent("Last low-disk clean",
                               value: settings.lastLowDiskCleanText ?? "Never")
            }
        }
        .formStyle(.grouped)
    }
}

private struct ScheduleTab: View {
    let cleaner: CleanerViewModel
    @Bindable var settings: SettingsViewModel
    let notifier: Notifying

    private let weekdaySymbols = Calendar.current.weekdaySymbols
    private let thresholdText = LowDiskMath.threshold.formatted(.percent.precision(.fractionLength(0)))

    private var hourMinuteBinding: Binding<Date> {
        Binding(
            get: {
                var comps = DateComponents()
                comps.hour = settings.scheduleHour
                comps.minute = settings.scheduleMinute
                return Calendar.current.date(from: comps) ?? Date()
            },
            set: { newDate in
                let c = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                settings.scheduleHour = c.hour ?? 2
                settings.scheduleMinute = c.minute ?? 0
            }
        )
    }

    private func bindingFor(_ name: String) -> Binding<Bool> {
        Binding(
            get: { settings.enabledTargetNames.contains(name) },
            set: { isOn in
                if isOn { settings.enabledTargetNames.insert(name) }
                else { settings.enabledTargetNames.remove(name) }
            }
        )
    }

    var body: some View {
        Form {
            Section {
                Toggle("Enable scheduled cleaning", isOn: $settings.schedulingEnabled)
                    .onChange(of: settings.schedulingEnabled) { _, isOn in
                        if isOn { Task { await notifier.requestAuthorization() } }
                    }
            } footer: {
                Text("Automatically clean the selected caches on a weekly schedule.")
            }

            Section("When") {
                Picker("Day", selection: $settings.scheduleWeekday) {
                    ForEach(weekdaySymbols.indices, id: \.self) { i in
                        Text(weekdaySymbols[i]).tag(i + 1)  // 1=Sunday…7=Saturday
                    }
                }
                DatePicker("Time", selection: hourMinuteBinding, displayedComponents: .hourAndMinute)
            }
            .disabled(!settings.schedulingEnabled)

            Section {
                Toggle("Clean when free disk space is below \(thresholdText)",
                       isOn: $settings.lowDiskCleanEnabled)
                    .onChange(of: settings.lowDiskCleanEnabled) { _, isOn in
                        if isOn { Task { await notifier.requestAuthorization() } }
                    }
            } header: {
                Text("Low disk space")
            } footer: {
                Text("Checked every minute. Waits while a build is running and runs at most once every "
                     + "\(Int(LowDiskMath.cooldown / 3600)) hours.")
            }

            Section("Targets to auto-clean") {
                ForEach(cleaner.targets) { target in
                    Toggle(target.name, isOn: bindingFor(target.name))
                }
            }
            .disabled(!settings.schedulingEnabled && !settings.lowDiskCleanEnabled)
        }
        .formStyle(.grouped)
    }
}
