import Foundation
import FoundationModels

// MARK: - Search Code Tool

struct SearchCodeTool: Tool {
    @Generable(description: "Arguments for searching code")
    struct Arguments {
        @Guide(description: "The text pattern to search for in file contents")
        var query: String
        @Guide(description: "File extension filter (e.g. 'swift', 'ts'). Empty = all files.")
        var fileExtension: String
        @Guide(description: "Treat query as a regular expression. Set false to match literally (fixed string). Default true.")
        var regex: Bool = true
    }

    static let name = "search_code"
    let description = "Search for a text pattern across files in the project. Returns matching lines with file paths and line numbers."
    let workingDirectory: String

    init(workingDirectory: String) {
        self.workingDirectory = workingDirectory
    }

    func call(arguments: Arguments) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/grep")
        var grepArgs = ["-rn", "--max-count=50"]
        // Interpret the query as a regex (default) or a literal fixed string.
        grepArgs.append(arguments.regex ? "-E" : "-F")
        grepArgs.append(arguments.query)
        if !arguments.fileExtension.isEmpty {
            grepArgs.append("--include=*.\(arguments.fileExtension)")
        }
        grepArgs.append(".")
        process.arguments = grepArgs
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        var output = String(data: data, encoding: .utf8) ?? ""

        if output.isEmpty {
            output = "No matches found for '\(arguments.query)'"
        }

        // Cap total lines regardless of grep's per-file max-count.
        let lines = output.components(separatedBy: "\n")
        if lines.count > 200 {
            output = lines.prefix(200).joined(separator: "\n") + "\n… (\(lines.count - 200) more lines)"
        }
        return output
    }
}

// MARK: - Project Structure Tool

struct ProjectStructureTool: Tool {
    @Generable(description: "Arguments for getting project structure")
    struct Arguments {
        @Guide(description: "Maximum depth to traverse. Default 3.")
        var maxDepth: Int
    }

    static let name = "project_structure"
    let description = "Get a tree view of the project directory structure. Shows files and folders up to the specified depth."
    let workingDirectory: String

    init(workingDirectory: String) {
        self.workingDirectory = workingDirectory
    }

    func call(arguments: Arguments) async throws -> String {
        let depth = arguments.maxDepth > 0 ? arguments.maxDepth : 3
        let url = URL(fileURLWithPath: workingDirectory)
        var lines: [String] = []
        buildTree(at: url, prefix: "", depth: 0, maxDepth: depth, lines: &lines)

        if lines.isEmpty {
            return "Empty project directory"
        }
        return lines.joined(separator: "\n")
    }

    private func buildTree(at url: URL, prefix: String, depth: Int, maxDepth: Int, lines: inout [String]) {
        guard depth < maxDepth else { return }

        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey]) else { return }

        let sorted = entries
            .filter { entry in
                let name = entry.lastPathComponent
                return !name.hasPrefix(".") && name != "__pycache__" && name != "node_modules" && name != ".git"
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        for (idx, entry) in sorted.enumerated() {
            let isLast = idx == sorted.count - 1
            let connector = isLast ? "└── " : "├── "
            let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            lines.append(prefix + connector + entry.lastPathComponent + (isDir ? "/" : ""))

            if isDir {
                let newPrefix = prefix + (isLast ? "    " : "│   ")
                buildTree(at: entry, prefix: newPrefix, depth: depth + 1, maxDepth: maxDepth, lines: &lines)
            }
        }
    }
}
