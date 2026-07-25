import Foundation

extension ConversationStore {
    // MARK: - Streaming

    func streamAssistantResponse(to prompt: String, convoId: UUID) async {
        guard ai.isAvailable else {
            guard let idx = conversations.firstIndex(where: { $0.id == convoId }) else { return }
            let errorMsg = ChatMessage(
                role: .assistant,
                content: "⚠️ \(ai.availabilityMessage)\n\nPlease enable Apple Intelligence in System Settings > Apple Intelligence & Siri."
            )
            conversations[idx].messages.append(errorMsg)
            return
        }

        guard let idx = conversations.firstIndex(where: { $0.id == convoId }) else { return }

        let assistantMsg = ChatMessage(role: .assistant, content: "", isStreaming: true)
        conversations[idx].messages.append(assistantMsg)
        let msgId = assistantMsg.id
        streamingMessageID = msgId
        isStreaming = true

        let result = await ai.streamResponse(to: prompt)

        guard let currentIdx = conversations.firstIndex(where: { $0.id == convoId }) else {
            isStreaming = false
            streamingMessageID = nil
            streamingConversationID = nil
            return
        }

        guard let msgIdx = conversations[currentIdx].messages.firstIndex(where: { $0.id == msgId }) else {
            isStreaming = false
            streamingMessageID = nil
            streamingConversationID = nil
            return
        }

        switch result {
        case .success(let text):
            conversations[currentIdx].messages[msgIdx].content = text.isEmpty ? "(cancelled)" : text
            conversations[currentIdx].messages[msgIdx].toolCalls = ai.lastToolCalls
            conversations[currentIdx].messages[msgIdx].isStreaming = false
            ConversationFileChangeTracker.apply(toolCalls: ai.lastToolCalls, to: &conversations[currentIdx])

            if ai.contextWindowUsed > autoCompactThreshold {
                autoCompact(in: currentIdx)
            }

        case .failure(let error):
            conversations[currentIdx].messages[msgIdx].content = "⚠️ Error: \(error.localizedDescription)"
            conversations[currentIdx].messages[msgIdx].isStreaming = false
        }

        conversations[currentIdx].updatedAt = Date()
        isStreaming = false
        streamingMessageID = nil
        streamingConversationID = nil
        streamingTask = nil
        saveAll()
    }

    func cancelStreaming() {
        streamingTask?.cancel()
        streamingTask = nil
        ai.cancelStreaming()
        ai.approvalGate.cancelAll()
        isStreaming = false

        if let msgId = streamingMessageID,
           let convoId = streamingConversationID,
           let convoIdx = conversations.firstIndex(where: { $0.id == convoId }),
           let msgIdx = conversations[convoIdx].messages.firstIndex(where: { $0.id == msgId }) {
            if conversations[convoIdx].messages[msgIdx].content.isEmpty {
                conversations[convoIdx].messages[msgIdx].content = "(cancelled)"
            }
            conversations[convoIdx].messages[msgIdx].isStreaming = false
        }
        streamingMessageID = nil
        streamingConversationID = nil
    }

    func autoCompact(in convoIdx: Int) {
        let messages = conversations[convoIdx].messages
        guard messages.count > 6 else { return }

        let firstBatch = messages.prefix(2)
        let lastBatch = messages.suffix(4)
        let middleCount = messages.count - firstBatch.count - lastBatch.count

        let summary = "📋 [Auto-compacted \(middleCount) messages to save context]"
        let summaryMsg = ChatMessage(role: .system, content: summary)

        conversations[convoIdx].messages = Array(firstBatch) + [summaryMsg] + Array(lastBatch)
    }

    func retryLastMessage() {
        guard let convoId = selectedConversationID,
              let idx = conversations.firstIndex(where: { $0.id == convoId }) else { return }
        let messages = conversations[idx].messages
        guard let lastUserIdx = messages.lastIndex(where: { $0.role == .user }) else { return }
        let prompt = messages[lastUserIdx].content
        conversations[idx].messages = Array(messages.prefix(lastUserIdx + 1))

        streamingConversationID = convoId
        streamingTask = Task {
            await self.streamAssistantResponse(to: prompt, convoId: convoId)
        }
    }

    // MARK: - LLM compaction

    func compactConversation(convoId: UUID) async {
        guard let idx = conversations.firstIndex(where: { $0.id == convoId }) else { return }
        let messages = conversations[idx].messages
        guard messages.count > 4 else { return }

        let transcript = messages.map { "\($0.role.rawValue): \($0.content)" }.joined(separator: "\n")
        let prompt = """
        Summarize the following conversation concisely, preserving key facts, \
        decisions, file paths, and any context needed to continue the work. \
        Keep it under 600 words:

        \(transcript)
        """

        let summarizer = AIService()
        summarizer.checkAvailability()
        let workDir = conversations[idx].projectPath ?? FileManager.default.currentDirectoryPath
        summarizer.startSession(workingDirectory: workDir, workMode: .readOnly)
        let result = await summarizer.respond(to: prompt)
        let summary = (try? result.get()) ?? "Conversation summary unavailable."

        let recent = Array(messages.suffix(4))
        let summaryMsg = ChatMessage(role: .system, content: "📋 **Conversation Summary**\n\n\(summary)")
        conversations[idx].messages = [summaryMsg] + recent

        if let path = conversations[idx].projectPath {
            ai.startSession(
                workingDirectory: path,
                modelChoice: conversations[idx].modelChoice,
                workMode: conversations[idx].workMode,
                additionalInstructions: (composeAdditionalInstructionsForSession() ?? "") + "\n\n" + summary,
                additionalTools: additionalModelTools()
            )
        } else {
            ai.clearSession()
        }
        saveAll()
    }
}
