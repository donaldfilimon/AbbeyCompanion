import Foundation

@MainActor
@Observable
package final class FileTreeService {
    private(set) var rootEntries: [FileEntry] = []
    private(set) var isLoading: Bool = false

    package init() {}

    struct FileEntry: Identifiable, Hashable {
        let id: String
        let path: String
        let name: String
        let isDirectory: Bool
        var children: [FileEntry]?
        var isExpanded: Bool
    }

    func loadProject(at path: String) {
        isLoading = true
        defer { isLoading = false }

        let url = URL(fileURLWithPath: path)
        rootEntries = buildEntries(at: url, depth: 0, maxDepth: 2)
    }

    func toggleExpand(_ entry: FileEntry) {
        // For simplicity, reload the tree when toggling
        // A more sophisticated approach would lazy-load children
    }

    private func buildEntries(at url: URL, depth: Int, maxDepth: Int) -> [FileEntry] {
        guard depth < maxDepth else { return [] }
        let fm = FileManager.default

        guard let entries = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }

        return entries
            .filter { name in
                !name.lastPathComponent.hasPrefix(".") &&
                name.lastPathComponent != "__pycache__" &&
                name.lastPathComponent != "node_modules" &&
                name.lastPathComponent != ".build" &&
                name.lastPathComponent != "dist" &&
                name.lastPathComponent != "DerivedData"
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { entryURL in
                let isDir = (try? entryURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                let children = isDir ? buildEntries(at: entryURL, depth: depth + 1, maxDepth: maxDepth) : nil

                return FileEntry(
                    id: entryURL.path,
                    path: entryURL.path,
                    name: entryURL.lastPathComponent,
                    isDirectory: isDir,
                    children: children,
                    isExpanded: depth < 1
                )
            }
    }
}
