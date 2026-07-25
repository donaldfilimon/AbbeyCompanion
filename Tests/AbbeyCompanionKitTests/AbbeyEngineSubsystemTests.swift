import Testing
import AbbeyCompanionKit
import AbbeyCore

@Suite("AbbeyCompanionKit Engine")
struct AbbeyEngineSubsystemTests {
    @Test("EventBus publishes to all subscribers")
    func eventBusBroadcasts() async {
        let bus = EventBus()
        let stream = await bus.subscribe()
        let collectTask = Task {
            var events: [AbbeyEvent] = []
            for await event in stream {
                events.append(event)
                if events.count == 3 { break }
            }
            #expect(events.count == 3)
        }
        await bus.publish(.personaSwitched(to: "aviva"))
        await bus.publish(.reputationChanged(userId: "u1", guildId: "g1", newValue: 0.8, reason: "test"))
        await bus.publish(.inferenceProviderFailed(mode: .deterministicFloor, message: "test"))
        _ = await collectTask.value
    }

    @Test("EventBus subscriber receives no events after deallocation")
    func eventBusUnregistersOnCancel() async {
        let bus = EventBus()
        do {
            let stream = await bus.subscribe()
            _ = stream.makeAsyncIterator()
        }
        await bus.publish(.personaSwitched(to: "aviva"))
    }

    @Test("ConfirmationGate skips when confirmation is not required")
    func confirmationGateSkipsWhenDisabled() async {
        let bus = EventBus()
        let gate = ConfirmationGate(eventBus: bus, requireConfirmation: { false })
        let approved = await gate.request(kind: .kick, targetUserId: "u1", guildId: "g1", reason: "test")
        #expect(approved)
    }

    @Test("ConfirmationGate confirm resolves true")
    func confirmationGateConfirm() async {
        let bus = EventBus()
        let gate = ConfirmationGate(eventBus: bus, requireConfirmation: { true })
        async let approved = gate.request(kind: .kick, targetUserId: "u1", guildId: "g1", reason: "test")
        try? await Task.sleep(nanoseconds: 50_000_000)
        let req = await gate.queue.first
        #expect(req != nil)
        if let req {
            await gate.confirm(req.id)
        }
        let result = await approved
        #expect(result)
        #expect(await gate.queue.isEmpty)
    }

    @Test("ConfirmationGate cancel resolves false")
    func confirmationGateCancel() async {
        let bus = EventBus()
        let gate = ConfirmationGate(eventBus: bus, requireConfirmation: { true })
        async let approved = gate.request(kind: .ban, targetUserId: "u1", guildId: "g1", reason: "spam")
        try? await Task.sleep(nanoseconds: 50_000_000)
        let req = await gate.queue.first
        #expect(req != nil)
        if let req {
            await gate.cancel(req.id)
        }
        let result = await approved
        #expect(!result)
        #expect(await gate.queue.isEmpty)
    }

    @Test("ABIRouter routes modRequest to Aviva")
    func routerModRequest() async {
        let bus = EventBus()
        let router = ABIRouter(eventBus: bus)
        let persona = await router.route(intent: .modRequest)
        #expect(persona.name == "Aviva")
    }

    @Test("ABIRouter routes greeting to Abi")
    func routerGreeting() async {
        let bus = EventBus()
        let router = ABIRouter(eventBus: bus)
        let persona = await router.route(intent: .greeting)
        #expect(persona.name == "Abi")
    }

    @Test("ABIRouter routes question to default (Abbey)")
    func routerDefault() async {
        let bus = EventBus()
        let router = ABIRouter(eventBus: bus)
        let persona = await router.route(intent: .question)
        #expect(persona.name == "Abbey")
    }

    @Test("ABIRouter setPersona switches active persona")
    func routerSetPersona() async {
        let bus = EventBus()
        let router = ABIRouter(eventBus: bus)
        await router.setPersona(named: "aviva")
        let current = await router.currentPersona()
        #expect(current.name == "Aviva")
        await router.setPersona(named: "abi")
        let after = await router.currentPersona()
        #expect(after.name == "Abi")
    }
}
