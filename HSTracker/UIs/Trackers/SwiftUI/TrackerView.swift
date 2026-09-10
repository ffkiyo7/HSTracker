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
            TrackerCardListView(viewModel: viewModel.cards)
                .frame(height: layout.listHeight)
            if layout.bottomHeight > 0 {
                TrackerSectionView(viewModel: viewModel.bottom, title: bottomTitle)
                    .frame(height: layout.bottomHeight)
            }
            if layout.relatedHeight > 0 {
                TrackerSectionView(viewModel: viewModel.related, title: relatedTitle)
                    .frame(height: layout.relatedHeight)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.clear)
        .transaction { $0.animation = nil }
    }
}

/// The single content host of the tracker window. Created once; every refresh
/// goes through the view models, so the view tree is never rebuilt.
final class TrackerRootHost: NSView {
    let viewModel = TrackerViewModel()
    private let hostingView: TrackerTransparentHostingView<TrackerView>

    override var isOpaque: Bool { false }

    init(frame: NSRect, topTitle: String, bottomTitle: String, relatedTitle: String) {
        hostingView = TrackerTransparentHostingView(
            rootView: TrackerView(viewModel: viewModel,
                                  topTitle: topTitle,
                                  bottomTitle: bottomTitle,
                                  relatedTitle: relatedTitle)
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
