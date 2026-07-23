import Foundation
import Observation

// MARK: - ACP (Agent Communication Protocol)

@MainActor
@Observable
final class ACPClient {
    private(set) var connectedAgents: [AgentInfo] = []
    private(set) var messages: [ACPMessage] = []
    private(set) var isListening: Bool = false
    private var serverSocket: Int32 = -1

    /// Working directory used by the throwaway worker sessions spun up during
    /// orchestration. Set by the conversation store when a project is open.
    var orchestrationWorkingDirectory: String?
    /// Executor factory: returns a fresh, isolated `AIService` so sub-agent
    /// work never pollutes the main chat session's transcript.
    var executorFactory: (() -> AIService)?

    struct AgentInfo: Identifiable, Hashable {
        let id: String
        let name: String
        let capabilities: [String]
        let endpoint: String
    }

    struct ACPMessage: Identifiable, Hashable {
        let id: UUID
        let fromAgent: String
        let toAgent: String
        let content: String
        let messageType: MessageType
        let timestamp: Date

        enum MessageType: String, Hashable {
            case task
            case result
            case query
            case response
            case broadcast
        }
    }

    // MARK: - Agent Registration

    func registerAgent(name: String, capabilities: [String], endpoint: String) {
        let agent = AgentInfo(id: name, name: name, capabilities: capabilities, endpoint: endpoint)
        if let idx = connectedAgents.firstIndex(where: { $0.id == name }) {
            connectedAgents[idx] = agent
        } else {
            connectedAgents.append(agent)
        }
    }

    func unregisterAgent(named name: String) {
        connectedAgents.removeAll { $0.id == name }
    }

    // MARK: - Messaging

    func sendTask(to agentName: String, content: String) {
        let msg = ACPMessage(
            id: UUID(), fromAgent: "CoreAI", toAgent: agentName,
            content: content, messageType: .task, timestamp: Date()
        )
        messages.append(msg)
    }

    func sendQuery(to agentName: String, content: String) {
        let msg = ACPMessage(
            id: UUID(), fromAgent: "CoreAI", toAgent: agentName,
            content: content, messageType: .query, timestamp: Date()
        )
        messages.append(msg)
    }

    func broadcast(content: String) {
        let msg = ACPMessage(
            id: UUID(), fromAgent: "CoreAI", toAgent: "*",
            content: content, messageType: .broadcast, timestamp: Date()
        )
        messages.append(msg)
    }

    func receiveMessage(_ msg: ACPMessage) {
        messages.append(msg)
    }

    // MARK: - Workflow Orchestration

    /// Dispatches `task` to each named agent as an isolated in-process
    /// sub-agent and collects their results. Each agent gets its own
    /// `AIService` worker session (built by `executorFactory`) so the main
    /// conversation transcript is never polluted. Returns a combined report.
    func orchestrate(task: String, agents: [String]) async -> String {
        guard let makeExecutor = executorFactory else {
            return "No agent executor configured. Call setExecutorFactory(_:) first."
        }

        let workingDir = orchestrationWorkingDirectory ?? FileManager.default.currentDirectoryPath
        var results: [String] = []

        for agentName in agents {
            sendTask(to: agentName, content: task)

            let worker = makeExecutor()
            worker.checkAvailability()
            worker.startSession(workingDirectory: workingDir, workMode: .execute)

            let prompt = "You are sub-agent '\(agentName)'. Complete the following task and return a concise result:\n\n\(task)"
            let result = await worker.respond(to: prompt)

            switch result {
            case .success(let text):
                results.append("[\(agentName)] \(text)")
                receiveMessage(ACPMessage(
                    id: UUID(), fromAgent: agentName, toAgent: "CoreAI",
                    content: text, messageType: .result, timestamp: Date()
                ))
            case .failure(let error):
                results.append("[\(agentName)] error: \(error.localizedDescription)")
            }
        }

        return results.joined(separator: "\n\n")
    }

    // MARK: - Status

    var statusText: String {
        if connectedAgents.isEmpty {
            return "No agents connected"
        }
        return "\(connectedAgents.count) agent(s): \(connectedAgents.map { $0.name }.joined(separator: ", "))"
    }
}
