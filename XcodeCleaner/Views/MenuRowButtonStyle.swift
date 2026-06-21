import SwiftUI

/// Full-width, left-aligned menu-row button (like a native menu item): no border,
/// an accent-colored highlight on hover, and a dim on press.
struct MenuRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Row(configuration: configuration)
    }

    private struct Row: View {
        let configuration: Configuration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .contentShape(Rectangle())
                .foregroundStyle(hovering ? Color.white : Color.primary)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(hovering ? Color.accentColor : Color.clear)
                )
                .opacity(configuration.isPressed ? 0.6 : 1)
                .onHover { hovering = $0 }
        }
    }
}
