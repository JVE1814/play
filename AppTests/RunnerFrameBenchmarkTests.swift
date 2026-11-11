@testable import Runner
import QuartzCore
import RunnerEngine
import SwiftUI
import XCTest

/// What it costs to rasterize one frame of the pier on the CPU, at a phone's scale. Prints
/// `RUNNER-PERF raster` lines to the test log, so changes to the painter can be compared.
@MainActor
final class RunnerFrameBenchmarkTests: XCTestCase {
    private static let size = CGSize(width: 377, height: 640)

    private func seconds(_ body: () -> Void) -> Double {
        let begin = CACurrentMediaTime()
        body()
        return CACurrentMediaTime() - begin
    }

    private func render(_ paint: @escaping (inout GraphicsContext) -> Void) -> Double {
        let renderer = ImageRenderer(content: Canvas { context, _ in
            var context = context
            paint(&context)
        }.frame(width: Self.size.width, height: Self.size.height))
        renderer.scale = 3
        return seconds { XCTAssertNotNil(renderer.cgImage) }
    }

    private func frames(of start: Run, count: Int, scenery: Scenery) -> [PierFrame] {
        var run = start
        return (0..<count).map { index in
            run.advance(by: 1.0 / 60)
            return PierFrame(size: Self.size, run: run, scenery: scenery, clock: Double(index) / 60, reduceMotion: false,
                             standing: false, sinceCoin: 0.1, sinceShieldBroke: nil, sinceCrash: nil)
        }
    }

    private func centile(_ values: [Double], _ p: Double) -> Double {
        let sorted = values.sorted()
        return sorted[min(sorted.count - 1, Int(Double(sorted.count) * p))]
    }

    func testRasterizingAFrameOfThePier() {
        var probe = Scenarios.probeCourse
        probe.advance(by: 2.5)
        let course = RunnerBot.expert.play(Run(seed: 3), to: 400)
        let empty = (0..<60).map { _ in render { _ in } }
        let overhead = centile(empty, 0.5)
        print(String(format: "RUNNER-PERF raster empty-canvas p50=%.2f ms", overhead * 1_000))
        for (name, start) in [("probe", probe), ("course", course)] {
            for (scheme, scenery) in [("dark", Scenery.night), ("light", Scenery.dusk)] {
                let times = frames(of: start, count: 120, scenery: scenery).map { frame in
                    render { PierPainter(f: frame).paint(&$0) } - overhead
                }
                print(String(format: "RUNNER-PERF raster %@ %@ p50=%.2f p95=%.2f max=%.2f ms", name, scheme,
                             centile(times, 0.5) * 1_000, centile(times, 0.95) * 1_000, (times.max() ?? 0) * 1_000))
            }
        }
    }
}
