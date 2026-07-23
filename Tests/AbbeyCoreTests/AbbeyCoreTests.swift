import Foundation
import Testing
import AbbeyCore

@Suite("AbbeyCore")
struct AbbeyCoreTests {
    @Test("classify routes greetings and questions")
    func classifyBasics() {
        #expect(IntentClassifier.classify("hey there") == .greeting)
        #expect(IntentClassifier.classify("what is up?") == .question)
        #expect(IntentClassifier.classify("!help") == .command)
        #expect(IntentClassifier.classify("remember I like Zig") == .memoryStore)
        #expect(IntentClassifier.classify("what's my reputation") == .repQuery)
        #expect(IntentClassifier.classify("switch to aviva") == .personaSwitch)
    }

    @Test("classifyStrict demotes empty-ish smallTalk to unknown")
    func classifyStrictUnknown() {
        #expect(IntentClassifier.classifyStrict("🙂") == .unknown)
        #expect(IntentClassifier.classifyStrict("ok sure") == .smallTalk)
    }

    @Test("SentimentAnalyzer produces pinned 18-dim state")
    func sentimentDimension() {
        let state = SentimentAnalyzer.analyze(
            text: "Hello world!",
            authorReputation: 0.5,
            recentReactionCount: 2,
            mentionsSomeone: false,
            isReply: false,
            timestamp: .now,
            channelMessageCountInWindow: 10,
            authorInteractionCount: 3,
            isDirectMessage: false
        )
        #expect(state.count == SentimentAnalyzer.stateDimension)
    }

    @Test("FactorScreen scores clamp to 0...1")
    func factorScoreClamp() {
        let high = FactorScreen.score(.init(momentum: 1, volatilityDampening: 1, syntheticGrowth: 1, noveltyPenalty: 0))
        let low = FactorScreen.score(.init(momentum: -1, volatilityDampening: 0, syntheticGrowth: -1, noveltyPenalty: 1))
        #expect(high >= 0 && high <= 1)
        #expect(low >= 0 && low <= 1)
    }

    @Test("modRequest and parseModCommand")
    func modCommands() {
        #expect(IntentClassifier.classify("!kick spammer being toxic") == .modRequest)
        #expect(IntentClassifier.classify("/ban alice") == .modRequest)
        let parsed = IntentClassifier.parseModCommand("!kick spammer being toxic")
        #expect(parsed?.kind == "kick")
        #expect(parsed?.target == "spammer")
        #expect(parsed?.reason == "being toxic")
    }

    @Test("projectToNetworkInput is 8-dim")
    func projectNetworkInput() {
        let state = SentimentAnalyzer.analyze(
            text: "Hello world!",
            authorReputation: 0.5,
            recentReactionCount: 2,
            mentionsSomeone: false,
            isReply: false,
            timestamp: .now,
            channelMessageCountInWindow: 10,
            authorInteractionCount: 3,
            isDirectMessage: false
        )
        let projected = SentimentAnalyzer.projectToNetworkInput(state)
        #expect(projected.count == SentimentAnalyzer.networkInputDimension)
    }

    @Test("DQNAgent selects in-range action")
    func dqnActionRange() async {
        let agent = DQNAgent(topology: [SentimentAnalyzer.networkInputDimension, 16, 3], seed: 7)
        let state18 = Array(repeating: Float(0.1), count: SentimentAnalyzer.stateDimension)
        let state = SentimentAnalyzer.projectToNetworkInput(state18)
        let action = await agent.selectAction(state: state)
        #expect(action >= 0 && action < 3)
        #expect(DQNAction(raw: action).label.count > 0)
    }

    @Test("suggestCompletions includes slash commands")
    func suggestions() {
        let hits = IntentClassifier.suggestCompletions(for: "!h")
        #expect(hits.contains("!help"))
    }

    @Test("MirrorExportDocument round-trips")
    func mirrorExportRoundTrip() throws {
        let original = MirrorExportDocument(
            exportedAt: Date(timeIntervalSince1970: 1_700_000_000),
            messages: [
                .init(
                    discordMessageId: "m1",
                    channelId: "general",
                    guildId: "g1",
                    authorId: "donald",
                    content: "hey",
                    createdAt: Date(timeIntervalSince1970: 1_700_000_001)
                )
            ],
            users: [
                .init(
                    discordUserId: "donald",
                    guildId: "g1",
                    facts: ["ships Zig"],
                    reputation: 0.72,
                    interactionCount: 3
                )
            ],
            channels: [
                .init(channelId: "general", guildId: "g1", summary: "chat", messageCount: 1)
            ]
        )
        let data = try original.encode()
        let decoded = try MirrorExportDocument.decode(from: data)
        #expect(decoded == original)
    }

    @Test("memory fact extraction")
    func memoryFactExtractionHints() {
        func extract(_ text: String) -> String {
            let lower = text.lowercased()
            if let range = lower.range(of: "remember ") {
                return String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return text
        }
        #expect(extract("remember I ship on Fridays") == "I ship on Fridays")
    }
}
