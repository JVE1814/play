import Foundation

/// A player made of code. It looks a little way ahead, tries what it could do and when, and
/// picks something that keeps it on its feet. The tests use one with long sight to show that
/// every course can be run; `runner-calibrate` uses weaker ones to see how hard the game is.
public struct RunnerBot: Sendable {
    /// How far ahead it looks, in seconds.
    public var foresight: Double
    /// The chance, each time it has to act, that it hesitates first.
    public var lapse: Double

    public init(foresight: Double, lapse: Double) {
        self.foresight = foresight
        self.lapse = lapse
    }

    /// Sees everything in time and never hesitates.
    public static let expert = RunnerBot(foresight: 1.3, lapse: 0)
    /// Someone who has played for a while.
    public static let regular = RunnerBot(foresight: 0.9, lapse: 0.04)
    /// Someone new: sees things late, and sometimes freezes.
    public static let newcomer = RunnerBot(foresight: 0.6, lapse: 0.12)

    /// Seconds between its decisions.
    static let tick = 0.1
    /// Seconds lost to a hesitation.
    static let hesitation = 0.35

    /// Runs `run` on until it crashes or reaches `distance`.
    public func play(_ run: Run, to distance: Double, seed: UInt64 = 1) -> Run {
        var run = run
        var random = SeededGenerator(seed: seed)
        let slots = max(1, Int((foresight / Self.tick).rounded()))
        var plan = [Move?](repeating: nil, count: slots)
        var frozenUntil = 0.0
        while run.status == .running, run.distance < distance {
            if run.time >= frozenUntil {
                if !Self.survives(run, plan) {
                    plan = Self.search(run, slots: slots) ?? plan
                }
                if let move = plan[0] {
                    if random.chance(lapse) {
                        frozenUntil = run.time + Self.hesitation
                    } else {
                        run.perform(move)
                    }
                }
            }
            run.advance(by: Self.tick)
            plan.removeFirst()
            plan.append(nil)
        }
        return run
    }

    /// Whether `run` is still going after making each move of `plan` in its tick.
    private static func survives(_ run: Run, _ plan: [Move?]) -> Bool {
        var run = run
        for move in plan {
            if let move { run.perform(move) }
            run.advance(by: tick)
            if run.status == .crashed { return false }
        }
        return true
    }

    /// A plan of up to three moves that survives, trying fewer and earlier moves first.
    private static func search(_ run: Run, slots: Int) -> [Move?]? {
        let none = [Move?](repeating: nil, count: slots)
        if survives(run, none) { return none }
        let choices = (0..<slots).flatMap { slot in Move.allCases.map { (slot, $0) } }
        for (slot, move) in choices {
            var plan = none
            plan[slot] = move
            if survives(run, plan) { return plan }
        }
        for (index, first) in choices.enumerated() {
            for second in choices[(index + 1)...] where second.0 > first.0 {
                var plan = none
                plan[first.0] = first.1
                plan[second.0] = second.1
                if survives(run, plan) { return plan }
            }
        }
        for (i, first) in choices.enumerated() {
            for (j, second) in choices.enumerated() where j > i && second.0 > first.0 {
                for third in choices[(j + 1)...] where third.0 > second.0 {
                    var plan = none
                    plan[first.0] = first.1
                    plan[second.0] = second.1
                    plan[third.0] = third.1
                    if survives(run, plan) { return plan }
                }
            }
        }
        return nil
    }
}
