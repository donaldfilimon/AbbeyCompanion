import SwiftUI
import AppKit

struct ComposerView: View {
    let store: ConversationStore
    @State private var inputText = ""
    @State private var messageHistory: [String] = []
    @State private var historyIndex: Int = -1
    @State private var pastedImageDescription: String?
    @FocusState private var isFocused: Bool

    init(store: ConversationStore) {
        self.store = store
    }

    var body: some View {
        VStack(spacing: 0) {
            if let cmd = currentSlashHint {
                slashHint(cmd)
            }

            // Pasted image indicator
            if let imgDesc = pastedImageDescription {
                HStack(spacing: 6) {
                    Image(systemName: "photo")
                        .font(.caption)
                        .foregroundStyle(.tint)
                    Text(imgDesc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        pastedImageDescription = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 3)
            }

            HStack(alignment: .bottom, spacing: 8) {
                TextField("Ask CoreAI to code, debug, or explore…  (try /help, paste images)", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .lineLimit(1...6)
                    .focused($isFocused)
                    .onSubmit(sendMessage)
                    .onKeyPress(.upArrow) {
                        navigateHistory(direction: .up); return .handled
                    }
                    .onKeyPress(.downArrow) {
                        navigateHistory(direction: .down); return .handled
                    }
                    .onPasteCommand(of: [.image]) { _ in
                        handleImagePaste()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)

                Button(action: handleSendButton) {
                    Image(systemName: store.isStreaming ? "stop.fill" : "arrow.up.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(canSend ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .disabled(!canSend && !store.isStreaming)
                .padding(.bottom, 6)
                .padding(.trailing, 12)
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppearanceSettings.shared.surfaceStyle)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isFocused ? Color.accentColor.opacity(0.4) : Color.secondary.opacity(0.18), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(AppearanceSettings.shared.vividGlass ? 0.12 : 0.05), radius: AppearanceSettings.shared.vividGlass ? 8 : 3, y: 2)
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Image Paste

    private func handleImagePaste() {
        guard let nsImage = NSPasteboard.general.readObjects(forClasses: [NSImage.self])?.first as? NSImage else {
            return
        }

        // Save to temp file
        let tempDir = FileManager.default.temporaryDirectory
        let timestamp = Int(Date().timeIntervalSince1970)
        let imagePath = tempDir.appendingPathComponent("coreai_paste_\(timestamp).png")

        if let tiff = nsImage.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff),
           let png = bitmap.representation(using: .png, properties: [:]) {
            try? png.write(to: imagePath)

            let size = nsImage.size
            pastedImageDescription = "Pasted image (\(Int(size.width))×\(Int(size.height))) — will be included with your message"

            // Append image path to input text
            if !inputText.isEmpty { inputText += "\n" }
            inputText += "[Pasted image at: \(imagePath.path)]"
        }
    }

    // MARK: - Slash Command Hints

    private var currentSlashHint: SlashCommand? {
        let trimmed = inputText.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("/") && !trimmed.contains(" ") else { return nil }
        let search = String(trimmed.dropFirst()).lowercased()
        guard !search.isEmpty else { return nil }
        return SlashCommand.allCases.first { $0.rawValue.hasPrefix(search) && $0.rawValue != search }
    }

    private func slashHint(_ cmd: SlashCommand) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "text.magnifyingglass")
                .font(.caption)
                .foregroundStyle(.tint)
            Text(cmd.trigger)
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.medium)
            Text("— \(cmd.description)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text("Tab to use")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 4)
        .onTapGesture {
            inputText = cmd.trigger + " "
        }
    }

    // MARK: - Message History

    private enum HistoryDirection { case up, down }

    private func navigateHistory(direction: HistoryDirection) {
        if messageHistory.isEmpty { return }
        switch direction {
        case .up:
            if historyIndex < messageHistory.count - 1 {
                historyIndex += 1
                inputText = messageHistory[messageHistory.count - 1 - historyIndex]
            }
        case .down:
            if historyIndex > 0 {
                historyIndex -= 1
                inputText = messageHistory[messageHistory.count - 1 - historyIndex]
            } else {
                historyIndex = -1
                inputText = ""
            }
        }
    }

    // MARK: - Actions

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespaces).isEmpty && !store.isStreaming
    }

    private func handleSendButton() {
        if store.isStreaming {
            store.cancelStreaming()
        } else {
            sendMessage()
        }
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        if !messageHistory.contains(text) { messageHistory.append(text) }
        historyIndex = -1
        inputText = ""
        pastedImageDescription = nil
        store.send(text)
    }
}
