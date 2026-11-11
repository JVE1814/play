import Darwin
import Foundation
import os

/// Debug builds, with `-frameProbe`: a small sampling profiler for the main thread. A thread of
/// its own stops the main thread a thousand times a second, notes where it is (its call stack,
/// by frame pointers), and lets it go on. Afterwards the addresses are named by library and
/// symbol, to say where the main thread's time goes: SwiftUI, the renderer, Metal, Core
/// Graphics, or the game's own code.
///
/// Nothing is allocated while the main thread is stopped (it may hold the allocator's lock), and
/// names are looked up only once sampling has ended.
final class MainThreadSampler: @unchecked Sendable {
    private static let depth = 48
    private static let capacity = 16_000
    /// arm_thread_state64_t as plain words: x0-x28, fp, lr, sp, pc, then cpsr and padding.
    private static let stateWords = 34
    private static let flavor: thread_state_flavor_t = 6   // ARM_THREAD_STATE64
    /// Return addresses can carry pointer-authentication bits above the address.
    private static let addressMask: UInt = 0x0000_007F_FFFF_FFFF

    private let thread: thread_t
    private let stackLow: UInt
    private let stackHigh: UInt
    private let frames: UnsafeMutablePointer<UInt>
    private let lengths: UnsafeMutablePointer<Int>
    private let state: UnsafeMutablePointer<UInt64>
    private var count = 0
    private let stopping = OSAllocatedUnfairLock(initialState: false)
    private let finished = OSAllocatedUnfairLock(initialState: false)

    /// Call on the main thread.
    init() {
        thread = mach_thread_self()
        let main = pthread_self()
        stackHigh = UInt(bitPattern: pthread_get_stackaddr_np(main))
        stackLow = stackHigh - UInt(pthread_get_stacksize_np(main))
        frames = .allocate(capacity: Self.depth * Self.capacity)
        lengths = .allocate(capacity: Self.capacity)
        state = .allocate(capacity: Self.stateWords)
    }

    deinit {
        frames.deallocate()
        lengths.deallocate()
        state.deallocate()
    }

    func start() {
        let sampler = Thread { [self] in
            while !stopping.withLock({ $0 }) && count < Self.capacity {
                usleep(1_000)
                sample()
            }
            finished.withLock { $0 = true }
        }
        sampler.qualityOfService = .userInteractive
        sampler.start()
    }

    /// Stops sampling and says where the time went. Call on the main thread.
    func stop() -> String {
        stopping.withLock { $0 = true }
        while !finished.withLock({ $0 }) { usleep(200) }
        return describe()
    }

    private func sample() {
        #if arch(arm64)
        guard thread_suspend(thread) == KERN_SUCCESS else { return }
        var words = mach_msg_type_number_t(Self.stateWords * 2)
        let read = state.withMemoryRebound(to: natural_t.self, capacity: Self.stateWords * 2) {
            thread_get_state(thread, Self.flavor, $0, &words)
        }
        guard read == KERN_SUCCESS else {
            thread_resume(thread)
            return
        }
        let row = frames + count * Self.depth
        var length = 0
        row[length] = UInt(state[32]) & Self.addressMask         // pc
        length += 1
        var fp = UInt(state[29])
        while length < Self.depth, fp >= stackLow, fp + 16 <= stackHigh, fp & 7 == 0 {
            let link = UnsafePointer<UInt>(bitPattern: fp)!
            let next = link[0]
            let back = link[1] & Self.addressMask
            if back == 0 { break }
            row[length] = back
            length += 1
            if next <= fp { break }
            fp = next
        }
        thread_resume(thread)
        lengths[count] = length
        count += 1
        #endif
    }

    private func describe() -> String {
        var names: [UInt: (image: String, symbol: String)] = [:]
        func name(_ address: UInt) -> (image: String, symbol: String) {
            if let known = names[address] { return known }
            var info = Dl_info()
            var found = ("?", "?")
            if let pointer = UnsafeRawPointer(bitPattern: address), dladdr(pointer, &info) != 0 {
                let image = info.dli_fname.map { String(cString: $0) }.map { ($0 as NSString).lastPathComponent } ?? "?"
                let symbol = info.dli_sname.map { String(cString: $0) } ?? "?"
                found = (image, String(symbol.prefix(60)))
            }
            names[address] = found
            return found
        }
        var waiting = 0
        var busy = 0
        var selfImages: [String: Int] = [:]
        var selfSymbols: [String: Int] = [:]
        var inclusive: [String: Int] = [:]
        /// For the stretches it was blocked, what it was waiting in: the first two callers
        /// above the system's waiting calls.
        var blockedIn: [String: Int] = [:]
        var blocked = 0
        for index in 0..<count {
            let row = frames + index * Self.depth
            let leaf = name(row[0])
            // Asleep in the run loop, waiting for the next thing to do.
            if leaf.symbol.contains("mach_msg") || leaf.symbol.contains("semwait") {
                waiting += 1
                continue
            }
            busy += 1
            if leaf.symbol.contains("wait") {
                blocked += 1
                var callers: [String] = []
                for depth in 1..<max(1, lengths[index]) where callers.count < 2 {
                    let frame = name(row[depth])
                    if frame.image.hasPrefix("libsystem_") || frame.image == "libdispatch.dylib" { continue }
                    callers.append("\(frame.symbol)@\(frame.image)")
                }
                blockedIn[callers.joined(separator: "<"), default: 0] += 1
            }
            selfImages[leaf.image, default: 0] += 1
            selfSymbols["\(leaf.symbol)@\(leaf.image)", default: 0] += 1
            var seen = Set<String>()
            for depth in 0..<lengths[index] { seen.insert(name(row[depth]).image) }
            for image in seen { inclusive[image, default: 0] += 1 }
        }
        func top(_ counts: [String: Int], _ limit: Int) -> String {
            counts.sorted { $0.value > $1.value }.prefix(limit)
                .map { "\($0.key.replacingOccurrences(of: " ", with: "_")):\(String(format: "%.1f", 100 * Double($0.value) / Double(max(1, busy))))" }
                .joined(separator: ",")
        }
        return " prof_samples=\(count) prof_waiting=\(String(format: "%.1f", 100 * Double(waiting) / Double(max(1, count))))"
            + " prof_self=\(top(selfImages, 8)) prof_incl=\(top(inclusive, 12)) prof_sym=\(top(selfSymbols, 14))"
            + " prof_blocked=\(String(format: "%.1f", 100 * Double(blocked) / Double(max(1, busy)))) prof_blocked_in=\(top(blockedIn, 6))"
    }
}
