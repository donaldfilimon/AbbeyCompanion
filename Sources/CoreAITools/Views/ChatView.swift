import SwiftUI
import AppKit

struct ChatView: View {
    let store: ConversationStore
    @State private var showTerminal = false
    @State private var showCommandHistory = false

    init(store: ConversationStore) {
        self.store = store
    }

    var body: some View {
        VStack(spacing: 0) {
            MessageListView(store: store)
            Divider()

            QuickActionsBar(store: store)

            // Command history panel
            if showCommandHistory {
                VStack(spacing: 0) {
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Command History")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            showCommandHistory = false
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .coreAIGlass()

                    CommandHistoryView(messages: store.selectedMessages)
                }
                .frame(height: 200)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Terminal output panel
            TerminalOutputView(
                output: lastCommandOutput,
                isVisible: showTerminal
            )
            .animation(.easeInOut, value: showTerminal)

            ApprovalBannerView(gate: store.ai.approvalGate)
                .animation(.easeInOut, value: store.ai.approvalGate.pendingRequest != nil)

            ComposerView(store: store)
            StatusBarView(store: store)
        }
        .navigationTitle(store.selectedConversation?.title ?? "Chat")
        .navigationSubtitle(store.selectedConversation?.projectPath ?? "")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                // Command history toggle
                Button {
                    showCommandHistory.toggle()
                    if showCommandHistory { showTerminal = false }
                } label: {
                    Label("History", systemImage: showCommandHistory ? "clock.arrow.circlepath" : "clock")
                }
                .help("Toggle command history panel")

                // Terminal toggle
                Button {
                    showTerminal.toggle()
                    if showTerminal { showCommandHistory = false }
                } label: {
                    Label("Terminal", systemImage: showTerminal ? "terminal.fill" : "terminal")
                }
                .help("Toggle terminal output panel")

                if let convo = store.selectedConversation {
                    Picker("Mode", selection: Binding(
                        get: { convo.workMode },
                        set: { newMode in store.setWorkMode(newMode) }
                    )) {
                        ForEach(WorkMode.allCases, id: \.self) { mode in
                            Label(mode.rawValue, systemImage: mode.icon)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .help(convo.workMode.description)
                    .frame(width: 200)
                }

                Menu {
                    Button("Export as Markdown…") {
                        if let convo = store.selectedConversation {
                            _ = ConversationExport.save(convo)
                        }
                    }
                    .disabled(store.selectedMessages.isEmpty)

                    Divider()

                    Button("Retry Last Response") {
                        store.retryLastMessage()
                    }
                    .disabled(store.selectedMessages.isEmpty || store.isStreaming)

                    Button("Clear Conversation") {
                        if let id = store.selectedConversationID,
                           let idx = store.conversations.firstIndex(where: { $0.id == id }) {
                            store.conversations[idx].messages.removeAll()
                            store.conversations[idx].fileChanges.removeAll()
                            store.saveAll()
                        }
                    }
                    .disabled(store.selectedMessages.isEmpty)

                    Button("Re-explore Project") {
                        store.autoExploreProject()
                    }
                    .disabled(store.selectedConversation?.projectPath == nil)

                    Divider()

                    Toggle("Require Approval for Destructive Actions", isOn: Binding(
                        get: { store.ai.approvalGate.isApprovalEnabled },
                        set: {
                            store.ai.approvalGate.isApprovalEnabled = $0
                            UserDefaults.standard.set($0, forKey: "requireApprovalForCommands")
                        }
                    ))
                } label: {
                    Label("Options", systemImage: "ellipsis.circle")
                }
            }
        }
    }

    private var lastCommandOutput: String {
        let messages = store.selectedMessages
        for msg in messages.reversed() {
            for call in msg.toolCalls where call.name == "run_command" {
                if let result = call.result {
                    return "$ \(call.argumentsSummary)\n\n\(result)"
                }
            }
        }
        return "No command output yet."
    }
}

private struct MessageListView: View {
    let store: ConversationStore

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(store.selectedMessages) { msg in
                        MessageRow(message: msg, store: store)
                            .id(msg.id)
                            .contextMenu {
                                Button("Copy") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(msg.content, forType: .string)
                                }
                            }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .onChange(of: store.selectedMessages.count) { _, _ in
                withAnimation {
                    proxy.scrollTo(store.selectedMessages.last?.id, anchor: .bottom)
                }
            }
            .onChange(of: store.ai.streamingText) { _, _ in
                proxy.scrollTo(store.streamingMessageID, anchor: .bottom)
            }
        }
    }
}
