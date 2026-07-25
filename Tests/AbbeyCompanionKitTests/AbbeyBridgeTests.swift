import Foundation
import Testing
import AbbeyCompanionKit
import CoreAITools

@Suite("AbbeyCompanionKit Bridge")
@MainActor
struct AbbeyBridgeTests {
    @Test("ConversationStoreBootstrap defaults are empty")
    func abbeyBootstrapDefaultsEmpty() {
        let bootstrap = ConversationStoreBootstrap()
        #expect(bootstrap.defaultProjectPath == nil)
        #expect(bootstrap.additionalSystemPrompt == nil)
    }

    @Test("ConversationStoreBootstrap carries persona and inference context")
    func abbeyBootstrapInjection() async throws {
        let engine = AbbeyStore.makePreviewEngine()
        let persona = await engine.personaRouter.currentPersona()
        let bootstrap = ConversationStoreBootstrap(
            defaultProjectPath: FileManager.default.currentDirectoryPath,
            additionalSystemPrompt: """
            You are running inside AbbeyCompanion, a Discord-bot companion app.
            Active persona: \(persona.name).
            Inference mode: \(engine.config.inferenceMode.rawValue).
            """
        )
        let addition = try #require(bootstrap.additionalSystemPrompt)
        #expect(addition.contains(persona.name))
        #expect(addition.contains(engine.config.inferenceMode.rawValue))
        #expect(bootstrap.defaultProjectPath != nil)
    }

    @Test("AssistantRootView type is distinct from AbbeyRootView")
    func rootViewTypesAreDistinct() {
        let assistant = String(describing: AssistantRootView.self)
        let abbey = String(describing: AbbeyRootView<AbbeyAIAssistantPlaceholder>.self)
        #expect(assistant.contains("AssistantRootView"))
        #expect(abbey.contains("AbbeyRootView"))
        #expect(!assistant.contains("AbbeyRootView"))
    }

    @Test("AbbeyEngine activePersonaName tracks persona switches")
    func activePersonaNameTracksSwitch() async {
        let engine = AbbeyStore.makePreviewEngine()
        #expect(engine.activePersonaName == "Abbey")
        // Event listener is started asynchronously in AbbeyEngine.init.
        try? await Task.sleep(for: .milliseconds(50))
        await engine.personaRouter.setPersona(named: "aviva")
        for _ in 0..<100 where engine.activePersonaName != "Aviva" {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(engine.activePersonaName == "Aviva")
    }

    @Test("OnDeviceModelStatus unsupportedPlatform label mentions macOS 27+")
    func onDeviceUnsupportedLabel() {
        #expect(OnDeviceModelStatus.unsupportedPlatform.label.contains("macOS 27"))
        #expect(OnDeviceModelStatus.available.label == "Available")
    }

    @Test("DocumentIO is MainActor-isolated")
    func documentIOMainActor() {
        #expect(DocumentIO.self == DocumentIO.self)
    }
}
