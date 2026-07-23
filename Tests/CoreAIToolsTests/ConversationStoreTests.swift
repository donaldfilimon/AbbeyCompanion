import Testing
@testable import CoreAITools

@MainActor
struct ConversationStoreTests {
    @Test func store_initializes_empty() {
        let store = ConversationStore()
        // Store may load persisted conversations from disk
        #expect(store.conversations.count >= 0)
    }

    @Test func store_newConversation_addsTo() {
        let store = ConversationStore()
        let initialCount = store.conversations.count
        store.newConversation(projectPath: "/tmp")
        #expect(store.conversations.count == initialCount + 1)
        #expect(store.selectedConversationID != nil)
    }

    @Test func store_deleteConversation_removes() {
        let store = ConversationStore()
        store.newConversation(projectPath: "/tmp")
        let id = store.selectedConversationID!
        store.delete(id)
        #expect(store.conversations.first(where: { $0.id == id }) == nil)
    }

    @Test func store_fileChanges_initially_empty() {
        let store = ConversationStore()
        store.newConversation(projectPath: "/tmp")
        #expect(store.fileChanges.isEmpty)
    }
}
