//
//  TrackerView.swift
//  HSTracker
//
//  Root view of the SwiftUI tracker: the three-row header plus every card
//  section, stacked top down under the (AppKit) hero bar. Replaces the frame
//  arithmetic Tracker.updateFrames() ran for these views.
//

import AppKit
import SwiftUI

struct TrackerView: View {
    @ObservedObject var viewModel: TrackerViewModel
    let topTitle: String
    let bottomTitle: String
    let relatedTitle: String
    let deckTitle: String
    let handTitle: String
    let playedTitle: String

    /// The panel hugs the window edge it is docked to, so when the rows narrow
    /// under compression the gap opens on the inner side, not against the
    /// screen edge.
    private var dockedEdge: Alignment {
        viewModel.playerType == .opponent ? .topLeading : .topTrailing
    }

    var body: some View {
        let layout = viewModel.layout
        VStack(spacing: 0) {
            if layout.headerHeight > 0 {
                TrackerHeaderView(viewModel: viewModel.header)
                    .frame(height: layout.headerHeight)
            }
            if layout.topHeight > 0 {
                TrackerSectionView(viewModel: viewModel.top, title: topTitle)
                    .frame(height: layout.topHeight)
            }
            // Zone mode feeds these three and empties `cards`; flat mode does the
            // reverse, so only one of the two shapes ever has a height.
            TrackerCardListView(viewModel: viewModel.cards)
                .frame(height: layout.listHeight)
            if layout.deckHeight > 0 {
                TrackerSectionView(viewModel: viewModel.deck, title: deckTitle)
                    .frame(height: layout.deckHeight)
            }
            if layout.handHeight > 0 {
                TrackerSectionView(viewModel: viewModel.hand, title: handTitle)
                    .frame(height: layout.handHeight)
                    // The only place that knows a section is the hand section;
                    // the rows read it back in `CardRowView.nameColor`.
                    .environment(\.trackerHandSection, true)
            }
            if layout.playedHeight > 0 {
                TrackerSectionView(viewModel: viewModel.played, title: playedTitle)
                    .frame(height: layout.playedHeight)
            }
            if layout.bottomHeight > 0 {
                TrackerSectionView(viewModel: viewModel.bottom, title: bottomTitle)
                    .frame(height: layout.bottomHeight)
            }
            if layout.relatedHeight > 0 {
                TrackerSectionView(viewModel: viewModel.related, title: relatedTitle)
                    .frame(height: layout.relatedHeight)
            }
        }
        .frame(width: layout.barWidth > 0 ? layout.barWidth : nil,
               alignment: .topLeading)
        // D2: one base under the whole panel, times the opacity setting. The
        // window itself is left clear on this path (Tracker.setOpacity).
        .background(TrackerBarStyle.base.opacity(layout.opacity))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: dockedEdge)
        .transaction { $0.animation = nil }
    }
}

/// The single content host of the tracker window. Created once; every refresh
/// goes through the view models, so the view tree is never rebuilt.
final class TrackerRootHost: NSView {
    let viewModel = TrackerViewModel()
    private let hostingView: TrackerTransparentHostingView<TrackerView>

    override var isOpaque: Bool { false }

    init(frame: NSRect, topTitle: String, bottomTitle: String, relatedTitle: String,
         deckTitle: String, handTitle: String, playedTitle: String) {
        hostingView = TrackerTransparentHostingView(
            rootView: TrackerView(viewModel: viewModel,
                                  topTitle: topTitle,
                                  bottomTitle: bottomTitle,
                                  relatedTitle: relatedTitle,
                                  deckTitle: deckTitle,
                                  handTitle: handTitle,
                                  playedTitle: playedTitle)
        )
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.isOpaque = false
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Perf P2 switch ④. `Tracker.setOpacity()` leaves the window clear on this
    /// path so the panel can paint its own base; this makes the whole window
    /// opaque instead, which is the only way to ask the window server to skip
    /// blending the overlay over the game. The area the panel does not cover
    /// goes flat dark — expected, it is a measurement mode. Applied here because
    /// `Tracker.swift` is outside this slice; a later `setOpacity()` (the user
    /// moving the opacity slider mid-session) puts the clear background back,
    /// so the switch is scoped to a restart.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard TrackerDiagnostics.forcesOpaquePanel, let window else {
            return
        }
        window.backgroundColor = TrackerBarStyle.baseNS
        window.isOpaque = true
    }
}
