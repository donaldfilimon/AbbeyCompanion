import Foundation

/// A surface that can execute slash commands. The shared `SlashCommandRunner`
/// drives canonical behavior through these primitives so every surface
/// (GUI, CLI, TUI) behaves consistently.
@MainActor
protocol SlashCommandSurface: AnyObject {
    var ai: AIService { get }
    var projectPath: String? { get }
    var currentModelChoice: String { get }
    var currentWorkMode: String { get }

    var messageCount: Int { get }
    var userMessageCount: Int { get }
    var assistantMessageCount: Int { get }
    var toolCallCount: Int { get }
    var fileChangeCount: Int { get }

    func appendSystemMessage(_ text: String)
    func clearConversation()
    func listFileChanges() -> [FileChange]
    func addFileChange(_ change: FileChange)
    func compactConversation() async
    func exploreProject() async
    func saveConversation()
}

@MainActor
enum SlashCommandRunner {
    /// Runs the canonical behavior for `cmd` against `surface`. Every command
    /// has a real branch here so the GUI, CLI, and TUI stay in parity.
    static func run(_ cmd: SlashCommand, surface: some SlashCommandSurface) async {
        switch cmd {
        case .help:
            surface.appendSystemMessage(SlashCommand.helpText)

        case .clear:
            surface.clearConversation()

        case .compact:
            await surface.compactConversation()

        case .git:
            await runGit(surface)

        case .files:
            runFiles(surface)

        case .model:
            surface.appendSystemMessage(modelInfo(for: surface))

        case .explore:
            await surface.exploreProject()

        case .init_:
            await runInit(surface)

        case .stats:
            surface.appendSystemMessage(stats(for: surface))
        }

        surface.saveConversation()
    }

    private static func runGit(_ surface: some SlashCommandSurface) async {
        guard let path = surface.projectPath else {
            surface.appendSystemMessage("No project open.")
            return
        }
        let result = try? await GitRunner.run(["status"], workingDirectory: path)
        surface.appendSystemMessage(result ?? "Not a git repository")
    }

    private static func runFiles(_ surface: some SlashCommandSurface) {
        let changes = surface.listFileChanges()
        if changes.isEmpty {
            surface.appendSystemMessage("No files modified in this session.")
        } else {
            let list = changes.map { "  [\($0.changeType.rawValue)] \($0.path)" }.joined(separator: "\n")
            surface.appendSystemMessage("Modified files:\n\(list)")
        }
    }

    private static func modelInfo(for surface: some SlashCommandSurface) -> String {
        let current = surface.currentModelChoice
        let all = Conversation.ModelChoice.allCases.map { m in
            let marker = m.rawValue == current ? "← current" : ""
            return "  \(m.rawValue) \(marker)"
        }.joined(separator: "\n")
        return "Current: \(current)\n\n\(all)\n\nChange via Settings."
    }

    private static func runInit(_ surface: some SlashCommandSurface) async {
        guard let path = surface.projectPath else {
            surface.appendSystemMessage("No project open. Open a project first.")
            return
        }
        let treeResult = await surface.ai.respond(to: "List the top-level project structure in a tree format, max 3 levels")
        let treeText: String
        if case .success(let t) = treeResult { treeText = t } else { treeText = "" }
        let agentsMd = ProjectContextLoader.generateAgentsMd(for: path, projectStructure: treeText)
        let agentsPath = (path as NSString).appendingPathComponent("AGENTS.md")
        try? agentsMd.write(toFile: agentsPath, atomically: true, encoding: .utf8)
        surface.appendSystemMessage("Generated AGENTS.md at project root.")
        surface.addFileChange(FileChange(path: agentsPath, changeType: .created))
    }

    private static func stats(for surface: some SlashCommandSurface) -> String {
        let msgs = surface.messageCount
        let user = surface.userMessageCount
        let assistant = surface.assistantMessageCount
        let tools = surface.toolCallCount
        let files = surface.fileChangeCount
        return """
        **Conversation Statistics**

        • Messages: \(msgs) (\(user) user, \(assistant) assistant)
        • Tool calls: \(tools)
        • Files changed: \(files)
        • Input tokens: \(surface.ai.inputTokenCount)
        • Output tokens: \(surface.ai.outputTokenCount)
        • Context window: \(surface.ai.contextWindowUsed) tokens
        • Model: \(surface.currentModelChoice)
        • Mode: \(surface.currentWorkMode)
        """
    }
}
