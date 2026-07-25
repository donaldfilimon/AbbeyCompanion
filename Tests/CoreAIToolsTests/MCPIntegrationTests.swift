import Foundation
import Testing
@testable import CoreAITools

@MainActor
struct MCPIntegrationTests {
    @Test func mcpClient_initializes_empty() {
        let client = MCPClient()
        #expect(client.servers.isEmpty)
        #expect(client.discoveredTools.isEmpty)
        #expect(client.connectedServers.isEmpty)
    }

    @Test func mcpClient_addRemoveServer() {
        let client = MCPClient()
        let config = MCPServerConfig(
            name: "test-server",
            command: "/bin/echo",
            args: ["hello"],
            env: nil
        )
        client.addServer(config)
        #expect(client.servers.count == 1)
        #expect(client.servers["test-server"] != nil)

        client.removeServer(named: "test-server")
        #expect(client.servers.isEmpty)
    }

    @Test func mcpToolInfo_isHashable() {
        let info = MCPClient.MCPToolInfo(
            id: "test.tool",
            serverName: "test",
            toolName: "tool",
            description: "test tool",
            inputSchemaJSON: "{}"
        )
        #expect(info.id == "test.tool")
        #expect(info.serverName == "test")
    }

    @Test func mcpServerConfig_isCodable() throws {
        let config = MCPServerConfig(
            name: "fs",
            command: "npx",
            args: ["@anthropic/mcp-server-filesystem"],
            env: ["NODE_PATH": "/usr/local"]
        )
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(MCPServerConfig.self, from: data)
        #expect(decoded.name == "fs")
        #expect(decoded.command == "npx")
        #expect(decoded.args == ["@anthropic/mcp-server-filesystem"])
    }
}
