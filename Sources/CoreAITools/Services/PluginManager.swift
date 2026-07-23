import Foundation
import FoundationModels
import Observation

// MARK: - Plugin Protocol

package protocol CoreAIPlugin: AnyObject {
    var name: String { get }
    var version: String { get }
    var description: String { get }

    func initialize(context: PluginContext) async
    func getTools() -> [PluginToolDefinition]
    func getCommands() -> [PluginCommand]
    func terminate() async
}

package struct PluginContext {
    package let projectPath: String
    package let logger: PluginLogger
    package let httpClient: PluginHTTPClient

    package init(projectPath: String) {
        self.projectPath = projectPath
        self.logger = PluginLogger()
        self.httpClient = PluginHTTPClient()
    }
}

package final class PluginLogger: @unchecked Sendable {
    package func info(_ message: String) { print("[plugin] \(message)") }
    package func error(_ message: String) { print("[plugin ERROR] \(message)") }
}

package final class PluginHTTPClient: @unchecked Sendable {
    package func get(_ url: String) async -> String? {
        guard let url = URL(string: url) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}

package struct PluginToolDefinition: Identifiable, Hashable {
    package let id: String
    package let name: String
    package let description: String
    package let category: String

    package init(name: String, description: String, category: String = "general") {
        self.id = name
        self.name = name
        self.description = description
        self.category = category
    }
}

package struct PluginCommand: Identifiable, Hashable {
    package let id: String
    package let trigger: String
    package let description: String
    package let handler: String

    package init(trigger: String, description: String, handler: String) {
        self.id = trigger
        self.trigger = trigger
        self.description = description
        self.handler = handler
    }
}

// MARK: - Plugin Manager

@MainActor
@Observable
final class PluginManager {
    private(set) var loadedPlugins: [String: CoreAIPlugin] = [:]
    private(set) var pluginTools: [PluginToolDefinition] = []
    private(set) var pluginCommands: [PluginCommand] = []
    private(set) var pluginErrors: [String: String] = [:]

    /// Maps a plugin tool name to the script that implements it, so tool
    /// invocations from the model can be dispatched to the right script.
    private var scriptByTool: [String: String] = [:]

    /// Returns the script path for a given tool name, if registered.
    func scriptPath(for toolName: String) -> String? {
        scriptByTool[toolName]
    }

    private let globalPluginsDir: String
    private var projectPluginsDir: String?

    init() {
        globalPluginsDir = "\(NSHomeDirectory())/.coreai/plugins"
        loadGlobalPlugins()
    }

    func setProjectPath(_ path: String) {
        projectPluginsDir = "\(path)/.coreai/plugins"
        loadProjectPlugins()
    }

    // MARK: - Loading

    func loadGlobalPlugins() {
        loadPlugins(from: globalPluginsDir)
    }

    func loadProjectPlugins() {
        guard let dir = projectPluginsDir else { return }
        loadPlugins(from: dir)
    }

    private func loadPlugins(from directory: String) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory) else { return }

        guard let entries = try? fm.contentsOfDirectory(atPath: directory) else { return }

        for entry in entries {
            let pluginPath = "\(directory)/\(entry)"

            // Look for plugin.json manifest
            let manifestPath = "\(pluginPath)/plugin.json"
            guard fm.fileExists(atPath: manifestPath) else { continue }

            guard let data = try? Data(contentsOf: URL(fileURLWithPath: manifestPath)),
                  let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                pluginErrors[entry] = "Invalid plugin.json"
                continue
            }

            let name = manifest["name"] as? String ?? entry
            let scriptPath = manifest["script"] as? String ?? "\(pluginPath)/main.sh"

            // Load script-based plugin
            if fm.fileExists(atPath: scriptPath) {
                loadScriptPlugin(name: name, path: pluginPath, scriptPath: scriptPath, manifest: manifest)
            }
        }
    }

    private func loadScriptPlugin(name: String, path: String, scriptPath: String, manifest: [String: Any]) {
        // Register tool definitions from manifest
        if let tools = manifest["tools"] as? [[String: Any]] {
            for tool in tools {
                let toolName = tool["name"] as? String ?? "unknown"
                let toolDesc = tool["description"] as? String ?? ""
                let category = tool["category"] as? String ?? "plugin"
                pluginTools.append(PluginToolDefinition(name: toolName, description: toolDesc, category: category))
                scriptByTool[toolName] = scriptPath
            }
        }

        // Register commands from manifest
        if let commands = manifest["commands"] as? [[String: Any]] {
            for cmd in commands {
                let trigger = cmd["trigger"] as? String ?? ""
                let desc = cmd["description"] as? String ?? ""
                let handler = cmd["handler"] as? String ?? scriptPath
                if !trigger.isEmpty {
                    pluginCommands.append(PluginCommand(trigger: trigger, description: desc, handler: handler))
                }
            }
        }
    }

    // MARK: - Execution

    func executeCommand(_ trigger: String, arguments: [String]) async -> String? {
        guard let cmd = pluginCommands.first(where: { $0.trigger == trigger }) else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [cmd.handler] + arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return "Plugin error: \(error.localizedDescription)"
        }
    }

    /// Runs a registered plugin tool by invoking its backing script with the
    /// convention: `/bin/sh <script> --tool <name> --args <base64-json>`.
    func executeTool(named name: String, arguments: [String: Any]) async -> String {
        guard let script = scriptByTool[name] else { return "Plugin tool not found: \(name)" }

        let argData = (try? JSONSerialization.data(withJSONObject: arguments)) ?? Data()
        let argB64 = argData.base64EncodedString()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script, "--tool", name, "--args", argB64]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return "Plugin error: \(error.localizedDescription)"
        }
    }

    // MARK: - Model Tool Wrappers

    /// Builds `Tool`-conforming wrappers for every registered plugin tool so
    /// they can be surfaced to the model alongside the built-in tools.
    func toolWrappers() -> [any Tool] {
        pluginTools.compactMap { def in
            guard scriptByTool[def.name] != nil else { return nil }
            return PluginScriptToolWrapper(name: def.name, description: def.description, toolName: def.name, manager: self)
        }
    }

    // MARK: - System Prompt Integration

    func systemPromptAddition() -> String? {
        guard !pluginTools.isEmpty else { return nil }

        var lines = ["\n\n## Plugin Tools Available\n"]
        for tool in pluginTools {
            lines.append("- \(tool.name): \(tool.description) [\(tool.category)]")
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Plugin Tool Wrapper (FoundationModels Tool)

/// Adapts a registered plugin tool into a FoundationModels `Tool` so the model
/// can call it directly. Invocations are forwarded to `PluginManager.executeTool`.
struct PluginScriptToolWrapper: Tool {
    @Generable(description: "Arguments for the plugin tool — provide as JSON string")
    struct Arguments {
        @Guide(description: "JSON-encoded arguments for the tool")
        var argumentsJSON: String
    }

    let name: String
    let description: String
    let toolName: String
    weak var manager: PluginManager?

    func call(arguments: Arguments) async throws -> String {
        guard let manager else { return "Error: plugin manager deallocated" }
        guard let data = arguments.argumentsJSON.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "Error: Invalid JSON arguments"
        }
        return await manager.executeTool(named: toolName, arguments: parsed)
    }
}
