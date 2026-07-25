import Foundation
import FoundationModels

// MARK: - MCP Server Configuration

package struct MCPServerConfig: Codable, Hashable {
    package let name: String
    package let command: String
    package let args: [String]
    package let env: [String: String]?

    package init(name: String, command: String, args: [String], env: [String: String]? = nil) {
        self.name = name
        self.command = command
        self.args = args
        self.env = env
    }

    static let configPath: String = {
        let home = NSHomeDirectory()
        return "\(home)/.coreai/mcp-servers.json"
    }()
}

// MARK: - MCP Client

@MainActor
@Observable
final class MCPClient {
    private(set) var servers: [String: MCPServerConfig] = [:]
    private(set) var discoveredTools: [MCPToolInfo] = []
    private(set) var connectedServers: Set<String> = []
    private var processes: [String: Process] = [:]
    private var inputPipes: [String: Pipe] = [:]
    private var outputPipes: [String: Pipe] = [:]
    private var requestID: Int = 0

    struct MCPToolInfo: Identifiable, Hashable {
        let id: String
        let serverName: String
        let toolName: String
        let description: String
        let inputSchemaJSON: String
    }

    init() {
        loadConfig()
    }

    // MARK: - Config

    func loadConfig() {
        let path = MCPServerConfig.configPath
        guard FileManager.default.fileExists(atPath: path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return }

        struct ConfigFile: Codable { let servers: [String: MCPServerConfig] }
        if let config = try? JSONDecoder().decode(ConfigFile.self, from: data) {
            servers = config.servers
        }
    }

    func addServer(_ config: MCPServerConfig) {
        servers[config.name] = config
        saveConfig()
    }

    func removeServer(named name: String) {
        disconnect(server: name)
        servers.removeValue(forKey: name)
        saveConfig()
    }

    private func saveConfig() {
        let path = MCPServerConfig.configPath
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        struct ConfigFile: Codable { let servers: [String: MCPServerConfig] }
        let config = ConfigFile(servers: servers)
        if let data = try? JSONEncoder().encode(config) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }

    // MARK: - Connection

    func connect(server name: String) async {
        guard let config = servers[name], !connectedServers.contains(name) else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: config.command)
        process.arguments = config.args

        var env = ProcessInfo.processInfo.environment
        if let extra = config.env { env.merge(extra) { _, new in new } }
        process.environment = env

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
            processes[name] = process
            inputPipes[name] = inputPipe
            outputPipes[name] = outputPipe
            connectedServers.insert(name)

            _ = await sendRequest(server: name, method: "initialize", params: [
                "protocolVersion": "2024-11-05",
                "capabilities": [:],
                "clientInfo": ["name": "CoreAI Assistant", "version": "1.0.0"]
            ])
            sendNotification(server: name, method: "notifications/initialized")
            await discoverTools(server: name)
        } catch {
            print("Failed to start MCP server \(name): \(error)")
        }
    }

    func disconnect(server name: String) {
        processes[name]?.terminate()
        processes.removeValue(forKey: name)
        inputPipes.removeValue(forKey: name)
        outputPipes.removeValue(forKey: name)
        connectedServers.remove(name)
        discoveredTools.removeAll { $0.serverName == name }
    }

    func disconnectAll() {
        for name in connectedServers { disconnect(server: name) }
    }

    // MARK: - Tool Discovery

    private func discoverTools(server name: String) async {
        let response = await sendRequest(server: name, method: "tools/list", params: [:])
        if let result = response["result"] as? [String: Any],
           let tools = result["tools"] as? [[String: Any]] {
            for tool in tools {
                let toolName = tool["name"] as? String ?? "unknown"
                let description = tool["description"] as? String ?? ""
                let schema = tool["inputSchema"] as? [String: Any] ?? [:]
                let schemaJSON = (try? JSONSerialization.data(withJSONObject: schema))
                    .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"

                discoveredTools.append(MCPToolInfo(
                    id: "\(name).\(toolName)",
                    serverName: name,
                    toolName: toolName,
                    description: description,
                    inputSchemaJSON: schemaJSON
                ))
            }
        }
    }

    // MARK: - Tool Execution

    func callTool(serverName: String, toolName: String, arguments: [String: Any]) async -> String {
        let response = await sendRequest(server: serverName, method: "tools/call", params: [
            "name": toolName, "arguments": arguments
        ])
        if let result = response["result"] as? [String: Any],
           let content = result["content"] as? [[String: Any]] {
            return content.compactMap { $0["text"] as? String }.joined(separator: "\n")
        }
        if let error = response["error"] as? [String: Any],
           let message = error["message"] as? String {
            return "MCP Error: \(message)"
        }
        return "(no output from MCP tool)"
    }

    // MARK: - JSON-RPC Transport

    private func sendRequest(server name: String, method: String, params: [String: Any]) async -> [String: Any] {
        guard let inputPipe = inputPipes[name], let outputPipe = outputPipes[name] else {
            return ["error": ["message": "Server not connected"]]
        }
        requestID += 1
        let request: [String: Any] = ["jsonrpc": "2.0", "id": requestID, "method": method, "params": params]
        guard let data = try? JSONSerialization.data(withJSONObject: request),
              let line = String(data: data, encoding: .utf8) else { return ["error": ["message": "Encode failed"]] }

        inputPipe.fileHandleForWriting.write((line + "\n").data(using: .utf8)!)
        let responseData = await readResponse(from: outputPipe, timeout: 10)
        guard let responseData = responseData,
              let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            return ["error": ["message": "No response"]]
        }
        return json
    }

    private func sendNotification(server name: String, method: String) {
        guard let inputPipe = inputPipes[name] else { return }
        let notification: [String: Any] = ["jsonrpc": "2.0", "method": method]
        if let data = try? JSONSerialization.data(withJSONObject: notification),
           let line = String(data: data, encoding: .utf8) {
            inputPipe.fileHandleForWriting.write((line + "\n").data(using: .utf8)!)
        }
    }

    private func readResponse(from pipe: Pipe, timeout: TimeInterval) async -> Data? {
        await Task.detached(priority: .userInitiated) {
            let deadline = Date().addingTimeInterval(timeout)
            var buffer = Data()
            while Date() < deadline {
                let available = pipe.fileHandleForReading.availableData
                if !available.isEmpty {
                    buffer.append(available)
                    if let str = String(data: buffer, encoding: .utf8), str.contains("\n") {
                        if let lineEnd = str.range(of: "\n") {
                            return str[..<lineEnd.lowerBound].data(using: .utf8)
                        }
                    }
                }
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
            return buffer.isEmpty ? nil : buffer
        }.value
    }
}

// MARK: - MCP Tool Wrapper (FoundationModels Tool)

struct MCPToolWrapper: Tool {
    @Generable(description: "Arguments for MCP tool — provide as JSON string")
    struct Arguments {
        @Guide(description: "JSON-encoded arguments for the tool")
        var argumentsJSON: String
    }

    let name: String
    let description: String
    let mcpServerName: String
    let mcpToolName: String
    weak var mcpClient: MCPClient?

    init(client: MCPClient, serverName: String, toolName: String, description: String) {
        self.name = "mcp_\(serverName)_\(toolName)"
        self.description = description
        self.mcpServerName = serverName
        self.mcpToolName = toolName
        self.mcpClient = client
    }

    func call(arguments: Arguments) async throws -> String {
        guard let client = mcpClient else { return "Error: MCP client deallocated" }
        guard let jsonData = arguments.argumentsJSON.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return "Error: Invalid JSON arguments"
        }
        return await client.callTool(serverName: mcpServerName, toolName: mcpToolName, arguments: parsed)
    }
}
