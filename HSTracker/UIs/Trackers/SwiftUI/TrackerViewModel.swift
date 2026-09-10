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
    var headerHeight: CGFloat = 0
    var topHeight: CGFloat = 0
    var listHeight: CGFloat = 0
    var bottomHeight: CGFloat = 0
    var relatedHeight: CGFloat = 0

    var contentHeight: CGFloat {
        headerHeight + topHeight + listHeight + bottomHeight + relatedHeight
    }
}

final class TrackerViewModel: ObservableObject {
    /// Bottom padding under a section's card list, as in the old
    /// `count * cardHeight + frameHeight + 5`.
    private static let sectionPadding: CGFloat = 5

    let header = TrackerHeaderViewModel()
    let cards = TrackerCardListViewModel()
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

    private var lists: [TrackerCardListViewModel] { [cards, top, bottom, related] }

    func update(cards: [Card], top: [Card], bottom: [Card], relatedCards: [Card]) {
        self.cards.update(cards: cards)
        self.top.update(cards: top)
        self.bottom.update(cards: bottom)
        self.related.update(cards: relatedCards)
    }

    /// - Parameters:
    ///   - availableHeight: the window below the AppKit hero bar, i.e. the root
    ///     host's own height.
    ///   - frameHeight: `round(40 / ratio)`, one section header / header row.
    ///   - reserveGraveyardRow: the graveyard counter is not drawn on this path,
    ///     but the old layout still reserved its row in the compression budget.
    func updateLayout(availableHeight: CGFloat,
                      frameHeight: CGFloat,
                      reserveGraveyardRow: Bool) {
        for list in lists {
            list.syncAppearance()
        }

        let showTop = top.count > 0 && Settings.showPlayerCardsTop
        let showBottom = bottom.count > 0 && Settings.showPlayerCardsBottom
        let showRelated = related.count > 0 && Settings.showOpponentRelatedCards

        let headerHeight = header.height
        var offset = headerHeight
        if reserveGraveyardRow {
            offset += frameHeight
        }
        var totalCards = cards.count
        if showTop {
            offset += frameHeight
            totalCards += top.count
        }
        if showBottom {
            offset += frameHeight
            totalCards += bottom.count
        }
        if showRelated {
            offset += frameHeight
            totalCards += related.count
        }

        // Upstream's adaptive row height: rows shrink so that everything still
        // fits when the deck list is long (Tracker.swift, pre-T6).
        var cardHeight = Self.baseCardHeight
        if totalCards > 0 {
            cardHeight = min(cardHeight, (availableHeight - offset) / CGFloat(totalCards))
        }

        let next = TrackerLayout(
            cardHeight: cardHeight,
            headerHeight: headerHeight,
            topHeight: showTop ? sectionHeight(top, cardHeight, frameHeight) : 0,
            listHeight: CGFloat(cards.count) * cardHeight,
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

    private static var baseCardHeight: CGFloat {
        switch Settings.cardSize {
        case .tiny: return CGFloat(kTinyRowHeight)
        case .small: return CGFloat(kSmallRowHeight)
        case .medium: return CGFloat(kMediumRowHeight)
        case .huge: return CGFloat(kHighRowHeight)
        case .big: return CGFloat(kRowHeight)
        }
    }
}
