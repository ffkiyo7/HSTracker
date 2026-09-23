//
//  TrackerView.swift
//  HSTracker
//
//  The fork's block inside the upstream tracker panel: the three-row header
//  plus every card section, stacked top down. `TrackerZonePanelStack` places it
//  among the upstream sections it keeps (TrackerPanelZone.swift).
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

    /// The panel hugs the edge it is docked to, so when the rows narrow under
    /// compression the gap opens on the inner side, not against the screen
    /// edge.
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
        // D2: one base under the whole block, times the opacity setting.
        .background(TrackerBarStyle.base.opacity(layout.opacity))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: dockedEdge)
        // T8: the block's only animation. It is attached to the verdict rather
        // than taken at mutation time, so the section frames here and the rows
        // inside them animate on exactly the same updates — the ones
        // `TrackerViewModel` bumped. With the switch off (or the system's
        // "Reduce motion" on) the animation is nil *and* the verdict never
        // bumps, so the panel behaves frame for frame as it did before T8.
        .animation(TrackerMotion.isEnabled ? TrackerMotion.animation : nil,
                   value: viewModel.motionGeneration)
    }
}
