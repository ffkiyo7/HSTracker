//
//  LatencyProbe.swift
//  HSTracker
//
//  Measures how long it takes for a Hearthstone log line to show up in the
//  overlay, broken down by stage, so the pipeline can be optimised against
//  numbers instead of impressions.
//

import CoreFoundation
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
    private var tick = [Double]()       // C: update requested -> tick consumed it
    private var render = [Double]()     // D: update started -> main thread committed
    private var endToEnd = [Double]()   // A+B+C+D as the user experiences it

    enum RenderBlock: String, CaseIterable {
        case playerTracker = "player tracker"
        case opponentTracker = "opponent tracker"
        case cardHud = "card HUD"
        case turnTimer = "turn timer"
        case boardState = "board state"
        case secrets = "secrets"
        case battlegrounds = "battlegrounds"
        case bobsBuddy = "BobsBuddy"
        case turnCounter = "turn counter"
        case toaster = "toaster"
        case experience = "experience"
        case mercenariesTasks = "mercenaries tasks"
        case boardOverlay = "board overlay"
        case mulligan = "mulligan"
        case activeEffects = "active effects"
        case maxResources = "max resources"
        case rootOverlay = "root overlay"
        case counters = "counters"
        case playerCountersUpdate = "player counters update"
        case opponentCountersUpdate = "opponent counters update"
        case mulliganGuideScaling = "mulligan guide scaling"
        case mulliganPreLobbyScaling = "mulligan pre-lobby scaling"
    }

    enum MainQueueWork: String, CaseIterable {
        case battlegroundsTeammate = "gap: watcher teammate state"
        case discoverHighlight = "gap: watcher discover highlight"
        case battlegroundsState = "gap: watcher battlegrounds state"
        case choicesVisible = "gap: watcher choices visible"
        case deckPicker = "gap: watcher deck picker"
        case constructedQueue = "gap: watcher constructed queue"
        case tier7UserState = "gap: scene Tier7 user state"
    }

    private enum RunLoopPhase: String, CaseIterable {
        case sources = "gap: runloop source phase"
        case timers = "gap: runloop timer/observer phase"
        case waiting = "gap: runloop wait/outside"
        case transitions = "gap: runloop transitions"
        case unknown = "gap: unknown runloop phase"
    }

    struct RenderBlockToken {
        let block: RenderBlock
        let startClock: TimeInterval
        let generation: UInt
    }

    struct MainQueueWorkToken {
        let work: MainQueueWork
        let startClock: TimeInterval
        let generation: UInt
    }

    private var droppedOutliers = 0
    private static let maxSamples = 4000

    private var pendingLineClock: TimeInterval?
    private var pendingRequestClock: TimeInterval?
    private var updateLineClock: TimeInterval?
    private var updateStartClock: TimeInterval?
    private var processingLines = [ObjectIdentifier: UpdateRequest]()
    private var renderGeneration: UInt = 0
    private var firstRenderBlockClock: TimeInterval?
    private var currentRenderBlocks = [RenderBlock: TimeInterval]()
    private var renderBlocks = [RenderBlock: [Double]]()
    private var renderInitialWait = [Double]()
    private var renderUnattributed = [Double]()
    private var currentGapPhases = [RunLoopPhase: TimeInterval]()
    private var currentMainQueueWork = [MainQueueWork: TimeInterval]()
    private var renderGapPhases = [RunLoopPhase: [Double]]()
    private var renderMainQueueWork = [MainQueueWork: [Double]]()
    private var gapAccountingClock: TimeInterval?
    private var runLoopPhase = RunLoopPhase.unknown

    struct UpdateRequest {
        let processingStartClock: TimeInterval
        let lineClock: TimeInterval?
    }

    private static let dumpInterval: TimeInterval = 30.0

    private var dumpTimer: DispatchSourceTimer?
    private var runLoopObserver: CFRunLoopObserver?

    private init() {
        guard LatencyProbe.enabled else { return }
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + LatencyProbe.dumpInterval,
                       repeating: LatencyProbe.dumpInterval)
        timer.setEventHandler { [weak self] in self?.dump() }
        timer.resume()
        dumpTimer = timer
        DispatchQueue.main.async { [weak self] in
            self?.installRunLoopObserver()
        }
        logger.info("[latency] probe enabled, reporting every \(Int(LatencyProbe.dumpInterval))s")
    }

    private static func now() -> TimeInterval { Date().timeIntervalSince1970 }

    private func record(_ bucket: inout [Double], _ value: TimeInterval) {
        if bucket.count >= LatencyProbe.maxSamples { bucket.removeFirst(bucket.count / 4) }
        bucket.append(value * 1000.0)
    }

    private func record(_ block: RenderBlock, _ value: TimeInterval) {
        var bucket = renderBlocks[block] ?? []
        record(&bucket, value)
        renderBlocks[block] = bucket
    }

    private func accountGap(until clock: TimeInterval) {
        guard let started = gapAccountingClock else { return }
        currentGapPhases[runLoopPhase, default: 0] += max(0, clock - started)
        gapAccountingClock = clock
    }

    private func installRunLoopObserver() {
        let observer = CFRunLoopObserverCreateWithHandler(
            kCFAllocatorDefault,
            CFRunLoopActivity.allActivities.rawValue,
            true,
            0
        ) { [weak self] _, activity in
            self?.runLoopActivityChanged(activity)
        }
        runLoopObserver = observer
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    }

    private func runLoopActivityChanged(_ activity: CFRunLoopActivity) {
        let t = LatencyProbe.now()
        lock.lock()
        accountGap(until: t)
        switch activity {
        case .beforeTimers:
            runLoopPhase = .timers
        case .beforeSources:
            runLoopPhase = .sources
        case .beforeWaiting, .exit:
            runLoopPhase = .waiting
        case .entry, .afterWaiting:
            runLoopPhase = .transitions
        default:
            runLoopPhase = .unknown
        }
        lock.unlock()
    }

    // MARK: - Stage hooks

    /// LogReaderManager, as each line starts processing.
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

    func logLineFinished() {
        guard LatencyProbe.enabled else { return }
        lock.lock()
        processingLines.removeValue(forKey: ObjectIdentifier(Thread.current))
        lock.unlock()
    }

    /// Captures whether this request was made synchronously by a log parser.
    func captureUpdateRequest() -> UpdateRequest? {
        guard LatencyProbe.enabled else { return nil }
        lock.lock()
        let request = processingLines[ObjectIdentifier(Thread.current)]
        lock.unlock()
        return request
    }

    /// Game.updateTrackers, where a parser flags that the UI is now stale.
    func updateRequested(request: UpdateRequest?) {
        guard LatencyProbe.enabled else { return }
        let t = LatencyProbe.now()
        lock.lock()
        if let request {
            record(&parsing, t - request.processingStartClock)
        }
        if pendingRequestClock == nil {
            pendingRequestClock = t
        }
        if pendingLineClock == nil {
            pendingLineClock = request?.lineClock
        }
        lock.unlock()
    }

    /// Game.runGuiUpdate, where the scheduled update picks the flag up.
    func updateStarted() {
        guard LatencyProbe.enabled else { return }
        let t = LatencyProbe.now()
        lock.lock()
        if let requested = pendingRequestClock {
            record(&tick, t - requested)
            pendingRequestClock = nil
        }
        updateLineClock = pendingLineClock
        pendingLineClock = nil
        updateStartClock = t
        renderGeneration &+= 1
        firstRenderBlockClock = nil
        currentRenderBlocks.removeAll(keepingCapacity: true)
        currentGapPhases.removeAll(keepingCapacity: true)
        currentMainQueueWork.removeAll(keepingCapacity: true)
        gapAccountingClock = nil
        lock.unlock()
    }

    /// One of the main-queue blocks enqueued by Game.updateAllTrackers.
    func renderBlockStarted(_ block: RenderBlock) -> RenderBlockToken? {
        guard LatencyProbe.enabled else { return nil }
        let t = LatencyProbe.now()
        lock.lock()
        guard updateStartClock != nil else {
            lock.unlock()
            return nil
        }
        if firstRenderBlockClock == nil {
            firstRenderBlockClock = t
        } else {
            accountGap(until: t)
        }
        gapAccountingClock = nil
        let token = RenderBlockToken(block: block, startClock: t, generation: renderGeneration)
        lock.unlock()
        return token
    }

    func renderBlockFinished(_ token: RenderBlockToken?) {
        guard let token else { return }
        let t = LatencyProbe.now()
        lock.lock()
        if updateStartClock != nil && token.generation == renderGeneration {
            currentRenderBlocks[token.block, default: 0] += max(0, t - token.startClock)
            gapAccountingClock = t
        }
        lock.unlock()
    }

    /// App-owned work that can be interleaved with tracker refresh blocks on
    /// the main queue. These hooks do not change how or when the work is queued.
    func mainQueueWorkStarted(_ work: MainQueueWork) -> MainQueueWorkToken? {
        guard LatencyProbe.enabled else { return nil }
        let t = LatencyProbe.now()
        lock.lock()
        guard updateStartClock != nil, gapAccountingClock != nil else {
            lock.unlock()
            return nil
        }
        accountGap(until: t)
        gapAccountingClock = nil
        let token = MainQueueWorkToken(work: work, startClock: t, generation: renderGeneration)
        lock.unlock()
        return token
    }

    func mainQueueWorkFinished(_ token: MainQueueWorkToken?) {
        guard let token else { return }
        let t = LatencyProbe.now()
        lock.lock()
        if updateStartClock != nil && token.generation == renderGeneration {
            currentMainQueueWork[token.work, default: 0] += max(0, t - token.startClock)
            gapAccountingClock = t
        }
        lock.unlock()
    }

    /// Main-thread marker queued after all tracker update blocks.
    func updateCommitted() {
        guard LatencyProbe.enabled else { return }
        let t = LatencyProbe.now()
        lock.lock()
        if let started = updateStartClock {
            accountGap(until: t)
            let total = max(0, t - started)
            let initialWait = max(0, (firstRenderBlockClock ?? t) - started)
            let measuredBlocks = currentRenderBlocks.values.reduce(0, +)
            let unattributed = max(0, total - initialWait - measuredBlocks)
            record(&render, total)
            record(&renderInitialWait, initialWait)
            record(&renderUnattributed, unattributed)
            for block in RenderBlock.allCases {
                record(block, currentRenderBlocks[block] ?? 0)
            }
            for phase in RunLoopPhase.allCases {
                var bucket = renderGapPhases[phase] ?? []
                record(&bucket, currentGapPhases[phase] ?? 0)
                renderGapPhases[phase] = bucket
            }
            for work in MainQueueWork.allCases {
                var bucket = renderMainQueueWork[work] ?? []
                record(&bucket, currentMainQueueWork[work] ?? 0)
                renderMainQueueWork[work] = bucket
            }
            updateStartClock = nil
            firstRenderBlockClock = nil
            currentRenderBlocks.removeAll(keepingCapacity: true)
            currentGapPhases.removeAll(keepingCapacity: true)
            currentMainQueueWork.removeAll(keepingCapacity: true)
            gapAccountingClock = nil
        }
        if let lineClock = updateLineClock {
            let total = t - lineClock
            if total >= 0 && total <= LatencyProbe.outlierCutoff {
                record(&endToEnd, total)
            }
            updateLineClock = nil
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
        let f = percentiles(flush), p = percentiles(parsing), t = percentiles(tick)
        let r = percentiles(render), e = percentiles(endToEnd)
        let renderTotal = render.reduce(0, +)
        var renderComponents = RenderBlock.allCases.map { block in
            (block.rawValue, renderBlocks[block] ?? [])
        }
        renderComponents.append(("first main-queue wait", renderInitialWait))
        renderComponents.append(contentsOf: RunLoopPhase.allCases.map { phase in
            (phase.rawValue, renderGapPhases[phase] ?? [])
        })
        renderComponents.append(contentsOf: MainQueueWork.allCases.map { work in
            (work.rawValue, renderMainQueueWork[work] ?? [])
        })
        renderComponents.sort { $0.1.reduce(0, +) > $1.1.reduce(0, +) }
        let componentTotal = renderComponents.reduce(0) { $0 + $1.1.reduce(0, +) }
        let gapTotal = renderUnattributed.reduce(0, +)
        let gapComponentTotal = RunLoopPhase.allCases.reduce(0) {
            $0 + (renderGapPhases[$1] ?? []).reduce(0, +)
        } + MainQueueWork.allCases.reduce(0) {
            $0 + (renderMainQueueWork[$1] ?? []).reduce(0, +)
        }
        let dropped = droppedOutliers
        lock.unlock()

        logger.info("[latency] all values in ms, dropped \(dropped) outliers (>\(Int(LatencyProbe.outlierCutoff))s)")
        logger.info("[latency] A log line -> parsed   \(f)   <- includes Hearthstone's own flush delay, the floor")
        logger.info("[latency] B parsing -> requested \(p)   <- parser and request queue")
        logger.info("[latency] C requested -> tick    \(t)   <- debounce")
        logger.info("[latency] D tick -> UI committed \(r)   <- render cost")
        logger.info("[latency] E2E line -> UI         \(e)")
        let coverage = renderTotal > 0 ? componentTotal / renderTotal * 100.0 : 0
        logger.info(String(format: "[latency] D breakdown additive total=%.1f componentTotal=%.1f coverage=%.1f%%",
                           renderTotal, componentTotal, coverage))
        let gapCoverage = gapTotal > 0 ? gapComponentTotal / gapTotal * 100.0 : 0
        logger.info(String(format: "[latency] D gaps additive total=%.1f componentTotal=%.1f coverage=%.1f%%",
                           gapTotal, gapComponentTotal, gapCoverage))
        for (name, samples) in renderComponents where samples.contains(where: { $0 > 0 }) {
            let total = samples.reduce(0, +)
            let average = total / Double(samples.count)
            let share = renderTotal > 0 ? total / renderTotal * 100.0 : 0
            logger.info(String(format: "[latency] D part %-28@ %@ avg=%.1f total=%.1f share=%.1f%%",
                               name as NSString, percentiles(samples), average, total, share))
        }
    }
}
