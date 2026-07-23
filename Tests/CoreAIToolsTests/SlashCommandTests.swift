import Testing
@testable import CoreAITools

struct SlashCommandTests {
    @Test func parse_validCommands() {
        #expect(SlashCommand.parse("/clear") == .clear)
        #expect(SlashCommand.parse("/help") == .help)
        #expect(SlashCommand.parse("/compact") == .compact)
        #expect(SlashCommand.parse("/git") == .git)
        #expect(SlashCommand.parse("/files") == .files)
        #expect(SlashCommand.parse("/model") == .model)
        #expect(SlashCommand.parse("/explore") == .explore)
        #expect(SlashCommand.parse("/init") == .init_)
        #expect(SlashCommand.parse("/stats") == .stats)
    }

    @Test func parse_invalidCommands() {
        #expect(SlashCommand.parse("hello") == nil)
        #expect(SlashCommand.parse("") == nil)
        #expect(SlashCommand.parse("/unknown") == nil)
    }

    @Test func allCases_count() {
        #expect(SlashCommand.allCases.count == 9)
    }

    @Test func helpText_containsToolCount() {
        #expect(SlashCommand.helpText.contains("19"))
    }

    @Test func triggers_areCorrect() {
        #expect(SlashCommand.clear.trigger == "/clear")
        #expect(SlashCommand.help.trigger == "/help")
        #expect(SlashCommand.init_.trigger == "/init")
    }
}
