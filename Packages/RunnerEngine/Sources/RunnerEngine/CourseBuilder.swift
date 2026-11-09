import Foundation

/// What one row adds to the course.
struct Row {
    var obstacles: [Obstacle] = []
    var coins: [Coin] = []
    var pickups: [Pickup] = []
}

/// Lays the course row by row, always further than the runner can see.
///
/// Every row leaves one lane, the path, that can be run: open, or holding something that a jump
/// or a slide gets past. The path moves at most one lane from row to row, and nothing long is
/// ever put where it would wall the path in, so every course can be run to any distance. No
/// lane is a dead end either: while a long stack splits the pier down the middle, both sides
/// stay runnable.
struct CourseBuilder: Codable, Equatable, Sendable {
    /// Metres of clear planks before the first row.
    static let firstRow = 30.0
    /// The rows of the coached opening: go round, jump, slide.
    static let lessons = 3
    static let coinSpacing = 1.7
    /// Metres it takes, at any speed, to see the end of a long stack and cross the pier behind it.
    static let crossingRoom = 12.0

    private var random: SeededGenerator
    /// Where the next row goes.
    private(set) var nextRow = CourseBuilder.firstRow
    /// The path's lane in the rows to come, the next row first.
    private var path: [Int]
    /// Where the row before is, and the path's lane there.
    private var previousRow = 0.0
    private var previousLane = Body.startLane
    /// Per lane, how far along nothing more may be placed: a long stack lies there, or a
    /// barrel is rolling in.
    private var reservedUntil = [Double](repeating: 0, count: Body.lanes)
    /// How far along a long stack in the middle lane keeps the outer lanes apart (and a
    /// little further, for the time it takes to cross over).
    private var splitUntil = 0.0
    private var nextPickup: Double
    /// Power-ups take turns, so neither kind stays away for long.
    private var nextPickupKind: Pickup.Kind
    private var lessonsLeft: Int

    init(seed: UInt64, coached: Bool) {
        random = SeededGenerator(seed: seed)
        lessonsLeft = coached ? Self.lessons : 0
        // The first lesson leaves the left lane open; the next two cross every lane.
        path = coached ? [0, 1, 1] : []
        nextPickup = 180
        nextPickup += random.uniform(0...80)
        nextPickupKind = random.chance(0.5) ? .magnet : .shield
        extendPath()
    }

    /// Where the coached opening ends (0 for a course without one).
    var lessonsEnd: Double {
        var position = Self.firstRow
        for _ in 1..<max(1, lessonsLeft) { position += Pace.rowSpacing(at: position) }
        return lessonsLeft > 0 ? position : 0
    }

    private mutating func extendPath() {
        while path.count < 8 {
            let last = path.last ?? Body.startLane
            var next = last
            if random.chance(0.55) { next += random.chance(0.5) ? -1 : 1 }
            if !(0..<Body.lanes).contains(next) { next = last + (last - next) }
            path.append(next)
        }
    }

