import SwiftUI

struct MenuBarView: View {
    @State private var state = AppState()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Xcode Cleaner").font(.headline)
                Spacer()
                Button { state.scanAll() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
            }
            Text("Reclaimable: \(state.totalText)")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            ForEach(state.targets) { target in
                TargetRow(target: target) { state.clean(target) }
            }
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
        }
        .padding(12)
        .frame(width: 320)
        .onAppear { state.scanAll() }
    }
}
