import Foundation

/// Policy actions over the DQN output head (topology last dim == 3).
public enum DQNAction: Int, Sendable, CaseIterable {
    case ignore = 0
    case reply = 1
    case escalate = 2

    public var label: String {
        switch self {
        case .ignore: return "ignore"
        case .reply: return "reply"
        case .escalate: return "escalate"
        }
    }

    public init(raw: Int) {
        self = DQNAction(rawValue: raw) ?? .reply
    }
}

/// Deep Q-Network agent driving Abbey's self-learning loop: MessageCreate → WDBX/local
/// ingest → reward on reactions → `learn()`.
///
/// Two corrections versus the reference draft in brain.md, both mechanical:
///   1. `online`/`target` are plain (non-async) `NeuralNetwork` values, so calling their
///      methods from within this actor needs no `await` — the reference draft's
///      `await online.forward(state)` was calling `await` on a synchronous method,
///      which only compiled by accident of `forward` also being (incorrectly) `mutating`
///      in a context where the compiler inserted an implicit actor-hop. Making
///      `forward`/`forwardLogits` non-mutating (see NeuralNetwork.swift) removes the
///      ambiguity entirely.
///   2. Q-value estimation uses `forwardLogits`, not `forward` — see the comment on
///      `NeuralNetwork.forwardLogits` for why. This is the flagged-not-silent fix for
///      the "softmax on Q-values" open decision.
///
/// Callers must pass `SentimentAnalyzer.projectToNetworkInput(state)` (8-dim), not the
/// raw 18-dim analyzer vector — SIMD8 weights only consume eight lanes.
public actor DQNAgent {
    public private(set) var online: NeuralNetwork
    public private(set) var target: NeuralNetwork
    private var buffer: ReplayBuffer
    private var rng: SplitMix64

    public let gamma: Float
    public let epsilon: Float
    public private(set) var stepCount = 0

    public struct Checkpoint: Codable, Sendable, Equatable {
        public var online: NeuralNetwork.Snapshot
        public var target: NeuralNetwork.Snapshot
        public var stepCount: Int
        public var gamma: Float
        public var epsilon: Float

        public init(
            online: NeuralNetwork.Snapshot,
            target: NeuralNetwork.Snapshot,
            stepCount: Int,
            gamma: Float,
            epsilon: Float
        ) {
            self.online = online
            self.target = target
            self.stepCount = stepCount
            self.gamma = gamma
            self.epsilon = epsilon
        }
    }

    public init(topology: [Int], gamma: Float = 0.99, epsilon: Float = 0.1, bufferCapacity: Int = 10_000, seed: UInt64 = 42) {
        self.online = NeuralNetwork(topology: topology, seed: seed)
        self.target = online
        self.buffer = ReplayBuffer(capacity: bufferCapacity)
        self.rng = SplitMix64(seed: seed &+ 1)
        self.gamma = gamma
        self.epsilon = epsilon
    }

    public var experienceCount: Int { buffer.count }

    public func exportCheckpoint() -> Checkpoint {
        Checkpoint(
            online: online.makeSnapshot(),
            target: target.makeSnapshot(),
            stepCount: stepCount,
            gamma: gamma,
            epsilon: epsilon
        )
    }

    public func loadCheckpoint(_ checkpoint: Checkpoint) throws {
        guard checkpoint.online.topology == online.topology,
              checkpoint.target.topology == online.topology
        else {
            throw CheckpointError.topologyMismatch
        }
        online = try NeuralNetwork(snapshot: checkpoint.online)
        target = try NeuralNetwork(snapshot: checkpoint.target)
        stepCount = checkpoint.stepCount
    }

    public func reset(seed: UInt64 = 42) {
        online = NeuralNetwork(topology: online.topology, seed: seed)
        target = online
        buffer = ReplayBuffer(capacity: buffer.capacity)
        rng = SplitMix64(seed: seed &+ 1)
        stepCount = 0
    }

    /// Credits a delayed reward (e.g. UI 👍/👎) against a prior policy decision.
    public func creditReward(state: [Float], action: Int, reward: Float) {
        remember(
            Experience(
                state: state,
                action: action,
                reward: reward,
                nextState: state,
                done: true
            )
        )
        learn(batchSize: 8)
    }

    /// ε-greedy action selection over raw Q-values.
    public func selectAction(state: [Float]) -> Int {
        guard let actionCount = online.topology.last, actionCount > 0 else { return 0 }
        if Float.random(in: 0...1, using: &rng) < epsilon {
            return Int.random(in: 0..<actionCount, using: &rng)
        }
        let qValues = online.forwardLogits(state)
        guard let best = qValues.enumerated().max(by: { $0.element < $1.element }) else { return 0 }
        return best.offset
    }

    public func remember(_ experience: Experience) {
        buffer.add(experience)
    }

    /// One learning step over a random minibatch. No-op until the buffer has at least
    /// `batchSize` experiences, matching the reference draft's guard.
    public func learn(batchSize: Int = 64) {
        guard buffer.count >= batchSize else { return }
        let batch = buffer.sample(size: batchSize, using: &rng)

        for experience in batch {
            let nextQValues = target.forwardLogits(experience.nextState)
            let bestNextQ = nextQValues.max() ?? 0
            let bootstrapped = experience.done ? experience.reward : experience.reward + gamma * bestNextQ

            var targetVector = online.forwardLogits(experience.state)
            if experience.action < targetVector.count {
                targetVector[experience.action] = bootstrapped
            }
            online.train(input: experience.state, target: targetVector)
        }

        stepCount += 1
        if stepCount % 100 == 0 {
            target = online   // periodic target-network sync
        }
    }
}
