//
//  TrackerCardListView.swift
//  HSTracker
//
//  SwiftUI stand-in for AnimatedCardList on Tracker's main card table.
//  Stacked inside TrackerView; the xib outlet is left untouched for the
//  useSwiftUITracker == false path.
//

import AppKit
import SwiftUI

struct TrackerCardListView: View {
    @ObservedObject var viewModel: TrackerCardListViewModel

    var body: some View {
        VStack(spacing: 0) {
            ForEach(viewModel.rows) { row in
                ZStack(alignment: .topLeading) {
                    // `.equatable()` is load bearing, not an optimisation: the
                    // comparison SwiftUI makes on its own reads `Card`'s `==`,
                    // which is the id alone, so a row whose count changed looked
                    // unchanged and kept its old bitmap (bug T10).
                    CardRowView(
                        card: row.card,
                        playerType: viewModel.playerType,
                        showRarityColors: viewModel.showRarityColors,
                        rowHeight: viewModel.rowHeight,
                        barWidth: viewModel.barWidth,
                        highlightColor: row.highlight,
                        baseOpacity: viewModel.baseOpacity,
                        flattensToBitmap: viewModel.flattensRows,
                        drawsArt: viewModel.drawsArt,
                        drawsTextShadow: viewModel.drawsTextShadow
                    )
                    .equatable()
                    // T8: the draw flash. A sibling of the row bitmap, never
                    // part of it, so it cannot enter `CardRowRasterKey`; the
                    // row under it already reads the new count.
                    if let generation = viewModel.flashing[row.id] {
                        TrackerRowFlash(width: viewModel.barWidth,
                                        height: viewModel.rowHeight)
                            .id(generation)
                            .transition(.identity)
                    }
                }
                .frame(maxWidth: .infinity,
                       minHeight: viewModel.rowHeight,
                       maxHeight: viewModel.rowHeight,
                       alignment: .topLeading)
                .clipped()
                // Outside the clip, so its own height is the row's animated
                // one rather than the full row (see TrackerCardRowHitArea).
                .overlay(alignment: .topLeading) {
                    TrackerCardRowHitArea(card: row.card,
                                          viewModel: viewModel,
                                          rowHeight: viewModel.rowHeight)
                }
                .transition(TrackerMotion.rowTransition(rowHeight: viewModel.rowHeight))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.clear)
        // A section's frame follows the rows one frame later at worst, so the
        // list may not paint outside it while a row is collapsing.
        .clipped()
        // Same verdict as the panel's (`TrackerViewModel` bumps both in one
        // block); stated here as well so a list hosted on its own still moves.
        .animation(TrackerMotion.isEnabled ? TrackerMotion.animation : nil,
                   value: viewModel.motionGeneration)
    }
}

final class TrackerTransparentHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }

    required init(rootView: Content) {
        super.init(rootView: rootView)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.isOpaque = false
        safeAreaRegions = []
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.isOpaque = false
    }
}

/// T8: the hit area is the one thing that must not keep the row's full height
/// while the row collapses — a leaving row would otherwise sit on top of the
/// one sliding up under it and answer its hover. `RowCollapse` publishes its
/// progress through the environment and the sensor shrinks with it; a settled
/// row reads the default 1 and covers the whole row, as before.
private struct TrackerCardRowHitArea: View {
    let card: Card
    let viewModel: TrackerCardListViewModel
    let rowHeight: CGFloat

    @Environment(\.trackerRowMotion) private var motion

    var body: some View {
        TrackerCardRowSensor(card: card, viewModel: viewModel, isSettled: motion >= 1)
            .frame(height: rowHeight * max(0, min(1, motion)), alignment: .top)
    }
}

/// Same NSTrackingArea options as CardBar, so hover works in the overlay
/// window without walking superviews to guess the section.
private struct TrackerCardRowSensor: NSViewRepresentable {
    let card: Card
    let viewModel: TrackerCardListViewModel
    var isSettled: Bool = true

    func makeNSView(context: Context) -> Inner {
        let view = Inner()
        view.card = card
        view.viewModel = viewModel
        view.isSettled = isSettled
        return view
    }

    func updateNSView(_ view: Inner, context: Context) {
        view.card = card
        view.viewModel = viewModel
        view.isSettled = isSettled
    }

    /// A row can also vanish without an animation (the instant path, a deck
    /// swap, the end of a game). Whoever was hovering it has to be told, or
    /// the tooltip keeps pointing at a card that is no longer on the panel.
    static func dismantleNSView(_ view: Inner, coordinator: ()) {
        view.endHover()
    }

    final class Inner: NSView {
        var card: Card?
        weak var viewModel: TrackerCardListViewModel?
        var isSettled = true {
            didSet {
                if !isSettled {
                    endHover()
                }
            }
        }

        private var isHovering = false

        func endHover() {
            guard isHovering, let card else { return }
            isHovering = false
            viewModel?.onExit?(card)
        }

        private lazy var trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.inVisibleRect, .activeAlways, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )

        override var isOpaque: Bool { false }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if !trackingAreas.contains(trackingArea) {
                addTrackingArea(trackingArea)
            }
        }

        override func mouseEntered(with event: NSEvent) {
            guard isSettled, let card else { return }
            isHovering = true
            viewModel?.onHover?(card, self)
        }

        override func mouseExited(with event: NSEvent) {
            guard let card else { return }
            isHovering = false
            viewModel?.onExit?(card)
        }
    }
}
