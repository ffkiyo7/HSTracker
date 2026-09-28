//
//  SessionRecapWindowController.swift
//  HSTracker
//
//  Plain window at the normal level: the recap has to survive Hearthstone
//  quitting, so it is not an overlay and `hideAllWhenGameInBackground` does not
//  reach it. It never disappears on its own.
//

import AppKit
import SwiftUI

final class SessionRecapWindowController: NSWindowController, NSWindowDelegate {
    private static var retained: SessionRecapWindowController?

    private var onClose: (() -> Void)?
    private var statistics: Statistics?

    /// Ends the running session and puts its recap on screen. Returns false when
    /// nothing was shown (setting off, no session, no constructed game), which
    /// is what tells `CoreManager` it may quit right away.
    @discardableResult
    static func showIfNeeded(onClose: @escaping () -> Void) -> Bool {
        assertMainThread()
        guard Settings.showConstructedSessionRecap else {
            return false
        }
        guard let summary = SessionRecap.endSession() else {
            return false
        }
        if let previous = retained {
            // A recap left open from the last session is replaced, and its own
            // close callback must not run — that one may quit the app.
            previous.onClose = nil
            retained = nil
            previous.window?.close()
        }
        let controller = SessionRecapWindowController(summary: summary, onClose: onClose)
        retained = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    private convenience init(summary: SessionRecapSummary, onClose: @escaping () -> Void) {
        let height = min(SessionRecapView.preferredHeight(for: summary),
                         (NSScreen.main?.visibleFrame.height ?? 900) * 0.8)
        let size = NSSize(width: SessionRecapStyle.width, height: height)
        let window = SessionRecapWindow(contentRect: NSRect(origin: .zero, size: size),
                                        styleMask: [.titled, .closable, .resizable],
                                        backing: .buffered,
                                        defer: false)
        self.init(window: window)
        self.onClose = onClose

        window.title = SessionRecapWindowController.title(for: summary)
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.backgroundColor = NSColor(red: 0x23 / 255, green: 0x27 / 255, blue: 0x2A / 255, alpha: 1)
        let hosting = NSHostingController(rootView: SessionRecapView(
            summary: summary,
            onOpenStatistics: { [weak self] deckId in self?.openStatistics(deckId: deckId) },
            onClose: { [weak self] in self?.window?.performClose(nil) }))
        // Without this the hosting controller propagates the whole table's
        // height as the window's preferred size and the 80% cap never holds.
        hosting.sizingOptions = []
        window.contentViewController = hosting
        window.setContentSize(size)
        window.center()
    }

    private static func title(for summary: SessionRecapSummary) -> String {
        let formatter = SessionRecapView.time
        return String.localizedString("session_recap_title", comment: "")
            + " · \(formatter.string(from: summary.start)) – \(formatter.string(from: summary.end))"
    }

    /// Reuses the deck manager's statistics window as a sheet on the recap: its
    /// Close button ends a sheet on its parent, so a standalone window would
    /// leave that button dead.
    private func openStatistics(deckId: String) {
        guard let window, statistics == nil, let deck = RealmHelper.getDeck(with: deckId) else {
            return
        }
        let controller = Statistics(windowNibName: "Statistics")
        controller.deck = deck
        guard let statisticsWindow = controller.window else {
            return
        }
        statistics = controller
        window.beginSheet(statisticsWindow) { [weak self] _ in
            self?.statistics = nil
        }
    }

    func windowWillClose(_ notification: Notification) {
        let onClose = self.onClose
        self.onClose = nil
        // Dropping the last reference from inside the notification would
        // deallocate the window that is sending it.
        DispatchQueue.main.async { [weak self] in
            if SessionRecapWindowController.retained === self {
                SessionRecapWindowController.retained = nil
            }
        }
        onClose?()
    }
}

private final class SessionRecapWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        performClose(sender)
    }
}
