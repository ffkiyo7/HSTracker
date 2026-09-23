//
//  TrackerCardListView.swift
//  HSTracker
//
//  One card list of the fork's tracker block: the main list, a zone section
//  or a top / bottom / related section. Stacked inside TrackerView.
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
                    if viewModel.hoverKind != .none {
                        TrackerCardRowHitArea(card: row.card,
                                              kind: viewModel.hoverKind,
                                              width: viewModel.barWidth,
                                              rowHeight: viewModel.rowHeight)
                    }
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

/// The row's hover, reported the way upstream's `CardTileListView` reports its
/// rows: the overlay canvas is click-through, so `RootOverlayWindow` sweeps the
/// cursor over these rects instead of the rows tracking the mouse themselves.
///
/// T8: the rect is the one thing that must not keep the row's full height while
/// the row collapses — a leaving row would otherwise sit on top of the one
/// sliding up under it and answer its hover. `RowCollapse` publishes its
/// progress through the environment and the rect shrinks with it. A row in
/// flight reports `.none`, which the sweep treats as "over no row": the hover it
/// had ends and none starts. A settled row reads the default 1 and covers the
/// whole row, as before.
private struct TrackerCardRowHitArea: View {
    let card: Card
    let kind: TrackerRowHoverKind
    let width: CGFloat
    let rowHeight: CGFloat

    @Environment(\.trackerRowMotion) private var motion

    var body: some View {
        let progress = max(0, min(1, motion))
        Color.clear
            .frame(width: width, height: rowHeight * progress, alignment: .top)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: TrackerRowHoverKey.self,
                        value: [TrackerRowHover(rect: proxy.frame(in: .rootOverlayCanvas),
                                                card: card,
                                                kind: progress >= 1 ? kind : .none)])
                }
            )
            .allowsHitTesting(false)
    }
}
