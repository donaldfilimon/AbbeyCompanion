import SwiftUI

package struct QuickIngestPanel: View {
    @Environment(AbbeyEngine.self) private var engine
    @State private var content = ""
    @State private var channelId = "general"
    @State private var guildId = "dev-guild"
    @State private var authorId = "donald"
    @State private var isIngesting = false
    @State private var isExpanded = false
    @FocusState private var isFocused: Bool

    package init() {}

    package var body: some View {
        VStack(spacing: 0) {
            if isExpanded {
                HStack(spacing: 8) {
                    TextField("Channel", text: $channelId)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                    TextField("Guild", text: $guildId)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                    TextField("Author", text: $authorId)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }

            HStack(spacing: 8) {
                Button {
                    isExpanded.toggle()
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Toggle channel/guild/author fields")

                TextField("Message…", text: $content)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFocused)
                    .onSubmit { Task { await ingest() } }

                Button {
                    Task { await ingest() }
                } label: {
                    if isIngesting {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title3)
                    }
                }
                .buttonStyle(.plain)
                .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isIngesting)
                .keyboardShortcut(.return, modifiers: [.command])
            }
            .padding(10)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func ingest() async {
        isIngesting = true
        defer { isIngesting = false }
        await engine.ingestMessage(
            content: content,
            channelId: channelId,
            guildId: guildId,
            authorId: authorId
        )
        content = ""
    }
}
