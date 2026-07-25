import SwiftUI
import AbbeyCompanionKit

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

            Button("Export JSON…") {
                NotificationCenter.default.post(name: .abbeyExportRequested, object: nil)
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])

            Button("Import JSON…") {
                NotificationCenter.default.post(name: .abbeyImportRequested, object: nil)
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])

            Divider()

            Button("Reset DQN Weights") {
                Task { await engine.resetDQNWeights() }
            }

            Divider()

            Button("Reset Local Store…") {
                NotificationCenter.default.post(name: .abbeyResetStoreRequested, object: nil)
            }
        }

        CommandMenu("Navigate") {
            Button("Dashboard") {
                NotificationCenter.default.post(name: .abbeyNavigateTo, object: "dashboard")
            }
            .keyboardShortcut("1", modifiers: [.command])

            Button("Users") {
                NotificationCenter.default.post(name: .abbeyNavigateTo, object: "users")
            }
            .keyboardShortcut("2", modifiers: [.command])

            Button("Channels") {
                NotificationCenter.default.post(name: .abbeyNavigateTo, object: "channels")
            }
            .keyboardShortcut("3", modifiers: [.command])

            Button("Messages") {
                NotificationCenter.default.post(name: .abbeyNavigateTo, object: "messages")
            }
            .keyboardShortcut("4", modifiers: [.command])

            Button("Activity") {
                NotificationCenter.default.post(name: .abbeyNavigateTo, object: "activity")
            }
            .keyboardShortcut("5", modifiers: [.command])

            Button("Personas") {
                NotificationCenter.default.post(name: .abbeyNavigateTo, object: "personas")
            }
            .keyboardShortcut("6", modifiers: [.command])

            Divider()

            Button("Statistics") {
                NotificationCenter.default.post(name: .abbeyNavigateTo, object: "statistics")
            }
            .keyboardShortcut("8", modifiers: [.command])

            Button("AI Assistant") {
                NotificationCenter.default.post(name: .abbeyNavigateTo, object: "aiAssistant")
            }
            .keyboardShortcut("9", modifiers: [.command])
        }

        CommandGroup(replacing: .newItem) { }

        CommandGroup(after: .help) {
            Button("Abbey Command Help") {
                NotificationCenter.default.post(name: .abbeyHelpRequested, object: nil)
            }
            Button("Keyboard Shortcuts") {
                NotificationCenter.default.post(name: .abbeyShortcutsRequested, object: nil)
            }
            .keyboardShortcut("/", modifiers: [.command, .shift])
        }
    }
}
