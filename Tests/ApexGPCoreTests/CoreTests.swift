import Testing
import simd
@testable import ApexGPCore

// Track tests live in TrackTests.swift.

@Suite struct MessageBusTests {
    final class RecordingAgent: RaceAgent {
        let id: String
        let subscriptions: [String]
        var received: [AgentMessage] = []
        var ticks = 0
        init(id: String, subscriptions: [String]) {
            self.id = id
            self.subscriptions = subscriptions
        }
        func receive(_ message: AgentMessage) { received.append(message) }
        func tick(simTime: Double, deltaTime: Double, bus: MessageBus) { ticks += 1 }
    }

    @Test func deliversByTopicPrefixOnNextTick() {
        let bus = MessageBus()
        let driver = RecordingAgent(id: "driver.3", subscriptions: ["team.2", "race.flag"])
        let bystander = RecordingAgent(id: "driver.7", subscriptions: ["team.5"])
        bus.register(driver)
        bus.register(bystander)

        bus.post(AgentMessage(topic: "team.2.pitNow", senderID: "strategy.2", simTime: 0))
        #expect(driver.received.isEmpty)  // queued, not delivered mid-tick

        bus.tick(simTime: 0.01, deltaTime: 0.01)
        #expect(driver.received.count == 1)
        #expect(driver.received.first?.topic == "team.2.pitNow")
        #expect(bystander.received.isEmpty)
        #expect(driver.ticks == 1 && bystander.ticks == 1)
    }

    @Test func senderDoesNotReceiveOwnMessage() {
        let bus = MessageBus()
        let agent = RecordingAgent(id: "director", subscriptions: ["race"])
        bus.register(agent)
        bus.post(AgentMessage(topic: "race.flag.yellow", senderID: "director", simTime: 0))
        bus.tick(simTime: 0.01, deltaTime: 0.01)
        #expect(agent.received.isEmpty)
    }
}

@Suite struct VehicleStateTests {
    @Test func speedIsVelocityMagnitude() {
        var state = VehicleState()
        state.velocity = SIMD3(3, 0, 4)
        #expect(abs(state.speed - 5) < 1e-5)
    }
}
