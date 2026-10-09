//
//  PerfLog.swift
//  HSTracker
//
//  Fork only: records CPU, memory and overlay cost once a second while a game
//  is in progress, one JSON Lines file per game under
//  ~/Library/Logs/HSTracker/perf/. On by default in Release so every game
//  played is a measurement; Debug numbers are dominated by Debug-only work and
//  stay off unless `perf_log` is set. Format: docs/perf-log.md.
//

import Foundation
import IOKit

final class PerfLog {
    static let shared = PerfLog()

    static let sampleInterval: TimeInterval = 1.0
    /// A game with no end logged (crash, Hearthstone killed) stops here.
    static let maxGameDuration: TimeInterval = 3 * 60 * 60
    /// Oldest files beyond this are deleted when a game starts.
    static let keepFiles = 100

    static var directory: URL {
        return Paths.logs.appendingPathComponent("perf", isDirectory: true)
    }

    private let queue = DispatchQueue(label: "net.hearthsim.hstracker.perflog", qos: .utility)

    // Confined to `queue`.
    private var timer: DispatchSourceTimer?
    private var handle: FileHandle?
    private var startClock: TimeInterval = 0
    private var lastCPUTime: TimeInterval = 0
    private var lastSampleClock: TimeInterval = 0
    private var gpuService: io_registry_entry_t = 0
    private var lagPending = false
    private var lastLagMs: Double?
    private var stats = GameStats()

    // Written on the main thread by the overlay, drained by `queue` each tick.
    private let refreshLock = UnfairLock()
    private var recording = false
    private var refreshCount = 0
    private var refreshTotalMs = 0.0
    private var refreshMaxMs = 0.0

    private struct GameStats {
        var samples = 0
        var cpu = [Double]()
        var footprintMaxMB = 0.0
        var footprintStartMB: Double?
        var refreshes = 0
        var refreshTotalMs = 0.0
        var refreshMaxMs = 0.0
        var lag = [Double]()
    }

    private init() {}

    private static func now() -> TimeInterval { ProcessInfo.processInfo.systemUptime }

    // MARK: - Game hooks (any thread)

    func gameStarted(mode: String, gameType: String, format: String) {
        guard Settings.perfLog else { return }
        queue.async {
            if self.handle != nil {
                self.finish(reason: "restarted", mode: nil)
            }
            self.begin(mode: mode, gameType: gameType, format: format)
        }
    }

    func gameEnded(mode: String) {
        queue.async {
            guard self.handle != nil else { return }
            self.finish(reason: "game_end", mode: mode)
        }
    }

    /// App quitting mid-game. Waits so the summary reaches disk.
    func appWillTerminate() {
        queue.sync {
            guard self.handle != nil else { return }
            self.finish(reason: "app_quit", mode: nil)
        }
    }

    // MARK: - Overlay hook (main thread)

    /// OverlayRefreshScheduler, once a refresh's main-thread work has drained:
    /// from asking for it to the last of its blocks having run.
    func overlayRefreshed(milliseconds: Double) {
        refreshLock.lock()
        if recording {
            refreshCount += 1
            refreshTotalMs += milliseconds
            refreshMaxMs = max(refreshMaxMs, milliseconds)
        }
        refreshLock.unlock()
    }

    // MARK: - Recording (on `queue`)

