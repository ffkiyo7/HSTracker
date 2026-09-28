//
//  TrackerMetricsTests.swift
//  HSTracker
//
//  Phase 2 / V1: the tracker panel is sized off the Hearthstone window and the
//  8.14 : 1 bar aspect is locked, compression included.
//

import XCTest
import AppKit
import Combine
import SwiftUI

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

    // MARK: - Perf P1 / 1: orderFront is not part of a routine refresh

    /// The refresh path runs every 16ms; nothing moved means no WindowServer
    /// transaction.
    func testRoutineRefreshDoesNotReorderTheWindow() {
        XCTAssertFalse(OverlayOrderFrontGate.shouldOrderFront(isVisible: true, isOccluded: false,
                                                              attributesChanged: false,
                                                              pendingReorder: false))
    }

    /// The four reasons that still have to re-front the window: it is hidden,
    /// something is covering it, one of its attributes was just rewritten, or a
    /// Space / Hearthstone event raised the reorder generation.
    func testEveryReorderReasonStillOrdersTheWindowFront() {
        XCTAssertTrue(OverlayOrderFrontGate.shouldOrderFront(isVisible: false, isOccluded: false,
                                                             attributesChanged: false, pendingReorder: false))
        XCTAssertTrue(OverlayOrderFrontGate.shouldOrderFront(isVisible: true, isOccluded: true,
                                                             attributesChanged: false, pendingReorder: false))
        XCTAssertTrue(OverlayOrderFrontGate.shouldOrderFront(isVisible: true, isOccluded: false,
                                                             attributesChanged: true, pendingReorder: false))
        XCTAssertTrue(OverlayOrderFrontGate.shouldOrderFront(isVisible: true, isOccluded: false,
                                                             attributesChanged: false, pendingReorder: true))
    }

    func testSpaceAndHearthstoneEventsAreReorderReasons() {
        for event in [Events.space_changed, Events.hearthstone_active, Events.hearthstone_deactived,
                      Events.hearthstone_running, Events.hearthstone_closed] {
            XCTAssertTrue(OverlayOrderFrontGate.reorderEvents.contains(event),
                          "\(event) has to force the overlays back to the front")
        }
    }

    // MARK: - Perf P1 / 4: same-value playerType

    /// `playerType` never changes after the tracker is built, but the assignment
    /// used to publish through all seven lists on every refresh.
    func testSamePlayerTypeDoesNotNotifyTheLists() {
        let viewModel = TrackerViewModel()
        viewModel.playerType = .opponent

        var notifications = 0
        var tokens = [AnyCancellable]()
        for list in [viewModel.cards, viewModel.deck, viewModel.hand, viewModel.played,
                     viewModel.top, viewModel.bottom, viewModel.related] {
            tokens.append(list.objectWillChange.sink { _ in notifications += 1 })
        }
        XCTAssertEqual(tokens.count, 7)

        viewModel.playerType = .opponent
        XCTAssertEqual(notifications, 0, "a refresh that changes nothing must not publish")

        viewModel.playerType = .player
        XCTAssertEqual(notifications, 7, "a real change still reaches every list")
    }

    // MARK: - Perf P2: what the render server has to composite

    /// Proxy metric only. It counts the CALayer tree the panel hands to the
    /// window server, **not** Hearthstone's frame time: shadows, group opacity
    /// and masks are the layers that cost an offscreen pass, so their number is
    /// the thing this slice is allowed to claim it moved.
    struct LayerCensus {
        var total = 0
        var shadowed = 0
        var groupOpacity = 0
        /// A real mask layer: always an offscreen pass.
        var masked = 0
        /// `masksToBounds`, i.e. a rectangular clip. Counted apart because the
        /// compositor can usually do it with a scissor rather than a pass.
        var clipping = 0

        var description: String {
            "total \(total), shadowed \(shadowed), groupOpacity \(groupOpacity), "
                + "masked \(masked), clipping \(clipping)"
        }

        /// The three that cost the render server an extra pass.
        var offscreen: Int { shadowed + groupOpacity + masked }
    }

    private func census(of layer: CALayer, into result: inout LayerCensus) {
        result.total += 1
        if layer.shadowOpacity > 0 {
            result.shadowed += 1
        }
        let sublayers = layer.sublayers ?? []
        if layer.opacity < 1 && !sublayers.isEmpty {
            result.groupOpacity += 1
        }
        if layer.mask != nil && !sublayers.isEmpty {
            result.masked += 1
        }
        if layer.masksToBounds && !sublayers.isEmpty {
            result.clipping += 1
        }
        for sublayer in sublayers {
            census(of: sublayer, into: &result)
        }
    }

    private func rowCards(_ count: Int) -> [Card] {
        (0..<count).map { index in
            let card = Card()
            card.id = "PERF_\(index)"
            card.name = "Prosecutor Mel'tranix \(index)"
            card.cost = index % 10
            card.count = index % 3 == 0 ? 2 : 1
            card.rarity = [Rarity.common, .rare, .epic, .legendary][index % 4]
            return card
        }
    }

    /// Runs `body` with a diagnostic key forced, then puts back whatever the
    /// user's own domain held — including nothing, and including a value they
    /// set by hand for a bisection run.
    private func withDefault<T>(_ key: String, _ value: Bool, _ body: () -> T) -> T {
        let previous = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.set(value, forKey: key)
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        return body()
    }

    private func withFlattening<T>(_ flattens: Bool, _ body: () -> T) -> T {
        withDefault(Settings.tracker_perf_flatten_rows, flattens, body)
    }

    private func census<V: View>(of rootView: V, size: NSSize) -> LayerCensus {
        let host = NSHostingView(rootView: rootView)
        host.frame = NSRect(origin: .zero, size: size)
        host.wantsLayer = true
        let window = NSWindow(contentRect: host.frame,
                              styleMask: [.borderless],
                              backing: .buffered,
                              defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()

        var result = LayerCensus()
        if let layer = host.layer {
            census(of: layer, into: &result)
        }
        window.contentView = nil
        return result
    }

    /// Renders 30 rows into a hosting view and counts the layer tree behind it.
    private func listCensus(rows: Int,
                            rowHeight: CGFloat = 21,
                            barWidth: CGFloat = 171) -> LayerCensus {
        let viewModel = TrackerCardListViewModel()
        viewModel.rowHeight = rowHeight
        viewModel.barWidth = barWidth
        viewModel.update(cards: rowCards(rows))
        return census(of: TrackerCardListView(viewModel: viewModel),
                      size: NSSize(width: barWidth, height: rowHeight * CGFloat(rows)))
    }

    /// The whole panel in zone mode, which is what the user actually runs:
    /// a one-line header, three section headers and 38 rows.
    private func panelCensus(rowHeight: CGFloat = 21,
                             barWidth: CGFloat = 171) -> LayerCensus {
        let viewModel = TrackerViewModel()
        viewModel.header.showCardCount = true
        viewModel.header.handCount = 6
        viewModel.header.deckCount = 13
        viewModel.header.lineHeight = rowHeight
        viewModel.header.barWidth = barWidth
        let all = rowCards(38)
        let groups = CardZoneGroups(deck: Array(all[0..<20]),
                                    hand: Array(all[20..<26]),
                                    played: Array(all[26..<38]))
        viewModel.update(cards: [], top: [], bottom: [], relatedCards: [], groups: groups)
        viewModel.updateLayout(availableHeight: 1000,
                               panelWidth: barWidth,
                               frameHeight: TrackerMetrics.sectionHeaderHeight(rowHeight: rowHeight),
                               reserveGraveyardRow: false)
        return census(of: TrackerView(viewModel: viewModel,
                                      topTitle: "On Top",
                                      bottomTitle: "On Bottom",
                                      relatedTitle: "Related",
                                      deckTitle: "Deck",
                                      handTitle: "Hand",
                                      playedTitle: "Played"),
                      size: NSSize(width: barWidth, height: 1000))
    }

    @MainActor
    func testWholePanelLayerCensus() {
        let vector = withFlattening(false) { panelCensus() }
        let flat = withFlattening(true) { panelCensus() }
        print("[perf-p2] whole panel (1 header line + 3 sections + 38 rows), vector: "
              + vector.description)
        print("[perf-p2] whole panel (1 header line + 3 sections + 38 rows), flat:   "
              + flat.description)
        XCTAssertGreaterThan(vector.total, 0)
        XCTAssertLessThan(flat.total, vector.total / 2)
        // What is left with a shadow is the header's, not the rows'.
        XCTAssertLessThanOrEqual(flat.shadowed, 4)
    }

    /// The number this slice is judged on: 30 rows, the two drawings, one run.
    @MainActor
    func testFlatteningCollapsesTheRowLayerTree() {
        let vector = withFlattening(false) { listCensus(rows: 30) }
        let flat = withFlattening(true) { listCensus(rows: 30) }
        print("[perf-p2] 30 rows, vector: \(vector.description)")
        print("[perf-p2] 30 rows, flat:   \(flat.description)")

        XCTAssertGreaterThan(vector.total, 0, "no layer tree was built; the census is meaningless")
        XCTAssertEqual(flat.shadowed, 0, "a flat bitmap has nothing left to blur offscreen")
        XCTAssertEqual(flat.groupOpacity, 0)
        XCTAssertEqual(flat.masked, 0)
        XCTAssertLessThan(flat.total, vector.total / 2)
        // Upper bound, so the vector row cannot creep back in unnoticed: four
        // layers per row plus the list's own.
        XCTAssertLessThanOrEqual(flat.total, 4 * 30 + 10)
    }

    // MARK: - Perf P2: the flattened row is the same picture

    @MainActor
    private func render<V: View>(_ view: V, scale: CGFloat) -> CGImage? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        return renderer.cgImage
    }

    private func pixels(_ image: CGImage) -> [UInt8]? {
        let width = image.width
        let height = image.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = buffer.withUnsafeMutableBytes({ bytes -> CGContext? in
            CGContext(data: bytes.baseAddress,
                      width: width,
                      height: height,
                      bitsPerComponent: 8,
                      bytesPerRow: width * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: info)
        }) else {
            return nil
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }

    private func sampleCard() -> Card {
        let card = Card()
        card.id = "PERF_SAMPLE"
        card.name = "公诉人梅尔特拉尼克斯"
        card.cost = 7
        card.count = 2
        card.rarity = .legendary
        return card
    }

    /// "Pixel-level appearance unchanged" is the hard constraint of this slice.
    /// The drawing is literally the same view — `CardRowContentView` — so the
    /// only thing that could move is the rasterise-and-blit step: a wrong scale,
    /// a half-point offset, a resample. This renders the row both ways at the
    /// same scale and diffs the buffers.
    @MainActor
    func testFlattenedRowIsTheSamePicture() {
        TrackerRowRaster.reset()
        let card = sampleCard()
        let scale: CGFloat = 2
        let content = CardRowContentView(card: card, rowHeight: 21, barWidth: 171)
        guard let vector = render(content, scale: scale),
              let flat = render(withFlattening(true) {
                  CardRowView(card: card, rowHeight: 21, barWidth: 171)
              }, scale: scale) else {
            return XCTFail("the renderer produced nothing")
        }
        XCTAssertEqual(flat.width, vector.width)
        XCTAssertEqual(flat.height, vector.height)
        guard let a = pixels(vector), let b = pixels(flat) else {
            return XCTFail("could not read the rendered pixels")
        }
        XCTAssertEqual(a.count, b.count)
        var worst = 0
        var differing = 0
        for index in 0..<min(a.count, b.count) {
            let delta = abs(Int(a[index]) - Int(b[index]))
            if delta > 0 {
                differing += 1
                worst = max(worst, delta)
            }
        }
        print("[perf-p2] flattened row vs vector row: \(differing) of \(a.count) "
              + "channel samples differ, worst delta \(worst)")
        XCTAssertLessThanOrEqual(worst, 1, "the blit must not resample or shift the row")
    }

    /// The point of the cache: a row that has not changed is not redrawn.
    @MainActor
    func testUnchangedRowsAreNotRedrawn() {
        TrackerRowRaster.reset()
        let card = sampleCard()
        let key = CardRowContentView(card: card, rowHeight: 21, barWidth: 171).rasterKey(scale: 2)
        for _ in 0..<5 {
            _ = TrackerRowRaster.image(for: key) {
                CardRowContentView(card: card, rowHeight: 21, barWidth: 171)
            }
        }
        XCTAssertEqual(TrackerRowRaster.lookups, 5)
        XCTAssertEqual(TrackerRowRaster.renders, 1, "four of the five had to be cache hits")
    }

    // MARK: - Bug T10: a row that changed has to be drawn again

    /// Hosts a live list and returns what it actually paints.
    @MainActor
    private func paint(_ viewModel: TrackerCardListViewModel,
                       rows: Int,
                       window: NSWindow,
                       host: NSHostingView<TrackerCardListView>) -> [UInt8]? {
        host.frame = NSRect(x: 0, y: 0,
                            width: viewModel.barWidth,
                            height: viewModel.rowHeight * CGFloat(max(rows, 1)))
        window.setContentSize(host.frame.size)
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            return nil
        }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let image = rep.cgImage else { return nil }
        return pixels(image)
    }

    /// Bug T10: the deck section drew `发挥优势 ×2` while its own header said the
    /// section held three cards — one per row. The count in a row comes from
    /// `Card`, and `Card` is a class whose `==` compares the id and nothing else,
    /// so two refreshes of the same card look equal to SwiftUI however much the
    /// count moved: `CardRowView.body` is skipped and the row keeps the bitmap it
    /// was rasterised with.
    @MainActor
    func testACountChangeRepaintsTheRow() {
        withFlattening(true) {
            TrackerRowRaster.reset()
            let viewModel = TrackerCardListViewModel()
            viewModel.rowHeight = 21
            viewModel.barWidth = 171

            let two = sampleCard()
            two.count = 2
            viewModel.update(cards: [two])

            let host = NSHostingView(rootView: TrackerCardListView(viewModel: viewModel))
            host.wantsLayer = true
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 171, height: 21),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host
            let before = paint(viewModel, rows: 1, window: window, host: host)
            let lookupsAfterFirst = TrackerRowRaster.lookups
            XCTAssertGreaterThan(lookupsAfterFirst, 0, "the first pass has to rasterise the row")

            let one = sampleCard()
            one.count = 1
            viewModel.update(cards: [one])
            XCTAssertEqual(viewModel.rows.first?.card.count, 1, "the view model did take the change")
            let after = paint(viewModel, rows: 1, window: window, host: host)

            XCTAssertGreaterThan(TrackerRowRaster.lookups, lookupsAfterFirst,
                                 "the row's body was skipped, so it still shows the old count")
            guard let before, let after else {
                return XCTFail("the hosting view painted nothing")
            }
            XCTAssertNotEqual(before, after, "the count box still reads 2")
            window.contentView = nil
        }
    }

    /// The hand section in the same screenshot said three cards and drew two.
    /// The third card had just been drawn, i.e. a row was inserted above two
    /// rows that were already on screen — so this feeds exactly that and checks
    /// every stripe is painted.
    @MainActor
    func testARowInsertedAboveOthersLeavesNoBlankStripe() {
        withFlattening(true) {
            TrackerRowRaster.reset()
            let viewModel = TrackerCardListViewModel()
            viewModel.rowHeight = 21
            viewModel.barWidth = 171
            let all = rowCards(3)
            viewModel.update(cards: [all[1], all[2]])

            let host = NSHostingView(rootView: TrackerCardListView(viewModel: viewModel))
            host.wantsLayer = true
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 171, height: 63),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host
            _ = paint(viewModel, rows: 2, window: window, host: host)

            viewModel.update(cards: all)
            guard let buffer = paint(viewModel, rows: 3, window: window, host: host) else {
                return XCTFail("the hosting view painted nothing")
            }
            let stride = buffer.count / 3
            for row in 0..<3 {
                let slice = buffer[(row * stride)..<((row + 1) * stride)]
                XCTAssertTrue(slice.contains { $0 != 0 },
                              "row \(row) of three was left blank after the insert")
            }
            window.contentView = nil
        }
    }

    /// The same skip seen from the other side: a row that is genuinely unchanged
    /// must stay a cache hit, so the fix may not simply repaint everything.
    @MainActor
    func testAnUnchangedRowIsStillNotRedrawn() {
        withFlattening(true) {
            TrackerRowRaster.reset()
            let viewModel = TrackerCardListViewModel()
            viewModel.rowHeight = 21
            viewModel.barWidth = 171
            viewModel.update(cards: [sampleCard()])

            let host = NSHostingView(rootView: TrackerCardListView(viewModel: viewModel))
            host.wantsLayer = true
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 171, height: 21),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host
            _ = paint(viewModel, rows: 1, window: window, host: host)
            let rendersAfterFirst = TrackerRowRaster.renders

            for _ in 0..<3 {
                viewModel.update(cards: [sampleCard()])
                _ = paint(viewModel, rows: 1, window: window, host: host)
            }
            XCTAssertEqual(TrackerRowRaster.renders, rendersAfterFirst,
                           "an unchanged row may be re-evaluated, but never re-rasterised")
            window.contentView = nil
        }
    }

    /// ...and a row that did change is. Every field of the key is one of the
    /// things V1 / V2 let change a row's appearance.
    @MainActor
    func testEveryAppearanceChangeIsANewRasterKey() {
        let card = sampleCard()
        let base = CardRowContentView(card: card, rowHeight: 21, barWidth: 171)
        let key = base.rasterKey(scale: 2)

        let bigger = CardRowContentView(card: card, rowHeight: 28, barWidth: 228)
        XCTAssertNotEqual(bigger.rasterKey(scale: 2), key)
        XCTAssertNotEqual(base.rasterKey(scale: 1), key)

        var other = base
        other.baseOpacity = base.baseOpacity / 2
        XCTAssertNotEqual(other.rasterKey(scale: 2), key)
        other = base
        other.highlightColor = .teal
        XCTAssertNotEqual(other.rasterKey(scale: 2), key)
        other = base
        other.showRarityColors = false
        XCTAssertNotEqual(other.rasterKey(scale: 2), key)
        other = base
        other.drawsArt = false
        XCTAssertNotEqual(other.rasterKey(scale: 2), key)
        other = base
        other.drawsTextShadow = false
        XCTAssertNotEqual(other.rasterKey(scale: 2), key)
        other = base
        other.isHandSection = true
        other.tile = NSImage(size: NSSize(width: 4, height: 4))
        XCTAssertNotEqual(other.rasterKey(scale: 2), key)

        let played = Card()
        played.id = card.id
        played.name = card.name
        played.cost = card.cost
        played.rarity = card.rarity
        played.count = -2
        XCTAssertNotEqual(CardRowContentView(card: played, rowHeight: 21, barWidth: 171)
                            .rasterKey(scale: 2), key)
    }

    /// Art is one more image layer and one more clip on the vector row, and
    /// nothing at all on the flattened one — so the list census above, taken
    /// with the tiles absent, understates what flattening removes.
    @MainActor
    func testArtCostsLayersOnlyOnTheVectorRow() {
        let tile = NSImage(size: NSSize(width: 256, height: 59))
        tile.lockFocus()
        NSColor.red.drawSwatch(in: NSRect(x: 0, y: 0, width: 256, height: 59))
        tile.unlockFocus()

        let card = sampleCard()
        let size = NSSize(width: 171, height: 21)
        let bare = census(of: CardRowContentView(card: card, rowHeight: 21, barWidth: 171),
                          size: size)
        let arted = census(of: CardRowContentView(card: card, rowHeight: 21, barWidth: 171,
                                                  tile: tile),
                           size: size)
        let flat = withFlattening(true) {
            census(of: CardRowView(card: card, rowHeight: 21, barWidth: 171), size: size)
        }
        print("[perf-p2] one row, vector no art: \(bare.description)")
        print("[perf-p2] one row, vector + art:  \(arted.description)")
        print("[perf-p2] one row, flat:          \(flat.description)")
        XCTAssertGreaterThan(arted.total, bare.total)
        XCTAssertLessThan(flat.total, bare.total)
        XCTAssertEqual(flat.shadowed, 0)
    }

    /// The other half of the trade: flattening buys layers with CPU on the
    /// frames where a row really changed. Timed, not asserted — the number goes
    /// in the report, the machine decides how big it is.
    @MainActor
    func testColdAndWarmRasterCost() {
        TrackerRowRaster.reset()
        // A `.big` row on the user's 3840x2160 window.
        let rowHeight: CGFloat = 41.9
        let barWidth: CGFloat = 341.2
        let cards = rowCards(60)
        func pass() -> TimeInterval {
            let start = Date()
            for card in cards {
                let content = CardRowContentView(card: card, rowHeight: rowHeight,
                                                 barWidth: barWidth)
                _ = TrackerRowRaster.image(for: content.rasterKey(scale: 2)) { content }
            }
            return Date().timeIntervalSince(start)
        }
        let cold = pass()
        XCTAssertEqual(TrackerRowRaster.renders, 60, "the first pass is all misses")
        let warm = pass()
        XCTAssertEqual(TrackerRowRaster.renders, 60, "the second pass must be all hits")
        print(String(format: "[perf-p2] 60 rows at %.0fx%.0f @2x: cold %.1f ms, warm %.2f ms",
                     barWidth, rowHeight, cold * 1000, warm * 1000))
    }

    /// `tracker_opacity` has to keep taking effect live. V2b let the row read
    /// `Settings` through a default argument, which only re-ran when the row was
    /// rebuilt for some other reason; the value now travels with the list.
    func testOpacityReachesEveryList() {
        let viewModel = TrackerViewModel()
        viewModel.update(cards: rowCards(5), top: [], bottom: [], relatedCards: [], groups: nil)
        viewModel.updateLayout(availableHeight: 900,
                               panelWidth: 171,
                               frameHeight: TrackerMetrics.sectionHeaderHeight(rowHeight: 21),
                               reserveGraveyardRow: false)
        for list in [viewModel.cards, viewModel.deck, viewModel.hand, viewModel.played,
                     viewModel.top, viewModel.bottom, viewModel.related] {
            XCTAssertEqual(list.baseOpacity, viewModel.layout.opacity, accuracy: accuracy)
            XCTAssertEqual(list.flattensRows, TrackerDiagnostics.flattensRows)
            XCTAssertEqual(list.drawsArt, TrackerDiagnostics.drawsArt)
            XCTAssertEqual(list.drawsTextShadow, TrackerDiagnostics.drawsTextShadow)
        }
        withDefault(Settings.tracker_perf_force_opaque, true) {
            viewModel.updateLayout(availableHeight: 900,
                                   panelWidth: 171,
                                   frameHeight: TrackerMetrics.sectionHeaderHeight(rowHeight: 21),
                                   reserveGraveyardRow: false)
            XCTAssertEqual(viewModel.layout.opacity, 1, accuracy: accuracy)
            XCTAssertEqual(viewModel.cards.baseOpacity, 1, accuracy: accuracy)
        }
    }

    /// The four bisection switches: their names, their defaults when unset, and
    /// that each one reaches the thing it is supposed to turn off. The user's
    /// own values are read back and restored, so running the suite never
    /// disturbs a bisection in progress.
    func testDiagnosticSwitches() {
        func unset(_ key: String, _ check: () -> Void) {
            let previous = UserDefaults.standard.object(forKey: key)
            UserDefaults.standard.removeObject(forKey: key)
            check()
            if let previous {
                UserDefaults.standard.set(previous, forKey: key)
            }
        }
        unset(Settings.tracker_perf_flatten_rows) {
            XCTAssertTrue(TrackerDiagnostics.flattensRows, "the new path is the default")
        }
        unset(Settings.tracker_perf_no_text_shadow) {
            XCTAssertTrue(TrackerDiagnostics.drawsTextShadow)
        }
        unset(Settings.tracker_perf_no_card_art) {
            XCTAssertTrue(TrackerDiagnostics.drawsArt)
        }
        unset(Settings.tracker_perf_force_opaque) {
            XCTAssertFalse(TrackerDiagnostics.forcesOpaquePanel)
            XCTAssertEqual(TrackerDiagnostics.panelOpacity(setting: 50),
                           TrackerMetrics.baseOpacity(setting: 50), accuracy: accuracy)
        }

        withDefault(Settings.tracker_perf_flatten_rows, false) {
            XCTAssertFalse(TrackerDiagnostics.flattensRows)
        }
        withDefault(Settings.tracker_perf_no_text_shadow, true) {
            XCTAssertFalse(TrackerDiagnostics.drawsTextShadow)
        }
        withDefault(Settings.tracker_perf_no_card_art, true) {
            XCTAssertFalse(TrackerDiagnostics.drawsArt)
            let card = sampleCard()
            let tile = NSImage(size: NSSize(width: 4, height: 4))
            let drawn = CardRowContentView(card: card, drawsArt: true, tile: tile)
            let hidden = CardRowContentView(card: card, drawsArt: false, tile: tile)
            XCTAssertNotEqual(drawn.rasterKey(scale: 2), hidden.rasterKey(scale: 2))
        }
        withDefault(Settings.tracker_perf_force_opaque, true) {
            XCTAssertTrue(TrackerDiagnostics.forcesOpaquePanel)
            XCTAssertEqual(TrackerDiagnostics.panelOpacity(setting: 50), 1, accuracy: accuracy)
            XCTAssertEqual(TrackerDiagnostics.panelOpacity(setting: 0), 1, accuracy: accuracy)
        }
    }

    // MARK: - Bug T11

    /// Symptom ①: a card destroyed inside the deck leaves the deck section's
    /// row list. The accounting does drop it (see `ZoneGroupsT11ReplayTests`),
    /// so what is left to check is that the row stops being painted.
    @MainActor
    func testARemovedRowStopsBeingPainted() {
        withFlattening(true) {
            TrackerRowRaster.reset()
            let viewModel = TrackerCardListViewModel()
            viewModel.rowHeight = 21
            viewModel.barWidth = 171
            let all = rowCards(2)
            viewModel.update(cards: all)

            let host = NSHostingView(rootView: TrackerCardListView(viewModel: viewModel))
            host.wantsLayer = true
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 171, height: 42),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host
            guard let both = paint(viewModel, rows: 2, window: window, host: host) else {
                return XCTFail("the hosting view painted nothing")
            }
            XCTAssertTrue(both[(both.count / 2)...].contains { $0 != 0 },
                          "the second row has to be on screen first")

            viewModel.update(cards: [all[0]])
            XCTAssertEqual(viewModel.rows.count, 1, "the view model did take the removal")
            guard let one = paint(viewModel, rows: 1, window: window, host: host) else {
                return XCTFail("the hosting view painted nothing")
            }
            XCTAssertEqual(one.count, both.count / 2,
                           "one row left, so the list is half as tall")
            XCTAssertEqual(one, Array(both[0..<(both.count / 2)]),
                           "the surviving row is the first one, unchanged")
            window.contentView = nil
        }
    }

    /// Symptom ②: the synergy highlight. `Tracker.setSwiftUIHighlight` hands the
    /// list a closure; the row list has to re-evaluate with it and the row has
    /// to be drawn again with the tint.
    @MainActor
    func testSettingTheSynergyHighlightRepaintsTheRow() {
        withFlattening(true) {
            TrackerRowRaster.reset()
            let viewModel = TrackerCardListViewModel()
            viewModel.rowHeight = 21
            viewModel.barWidth = 171
            viewModel.update(cards: [sampleCard()])

            let host = NSHostingView(rootView: TrackerCardListView(viewModel: viewModel))
            host.wantsLayer = true
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 171, height: 21),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host
            let plain = paint(viewModel, rows: 1, window: window, host: host)
            XCTAssertEqual(token(viewModel.rows.first?.highlight), 0)

            viewModel.setHighlight { _, _ in .teal }
            XCTAssertEqual(token(viewModel.rows.first?.highlight), 1,
                           "the closure never reached the rows")
            let lit = paint(viewModel, rows: 1, window: window, host: host)

            guard let plain, let lit else {
                return XCTFail("the hosting view painted nothing")
            }
            XCTAssertNotEqual(plain, lit, "the row was not repainted with the highlight")

            viewModel.setHighlight(nil)
            XCTAssertEqual(token(viewModel.rows.first?.highlight), 0, "clearing left the tint on")
            let off = paint(viewModel, rows: 1, window: window, host: host)
            XCTAssertEqual(off, plain, "clearing the highlight has to put the row back")
            window.contentView = nil
        }
    }

    /// The same closure through `TrackerViewModel`, i.e. the way
    /// `Tracker.setSwiftUIHighlight` reaches the three zone sections: the
    /// highlight has to survive the next tracker refresh, which rebuilds every
    /// row from a fresh `[Card]`.
    @MainActor
    func testTheSynergyHighlightSurvivesTheNextRefresh() {
        let viewModel = TrackerCardListViewModel()
        let cards = rowCards(2)
        viewModel.update(cards: cards)
        viewModel.setHighlight { card, _ in card.id == "PERF_1" ? .teal : .none }
        XCTAssertEqual(viewModel.rows.map { token($0.highlight) }, [0, 1])

        // A refresh a moment later: same cards, new objects, as the tracker
        // rebuilds them from the game state on every update.
        viewModel.update(cards: rowCards(2))
        XCTAssertEqual(viewModel.rows.map { token($0.highlight) }, [0, 1],
                       "a refresh dropped the highlight")
    }

    /// Symptom ②, the upstream half: the closure `Tracker.highlightPlayerDeckCards`
    /// hands to the lists comes out of `RelatedCardsManager`, which fills itself
    /// by reflection. An empty table there would kill every highlight at once,
    /// which is what "the synergy highlight stopped working" looks like.
    @MainActor
    func testTheRealSynergyClosureReachesTheRows() {
        // `ReflectionHelper.initialize()` runs off the main queue while the test
        // host app launches; the table is empty until it lands.
        let launched = Date().addingTimeInterval(30)
        while ReflectionHelper.getHighlightClasses().isEmpty && Date() < launched {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        XCTAssertGreaterThan(ReflectionHelper.getHighlightClasses().count, 100,
                             "reflection found next to no ICardWithHighlight")
        let manager = RelatedCardsManager()
        manager.reset()
        guard let source = manager.getCardWithHighlight(CardIds.Collectible.Mage.Arcanologist) else {
            return XCTFail("the highlight table is empty — reflection found no ICardWithHighlight")
        }

        // Out of scope, recorded here because the table is what this test reads:
        // `ReflectionHelper.initialize()` sorts a class with an `else if` chain,
        // so the four cards that are both ICardWithRelatedCards and
        // ICardWithHighlight land in the related table only and never get a
        // highlight. See the task book's 执行结果.
        XCTAssertNil(manager.getCardWithHighlight(CardIds.Collectible.Invalid.LiftOff),
                     "if this now resolves, ReflectionHelper was fixed — drop this assertion")

        let secret = Card()
        secret.id = "PERF_SECRET"
        secret.name = "Counterspell"
        secret.count = 1
        secret.mechanics = ["SECRET"]
        let plain = rowCards(1)[0]

        let viewModel = TrackerCardListViewModel()
        viewModel.update(cards: [secret, plain])
        viewModel.setHighlight(source.shouldHighlight)
        XCTAssertEqual(viewModel.rows.map { token($0.highlight) }, [1, 0],
                       "the real closure has to tint the secret and nothing else")
    }

    /// Symptom ②, the entry point: hovering a row in the panel is what asks for
    /// the highlight. On the overlay canvas the rows do not track the mouse;
    /// each reports its rect to `RootOverlayWindow`'s sweep (`TrackerRowHoverKey`),
    /// so every row has to report one covering the whole row, under the list's
    /// hover kind.
    @MainActor
    func testTheHoverSensorStillCoversEveryRow() {
        withFlattening(true) {
            let viewModel = TrackerCardListViewModel()
            viewModel.rowHeight = 21
            viewModel.barWidth = 171
            viewModel.hoverKind = .playerDeck
            viewModel.update(cards: rowCards(2))

            let (window, host) = hostedList(viewModel, height: 42)
            pump(host, 0.05)
            let rows = hoverRows(in: host)
            XCTAssertEqual(rows.count, 2, "one hover rect per row")
            for row in rows {
                XCTAssertEqual(row.rect.size,
                               CGSize(width: viewModel.barWidth, height: viewModel.rowHeight),
                               "the rect has to cover the whole row")
                XCTAssertEqual(row.kind, .playerDeck)
            }
            XCTAssertEqual(rows.map(\.rect.minY).sorted(), [0, 21], "one rect on each row")
            XCTAssertEqual(rows.map(\.card.id), viewModel.rows.map(\.card.id))

            viewModel.hoverKind = .none
            viewModel.update(cards: rowCards(3))
            pump(host, 0.05)
            XCTAssertTrue(hoverRows(in: host).isEmpty, "a list bound to no hover reports nothing")
            drain(window, host)
        }
    }

    // MARK: - Phase 1 / T8: motion

    private func motionRows(_ rows: [(String, Int)]) -> [TrackerMotion.Row] {
        rows.map { id, count in
            TrackerMotion.Row(id: TrackerCardRowID(cardId: id,
                                                   jousted: false,
                                                   isCreated: false,
                                                   wasDiscarded: false,
                                                   deckListIndex: 0,
                                                   hasIncindius: false,
                                                   incindiusTurn: 0,
                                                   incindiusCounter: 0),
                              count: count)
        }
    }

    private func animates(_ before: [(String, Int)], _ after: [(String, Int)]) -> Bool {
        if case .animated = TrackerMotion.plan(from: motionRows(before), to: motionRows(after)) {
            return true
        }
        return false
    }

    private func flashes(_ before: [(String, Int)], _ after: [(String, Int)]) -> [String] {
        guard case .animated(let ids) = TrackerMotion.plan(from: motionRows(before),
                                                           to: motionRows(after)) else {
            return []
        }
        return ids.map(\.cardId).sorted()
    }

    /// The whole "does this refresh move?" rule, shape by shape. Only a single
    /// card entering or leaving *this* list may animate; every bulk change is
    /// one frame, which is what keeps thirty rows from flying at once.
    func testOnlyASingleCardMovesTheList() {
        // draw the last copy: the row leaves
        XCTAssertTrue(animates([("a", 1), ("b", 1)], [("b", 1)]))
        // draw one of two copies: the row stays and the count drops
        XCTAssertTrue(animates([("a", 2), ("b", 1)], [("a", 1), ("b", 1)]))
        // shuffled in / drawn into the hand section: one row arrives
        XCTAssertTrue(animates([("b", 1)], [("a", 1), ("b", 1)]))
        // the played section counts down from zero
        XCTAssertTrue(animates([("a", -1)], [("a", -2)]))

        // opening deal, deck swap, end of game, groupCardsByZone flipping
        XCTAssertFalse(animates([], [("a", 1)]))
        XCTAssertFalse(animates([("a", 1)], []))
        XCTAssertFalse(animates([("a", 1), ("b", 1), ("c", 1)], [("c", 1)]))
        XCTAssertFalse(animates([("a", 1)], [("x", 1), ("y", 1), ("z", 1)]))
        // a whole two-of leaving at once is not one card
        XCTAssertFalse(animates([("a", 2), ("b", 1)], [("b", 1)]))
        // one out and one in on the same refresh: two cards as far as this
        // list can tell, so it refuses rather than guess they are the same one
        XCTAssertFalse(animates([("a", 1), ("b", 1)], [("b", 1), ("c", 1)]))
        // a refresh that only re-tints (hover, highlightDraw) moves nothing
        XCTAssertFalse(animates([("a", 1), ("b", 1)], [("a", 1), ("b", 1)]))
        // reordering alone is not a card moving either
        XCTAssertFalse(animates([("a", 1), ("b", 1)], [("b", 1), ("a", 1)]))
    }

    /// The flash marks the card that is *there* and changed; a row on its way
    /// out is told by the collapse instead.
    func testTheFlashMarksTheCardThatStayed() {
        XCTAssertEqual(flashes([("a", 2), ("b", 1)], [("a", 1), ("b", 1)]), ["a"])
        XCTAssertEqual(flashes([("b", 1)], [("a", 1), ("b", 1)]), ["a"])
        XCTAssertEqual(flashes([("a", 1), ("b", 1)], [("b", 1)]), [])
    }

    /// Grid changes — `card_size`, a window resize, the compression step, the
    /// opacity slider — move every row at once and may never glide.
    func testOnlyTheHeightsMayGlide() {
        let base = TrackerLayout(cardHeight: 21, barWidth: 171, opacity: 1,
                                 headerHeight: 21, listHeight: 21 * 10)
        let chrome: CGFloat = 22 + 5

        var oneRowShorter = base
        oneRowShorter.listHeight -= 21
        XCTAssertTrue(TrackerMotion.layoutCanAnimate(from: base, to: oneRowShorter,
                                                     sectionChrome: chrome))

        var sectionAppeared = base
        sectionAppeared.listHeight -= 21
        sectionAppeared.handHeight = 21 + chrome
        XCTAssertTrue(TrackerMotion.layoutCanAnimate(from: base, to: sectionAppeared,
                                                     sectionChrome: chrome))

        var resized = base
        resized.cardHeight = 28
        resized.barWidth = 228
        XCTAssertFalse(TrackerMotion.layoutCanAnimate(from: base, to: resized,
                                                      sectionChrome: chrome))

        var dimmer = base
        dimmer.opacity = 0.5
        XCTAssertFalse(TrackerMotion.layoutCanAnimate(from: base, to: dimmer,
                                                      sectionChrome: chrome))

        var emptied = base
        emptied.listHeight = 0
        XCTAssertFalse(TrackerMotion.layoutCanAnimate(from: base, to: emptied,
                                                      sectionChrome: chrome))
    }

    /// One linear animation drives the flash, so an interrupted one cannot be
    /// left lit: every value the curve can take is bounded, and both ends are 0.
    func testTheFlashCurveStartsAndEndsDark() {
        XCTAssertEqual(TrackerMotion.flashOpacity(0), 0, accuracy: 0.0001)
        XCTAssertEqual(TrackerMotion.flashOpacity(1), 0, accuracy: 0.0001)
        XCTAssertEqual(TrackerMotion.flashOpacity(0.5), TrackerMotion.flashPeak, accuracy: 0.0001)
        XCTAssertEqual(TrackerMotion.flashOpacity(-3), 0, accuracy: 0.0001)
        XCTAssertEqual(TrackerMotion.flashOpacity(9), 0, accuracy: 0.0001)
        for step in 0...20 {
            let value = TrackerMotion.flashOpacity(CGFloat(step) / 20)
            XCTAssertGreaterThanOrEqual(value, 0)
            XCTAssertLessThanOrEqual(value, TrackerMotion.flashPeak)
        }
    }

    /// Hosts a list and returns it, so a test can drive it across frames.
    @MainActor
    private func hostedList(_ viewModel: TrackerCardListViewModel,
                            height: CGFloat) -> (NSWindow, NSView) {
        let host = probedHost(TrackerCardListView(viewModel: viewModel))
        host.wantsLayer = true
        host.frame = NSRect(x: 0, y: 0, width: viewModel.barWidth, height: height)
        let window = NSWindow(contentRect: host.frame,
                              styleMask: [.borderless],
                              backing: .buffered,
                              defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        return (window, host)
    }

    @MainActor
    private func pump(_ host: NSView, _ seconds: TimeInterval) {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: seconds))
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
    }

    /// Hand a hosted panel back empty. A hosting view that is merely detached
    /// can still be mid-animation, and a foreign frame drawn after the *next*
    /// test's `TrackerRowRaster.reset()` would land on that test's probe.
    @MainActor
    private func drain(_ window: NSWindow, _ host: NSView) {
        window.contentView = nil
        RunLoop.current.run(until: Date(timeIntervalSinceNow:
            TrackerMotion.duration + TrackerMotion.flashDuration + 0.1))
    }

    /// The same problem seen from the other side, for tests that cannot be
    /// sure what ran before them: let the previous test's animations finish
    /// before this one resets the probe.
    @MainActor
    private func quiesce() {
        RunLoop.current.run(until: Date(timeIntervalSinceNow:
            TrackerMotion.duration + TrackerMotion.flashDuration + 0.4))
    }

    /// What a hosted view last reported through `TrackerRowHoverKey` — the
    /// overlay canvas's `onPreferenceChange`, stood in for by the host's root.
    private final class HoverProbe {
        var rows: [TrackerRowHover] = []
    }

    private struct ProbedRoot<Content: View>: View {
        let content: Content
        let probe: HoverProbe

        var body: some View {
            content.onPreferenceChange(TrackerRowHoverKey.self) { probe.rows = $0 }
        }
    }

    private var probes: [ObjectIdentifier: HoverProbe] = [:]

    @MainActor
    private func probedHost<Content: View>(_ content: Content) -> NSView {
        let probe = HoverProbe()
        let host = NSHostingView(rootView: ProbedRoot(content: content, probe: probe))
        probes[ObjectIdentifier(host)] = probe
        return host
    }

    /// Every row the hosted view reports a hover rect for, top down.
    private func hoverRows(in host: NSView) -> [TrackerRowHover] {
        (probes[ObjectIdentifier(host)]?.rows ?? []).sorted { $0.rect.minY < $1.rect.minY }
    }

    /// The hit areas themselves: one per settled row. A row on its way out
    /// stops reporting one.
    private func sensors(in host: NSView) -> [CGRect] {
        hoverRows(in: host).map(\.rect)
    }

    /// The row bitmaps the host is drawing this frame, read off its layer tree:
    /// one per *displayed* row, a row still collapsing included, at the height
    /// it is drawn at. Flattened rows only, on a panel without hero art: the row
    /// bitmaps are then the only image layers in the tree (text and shapes are
    /// drawn into layers of their own kinds).
    @MainActor
    private func displayedRows(in host: NSView) -> [CGRect] {
        guard let root = host.layer else { return [] }
        var found = [CGRect]()
        func walk(_ layer: CALayer) {
            if layer.contents != nil, String(describing: type(of: layer)) == "ImageLayer" {
                found.append(layer.convert(layer.bounds, to: root))
            }
            (layer.sublayers ?? []).forEach(walk)
        }
        walk(root)
        return found
    }

    /// Fresh `Card` instances every call: `Card` is a class, and reusing the
    /// same objects for the before and after of a refresh would mutate the
    /// rows the view model is still holding.
    private func motionCards(_ counts: [Int]) -> [Card] {
        let cards = rowCards(counts.count)
        for (card, count) in zip(cards, counts) {
            card.count = count
        }
        return cards
    }

    /// Perf P2's account may not be paid for with motion: the bitmap a row
    /// shows is keyed on its appearance, and neither the collapse nor the
    /// flash is part of that appearance. So a row that is animating is scaled
    /// and faded by the compositor, never re-rendered.
    @MainActor
    func testAnAnimatingRowIsNeverRedrawn() {
        withFlattening(true) {
            quiesce()
            TrackerRowRaster.reset()
            let viewModel = TrackerCardListViewModel()
            viewModel.rowHeight = 21
            viewModel.barWidth = 171
            viewModel.update(cards: motionCards([1, 2, 1, 1]))
            let (window, host) = hostedList(viewModel, height: 21 * 4)
            pump(host, 0.05)
            let settled = TrackerRowRaster.renders
            XCTAssertGreaterThan(settled, 0, "nothing was rasterised; the probe is meaningless")

            // one copy of a two-of drawn: the row stays, flashes, and its
            // count box goes away — one new picture, drawn once.
            viewModel.update(cards: motionCards([1, 1, 1, 1]))
            viewModel.commitMotion(animates: true)
            XCTAssertFalse(viewModel.flashing.isEmpty, "the count change has to flash")
            var duringFlash = settled
            for _ in 0..<5 {
                pump(host, TrackerMotion.flashDuration / 5)
                duringFlash = max(duringFlash, TrackerRowRaster.renders)
            }
            XCTAssertLessThanOrEqual(duringFlash - settled, 1,
                                     "the flash re-rasterised rows: \(duringFlash - settled)")

            // the last copy drawn: the row leaves, and a row on its way out is
            // the bitmap it already had, scaled and faded.
            let afterRemoval = TrackerRowRaster.renders
            viewModel.update(cards: Array(motionCards([1, 1, 1, 1])[0..<3]))
            viewModel.commitMotion(animates: true)
            var duringCollapse = afterRemoval
            for _ in 0..<5 {
                pump(host, TrackerMotion.duration / 5)
                duringCollapse = max(duringCollapse, TrackerRowRaster.renders)
            }
            XCTAssertEqual(duringCollapse, afterRemoval,
                           "the collapse re-rasterised rows")
            print("[t8] renders: \(settled) settled, \(duringFlash) through the flash, "
                  + "\(duringCollapse) through the collapse")
            drain(window, host)
        }
    }

    /// The other half of that account: what the render server has to composite
    /// while a row is in flight. The settled number is Perf P2's and is locked
    /// by `testFlatteningCollapsesTheRowLayerTree`; this one is recorded so a
    /// later change cannot quietly turn a transient cost into a standing one.
    @MainActor
    func testTheLayerTreeWhileARowIsInFlight() {
        withFlattening(true) {
            let viewModel = TrackerCardListViewModel()
            viewModel.rowHeight = 21
            viewModel.barWidth = 171
            viewModel.update(cards: motionCards(Array(repeating: 1, count: 10)))
            let (window, host) = hostedList(viewModel, height: 21 * 10)
            pump(host, 0.05)

            var settled = LayerCensus()
            if let layer = host.layer {
                census(of: layer, into: &settled)
            }

            viewModel.update(cards: Array(motionCards(Array(repeating: 1, count: 10))[0..<9]))
            viewModel.commitMotion(animates: true)
            pump(host, TrackerMotion.duration / 3)

            var moving = LayerCensus()
            if let layer = host.layer {
                census(of: layer, into: &moving)
            }
            print("[t8] 10 rows settled: \(settled.description)")
            print("[t8] 10 rows in flight: \(moving.description)")

            pump(host, TrackerMotion.flashDuration + TrackerMotion.duration)
            var again = LayerCensus()
            if let layer = host.layer {
                census(of: layer, into: &again)
            }
            print("[t8] 10 rows after landing: \(again.description)")
            XCTAssertLessThanOrEqual(again.total, settled.total,
                                     "the motion left layers behind: \(again.description)")
            XCTAssertEqual(again.shadowed, settled.shadowed)
            XCTAssertEqual(again.groupOpacity, 0,
                           "a finished fade must not leave a group opacity layer")
            drain(window, host)
        }
    }

    /// Three draws inside one animation, then a fourth that puts a card back:
    /// whatever the panel did in between, the picture it settles on is the one
    /// it would have shown with the switch off.
    @MainActor
    func testAnInterruptedRunConvergesOnTheInstantPicture() {
        withFlattening(true) {
            let ones = Array(repeating: 1, count: 6)
            let steps: [[Card]] = [6, 5, 4, 3, 4].map { Array(motionCards(ones)[0..<$0]) }

            @MainActor
            func run(motion: Bool, interrupt: Bool) -> [UInt8]? {
                let key = Settings.tracker_motion
                let previous = UserDefaults.standard.object(forKey: key)
                UserDefaults.standard.set(motion, forKey: key)
                defer {
                    if let previous {
                        UserDefaults.standard.set(previous, forKey: key)
                    } else {
                        UserDefaults.standard.removeObject(forKey: key)
                    }
                }
                let viewModel = TrackerCardListViewModel()
                viewModel.rowHeight = 21
                viewModel.barWidth = 171
                viewModel.update(cards: steps[0])
                let (window, host) = hostedList(viewModel, height: 21 * 6)
                pump(host, 0.05)
                for step in steps.dropFirst() {
                    viewModel.update(cards: step)
                    viewModel.commitMotion(animates: true)
                    // The interrupted run never lets one animation finish.
                    pump(host, interrupt ? TrackerMotion.duration / 4 : 0.02)
                }
                pump(host, TrackerMotion.duration + TrackerMotion.flashDuration + 0.2)
                defer { drain(window, host) }
                XCTAssertEqual(viewModel.rows.count, 4)
                XCTAssertTrue(viewModel.flashing.isEmpty,
                              "a flash outlived its own duration")
                guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
                    return nil
                }
                host.cacheDisplay(in: host.bounds, to: rep)
                return rep.cgImage.flatMap(pixels)
            }

            guard let still = run(motion: false, interrupt: false),
                  let interrupted = run(motion: true, interrupt: true) else {
                return XCTFail("the hosting view painted nothing")
            }
            XCTAssertEqual(interrupted, still,
                           "a run of interrupted animations did not land on the same picture")
        }
    }

    /// The switch, and with it "reduce motion": off, a refresh that would have
    /// animated publishes the new rows in one go and lights nothing.
    @MainActor
    func testTheMotionSwitchTurnsEverythingOff() {
        let key = Settings.tracker_motion
        XCTAssertTrue(withDefault(key, true) { Settings.trackerMotion })
        XCTAssertFalse(withDefault(key, false) { Settings.trackerMotion })
        XCTAssertFalse(withDefault(key, false) { TrackerMotion.isEnabled })

        withDefault(key, false) {
            let viewModel = TrackerCardListViewModel()
            viewModel.update(cards: motionCards([1, 1, 1]))
            viewModel.update(cards: Array(motionCards([1, 1, 1])[0..<2]))
            viewModel.commitMotion(animates: true)
            XCTAssertEqual(viewModel.rows.count, 2)
            XCTAssertTrue(viewModel.flashing.isEmpty, "the switch is off; nothing may flash")
            XCTAssertEqual(viewModel.motionGeneration, 0,
                           "the switch is off; the verdict may not bump either")
        }
    }

    /// The verdict is the coordinator's, and a list holds its request until it
    /// arrives — so a refresh the geometry refuses cannot leave a list moving.
    @MainActor
    func testTheListWaitsForTheVerdict() {
        let viewModel = TrackerCardListViewModel()
        viewModel.update(cards: motionCards([1, 1, 1]))
        XCTAssertFalse(viewModel.wantsMotion, "a deal-in does not ask to move")

        viewModel.update(cards: Array(motionCards([1, 1, 1])[0..<2]))
        XCTAssertTrue(viewModel.wantsMotion)
        XCTAssertEqual(viewModel.motionGeneration, 0, "nothing moves before the verdict")
        viewModel.commitMotion(animates: false)
        XCTAssertEqual(viewModel.motionGeneration, 0, "a refused refresh may not move")
        XCTAssertFalse(viewModel.wantsMotion, "the verdict has to clear the request")
        XCTAssertTrue(viewModel.flashing.isEmpty)

        viewModel.update(cards: Array(motionCards([1, 1, 1])[0..<1]))
        viewModel.commitMotion(animates: true)
        XCTAssertEqual(viewModel.motionGeneration, 1)

        viewModel.setHighlight { _, _ in .teal }
        XCTAssertFalse(viewModel.wantsMotion, "hovering is not motion")
    }

    // MARK: - T8 review 1: the compressed panel

    /// A whole panel in zone mode, sized so that `updateLayout` either does or
    /// does not have to shrink the row grid to fit.
    @MainActor
    private func zonePanel(deck: Int,
                           availableHeight: CGFloat,
                           barWidth: CGFloat = 171) -> TrackerViewModel {
        let viewModel = TrackerViewModel(playerType: .player)
        viewModel.header.lineHeight = 21
        viewModel.header.barWidth = barWidth
        feed(viewModel, deck: deck, availableHeight: availableHeight, barWidth: barWidth)
        return viewModel
    }

    @MainActor
    private func feed(_ viewModel: TrackerViewModel,
                      deck: Int,
                      availableHeight: CGFloat,
                      barWidth: CGFloat = 171) {
        let groups = CardZoneGroups(deck: motionCards(Array(repeating: 1, count: deck)),
                                    hand: [], played: [])
        viewModel.update(cards: [], top: [], bottom: [], relatedCards: [], groups: groups)
        viewModel.updateLayout(availableHeight: availableHeight,
                               panelWidth: barWidth,
                               frameHeight: TrackerMetrics.sectionHeaderHeight(rowHeight: 21),
                               reserveGraveyardRow: false)
    }

    @MainActor
    private func hostedPanel(_ viewModel: TrackerViewModel,
                             height: CGFloat,
                             barWidth: CGFloat = 171) -> (NSWindow, NSView) {
        let host = probedHost(TrackerView(viewModel: viewModel,
                                          topTitle: "On Top",
                                          bottomTitle: "On Bottom",
                                          relatedTitle: "Related",
                                          deckTitle: "Deck",
                                          handTitle: "Hand",
                                          playedTitle: "Played"))
        host.wantsLayer = true
        host.frame = NSRect(x: 0, y: 0, width: barWidth, height: height)
        let window = NSWindow(contentRect: host.frame,
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        return (window, host)
    }

    /// The observable. One row bitmap is drawn per *displayed* row, at that
    /// row's own height, so the bitmaps are a readout of what the layout
    /// actually did this frame.
    ///
    /// The load-bearing half is the count: a bitmap exists for a row that is
    /// still collapsing, so `rows drawn > rows` means "something is in flight".
    /// Combined with a `cardHeight` that has already moved, that is exactly the
    /// defect — content still laid out on the old grid, frames on the new one,
    /// i.e. the list overflowing the section box. The height check is the
    /// weaker half and is there to catch a row left at a stale size.
    @MainActor
    private func gridIsWhole(_ host: NSView, _ viewModel: TrackerViewModel) -> Bool {
        let found = displayedRows(in: host)
        guard found.count == viewModel.deck.rows.count else { return false }
        return found.allSatisfy { abs($0.height - viewModel.layout.cardHeight) < 1 }
    }

    /// Review 1. Under compression `cardHeight` is
    /// `(availableHeight - offset) / totalCards`, so losing one row makes every
    /// row taller. The rows may not animate through a grid change: the whole
    /// refresh goes in one frame, both halves together.
    @MainActor
    func testACompressedPanelNeverFliesThroughAGridChange() {
        withFlattening(true) {
            // 30 rows into 320pt: the grid is compressed well below 21pt.
            let viewModel = zonePanel(deck: 30, availableHeight: 320)
            XCTAssertLessThan(viewModel.layout.cardHeight, 21,
                              "the panel is not compressed; the test proves nothing")
            let (window, host) = hostedPanel(viewModel, height: 320)
            pump(host, 0.05)
            XCTAssertTrue(gridIsWhole(host, viewModel))
            let before = viewModel.motionGeneration
            let grid = viewModel.layout.cardHeight

            // one card drawn
            feed(viewModel, deck: 29, availableHeight: 320)
            XCTAssertGreaterThan(viewModel.layout.cardHeight, grid,
                                 "losing a row has to move the compressed grid")
            XCTAssertEqual(viewModel.motionGeneration, before,
                           "a refresh that moves the grid may not animate")
            for _ in 0..<6 {
                pump(host, TrackerMotion.duration / 5)
                XCTAssertTrue(gridIsWhole(host, viewModel),
                              "a row was in flight while the grid jumped: "
                                + "\(displayedRows(in: host).map(\.height)) "
                                + "vs \(viewModel.layout.cardHeight)")
            }

            // and the other way: a card shuffled back in
            feed(viewModel, deck: 30, availableHeight: 320)
            XCTAssertEqual(viewModel.motionGeneration, before)
            for _ in 0..<6 {
                pump(host, TrackerMotion.duration / 5)
                XCTAssertTrue(gridIsWhole(host, viewModel),
                              "the insert flew through a grid change")
            }
            drain(window, host)
        }
    }

    /// The refresh that crosses the threshold: uncompressed before, compressed
    /// after. It moves the grid too, so it is one frame as well.
    @MainActor
    func testTheRefreshThatCrossesTheCompressionThresholdIsOneFrame() {
        withFlattening(true) {
            // The exact height at which 12 rows fit on the base grid, read off
            // the layout itself rather than guessed: one more row then has to
            // compress, by construction.
            let probe = zonePanel(deck: 12, availableHeight: 10_000)
            let exactFit = probe.layout.contentHeight
            let viewModel = zonePanel(deck: 12, availableHeight: exactFit)
            XCTAssertEqual(viewModel.layout.cardHeight, 21, accuracy: 0.01,
                           "the panel starts compressed; the probe is wrong")
            let (window, host) = hostedPanel(viewModel, height: exactFit)
            pump(host, 0.05)
            let before = viewModel.motionGeneration

            feed(viewModel, deck: 13, availableHeight: exactFit)
            XCTAssertLessThan(viewModel.layout.cardHeight, 21,
                              "13 rows still fit; the threshold was not crossed")
            XCTAssertEqual(viewModel.motionGeneration, before,
                           "the refresh that starts compressing may not animate")
            for _ in 0..<6 {
                pump(host, TrackerMotion.duration / 5)
                XCTAssertTrue(gridIsWhole(host, viewModel),
                              "a row flew across the compression threshold")
            }
            drain(window, host)
        }
    }

    /// The control, so the two tests above cannot pass by never animating at
    /// all: the same single-card refresh on a panel with room to spare does
    /// animate, and its grid holds still throughout.
    @MainActor
    func testAnUncompressedPanelStillAnimatesTheSameRefresh() {
        withFlattening(true) {
            let viewModel = zonePanel(deck: 8, availableHeight: 600)
            XCTAssertEqual(viewModel.layout.cardHeight, 21, accuracy: 0.01)
            let (window, host) = hostedPanel(viewModel, height: 600)
            pump(host, 0.05)
            let before = viewModel.motionGeneration

            feed(viewModel, deck: 7, availableHeight: 600)
            XCTAssertEqual(viewModel.layout.cardHeight, 21, accuracy: 0.01,
                           "the grid must not move here")
            XCTAssertEqual(viewModel.motionGeneration, before + 1,
                           "an uncompressed single-card refresh has to animate")

            var sawFlight = false
            for _ in 0..<4 {
                pump(host, TrackerMotion.duration / 5)
                let found = displayedRows(in: host)
                if found.count > viewModel.deck.rows.count {
                    sawFlight = true
                }
                // the grid itself never moves while a row is in flight
                XCTAssertTrue(found.allSatisfy { $0.height <= 21 + 1 },
                              "a row grew past the grid: \(found.map(\.height))")
            }
            XCTAssertTrue(sawFlight, "nothing was ever in flight; the control is vacuous")

            pump(host, TrackerMotion.duration + 0.2)
            XCTAssertTrue(gridIsWhole(host, viewModel))
            drain(window, host)
        }
    }

    /// The hit area is the one part that may not keep the row's full height
    /// while the row collapses: a leaving row would sit on top of the one
    /// sliding up under it and answer its hover.
    @MainActor
    func testTheHoverSensorShrinksWithALeavingRow() {
        withFlattening(true) {
            let viewModel = TrackerCardListViewModel()
            viewModel.rowHeight = 21
            viewModel.barWidth = 171
            viewModel.hoverKind = .playerDeck
            viewModel.update(cards: motionCards([1, 1, 1]))
            let (window, host) = hostedList(viewModel, height: 21 * 3)
            pump(host, 0.05)
            XCTAssertEqual(sensors(in: host).count, 3, "one hover sensor per row")
            XCTAssertTrue(sensors(in: host).allSatisfy { $0.height == 21 },
                          "a settled row's hit area covers the whole row")

            viewModel.update(cards: Array(motionCards([1, 1, 1])[0..<2]))
            viewModel.commitMotion(animates: true)
            pump(host, TrackerMotion.duration / 2)
            let moving = displayedRows(in: host)
            XCTAssertEqual(moving.count, 3, "the leaving row is still on screen")
            XCTAssertEqual(moving.filter { $0.height < 20 }.count, 1,
                           "exactly the leaving row collapses: \(moving.map(\.height))")
            // ...but it no longer answers the sweep: only the two rows that stay
            // report a hit area, so a hover on the leaving row ends.
            let hovered = hoverRows(in: host)
            XCTAssertEqual(hovered.count, 2, "the leaving row still reports a hit area")
            XCTAssertTrue(hovered.allSatisfy { $0.kind == .playerDeck && $0.rect.height == 21 })

            pump(host, TrackerMotion.duration + 0.2)
            let landed = sensors(in: host)
            XCTAssertEqual(landed.count, 2, "the leaving row's hit area outlived the row")
            XCTAssertTrue(landed.allSatisfy { $0.height == 21 })
            XCTAssertEqual(displayedRows(in: host).count, 2)
            drain(window, host)
        }
    }

    // MARK: - REFORK S4: the block inside the upstream panel

    /// The fork's block replaces the player's title / wins / top / cards /
    /// bottom / counter sections at the first of their places, the upstream
    /// sections it keeps share its row grid, and the whole stack stays inside
    /// the box upstream's placement settings give the panel.
    @MainActor
    func testTheZonePanelSitsInsideTheUpstreamShell() {
        withDefault(Settings.group_cards_by_zone, true) {
            withDefault(Settings.player_draw_chance, true) {
                let canvas = CGSize(width: 1920, height: 1080)
                let panel = TrackerPanelViewModel(playerType: .player)
                panel.height = 40
                panel.scaling = 100
                panel.panelOrder = DeckPanel.defaultPlayerOrder
                panel.showGraveyard = true
                XCTAssertFalse(TrackerPanelLayout(viewModel: panel, canvasHeight: canvas.height).isZonePanel,
                               "a block that was never laid out leaves the panel on upstream's layout")
                XCTAssertEqual(panel.zonePanel.deck.hoverKind, .playerDeck)

                let groups = CardZoneGroups(deck: rowCards(24), hand: rowCards(6), played: [])
                panel.update(cards: [], top: [], bottom: [], sideboards: [], relatedCards: [], groups: groups)
                panel.relayoutZonePanel(canvasSize: canvas)

                let layout = TrackerPanelLayout(viewModel: panel, canvasHeight: canvas.height)
                XCTAssertTrue(layout.isZonePanel)
                XCTAssertEqual(layout.sections.map(\.kind), [.zone],
                               "S6b: no draw chances or graveyard counter under the block, as on dev")
                XCTAssertEqual(layout.width,
                               TrackerMetrics.panelWidth(windowWidth: canvas.width, windowHeight: canvas.height,
                                                         cardSize: Settings.cardSize),
                               accuracy: accuracy)
                XCTAssertEqual(layout.boxHeight, canvas.height * 0.4, accuracy: accuracy)
                XCTAssertLessThan(layout.cardHeight, TrackerMetrics.rowHeight(panelWidth: layout.width),
                                  "30 rows in 432pt have to compress; the test proves nothing")
                XCTAssertEqual(layout.cardHeight, panel.zonePanel.layout.cardHeight, accuracy: accuracy)
                let content = layout.sections.reduce(0) { $0 + $1.height }
                XCTAssertLessThanOrEqual(content, layout.boxHeight + 0.5, "the stack spills out of its box")
                XCTAssertEqual(layout.sections.first?.height ?? 0, panel.zonePanel.layout.contentHeight,
                               accuracy: accuracy)
                // Upstream's frames are drawn at the panel's width.
                XCTAssertEqual(layout.smallFrameHeight, layout.width * 40 / 217, accuracy: accuracy)

                withDefault(Settings.group_cards_by_zone, false) {
                    panel.relayoutZonePanel()
                    XCTAssertFalse(TrackerPanelLayout(viewModel: panel, canvasHeight: canvas.height).isZonePanel,
                                   "switching zones off falls back to upstream's panel")
                }
            }
        }
    }

    /// The opponent keeps upstream's hero bar on top and the block below it.
    @MainActor
    func testTheOpponentZonePanelKeepsTheHeroBar() {
        withDefault(Settings.group_cards_by_zone, true) {
            withDefault(Settings.show_opponent_class, true) {
                let panel = TrackerPanelViewModel(playerType: .opponent)
                panel.height = 60
                panel.scaling = 100
                panel.panelOrder = DeckPanel.defaultOpponentOrder
                panel.playerClassId = "HERO_01"
                panel.showGraveyard = false
                XCTAssertEqual(panel.zonePanel.cards.playerType, .opponent)
                XCTAssertEqual(panel.zonePanel.cards.hoverKind, .opponentDeck)

                panel.update(cards: rowCards(5), top: [], bottom: [], sideboards: [], relatedCards: [],
                             groups: nil)
                panel.relayoutZonePanel(canvasSize: CGSize(width: 1920, height: 1080))
                let layout = TrackerPanelLayout(viewModel: panel, canvasHeight: 1080)
                XCTAssertEqual(layout.sections.first?.kind, .deckPanel(.deckTitle))
                XCTAssertEqual(layout.sections.dropFirst().first?.kind, .zone)
                XCTAssertEqual(panel.zonePanel.cards.rows.count, 5, "no linked deck: the flat list")
            }
        }
    }

    // MARK: - REFORK S6b: panel leftovers

    /// Draw chances, the graveyard counter and the sideboard band stay out of
    /// the zone panel whatever their settings say; only the block (and the
    /// opponent's hero bar) is left.
    @MainActor
    func testTheZonePanelDrawsNoDrawChancesGraveyardOrSideboards() {
        withDefault(Settings.group_cards_by_zone, true) {
            withDefault(Settings.player_draw_chance, true) {
                withDefault(Settings.opponent_draw_chance, true) {
                    withDefault(Settings.hide_player_sideboards, false) {
                        withDefault(Settings.show_opponent_class, false) {
                            let canvas = CGSize(width: 1920, height: 1080)
                            for playerType in [PlayerType.player, .opponent] {
                                let panel = TrackerPanelViewModel(playerType: playerType)
                                panel.height = 60
                                panel.scaling = 100
                                panel.panelOrder = DeckPanel.order(for: playerType)
                                panel.showGraveyard = true
                                let sideboards = [Sideboard(ownerCardId: CardIds.Collectible.Neutral.ETCBandManager,
                                                            cards: rowCards(3))]
                                panel.update(cards: rowCards(5), top: [], bottom: [], sideboards: sideboards,
                                             relatedCards: [], groups: nil)
                                XCTAssertGreaterThan(panel.sideboardCardCount, 0,
                                                     "upstream would draw its band; the test proves nothing")
                                panel.relayoutZonePanel(canvasSize: canvas)

                                let layout = TrackerPanelLayout(viewModel: panel, canvasHeight: canvas.height)
                                XCTAssertEqual(layout.sections.map(\.kind), [.zone], "\(playerType)")
                                XCTAssertNil(layout.offset(of: .deckPanel(.graveyard), centered: false),
                                             "no counter, so no graveyard details hover region")
                            }
                        }
                    }
                }
            }
        }
    }

    /// The opponent's hero bar is one card row tall, on the same grid as the
    /// header lines (dev 1745adfa), not upstream's 34 / 217 frame.
    @MainActor
    func testTheOpponentHeroBarIsOneRowTall() {
        withDefault(Settings.group_cards_by_zone, true) {
            withDefault(Settings.show_opponent_class, true) {
                let canvas = CGSize(width: 1920, height: 1080)
                let panel = TrackerPanelViewModel(playerType: .opponent)
                panel.height = 60
                panel.scaling = 100
                panel.panelOrder = DeckPanel.defaultOpponentOrder
                panel.playerClassId = "HERO_01"
                panel.update(cards: rowCards(5), top: [], bottom: [], sideboards: [], relatedCards: [],
                             groups: nil)
                panel.relayoutZonePanel(canvasSize: canvas)

                let layout = TrackerPanelLayout(viewModel: panel, canvasHeight: canvas.height)
                let rowHeight = TrackerMetrics.rowHeight(panelWidth: layout.width)
                XCTAssertEqual(layout.sections.first?.kind, .deckPanel(.deckTitle))
                XCTAssertEqual(layout.sections.first?.height ?? 0, rowHeight, accuracy: accuracy)
                XCTAssertEqual(panel.zonePanel.shell?.heroHeight ?? 0, rowHeight, accuracy: accuracy)
                XCTAssertEqual(panel.zonePanel.header.lineHeight, rowHeight, accuracy: accuracy,
                               "the bar and the header lines share one grid")
            }
        }
    }

    private func sideboardPanel(_ sideboards: [Sideboard]) -> TrackerPanelViewModel {
        let panel = TrackerPanelViewModel(playerType: .player)
        panel.update(cards: [], top: [], bottom: [], sideboards: sideboards, relatedCards: [], groups: nil)
        return panel
    }

    private func ownerCard(_ id: String) -> Card {
        let card = Card()
        card.id = id
        card.count = 1
        return card
    }

    /// Hovering a sideboard owner finds its sideboard by `ownerCardId`, for any
    /// owner rather than the two upstream's band hard-codes, and only in the
    /// zone panel.
    @MainActor
    func testASideboardIsFoundByItsOwner() {
        withDefault(Settings.hide_player_sideboards, false) {
            let band = rowCards(3)
            let other = rowCards(2)
            let panel = sideboardPanel([
                Sideboard(ownerCardId: CardIds.Collectible.Neutral.ETCBandManager, cards: band),
                Sideboard(ownerCardId: "SOME_FUTURE_OWNER", cards: other),
                Sideboard(ownerCardId: CardIds.Collectible.Hunter.KingOfTheUnderbelly, cards: [])
            ])
            withDefault(Settings.group_cards_by_zone, true) {
                XCTAssertEqual(panel.sideboardCards(for: ownerCard(CardIds.Collectible.Neutral.ETCBandManager))?
                                .map(\.id), band.map(\.id))
                XCTAssertEqual(panel.sideboardCards(for: ownerCard("SOME_FUTURE_OWNER"))?.map(\.id),
                               other.map(\.id), "any owner id matches, not just E.T.C. and the King")
                XCTAssertNil(panel.sideboardCards(for: ownerCard(CardIds.Collectible.Hunter.KingOfTheUnderbelly)),
                             "an empty sideboard shows nothing")
                XCTAssertNil(panel.sideboardCards(for: ownerCard("PERF_0")))

                let opponent = TrackerPanelViewModel(playerType: .opponent)
                opponent.update(cards: [], top: [], bottom: [],
                                sideboards: [Sideboard(ownerCardId: "SOME_FUTURE_OWNER", cards: other)],
                                relatedCards: [], groups: nil)
                XCTAssertNil(opponent.sideboardCards(for: ownerCard("SOME_FUTURE_OWNER")))
            }
            withDefault(Settings.group_cards_by_zone, false) {
                XCTAssertNil(panel.sideboardCards(for: ownerCard(CardIds.Collectible.Neutral.ETCBandManager)),
                             "zones off: upstream's band shows the sideboard, the hover stays upstream's")
            }
        }
    }

    /// `hide_player_sideboards` turns the whole hover off, and the related
    /// cards get the grid back.
    @MainActor
    func testHidingSideboardsTurnsTheHoverOff() {
        withDefault(Settings.group_cards_by_zone, true) {
            withDefault(Settings.hide_player_sideboards, true) {
                let panel = sideboardPanel([Sideboard(ownerCardId: CardIds.Collectible.Neutral.ETCBandManager,
                                                      cards: rowCards(3))])
                XCTAssertNil(panel.sideboardCards(for: ownerCard(CardIds.Collectible.Neutral.ETCBandManager)))
            }
        }
    }

    /// A customised Zilliax is listed as a copy of its cosmetic module, whose
    /// own id never matches the owner; `deckbuildingCard` maps it back.
    @MainActor
    func testACustomisedZilliaxFindsItsSideboard() {
        let deadline = Date().addingTimeInterval(60)
        while Cards.any(byId: "TOY_330t10") == nil && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        guard let module = Cards.any(byId: "TOY_330t10")?.copy(),
              Cards.by(cardId: CardIds.Collectible.Neutral.ZilliaxDeluxe3000) != nil else {
            return XCTFail("the card database never loaded Zilliax")
        }
        XCTAssertTrue(module.zilliaxCustomizableCosmeticModule,
                      "TOY_330t10 is no longer flagged as a Zilliax cosmetic module")
        withDefault(Settings.group_cards_by_zone, true) {
            withDefault(Settings.hide_player_sideboards, false) {
                let modules = rowCards(2)
                let panel = sideboardPanel([Sideboard(ownerCardId: CardIds.Collectible.Neutral.ZilliaxDeluxe3000,
                                                      cards: modules)])
                XCTAssertNotEqual(module.id, CardIds.Collectible.Neutral.ZilliaxDeluxe3000)
                XCTAssertEqual(panel.sideboardCards(for: module)?.map(\.id), modules.map(\.id))
            }
        }
    }

    // MARK: - Second review batch

    /// The image cache is bounded, so a tile the rows already had can be evicted.
    /// Remembering it as "requested" forever left those rows without art for
    /// the rest of the session.
    @MainActor
    func testAnEvictedTileIsFetchedAgain() {
        var store = [String: NSImage]()
        var fetches = [String: [(NSImage?) -> Void]]()
        let cache = CardTileArtCache(cachedTile: { store[$0] },
                                     fetchTile: { cardId, done in fetches[cardId, default: []].append(done) })

        XCTAssertNil(cache.tile(for: "A"))
        drainMainQueue()
        XCTAssertEqual(fetches["A"]?.count, 1)
        XCTAssertNil(cache.tile(for: "A"))
        drainMainQueue()
        XCTAssertEqual(fetches["A"]?.count, 1, "a fetch still in flight must not be started again")

        let image = NSImage(size: NSSize(width: 1, height: 1))
        store["A"] = image
        fetches["A"]?[0](image)
        drainMainQueue()
        XCTAssertTrue(cache.tile(for: "A") === image)

        store["A"] = nil
        XCTAssertNil(cache.tile(for: "A"))
        drainMainQueue()
        XCTAssertEqual(fetches["A"]?.count, 2, "the evicted tile was never asked for again")
    }

    /// A tile that does not exist stays asked for once: the rows redraw on every
    /// fetch that lands, and each redraw would retry it.
    @MainActor
    func testAMissingTileIsNotRetriedOnEveryRedraw() {
        var fetches = 0
        var pending: ((NSImage?) -> Void)?
        let cache = CardTileArtCache(cachedTile: { _ in nil },
                                     fetchTile: { _, done in fetches += 1; pending = done })
        XCTAssertNil(cache.tile(for: "B"))
        drainMainQueue()
        pending?(nil)
        drainMainQueue()
        XCTAssertNil(cache.tile(for: "B"))
        drainMainQueue()
        XCTAssertEqual(fetches, 1)
    }

    /// Upstream's flat list lights the rows still in the deck and hands the
    /// closure those rows as the deck. In zone mode that is the deck section:
    /// the hand and played sections stay unlit, and the closure never sees them.
    @MainActor
    func testZoneModeHighlightsTheDeckSectionOnly() {
        func cards(_ prefix: String, _ counts: [Int]) -> [Card] {
            counts.enumerated().map { index, count in
                let card = Card()
                card.id = "\(prefix)_\(index)"
                card.name = card.id
                card.count = count
                return card
            }
        }
        let deck = cards("DECK", [2, 1])
        let hand = cards("HAND", [1, 1])
        let played = cards("PLAYED", [-1])
        let viewModel = TrackerViewModel(playerType: .player)
        viewModel.update(cards: [], top: [], bottom: [], relatedCards: [],
                         groups: CardZoneGroups(deck: deck, hand: hand, played: played))

        var seenDecks = [[String]]()
        viewModel.setHighlight { _, deckCards in
            seenDecks.append(deckCards.map(\.id))
            return .teal
        }
        XCTAssertEqual(viewModel.deck.rows.map { token($0.highlight) }, [1, 1])
        XCTAssertEqual(viewModel.hand.rows.map { token($0.highlight) }, [0, 0],
                       "the hand is not the deck")
        XCTAssertEqual(viewModel.played.rows.map { token($0.highlight) }, [0])
        XCTAssertFalse(seenDecks.isEmpty)
        XCTAssertTrue(seenDecks.allSatisfy { $0 == ["DECK_0", "DECK_1"] },
                      "the closure has to reason about the deck section: \(seenDecks)")

        // The next refresh keeps it that way.
        seenDecks.removeAll()
        viewModel.update(cards: [], top: [], bottom: [], relatedCards: [],
                         groups: CardZoneGroups(deck: cards("DECK", [2, 1]), hand: cards("HAND", [1, 1]),
                                                played: cards("PLAYED", [-1])))
        XCTAssertEqual(viewModel.hand.rows.map { token($0.highlight) }, [0, 0])
        XCTAssertTrue(seenDecks.allSatisfy { $0 == ["DECK_0", "DECK_1"] })

        // Flat mode: the one list, as upstream.
        seenDecks.removeAll()
        let flat = cards("FLAT", [1, 0, 2])
        viewModel.update(cards: flat, top: [], bottom: [], relatedCards: [], groups: nil)
        XCTAssertEqual(viewModel.cards.rows.map { token($0.highlight) }, [1, 0, 1])
        XCTAssertTrue(seenDecks.allSatisfy { $0 == ["FLAT_0", "FLAT_2"] })
    }

    /// Requests inside the debounce window cost one refresh, and a reset among
    /// them is not dropped.
    func testRefreshRequestsCoalesce() {
        let scheduler = OverlayRefreshScheduler()
        let calls = Recorder<Bool>()
        let ran = expectation(description: "refresh")
        ran.assertForOverFulfill = false
        scheduler.refresh = { reset in
            calls.append(reset)
            ran.fulfill()
        }
        for index in 0..<20 {
            scheduler.request(reset: index == 7)
        }
        wait(for: [ran], timeout: 1)
        spinMainRunLoop(for: 0.1)
        XCTAssertEqual(calls.values, [true])
    }

    /// The next refresh waits for the main queue to get through the last one.
    func testNoRefreshStartsWhileTheLastOneIsInFlight() {
        let scheduler = OverlayRefreshScheduler()
        let calls = Recorder<Bool>()
        let started = DispatchSemaphore(value: 0)
        scheduler.refresh = { reset in
            calls.append(reset)
            started.signal()
        }
        scheduler.request()
        XCTAssertEqual(started.wait(timeout: .now() + 1), .success)

        // The main thread is held here, so the markers the refresh queued behind
        // itself cannot run.
        scheduler.request()
        Thread.sleep(forTimeInterval: 0.1)
        XCTAssertEqual(calls.values.count, 1, "a refresh started on top of one still in flight")

        let deadline = Date().addingTimeInterval(1)
        while calls.values.count < 2 && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        XCTAssertEqual(calls.values.count, 2, "the held request never ran")
    }

    func testARequestBeforeTheRefreshIsSetIsNotLost() {
        let scheduler = OverlayRefreshScheduler()
        scheduler.request(reset: true)
        // Well past the debounce: the scheduled run found nothing to call.
        Thread.sleep(forTimeInterval: 0.1)

        let calls = Recorder<Bool>()
        let ran = expectation(description: "refresh")
        scheduler.refresh = { reset in
            calls.append(reset)
            ran.fulfill()
        }
        wait(for: [ran], timeout: 1)
        XCTAssertEqual(calls.values, [true])
    }

    func testTheLeastRecentlyUsedEntryIsEvictedFirst() {
        let cache = SynchronizedLRUCache<String, Int>(capacity: 3)
        cache["a"] = 1
        cache["b"] = 2
        cache["c"] = 3
        XCTAssertEqual(cache["a"], 1) // a is now the most recent
        cache["d"] = 4
        XCTAssertNil(cache["b"], "b was the least recently used")

        cache["c"] = 30 // a write counts as a use
        cache["e"] = 5
        XCTAssertNil(cache["a"])
        XCTAssertEqual(cache["d"], 4)
        XCTAssertEqual(cache["c"], 30)
        XCTAssertEqual(cache["e"], 5)

        cache["d"] = nil
        cache["f"] = 6
        XCTAssertEqual(cache["c"], 30, "a removal frees a slot")
        XCTAssertEqual(cache["e"], 5)
        XCTAssertEqual(cache["f"], 6)
    }

    /// The upstream record label and the zone header drop at the same moments.
    func testTheRecordCacheGenerationMovesOnEveryInvalidation() {
        let cache = DeckRecordLabelCache()
        let start = cache.generation(gameEnded: false)
        XCTAssertEqual(cache.generation(gameEnded: false), start)
        let ended = cache.generation(gameEnded: true)
        XCTAssertNotEqual(ended, start, "a gameEnded flip")
        cache.invalidate()
        XCTAssertNotEqual(cache.generation(gameEnded: true), ended, "an explicit invalidation")
    }

    /// Runs what is queued on main, a few levels of `main.async` deep.
    private func drainMainQueue() {
        for _ in 0..<3 {
            var done = false
            DispatchQueue.main.async { done = true }
            let deadline = Date().addingTimeInterval(1)
            while !done && Date() < deadline {
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
            }
        }
    }

    private func spinMainRunLoop(for interval: TimeInterval) {
        let deadline = Date().addingTimeInterval(interval)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
    }

    private func token(_ color: HighlightColor?) -> Int {
        switch color {
        case .none?: return 0
        case .teal?: return 1
        case .orange?: return 2
        case .green?: return 3
        case nil: return -1
        }
    }
}

/// What a closure running on another queue saw.
private final class Recorder<Value> {
    private let lock = NSLock()
    private var recorded = [Value]()

    var values: [Value] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func append(_ value: Value) {
        lock.lock()
        recorded.append(value)
        lock.unlock()
    }
}
