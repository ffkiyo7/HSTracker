//
//  LatencyProbe.swift
//  HSTracker
//
//  Measures how long it takes for a Hearthstone log line to show up in the
//  overlay, so the pipeline can be optimised against numbers instead of
//  impressions. Three hooks in upstream files, no more: the log line entering
//  the parser, the refresh being asked for, and the refresh landing on screen.
//

import Foundation

/// Off unless HSTRACKER_LATENCY_PROBE=1 is set in the environment, so the
/// instrumented paths cost one atomic load in normal use. Set it in the Xcode
/// scheme's Run > Arguments > Environment Variables.
final class LatencyProbe {
    static let shared = LatencyProbe()

    static let enabled = ProcessInfo.processInfo.environment["HSTRACKER_LATENCY_PROBE"] == "1"

    /// Samples above this are dropped rather than skewing the percentiles. A log
    /// line older than this is not latency we caused - it is Hearthstone having
    /// written a batch it had been sitting on, the app having just started and
    /// replayed the existing log, or the HH:mm:ss timestamps having rolled over
    /// midnight (the log carries no date).
    private static let outlierCutoff: TimeInterval = 10.0

    private let lock = UnfairLock()

    private var flush = [Double]()      // A: log line timestamp -> we parsed it
    private var parsing = [Double]()    // B: processLine started -> update requested
    private var endToEnd = [Double]()   // A+B+ debounce + render, as the user experiences it

    private var droppedOutliers = 0
    private static let maxSamples = 4000

    /// The oldest log line whose refresh has not been committed yet.
    private var pendingLineClock: TimeInterval?
    private var processingLines = [ObjectIdentifier: UpdateRequest]()

    struct UpdateRequest {
        let processingStartClock: TimeInterval
        let lineClock: TimeInterval?
    }

    private static let dumpInterval: TimeInterval = 30.0

    private var dumpTimer: DispatchSourceTimer?

    private init() {
        guard LatencyProbe.enabled else { return }
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + LatencyProbe.dumpInterval,
                       repeating: LatencyProbe.dumpInterval)
        timer.setEventHandler { [weak self] in self?.dump() }
        timer.resume()
        dumpTimer = timer
        logger.info("[latency] probe enabled, reporting every \(Int(LatencyProbe.dumpInterval))s")
    }

    private static func now() -> TimeInterval { Date().timeIntervalSince1970 }

    private func record(_ bucket: inout [Double], _ value: TimeInterval) {
        if bucket.count >= LatencyProbe.maxSamples { bucket.removeFirst(bucket.count / 4) }
        bucket.append(value * 1000.0)
    }

    // MARK: - Stage hooks

    /// LogReaderManager, as each line starts processing. The line is parked
    /// under the parser thread until a refresh claims it.
    func logLineStarted(time: LogDate) {
        guard LatencyProbe.enabled else { return }
        let processingStartClock = LatencyProbe.now()
        let lineClock = time.date.timeIntervalSince1970 + Double(time.subseconds) / 10_000_000.0
        let age = processingStartClock - lineClock
        let thread = ObjectIdentifier(Thread.current)

        lock.lock()
        if age >= 0 && age <= LatencyProbe.outlierCutoff {
            record(&flush, age)
            processingLines[thread] = UpdateRequest(processingStartClock: processingStartClock, lineClock: lineClock)
        } else {
            droppedOutliers += 1
            processingLines[thread] = UpdateRequest(processingStartClock: processingStartClock, lineClock: nil)
        }
        lock.unlock()
    }

    /// Game.updateTrackers, where a parser flags that the UI is now stale. Runs
    /// on the caller's thread, which is how it finds the line it came from.
    /// The line is claimed once: a later request with no fresh line behind it
    /// produces no sample rather than being charged an old timestamp.
    func updateRequested() {
        guard LatencyProbe.enabled else { return }
        let t = LatencyProbe.now()
        let thread = ObjectIdentifier(Thread.current)
        lock.lock()
        let request = processingLines.removeValue(forKey: thread)
        if let request {
            record(&parsing, t - request.processingStartClock)
        }
        if pendingLineClock == nil {
            pendingLineClock = request?.lineClock
        }
        lock.unlock()
    }

    /// Main-thread marker queued after all tracker update blocks.
    func updateCommitted() {
        guard LatencyProbe.enabled else { return }
        let t = LatencyProbe.now()
        lock.lock()
        if let lineClock = pendingLineClock {
            let total = t - lineClock
            if total >= 0 && total <= LatencyProbe.outlierCutoff {
                record(&endToEnd, total)
            }
            pendingLineClock = nil
        }
        lock.unlock()
    }

    // MARK: - Reporting

    private func percentiles(_ samples: [Double]) -> String {
        guard !samples.isEmpty else { return "no samples" }
        let sorted = samples.sorted()
        func at(_ p: Double) -> Double {
            let idx = min(sorted.count - 1, max(0, Int(Double(sorted.count - 1) * p)))
            return sorted[idx]
        }
        return String(format: "n=%d p50=%.1f p95=%.1f p99=%.1f max=%.1f",
                      sorted.count, at(0.50), at(0.95), at(0.99), sorted[sorted.count - 1])
    }

    func dump() {
        guard LatencyProbe.enabled else { return }
        lock.lock()
        let f = percentiles(flush), p = percentiles(parsing), e = percentiles(endToEnd)
        let dropped = droppedOutliers
        lock.unlock()

        logger.info("[latency] all values in ms, dropped \(dropped) outliers (>\(Int(LatencyProbe.outlierCutoff))s)")
        logger.info("[latency] A log line -> parsed   \(f)   <- includes Hearthstone's own flush delay, the floor")
        logger.info("[latency] B parsing -> requested \(p)   <- parser and request queue")
        logger.info("[latency] E2E line -> UI         \(e)")
    }
}
