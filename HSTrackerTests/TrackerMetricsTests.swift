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
                               frameHeight: TrackerMetrics.sectionHeaderHeight(
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
                               frameHeight: TrackerMetrics.sectionHeaderHeight(
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

    // MARK: - V2a: header and section header on the row grid

    /// The 40 : 34 stretch the theme-PNG path gave both header kinds is gone: a
    /// header line is a card row, a section header the sheet's 22 : 21 notch.
    func testHeaderKindsSitOnTheCardRowGrid() {
        let rowHeight = TrackerMetrics.rowHeight(panelWidth: 171)
        XCTAssertEqual(rowHeight, 21, accuracy: 0.1)
        XCTAssertEqual(TrackerMetrics.sectionHeaderHeight(rowHeight: rowHeight), 22, accuracy: 0.1)
        XCTAssertLessThan(TrackerMetrics.sectionHeaderHeight(rowHeight: rowHeight),
                          rowHeight * 40 / 34)
    }

    func testSectionHeaderKeepsItsRatioToTheRow() {
        for panelWidth in [113.7, 171.0, 227.5] {
            let rowHeight = TrackerMetrics.rowHeight(panelWidth: panelWidth)
            XCTAssertEqual(TrackerMetrics.sectionHeaderHeight(rowHeight: rowHeight) / rowHeight,
                           22.0 / 21.0, accuracy: accuracy)
        }
    }

    /// The two count columns are fixed; what is left is the deck-name column.
    func testHeaderColumnsLeaveRoomForTheDeckName() {
        let fixed = TrackerBarStyle.headerMiddleColumn + TrackerBarStyle.headerTrailingColumn
        XCTAssertEqual(fixed, 86, accuracy: accuracy)
        // D2 asked for a name column of about 80 reference pixels; 171 - 86 = 85.
        XCTAssertGreaterThanOrEqual(TrackerMetrics.panelWidth - fixed, 80)
    }

    /// V1 left the header's columns frozen to the uncompressed row height, so a
    /// heavily compressed panel squeezed the deck name to nothing. The header
    /// now gets the compressed bar width.
    func testCompressedPanelNarrowsTheHeaderColumns() {
        let viewModel = TrackerViewModel()
        let deck = (0..<40).map { index -> Card in
            let card = Card()
            card.id = "c\(index)"
            card.count = 1
            return card
        }
        viewModel.update(cards: deck, top: [], bottom: [], relatedCards: [], groups: nil)
        let rowHeight = TrackerMetrics.rowHeight(panelWidth: 171)
        viewModel.updateLayout(availableHeight: 500,
                               panelWidth: 171,
                               frameHeight: TrackerMetrics.sectionHeaderHeight(rowHeight: rowHeight),
                               reserveGraveyardRow: false)
        XCTAssertLessThan(viewModel.layout.barWidth, 171)
        XCTAssertEqual(viewModel.header.barWidth, viewModel.layout.barWidth, accuracy: accuracy)
    }

    // MARK: - V2b: D3-b full-bleed art

    /// The art starts at the cost cell's trailing edge and runs to the end of
    /// the bar: 149 of the 171 reference pixels, at every panel size.
    func testArtStripSpansEverythingRightOfTheCostCell() {
        for panelWidth in [113.7, 170.6, 227.5] {
            let u = TrackerMetrics.rowHeight(panelWidth: panelWidth) / TrackerMetrics.rowHeight
            let cost = TrackerBarStyle.costWidth * u
            XCTAssertEqual(cost / u, 22, accuracy: accuracy)
            XCTAssertEqual((panelWidth - cost) / u, 149, accuracy: 0.5)
        }
    }

    /// `.D.fe75`: solid for the leading tenth of the strip, gone by 75%.
    func testD3bFadeStopsMatchTheSheet() {
        XCTAssertEqual(TrackerBarStyle.artSolidFraction, 0.10, accuracy: 0.0001)
        XCTAssertEqual(TrackerBarStyle.artClearFraction, 0.75, accuracy: 0.0001)
        // In bar coordinates: solid out to 36.9, fully clear at 133.75 of 171.
        XCTAssertEqual(22 + 149 * TrackerBarStyle.artSolidFraction, 36.9, accuracy: 0.05)
        XCTAssertEqual(22 + 149 * TrackerBarStyle.artClearFraction, 133.75, accuracy: 0.05)
    }

    /// The session recap window still wants the D2 strip. Its two numbers used
    /// to be derived from the card row's; D3-b moved the row, so they are now
    /// the recap's own and must not track it.
    func testSessionRecapFadeIsIndependentOfTheCardRow() {
        XCTAssertEqual(TrackerFade.opaqueFraction, 0.35, accuracy: accuracy)
        XCTAssertEqual(TrackerFade.startFraction, 1 - 100.0 / 171.0, accuracy: accuracy)
        XCTAssertNotEqual(TrackerFade.opaqueFraction, TrackerBarStyle.artSolidFraction)
    }

    /// The shade over the art is the panel base, so it has to dim with the
    /// panel instead of staying opaque over a translucent one.
    func testArtShadeCarriesThePanelOpacity() {
        XCTAssertEqual(CardRowView(card: Card()).baseOpacity,
                       TrackerMetrics.baseOpacity(setting: Settings.trackerOpacity),
                       accuracy: accuracy)
    }

    // MARK: - base opacity

    /// `tracker_opacity` defaults to 0, which on the theme-PNG path meant "no
    /// extra tint". Read literally it would erase the D2 base, so 0 paints it
    /// in full; explicit values still apply.
    func testDefaultOpacitySettingPaintsTheBaseInFull() {
        XCTAssertEqual(TrackerMetrics.baseOpacity(setting: 0), 1, accuracy: accuracy)
        XCTAssertEqual(TrackerMetrics.baseOpacity(setting: -5), 1, accuracy: accuracy)
        XCTAssertEqual(TrackerMetrics.baseOpacity(setting: 40), 0.4, accuracy: accuracy)
        XCTAssertEqual(TrackerMetrics.baseOpacity(setting: 100), 1, accuracy: accuracy)
        XCTAssertEqual(TrackerMetrics.baseOpacity(setting: 250), 1, accuracy: accuracy)
    }
}
