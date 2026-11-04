import KlondikeEngine
import SwiftUI

/// Original flat suit shapes. Each suit has a distinct silhouette, so suits can be told apart
/// without relying on colour.
struct SuitShape: Shape {
    let suit: Suit

    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        var path = Path()
        switch suit {
        case .diamonds:
            path.move(to: p(0.5, 0.0))
            path.addQuadCurve(to: p(0.9, 0.5), control: p(0.68, 0.3))
            path.addQuadCurve(to: p(0.5, 1.0), control: p(0.68, 0.7))
            path.addQuadCurve(to: p(0.1, 0.5), control: p(0.32, 0.7))
            path.addQuadCurve(to: p(0.5, 0.0), control: p(0.32, 0.3))
        case .hearts:
            path.move(to: p(0.5, 0.27))
            path.addCurve(to: p(0.0, 0.32), control1: p(0.4, 0.0), control2: p(0.0, 0.02))
            path.addCurve(to: p(0.5, 0.98), control1: p(0.0, 0.62), control2: p(0.36, 0.76))
            path.addCurve(to: p(1.0, 0.32), control1: p(0.64, 0.76), control2: p(1.0, 0.62))
            path.addCurve(to: p(0.5, 0.27), control1: p(1.0, 0.02), control2: p(0.6, 0.0))
        case .spades:
            var body = Path()
            body.move(to: p(0.5, 0.0))
            body.addCurve(to: p(0.0, 0.56), control1: p(0.36, 0.2), control2: p(0.0, 0.3))
            body.addCurve(to: p(0.5, 0.62), control1: p(0.0, 0.8), control2: p(0.38, 0.84))
            body.addCurve(to: p(1.0, 0.56), control1: p(0.62, 0.84), control2: p(1.0, 0.8))
            body.addCurve(to: p(0.5, 0.0), control1: p(1.0, 0.3), control2: p(0.64, 0.2))
            body.closeSubpath()
            // Union (not just appending subpaths) so overlaps never cancel out when filled.
            return body.union(stem(in: rect))
        case .clubs:
            let r: CGFloat = 0.215
            let leaf = CGSize(width: 2 * r * rect.width, height: 2 * r * rect.height)
            var club = Path(ellipseIn: CGRect(origin: p(0.5 - r, 0.04), size: leaf))
            club = club.union(Path(ellipseIn: CGRect(origin: p(0.02, 0.38), size: leaf)))
            club = club.union(Path(ellipseIn: CGRect(origin: p(0.98 - 2 * r, 0.38), size: leaf)))
            club = club.union(Path(ellipseIn: CGRect(origin: p(0.34, 0.34), size: CGSize(width: 0.32 * rect.width, height: 0.32 * rect.height))))
            return club.union(stem(in: rect))
        }
        path.closeSubpath()
        return path
    }

    private func stem(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        var stem = Path()
        stem.move(to: p(0.5, 0.52))
        stem.addQuadCurve(to: p(0.28, 1.0), control: p(0.47, 0.9))
        stem.addLine(to: p(0.72, 1.0))
        stem.addQuadCurve(to: p(0.5, 0.52), control: p(0.53, 0.9))
        stem.closeSubpath()
        return stem
    }
}
