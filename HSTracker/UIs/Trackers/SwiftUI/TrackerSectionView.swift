//
//  TrackerSectionView.swift
//  HSTracker
//
//  SwiftUI stand-in for DeckLens on Tracker's three headed card sections.
//

import AppKit
import SwiftUI

struct TrackerSectionView: View {
    @ObservedObject var viewModel: TrackerCardListViewModel
    let title: String

    /// Copies, not rows: the sheet's "(12)" counts the same way a card row's
    /// count box does, so a two-of contributes 2. The played section carries
    /// negative counts, hence the absolute value.
    private var copies: Int {
        viewModel.rows.reduce(0) { $0 + abs($1.card.count) }
    }

    var body: some View {
        if viewModel.rows.isEmpty {
            Color.clear
                .frame(width: 0, height: 0)
        } else {
            VStack(spacing: 0) {
                TrackerSectionHeaderView(title: title,
                                         copies: copies,
                                         height: viewModel.sectionHeaderHeight)
                TrackerCardListView(viewModel: viewModel)
                Color.clear.frame(height: 5)
            }
            .frame(maxWidth: .infinity,
                   maxHeight: .infinity,
                   alignment: .topLeading)
            // No background of its own: D2 gives the whole panel one base,
            // painted once in TrackerView.
            .transaction { $0.animation = nil }
        }
    }
}

/// `.sec` of the D3 sheet: a gold rule on top, the section name centred in the
/// theme face with the copy count in Belwe beside it, and a collapse chevron in
/// a square column on the trailing edge. The chevron is drawn only — the
/// collapse gesture is a later slice.
private struct TrackerSectionHeaderView: View {
    let title: String
    let copies: Int
    let height: CGFloat

    /// One reference pixel: the section header is 22 of them tall.
    private var u: CGFloat { height / TrackerBarStyle.sectionRowHeight }
    private var side: CGFloat { TrackerBarStyle.sectionSideColumn * u }
    private var chevron: CGFloat { TrackerBarStyle.chevron * u }

    var body: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: side)
            HStack(spacing: TrackerBarStyle.sectionCountGap * u) {
                Text(title)
                    .font(TrackerBarStyle.label(u, size: TrackerBarStyle.sectionFontSize))
                    .tracking(TrackerBarStyle.sectionTracking * TrackerBarStyle.sectionFontSize * u)
                    .foregroundColor(TrackerBarStyle.gold)
                Text("(\(copies))")
                    .font(TrackerBarStyle.digits(u, size: TrackerBarStyle.sectionFontSize))
                    .foregroundColor(TrackerBarStyle.text)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            TrackerChevron()
                .stroke(TrackerBarStyle.gold,
                        style: StrokeStyle(lineWidth: max(TrackerBarStyle.chevronStroke * u, 1)))
                .frame(width: chevron, height: chevron)
                .rotationEffect(.degrees(45))
                .offset(y: -chevron / 4)
                .opacity(TrackerBarStyle.chevronOpacity)
                .frame(width: side)
        }
        .frame(maxWidth: .infinity,
               minHeight: height,
               maxHeight: height)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(TrackerBarStyle.line)
                .frame(height: max(TrackerBarStyle.hairline * u, 0.5))
        }
    }
}
