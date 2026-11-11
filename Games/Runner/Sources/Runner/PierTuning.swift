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

    /// The pier's accessibility is set outside the timeline, so it is not rebuilt every frame.
    static let quietAccessibility = PierTuning(rawValue: 1 << 3)
    /// The score and coins in the heads-up display change at most 15 times a second.
    static let calmHUD = PierTuning(rawValue: 1 << 4)

    /// The calm heads-up display is tried by name only (`hud`): it lags the score a little.
    static let all: PierTuning = [.gpu, .fullRate, .frameClock, .quietAccessibility]

    init(rawValue: Int) { self.rawValue = rawValue }

    init(options: LaunchOptions) {
        guard let list = options.value(after: "-pierTuning") else {
            self = .all
            return
        }
        let names: [String: PierTuning] = ["gpu": .gpu, "rate": .fullRate, "clock": .frameClock, "ax": .quietAccessibility, "hud": .calmHUD]
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
    /// From the start of the frame's view update to the end of its painting.
    private var works: [Double] = []
    private var updateBegan: CFTimeInterval?
    /// The gaps between the beats of a display link of the probe's own: one that arrives late
    /// means the main thread was held up, rather than the drawing falling behind.
    private var beats: [Double] = []
    private var lastBeat: CFTimeInterval?
    /// How long the main thread works each time it wakes, everything included (view updates,
    /// painting, rendering what was painted, the session's tick), and the longest of those
    /// stretches with what woke it.
    private var busy: [Double] = []
    private var woke: CFTimeInterval?
    /// The same stretches in the main thread's own CPU time, which a busy machine does not
    /// stretch, and the main thread's CPU time over the whole measurement, everything included.
    private var busyCPU: [Double] = []
    private var wokeCPU: Double?
    private var cpuAtStart: Double?
    private var wallAtStart: CFTimeInterval?

    /// Seconds of CPU the calling thread has used.
    private static func threadCPU() -> Double {
        Double(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)) / 1e9
    }
    private var watcher: CFRunLoopObserver?
    private(set) var report: String?

    /// Frames in the first half second are not counted: the screen is still settling.
    private static let warmUp = 0.5

    init?(options: LaunchOptions) {
        guard let value = options.value(after: "-frameProbe").flatMap(Double.init) else { return nil }
        seconds = value
    }

    /// The view update of a frame begins.
    func updateBegins(at time: CFTimeInterval) {
        updateBegan = time
    }

    /// Starts timing the main thread's working stretches.
    func watchMainThread() {
        guard watcher == nil else { return }
        let activities = CFRunLoopActivity.afterWaiting.rawValue | CFRunLoopActivity.beforeWaiting.rawValue
        let watcher = CFRunLoopObserverCreateWithHandler(nil, activities, true, 0) { [weak self] _, activity in
            guard let self, self.report == nil else { return }
            let now = CACurrentMediaTime()
            let cpu = Self.threadCPU()
            if activity == .afterWaiting {
                self.woke = now
                self.wokeCPU = cpu
            } else if let woke = self.woke, let wokeCPU = self.wokeCPU {
                if let started = self.started, now - started > Self.warmUp {
                    self.busy.append(now - woke)
                    self.busyCPU.append(cpu - wokeCPU)
                }
                self.woke = nil
            }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), watcher, .commonModes)
        self.watcher = watcher
    }

    /// A beat of the probe's display link. False once the probe is done.
    func beat(at time: CFTimeInterval) -> Bool {
        guard report == nil else { return false }
        if let lastBeat, let started, time - started > Self.warmUp { beats.append(time - lastBeat) }
        lastBeat = time
        return true
    }

    /// Records one frame, painted from `begin` to `end`. True once the probe has seen enough.
    func record(begin: CFTimeInterval, end: CFTimeInterval) -> Bool {
        guard report == nil else { return false }
        let start = started ?? begin
        started = start
        if begin - start > Self.warmUp, cpuAtStart == nil {
            cpuAtStart = Self.threadCPU()
            wallAtStart = begin
        }
        if let last, begin - start > Self.warmUp {
            intervals.append(begin - last)
            paints.append(end - begin)
            if let updateBegan, updateBegan <= begin, begin - updateBegan < 0.1 { works.append(end - updateBegan) }
        }
        last = begin
        guard begin - start > Self.warmUp + seconds else { return false }
        let usage = cpuAtStart.flatMap { cpu in wallAtStart.map { (Self.threadCPU() - cpu) / max(0.001, begin - $0) } } ?? 0
        report = Self.describe(intervals: intervals, paints: paints, works: works, beats: beats, busy: busy, busyCPU: busyCPU)
            // The main thread's CPU per frame drawn, in milliseconds.
            + String(format: " main_cpu_use=%.3f main_cpu_per_frame=%.2f", usage,
                     usage * intervals.reduce(0, +) * 1_000 / max(1, Double(intervals.count)))
        if let watcher { CFRunLoopObserverInvalidate(watcher) }
        return true
    }

    private static func describe(intervals: [Double], paints: [Double], works: [Double], beats: [Double], busy: [Double], busyCPU: [Double]) -> String {
        func ms(_ value: Double) -> String { String(format: "%.2f", value * 1_000) }
        func centile(_ sorted: [Double], _ p: Double) -> Double {
            sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * p))]
        }
        let gaps = intervals.sorted()
        let paint = paints.sorted()
        let work = works.sorted()
        let total = intervals.reduce(0, +)
        // A frame that took more than one and a half of the usual is a hitch.
        let usual = centile(gaps, 0.5)
        let hitches = intervals.filter { $0 > usual * 1.5 }.count
        return "frames=\(intervals.count) fps=\(String(format: "%.1f", Double(intervals.count) / max(total, 0.001)))"
            + " gap_p50=\(ms(usual)) gap_p95=\(ms(centile(gaps, 0.95))) gap_p99=\(ms(centile(gaps, 0.99))) gap_max=\(ms(gaps.last ?? 0))"
            + " hitches=\(hitches) paint_p50=\(ms(centile(paint, 0.5))) paint_p95=\(ms(centile(paint, 0.95))) paint_max=\(ms(paint.last ?? 0))"
            + " work_p50=\(ms(centile(work, 0.5))) work_p95=\(ms(centile(work, 0.95)))"
            // The probe's display link asks for 60 a second: a beat more than 25 ms after the
            // last one is a frame the main thread missed.
            + " main_beats=\(beats.count) main_missed=\(beats.filter { $0 > 0.025 }.count) main_gap_max=\(ms(beats.max() ?? 0))"
            + " busy_n=\(busy.count) busy_p50=\(ms(centile(busy.sorted(), 0.5))) busy_p95=\(ms(centile(busy.sorted(), 0.95)))"
            + " busy_p99=\(ms(centile(busy.sorted(), 0.99))) busy_max=\(ms(busy.max() ?? 0)) busy_over16=\(busy.filter { $0 > 0.016 }.count)"
            + " cpu_p50=\(ms(centile(busyCPU.sorted(), 0.5))) cpu_p95=\(ms(centile(busyCPU.sorted(), 0.95))) cpu_max=\(ms(busyCPU.max() ?? 0))"
    }
}
