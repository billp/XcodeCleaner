import SwiftUI

struct TargetRow: View {
    let target: CleanupTarget
    let onClean: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(target.name).font(.body)
                if case .error(let msg) = target.state {
                    Text(msg).font(.caption).foregroundStyle(.red).lineLimit(1)
                } else {
                    Text(target.sizeText).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            trailing
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private var trailing: some View {
        switch target.state {
        case .cleaning, .scanning:
            ProgressView().controlSize(.small)
        default:
            Button("Clean", action: onClean)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(target.sizeBytes == 0)   // nothing to clean
        }
    }
}
