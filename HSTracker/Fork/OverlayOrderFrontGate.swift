//
//  OverlayOrderFrontGate.swift
//  HSTracker
//
//  Fork only (Perf P1, dev 412fa5ee / 143db6f3): WindowManager.show runs on
//  every overlay refresh, and orderFront is a WindowServer transaction that
//  contends with Hearthstone's own compositing, so a routine refresh must not
//  issue one.
//

import AppKit

/// Only the events that can reshuffle the on-screen order raise the generation;
/// every window then gets exactly one orderFront on its next show(). Main
/// thread only, like WindowManager.show.
final class OverlayOrderFrontGate {
    static let reorderEvents = [Events.space_changed,
                                Events.hearthstone_active,
                                Events.hearthstone_deactived,
                                Events.hearthstone_running,
                                Events.hearthstone_closed]

    private var generation = 0
    private var orderedFront = [ObjectIdentifier: Int]()
    private var observers = [NSObjectProtocol]()

    init() {
        for event in OverlayOrderFrontGate.reorderEvents {
            let observer = NotificationCenter.default.addObserver(
                forName: NSNotification.Name(rawValue: event), object: nil,
                queue: OperationQueue.main) { [weak self] _ in
                    self?.generation += 1
            }
            observers.append(observer)
        }
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// `isOccluded` catches a window that ended up behind another one without
    /// any of our events firing; `attributesChanged` covers the level / style /
    /// frame writes that can move a window in the ordering by themselves.
    static func shouldOrderFront(isVisible: Bool, isOccluded: Bool,
                                 attributesChanged: Bool, pendingReorder: Bool) -> Bool {
        return !isVisible || isOccluded || attributesChanged || pendingReorder
    }

    func orderFrontIfNeeded(_ window: NSWindow, attributesChanged: Bool) {
        let id = ObjectIdentifier(window)
        if OverlayOrderFrontGate.shouldOrderFront(isVisible: window.isVisible,
                                                  isOccluded: !window.occlusionState.contains(.visible),
                                                  attributesChanged: attributesChanged,
                                                  pendingReorder: orderedFront[id] != generation) {
            window.orderFront(nil)
            orderedFront[id] = generation
        }
    }

    func orderOut(_ window: NSWindow) {
        if window.isVisible {
            window.orderOut(nil)
        }
        // A hidden window has to be re-fronted when it comes back.
        orderedFront.removeValue(forKey: ObjectIdentifier(window))
    }
}
