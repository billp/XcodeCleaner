import SwiftUI

struct SettingsView: View {
    let vm: CleanerViewModel
    @Bindable var settings: SettingsModel

    init(vm: CleanerViewModel, settings: SettingsModel) {
        self.vm = vm
        self.settings = settings
    }

    var body: some View {
        TabView {
            GeneralTab(settings: settings)
                .tabItem { Label("General", systemImage: "gear") }
            ScheduleTab(vm: vm, settings: settings)
                .tabItem { Label("Schedule", systemImage: "clock") }
        }
        .frame(width: 420)
    }
}

private struct GeneralTab: View {
    @Bindable var settings: SettingsModel

    var body: some View {
        Form {
            Toggle("Launch at login", isOn: $settings.launchAtLogin)
            if settings.schedulingEnabled {
                Section("Next scheduled clean") {
                    Text(settings.nextRunText ?? "—")
                        .foregroundStyle(.secondary)
                    if settings.enabledTargetNames.isEmpty {
                        Text("No targets selected.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text(settings.enabledTargetNames.sorted().joined(separator: ", "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("Scheduling disabled")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(minWidth: 380)
    }
}

private struct ScheduleTab: View {
    let vm: CleanerViewModel
    @Bindable var settings: SettingsModel

    private let weekdaySymbols = Calendar.current.shortWeekdaySymbols

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
            Toggle("Enable scheduled cleaning", isOn: $settings.schedulingEnabled)

            Section {
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
                        .disabled(!settings.schedulingEnabled)
                }
            }
        }
        .padding(20)
        .frame(minWidth: 380)
    }
}
