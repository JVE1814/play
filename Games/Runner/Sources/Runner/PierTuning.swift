import Foundation
import PlayKit
import QuartzCore

/// How the pier is drawn and the run is clocked. Every option is on in the app; debug builds
/// can turn them off with `-pierTuning` (a comma-separated list, or `none`) to measure what
/// each one is worth.
struct PierTuning: OptionSet {
    let rawValue: Int

    /// The pier is rendered on the GPU (`drawingGroup`) instead of rasterized on the CPU.
    static let gpu = PierTuning(rawValue: 1 << 0)
    /// While running, the pier is drawn at the display's own rate (up to 120 Hz on ProMotion)
    /// instead of being held to a 60 Hz schedule, which skips frames that arrive a little early.
    static let fullRate = PierTuning(rawValue: 1 << 1)
    /// The run is played forward on the display's clock instead of a sleeping task, and the
    /// saves made along the way are written off the main thread.
    static let frameClock = PierTuning(rawValue: 1 << 2)

    static let all: PierTuning = [.gpu, .fullRate, .frameClock]

    init(rawValue: Int) { self.rawValue = rawValue }

    init(options: LaunchOptions) {
        guard let list = options.value(after: "-pierTuning") else {
            self = .all
            return
        }
        let names: [String: PierTuning] = ["gpu": .gpu, "rate": .fullRate, "clock": .frameClock]
        self = PierTuning(list.split(separator: ",").compactMap { names[String($0)] })
    }
}

/// Calls `tick` once for every frame the display shows, at up to 60 a second, until `stop()`
/// or until `tick` returns false.
@MainActor
final class FrameTicker {
    private final class Target: NSObject {
        let tick: @MainActor () -> Bool
        init(tick: @escaping @MainActor () -> Bool) { self.tick = tick }
        @objc func step(_ link: CADisplayLink) {
            if !MainActor.assumeIsolated({ tick() }) { link.invalidate() }
        }
    }

    private var link: CADisplayLink?

    init(tick: @escaping @MainActor () -> Bool) {
        let link = CADisplayLink(target: Target(tick: tick), selector: #selector(Target.step))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
    }
}

/// Debug builds, `-frameProbe SECONDS`: the run starts by itself, and after that many seconds
/// it pauses and the pier says how evenly it was drawn (in the `frameProbe` element's value).
final class FrameProbe {
    let seconds: Double
    private var started: CFTimeInterval?
    private var last: CFTimeInterval?
    private var intervals: [Double] = []
    private var paints: [Double] = []
    private(set) var report: String?

    /// Frames in the first half second are not counted: the screen is still settling.
    private static let warmUp = 0.5

    init?(options: LaunchOptions) {
        guard let value = options.value(after: "-frameProbe").flatMap(Double.init) else { return nil }
        seconds = value
    }

    /// Records one frame, painted from `begin` to `end`. True once the probe has seen enough.
    func record(begin: CFTimeInterval, end: CFTimeInterval) -> Bool {
        guard report == nil else { return false }
        let start = started ?? begin
        started = start
        if let last, begin - start > Self.warmUp {
            intervals.append(begin - last)
            paints.append(end - begin)
        }
        last = begin
        guard begin - start > Self.warmUp + seconds else { return false }
        report = Self.describe(intervals: intervals, paints: paints)
        return true
    }

    private static func describe(intervals: [Double], paints: [Double]) -> String {
        func ms(_ value: Double) -> String { String(format: "%.2f", value * 1_000) }
        func centile(_ sorted: [Double], _ p: Double) -> Double {
            sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * p))]
        }
        let gaps = intervals.sorted()
        let paint = paints.sorted()
        let total = intervals.reduce(0, +)
        // A frame that took more than one and a half of the usual is a hitch.
        let usual = centile(gaps, 0.5)
        let hitches = intervals.filter { $0 > usual * 1.5 }.count
        return "frames=\(intervals.count) fps=\(String(format: "%.1f", Double(intervals.count) / max(total, 0.001)))"
            + " gap_p50=\(ms(usual)) gap_p95=\(ms(centile(gaps, 0.95))) gap_p99=\(ms(centile(gaps, 0.99))) gap_max=\(ms(gaps.last ?? 0))"
            + " hitches=\(hitches) paint_p50=\(ms(centile(paint, 0.5))) paint_p95=\(ms(centile(paint, 0.95))) paint_max=\(ms(paint.last ?? 0))"
    }
}
