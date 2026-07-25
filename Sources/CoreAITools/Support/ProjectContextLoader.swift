import Foundation

enum ProjectContextLoader {
    static let contextFiles = [
        "AGENTS.md",
        "CLAUDE.md",
        "GEMINI.md",
        ".cursorrules",
        ".github/copilot-instructions.md",
        "CONTRIBUTING.md",
    ]

    /// Load any existing context files from the project directory
    /// and append them to the system prompt.
    static func loadContext(from projectPath: String) -> String? {
        var found: [String] = []

        for fileName in contextFiles {
            let path = (projectPath as NSString).appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: path) {
                if let content = try? String(contentsOfFile: path, encoding: .utf8) {
                    let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        found.append("### \(fileName)\n\(trimmed)")
                    }
                }
            }
        }

        guard !found.isEmpty else { return nil }
        return "\n\n## Project Context Files\n\n" + found.joined(separator: "\n\n")
    }

    /// Generate a default AGENTS.md context file for the project.
    static func generateAgentsMd(for projectPath: String, projectStructure: String) -> String {
        let name = (projectPath as NSString).lastPathComponent
        return """
        # AGENTS.md — \(name)

        ## Project Overview
        [Describe the project purpose and architecture]

        ## Build & Test Commands
        - Build: [command]
        - Test: [command]
        - Lint: [command]

        ## Coding Conventions
        - Language: [primary language]
        - Style: [coding style guidelines]
        - Testing: [test framework and patterns]

        ## Architecture
        ```
        \(projectStructure)
        ```

        ## Important Notes
        - [Any constraints or gotchas]
        - [Security considerations]
        - [Performance requirements]
        """
    }
}
