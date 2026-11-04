import Foundation

/// A small, fast, deterministic random number generator (SplitMix64).
///
/// The standard library's shuffling algorithm is not guaranteed to stay the same
/// between Swift releases, so deals use this generator together with our own
/// Fisher–Yates shuffle. A given seed therefore always produces the same deal.
public struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform integer in `0..<bound` without modulo bias (rejection sampling).
    public mutating func nextInt(below bound: Int) -> Int {
        precondition(bound > 0, "bound must be positive")
        let upper = UInt64(bound)
        let limit = UInt64.max - (UInt64.max % upper)
        while true {
            let value = next()
            if value < limit { return Int(value % upper) }
        }
    }
}

extension Array {
    /// Deterministic Fisher–Yates shuffle driven by a `SeededGenerator`.
    mutating func seededShuffle(using generator: inout SeededGenerator) {
        guard count > 1 else { return }
        for i in stride(from: count - 1, to: 0, by: -1) {
            let j = generator.nextInt(below: i + 1)
            if i != j { swapAt(i, j) }
        }
    }
}
