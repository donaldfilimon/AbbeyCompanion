import FoundationModels
import Foundation
import Observation

/// Explicit host configuration for `ConversationStore` (no process-global statics).
package struct ConversationStoreBootstrap: Sendable, Equatable {
    package var defaultProjectPath: String?
    package var additionalSystemPrompt: String?

    package init(defaultProjectPath: String? = nil, additionalSystemPrompt: String? = nil) {
        self.defaultProjectPath = defaultProjectPath
        self.additionalSystemPrompt = additionalSystemPrompt
    }
}

@MainActor
@Observable
package final class ConversationStore {
    var conversations: [Conversation] = []
    var selectedConversationID: UUID?
    var ai = AIService()
    var fileTree = FileTreeService()
    var fileWatcher = FileWatcherService()
    var mcpClient = MCPClient()
    var skillsService = SkillsService()
    var pluginManager = PluginManager()
    var acpClient = ACPClient()

    var isStreaming: Bool = false
    var streamingMessageID: UUID?
    var streamingConversationID: UUID?
    var searchQuery: String = ""

    var streamingTask: Task<Void, Never>?
    let autoCompactThreshold = 8000
    private let bootstrap: ConversationStoreBootstrap

    var selectedConversation: Conversation? {
        guard let id = selectedConversationID else { return nil }
        return conversations.first { $0.id == id }
    }

    var selectedMessages: [ChatMessage] {
        selectedConversation?.messages ?? []
    }

    var fileChanges: [FileChange] {
        selectedConversation?.fileChanges ?? []
    }

    var filteredConversations: [Conversation] {
        guard !searchQuery.isEmpty else { return conversations }
        return conversations.filter { convo in
            convo.title.localizedCaseInsensitiveContains(searchQuery) ||
            convo.messages.contains { $0.content.localizedCaseInsensitiveContains(searchQuery) }
        }
    }

    // MARK: - Init

    package init(bootstrap: ConversationStoreBootstrap = .init()) {
        self.bootstrap = bootstrap
        conversations = ConversationPersistence.load()
        if conversations.isEmpty, let path = bootstrap.defaultProjectPath {
            newConversation(projectPath: path)
            return
        }
        if let first = conversations.first {
            selectedConversationID = first.id
            if let path = first.projectPath {
                skillsService.setProjectPath(path)
                pluginManager.setProjectPath(path)
                configureACP(for: path)
                ai.startSession(
                    workingDirectory: path,
                    modelChoice: first.modelChoice,
                    workMode: first.workMode,
                    additionalInstructions: composeAdditionalInstructionsForSession(),
                    additionalTools: additionalModelTools()
                )
                fileTree.loadProject(at: path)
                startFileWatch(at: path)
            }
        }
    }

    /// Merges skills‑sourced prompt additions with host-provided Abbey/persona context.
    func composeAdditionalInstructionsForSession() -> String? {
        let parts = [
            skillsService.systemPromptAddition(),
            bootstrap.additionalSystemPrompt
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }

    // MARK: - File Watching

    private func startFileWatch(at path: String) {
        fileWatcher.startWatching(path: path) { [weak self] in
            self?.fileTree.loadProject(at: path)
        }
    }

    // MARK: - Conversation Management

    func newConversation(projectPath: String? = nil, modelChoice: Conversation.ModelChoice = .systemDefault, workMode: WorkMode = .execute) {
        cancelStreaming()

        let convo = Conversation(projectPath: projectPath, modelChoice: modelChoice, workMode: workMode)
        conversations.append(convo)
        selectedConversationID = convo.id

        if let path = projectPath {
            skillsService.setProjectPath(path)
            pluginManager.setProjectPath(path)
            configureACP(for: path)

            ai.startSession(
                workingDirectory: path,
                modelChoice: modelChoice,
                workMode: workMode,
                additionalInstructions: composeAdditionalInstructionsForSession(),
                additionalTools: additionalModelTools()
            )
            fileTree.loadProject(at: path)
            startFileWatch(at: path)

            if let contextAddition = ProjectContextLoader.loadContext(from: path) {
                let contextMsg = ChatMessage(role: .system, content: "📋 Loaded project context:\n\(contextAddition)")
                if let idx = conversations.firstIndex(where: { $0.id == convo.id }) {
                    conversations[idx].messages.append(contextMsg)
                }
            }

            autoExploreProject()
        }
        saveAll()
    }

    func select(_ id: UUID) {
        cancelStreaming()
        selectedConversationID = id
        if let convo = conversations.first(where: { $0.id == id }) {
            if let path = convo.projectPath {
                ai.startSession(
                    workingDirectory: path,
                    modelChoice: convo.modelChoice,
                    workMode: convo.workMode,
                    additionalInstructions: composeAdditionalInstructionsForSession(),
                    additionalTools: additionalModelTools()
                )
                fileTree.loadProject(at: path)
                startFileWatch(at: path)
                skillsService.setProjectPath(path)
                pluginManager.setProjectPath(path)
                configureACP(for: path)
            } else {
                ai.clearSession()
                fileWatcher.stopWatching()
            }
        }
    }

    func delete(_ id: UUID) {
        if id == streamingConversationID {
            cancelStreaming()
        }

        conversations.removeAll { $0.id == id }
        if selectedConversationID == id {
            selectedConversationID = conversations.first?.id
            if let newId = selectedConversationID {
                select(newId)
            } else {
                fileWatcher.stopWatching()
                ai.clearSession()
            }
        }
        saveAll()
    }

    func saveAll() {
        let persistable = conversations.map { convo -> Conversation in
            var c = convo
            c.messages = c.messages.map { msg in
                var m = msg
                m.isStreaming = false
                return m
            }
            return c
        }
        ConversationPersistence.save(persistable)
    }

    // MARK: - Send Message

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        if let cmd = SlashCommand.parse(trimmed) {
            Task { await SlashCommandRunner.run(cmd, surface: self) }
            return
        }

        guard let convoId = selectedConversationID,
              let idx = conversations.firstIndex(where: { $0.id == convoId }) else { return }

        let userMsg = ChatMessage(role: .user, content: trimmed)
        conversations[idx].messages.append(userMsg)
        conversations[idx].updatedAt = Date()

        if conversations[idx].title == "New Conversation" {
            conversations[idx].title = String(trimmed.prefix(40))
        }

        streamingConversationID = convoId
        streamingTask = Task {
            await self.streamAssistantResponse(to: trimmed, convoId: convoId)
        }
    }

    // MARK: - Auto Explore

    func autoExploreProject() {
        guard let convo = selectedConversation, convo.projectPath != nil else { return }
        let convoId = convo.id
        Task { [weak self] in
            guard let self = self else { return }
            let result = await self.ai.respond(to: "Briefly explore this project structure and tell me what kind of project this is, what languages/frameworks it uses, and key entry points. Keep it under 3 sentences.")
            if case .success(let text) = result, !text.isEmpty {
                if let idx = conversations.firstIndex(where: { $0.id == convoId }) {
                    let exploreMsg = ChatMessage(role: .assistant, content: "📋 **Project Overview**\n\n\(text)")
                    conversations[idx].messages.insert(exploreMsg, at: 0)
                }
            }
        }
    }

    // MARK: - Work Mode

    func setWorkMode(_ mode: WorkMode) {
        guard let id = selectedConversationID,
              let idx = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[idx].workMode = mode
        if let path = conversations[idx].projectPath {
            ai.startSession(workingDirectory: path, modelChoice: conversations[idx].modelChoice, workMode: mode)
        }
        saveAll()
    }

    // MARK: - Model tools / ACP

    func additionalModelTools() -> [any Tool] {
        var tools: [any Tool] = mcpClient.discoveredTools.map { info in
            MCPToolWrapper(
                client: mcpClient,
                serverName: info.serverName,
                toolName: info.toolName,
                description: info.description
            )
        }
        tools.append(contentsOf: pluginManager.toolWrappers())
        return tools
    }

    func configureACP(for path: String) {
        acpClient.orchestrationWorkingDirectory = path
        acpClient.executorFactory = { AIService() }
    }

    func connectMCPServer(named name: String) {
        Task {
            await mcpClient.connect(server: name)
        }
    }

    func refreshModelStatus() {
        ai.checkAvailability()
    }
}
