import Testing
@testable import CoreAITools

@MainActor
struct ACPIntegrationTests {
    @Test func acpClient_initializes_empty() {
        let client = ACPClient()
        #expect(client.connectedAgents.isEmpty)
        #expect(client.messages.isEmpty)
        #expect(client.isListening == false)
    }

    @Test func acpClient_registerUnregisterAgent() {
        let client = ACPClient()
        client.registerAgent(name: "coder", capabilities: ["code"], endpoint: "local")
        #expect(client.connectedAgents.count == 1)

        client.unregisterAgent(named: "coder")
        #expect(client.connectedAgents.isEmpty)
    }

    @Test func acpClient_sendTask() {
        let client = ACPClient()
        client.registerAgent(name: "worker", capabilities: ["exec"], endpoint: "local")
        client.sendTask(to: "worker", content: "build the project")
        #expect(client.messages.count == 1)
        #expect(client.messages.first?.toAgent == "worker")
        #expect(client.messages.first?.messageType == .task)
    }

    @Test func acpClient_broadcast() {
        let client = ACPClient()
        client.broadcast(content: "hello all")
        #expect(client.messages.count == 1)
        #expect(client.messages.first?.toAgent == "*")
        #expect(client.messages.first?.messageType == .broadcast)
    }

    @Test func acpClient_statusText() {
        let client = ACPClient()
        #expect(client.statusText == "No agents connected")

        client.registerAgent(name: "a", capabilities: [], endpoint: "x")
        client.registerAgent(name: "b", capabilities: [], endpoint: "y")
        #expect(client.statusText.contains("2 agent(s)"))
    }
}
