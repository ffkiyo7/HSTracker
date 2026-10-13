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
    /// B: a section header's arrow was clicked. The panel that hosts the block
    /// toggles the section and lays itself out again.
    var onToggleSection: ((TrackerCardListViewModel) -> Void)?

    /// The panel hugs the edge it is docked to.
    private var dockedEdge: Alignment {
        viewModel.playerType == .opponent ? .topLeading : .topTrailing
    }

    var body: some View {
        let layout = viewModel.layout
        let scrolls = layout.maxScroll > 0
        VStack(spacing: 0) {
            if layout.headerHeight > 0 {
                TrackerHeaderView(viewModel: viewModel.header)
                    .frame(height: layout.headerHeight)
            }
            // A2: the header stays put and every card section scrolls together
            // in this clipped window. When everything fits the window is the
            // sections' own height and the offset is 0, i.e. the old stack.
            sections(layout)
                .offset(y: -viewModel.scrollOffset)
                .environment(\.trackerViewportHeight, scrolls ? layout.viewportHeight : nil)
                .frame(height: layout.viewportHeight, alignment: .top)
                .clipped()
                .overlay { TrackerViewportFade(layout: layout, offset: viewModel.scrollOffset) }
                .coordinateSpace(name: TrackerViewport.space)
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

    private func sections(_ layout: TrackerLayout) -> some View {
        VStack(spacing: 0) {
            if layout.topHeight > 0 {
                section(viewModel.top, title: topTitle)
                    .frame(height: layout.topHeight)
            }
            // Zone mode feeds these three and empties `cards`; flat mode does the
            // reverse, so only one of the two shapes ever has a height.
            TrackerCardListView(viewModel: viewModel.cards)
                .frame(height: layout.listHeight)
            if layout.deckHeight > 0 {
                section(viewModel.deck, title: deckTitle)
                    .frame(height: layout.deckHeight)
            }
            if layout.handHeight > 0 {
                section(viewModel.hand, title: handTitle)
                    .frame(height: layout.handHeight)
                    // The only place that knows a section is the hand section;
                    // the rows read it back in `CardRowView.nameColor`.
                    .environment(\.trackerHandSection, true)
            }
            if layout.playedHeight > 0 {
                section(viewModel.played, title: playedTitle)
                    .frame(height: layout.playedHeight)
            }
            if layout.bottomHeight > 0 {
                section(viewModel.bottom, title: bottomTitle)
                    .frame(height: layout.bottomHeight)
            }
            if layout.relatedHeight > 0 {
                section(viewModel.related, title: relatedTitle)
                    .frame(height: layout.relatedHeight)
            }
        }
    }

    private func section(_ list: TrackerCardListViewModel, title: String) -> TrackerSectionView {
        TrackerSectionView(viewModel: list, title: title,
                           onToggle: onToggleSection.map { toggle in { toggle(list) } })
    }
}

/// The scroll viewport's geometry, as the rows and section headers inside it
/// need it to clip what they report to the overlay window.
enum TrackerViewport {
    static let space = "trackerViewport"

    /// The part of `canvas` (a rect in the overlay canvas) that is inside the
    /// viewport. `local` is the same rect in the viewport's own space, which
    /// starts at its top edge and is in the panel's pre-scale units; the
    /// panel's `.scaleEffect` is the ratio between the two. `nil` when nothing
    /// is left. A block that does not scroll passes no height and keeps the
    /// whole rect, exactly as before the viewport existed.
    static func visible(canvas: CGRect, local: CGRect, viewportHeight: CGFloat?) -> CGRect? {
        guard let viewportHeight else { return canvas }
        let top = max(local.minY, 0)
        let bottom = min(local.maxY, viewportHeight)
        guard bottom - top > 0.5, local.height > 0 else { return nil }
        let scale = canvas.height / local.height
        return CGRect(x: canvas.minX,
                      y: canvas.minY + (top - local.minY) * scale,
                      width: canvas.width,
                      height: (bottom - top) * scale)
    }
}

/// A5: the viewport's edges fade into the panel base while there is more to
/// scroll to that way. A gradient of the base laid over the rows rather than a
/// mask, so it costs no offscreen pass; at `opacity` 0 it draws nothing.
private struct TrackerViewportFade: View {
    let layout: TrackerLayout
    let offset: CGFloat

    var body: some View {
        let base = TrackerBarStyle.base.opacity(layout.opacity)
        let clear = TrackerBarStyle.base.opacity(0)
        VStack(spacing: 0) {
            LinearGradient(colors: [base, clear], startPoint: .top, endPoint: .bottom)
                .frame(height: layout.cardHeight)
                .opacity(offset > 0.5 ? 1 : 0)
            Spacer(minLength: 0)
            LinearGradient(colors: [clear, base], startPoint: .top, endPoint: .bottom)
                .frame(height: layout.cardHeight)
                .opacity(offset < layout.maxScroll - 0.5 ? 1 : 0)
        }
        .allowsHitTesting(false)
    }
}

private struct TrackerViewportHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

/// Whether section headers may take a click: only on a locked overlay (B3,
/// default 2). Set by the panel that hosts the block.
private struct TrackerSectionsCollapsibleKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// The viewport's height while the block scrolls, `nil` otherwise.
    var trackerViewportHeight: CGFloat? {
        get { self[TrackerViewportHeightKey.self] }
        set { self[TrackerViewportHeightKey.self] = newValue }
    }

    var trackerSectionsCollapsible: Bool {
        get { self[TrackerSectionsCollapsibleKey.self] }
        set { self[TrackerSectionsCollapsibleKey.self] = newValue }
    }
}
