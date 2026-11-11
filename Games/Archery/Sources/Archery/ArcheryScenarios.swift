import ArcheryEngine

/// Prepared attempts for UI tests and screenshots, by `-scenario` name.
enum Scenarios {
    static func round(_ name: String?) -> ArcheryRound? {
        switch name {
        case "archeryNearWin":
            // Two arrows in the X ring; one more in the gold earns three stars.
            var round = ArcheryRound(level: LevelCatalog.level(1))
            round.shoot(aim: Vec2(0.012, 0.01))
            round.shoot(aim: Vec2(-0.015, -0.008))
            return round
        case "archeryLastArrow":
            // Two arrows in the straw outside the face: even a ten can't reach a star now.
            var round = ArcheryRound(level: LevelCatalog.level(1))
            round.shoot(aim: Vec2(0.63, 0.2))
            round.shoot(aim: Vec2(-0.62, -0.3))
            return round
        case "archeryShowcase":
            return demonstration(level: 22, hits: [(1.8, Vec2(0.02, 0.03)), (6.2, Vec2(-0.08, -0.05)),
                                                   (10.5, Vec2(0.12, 0.07))], clock: 13.4)
        case "archeryNight":
            return demonstration(level: 29, hits: [(2.4, Vec2(-0.05, 0.04)), (7.9, Vec2(0.16, -0.1))], clock: 11.2)
        default:
            return nil
        }
    }

    /// An attempt with arrows already in the target at `hits` (when shot, and where), seen at `clock`.
    private static func demonstration(level number: Int, hits: [(Double, Vec2)], clock: Double) -> ArcheryRound {
        var round = ArcheryRound(level: LevelCatalog.level(number))
        for (time, point) in hits {
            round.advance(to: time)
            round.shoot(aim: round.aim(toHit: point))
        }
        round.advance(to: clock)
        return round
    }
}
