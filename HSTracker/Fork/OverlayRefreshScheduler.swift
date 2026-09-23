//
//  OverlayRefreshScheduler.swift
//  HSTracker
//
//  Fork only (dev 7617b8ad): upstream polls `guiNeedsUpdate` every 500ms, so
//  every overlay reaction to the log waited up to half a second. This runs one
//  coalesced refresh shortly after it is asked for instead.
//

import Foundation

final class OverlayRefreshScheduler {
    /// A frame and a bit: smaller lets bursty logs through one line at a time,
    /// larger gives back what the poll was costing.
    static let debounce: TimeInterval = 0.016

    private let queue = DispatchQueue(label: "net.hearthsim.hstracker.guiupdate", attributes: [])

    // Confined to `queue`.
    private var needsUpdate = false
    private var resets = false
    private var scheduled = false
    private var inFlight = false

    /// Runs on `queue` and must only enqueue its work on the main queue. Set
    /// once, before the first request.
    var refresh: ((_ reset: Bool) -> Void)?

    /// Any thread. Requests inside the window only set the flag.
    func request(reset: Bool = false) {
        queue.async {
            self.needsUpdate = true
            self.resets = self.resets || reset
            self.schedule()
        }
    }

    /// Not a trailing-edge debounce: resetting the timer on every request would
    /// starve the overlay while the log is busy, since the requests never stop.
    private func schedule() {
        guard !scheduled, !inFlight else { return }
        scheduled = true
        queue.asyncAfter(deadline: .now() + OverlayRefreshScheduler.debounce) {
            self.run()
        }
    }

    private func run() {
        scheduled = false
        guard needsUpdate else { return }
        needsUpdate = false
        let reset = resets
        resets = false
        inFlight = true
        refresh?(reset)
        // `refresh` only enqueues its blocks on the main queue, which is FIFO, and
        // some of them enqueue one more level while they run: the second marker
        // lands behind those, once the refresh is really done. Holding the next
        // refresh until then keeps a 16ms window from piling refreshes onto a
        // main thread that has not finished the last one.
        DispatchQueue.main.async {
            DispatchQueue.main.async {
                LatencyProbe.shared.updateCommitted()
                self.queue.async {
                    self.inFlight = false
                    if self.needsUpdate {
                        self.schedule()
                    }
                }
            }
        }
    }
}
