//
//  TrackerViewModel.swift
//  HSTracker
//
//  Root view model of the SwiftUI tracker: owns the header and the four card
//  lists, and computes the geometry Tracker.updateFrames() used to derive by
//  hand (docs/PLAN.md 1.4).
//

import AppKit
import Foundation

/// One frame of tracker geometry. It lives in the view model rather than in the
/// view's `GeometryReader` because `Tracker.bottomY` (the opponent tracking
/// area) is derived from the very same numbers — two independent computations
/// would be free to drift apart.
struct TrackerLayout: Equatable {
    var cardHeight: CGFloat = 0
    /// Panel width for this frame. When the adaptive row height kicks in, the
    /// bars narrow by the same factor so the 8.14 : 1 aspect never changes
    /// (PLAN 2.8 third cause). Purely a drawing width — the window frame and
    /// therefore `Tracker.bottomY` / the tracking area are unaffected.
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

    var playerType: PlayerType = .player {
        didSet {
            for list in lists {
                list.playerType = playerType
            }
        }
    }

    private var lists: [TrackerCardListViewModel] { [cards, deck, hand, played, top, bottom, related] }

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
    ///   - availableHeight: the window below the AppKit hero bar, i.e. the root
    ///     host's own height.
    ///   - panelWidth: the tracker window's own width, i.e. the uncompressed
    ///     panel width `SizeHelper.trackerWidth` derived from the Hearthstone
    ///     window. The base row height follows from it and the fixed aspect.
    ///   - frameHeight: one section header / header row.
    ///   - reserveGraveyardRow: the graveyard counter is not drawn on this path,
    ///     but the old layout still reserved its row in the compression budget.
    func updateLayout(availableHeight: CGFloat,
                      panelWidth: CGFloat,
                      frameHeight: CGFloat,
                      reserveGraveyardRow: Bool) {
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
        var offset = headerHeight
        if reserveGraveyardRow {
            offset += frameHeight
        }
        var totalCards = cards.count
        // A section costs its header *and* its bottom padding. Leaving the
        // padding out of the budget (as the pre-V1 code did) let contentHeight
        // overshoot `availableHeight` by 5 per section once compression kicked
        // in, which pushed `Tracker.bottomY` negative.
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
            opacity: CGFloat(Settings.trackerOpacity / 100.0),
            headerHeight: headerHeight,
            topHeight: showTop ? sectionHeight(top, cardHeight, frameHeight) : 0,
            listHeight: CGFloat(cards.count) * cardHeight,
            deckHeight: showDeck ? sectionHeight(deck, cardHeight, frameHeight) : 0,
            handHeight: showHand ? sectionHeight(hand, cardHeight, frameHeight) : 0,
            playedHeight: showPlayed ? sectionHeight(played, cardHeight, frameHeight) : 0,
            bottomHeight: showBottom ? sectionHeight(bottom, cardHeight, frameHeight) : 0,
            relatedHeight: showRelated ? sectionHeight(related, cardHeight, frameHeight) : 0
        )
        if next != layout {
            layout = next
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
