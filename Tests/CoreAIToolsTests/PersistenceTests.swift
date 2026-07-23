import Foundation
import Testing
@testable import CoreAITools

@MainActor
struct PersistenceTests {

    private func sampleConversation() -> Conversation {
        Conversation(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            title: "Test Chat",
            messages: [
                ChatMessage(role: .user, content: "Hello"),
                ChatMessage(
                    role: .assistant,
                    content: "Hi there",
                    toolCalls: [ToolCallRecord(name: "run_command", argumentsSummary: "ls", status: .completed)]
                )
            ],
            projectPath: "/tmp/project",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100),
            fileChanges: [FileChange(path: "/tmp/project/a.swift", changeType: .modified)],
            modelChoice: .cloudCompute,
            workMode: .plan
        )
    }

    @Test func persistedConversation_roundTripsIdentity() throws {
        let original = sampleConversation()
        let entity = try PersistedConversation(from: original)
        let restored = try #require(entity.toConversation())

        #expect(restored.id == original.id)
        #expect(restored.title == original.title)
        #expect(restored.projectPath == original.projectPath)
        #expect(restored.modelChoice == original.modelChoice)
        #expect(restored.workMode == original.workMode)
        #expect(abs(restored.createdAt.timeIntervalSince(original.createdAt)) < 1)
        #expect(abs(restored.updatedAt.timeIntervalSince(original.updatedAt)) < 1)
    }

    @Test func persistedConversation_preservesMessagesAndFileChanges() throws {
        let original = sampleConversation()
        let entity = try PersistedConversation(from: original)
        let restored = try #require(entity.toConversation())

        #expect(restored.messages.count == 2)
        #expect(restored.messages[0].role == .user)
        #expect(restored.messages[0].content == "Hello")
        #expect(restored.messages[1].toolCalls.first?.name == "run_command")
        #expect(restored.fileChanges.count == 1)
        #expect(restored.fileChanges[0].path == "/tmp/project/a.swift")
        #expect(restored.fileChanges[0].changeType == .modified)
    }

    @Test func persistedConversation_defaultsToSystemModelExecute() throws {
        // A minimal conversation should round-trip with default model/work mode.
        let original = Conversation(title: "Minimal")
        let entity = try PersistedConversation(from: original)
        let restored = try #require(entity.toConversation())
        #expect(restored.modelChoice == .systemDefault)
        #expect(restored.workMode == .execute)
    }
}

@MainActor
struct AppearanceTests {

    private func reset() {
        for key in [
            "appearance.accent",
            "appearance.glassMaterial",
            "appearance.sidebarStyle",
            "appearance.fontSize",
            "appearance.reduceTransparency",
            "appearance.vividGlass"
        ] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    @Test func defaults_matchFactoryValues() {
        reset()
        let settings = AppearanceSettings.shared
        #expect(settings.accent == .indigo)
        #expect(settings.glassMaterial == .thin)
        #expect(settings.sidebarStyle == .glass)
        #expect(settings.fontSize == 14.0)
        #expect(settings.reduceTransparency == false)
        #expect(settings.vividGlass == true)
    }

    @Test func surfaceStyle_respectsReduceTransparency() {
        reset()
        let settings = AppearanceSettings.shared
        settings.reduceTransparency = false
        #expect(String(describing: settings.surfaceStyle).contains("Material"))
        settings.reduceTransparency = true
        #expect(String(describing: settings.surfaceStyle).contains("windowBackgroundColor") ||
                String(describing: settings.surfaceStyle).contains("Color"))
    }

    @Test func everyOptionMapsToAStyle() {
        for accent in AccentColorOption.allCases {
            #expect(!String(describing: accent.color).isEmpty)
        }
        for material in GlassMaterialOption.allCases {
            #expect(String(describing: material.material).contains("Material"))
        }
        #expect(SidebarStyleOption.allCases.count == 2)
    }
}
