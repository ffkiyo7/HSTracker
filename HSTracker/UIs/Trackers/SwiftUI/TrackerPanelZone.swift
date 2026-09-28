//
//  TrackerPanelZone.swift
//  HSTracker
//
//  REFORK S4: the fork's tracker inside upstream's `TrackerPanelView`. The
//  upstream panel stays the shell — placement, drag and resize, hover and
//  interactive regions, graveyard details, the link-deck prompt — and only the
//  card lists and the rows around them are ours.
//
//  What the fork block (`TrackerView`) replaces: the player's deck title, wins,
//  top / bottom lenses, card list and card counter, and the opponent's card
//  list, card counter and related-cards lens. It sits where the first of those
//  is in the panel order. The opponent's hero bar and the arena package and
//  Godfrey lenses stay upstream's views, sized to the fork's panel width, and
//  their rows share the fork's row grid. Draw chances, the graveyard counter
//  and the sideboard band are not drawn, as on dev; a sideboard is shown by
//  hovering its owner's row instead (`showSideboardTooltip`).
//

import AppKit
import SwiftUI

/// The upstream panel around the fork's block as of the last relayout, in the
/// panel's own (pre-`scaleEffect`) units.
struct TrackerZoneShell: Equatable {
    let width: CGFloat
    let cardHeight: CGFloat
    let smallFrameHeight: CGFloat
    let bigFrameHeight: CGFloat
    let heroHeight: CGFloat
    /// Upstream's lens and sideboard views are fixed to `SizeHelper.trackerWidth`;
    /// they are laid out at that width and scaled by this onto the panel's.
    let fitScale: CGFloat
    let sections: [TrackerPanelLayout.Section]

    static func == (lhs: TrackerZoneShell, rhs: TrackerZoneShell) -> Bool {
        lhs.width == rhs.width
            && lhs.cardHeight == rhs.cardHeight
            && lhs.smallFrameHeight == rhs.smallFrameHeight
            && lhs.bigFrameHeight == rhs.bigFrameHeight
            && lhs.heroHeight == rhs.heroHeight
            && lhs.fitScale == rhs.fitScale
            && lhs.sections.map(\.kind) == rhs.sections.map(\.kind)
            && lhs.sections.map(\.height) == rhs.sections.map(\.height)
    }
}

/// The upstream frames at the fork's panel width. Upstream's frame PNGs are
/// drawn at 217 x 40 (or x 71) and keep that aspect, so a frame that is as wide
/// as the panel is this tall.
private struct TrackerZoneFrames {
    let width: CGFloat
    let small: CGFloat
    let big: CGFloat
    let hero: CGFloat
    let fitScale: CGFloat

    init(width: CGFloat) {
        self.width = width
        small = width * 40 / 217
        big = width * 71 / 217
        // The hero bar is one card row, like each header line (dev 1745adfa).
        hero = TrackerMetrics.rowHeight(panelWidth: width)
        fitScale = width / max(SizeHelper.trackerWidth, 1)
    }

    /// A lens's header plus the five points `DeckLens` leaves under its list.
    var lensChrome: CGFloat { small + 5 * fitScale }
}

extension TrackerViewModel {
    convenience init(playerType: PlayerType) {
        self.init()
        self.playerType = playerType
        hoverKind = playerType == .opponent ? .opponentDeck : .playerDeck
        propagatePlayerType()
        propagateHoverKind()
    }
}

/// The header's deck records, cached across refreshes: the relayout runs on
/// every tracker update and `RealmHelper.getDeck` is not free. Dropped together
/// with the upstream record label (`DeckRecordLabelCache`), so the two never
/// show different games' records.
final class TrackerHeaderStats {
    var needsRefresh = false
    private var generation: Int?
    private var deckId: String?
    private var opponentClass: CardClass?
    private var overall: StatsDeckRecord?
    private var matchup: StatsDeckRecord?

