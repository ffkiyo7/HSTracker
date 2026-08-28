//
//  TrackerCardListViewModel.swift
//  HSTracker
//
//  ObservableObject list state for the SwiftUI main tracker table.
//  Same pattern as PlayerResourcesViewModel / RootOverlayViewModel.
//

import AppKit
import Foundation

struct TrackerCardRowID: Hashable {
    let cardId: String
    let jousted: Bool
    let isCreated: Bool
    let wasDiscarded: Bool
    let deckListIndex: Int
    let hasIncindius: Bool
    let incindiusTurn: Int
    let incindiusCounter: Int
    // A created copy in hand and one in the deck can produce two identical
    // keys; ForEach needs distinct ids, so repeats are numbered.
    var occurrence: Int = 0

    static func matchingAnimatedCardList(_ card: Card) -> TrackerCardRowID {
        let incindius = card.extraInfo as? IncindiusCounter
        return TrackerCardRowID(
            cardId: card.id,
            jousted: card.jousted,
            isCreated: card.isCreated,
            wasDiscarded: Settings.highlightDiscarded ? card.wasDiscarded : false,
            deckListIndex: card.deckListIndex,
            hasIncindius: incindius != nil,
            incindiusTurn: incindius?.turnPlayed ?? 0,
            incindiusCounter: incindius?.counter ?? 0
        )
    }
}

struct TrackerCardRow: Identifiable, Equatable {
    let id: TrackerCardRowID
    let card: Card
    var highlight: HighlightColor

    static func == (lhs: TrackerCardRow, rhs: TrackerCardRow) -> Bool {
        lhs.id == rhs.id
            && highlightsEqual(lhs.highlight, rhs.highlight)
            && lhs.card.count == rhs.card.count
            && lhs.card.cost == rhs.card.cost
            && lhs.card.name == rhs.card.name
            && lhs.card.highlightDraw == rhs.card.highlightDraw
            && lhs.card.highlightInHand == rhs.card.highlightInHand
            && lhs.card.extraInfo?.cardNameSuffix == rhs.card.extraInfo?.cardNameSuffix
    }

    private static func highlightsEqual(_ a: HighlightColor, _ b: HighlightColor) -> Bool {
        switch (a, b) {
        case (.none, .none), (.teal, .teal), (.orange, .orange), (.green, .green):
            return true
        default:
            return false
        }
    }
}

final class TrackerCardListViewModel: ObservableObject {
    @Published private(set) var rows: [TrackerCardRow] = []
    @Published var rowHeight: CGFloat = CGFloat(kRowHeight)
    @Published var theme: String = Settings.theme
    @Published var cardSize: CardSize = Settings.cardSize
    @Published var showRarityColors: Bool = Settings.showRarityColors
    @Published var playerType: PlayerType = .player
    @Published var sectionHeaderHeight: CGFloat = 40

    var onHover: ((Card, NSView) -> Void)?
    var onExit: ((Card) -> Void)?

    var count: Int { rows.count }

    private var highlightFn: ((Card, [Card]) -> HighlightColor)?

    func syncAppearance() {
        let nextTheme = Settings.theme
        let nextSize = Settings.cardSize
        let nextRarity = Settings.showRarityColors
        if theme != nextTheme {
            theme = nextTheme
        }
        if cardSize != nextSize {
            cardSize = nextSize
        }
        if showRarityColors != nextRarity {
            showRarityColors = nextRarity
        }
        ThemeImageCache.prepare(theme: nextTheme)
    }

    func update(cards: [Card]) {
        syncAppearance()
        let next = rows(from: cards)
        if next != rows {
            rows = next
        }
    }

    func setHighlight(_ fn: ((Card, [Card]) -> HighlightColor)?) {
        highlightFn = fn
        let next = rows(from: rows.map(\.card))
        if next != rows {
            rows = next
        }
    }

    private func rows(from cards: [Card]) -> [TrackerCardRow] {
        let live = cards.filter { $0.count > 0 }
        var seen: [TrackerCardRowID: Int] = [:]
        return cards.map { card in
            let highlight: HighlightColor
            if card.count <= 0 || card.jousted {
                highlight = .none
            } else {
                highlight = highlightFn?(card, live) ?? .none
            }
            var id = TrackerCardRowID.matchingAnimatedCardList(card)
            let repeats = seen[id, default: 0]
            seen[id] = repeats + 1
            id.occurrence = repeats
            return TrackerCardRow(id: id, card: card, highlight: highlight)
        }
    }
}
