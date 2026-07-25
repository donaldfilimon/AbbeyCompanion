import Foundation
import AppKit

@MainActor
enum FileService {
    static func openFolderPanel() -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open Project"
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory())

        let response = panel.runModal()
        guard response == .OK, let url = panel.url else { return nil }
        return url.path
    }
}
