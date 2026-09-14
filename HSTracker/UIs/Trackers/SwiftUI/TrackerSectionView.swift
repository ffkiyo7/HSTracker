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

    var body: some View {
        if viewModel.rows.isEmpty {
            Color.clear
                .frame(width: 0, height: 0)
        } else {
            VStack(spacing: 0) {
                TrackerSectionHeaderView(title: title,
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

private struct TrackerSectionHeaderView: View {
    let title: String
    let height: CGFloat

    private static let icon: NSImage = {
#if HSTTEST
        return NSImage(systemSymbolName: "magnifyingglass",
                       accessibilityDescription: nil)!
#else
        return NSImage(named: "icon_magnifying_glass",
                       size: NSSize(width: 17, height: 17))!
#endif
    }()

    /// T4 drew this at a flat 17pt inside a 40pt row; rows are shorter now, so
    /// it is clamped to the row instead. Restyling the section headers is V2.
    private var content: CGFloat { min(17, max(height - 6, 1)) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: 5) {
                Image(nsImage: Self.icon)
                    .resizable()
                    .frame(width: content, height: content)
                Text(title)
                    .font(.system(size: NSFont.systemFontSize * content / 17))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity,
                           minHeight: content,
                           maxHeight: content,
                           alignment: .leading)
            }
            .padding(.horizontal, 5)
            .frame(maxWidth: .infinity,
                   minHeight: content,
                   maxHeight: content,
                   alignment: .leading)
            .offset(y: (height - content) / 2)
        }
        .frame(maxWidth: .infinity,
               minHeight: height,
               maxHeight: height,
               alignment: .topLeading)
    }
}
