import SwiftUI
import SwiftData
import AbbeyCore

struct MessagesView: View {
    @Environment(AbbeyEngine.self) private var engine
    @Query(sort: \GuildMessage.createdAt, order: .reverse) private var messages: [GuildMessage]
    @State private var search = ""
    @State private var channelFilter = ""

    private var filtered: [GuildMessage] {
        messages.filter { message in
            let channelOK = channelFilter.isEmpty
                || message.channelId.localizedCaseInsensitiveContains(channelFilter)
            let searchOK = search.isEmpty
                || message.authorId.localizedCaseInsensitiveContains(search)
                || message.content.localizedCaseInsensitiveContains(search)
                || message.channelId.localizedCaseInsensitiveContains(search)
                || message.guildId.localizedCaseInsensitiveContains(search)
            return channelOK && searchOK
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !channelFilter.isEmpty {
                HStack {
                    Text("Channel filter: #\(channelFilter)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear #\(channelFilter) messages", role: .destructive) {
                        engine.clearChannel(channelId: channelFilter)
                    }
                    .controlSize(.small)
                    Button("Clear filter") { channelFilter = "" }
                        .controlSize(.small)
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }

            if filtered.isEmpty {
                ContentUnavailableView(
                    messages.isEmpty ? "No messages yet" : "No matches",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text(
                        messages.isEmpty
                            ? "Use Dashboard → Simulate a message to populate the log."
                            : "Try a broader filter."
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filtered) { message in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(message.authorId).font(.headline)
                                Button("#\(message.channelId)") {
                                    channelFilter = message.channelId
                                }
                                .buttonStyle(.plain)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                if message.channel != nil {
                                    Image(systemName: "link")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                        .help("Linked to ChannelContext")
                                }
                                if message.policyAction >= 0 {
                                    Text("dqn:\(DQNAction(raw: message.policyAction).label)")
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.tertiary)
                                }
                                Spacer()
                                Text(message.createdAt, style: .time).font(.caption).foregroundStyle(.secondary)
                            }
                            Text(message.content)
                                .textSelection(.enabled)
                            if message.hasPolicy {
                                HStack(spacing: 8) {
                                    Button {
                                        Task { await engine.applyReaction(to: message, reward: 1) }
                                    } label: {
                                        Label("Good", systemImage: "hand.thumbsup")
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .disabled(message.hasPolicyReward)

                                    Button {
                                        Task { await engine.applyReaction(to: message, reward: -1) }
                                    } label: {
                                        Label("Bad", systemImage: "hand.thumbsdown")
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .disabled(message.hasPolicyReward)

                                    if message.reactionCount != 0 {
                                        Text("rx \(message.reactionCount)")
                                            .font(.caption.monospaced())
                                            .foregroundStyle(.secondary)
                                    } else if message.hasPolicyReward {
                                        Text("rewarded")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 2)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                engine.deleteMessage(message)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .contextMenu {
                            if message.hasPolicy && !message.hasPolicyReward {
                                Button("Reward +1") {
                                    Task { await engine.applyReaction(to: message, reward: 1) }
                                }
                                Button("Reward -1") {
                                    Task { await engine.applyReaction(to: message, reward: -1) }
                                }
                            }
                            Button("Delete", role: .destructive) {
                                engine.deleteMessage(message)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Messages")
        .searchable(text: $search, prompt: "Author, channel, guild, or content")
    }
}

#Preview("Messages") {
    let engine = AbbeyStore.makePreviewEngine()
    return MessagesView()
        .environment(engine)
        .modelContainer(engine.modelContainer)
}
