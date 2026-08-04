import SwiftUI
import SwiftData
import AbbeyCore

struct MessagesView: View {
    @Environment(AbbeyEngine.self) private var engine
    @State private var search = ""
    @State private var channelFilter = ""

    var body: some View {
        VStack(spacing: 0) {
            if !channelFilter.isEmpty {
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Text("#\(channelFilter)")
                            .font(.caption.weight(.semibold))
                        Button {
                            channelFilter = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .help("Clear channel filter")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.tint.opacity(0.15), in: Capsule())

                    Spacer()

                    Button("Clear #\(channelFilter) messages", role: .destructive) {
                        engine.clearChannel(channelId: channelFilter)
                    }
                    .controlSize(.small)
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }

            MessageListView(
                channelFilter: $channelFilter,
                search: search,
                engine: engine
            )
            .id(channelFilter)
        }
        .navigationTitle("Messages")
        .searchable(text: $search, prompt: "Author, channel, guild, or content")
    }
}

private struct MessageListView: View {
    @Binding var channelFilter: String
    let search: String
    let engine: AbbeyEngine

    @Query private var messages: [GuildMessage]

    init(channelFilter: Binding<String>, search: String, engine: AbbeyEngine) {
        self._channelFilter = channelFilter
        self.search = search
        self.engine = engine
        let trimmedChannel = channelFilter.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedChannel.isEmpty {
            _messages = Query(sort: \GuildMessage.createdAt, order: .reverse)
        } else {
            _messages = Query(
                filter: #Predicate<GuildMessage> { $0.channelId == trimmedChannel },
                sort: [SortDescriptor(\GuildMessage.createdAt, order: .reverse)]
            )
        }
    }

    private var filtered: [GuildMessage] {
        StoreFilters.filterMessages(messages, channelFilter: "", search: search)
    }

    var body: some View {
        Group {
            if filtered.isEmpty {
                ContentUnavailableView(
                    messages.isEmpty && channelFilter.isEmpty && search.isEmpty
                        ? "No messages yet"
                        : "No matches",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text(emptyDescription)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filtered) { message in
                        MessageRow(
                            message: message,
                            channelFilter: channelFilter,
                            onSelectChannel: { channelFilter = $0 },
                            engine: engine
                        )
                    }
                }
            }
        }
    }

    private var emptyDescription: String {
        if messages.isEmpty && channelFilter.isEmpty && search.isEmpty {
            return "Use Dashboard → Simulate a message to populate the log."
        }
        var parts: [String] = []
        if !channelFilter.isEmpty { parts.append("#\(channelFilter)") }
        let trimmedSearch = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSearch.isEmpty { parts.append("\"\(trimmedSearch)\"") }
        if parts.isEmpty { return "Try a broader filter." }
        return "No matches for \(parts.joined(separator: " · "))."
    }
}

private struct MessageRow: View {
    let message: GuildMessage
    let channelFilter: String
    let onSelectChannel: (String) -> Void
    let engine: AbbeyEngine

    private var isChannelActive: Bool {
        channelFilter == message.channelId
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(message.authorId).font(.headline)
                Button {
                    onSelectChannel(message.channelId)
                } label: {
                    HStack(spacing: 4) {
                        if isChannelActive {
                            Image(systemName: "checkmark")
                                .font(.caption2.weight(.bold))
                        }
                        Text("#\(message.channelId)")
                    }
                    .font(.caption.weight(isChannelActive ? .semibold : .regular))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        isChannelActive ? AnyShapeStyle(.tint.opacity(0.2)) : AnyShapeStyle(.quaternary.opacity(0.4)),
                        in: Capsule()
                    )
                    .overlay(
                        Capsule().stroke(isChannelActive ? Color.accentColor : Color.clear, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .foregroundStyle(isChannelActive ? .primary : .secondary)

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
            Button("Filter #\(message.channelId)") {
                onSelectChannel(message.channelId)
            }
            Button("Delete", role: .destructive) {
                engine.deleteMessage(message)
            }
        }
    }
}

#Preview("Messages") {
    let engine = AbbeyStore.makePreviewEngine()
    return MessagesView()
        .environment(engine)
        .modelContainer(engine.modelContainer)
}
