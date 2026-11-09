import ArcheryEngine
import CoreGraphics

/// Projects the range onto the screen. The camera sits at the archer's eye looking straight down
/// the range, magnified like a sight's scope so the target always appears at a comfortable size
/// (see `Optics`); the boss centre sits a little above the middle of the view.
struct RangeCamera {
    let size: CGSize
    let distance: Double
    /// Screen points per metre at one metre away (before zoom).
    let focal: CGFloat
    /// Where the boss centre at rest appears.
    let center: CGPoint
    /// Unzoomed screen height of the horizon.
    let horizon: CGFloat
    /// The view tightens a little while the bow is drawn.
    let zoom: CGFloat

    init(size: CGSize, distance: Double, zoom: CGFloat = 1) {
        self.size = size
        self.distance = distance
        self.zoom = zoom
        // Never so tall that the wind flag above the boss leaves the top of the view.
        let faceWidth = min(CGFloat(Optics.faceShare(distance: distance)) * size.width, size.height * 0.36)
        focal = faceWidth / 1.22 * CGFloat(distance)
        center = CGPoint(x: size.width / 2, y: size.height * 0.42)
        horizon = center.y - focal * CGFloat(Ballistics.eyeHeight - Ballistics.bossHeight) / CGFloat(distance)
    }

    /// Screen points per metre on the target.
    var pointsPerMetre: CGFloat { focal / CGFloat(distance) * zoom }

    /// Screen points per metre at `depth` metres from the eye.
    func scale(atDepth depth: Double) -> CGFloat { focal / CGFloat(max(depth, 0.05)) * zoom }

    func project(_ p: Vec3) -> CGPoint {
        let z = max(p.z, 0.05)
        let x = size.width / 2 + focal * CGFloat(p.x / z)
        let y = horizon - focal * CGFloat((p.y - Ballistics.eyeHeight) / z)
        return zoomed(CGPoint(x: x, y: y))
    }

    func zoomed(_ p: CGPoint) -> CGPoint {
        CGPoint(x: center.x + (p.x - center.x) * zoom, y: center.y + (p.y - center.y) * zoom)
    }

    /// A point on the target plane, in boss coordinates (metres from the boss centre at rest).
    func onTarget(_ v: Vec2) -> CGPoint {
        project(Vec3(v.x, Ballistics.bossHeight + v.y, distance))
    }

    /// Screen height of the ground `depth` metres away.
    func groundY(atDepth depth: Double) -> CGFloat { project(Vec3(0, 0, depth)).y }

    var horizonY: CGFloat { zoomed(CGPoint(x: 0, y: horizon)).y }

    /// The nearest ground still on screen.
    var nearestVisibleDepth: Double {
        let below = size.height - horizonY
        guard below > 1 else { return distance }
        return Double(focal * zoom) * Ballistics.eyeHeight / Double(below)
    }

    /// How far the sight may wander from the centre, in metres: to near the edges of the view.
    var aimLimit: Vec2 {
        let ppm = Double(pointsPerMetre)
        let c = onTarget(.zero)
        return Vec2(Double(size.width / 2 - 16) / ppm, Double(min(c.y, size.height - c.y) - 16) / ppm)
    }
}
