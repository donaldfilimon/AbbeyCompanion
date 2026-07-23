import SwiftUI

struct AbbeyCommands: Commands {
    let engine: AbbeyEngine

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Abbey Companion") {
                NotificationCenter.default.post(name: .abbeyAboutRequested, object: nil)
            }
        }

        CommandMenu("Abbey") {
            Button("Seed Demo Data") {
                Task { await engine.seedDemoData() }
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])

            Button("Consolidate Channels Now") {
                Task { await engine.scheduler.consolidateAllChannels() }
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])

            Divider()

            Button("Reset Local Store…") {
                NotificationCenter.default.post(name: .abbeyResetStoreRequested, object: nil)
            }
        }

        CommandGroup(replacing: .newItem) { }

        CommandGroup(after: .help) {
            Button("Abbey Command Help") {
                NotificationCenter.default.post(name: .abbeyHelpRequested, object: nil)
            }
        }
    }
}

extension Notification.Name {
    static let abbeyResetStoreRequested = Notification.Name("abbeyResetStoreRequested")
    static let abbeyAboutRequested = Notification.Name("abbeyAboutRequested")
    static let abbeyHelpRequested = Notification.Name("abbeyHelpRequested")
}
