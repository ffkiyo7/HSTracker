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

final class TrackerSectionHost: NSView {
    let viewModel = TrackerCardListViewModel()
    private let hostingView: TrackerTransparentHostingView<TrackerSectionView>

    var count: Int { viewModel.count }

    var cardHeight: CGFloat {
        get { viewModel.rowHeight }
        set {
            if viewModel.rowHeight != newValue {
                viewModel.rowHeight = newValue
            }
        }
    }

    var headerHeight: CGFloat {
        get { viewModel.sectionHeaderHeight }
        set {
            if viewModel.sectionHeaderHeight != newValue {
                viewModel.sectionHeaderHeight = newValue
            }
        }
    }

    var onHover: ((Card, NSView) -> Void)? {
        get { viewModel.onHover }
        set { viewModel.onHover = newValue }
    }

    var onExit: ((Card) -> Void)? {
        get { viewModel.onExit }
        set { viewModel.onExit = newValue }
    }

    override var isOpaque: Bool { false }

    init(frame: NSRect, title: String) {
        hostingView = TrackerTransparentHostingView(
            rootView: TrackerSectionView(viewModel: viewModel, title: title)
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
}
