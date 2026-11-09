import Foundation

/// One run along the pier: the runner, the course ahead and what has been collected.
///
/// Time moves in fixed steps, so the same seed and the same moves at the same moments always
/// give the same run, whatever the frame rate.
public struct Run: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable {
        case running, crashed
    }

    /// Something that happened, for sounds, haptics and announcements.
    public enum Event: Equatable, Sendable {
        case changedLane
        /// A swipe towards the edge of the pier.
        case hitEdge
        case jumped, slid, landed
        case coin
        case pickup(Pickup.Kind)
        /// The shield took a hit and is gone.
        case shieldBroke
        case crashed
    }

    /// Seconds in one step of the simulation.
    public static let step = 1.0 / 120
    /// Points for a coin; a metre is one point.
    public static let coinValue = 5
    public static let magnetTime = 8.0
    /// After the shield breaks, nothing hurts for this long.
    static let graceTime = 1.0
    /// Metres of course kept laid ahead of the runner.
    static let sight = 130.0
    /// Metres behind the runner at which things are forgotten.
    static let wake = 6.0

    public private(set) var status = Status.running
    /// Metres run.
    public private(set) var distance = 0.0
    /// Seconds run.
    public private(set) var time = 0.0
    /// The lane the runner is in, or heading for.
    public private(set) var lane = Body.startLane
    /// Where the runner is across the pier, in lanes: on the way to `lane` during a change.
    public private(set) var across = Double(Body.startLane)
    /// Height of the feet above the planks.
    public private(set) var height = 0.0
    public private(set) var isAirborne = false
    private var verticalSpeed = 0.0
    private var slideLeft = 0.0
    /// A slide was asked for in the air: the runner tucks, drops and slides on landing.
    private var slidesOnLanding = false
    private var jumpBufferLeft = 0.0
    public private(set) var coinCount = 0
    public private(set) var hasShield = false
    public private(set) var magnetLeft = 0.0
    private var graceLeft = 0.0
    /// What ended the run.
    public private(set) var crashedInto: Obstacle?

    public private(set) var obstacles: [Obstacle] = []
    public private(set) var coins: [Coin] = []
    public private(set) var pickups: [Pickup] = []
    private var builder: CourseBuilder?
    /// Where the coached opening ends (0 without one).
    private var lessonsEnd = 0.0
    /// Time given to `advance` that has not filled a step yet.
    private var carry = 0.0

    /// - Parameter coached: the course opens with three easy rows, one for each move, and
    ///   `prompt` says what to do at each.
    public init(seed: UInt64, coached: Bool = false) {
        let builder = CourseBuilder(seed: seed, coached: coached)
        lessonsEnd = builder.lessonsEnd
        self.builder = builder
        layCourse()
    }

    /// A course laid by hand, which never grows. Used for fixtures and tests.
    public init(obstacles: [Obstacle] = [], coins: [Coin] = [], pickups: [Pickup] = []) {
        self.obstacles = obstacles.sorted { $0.position < $1.position }
        self.coins = coins.sorted { $0.position < $1.position }
        self.pickups = pickups.sorted { $0.position < $1.position }
    }

    // MARK: State

    public var speed: Double { Pace.speed(at: distance) }
    public var score: Int { Int(distance) + Self.coinValue * coinCount }
    public var isSliding: Bool { !isAirborne && slideLeft > 0 }
    /// Curled up: sliding, or dropping out of a jump into a slide.
    public var isTucked: Bool { isSliding || slidesOnLanding }
    public var hasMagnet: Bool { magnetLeft > 0 }
    /// True for a moment after the shield breaks.
    public var isShaken: Bool { graceLeft > 0 }

    private var bodyTop: Double { height + (isTucked ? Body.tuckedHeight : Body.height) }

    /// The distance to draw the course from: `distance`, plus the part of a step that
    /// `advance` is still holding, so the course scrolls smoothly at any frame rate.
    public var drawnDistance: Double {
        status == .running ? distance + speed * carry : distance
    }

    /// The nearest obstacle still ahead in the runner's lane.
    public var obstacleAhead: Obstacle? {
        obstacles.first { $0.lane == lane && $0.isOnCourse(at: time) && $0.nearSide(at: time) > distance }
    }

    /// Seconds until the runner reaches `obstacle` at the present speed.
    public func seconds(to obstacle: Obstacle) -> Double {
        (obstacle.nearSide(at: time) - distance) / (speed + obstacle.rollSpeed)
    }

    /// During the coached opening, the move to make now.
    public var prompt: Move? {
        guard status == .running, distance < lessonsEnd, let ahead = obstacleAhead,
              ahead.position <= lessonsEnd, seconds(to: ahead) < 1.3 else { return nil }
        return ahead.kind.answer ?? .left
    }

    /// Whole state as text, for UI tests.
    public var signature: String {
        let pose = isAirborne ? "air" : (isSliding ? "slide" : "run")
        return "\(status.rawValue)|m:\(Int(distance))|lane:\(lane)|\(pose)|coins:\(coinCount)"
            + (hasShield ? "|shield" : "") + (hasMagnet ? "|magnet" : "")
    }

    // MARK: Moves

    /// Makes a move now. Returns what came of it, if anything did at once.
    @discardableResult
    public mutating func perform(_ move: Move) -> Event? {
        guard status == .running else { return nil }
        switch move {
        case .left, .right:
            let target = lane + (move == .left ? -1 : 1)
            guard (0..<Body.lanes).contains(target) else { return .hitEdge }
            lane = target
            return .changedLane
        case .jump:
            guard !isAirborne else {
                jumpBufferLeft = Body.jumpBuffer
                slidesOnLanding = false
                return nil
            }
            takeOff()
            return .jumped
        case .slide:
            if isAirborne {
                verticalSpeed = min(verticalSpeed, -Body.dropSpeed)
                slidesOnLanding = true
                jumpBufferLeft = 0
            } else {
                slideLeft = Body.slideTime
            }
            return .slid
        }
    }

    private mutating func takeOff() {
        isAirborne = true
        verticalSpeed = Body.jumpSpeed
        slideLeft = 0
        slidesOnLanding = false
        jumpBufferLeft = 0
    }

    // MARK: Time

    /// Moves the run on by `seconds` of play.
    @discardableResult
    public mutating func advance(by seconds: Double) -> [Event] {
        guard status == .running else { return [] }
        carry += max(0, seconds)
        var events: [Event] = []
        while carry >= Self.step, status == .running {
            carry -= Self.step
            step(&events)
        }
        return events
    }

    private mutating func step(_ events: inout [Event]) {
        let dt = Self.step
        time += dt
        let stride = dt / Body.laneChangeTime
        across += max(-stride, min(stride, Double(lane) - across))
        if isAirborne {
            verticalSpeed -= Body.gravity * dt
            height += verticalSpeed * dt
            if height <= 0 { land(&events) }
        } else {
            slideLeft = max(0, slideLeft - dt)
        }
        jumpBufferLeft = max(0, jumpBufferLeft - dt)
        magnetLeft = max(0, magnetLeft - dt)
        graceLeft = max(0, graceLeft - dt)
        distance += speed * dt
        layCourse()
        collect(&events)
        collide(&events)
        forgetWhatIsBehind()
    }

    private mutating func land(_ events: inout [Event]) {
        height = 0
        verticalSpeed = 0
        isAirborne = false
        events.append(.landed)
        if slidesOnLanding {
            slidesOnLanding = false
            slideLeft = Body.slideTime
        } else if jumpBufferLeft > 0 {
            takeOff()
            events.append(.jumped)
        }
    }

    private mutating func layCourse() {
        while let next = builder?.nextRow, next < distance + Self.sight {
            guard let row = builder?.layRow(runnerAt: distance, time: time) else { return }
            obstacles = (obstacles + row.obstacles).sorted { $0.position < $1.position }
            coins = (coins + row.coins).sorted { $0.position < $1.position }
            pickups += row.pickups
        }
    }

    /// The runner's body is over something lying at `position` in `lane`, `height` up.
    private func touches(lane: Int, position: Double, height: Double) -> Bool {
        abs(position - distance) < 0.7 && abs(Double(lane) - across) < 0.6
            && height > self.height - 0.35 && height < bodyTop + 0.35
    }

    private mutating func collect(_ events: inout [Event]) {
        // With the magnet, every coin that comes level is pulled in, whatever its lane or height.
        let pull = hasMagnet ? 1.5 : 0.0
        var index = 0
        while index < coins.count, coins[index].position <= distance + max(pull, 0.7) {
            let coin = coins[index]
            if abs(coin.position - distance) < pull || touches(lane: coin.lane, position: coin.position, height: coin.height) {
                coins.remove(at: index)
                coinCount += 1
                events.append(.coin)
            } else {
                index += 1
            }
        }
        if let index = pickups.firstIndex(where: { touches(lane: $0.lane, position: $0.position, height: Pickup.height) }) {
            let kind = pickups.remove(at: index).kind
            switch kind {
            case .magnet: magnetLeft = Self.magnetTime
            case .shield: hasShield = true
            }
            events.append(.pickup(kind))
        }
    }

    private mutating func collide(_ events: inout [Event]) {
        guard graceLeft == 0, let index = obstacles.firstIndex(where: touches) else { return }
        if hasShield {
            hasShield = false
            graceLeft = Self.graceTime
            obstacles.remove(at: index)
            events.append(.shieldBroke)
        } else {
            status = .crashed
            crashedInto = obstacles[index]
            carry = 0
            events.append(.crashed)
        }
    }

    private func touches(_ obstacle: Obstacle) -> Bool {
        guard obstacle.isOnCourse(at: time), abs(Double(obstacle.lane) - across) < Body.reach else { return false }
        let near = obstacle.nearSide(at: time)
        guard near < distance + Body.halfDepth, near + obstacle.length > distance - Body.halfDepth else { return false }
        let blocked = obstacle.kind.blocked
        return height < blocked.upperBound && bodyTop > blocked.lowerBound
    }

    private mutating func forgetWhatIsBehind() {
        let line = distance - Self.wake
        if let first = obstacles.first, first.position + first.length < line, first.nearSide(at: time) + first.length < line {
            obstacles.removeFirst()
        }
        if let first = coins.first, first.position < line { coins.removeFirst() }
        if let first = pickups.first, first.position < line { pickups.removeFirst() }
    }
}
