import SwiftUI

struct WelcomeView: View {
    let onNewConversation: () -> Void
    let onOpenProject: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Logo / icon
            VStack(spacing: 12) {
                Image(systemName: "cpu")
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)
                    .glassEffect(in: RoundedRectangle(cornerRadius: 24))

                Text("CoreAI Assistant")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("AI coding assistant powered by Apple Intelligence")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            // Feature highlights
            HStack(spacing: 24) {
                FeatureColumn(
                    icon: "doc.text", title: "19 Tools",
                    subtitle: "Read, write, search,\ngit, shell commands"
                )
                FeatureColumn(
                    icon: "shield", title: "Approval Gates",
                    subtitle: "Confirm before\ndestructive actions"
                )
                FeatureColumn(
                    icon: "terminal", title: "CLI + TUI",
                    subtitle: "Full terminal mode\nwith streaming"
                )
                FeatureColumn(
                    icon: "puzzlepiece.extension", title: "Plugins + MCP",
                    subtitle: "Extensible with\nexternal tools"
                )
            }

            // Action buttons
            HStack(spacing: 16) {
                Button {
                    onOpenProject()
                } label: {
                    Label("Open Project", systemImage: "folder.badge.plus")
                        .frame(width: 140)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    onNewConversation()
                } label: {
                    Label("New Conversation", systemImage: "plus.circle")
                        .frame(width: 140)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            // Quick start hint
            Text("Tip: Drag a folder onto the window to start instantly")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppearanceSettings.shared.surfaceStyle)
    }
}

private struct FeatureColumn: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.tint)
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(width: 120)
    }
}