    func records(game: Game) -> (overall: StatsDeckRecord?, matchupClass: CardClass?, matchup: StatsDeckRecord?) {
        let generation = DeckRecordLabelCache.shared.generation(gameEnded: game.gameEnded)
        if self.generation != generation {
            self.generation = generation
            needsRefresh = true
        }
        guard Settings.showWinLossRatio else {
            deckId = nil
            overall = nil
            matchup = nil
            return (nil, nil, nil)
        }
        guard let currentDeckId = game.currentDeck?.id else {
            return (nil, nil, nil)
        }
        let opponentClass = game.opponent.playerClassId.flatMap { Cards.hero(byId: $0)?.playerClass }
        if needsRefresh || deckId != currentDeckId || self.opponentClass != opponentClass {
            if let deck = RealmHelper.getDeck(with: currentDeckId) {
                overall = StatsHelper.getDeckRecord(deck: deck, againstClass: .neutral, mode: .all)
                matchup = opponentClass.map { StatsHelper.getDeckRecord(deck: deck, againstClass: $0, mode: .all) }
            } else {
                overall = nil
                matchup = nil
            }
            deckId = currentDeckId
            self.opponentClass = opponentClass
            needsRefresh = false
        }
        return (overall, opponentClass, matchup)
    }
}

extension TrackerPanelViewModel {
    /// `update(cards:top:bottom:...)` plus the zone split. `Game` calls this one;
    /// the rows go into the fork's block here and are laid out by
    /// `relayoutZonePanel()` at the end of the same main-thread block, which is
    /// what lets T8 decide rows and geometry together.
    func update(cards: [Card], top: [Card], bottom: [Card], sideboards: [Sideboard], relatedCards: [Card],
                packageCards: [Card] = [], packageLabel: String = "", godfreyCards: [Card] = [],
                groups: CardZoneGroups?, reset: Bool = false) {
        update(cards: cards, top: top, bottom: bottom, sideboards: sideboards, relatedCards: relatedCards,
               packageCards: packageCards, packageLabel: packageLabel, godfreyCards: godfreyCards,
               reset: reset)
        guard Settings.groupCardsByZone else { return }
        if reset && playerType == .player {
            zonePanel.headerStats.needsRefresh = true
        }
        zonePanel.update(cards: cards, top: top, bottom: bottom, relatedCards: relatedCards, groups: groups)
    }

    /// Lays the fork's block out inside the panel's box and records the shell
    /// `TrackerPanelLayout` reads back. Main thread; called at the end of each
    /// tracker update and whenever the box or the canvas changes.
    func relayoutZonePanel(canvasSize: CGSize? = nil) {
        let zone = zonePanel
        if let canvasSize, RootOverlayView.isUsableCanvas(canvasSize) {
            zone.canvasSize = canvasSize
        }
        guard Settings.groupCardsByZone else {
            if zone.shell != nil {
                objectWillChange.send()
                zone.shell = nil
            }
            return
        }
        let canvas = zone.canvasSize ?? SizeHelper.hearthstoneWindow.frame.size
        guard RootOverlayView.isUsableCanvas(canvas) else { return }

        let width = TrackerMetrics.panelWidth(windowWidth: canvas.width,
                                              windowHeight: canvas.height,
                                              cardSize: Settings.cardSize)
        let rowHeight = TrackerMetrics.rowHeight(panelWidth: width)
        let frames = TrackerZoneFrames(width: width)
        let plan = zonePlan(frames)

        feedZoneHeader(lineHeight: rowHeight)
        zone.updateLayout(availableHeight: zoneBoxHeight(canvasHeight: canvas.height),
                          panelWidth: width,
                          frameHeight: TrackerMetrics.sectionHeaderHeight(rowHeight: rowHeight),
                          reserveGraveyardRow: false,
                          extraFixedHeight: plan.reduce(0) { $0 + $1.fixed },
                          extraCards: plan.reduce(0) { $0 + $1.cards })

        let cardHeight = zone.layout.cardHeight
        let sections = plan.map { entry in
            TrackerPanelLayout.Section(kind: entry.kind,
                                       height: entry.kind == .zone
                                        ? zone.layout.contentHeight
                                        : entry.fixed + CGFloat(entry.cards) * cardHeight)
        }
        let shell = TrackerZoneShell(width: width,
                                     cardHeight: cardHeight,
                                     smallFrameHeight: frames.small,
                                     bigFrameHeight: frames.big,
                                     heroHeight: frames.hero,
                                     fitScale: frames.fitScale,
                                     sections: sections)
        if zone.shell != shell {
            // The panel lays itself out from the shell, which is not published.
            objectWillChange.send()
            zone.shell = shell
        }
    }

