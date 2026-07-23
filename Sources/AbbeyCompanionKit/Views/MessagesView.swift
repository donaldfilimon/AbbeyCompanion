import SwiftUI
import SwiftData

struct MessagesView: View {
    @Environment(AbbeyEngine.self) private var engine
    @Query(sort: \GuildMessage.createdAt, order: .reverse) private var messages: [GuildMessage]
    @State private var channelFilter = ""
    @State private var authorFilter = ""
    @State private var contentFilter = ""

    private var filtered: [GuildMessage] {
        messages.filter { message in
            let channelOK = channelFilter.isEmpty
                || message.channelId.localizedCaseInsensitiveContains(channelFilter)
            let authorOK = authorFilter.isEmpty
                || message.authorId.localizedCaseInsensitiveContains(authorFilter)
            let contentOK = contentFilter.isEmpty
                || message.content.localizedCaseInsensitiveContains(contentFilter)
            return channelOK && authorOK && contentOK
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                HStack {
                    TextField("Channel", text: $channelFilter)
                    TextField("Author", text: $authorFilter)
                    TextField("Content", text: $contentFilter)
                }
                .textFieldStyle(.roundedBorder)

                if !channelFilter.isEmpty {
                    HStack {
                        Button("Clear #\(channelFilter) messages", role: .destructive) {
                            engine.clearChannel(channelId: channelFilter)
                        }
                        Spacer()
                    }
                }
            }
            .padding()

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
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(message.authorId).font(.headline)
                                Text("#\(message.channelId)").font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Text(message.createdAt, style: .time).font(.caption).foregroundStyle(.secondary)
                            }
                            Text(message.content)
                                .textSelection(.enabled)
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
                            Button("Delete", role: .destructive) {
                                engine.deleteMessage(message)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Messages")
    }
}
