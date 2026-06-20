import SwiftUI

struct SettingsView: View {
    let vm: CleanerViewModel
    @Bindable var settings: SettingsModel
    let notifier: Notifying

    init(vm: CleanerViewModel, settings: SettingsModel, notifier: Notifying) {
        self.vm = vm
        self.settings = settings
        self.notifier = notifier
    }

    var body: some View {
        TabView {
            GeneralTab(settings: settings)
                .tabItem { Label("General", systemImage: "gearshape") }
            ScheduleTab(vm: vm, settings: settings, notifier: notifier)
                .tabItem { Label("Schedule", systemImage: "clock") }
        }
        .frame(width: 480, height: 380)
    }
}

private struct GeneralTab: View {
    @Bindable var settings: SettingsModel

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
            } footer: {
                Text("Start Xcode Cleaner automatically when you log in.")
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
                    Text("Turn on scheduling in the Schedule tab.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Last scheduled clean",
                               value: settings.lastRunText ?? "Never")
            }
        }
        .formStyle(.grouped)
    }
}

private struct ScheduleTab: View {
    let vm: CleanerViewModel
    @Bindable var settings: SettingsModel
    let notifier: Notifying

    private let weekdaySymbols = Calendar.current.weekdaySymbols

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

            Section("Targets to auto-clean") {
                ForEach(vm.targets) { target in
                    Toggle(target.name, isOn: bindingFor(target.name))
                }
            }
            .disabled(!settings.schedulingEnabled)
        }
        .formStyle(.grouped)
    }
}