    /// Upstream's `PlayerStackHeight`: the box the stack fits into, in its own
    /// units.
    fileprivate func zoneBoxHeight(canvasHeight: CGFloat) -> CGFloat {
        let scale = max(CGFloat(scaling) / 100.0, 0.01)
        return max(canvasHeight * CGFloat(height) / 100.0 / scale, 0)
    }

    /// The panel's sections in order, with what each costs the box: a fixed
    /// height and a number of rows on the shared grid.
    private func zonePlan(_ frames: TrackerZoneFrames) -> [(kind: TrackerPanelLayout.Kind, fixed: CGFloat, cards: Int)] {
        let isOpponent = playerType == .opponent
        let replaced: Set<DeckPanel> = isOpponent
            ? [.cards, .cardCounter]
            : [.deckTitle, .wins, .cardsTop, .cards, .cardsBottom, .cardCounter]
        var plan: [(kind: TrackerPanelLayout.Kind, fixed: CGFloat, cards: Int)] = []
        var placed = false
        for panel in panelOrder {
            if replaced.contains(panel) {
                if !placed {
                    plan.append((.zone, 0, 0))
                    placed = true
                }
                continue
            }
            // Draw chances, the graveyard counter and the sideboard band are
            // left out whatever their settings say (user, 09-26): the graveyard
            // details go with the counter, since it is their hover region.
            if panel == .deckTitle && Settings.showOpponentClassInTracker && playerClassId != nil {
                plan.append((.deckPanel(panel), frames.hero, 0))
            }
        }
        if !placed {
            plan.append((.zone, 0, 0))
        }
        if isOpponent && !Settings.hideOpponentArenaPackages && !packageCards.cards.isEmpty {
            plan.append((.packageLens, frames.lensChrome, packageCards.cards.count))
        }
        if !godfreyCards.cards.isEmpty {
            plan.append((.godfreyLens, frames.lensChrome, godfreyCards.cards.count))
        }
        return plan
    }

    /// The three-row header: deck name and counts, deck win rate, and the
    /// record against the opponent's class. The opponent's header only carries
    /// the counts.
    private func feedZoneHeader(lineHeight: CGFloat) {
        let game = AppDelegate.instance().coreManager.game
        let isPlayer = playerType == .player
        var records: (overall: StatsDeckRecord?, matchupClass: CardClass?, matchup: StatsDeckRecord?) = (nil, nil, nil)
        if isPlayer {
            records = zonePanel.headerStats.records(game: game)
        }
        let heroCardId = isPlayer ? (playerClassId ?? "") : ""
        zonePanel.header.update(showDeckName: isPlayer && Settings.showDeckNameInTracker,
                                playerClass: Cards.hero(byId: heroCardId)?.playerClass
                                    ?? game.currentDeck?.playerClass,
                                heroCardId: heroCardId,
                                handCount: handCount,
                                deckCount: deckCount,
                                showCardCount: isPlayer ? Settings.showPlayerCardCount : Settings.showOpponentCardCount,
                                overallRecord: records.overall,
                                matchupClass: records.matchupClass,
                                matchupRecord: records.matchup,
                                lineHeight: lineHeight)
    }
}

