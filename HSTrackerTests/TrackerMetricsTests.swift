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
        XCTAssertFalse(WindowManager.shouldOrderFront(isVisible: true, isOccluded: false,
                                                      attributesChanged: false,
                                                      pendingReorder: false))
    }

    /// The four reasons that still have to re-front the window: it is hidden,
    /// something is covering it, one of its attributes was just rewritten, or a
    /// Space / Hearthstone event raised the reorder generation.
    func testEveryReorderReasonStillOrdersTheWindowFront() {
        XCTAssertTrue(WindowManager.shouldOrderFront(isVisible: false, isOccluded: false,
                                                     attributesChanged: false, pendingReorder: false))
        XCTAssertTrue(WindowManager.shouldOrderFront(isVisible: true, isOccluded: true,
                                                     attributesChanged: false, pendingReorder: false))
        XCTAssertTrue(WindowManager.shouldOrderFront(isVisible: true, isOccluded: false,
                                                     attributesChanged: true, pendingReorder: false))
        XCTAssertTrue(WindowManager.shouldOrderFront(isVisible: true, isOccluded: false,
                                                     attributesChanged: false, pendingReorder: true))
    }

    func testSpaceAndHearthstoneEventsAreReorderReasons() {
        for event in [Events.space_changed, Events.hearthstone_active, Events.hearthstone_deactived,
                      Events.hearthstone_running, Events.hearthstone_closed] {
            XCTAssertTrue(WindowManager.reorderEvents.contains(event),
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
}
