import Foundation

public struct Experience: Sendable {
    public let state: [Float]
    public let action: Int
    public let reward: Float
    public let nextState: [Float]
    public let done: Bool

    public init(state: [Float], action: Int, reward: Float, nextState: [Float], done: Bool) {
        self.state = state
        self.action = action
        self.reward = reward
        self.nextState = nextState
        self.done = done
    }
}

/// Fixed-capacity ring buffer of experiences. O(1) add (overwrites oldest when full),
/// O(k) sample via partial Fisher-Yates. Not an actor itself — it's owned exclusively by
/// `DQNAgent`, which is already actor-isolated, so no separate synchronization is needed.
public struct ReplayBuffer: Sendable {
    private var storage: [Experience?]
    private var head: Int = 0
    public let capacity: Int

    public init(capacity: Int = 10_000) {
        self.capacity = max(capacity, 1)
        self.storage = Array(repeating: nil, count: self.capacity)
    }

    public var count: Int { _count }

    private var _count: Int = 0

    public mutating func add(_ experience: Experience) {
        storage[head] = experience
        head = (head + 1) % capacity
        if _count < capacity { _count += 1 }
    }

    public func sample(size: Int, using generator: inout some RandomNumberGenerator) -> [Experience] {
        guard _count > 0 else { return [] }
        let k = min(size, _count)
        var indices = Array(0..<_count)
        for i in 0..<k {
            let j = Int.random(in: i..<indices.count, using: &generator)
            indices.swapAt(i, j)
        }
        return indices.prefix(k).compactMap { ringIndex($0) }
    }

    private func ringIndex(_ logicalIndex: Int) -> Experience? {
        let start = (_count < capacity) ? 0 : head
        return storage[(start + logicalIndex) % capacity]
    }
}
