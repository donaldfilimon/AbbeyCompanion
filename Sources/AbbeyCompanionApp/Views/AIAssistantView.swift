import SwiftUI
import AbbeyCompanionKit
import CoreAITools

/// Hosts CoreAITools' assistant UI with an explicit bootstrap (no ConversationStore statics).
struct AIAssistantView: View {
    @Environment(AbbeyEngine.self) private var engine
    @State private var bootstrap: ConversationStoreBootstrap?
    @State private var preparedKey: String = ""

    var body: some View {
        Group {
            if let bootstrap {
                AssistantRootView(bootstrap: bootstrap)
                    .id(preparedKey)
            } else {
                ProgressView("Preparing assistant…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: "\(engine.config.inferenceMode.rawValue)|\(engine.activePersonaName)") {
            await prepareBootstrap()
        }
    }

    private func prepareBootstrap() async {
        let mode = engine.config.inferenceMode
        let persona = await engine.personaRouter.currentPersona()
        let key = "\(mode.rawValue)|\(persona.name)"
        let path = resolveDefaultProjectPath()
        let prompt = """
        You are running inside AbbeyCompanion, a Discord-bot companion app.
        Active persona: \(persona.name).
        Inference mode: \(mode.rawValue).
        """
        bootstrap = ConversationStoreBootstrap(
            defaultProjectPath: path,
            additionalSystemPrompt: prompt
        )
        preparedKey = key
    }

    private func resolveDefaultProjectPath() -> String? {
        let candidates: [String] = [
            Bundle.main.bundleURL.deletingLastPathComponent().path,
            FileManager.default.currentDirectoryPath,
            NSHomeDirectory()
        ]
        for path in candidates {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                return path
            }
        }
        return nil
    }
}
