import SwiftUI

struct MessageRow: View {
    let message: ChatMessage
    let store: ConversationStore

    var body: some View {
        switch message.role {
        case .system:
            systemMessage
        default:
            chatMessage
        }
    }

    private var chatMessage: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: message.role == .user ? "person.fill" : "cpu")
                .font(.system(size: 16))
                .foregroundStyle(message.role == .user ? Color.accentColor : Color.secondary)
                .frame(width: 28, height: 28)
                .background(message.role == .user ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 8) {
                if message.isStreaming {
                    // Render the live streamed text as it arrives (the model
                    // writes it to `store.ai.streamingText`). Before the first
                    // token shows, fall back to a "Thinking…" placeholder.
                    let live = (message.id == store.streamingMessageID) ? store.ai.streamingText : ""
                    if live.isEmpty {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Thinking…")
                                .foregroundStyle(.secondary)
                                .font(.callout)
                        }
                    } else {
                        MarkdownContentView(content: live)
                    }
                } else if message.content.isEmpty {
                    Text("")
                } else {
                    MarkdownContentView(content: message.content)
                }

                if !message.toolCalls.isEmpty {
                    ForEach(message.toolCalls) { call in
                        ToolCallView(toolCall: call)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                message.role == .user
                    ? AnyShapeStyle(Color.accentColor.opacity(0.10))
                    : AnyShapeStyle(AppearanceSettings.shared.surfaceStyle)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .font(.system(size: AppearanceSettings.shared.fontSize))
        }
    }

    private var systemMessage: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(.init(message.content))
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .font(.system(size: AppearanceSettings.shared.fontSize))
    }
}
