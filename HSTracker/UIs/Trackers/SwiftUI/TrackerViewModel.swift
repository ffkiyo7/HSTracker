//
//  TrackerViewModel.swift
//  HSTracker
//
//  Root view model of the fork's block inside the upstream tracker panel: owns
//  the header and the card lists, and computes the row grid (docs/PLAN.md 1.4).
//  `TrackerPanelViewModel.zonePanel` holds one per side.
//

import AppKit
import Foundation
import SwiftUI

/// One frame of tracker geometry. It lives in the view model rather than in the
/// view's `GeometryReader` because the upstream panel's section heights, hover
/// regions and the link-deck panel are derived from the very same numbers — two
/// independent computations would be free to drift apart.
struct TrackerLayout: Equatable {
    var cardHeight: CGFloat = 0
    /// Panel width for this frame: always the full panel since rows stopped
    /// compressing (phase2-scroll-collapse).
    var barWidth: CGFloat = 0
    var opacity: CGFloat = 1
    var headerHeight: CGFloat = 0
    var topHeight: CGFloat = 0
    var listHeight: CGFloat = 0
    var deckHeight: CGFloat = 0
    var handHeight: CGFloat = 0
    var playedHeight: CGFloat = 0
    var bottomHeight: CGFloat = 0
    var relatedHeight: CGFloat = 0
    /// The clipped window the card sections scroll in, under the pinned header.
    /// Equal to `scrollContentHeight` whenever everything fits.
    var viewportHeight: CGFloat = 0

    /// Every card section stacked, i.e. what scrolls.
    var scrollContentHeight: CGFloat {
        topHeight + listHeight + deckHeight + handHeight + playedHeight + bottomHeight + relatedHeight
    }

    /// What the block occupies in the panel: the header plus the viewport.
    var contentHeight: CGFloat {
        headerHeight + viewportHeight
    }

    var maxScroll: CGFloat {
        max(scrollContentHeight - viewportHeight, 0)
    }
}

final class TrackerViewModel: ObservableObject {
    /// Bottom padding under a section's card list, as in the old
    /// `count * cardHeight + frameHeight + 5`.
    private static let sectionPadding: CGFloat = 5

    let header = TrackerHeaderViewModel()
    let cards = TrackerCardListViewModel()
    let deck = TrackerCardListViewModel()
    let hand = TrackerCardListViewModel()
    let played = TrackerCardListViewModel()
    let top = TrackerCardListViewModel()
    let bottom = TrackerCardListViewModel()
    let related = TrackerCardListViewModel()

    @Published private(set) var layout = TrackerLayout()
    /// T8 review 1: one verdict for the whole panel, published after both the
    /// rows and the geometry of this refresh are known. The view animates only
    /// the updates that bump it, so rows and section frames can no longer
    /// disagree — a grid that moves (card size, window size) means nothing
    /// moves.
    @Published private(set) var motionGeneration = 0
    /// How far the card sections are scrolled, in `[0, layout.maxScroll]`.
    /// Clamped by `updateLayout` in the same main-thread block that publishes
    /// the layout, so the view never sees one without the other.
    @Published private(set) var scrollOffset: CGFloat = 0
    /// Set by a new game's refresh and applied by the `updateLayout` that
    /// follows it, so the jump back to the top lands with that refresh's rows.
    private var pendingScrollReset = false

    /// Same-value skip: the seven lists all publish `playerType`, so a blind
    /// re-assignment on every refresh was seven `objectWillChange` for nothing.
    var playerType: PlayerType = .player {
        didSet {
            guard oldValue != playerType else { return }
            propagatePlayerType()
        }
    }

    /// Which hover the rows raise on the overlay canvas. Set once, by the panel
    /// that owns this block.
    var hoverKind: TrackerRowHoverKind = .none {
        didSet {
            propagateHoverKind()
        }
    }

    // Also called from `init(playerType:)`, where the observers above do not run.
    func propagatePlayerType() {
        for list in lists where list.playerType != playerType {
            list.playerType = playerType
        }
    }

    func propagateHoverKind() {
        for list in lists {
            list.hoverKind = hoverKind
        }
    }

