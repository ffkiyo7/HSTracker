//
//  CardZoneGroupsTests.swift
//  HSTracker
//
//  Phase 2 / T1: the deck / hand / played split of the tracker's main list.
//  Bug T6 rebuilt the split around the zone the entities are in; the inputs
//  below are what `Player` derives from them.
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

    private func totals(_ cards: [Card]) -> [String: Int] {
        var result = [String: Int]()
        for card in cards {
            result[card.id] = (result[card.id] ?? 0) + abs(card.count)
        }
        return result
    }

    /// Every copy of every card has exactly one home. Copies that are not in the
    /// deck list (gifts, cards shuffled in) are known copies too, so they are
    /// passed in explicitly rather than derived from the list.
    private func assertNoCardIsLost(_ groups: CardZoneGroups,
                                    known: [String: Int],
                                    line: UInt = #line) {
        var sum = totals(groups.deck)
        for (id, count) in totals(groups.hand) {
            sum[id] = (sum[id] ?? 0) + count
        }
        for (id, count) in totals(groups.played) {
            sum[id] = (sum[id] ?? 0) + count
        }
        XCTAssertEqual(sum, known,
                       "deck + hand + played must account for every copy of every card",
                       line: line)
    }

    private func assertDeckHasNoZeroCount(_ groups: CardZoneGroups, line: UInt = #line) {
        XCTAssertTrue(groups.deck.all { $0.count > 0 },
                      "the deck section must not carry the flat list's count == 0 rows",
                      line: line)
    }

    // MARK: - Invariant 1 / 2

    /// Nothing drawn yet: the whole deck list is the deck section.
    func testUntouchedDeckIsEntirelyInTheDeckSection() {
        let deckList = [card("A", 2), card("B", 2), card("C", 1)]
        let groups = CardZoneGroups.make(deckList: deckList,
                                         knownInDeck: [],
                                         predictedInDeck: [],
                                         cardsInHand: [],
                                         leftDeck: [],
                                         inHandFromDeck: [:])

        XCTAssertEqual(totals(groups.deck), ["A": 2, "B": 2, "C": 1])
        XCTAssertTrue(groups.hand.isEmpty)
        XCTAssertTrue(groups.played.isEmpty)
        assertNoCardIsLost(groups, known: ["A": 2, "B": 2, "C": 1])
        assertDeckHasNoZeroCount(groups)
    }

    /// 5 cards drawn, 3 of them played. Every copy still has exactly one home,
    /// and none of them is a zero count row in the deck section anymore.
    func testDrawnAndPlayedCardsLeaveTheDeckSection() {
        // A: 2 copies, both drawn, both played. B: 2 copies, one drawn and still
        // in hand. C: 2 copies, one drawn and played. D: 1 copy, untouched.
        let deckList = [card("A", 2), card("B", 2), card("C", 2), card("D", 1)]
        let leftDeck = [card("A", 2), card("B", 1), card("C", 1)]
        let inHand = [card("B", 1)]

        let groups = CardZoneGroups.make(deckList: deckList,
                                         knownInDeck: [],
                                         predictedInDeck: [],
                                         cardsInHand: inHand,
                                         leftDeck: leftDeck,
                                         inHandFromDeck: ["B": 1])

        XCTAssertEqual(totals(groups.deck), ["B": 1, "C": 1, "D": 1])
        XCTAssertEqual(totals(groups.hand), ["B": 1])
        // A had both copies played, C one; B is fully accounted for by the hand.
        XCTAssertEqual(totals(groups.played), ["A": 2, "C": 1])
        assertNoCardIsLost(groups, known: ["A": 2, "B": 2, "C": 2, "D": 1])
        assertDeckHasNoZeroCount(groups)
    }

    /// The played rows keep rendering as today's dark bar (`count <= 0`), the
    /// copies they stand for live in `abs(count)`.
    func testPlayedRowsStayDark() {
        let groups = CardZoneGroups.make(deckList: [card("A", 2)],
                                         knownInDeck: [],
                                         predictedInDeck: [],
                                         cardsInHand: [],
                                         leftDeck: [card("A", 2)],
                                         inHandFromDeck: [:])

        XCTAssertEqual(groups.played.count, 1)
        XCTAssertEqual(groups.played.first?.count, -2)
        assertNoCardIsLost(groups, known: ["A": 2])
    }

    /// A gift in hand is not in the deck list, so it only has to be in the hand
    /// section, and it never touches the deck or played sections.
    func testCreatedCards() {
        let created = card("X", 1)
        created.isCreated = true
        let groups = CardZoneGroups.make(deckList: [card("A", 1)],
                                         knownInDeck: [],
                                         predictedInDeck: [],
                                         cardsInHand: [created],
                                         leftDeck: [],
                                         inHandFromDeck: [:])

        XCTAssertEqual(totals(groups.hand), ["X": 1])
        XCTAssertEqual(totals(groups.deck), ["A": 1])
        XCTAssertTrue(groups.played.isEmpty)
        assertNoCardIsLost(groups, known: ["A": 1, "X": 1])
    }

    /// Cards shuffled into the deck are not in the list; the deck section counts
    /// them from the deck zone, on top of what the list still owes.
    func testCardsShuffledIntoTheDeck() {
        let token = card("T", 6)
        token.isCreated = true
        let groups = CardZoneGroups.make(deckList: [card("A", 2)],
                                         knownInDeck: [token],
                                         predictedInDeck: [],
                                         cardsInHand: [],
                                         leftDeck: [],
                                         inHandFromDeck: [:])

        XCTAssertEqual(totals(groups.deck), ["A": 2, "T": 6])
        assertNoCardIsLost(groups, known: ["A": 2, "T": 6])
        assertDeckHasNoZeroCount(groups)
    }

    /// A copy shuffled in on top of the list's own copies must not be swallowed
    /// by the list: three copies are in the deck, the list only knows two.
    func testAnExtraCopyShuffledInIsNotSwallowed() {
        let groups = CardZoneGroups.make(deckList: [card("A", 2)],
                                         knownInDeck: [card("A", 3)],
                                         predictedInDeck: [],
                                         cardsInHand: [],
                                         leftDeck: [],
                                         inHandFromDeck: [:])

        XCTAssertEqual(totals(groups.deck), ["A": 3])
    }

    /// Predicted cards belong to the deck section (PLAN 2.1's first row).
    func testPredictedCardsAreInTheDeckSection() {
        let groups = CardZoneGroups.make(deckList: [card("A", 1)],
                                         knownInDeck: [],
                                         predictedInDeck: [card("P", 1)],
                                         cardsInHand: [],
                                         leftDeck: [],
                                         inHandFromDeck: [:])

        XCTAssertEqual(totals(groups.deck), ["A": 1, "P": 1])
    }

    // MARK: - highlightCardsInHand

    /// In zone mode the setting has no say: the hand section is built from the
    /// hand either way, and neither state puts a count == 0 row back into the
    /// deck section (feedback ①).
    func testGroupingIgnoresHighlightCardsInHand() {
        let deckList = [card("A", 2), card("B", 1)]
        let leftDeck = [card("A", 1), card("B", 1)]
        let inHand = [card("A", 1), card("B", 1)]

        let previous = Settings.highlightCardsInHand
        defer { Settings.highlightCardsInHand = previous }

        var results = [CardZoneGroups]()
        for highlight in [true, false] {
            Settings.highlightCardsInHand = highlight
            let groups = CardZoneGroups.make(deckList: deckList,
                                             knownInDeck: [],
                                             predictedInDeck: [],
                                             cardsInHand: inHand,
                                             leftDeck: leftDeck,
                                             inHandFromDeck: ["A": 1, "B": 1])
            XCTAssertEqual(totals(groups.deck), ["A": 1])
            XCTAssertEqual(totals(groups.hand), ["A": 1, "B": 1])
            XCTAssertTrue(groups.played.isEmpty)
            assertNoCardIsLost(groups, known: ["A": 2, "B": 1])
            assertDeckHasNoZeroCount(groups)
            results.append(groups)
        }
        XCTAssertEqual(totals(results[0].deck), totals(results[1].deck))
        XCTAssertEqual(totals(results[0].hand), totals(results[1].hand))
        XCTAssertEqual(totals(results[0].played), totals(results[1].played))
    }

    /// Same for `showPlayerGet`: it governs the flat list, not the hand section.
    func testGroupingIgnoresShowPlayerGet() {
        let previous = Settings.showPlayerGet
        defer { Settings.showPlayerGet = previous }

        let gift = card("X", 1)
        gift.isCreated = true
        for show in [true, false] {
            Settings.showPlayerGet = show
            let groups = CardZoneGroups.make(deckList: [card("A", 1)],
                                             knownInDeck: [],
                                             predictedInDeck: [],
                                             cardsInHand: [gift],
                                             leftDeck: [],
                                             inHandFromDeck: [:])
            XCTAssertEqual(totals(groups.hand), ["X": 1])
        }
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
