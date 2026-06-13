import Foundation

/// A message published on the bus. Topics are dot-namespaced strings,
/// e.g. "race.flag.yellow", "team.3.pitNow", "telemetry.player".
public struct AgentMessage: Sendable {
    public let topic: String
    public let senderID: String
    /// Simulation time the message was posted, in seconds since session start.
    public let simTime: Double
    public let payload: [String: Double]

    public init(topic: String, senderID: String, simTime: Double, payload: [String: Double] = [:]) {
        self.topic = topic
        self.senderID = senderID
        self.simTime = simTime
        self.payload = payload
    }
}

/// A participant in the in-game multi-agent system (AI driver, race engineer,
/// strategist, race director, broadcast director).
public protocol RaceAgent: AnyObject {
    var id: String { get }
    /// Topic prefixes this agent wants delivered, e.g. ["race.flag", "team.3"].
    var subscriptions: [String] { get }
    func receive(_ message: AgentMessage)
    /// Called once per simulation tick, after queued messages are delivered.
    func tick(simTime: Double, deltaTime: Double, bus: MessageBus)
}

/// Publish/subscribe hub ticked at the fixed simulation rate. Messages posted
/// during a tick are queued and delivered at the start of the next tick, so
/// delivery order never depends on agent registration order within a tick.
public final class MessageBus {
    private var agents: [RaceAgent] = []
    private var queue: [AgentMessage] = []

    public init() {}

    public var agentCount: Int { agents.count }

    public func register(_ agent: RaceAgent) {
        agents.append(agent)
    }

    public func post(_ message: AgentMessage) {
        queue.append(message)
    }

    public func tick(simTime: Double, deltaTime: Double) {
        let pending = queue
        queue.removeAll(keepingCapacity: true)
        for message in pending {
            for agent in agents where agent.id != message.senderID {
                if agent.subscriptions.contains(where: { message.topic.hasPrefix($0) }) {
                    agent.receive(message)
                }
            }
        }
        for agent in agents {
            agent.tick(simTime: simTime, deltaTime: deltaTime, bus: self)
        }
    }
}
