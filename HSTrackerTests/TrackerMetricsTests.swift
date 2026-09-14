//
//  TrackerMetricsTests.swift
//  HSTracker
//
//  Phase 2 / V1: the tracker panel is sized off the Hearthstone window and the
//  8.14 : 1 bar aspect is locked, compression included.
//

import XCTest

@testable import HSTracker

class TrackerMetricsTests: HSTrackerTests {

    private let accuracy: CGFloat = 0.01

    // MARK: - base size

    func testFirestoneTargetAt1920x1080() {
        let width = TrackerMetrics.panelWidth(windowWidth: 1920,
                                              windowHeight: 1080,
                                              cardSize: .big)
        XCTAssertEqual(width, 171, accuracy: 0.5)
        XCTAssertEqual(TrackerMetrics.rowHeight(panelWidth: width), 21, accuracy: 0.1)
    }

    func testScalesWithTheWindow() {
        for (w, h) in [(2560.0, 1440.0), (1280.0, 720.0), (3840.0, 2160.0)] {
            let width = TrackerMetrics.panelWidth(windowWidth: w, windowHeight: h, cardSize: .big)
            XCTAssertEqual(width / w, 0.089, accuracy: 0.001)
            XCTAssertEqual(TrackerMetrics.rowHeight(panelWidth: width) / h, 0.0194,
                           accuracy: 0.0005)
        }
    }

    /// An ultra-wide window must not get an 8.9%-of-width panel: the height
    /// rule takes over so the bars stay readable relative to the board.
    func testUltraWideFallsBackToTheHeightRule() {
        let width = TrackerMetrics.panelWidth(windowWidth: 3440,
                                              windowHeight: 1440,
                                              cardSize: .big)
        XCTAssertEqual(width, 1440 * 0.0194 * TrackerMetrics.aspect, accuracy: accuracy)
        XCTAssertLessThan(width, 3440 * 0.089)
    }

    // MARK: - presets

    func testPresetsAreOrderedAndDefaultIsTheFirestoneSize() {
        XCTAssertEqual(TrackerMetrics.multiplier(.big), 1.0, accuracy: accuracy)
        let ladder: [CardSize] = [.tiny, .small, .medium, .big, .huge]
        for (a, b) in zip(ladder, ladder.dropFirst()) {
            XCTAssertLessThan(TrackerMetrics.multiplier(a), TrackerMetrics.multiplier(b))
        }
        // The user's current preset has to come out a little under the default.
        XCTAssertLessThan(TrackerMetrics.multiplier(.small), TrackerMetrics.multiplier(.big))
    }

    func testPresetScalesWidthAndHeightTogether() {
        for size in [CardSize.tiny, .small, .medium, .big, .huge] {
            let width = TrackerMetrics.panelWidth(windowWidth: 1920,
                                                  windowHeight: 1080,
                                                  cardSize: size)
            let height = TrackerMetrics.rowHeight(panelWidth: width)
            XCTAssertEqual(width / height, TrackerMetrics.aspect, accuracy: accuracy)
        }
    }

    // MARK: - layout, including compression

    private func layout(cards: Int,
                        availableHeight: CGFloat,
                        panelWidth: CGFloat = 171) -> TrackerLayout {
        let viewModel = TrackerViewModel()
        let deck = (0..<cards).map { index -> Card in
            let card = Card()
            card.id = "c\(index)"
            card.count = 1
            return card
        }
        viewModel.update(cards: deck, top: [], bottom: [], relatedCards: [], groups: nil)
        viewModel.updateLayout(availableHeight: availableHeight,
                               panelWidth: panelWidth,
                               frameHeight: TrackerMetrics.headerLineHeight(
                                   rowHeight: TrackerMetrics.rowHeight(panelWidth: panelWidth)),
                               reserveGraveyardRow: false)
        return viewModel.layout
    }

    func testUncompressedRowsFillThePanelWidth() {
        let layout = layout(cards: 10, availableHeight: 900)
        XCTAssertEqual(layout.cardHeight, 21, accuracy: 0.1)
        XCTAssertEqual(layout.barWidth, 171, accuracy: 0.5)
    }

    /// PLAN 2.8 third cause: the row height was squeezed while the width stayed
    /// put, flattening the bars. Width now follows height.
    func testCompressionKeepsTheAspect() {
        let layout = layout(cards: 40, availableHeight: 500)
        XCTAssertLessThan(layout.cardHeight, 21)
        XCTAssertLessThan(layout.barWidth, 171)
        XCTAssertEqual(layout.barWidth / layout.cardHeight, TrackerMetrics.aspect,
                       accuracy: accuracy)
    }

    /// `Tracker.bottomY` is `availableHeight - contentHeight`; the rows have to
    /// end inside the window for that to stay non-negative.
    func testContentFitsTheAvailableHeight() {
        let available: CGFloat = 500
        let layout = layout(cards: 40, availableHeight: available)
        XCTAssertLessThanOrEqual(layout.contentHeight, available)
        XCTAssertGreaterThanOrEqual(available - layout.contentHeight, 0)
    }

    /// Zone mode: three section headers plus their bottom padding have to be
    /// inside the compression budget, or `bottomY` goes negative.
    func testZoneSectionsStayInsideTheWindowWhenCompressed() {
        let available: CGFloat = 400
        let panelWidth: CGFloat = 171
        let viewModel = TrackerViewModel()
        func cards(_ prefix: String, _ count: Int) -> [Card] {
            (0..<count).map { index in
                let card = Card()
                card.id = "\(prefix)\(index)"
                card.count = 1
                return card
            }
        }
        let groups = CardZoneGroups(deck: cards("d", 30),
                                    hand: cards("h", 10),
                                    played: cards("p", 20))
        viewModel.update(cards: [], top: [], bottom: [], relatedCards: [], groups: groups)
        viewModel.updateLayout(availableHeight: available,
                               panelWidth: panelWidth,
                               frameHeight: TrackerMetrics.headerLineHeight(
                                   rowHeight: TrackerMetrics.rowHeight(panelWidth: panelWidth)),
                               reserveGraveyardRow: false)
        let layout = viewModel.layout
        XCTAssertLessThan(layout.cardHeight, TrackerMetrics.rowHeight(panelWidth: panelWidth))
        XCTAssertEqual(layout.barWidth / layout.cardHeight, TrackerMetrics.aspect,
                       accuracy: accuracy)
        XCTAssertLessThanOrEqual(layout.contentHeight, available + accuracy)
    }

    func testEmptyListHasNoContent() {
        let layout = layout(cards: 0, availableHeight: 900)
        XCTAssertEqual(layout.contentHeight, 0, accuracy: accuracy)
    }
}
