//
//  CardZoneGroupsTests.swift
//  HSTracker
//
//  Phase 2 / T1: the deck / hand / played split of the tracker's main list.
//

import XCTest

@testable import HSTracker

class CardZoneGroupsTests: HSTrackerTests {

    private func card(_ id: String, _ count: Int) -> Card {
        let card = Card()
        card.id = id
        card.name = id
        card.count = count
        return card
    }

    /// What the flat list would show for a card id: `remainingInDeck` carries the
    /// copies still in the deck, `removedFromDeck` rows are forced to 0.
    private func totals(_ cards: [Card]) -> [String: Int] {
        var result = [String: Int]()
        for card in cards {
            result[card.id] = (result[card.id] ?? 0) + abs(card.count)
        }
        return result
    }

    private func assertNoCardIsLost(_ groups: CardZoneGroups,
                                    originalDeck: [Card],
                                    line: UInt = #line) {
        var sum = totals(groups.deck)
        for (id, count) in totals(groups.hand) {
            sum[id] = (sum[id] ?? 0) + count
        }
        for (id, count) in totals(groups.played) {
            sum[id] = (sum[id] ?? 0) + count
        }
        XCTAssertEqual(sum, totals(originalDeck),
                       "deck + hand + played must account for every copy of every card",
                       line: line)
    }

    private func assertDeckHasNoZeroCount(_ groups: CardZoneGroups, line: UInt = #line) {
        XCTAssertTrue(groups.deck.all { $0.count > 0 },
                      "the deck section must not carry the flat list's count == 0 rows",
                      line: line)
    }

    // MARK: - Invariant 1 / 2

    /// Nothing drawn yet: the whole deck list is the deck section, and the flat
    /// list and the deck section are the same rows with the same counts.
    func testUntouchedDeckIsEntirelyInTheDeckSection() {
        let deckList = [card("A", 2), card("B", 2), card("C", 1)]
        let groups = CardZoneGroups.make(remainingInDeck: deckList,
                                         predictedInDeck: [],
                                         removedFromDeck: [],
                                         cardsInHand: [],
                                         originalDeck: deckList)

        XCTAssertEqual(totals(groups.deck), ["A": 2, "B": 2, "C": 1])
        XCTAssertTrue(groups.hand.isEmpty)
        XCTAssertTrue(groups.played.isEmpty)
        assertNoCardIsLost(groups, originalDeck: deckList)
        assertDeckHasNoZeroCount(groups)
    }

    /// 5 cards drawn, 3 of them played. Every copy still has exactly one home,
    /// and none of them is a zero count row in the deck section anymore.
    func testDrawnAndPlayedCardsLeaveTheDeckSection() {
        // A: 2 copies, both drawn, both played. B: 2 copies, one drawn and still
        // in hand. C: 2 copies, one drawn and played. D: 1 copy, untouched.
        let deckList = [card("A", 2), card("B", 2), card("C", 2), card("D", 1)]
        let remaining = [card("B", 1), card("C", 1), card("D", 1)]
        // The rows getDeckState() builds for cards that left the deck: count 0.
        let removed = [card("A", 0), card("B", 0), card("C", 0)]
        let inHand = [card("B", 1)]

        let groups = CardZoneGroups.make(remainingInDeck: remaining,
                                         predictedInDeck: [],
                                         removedFromDeck: removed,
                                         cardsInHand: inHand,
                                         originalDeck: deckList)

        XCTAssertEqual(totals(groups.deck), ["B": 1, "C": 1, "D": 1])
        XCTAssertEqual(totals(groups.hand), ["B": 1])
        // A had both copies played, C one; B is fully accounted for by the hand.
        XCTAssertEqual(totals(groups.played), ["A": 2, "C": 1])
        assertNoCardIsLost(groups, originalDeck: deckList)
        assertDeckHasNoZeroCount(groups)
    }

