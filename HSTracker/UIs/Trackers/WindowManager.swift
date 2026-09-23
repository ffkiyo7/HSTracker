//
//  WindowManager.swift
//  HSTracker
//
//  Created by Benjamin Michotte on 20/10/16.
//  Copyright © 2016 Benjamin Michotte. All rights reserved.
//

import Foundation
import AppKit

class WindowManager {
	
	var hearthstoneActive = false
	
    // The two deck trackers, the secret helper and the link-opponent-deck panel
    // are RootOverlay children now - see RootOverlayViewModel's playerTracker /
    // opponentTracker / secretsPanel / linkOpponentDeck.

    private var _rootOverlay: Any?
    var rootOverlay: RootOverlayWindow? {
        if _rootOverlay == nil {
            _rootOverlay = RootOverlayWindow(windowNibName: "RootOverlayWindow")
        }
        return (_rootOverlay as? RootOverlayWindow)
    }

    var tooltipGridCards: RelatedCardsTooltipPanel {
        RelatedCardsTooltipPanel.shared
    }

    private var lastCardsUpdateRequest = Date.distantPast.timeIntervalSince1970

    private let orderFrontGate = OverlayOrderFrontGate()

	private func setHearthstoneActive() { hearthstoneActive = true }
	private func setHearthstoneBackground() { hearthstoneActive = false }

    func hideGameTrackers() {
		// TODO: use not defered gui instead
        DispatchQueue.main.async { [weak self] in
            self?.rootOverlay?.viewModel.secretsPanel.isShown = false
            self?.rootOverlay?.viewModel.opponentHandMarkers.hide()
            self?.rootOverlay?.viewModel.boardOverlay.isShown = false
            self?.rootOverlay?.viewModel.flavorText.hide()
            self?.tooltipGridCards.hide()
            RelatedCardsBrowserPanel.shared.hide()
        }
    }

    /// Takes down whatever the cursor last raised over a tracker row: the card
    /// render and the related-cards grid beside it. Called when a game ends, which
    /// can happen with the cursor still sitting on a row.
    func forceHideCardHover() {
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            CardTooltipPanel.shared.hide()
            self.tooltipGridCards.hide()
        }
    }

    // MARK: - Utility functions
    @MainActor
    func show(controller: OverWindowController, show: Bool,
              frame: NSRect? = nil, title: String? = nil, overlay: Bool = true) {
        // `controller.window` loads the nib on first access, so the hop has to
        // happen before it is touched, not after.
        if !Thread.isMainThread {
            DispatchQueue.main.async {
                self.show(controller: controller, show: show, frame: frame, title: title, overlay: overlay)
            }
            return
        }

        guard let window = controller.window else { return }
        
        if show {
            // add the window in the "windows menu"
            if let title = title {
                NSApp.addWindowsItem(window,
                                     title: String.localizedString(title, comment: ""),
                                     filename: false)
                window.title = String.localizedString(title, comment: "")
            }

            // update gui elements
            controller.updateFrames()

            // Runs on every refresh: each write below is skipped when it would
            // change nothing, and only one that did change something earns an
            // orderFront (OverlayOrderFrontGate).
            var attributesChanged = false

            // show window and set size
            if let frame = frame {
                if frame.origin.x.isFinite && frame.origin.y.isFinite && frame.size.width.isFinite && frame.size.height.isFinite
                    && window.frame != frame {
                    window.setFrame(frame, display: true, animate: false)
                    attributesChanged = true
                }
            }

            // Place overlays just above Hearthstone (normal level) but below
            // any system UI level so macOS Notification Center, menu bar, and
            // status items can render above them.
            let level: Int
            if overlay {
                level = Int(CGWindowLevelForKey(CGWindowLevelKey.normalWindow)) + 1
            } else {
                level = Int(CGWindowLevelForKey(CGWindowLevelKey.normalWindow))
            }
            let windowLevel = NSWindow.Level(rawValue: level)
            if window.level != windowLevel {
                window.level = windowLevel
                attributesChanged = true
            }

            // if the setting is on, set the window behavior to join all workspaces
            let collectionBehavior: NSWindow.CollectionBehavior
            if Settings.canJoinFullscreen {
                collectionBehavior = [NSWindow.CollectionBehavior.canJoinAllSpaces, NSWindow.CollectionBehavior.fullScreenAuxiliary]
            } else {
                collectionBehavior = []
            }
            if window.collectionBehavior != collectionBehavior {
                window.collectionBehavior = collectionBehavior
                attributesChanged = true
            }

            // A styleMask write rebuilds the window frame with a synchronous
            // WindowServer round trip, even when the value is the same.
            let locked = Settings.windowsLocked || controller.alwaysLocked
            let styleMask: NSWindow.StyleMask
            if locked {
                styleMask = [.borderless, .nonactivatingPanel]
            } else {
                styleMask = [.titled, .miniaturizable,
                             .resizable, .borderless,
                             .nonactivatingPanel]
            }
            if window.styleMask != styleMask {
                window.styleMask = styleMask
                attributesChanged = true
            }

            orderFrontGate.orderFrontIfNeeded(window, attributesChanged: attributesChanged)
        } else {
            if title != nil {
                NSApp.removeWindowsItem(window)
            }
            orderFrontGate.orderOut(window)
        }
    }
}

