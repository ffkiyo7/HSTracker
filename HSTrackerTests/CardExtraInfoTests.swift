//
//  CardExtraInfoTests.swift
//  HSTracker
//
//  Package 2 (W3f): a card's extraInfo survives grouping, Entity.copy() and sorting.
//

import XCTest

@testable import HSTracker

class CardExtraInfoTests: HSTrackerTests {

    private let eruption = CardIds.NonCollectible.Neutral.Incindius_EruptionToken

    private func waitForCard(_ cardId: String, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(60)
        while Cards.any(byId: cardId) == nil && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        XCTAssertNotNil(Cards.any(byId: cardId), "\(cardId) never showed up in the card database", line: line)
    }

    private func makeGame() -> Game {
        let game = Game(hearthstoneRunState: HearthstoneRunState(isRunning: false, isActive: false))
        game.player.id = 1
        game.opponent.id = 2
        return game
    }

    private func addDeckCard(_ game: Game, id: Int, cardId: String,
                             extraInfo: (any ICardExtraInfo)? = nil, controller: Int = 1) {
        let entity = Entity(id: id)
        entity.cardId = cardId
        entity[.zone] = Zone.deck.rawValue
        entity[.controller] = controller
        entity[.cardtype] = CardType.spell.rawValue
        entity.info.extraInfo = extraInfo
        game.entities[id] = entity
    }

    // MARK: - Grouping in Player

    func testCopiesWithAndWithoutExtraInfoAreSeparateRows() {
        waitForCard(eruption)
        let game = makeGame()
        addDeckCard(game, id: 10, cardId: eruption, extraInfo: IncindiusCounter(3, 2))
        addDeckCard(game, id: 11, cardId: eruption)

        let cards = game.player.knownCardsInDeck.filter { $0.id == eruption }
        XCTAssertEqual(cards.count, 2, "a counter makes its copy a row of its own")

        let counted = cards.first { $0.extraInfo != nil }
        XCTAssertEqual((counted?.extraInfo as? IncindiusCounter)?.counter, 2)
        XCTAssertEqual(counted?.extraInfo?.cardNameSuffix, "(+2)")
        XCTAssertEqual(counted?.count, 1)
        XCTAssertEqual(cards.first { $0.extraInfo == nil }?.count, 1)
    }

    func testCopiesWithEqualExtraInfoShareOneRow() {
        waitForCard(eruption)
        let game = makeGame()
        addDeckCard(game, id: 10, cardId: eruption, extraInfo: IncindiusCounter(3, 2))
        addDeckCard(game, id: 11, cardId: eruption, extraInfo: IncindiusCounter(3, 2))

        let cards = game.player.knownCardsInDeck.filter { $0.id == eruption }
        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards.first?.count, 2)
        XCTAssertEqual(cards.first?.extraInfo?.cardNameSuffix, "(+2)")
    }

    /// The zone panel builds its deck rows from `Card.copy()` of a template,
    /// so the copy has to carry extraInfo too.
    func testZoneDeckRowKeepsExtraInfo() {
        let previous = Player.knownOpponentDeck
        defer { Player.knownOpponentDeck = previous }

        waitForCard(eruption)
        let game = makeGame()
        Player.knownOpponentDeck = []
        addDeckCard(game, id: 10, cardId: eruption, extraInfo: IncindiusCounter(3, 2), controller: 2)
        addDeckCard(game, id: 11, cardId: eruption, extraInfo: IncindiusCounter(3, 2), controller: 2)

        guard let groups = game.opponent.opponentCardGroups else {
            return XCTFail("a linked opponent deck is grouped")
        }
        let rows = groups.deck.filter { $0.id == eruption }
        XCTAssertEqual(rows.map { $0.count }.reduce(0, +), 2)
        XCTAssertTrue(rows.all { $0.extraInfo?.cardNameSuffix == "(+2)" })
    }

    func testCardCopyKeepsAnIndependentExtraInfo() {
        let card = Card()
        let counter = IncindiusCounter(3, 2)
        card.extraInfo = counter

        let copied = card.copy().extraInfo as? IncindiusCounter
        XCTAssertEqual(copied, counter)
        XCTAssertFalse(copied === counter)
    }

    // MARK: - Entity.copy()

    func testEntityCopyKeepsAnIndependentExtraInfo() {
        let original = Entity(id: 1)
        let counter = IncindiusCounter(3, 2)
        original.info.extraInfo = counter

        let copy: Entity = original.copy()
        guard let copied = copy.info.extraInfo as? IncindiusCounter else {
            return XCTFail("the copy lost its extraInfo")
        }
        XCTAssertEqual(copied, counter)
        XCTAssertFalse(copied === counter, "the copy owns its own extraInfo")

        counter.counter += 1
        XCTAssertEqual(copied.counter, 2, "changing the original does not change the copy")
    }

    // MARK: - DynamicEntity equality and hash

    func testDynamicEntityEqualityCoversExtraInfo() {
        let bothNilA = DynamicEntity(cardId: eruption)
        let bothNilB = DynamicEntity(cardId: eruption)
        XCTAssertEqual(bothNilA, bothNilB)
        XCTAssertEqual(bothNilA.hashValue, bothNilB.hashValue)

        let sameA = DynamicEntity(cardId: eruption, extraInfo: IncindiusCounter(3, 2))
        let sameB = DynamicEntity(cardId: eruption, extraInfo: IncindiusCounter(3, 2))
        XCTAssertNotNil(sameA.extraInfo, "init keeps extraInfo")
        XCTAssertEqual(sameA, sameB)
        XCTAssertEqual(sameA.hashValue, sameB.hashValue)

        let different = DynamicEntity(cardId: eruption, extraInfo: IncindiusCounter(3, 1))
        XCTAssertNotEqual(sameA, different)

        XCTAssertNotEqual(bothNilA, sameA)
        XCTAssertNotEqual(sameA, bothNilA)
    }

    // MARK: - Sorting

    private func card(_ suffixCounter: Int?) -> Card {
        let card = Card()
        card.id = eruption
        card.name = "Eruption"
        card.cost = 1
        if let suffixCounter {
            card.extraInfo = IncindiusCounter(3, suffixCounter)
        }
        return card
    }

    func testSameCostSameNameSortsBySuffixWhateverTheInputOrder() {
        let cards = [card(2), card(nil), card(1)]
        let expected = ["", "(+1)", "(+2)"]

        for input in [cards, cards.reversed(), [cards[1], cards[2], cards[0]]] {
            let suffixes = input.sortCardList().map { $0.extraInfo?.cardNameSuffix ?? "" }
            XCTAssertEqual(suffixes, expected)
        }
    }
}