    /// The played rows keep rendering as today's dark bar (`count <= 0`), the
    /// copies they stand for live in `abs(count)`.
    func testPlayedRowsStayDark() {
        let deckList = [card("A", 2)]
        let groups = CardZoneGroups.make(remainingInDeck: [],
                                         predictedInDeck: [],
                                         removedFromDeck: [card("A", 0)],
                                         cardsInHand: [],
                                         originalDeck: deckList)

        XCTAssertEqual(groups.played.count, 1)
        XCTAssertEqual(groups.played.first?.count, -2)
        assertNoCardIsLost(groups, originalDeck: deckList)
    }

    /// A created card in hand is not in the deck list, so it only has to be in
    /// the hand section, and a created card that left the deck counts as one
    /// copy played.
    func testCreatedCards() {
        let created = card("X", 1)
        created.isCreated = true
        let groups = CardZoneGroups.make(remainingInDeck: [card("A", 1)],
                                         predictedInDeck: [],
                                         removedFromDeck: [card("Y", 0)],
                                         cardsInHand: [created],
                                         originalDeck: [card("A", 1)])

        XCTAssertEqual(totals(groups.hand), ["X": 1])
        XCTAssertEqual(totals(groups.played), ["Y": 1])
    }

    /// Predicted cards belong to the deck section (PLAN 2.1's first row).
    func testPredictedCardsAreInTheDeckSection() {
        let groups = CardZoneGroups.make(remainingInDeck: [card("A", 1)],
                                         predictedInDeck: [card("P", 1)],
                                         removedFromDeck: [],
                                         cardsInHand: [],
                                         originalDeck: [card("A", 1)])

        XCTAssertEqual(totals(groups.deck), ["A": 1, "P": 1])
    }

    // MARK: - highlightCardsInHand

    /// In zone mode the setting has no say: the hand section is built from the
    /// hand either way, and neither state puts a count == 0 row back into the
    /// deck section (feedback ①).
    func testGroupingIgnoresHighlightCardsInHand() {
        let deckList = [card("A", 2), card("B", 1)]
        let remaining = [card("A", 1)]
        let removed = [card("A", 0), card("B", 0)]
        let inHand = [card("A", 1), card("B", 1)]

        let previous = Settings.highlightCardsInHand
        defer { Settings.highlightCardsInHand = previous }

        var results = [CardZoneGroups]()
        for highlight in [true, false] {
            Settings.highlightCardsInHand = highlight
            let groups = CardZoneGroups.make(remainingInDeck: remaining,
                                             predictedInDeck: [],
                                             removedFromDeck: removed,
                                             cardsInHand: inHand,
                                             originalDeck: deckList)
            XCTAssertEqual(totals(groups.deck), ["A": 1])
            XCTAssertEqual(totals(groups.hand), ["A": 1, "B": 1])
            XCTAssertTrue(groups.played.isEmpty)
            assertNoCardIsLost(groups, originalDeck: deckList)
            assertDeckHasNoZeroCount(groups)
            results.append(groups)
        }
        XCTAssertEqual(totals(results[0].deck), totals(results[1].deck))
        XCTAssertEqual(totals(results[0].hand), totals(results[1].hand))
        XCTAssertEqual(totals(results[0].played), totals(results[1].played))
    }

    // MARK: - Opponent

    func testOpponentIsNotGroupedWithoutAKnownDeck() {
        let previous = Player.knownOpponentDeck
        defer { Player.knownOpponentDeck = previous }

        let game = Game(hearthstoneRunState: HearthstoneRunState(isRunning: false, isActive: false))
        let opponent = Player(local: false, game: game)

        Player.knownOpponentDeck = nil
        XCTAssertNil(opponent.opponentCardGroups, "an unlinked opponent deck must stay flat")

        Player.knownOpponentDeck = [card("A", 2)]
        XCTAssertNotNil(opponent.opponentCardGroups, "a linked opponent deck is grouped")
    }

    func testPlayerIsNotGroupedWithoutADeck() {
        let game = Game(hearthstoneRunState: HearthstoneRunState(isRunning: false, isActive: false))
        XCTAssertNil(game.currentDeck)
        XCTAssertNil(game.player.playerCardGroups, "no deck means nothing to split")
    }
}