    /// The upstream panel around this block, as of the last relayout
    /// (TrackerPanelZone.swift). `nil` until the block has been laid out once,
    /// which keeps the upstream panel on its own layout until then.
    var shell: TrackerZoneShell?
    /// The overlay canvas the panel last measured itself against.
    var canvasSize: CGSize?
    let headerStats = TrackerHeaderStats()

    private var lists: [TrackerCardListViewModel] { [cards, deck, hand, played, top, bottom, related] }

    /// The headed sections, by the name their collapsed state is stored under.
    private var collapsibleSections: [(key: String, list: TrackerCardListViewModel)] {
        [("top", top), ("deck", deck), ("hand", hand), ("played", played), ("bottom", bottom), ("related", related)]
    }

    func loadCollapsedSections() {
        let stored = Set(playerType == .opponent ? Settings.opponentTrackerCollapsedSections
                            : Settings.playerTrackerCollapsedSections)
        for (key, list) in collapsibleSections where list.isCollapsed != stored.contains(key) {
            list.isCollapsed = stored.contains(key)
        }
    }

    /// Main thread. The caller relays the panel out afterwards; the section
    /// jumps there in one frame, since no row asked to move.
    func toggleCollapsed(_ list: TrackerCardListViewModel) {
        guard collapsibleSections.contains(where: { $0.list === list }) else { return }
        list.isCollapsed.toggle()
        let collapsed = collapsibleSections.filter { $0.list.isCollapsed }.map(\.key)
        if playerType == .opponent {
            Settings.opponentTrackerCollapsedSections = collapsed
        } else {
            Settings.playerTrackerCollapsedSections = collapsed
        }
    }

    /// Main thread: the scroll-wheel monitors hop there before calling.
    func scroll(by delta: CGFloat) {
        let next = min(max(scrollOffset + delta, 0), layout.maxScroll)
        if next != scrollOffset {
            scrollOffset = next
        }
    }

    func resetScroll() {
        pendingScrollReset = true
    }

    /// The synergy highlight of `TrackerCardHoverHandler`, as upstream's flat
    /// list applies it: to the rows with copies left in the deck, handing the
    /// closure those same rows as the deck it reasons about (e.g. Taelan
    /// Fordring's highest cost minion). In zone mode that is the deck section
    /// alone; the hand section would light up cards that are no longer in the
    /// deck and hand the closure the hand as if it were the deck.
    func setHighlight(_ fn: ((Card, [Card]) -> HighlightColor)?) {
        for list in [cards, deck] {
            list.setHighlight(fn)
        }
    }

    /// The main list and the three zone sections are mutually exclusive: exactly
    /// one of them is fed, the other is emptied, so no extra published flag is
    /// needed to tell the view which one to draw.
    func update(cards: [Card], top: [Card], bottom: [Card], relatedCards: [Card],
                groups: CardZoneGroups?) {
        if let groups {
            self.cards.update(cards: [])
            deck.update(cards: groups.deck)
            hand.update(cards: groups.hand)
            played.update(cards: groups.played)
        } else {
            self.cards.update(cards: cards)
            deck.update(cards: [])
            hand.update(cards: [])
            played.update(cards: [])
        }
        self.top.update(cards: top)
        self.bottom.update(cards: bottom)
        self.related.update(cards: relatedCards)
    }

