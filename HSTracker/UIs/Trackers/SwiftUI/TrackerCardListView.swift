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
                    TrackerCardRowSensor(card: row.card, viewModel: viewModel)
                }
                .frame(maxWidth: .infinity,
                       minHeight: viewModel.rowHeight,
                       maxHeight: viewModel.rowHeight,
                       alignment: .topLeading)
                .clipped()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.clear)
        .transaction { $0.animation = nil }
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

/// Same NSTrackingArea options as CardBar, so hover works in the overlay
/// window without walking superviews to guess the section.
private struct TrackerCardRowSensor: NSViewRepresentable {
    let card: Card
    let viewModel: TrackerCardListViewModel

    func makeNSView(context: Context) -> Inner {
        let view = Inner()
        view.card = card
        view.viewModel = viewModel
        return view
    }

    func updateNSView(_ view: Inner, context: Context) {
        view.card = card
        view.viewModel = viewModel
    }

    final class Inner: NSView {
        var card: Card?
        weak var viewModel: TrackerCardListViewModel?

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
            if let card {
                viewModel?.onHover?(card, self)
            }
        }

        override func mouseExited(with event: NSEvent) {
            if let card {
                viewModel?.onExit?(card)
            }
        }
    }
}
