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
            .background(Color(red: 0x23 / 255,
                              green: 0x27 / 255,
                              blue: 0x2A / 255))
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

    var body: some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: 5) {
                Image(nsImage: Self.icon)
                    .resizable()
                    .frame(width: 17, height: 17)
                Text(title)
                    .font(.system(size: NSFont.systemFontSize))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity,
                           minHeight: 17,
                           maxHeight: 17,
                           alignment: .leading)
            }
            .padding(.horizontal, 5)
            .frame(maxWidth: .infinity,
                   minHeight: 17,
                   maxHeight: 17,
                   alignment: .leading)
            .offset(y: (height - 17) / 2)
        }
        .frame(maxWidth: .infinity,
               minHeight: height,
               maxHeight: height,
               alignment: .topLeading)
    }
}
