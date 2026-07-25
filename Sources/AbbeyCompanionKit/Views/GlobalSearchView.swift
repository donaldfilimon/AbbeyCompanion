import SwiftUI
import SwiftData

package struct GlobalSearchView: View {
    @Environment(AbbeyEngine.self) private var engine
    @Binding var isPresented: Bool
    @State private var query = ""
    @State private var messageResults: [GuildMessage] = []
    @State private var userResults: [UserMemory] = []
    @State private var channelResults: [ChannelContext] = []
    @FocusState private var isFocused: Bool

    package init(engine: AbbeyEngine, isPresented: Binding<Bool>) {
        self._isPresented = isPresented
    }

    package var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search messages, users, channels…", text: $query)
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    .onSubmit { performSearch() }
                if !query.isEmpty {
                    Button { query = ""; clearResults() } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
            .padding(12)

            if query.isEmpty {
                ContentUnavailableView(
                    "Global search",
                    systemImage: "magnifyingglass",
                    description: Text("Search across messages, users, and channels. Press Return to search.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if resultsEmpty {
                ContentUnavailableView(
                    "No results for \"\(query)\"",
                    systemImage: "magnifyingglass",
                    description: Text("Try a different term.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if !messageResults.isEmpty {
                        Section("Messages (\(messageResults.count))") {
                            ForEach(messageResults.prefix(20)) { msg in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(msg.authorId).font(.caption.weight(.semibold))
                                    Text(msg.content).font(.caption).lineLimit(2)
                                    Text("#\(msg.channelId) · \(msg.createdAt, style: .relative)")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                    if !userResults.isEmpty {
                        Section("Users (\(userResults.count))") {
                            ForEach(userResults.prefix(10)) { user in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(user.discordUserId).font(.caption.weight(.semibold))
                                    Text("guild: \(user.guildId) · rep: \(String(format: "%.2f", user.reputation))")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                    if !channelResults.isEmpty {
                        Section("Channels (\(channelResults.count))") {
                            ForEach(channelResults.prefix(10)) { channel in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("#\(channel.channelId)").font(.caption.weight(.semibold))
                                    Text("\(channel.messageCount) msgs · \(channel.summary.prefix(80))")
                                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }
            }
        }
        .frame(minWidth: 280, idealWidth: 320)
        .onAppear { isFocused = true }
    }

    private var resultsEmpty: Bool {
        messageResults.isEmpty && userResults.isEmpty && channelResults.isEmpty
    }

    private func performSearch() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { clearResults(); return }
        let context = ModelContext(engine.modelContainer)
        let needle = trimmed

        let msgDesc = FetchDescriptor<GuildMessage>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        if let msgs = try? context.fetch(msgDesc) {
            messageResults = msgs.filter {
                $0.content.localizedCaseInsensitiveContains(needle)
                    || $0.authorId.localizedCaseInsensitiveContains(needle)
                    || $0.channelId.localizedCaseInsensitiveContains(needle)
            }
        }

        let userDesc = FetchDescriptor<UserMemory>(sortBy: [SortDescriptor(\.reputation, order: .reverse)])
        if let users = try? context.fetch(userDesc) {
            userResults = users.filter {
                $0.discordUserId.localizedCaseInsensitiveContains(needle)
                    || $0.guildId.localizedCaseInsensitiveContains(needle)
                    || $0.facts.contains { $0.localizedCaseInsensitiveContains(needle) }
            }
        }

        let chanDesc = FetchDescriptor<ChannelContext>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        if let chans = try? context.fetch(chanDesc) {
            channelResults = chans.filter {
                $0.channelId.localizedCaseInsensitiveContains(needle)
                    || $0.guildId.localizedCaseInsensitiveContains(needle)
                    || $0.summary.localizedCaseInsensitiveContains(needle)
            }
        }
    }

    private func clearResults() {
        messageResults = []
        userResults = []
        channelResults = []
    }
}
