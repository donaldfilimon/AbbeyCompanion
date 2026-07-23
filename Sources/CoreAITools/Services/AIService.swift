import Foundation
import FoundationModels
import Observation

@MainActor
@Observable
package final class AIService {
    private(set) var isAvailable: Bool = false
    private(set) var availabilityMessage: String = "Checking…"
    private(set) var isResponding: Bool = false
    private(set) var streamingText: String = ""
    private(set) var lastToolCalls: [ToolCallRecord] = []
    private(set) var inputTokenCount: Int = 0
    private(set) var outputTokenCount: Int = 0
    private(set) var contextWindowUsed: Int = 0
    private(set) var modelCapabilities: [String] = []

    let approvalGate = ApprovalGate()

    private var session: LanguageModelSession?
    private var workingDirectory: String = FileManager.default.currentDirectoryPath
    private var lastModelChoice: Conversation.ModelChoice = .systemDefault
    private var lastWorkMode: WorkMode = .execute

    /// Honors the Settings toggles (sampling, temperature, approval) that
    /// are persisted in UserDefaults so changing them in Settings actually
    /// affects generation instead of being ignored.
    package init() {
        let ud = UserDefaults.standard
        if let greedy = ud.object(forKey: "useGreedySampling") as? Bool {
            useGreedySampling = greedy
        }
        if let temp = ud.object(forKey: "temperature") as? Double {
            temperature = temp
        }
        if let require = ud.object(forKey: "requireApprovalForCommands") as? Bool {
            approvalGate.isApprovalEnabled = require
        }
    }

    // Generation options
    var temperature: Double? = nil
    var useGreedySampling: Bool = true

    // MARK: - Availability

    func checkAvailability() {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            isAvailable = true
            availabilityMessage = "Apple Intelligence model ready"
            // Check capabilities (macOS 27+)
            if #available(macOS 27.0, *) {
                let caps = model.capabilities
                modelCapabilities = []
                if caps.contains(.toolCalling) { modelCapabilities.append("Tool Calling") }
                if caps.contains(.guidedGeneration) { modelCapabilities.append("Guided Generation") }
                if caps.contains(.vision) { modelCapabilities.append("Vision") }
                if caps.contains(.reasoning) { modelCapabilities.append("Reasoning") }
            }
        case .unavailable(let reason):
            isAvailable = false
            switch reason {
            case .deviceNotEligible:
                availabilityMessage = "Device not eligible for Apple Intelligence"
            case .appleIntelligenceNotEnabled:
                availabilityMessage = "Apple Intelligence not enabled. Turn it on in System Settings."
            case .modelNotReady:
                availabilityMessage = "Model not ready yet. Try again in a moment."
            @unknown default:
                availabilityMessage = "Model unavailable"
            }
        }
    }

    // MARK: - Session Management

    func startSession(workingDirectory: String, modelChoice: Conversation.ModelChoice = .systemDefault, workMode: WorkMode = .execute, additionalInstructions: String? = nil, additionalTools: [any Tool] = []) {
        self.workingDirectory = workingDirectory
        lastModelChoice = modelChoice
        lastWorkMode = workMode
        // Re-apply persisted sampling/temperature in case Settings changed
        // since this service was created.
        let ud = UserDefaults.standard
        if let greedy = ud.object(forKey: "useGreedySampling") as? Bool {
            useGreedySampling = greedy
        }
        if let temp = ud.object(forKey: "temperature") as? Double {
            temperature = temp
        }
        lastToolCalls = []

        var tools: [any Tool] = buildTools(workingDirectory: workingDirectory, workMode: workMode)
        tools.append(contentsOf: additionalTools)
        var instructions = SystemPrompt.instructions(for: workingDirectory, mode: workMode)
        if let extra = additionalInstructions {
            instructions += extra
        }

        if modelChoice == .cloudCompute, #available(macOS 27.0, *) {
            let cloudModel = PrivateCloudComputeLanguageModel()
            switch cloudModel.availability {
            case .available:
                session = LanguageModelSession(model: cloudModel, tools: tools, instructions: instructions)
            case .unavailable:
                session = LanguageModelSession(model: SystemLanguageModel.default, tools: tools, instructions: instructions)
            }
        } else {
            session = LanguageModelSession(
                model: SystemLanguageModel.default,
                tools: tools,
                instructions: instructions
            )
        }

        // Prewarm for faster first response
        session?.prewarm()
    }

    func clearSession() {
        // Drop the transcript but immediately open a fresh session so the
        // next message still has a model to talk to (a `nil` session would
        // make `streamResponse` fail). This is what `/clear` expects.
        startSession(workingDirectory: workingDirectory, modelChoice: lastModelChoice, workMode: lastWorkMode)
    }

    func buildTools(workingDirectory: String, workMode: WorkMode = .execute) -> [any Tool] {
        let approvalDelegate = ApprovalDelegate(gate: approvalGate)

        let allTools: [any Tool] = [
            ReadFileTool(workingDirectory: workingDirectory),
            WriteFileTool(workingDirectory: workingDirectory, approvalDelegate: approvalDelegate),
            ListFilesTool(workingDirectory: workingDirectory),
            SearchCodeTool(workingDirectory: workingDirectory),
            RunCommandTool(workingDirectory: workingDirectory, approvalDelegate: approvalDelegate),
            ApplyEditTool(workingDirectory: workingDirectory, approvalDelegate: approvalDelegate),
            ProjectStructureTool(workingDirectory: workingDirectory),
            GitStatusTool(workingDirectory: workingDirectory),
            GitDiffTool(workingDirectory: workingDirectory),
            GitLogTool(workingDirectory: workingDirectory),
            GitCommitTool(workingDirectory: workingDirectory, approvalDelegate: approvalDelegate),
            GitBranchTool(workingDirectory: workingDirectory, approvalDelegate: approvalDelegate),
            GitPushTool(workingDirectory: workingDirectory, approvalDelegate: approvalDelegate),
            GitPullTool(workingDirectory: workingDirectory, approvalDelegate: approvalDelegate),
            GitStashTool(workingDirectory: workingDirectory, approvalDelegate: approvalDelegate),
            GitRestoreTool(workingDirectory: workingDirectory, approvalDelegate: approvalDelegate),
            GitAddTool(workingDirectory: workingDirectory, approvalDelegate: approvalDelegate),
            GitShowTool(workingDirectory: workingDirectory),
            GitRemoteTool(workingDirectory: workingDirectory),
        ]

        switch workMode {
        case .execute:
            return allTools
        case .plan, .readOnly:
            return allTools.filter { tool in
                let name = tool.name
                return name != "write_file" &&
                       name != "apply_edit" &&
                       name != "run_command" &&
                       name != "git_commit" &&
                       name != "git_branch" &&
                       name != "git_push" &&
                       name != "git_pull" &&
                       name != "git_stash" &&
                       name != "git_restore" &&
                       name != "git_add"
            }
        }
    }

    // MARK: - Generation Options

    private func makeGenerationOptions() -> GenerationOptions {
        if useGreedySampling {
            return GenerationOptions(samplingMode: .greedy, temperature: temperature, maximumResponseTokens: nil)
        } else {
            return GenerationOptions(samplingMode: .random(top: 10), temperature: temperature, maximumResponseTokens: nil)
        }
    }

    // MARK: - Streaming Response

    func streamResponse(to prompt: String) async -> Result<String, Error> {
        guard let session else {
            return .failure(AIServiceError.noSession)
        }

        isResponding = true
        streamingText = ""
        // Reset per-turn so a text-only reply doesn't keep showing the
        // previous turn's tool calls.
        lastToolCalls = []
        defer { isResponding = false }

        do {
            let options = makeGenerationOptions()
            let stream = session.streamResponse(to: prompt, options: options)
            var fullText = ""

            for try await snapshot in stream {
                let chunk = snapshot.content
                if !chunk.isEmpty {
                    fullText = chunk
                    streamingText = chunk
                }
            }

            extractToolCalls(from: session.transcript)
            updateUsage(from: session)

            return .success(fullText)
        } catch is CancellationError {
            return .success("")
        } catch {
            return .failure(error)
        }
    }

    func cancelStreaming() {
        isResponding = false
    }

    // MARK: - Non-Streaming Response

    func respond(to prompt: String) async -> Result<String, Error> {
        guard let session else {
            return .failure(AIServiceError.noSession)
        }

        do {
            let options = makeGenerationOptions()
            let response = try await session.respond(to: prompt, options: options)
            return .success(response.content)
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Tool Call Extraction

    private func extractToolCalls(from transcript: Transcript) {
        var calls: [ToolCallRecord] = []

        for entry in transcript {
            switch entry {
            case .toolCalls(let toolCalls):
                for call in toolCalls {
                    let needsApproval = ToolCallRecord.approvalRequiredTools.contains(call.toolName)
                    let record = ToolCallRecord(
                        name: call.toolName,
                        argumentsSummary: String(describing: call.arguments).prefix(200).description,
                        status: .completed,
                        requiresApproval: needsApproval,
                        isApproved: true
                    )
                    calls.append(record)
                }
            case .toolOutput(let output):
                let outputText = output.segments
                    .compactMap { segment -> String? in
                        if case .text(let textSeg) = segment {
                            return textSeg.content
                        }
                        return nil
                    }
                    .joined(separator: "\n")

                if let idx = calls.lastIndex(where: { $0.name == output.toolName && $0.result == nil }) {
                    calls[idx].result = String(outputText.prefix(500))
                }
            default:
                break
            }
        }

        if !calls.isEmpty {
            lastToolCalls = calls
        }
    }

    private func updateUsage(from session: LanguageModelSession) {
        if #available(macOS 27.0, *) {
            inputTokenCount = session.usage.input.totalTokenCount
            outputTokenCount = session.usage.output.totalTokenCount
            contextWindowUsed = session.usage.totalTokenCount
        }
    }
}

enum AIServiceError: LocalizedError {
    case noSession
    case modelUnavailable

    var errorDescription: String? {
        switch self {
        case .noSession:
            return "No AI session is active. Open a project first."
        case .modelUnavailable:
            return "The on-device model is not available."
        }
    }
}