    /// - Parameters:
    ///   - availableHeight: the panel's box, i.e. upstream's `PlayerStackHeight`.
    ///   - panelWidth: the panel width `TrackerMetrics` derives from the overlay
    ///     canvas. The row height follows from it and the fixed aspect.
    ///   - frameHeight: one section header / header row.
    ///   - reserveGraveyardRow: reserves one `frameHeight` out of the viewport;
    ///     the panel passes the graveyard counter in `extraFixedHeight`.
    ///   - extraFixedHeight / extraCards: the upstream sections drawn around this
    ///     block. They share the box, and their card rows the grid.
    func updateLayout(availableHeight: CGFloat,
                      panelWidth: CGFloat,
                      frameHeight: CGFloat,
                      reserveGraveyardRow: Bool,
                      extraFixedHeight: CGFloat = 0,
                      extraCards: Int = 0) {
        for list in lists {
            list.syncAppearance()
        }

        let showTop = top.count > 0 && Settings.showPlayerCardsTop
        let showBottom = bottom.count > 0 && Settings.showPlayerCardsBottom
        let showRelated = related.count > 0 && Settings.showOpponentRelatedCards
        let showDeck = deck.count > 0
        let showHand = hand.count > 0
        let showPlayed = played.count > 0

        let headerHeight = header.height
        // Rows keep the base height and the panel's width; what does not fit
        // scrolls instead of shrinking (phase2-scroll-collapse A1).
        let cardHeight = TrackerMetrics.rowHeight(panelWidth: panelWidth)
        let barWidth = cardHeight * TrackerMetrics.aspect

        var next = TrackerLayout(
            cardHeight: cardHeight,
            barWidth: barWidth,
            opacity: TrackerDiagnostics.panelOpacity(setting: Settings.trackerOpacity),
            headerHeight: headerHeight,
            topHeight: showTop ? sectionHeight(top, cardHeight, frameHeight) : 0,
            listHeight: CGFloat(cards.count) * cardHeight,
            deckHeight: showDeck ? sectionHeight(deck, cardHeight, frameHeight) : 0,
            handHeight: showHand ? sectionHeight(hand, cardHeight, frameHeight) : 0,
            playedHeight: showPlayed ? sectionHeight(played, cardHeight, frameHeight) : 0,
            bottomHeight: showBottom ? sectionHeight(bottom, cardHeight, frameHeight) : 0,
            relatedHeight: showRelated ? sectionHeight(related, cardHeight, frameHeight) : 0
        )
        // The box minus the header and the upstream sections that share it (the
        // opponent's hero bar above, the package / Godfrey lenses below). Those
        // lenses cannot scroll, so when they leave less than three rows the
        // viewport keeps three and the panel runs past its box instead.
        var fixed = headerHeight + extraFixedHeight + CGFloat(extraCards) * cardHeight
        if reserveGraveyardRow {
            fixed += frameHeight
        }
        let body = next.scrollContentHeight
        let room = availableHeight - fixed
        next.viewportHeight = body <= room ? body : max(room, min(body, 3 * cardHeight))

        var offset = scrollOffset
        if pendingScrollReset {
            pendingScrollReset = false
            offset = 0
        }
        offset = min(max(offset, 0), next.maxScroll)
        // A2 / A7: a refresh that also has to move the scroll position goes in
        // one frame, so no row in flight can glide out of or into the viewport
        // while the content jumps under it.
        let scrollMoves = offset != scrollOffset

        // T8 review 1. The rows of this refresh went in earlier in this same
        // main-thread block (Game.updatePlayerTracker → `update(...groups:)` →
        // `relayoutZonePanel()`), but nothing has animated yet. This is the
        // only place that knows both halves, so it
        // is the only place that decides — and it decides once, for the rows
        // and the frames around them together.
        let animates = TrackerMotion.isEnabled
            && !scrollMoves
            && lists.contains { $0.wantsMotion }
            && TrackerMotion.layoutCanAnimate(from: layout,
                                              to: next,
                                              sectionChrome: frameHeight + Self.sectionPadding)
        if next != layout {
            layout = next
        }
        if scrollMoves {
            scrollOffset = offset
        }
        if animates {
            motionGeneration &+= 1
        }
        // Every list, not just the ones that moved: the verdict also clears
        // what a refused refresh left pending.
        for list in lists {
            list.commitMotion(animates: animates)
        }

        if header.barWidth != barWidth {
            header.barWidth = barWidth
        }

        for list in lists {
            if list.rowHeight != cardHeight {
                list.rowHeight = cardHeight
            }
            if list.barWidth != barWidth {
                list.barWidth = barWidth
            }
            if list.sectionHeaderHeight != frameHeight {
                list.sectionHeaderHeight = frameHeight
            }
        }
    }

    private func sectionHeight(_ list: TrackerCardListViewModel,
                               _ cardHeight: CGFloat,
                               _ frameHeight: CGFloat) -> CGFloat {
        // B1: a collapsed section is its header alone, without the padding.
        guard !list.isCollapsed else { return frameHeight }
        return CGFloat(list.count) * cardHeight + frameHeight + Self.sectionPadding
    }
}
