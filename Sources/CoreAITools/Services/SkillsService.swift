import Foundation
import Observation

// MARK: - Skill Definition

package struct CoreAISkill: Identifiable, Hashable {
    package let id: String
    package let name: String
    package let description: String
    package let content: String
    package let sourcePath: String
    package let isGlobal: Bool
}

// MARK: - Skills Service

@MainActor
@Observable
final class SkillsService {
    private(set) var skills: [CoreAISkill] = []

    private let globalSkillsDir: String
    private var projectSkillsDir: String?

    init(globalSkillsDir: String? = nil) {
        self.globalSkillsDir = globalSkillsDir ?? "\(NSHomeDirectory())/.coreai/skills"
        loadGlobalSkills()
    }

    func setProjectPath(_ path: String) {
        projectSkillsDir = "\(path)/.coreai/skills"
        loadProjectSkills()
    }

    // MARK: - Loading

    func loadGlobalSkills() {
        loadSkills(from: globalSkillsDir, isGlobal: true)
    }

    func loadProjectSkills() {
        guard let dir = projectSkillsDir else { return }
        // Remove old project skills first
        skills.removeAll { !$0.isGlobal }
        loadSkills(from: dir, isGlobal: false)
    }

    private func loadSkills(from directory: String, isGlobal: Bool) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory) else { return }

        guard let entries = try? fm.contentsOfDirectory(atPath: directory) else { return }

        for entry in entries {
            let skillPath = "\(directory)/\(entry)"

            // Check for SKILL.md in subdirectory or direct .md file
            let mdPath: String
            if fm.fileExists(atPath: "\(skillPath)/SKILL.md") {
                mdPath = "\(skillPath)/SKILL.md"
            } else if entry.hasSuffix(".md") {
                mdPath = skillPath
            } else {
                continue
            }

            guard let content = try? String(contentsOfFile: mdPath, encoding: .utf8) else { continue }
            let name = entry.replacingOccurrences(of: ".md", with: "")
            let description = extractDescription(from: content) ?? "Skill: \(name)"

            let skill = CoreAISkill(
                id: isGlobal ? "global:\(name)" : "project:\(name)",
                name: name,
                description: description,
                content: content,
                sourcePath: mdPath,
                isGlobal: isGlobal
            )

            // Replace if already loaded
            if let idx = skills.firstIndex(where: { $0.id == skill.id }) {
                skills[idx] = skill
            } else {
                skills.append(skill)
            }
        }
    }

    // MARK: - System Prompt Integration

    func systemPromptAddition() -> String? {
        guard !skills.isEmpty else { return nil }

        var lines = ["\n\n## Active Skills\n"]
        for skill in skills {
            lines.append("### Skill: \(skill.name)\n\(skill.content.trimmingCharacters(in: .whitespacesAndNewlines))\n")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Helpers

    private func extractDescription(from content: String) -> String? {
        // Try to extract from frontmatter or first paragraph
        if let range = content.range(of: "description:") {
            let after = content[range.upperBound...]
            if let newline = after.firstIndex(of: "\n") {
                return String(after[..<newline]).trimmingCharacters(in: .whitespaces)
            }
        }
        // First non-empty line after title
        let lines = content.components(separatedBy: "\n")
        for line in lines.dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty && !trimmed.hasPrefix("#") {
                return trimmed
            }
        }
        return nil
    }
}
