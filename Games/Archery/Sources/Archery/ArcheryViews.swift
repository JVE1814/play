import ArcheryEngine
import PlayKit
import SwiftUI

/// A score as on a score sheet, in the colour of the ring it hit.
struct ScoreChip: View {
    let hit: Hit
    let size: CGFloat

    var body: some View {
        let colors = ArcheryStyle.chip(for: hit)
        Text(hit.label)
            .font(.system(size: size * 0.5, weight: .heavy, design: .rounded))
            .foregroundStyle(colors.text)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(width: size, height: size)
            .background(Circle().fill(colors.fill))
            .overlay(Circle().strokeBorder(Color.black.opacity(0.25), lineWidth: 1))
            .accessibilityLabel(hit.spokenLabel)
    }
}

extension Hit {
    /// What VoiceOver says: the number, "X", or "Miss" (rather than the letter M).
    var spokenLabel: String {
        if isX { return "X" }
        return ring == 0 ? "Miss" : "\(ring)"
    }
}

/// An arrow never shot (the time ran out).
struct EmptyChip: View {
    let size: CGFloat

    var body: some View {
        Text("–")
            .font(.system(size: size * 0.5, weight: .heavy, design: .rounded))
            .foregroundStyle(Theme.inkSecondary)
            .frame(width: size, height: size)
            .background(Circle().fill(Theme.hairline))
            .accessibilityLabel("Not shot")
    }
}

/// A five-pointed star.
struct StarShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY + rect.height * 0.04)
        let outer = min(rect.width, rect.height) / 2
        for i in 0..<10 {
            let angle = -CGFloat.pi / 2 + CGFloat(i) * .pi / 5
            let r = i % 2 == 0 ? outer : outer * 0.45
            let p = CGPoint(x: c.x + r * cos(angle), y: c.y + r * sin(angle))
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }
}

/// Three stars, filled for those earned.
struct StarRow: View {
    let stars: Int
    let size: CGFloat

    var body: some View {
        HStack(spacing: size * 0.15) {
            ForEach(0..<3, id: \.self) { index in
                StarShape()
                    .fill(index < stars ? Theme.highlight : Theme.hairline)
                    .frame(width: size, height: size)
            }
        }
    }
}

/// The home screen illustration: a target face with an arrow in the gold.
struct ArcheryIcon: View {
    var body: some View {
        Canvas { context, size in
            let d = min(size.width, size.height) * 0.86
            let c = CGPoint(x: size.width / 2 - d * 0.04, y: size.height / 2 + d * 0.05)
            let zones: [Face.Zone] = [.white, .black, .blue, .red, .gold]
            for (index, zone) in zones.enumerated() {
                let r = d / 2 * (1 - CGFloat(index) * 0.19)
                let circle = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
                context.fill(circle, with: .color(ArcheryStyle.zoneColor(zone)))
                context.stroke(circle, with: .color(ArcheryStyle.ringLine(zone)), lineWidth: max(0.5, d * 0.008))
            }
            // An arrow just off the middle, its shaft pointing back up and to the right.
            let tip = CGPoint(x: c.x + d * 0.04, y: c.y - d * 0.03)
            let tail = CGPoint(x: tip.x + d * 0.34, y: tip.y - d * 0.34)
            var shaft = Path()
            shaft.move(to: tip)
            shaft.addLine(to: tail)
            context.stroke(shaft, with: .color(Color(hex: 0x2A2B31)), style: StrokeStyle(lineWidth: d * 0.055, lineCap: .round))
            for angle in [-135.0, -15.0, 105.0] {
                let radians = angle * .pi / 180
                var vane = Path()
                vane.move(to: tail)
                vane.addLine(to: CGPoint(x: tail.x + CGFloat(cos(radians)) * d * 0.13, y: tail.y + CGFloat(sin(radians)) * d * 0.13))
                context.stroke(vane, with: .color(ArcheryStyle.fletching(0)),
                               style: StrokeStyle(lineWidth: d * 0.07, lineCap: .round))
            }
            let nock = d * 0.045
            context.fill(Path(ellipseIn: CGRect(x: tail.x - nock, y: tail.y - nock, width: nock * 2, height: nock * 2)),
                         with: .color(Color(hex: 0xFFD60A)))
        }
    }
}

/// Rows for the shared Settings screen.
struct ArcherySettingsRows: View {
    @ObservedObject var preferences: ArcheryPreferences

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsChoiceRow("Aim speed",
                              detail: "How far the sight moves when you slide your thumb.",
                              choices: [(0, "Slow"), (1, "Normal"), (2, "Fast")],
                              selection: $preferences.aimSpeed,
                              identifier: "aimSpeed")
            SettingsDivider()
            SettingsToggleRow("Steady aim",
                              detail: "Much less sway. Helpful for shaky hands or a bumpy ride.",
                              isOn: $preferences.steadyAim,
                              identifier: "steadyAim")
            SettingsDivider()
            SettingsToggleRow("Left-handed archer",
                              detail: "Hold the bow in your right hand.",
                              isOn: $preferences.leftHanded,
                              identifier: "leftHandedArcher")
        }
    }
}