extension TrackerPanelLayout {
    /// The layout of a panel that draws the fork's block: the sections recorded
    /// at the last relayout, in the box the panel has right now. `nil` while the
    /// zone switch is off or the block has not been laid out yet, which leaves
    /// the panel on upstream's own layout.
    init?(zonePanelOf viewModel: TrackerPanelViewModel, canvasHeight: CGFloat) {
        guard Settings.groupCardsByZone, let shell = viewModel.zonePanel.shell else { return nil }
        width = shell.width
        cardHeight = shell.cardHeight
        smallFrameHeight = shell.smallFrameHeight
        bigFrameHeight = shell.bigFrameHeight
        boxHeight = viewModel.zoneBoxHeight(canvasHeight: canvasHeight)
        sections = shell.sections
    }

    var isZonePanel: Bool {
        sections.contains { $0.kind == .zone }
    }
}

/// The panel's sections when it draws the fork's block. It stands in for the
/// `VStack` `TrackerPanelView.panel` lays upstream's sections out in, and is
/// also where the block is kept laid out against the panel's box and wired to
/// the hover handler's synergy highlight.
struct TrackerZonePanelStack: View {
    // Observed, not just held: the relayout and highlight hooks below have to
    // see changes that leave `layout` as it was.
    @ObservedObject var viewModel: TrackerPanelViewModel
    @ObservedObject var zone: TrackerViewModel
    let layout: TrackerPanelLayout
    let canvasSize: CGSize
    @ObservedObject var hoverHandler: TrackerCardHoverHandler

    private struct RelayoutInputs: Equatable {
        let canvasSize: CGSize
        let height: Double
        let scaling: Double
        let order: [DeckPanel]
    }

    private var inputs: RelayoutInputs {
        RelayoutInputs(canvasSize: canvasSize, height: viewModel.height,
                       scaling: viewModel.scaling, order: viewModel.panelOrder)
    }

    private var hoverKind: TrackerRowHoverKind {
        viewModel.playerType == .opponent ? .opponentDeck : .playerDeck
    }

    private var fitScale: CGFloat { max(zone.shell?.fitScale ?? 1, 0.01) }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(layout.sections, id: \.kind) { section in
                sectionView(section)
                    .frame(width: layout.width, height: section.height, alignment: .top)
            }
        }
        // The sections below the block follow its T8 glide on the same verdict.
        .animation(TrackerMotion.isEnabled ? TrackerMotion.animation : nil,
                   value: zone.motionGeneration)
        .onAppear {
            viewModel.relayoutZonePanel(canvasSize: canvasSize)
            zone.setHighlight(hoverHandler.deckHighlight)
        }
        .onChange(of: inputs) { _, _ in
            // Dragging the resize grip, a scaling or order change, or the canvas
            // resizing: no rows moved, so this never animates.
            viewModel.relayoutZonePanel(canvasSize: canvasSize)
        }
        .onChange(of: hoverHandler.highlightVersion) { _, _ in
            zone.setHighlight(hoverHandler.deckHighlight)
        }
    }

    @ViewBuilder
    private func sectionView(_ section: TrackerPanelLayout.Section) -> some View {
        switch section.kind {
        case .zone:
            TrackerView(viewModel: zone,
                        topTitle: String.localizedString("On Top", comment: ""),
                        bottomTitle: String.localizedString("On Bottom", comment: ""),
                        relatedTitle: String.localizedString("Related_Cards", comment: ""),
                        deckTitle: String.localizedString("Zone_Deck", comment: ""),
                        handTitle: String.localizedString("Zone_Hand", comment: ""),
                        playedTitle: String.localizedString("Zone_Played", comment: ""))
        case .deckPanel(.deckTitle):
            CardTileView(card: heroCard, playerType: .hero,
                         playerName: viewModel.playerName,
                         rowHeight: zone.shell?.heroHeight ?? section.height)
        case .packageLens:
            lens(viewModel.packageCards, label: viewModel.packageLabel,
                 icon: .arenasmith, isPremium: true, height: section.height)
        case .godfreyLens:
            lens(viewModel.godfreyCards,
                 label: String.localizedString("DeckLens_Label_Overdrawn", comment: ""),
                 height: section.height)
        default:
            EmptyView()
        }
    }

    private func lens(_ content: TrackerCardListContent, label: String,
                      icon: DeckLensIcon = .lens, isPremium: Bool = false,
                      height: CGFloat) -> some View {
        fitted(TrackerDeckLensView(cards: content.cards, label: label, icon: icon, isPremium: isPremium,
                                   playerType: viewModel.playerType,
                                   cardHeight: layout.cardHeight / fitScale,
                                   frameHeight: layout.smallFrameHeight / fitScale,
                                   reset: content.reset, flashing: content.flashing,
                                   version: content.version, hoverKind: hoverKind),
               height: height)
    }

    /// An upstream view fixed to `SizeHelper.trackerWidth`, laid out at that
    /// width and scaled onto the panel's.
    private func fitted<Content: View>(_ content: Content, height: CGFloat) -> some View {
        content
            .frame(width: layout.width / fitScale, height: height / fitScale, alignment: .top)
            .scaleEffect(fitScale, anchor: .topLeading)
            .frame(width: layout.width, height: height, alignment: .topLeading)
    }

    private var heroCard: Card? {
        let card = Cards.hero(byId: viewModel.playerClassId ?? "")
        card?.count = 1
        // The opponent's bar is drawn costless, as upstream's panel draws it.
        if viewModel.playerType == .opponent {
            card?.cost = -1
        }
        return card
    }
}

