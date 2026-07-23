import SwiftUI
import SwiftData

struct ChannelContextsView: View {
    @Environment(AbbeyEngine.self) private var engine
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ChannelContext.updatedAt, order: .reverse) private var channels: [ChannelContext]
    @State private var newChannelId = ""
    @State private var newGuildId = ""

    var body: some View {
        VStack {
            if channels.isEmpty {
                ContentUnavailableView(
                    "No channels tracked",
                    systemImage: "number",
                    description: Text("Ingest a message (auto-tracks) or add a channel below, then consolidate.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(channels) { channel in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("#\(channel.channelId)").font(.headline)
                                Spacer()
                                Text("\(channel.messageCount) msgs")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(channel.summary.isEmpty ? "No summary yet — run Consolidate now." : channel.summary)
                                .font(.caption)
                                .foregroundStyle(channel.summary.isEmpty ? .secondary : .primary)
                                .lineLimit(6)
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 4)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                engine.deleteChannelContext(channelId: channel.channelId)
                            } label: {
                                Label("Untrack", systemImage: "trash")
                            }
                        }
                    }
                }
            }

            Divider()

            HStack {
                TextField("Channel ID", text: $newChannelId)
                TextField("Guild ID", text: $newGuildId)
                Button("Track channel") {
                    let context = ChannelContext(channelId: newChannelId, guildId: newGuildId)
                    modelContext.insert(context)
                    try? modelContext.save()
                    newChannelId = ""
                    newGuildId = ""
                }
                .disabled(newChannelId.isEmpty || newGuildId.isEmpty)

                Button("Consolidate now") {
                    let started = ContinuousClock.now
                    Task {
                        await engine.scheduler.consolidateAllChannels()
                        engine.logInteraction(
                            command: "consolidate",
                            userId: "local",
                            guildId: "companion",
                            succeeded: true,
                            started: started
                        )
                    }
                }
                .disabled(channels.isEmpty)
            }
            .textFieldStyle(.roundedBorder)
            .padding()
        }
        .navigationTitle("Channels")
    }
}
