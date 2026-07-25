import Foundation

extension ConversationStore: SlashCommandSurface {
    var projectPath: String? { selectedConversation?.projectPath }
    var currentModelChoice: String { selectedConversation?.modelChoice.rawValue ?? "" }
    var currentWorkMode: String { selectedConversation?.workMode.rawValue ?? "" }

    var messageCount: Int { selectedConversation?.messages.count ?? 0 }
    var userMessageCount: Int { selectedConversation?.messages.filter { $0.role == .user }.count ?? 0 }
    var assistantMessageCount: Int { selectedConversation?.messages.filter { $0.role == .assistant }.count ?? 0 }
    var toolCallCount: Int { selectedConversation?.messages.flatMap { $0.toolCalls }.count ?? 0 }
    var fileChangeCount: Int { selectedConversation?.fileChanges.count ?? 0 }

    func appendSystemMessage(_ text: String) {
        guard let convoId = selectedConversationID,
              let idx = conversations.firstIndex(where: { $0.id == convoId }) else { return }
        conversations[idx].messages.append(ChatMessage(role: .system, content: text))
        conversations[idx].updatedAt = Date()
    }

    func clearConversation() {
        guard let convoId = selectedConversationID,
              let idx = conversations.firstIndex(where: { $0.id == convoId }) else { return }
        conversations[idx].messages.removeAll()
        conversations[idx].fileChanges.removeAll()
        conversations[idx].updatedAt = Date()
        ai.clearSession()
    }

    func listFileChanges() -> [FileChange] {
        selectedConversation?.fileChanges ?? []
    }

    func addFileChange(_ change: FileChange) {
        guard let convoId = selectedConversationID,
              let idx = conversations.firstIndex(where: { $0.id == convoId }) else { return }
        if !conversations[idx].fileChanges.contains(where: { $0.path == change.path }) {
            conversations[idx].fileChanges.append(change)
        }
    }

    func compactConversation() async {
        guard let convoId = selectedConversationID else { return }
        await compactConversation(convoId: convoId)
    }

    func exploreProject() async {
        guard let path = selectedConversation?.projectPath else {
            appendSystemMessage("No project open.")
            return
        }
        fileTree.loadProject(at: path)
        autoExploreProject()
        appendSystemMessage("Re-exploring project at \(path)…")
    }

    func saveConversation() {
        saveAll()
    }
}
