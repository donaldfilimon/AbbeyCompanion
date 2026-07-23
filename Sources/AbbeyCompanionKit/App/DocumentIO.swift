import AppKit
import UniformTypeIdentifiers

@MainActor
package enum DocumentIO {
    package static func runJSONExport(data: Data, defaultName: String = "abbey-companion-export.json") -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = defaultName
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        try? data.write(to: url, options: .atomic)
        return url
    }

    package static func runJSONImport() -> Data? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return try? Data(contentsOf: url)
    }
}