    private func begin(mode: String, gameType: String, format: String) {
        let fileManager = FileManager.default
        let dir = PerfLog.directory
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        pruneOldFiles(in: dir)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let url = dir.appendingPathComponent("perf-\(formatter.string(from: Date())).jsonl")
        guard fileManager.createFile(atPath: url.path, contents: nil),
              let handle = try? FileHandle(forWritingTo: url) else {
            logger.warning("[perf] could not create \(url.path)")
            return
        }
        self.handle = handle
        startClock = PerfLog.now()
        lastSampleClock = startClock
        lastCPUTime = PerfLog.processCPUTime()
        stats = GameStats()
        lastLagMs = nil
        lagPending = false
        gpuService = PerfLog.findGPUService()

        refreshLock.lock()
        recording = true
        refreshCount = 0
        refreshTotalMs = 0
        refreshMaxMs = 0
        refreshLock.unlock()

        #if DEBUG
        let build = "Debug"
        #else
        let build = "Release"
        #endif
        write([
            "event": "game_start",
            "time": PerfLog.isoNow(),
            "mode": mode,
            "game_type": gameType,
            "format": format,
            "build": build,
            "version": Version.buildName,
            "interval_s": PerfLog.sampleInterval
        ])

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + PerfLog.sampleInterval,
                       repeating: PerfLog.sampleInterval,
                       leeway: .milliseconds(100))
        timer.setEventHandler { [weak self] in self?.sample() }
        timer.resume()
        self.timer = timer
        logger.info("[perf] recording to \(url.lastPathComponent)")
    }

    private func sample() {
        guard handle != nil else { return }
        let clock = PerfLog.now()
        if clock - startClock > PerfLog.maxGameDuration {
            finish(reason: "timeout", mode: nil)
            return
        }

        let cpuTime = PerfLog.processCPUTime()
        let wall = clock - lastSampleClock
        let cpu = wall > 0 ? (cpuTime - lastCPUTime) / wall * 100.0 : 0
        lastCPUTime = cpuTime
        lastSampleClock = clock

        let footprintMB = PerfLog.memoryFootprintMB()

        refreshLock.lock()
        let refreshes = refreshCount, refreshMs = refreshTotalMs, refreshMax = refreshMaxMs
        refreshCount = 0
        refreshTotalMs = 0
        refreshMaxMs = 0
        refreshLock.unlock()

        var record: [String: Any] = [
            "event": "sample",
            "t": PerfLog.round(clock - startClock, 1),
            "cpu_pct": PerfLog.round(cpu, 1),
            "refreshes": refreshes,
            "refresh_ms": PerfLog.round(refreshMs, 2),
            "refresh_max_ms": PerfLog.round(refreshMax, 2)
        ]
        if let footprintMB {
            record["footprint_mb"] = PerfLog.round(footprintMB, 1)
        }
        // From the previous tick: the ping below answers after this line is written.
        if let lag = lastLagMs {
            record["main_lag_ms"] = PerfLog.round(lag, 2)
        }
        if let gpu = PerfLog.gpuUtilization(gpuService) {
            record["gpu_sys_pct"] = gpu
        }
        write(record)

        stats.samples += 1
        stats.cpu.append(cpu)
        if let footprintMB {
            stats.footprintMaxMB = max(stats.footprintMaxMB, footprintMB)
            if stats.footprintStartMB == nil { stats.footprintStartMB = footprintMB }
        }
        stats.refreshes += refreshes
        stats.refreshTotalMs += refreshMs
        stats.refreshMaxMs = max(stats.refreshMaxMs, refreshMax)
        if let lag = lastLagMs { stats.lag.append(lag) }

        pingMainThread()
    }

    /// How long a block waits for the main thread: what a hover or an overlay
    /// update would wait. One ping in flight at a time, so a stuck main thread
    /// does not pile them up.
    private func pingMainThread() {
        guard !lagPending else { return }
        lagPending = true
        let sent = PerfLog.now()
        DispatchQueue.main.async {
            let lag = (PerfLog.now() - sent) * 1000.0
            self.queue.async {
                self.lagPending = false
                if self.handle != nil {
                    self.lastLagMs = lag
                }
            }
        }
    }

    private func finish(reason: String, mode: String?) {
        timer?.cancel()
        timer = nil
        refreshLock.lock()
        recording = false
        refreshLock.unlock()
        if gpuService != 0 {
            IOObjectRelease(gpuService)
            gpuService = 0
        }

        var summary: [String: Any] = [
            "event": "game_end",
            "time": PerfLog.isoNow(),
            "reason": reason,
            "duration_s": PerfLog.round(PerfLog.now() - startClock, 1),
            "samples": stats.samples,
            "refreshes": stats.refreshes,
            "refresh_total_ms": PerfLog.round(stats.refreshTotalMs, 1),
            "refresh_max_ms": PerfLog.round(stats.refreshMaxMs, 2)
        ]
        if let mode { summary["mode"] = mode }
        if !stats.cpu.isEmpty {
            summary["cpu_avg_pct"] = PerfLog.round(stats.cpu.reduce(0, +) / Double(stats.cpu.count), 1)
            summary["cpu_p95_pct"] = PerfLog.round(PerfLog.percentile(stats.cpu, 0.95), 1)
            summary["cpu_max_pct"] = PerfLog.round(stats.cpu.max() ?? 0, 1)
        }
        if let start = stats.footprintStartMB {
            summary["footprint_start_mb"] = PerfLog.round(start, 1)
            summary["footprint_max_mb"] = PerfLog.round(stats.footprintMaxMB, 1)
        }
        if let end = PerfLog.memoryFootprintMB() {
            summary["footprint_end_mb"] = PerfLog.round(end, 1)
        }
        if !stats.lag.isEmpty {
            summary["main_lag_p95_ms"] = PerfLog.round(PerfLog.percentile(stats.lag, 0.95), 2)
            summary["main_lag_max_ms"] = PerfLog.round(stats.lag.max() ?? 0, 2)
        }
        write(summary)

        try? handle?.close()
        handle = nil
    }

    private func write(_ record: [String: Any]) {
        guard let handle,
              var data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) else { return }
        data.append(0x0A)
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            logger.warning("[perf] write failed: \(error)")
        }
    }

    private func pruneOldFiles(in dir: URL) {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        // Names carry the start time, so name order is age order.
        let logs = files.filter { $0.lastPathComponent.hasPrefix("perf-") && $0.pathExtension == "jsonl" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        // Leaves room for the file about to be created.
        let excess = logs.count - (PerfLog.keepFiles - 1)
        guard excess > 0 else { return }
        for url in logs.prefix(excess) {
            try? fileManager.removeItem(at: url)
        }
    }

    // MARK: - Probes

    /// User + system time of every thread in the process, live and exited.
    private static func processCPUTime() -> TimeInterval {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return 0 }
        func seconds(_ t: timeval) -> TimeInterval {
            return TimeInterval(t.tv_sec) + TimeInterval(t.tv_usec) / 1_000_000
        }
        return seconds(usage.ru_utime) + seconds(usage.ru_stime)
    }

    /// `phys_footprint`, the number Activity Monitor shows as Memory.
    private static func memoryFootprintMB() -> Double? {
        let count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let rev1Count = mach_msg_type_number_t(
            MemoryLayout.offset(of: \task_vm_info_data_t.min_address)! / MemoryLayout<integer_t>.size)
        var info = task_vm_info_data_t()
        var size = count
        let kr = withUnsafeMutablePointer(to: &info) { infoPtr in
            infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(size)) { intPtr in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), intPtr, &size)
            }
        }
        guard kr == KERN_SUCCESS, size >= rev1Count else { return nil }
        return Double(info.phys_footprint) / 1024 / 1024
    }

    /// The GPU's own busy figure. It is the whole machine's, Hearthstone
    /// included; macOS has no per-process GPU time an app can read for itself.
    private static func findGPUService() -> io_registry_entry_t {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"),
                                           &iterator) == KERN_SUCCESS else { return 0 }
        defer { IOObjectRelease(iterator) }
        var service = IOIteratorNext(iterator)
        while service != 0 {
            if gpuUtilization(service) != nil {
                return service
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return 0
    }

    private static func gpuUtilization(_ service: io_registry_entry_t) -> Int? {
        guard service != 0,
              let stats = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString,
                                                          kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any],
              let value = stats["Device Utilization %"] as? NSNumber else { return nil }
        return value.intValue
    }

    // MARK: - Helpers

    private static func percentile(_ values: [Double], _ p: Double) -> Double {
        let sorted = values.sorted()
        let index = min(sorted.count - 1, max(0, Int(Double(sorted.count - 1) * p)))
        return sorted[index]
    }

    private static func round(_ value: Double, _ places: Int) -> Double {
        let scale = pow(10.0, Double(places))
        return (value * scale).rounded() / scale
    }

    private static func isoNow() -> String {
        return ISO8601DateFormatter().string(from: Date())
    }
}