// MARK: - Sideboards on hover (dev 8dcf2f47)

extension TrackerPanelViewModel {
    /// The sideboard a hovered row's card carries, from the snapshot the last
    /// tracker update stored. Any owner matches, not just the two upstream's
    /// band knows: a customised Zilliax is listed as a copy of its cosmetic
    /// module, which `deckbuildingCard` maps back to the owner id.
    func sideboardCards(for card: Card) -> [Card]? {
        guard Settings.groupCardsByZone, playerType == .player, !Settings.hidePlayerSideboards else {
            return nil
        }
        let ownerId = card.deckbuildingCard.id
        guard let sideboard = sideboards.first(where: { $0.ownerCardId == ownerId }),
              !sideboard.cards.isEmpty else {
            return nil
        }
        return sideboard.cards
    }
}

extension TrackerCardHoverHandler {
    /// Shows the hovered card's sideboard in the related-cards grid, which it
    /// takes over when the card has both. `false` leaves the grid to upstream.
    /// Main thread: called from the hover's `DelayedTooltip`, and reads what
    /// `Game.updatePlayerTracker`'s main block stored.
    func showSideboardTooltip(card: Card, anchor rect: NSRect) -> Bool {
        let game = AppDelegate.instance().coreManager.game
        guard playerType == .player,
              let cards = game.windowManager.rootOverlay?.viewModel.playerTracker.sideboardCards(for: card) else {
            return false
        }
        let tooltipGridCards = game.windowManager.tooltipGridCards
        tooltipGridCards.setCardIdsFromCards(cards)
        tooltipGridCards.setTitle(card.name)
        tooltipGridCards.setScale(1)
        tooltipGridCards.setPoolStatistics(nil, relatedCardsSummary: nil, hasLargePool: false)
        RelatedCardsRightClickMonitor.shared.clearHoveredLargePool()

        // Placed as `setRelatedCardsTooltip` places the related cards.
        let hearthstoneRect = SizeHelper.hearthstoneWindow.frame
        let width = CGFloat(tooltipGridCards.gridWidth)
        let height = CGFloat(tooltipGridCards.gridHeight)
        let screen = NSScreen.screens.first { $0.frame.intersects(rect) } ?? NSScreen.main
        let maxY = screen?.frame.maxY ?? hearthstoneRect.maxY
        let y = rect.minY + height > maxY ? maxY - height : rect.minY
        let x = rect.minX < hearthstoneRect.midX ? rect.maxX : rect.minX - width
        tooltipGridCards.show(frame: NSRect(x: x, y: y, width: width, height: height))
        return true
    }
}
