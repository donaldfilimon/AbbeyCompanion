import SwiftUI

package struct ShortcutHelpView: View {
    @Environment(\.dismiss) private var dismiss

    package init() {}

    package var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Keyboard Shortcuts")
                .font(.title2.bold())

            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                shortcutRow("Cmd+1", "Dashboard")
                shortcutRow("Cmd+2", "Users")
                shortcutRow("Cmd+3", "Channels")
                shortcutRow("Cmd+4", "Messages")
                shortcutRow("Cmd+5", "Activity")
                shortcutRow("Cmd+6", "Personas")
                shortcutRow("Cmd+7", "Equity Research")
                shortcutRow("Cmd+8", "Statistics")
                shortcutRow("Cmd+9", "AI Assistant")
                Divider().gridCellColumns(2)
                shortcutRow("Cmd+Return", "Ingest & reply (Dashboard)")
                shortcutRow("Cmd+Shift+D", "Seed demo data")
                shortcutRow("Cmd+Shift+K", "Consolidate channels")
                shortcutRow("Cmd+Shift+E", "Export JSON")
                shortcutRow("Cmd+Shift+I", "Import JSON")
                Divider().gridCellColumns(2)
                shortcutRow("Cmd+N", "New conversation (AI)")
                shortcutRow("Cmd+O", "Open project (AI)")
                shortcutRow("Cmd+K", "Clear conversation (AI)")
                shortcutRow("Cmd+Return", "Send message (AI)")
                shortcutRow("Cmd+Esc", "Cancel generation (AI)")
                shortcutRow("Cmd+Shift+Return", "Approve tool call (AI)")
                shortcutRow("Cmd+Shift+Esc", "Reject tool call (AI)")
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 400, height: 500)
    }

    private func shortcutRow(_ key: String, _ action: String) -> some View {
        GridRow {
            Text(key)
                .font(.caption.monospaced().weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
            Text(action)
                .font(.caption)
        }
    }
}
