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
    /// Panel width for this frame. When the adaptive row height kicks in, the
    /// bars narrow by the same factor so the 8.14 : 1 aspect never changes
    /// (PLAN 2.8 third cause). Purely a drawing width — the panel's box and its
    /// hover / drag regions keep the uncompressed width.
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

    var contentHeight: CGFloat {
        headerHeight + topHeight + listHeight + deckHeight + handHeight + playedHeight
            + bottomHeight + relatedHeight
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
    /// disagree — under compression a single card changes `cardHeight`, and a
    /// grid that moves means nothing moves.
    @Published private(set) var motionGeneration = 0

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

    /// The synergy highlight of `TrackerCardHoverHandler`. The main list is one
    /// list in flat mode and three in zone mode; the highlight covers whichever
    /// is being drawn.
    func setHighlight(_ fn: ((Card, [Card]) -> HighlightColor)?) {
        for list in [cards, deck, hand, played] {
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
    ///   - panelWidth: the uncompressed panel width `TrackerMetrics` derives from
    ///     the overlay canvas. The base row height follows from it and the fixed
    ///     aspect.
    ///   - frameHeight: one section header / header row.
    ///   - reserveGraveyardRow: reserves one `frameHeight` in the compression
    ///     budget; the panel passes the graveyard counter in `extraFixedHeight`.
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
        var offset = headerHeight + extraFixedHeight
        if reserveGraveyardRow {
            offset += frameHeight
        }
        var totalCards = cards.count + extraCards
        // A section costs its header *and* its bottom padding. Leaving the
        // padding out of the budget (as the pre-V1 code did) let contentHeight
        // overshoot `availableHeight` by 5 per section once compression kicked
        // in, and the panel spilled out of its box.
        let sectionOffset = frameHeight + Self.sectionPadding
        if showDeck {
            offset += sectionOffset
            totalCards += deck.count
        }
        if showHand {
            offset += sectionOffset
            totalCards += hand.count
        }
        if showPlayed {
            offset += sectionOffset
            totalCards += played.count
        }
        if showTop {
            offset += sectionOffset
            totalCards += top.count
        }
        if showBottom {
            offset += sectionOffset
            totalCards += bottom.count
        }
        if showRelated {
            offset += sectionOffset
            totalCards += related.count
        }

        // Upstream's adaptive row height: rows shrink so that everything still
        // fits when the deck list is long (Tracker.swift, pre-T6).
        let baseCardHeight = TrackerMetrics.rowHeight(panelWidth: panelWidth)
        var cardHeight = baseCardHeight
        if totalCards > 0 {
            cardHeight = max(min(cardHeight, (availableHeight - offset) / CGFloat(totalCards)), 1)
        }
        let barWidth = cardHeight * TrackerMetrics.aspect

        let next = TrackerLayout(
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
        // T8 review 1. The rows of this refresh went in earlier in this same
        // main-thread block (Game.updatePlayerTracker → `update(...groups:)` →
        // `relayoutZonePanel()`), but nothing has animated yet. This is the
        // only place that knows both halves, so it
        // is the only place that decides — and it decides once, for the rows
        // and the frames around them together.
        let animates = TrackerMotion.isEnabled
            && lists.contains { $0.wantsMotion }
            && TrackerMotion.layoutCanAnimate(from: layout,
                                              to: next,
                                              sectionChrome: frameHeight + Self.sectionPadding)
        if next != layout {
            layout = next
        }
        if animates {
            motionGeneration &+= 1
        }
        // Every list, not just the ones that moved: the verdict also clears
        // what a refused refresh left pending.
        for list in lists {
            list.commitMotion(animates: animates)
        }

        // The header's two fixed columns are a fraction of the panel, so it
        // needs the compressed width too (V1 left them frozen to the base).
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
        CGFloat(list.count) * cardHeight + frameHeight + Self.sectionPadding
    }
}
