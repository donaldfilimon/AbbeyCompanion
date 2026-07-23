import Foundation
import Testing
@testable import CoreAITools

struct SlashCommandParityTests {
    @Test func allCasesResolveViaParse() {
        for cmd in SlashCommand.allCases {
            #expect(SlashCommand.parse(cmd.trigger) == cmd)
        }
    }

    @Test func parseIsCaseInsensitive() {
        #expect(SlashCommand.parse("/INIT") == .init_)
        #expect(SlashCommand.parse("/Clear") == .clear)
    }

    @MainActor
    @Test func runnerHasBranchForEveryCommand() async {
        let surface = MockSlashSurface()
        for cmd in SlashCommand.allCases {
            await SlashCommandRunner.run(cmd, surface: surface)
        }
        // Every command reaches the runner (clear/compact/explore have their
        // own surface methods; the rest append a system message).
        #expect(surface.handledCommands.contains("clear"))
        #expect(surface.handledCommands.contains("compact"))
        #expect(surface.handledCommands.contains("explore"))
        #expect(surface.handledCommands.contains("files"))
        // help, git, files, model, init_, stats each append a system message.
        #expect(surface.appendCount == 6)
        #expect(surface.handledCommands.count == 6)
    }

    @Test func generateAgentsMdNonEmpty() {
        let md = ProjectContextLoader.generateAgentsMd(for: FileManager.default.currentDirectoryPath, projectStructure: "tree")
        #expect(!md.isEmpty)
        #expect(md.contains("AGENTS.md"))
    }
}

@MainActor
final class MockSlashSurface: SlashCommandSurface {
    let ai = AIService()
    let projectPath: String? = nil
    let currentModelChoice = "On-Device (System)"
    let currentWorkMode = "execute"

    var appendCount = 0
    var handledCommands: Set<String> = []

    var messageCount: Int { 0 }
    var userMessageCount: Int { 0 }
    var assistantMessageCount: Int { 0 }
    var toolCallCount: Int { 0 }
    var fileChangeCount: Int { 0 }

    func appendSystemMessage(_ text: String) {
        appendCount += 1
        handledCommands.insert("append")
    }

    func clearConversation() { handledCommands.insert("clear") }
    func listFileChanges() -> [FileChange] { handledCommands.insert("files"); return [] }
    func addFileChange(_ change: FileChange) { handledCommands.insert("addFileChange") }
    func compactConversation() async { handledCommands.insert("compact") }
    func exploreProject() async { handledCommands.insert("explore") }
    func saveConversation() { handledCommands.insert("save") }
}
