import Foundation
import Testing
@testable import CoreAITools

@MainActor
struct PluginLifecycleTests {
    /// A temporary, empty skills directory so tests don't depend on the
    /// developer's real `~/.coreai/skills`.
    private func emptySkillsDir() -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("coreai-tests-\(UUID().uuidString)")
            .appendingPathComponent(".coreai/skills")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.path
    }

    @Test func pluginManager_initializes_empty() {
        let manager = PluginManager()
        #expect(manager.loadedPlugins.isEmpty)
        #expect(manager.pluginTools.isEmpty)
        #expect(manager.pluginCommands.isEmpty)
    }

    @Test func pluginManager_loadGlobalSkills_noCrash() {
        let manager = PluginManager()
        manager.loadGlobalPlugins()
        // Should not crash even if no plugins directory exists
        #expect(manager.pluginErrors.count >= 0)
    }

    @Test func skillsService_initializes_empty() {
        let service = SkillsService(globalSkillsDir: emptySkillsDir())
        #expect(service.skills.isEmpty)
    }

    @Test func skillsService_systemPromptAddition_nil_when_empty() {
        let service = SkillsService(globalSkillsDir: emptySkillsDir())
        #expect(service.systemPromptAddition() == nil)
    }

    @Test func skillsService_setProjectPath_noCrash() {
        let service = SkillsService(globalSkillsDir: emptySkillsDir())
        service.setProjectPath("/tmp/nonexistent")
        #expect(service.skills.isEmpty)
    }

    /// Builds a throwaway project dir containing one script-based plugin with a
    /// single tool, and returns the project path.
    private func projectWithPlugin() throws -> String {
        let project = FileManager.default.temporaryDirectory
            .appendingPathComponent("coreai-plugin-tests-\(UUID().uuidString)")
        let pluginDir = project.appendingPathComponent(".coreai/plugins/demo")
        try FileManager.default.createDirectory(at: pluginDir, withIntermediateDirectories: true)

        let manifest = """
        {
            "name": "demo",
            "tools": [{"name": "demo_ping", "description": "Ping the plugin", "category": "plugin"}]
        }
        """
        try manifest.write(to: pluginDir.appendingPathComponent("plugin.json"),
                        atomically: true, encoding: .utf8)

        let script = "#!/bin/sh\necho \"ran:$2 args:$4\"\n"
        try script.write(to: pluginDir.appendingPathComponent("main.sh"),
                         atomically: true, encoding: .utf8)

        return project.path
    }

    @Test func pluginManager_wiresToolsIntoModel() async throws {
        let manager = PluginManager()
        let project = try projectWithPlugin()
        manager.setProjectPath(project)

        #expect(manager.pluginTools.contains { $0.name == "demo_ping" })
        let wrappers = manager.toolWrappers()
        #expect(wrappers.count == 1)

        let output = await manager.executeTool(named: "demo_ping", arguments: ["hello": "world"])
        #expect(output.contains("ran:demo_ping"))
        #expect(output.contains("args:"))
    }
}