    /// Lays the next row. The runner is at `distance` at `time`, which fixes when a rolling
    /// barrel has to set off.
    mutating func layRow(runnerAt distance: Double, time: Double) -> Row {
        let position = nextRow
        let lane = path.removeFirst()
        extendPath()
        var kinds = [Obstacle.Kind?](repeating: nil, count: Body.lanes)
        var lengths = [Double?](repeating: nil, count: Body.lanes)

        if lessonsLeft > 0 {
            switch Self.lessons - lessonsLeft {
            case 0: kinds = [nil, .stack, .stack]
            case 1: kinds = [.barrier, .barrier, .barrier]
            default: kinds = [.beam, .beam, .beam]
            }
            lessonsLeft -= 1
        } else {
            let level = Pace.difficulty(at: position)
            let open = (0..<Body.lanes).filter { reservedUntil[$0] <= position }
            if open.count == Body.lanes && random.chance(0.06 + 0.12 * level) {
                // Something right across: no going round it.
                let kind: Obstacle.Kind = random.chance(0.5) ? .barrier : .beam
                kinds = [kind, kind, kind]
            } else {
                if open.contains(lane) && random.chance(0.15 + 0.5 * level) {
                    kinds[lane] = actionKind(at: position, level: level)
                }
                let blockChance = 0.35 + 0.4 * level
                for other in open where other != lane {
                    let roll = random.nextUnit()
                    if roll < blockChance && position >= splitUntil {
                        kinds[other] = .stack
                        lengths[other] = longStackLength(in: other, at: position, level: level)
                    } else if roll < blockChance + (1 - blockChance) * 0.4 {
                        kinds[other] = actionKind(at: position, level: level)
                    }
                }
            }
        }

        var row = Row()
        for (index, kind) in kinds.enumerated() {
            guard let kind else { continue }
            if kind == .barrel {
                let rollSpeed = random.uniform(4...6)
                let meetTime = Pace.time(toReach: position, from: distance, at: time)
                row.obstacles.append(Obstacle(.barrel, lane: index, position: position, rollSpeed: rollSpeed, meetTime: meetTime))
                // Nothing may stand where it rolls in from.
                reservedUntil[index] = position + rollSpeed * Obstacle.barrelNotice + 2
            } else {
                let obstacle = Obstacle(kind, lane: index, position: position, length: lengths[index])
                row.obstacles.append(obstacle)
                if lengths[index] != nil {
                    reservedUntil[index] = position + obstacle.length + 3
                    if index == 1 { splitUntil = position + obstacle.length + Self.crossingRoom }
                }
            }
        }
        layCoins(into: &row, at: position, lane: lane, over: kinds[lane])
        previousRow = position
        previousLane = lane
        nextRow = position + Pace.rowSpacing(at: position)
        return row
    }

    /// Something that a jump or a slide gets past. Barrels start rolling half a kilometre in.
    private mutating func actionKind(at position: Double, level: Double) -> Obstacle.Kind {
        if random.chance(0.5) { return .beam }
        return position > 500 && random.chance(0.2 + 0.3 * level) ? .barrel : .barrier
    }

    /// A long stack's length, if one may lie in `lane` from `position`: far enough in, and
    /// the path stays out of that lane for as long as the stack runs.
    private mutating func longStackLength(in lane: Int, at position: Double, level: Double) -> Double? {
        guard position > 250, random.chance(0.12 + 0.2 * level) else { return nil }
        let length = random.uniform(9...20)
        var row = position
        for pathLane in path {
            row += Pace.rowSpacing(at: row)
            if row > position + length + 3 { return length }
            if pathLane == lane { return nil }
        }
        return nil
    }

    /// Coins along the path: a line up to the row, crossing to the path's lane half way, and
    /// over, under or through the row itself. Now and then a power-up takes a coin's place.
    private mutating func layCoins(into row: inout Row, at position: Double, lane: Int, over kind: Obstacle.Kind?) {
        let lineWanted = random.chance(0.72)
        let pickupWanted = position >= nextPickup
        // The first row has no row before it: its line starts a few strides out.
        let from = max(previousRow, position - 16) + 4
        let to = position - 4
        let middle = (from + to) / 2
        if pickupWanted {
            row.pickups.append(Pickup(kind: nextPickupKind, lane: lane, position: middle + Self.coinSpacing))
            nextPickupKind = nextPickupKind == .magnet ? .shield : .magnet
            nextPickup = position + random.uniform(280...420)
        }
        guard lineWanted else { return }
        var at = from
        while at <= to {
            let coinLane = at < middle ? previousLane : lane
            let taken = row.pickups.contains { abs($0.position - at) < Self.coinSpacing }
            if !taken { row.coins.append(Coin(lane: coinLane, position: at, height: Coin.usualHeight)) }
            at += Self.coinSpacing
        }
        switch kind?.answer {
        case .jump?:
            // An arc that a jump peaking over the obstacle runs through.
            let speed = Pace.speed(at: position)
            let jump = Body.jumpTime
            for step in -2...2 {
                let offset = Double(step) * speed * jump / 6
                let height = Coin.usualHeight + Body.jumpHeight(after: jump / 2 + offset / speed)
                row.coins.append(Coin(lane: lane, position: position + offset, height: height))
            }
        case .slide?:
            for step in -1...1 {
                row.coins.append(Coin(lane: lane, position: position + Double(step) * Self.coinSpacing, height: 0.4))
            }
        default:
            if kind == nil {
                for step in -1...1 {
                    row.coins.append(Coin(lane: lane, position: position + Double(step) * Self.coinSpacing, height: Coin.usualHeight))
                }
            }
        }
    }
}
