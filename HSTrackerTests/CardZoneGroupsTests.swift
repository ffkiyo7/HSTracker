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

    /// Codex review 2026-09-15 #1: two copies of the list's own card are still
    /// in the deck unrevealed, and a third copy of the same card is shuffled in.
    /// Counting "what the list owes" and "what is provably in there" as
    /// alternatives reported 2; they have to be added up instead.
    func testAShuffledInCopyIsNotSwallowedByUnrevealedListCopies() {
        let shuffledIn = card("A", 1)
        shuffledIn.isCreated = true
        let groups = CardZoneGroups.make(deckList: [card("A", 2)],
                                         knownInDeck: [shuffledIn],
                                         predictedInDeck: [],
                                         cardsInHand: [],
                                         leftDeck: [],
                                         shuffledIntoDeck: ["A": 1],
                                         inHandFromDeck: [:])

        XCTAssertEqual(totals(groups.deck), ["A": 3])
        assertNoCardIsLost(groups, known: ["A": 3])
        assertDeckHasNoZeroCount(groups)
    }

    /// The same, one turn later: one of the three copies has been drawn and
    /// played. The list still owes two, the shuffled in copy is still in there.
    func testAShuffledInCopySurvivesACopyOfTheSameCardBeingDrawn() {
        let shuffledIn = card("A", 1)
        shuffledIn.isCreated = true
        let groups = CardZoneGroups.make(deckList: [card("A", 2)],
                                         knownInDeck: [shuffledIn],
                                         predictedInDeck: [],
                                         cardsInHand: [],
                                         leftDeck: [card("A", 1)],
                                         shuffledIntoDeck: ["A": 1],
                                         inHandFromDeck: [:])

        XCTAssertEqual(totals(groups.deck), ["A": 2])
        XCTAssertEqual(totals(groups.played), ["A": 1])
        assertNoCardIsLost(groups, known: ["A": 3])
    }

    /// Bug T8: the list's two copies are still in the deck unrevealed and the
    /// copy that was shuffled in on top of them has been drawn. The list did not
    /// pay for that draw, so it still owes both copies — the deck section used
    /// to report 1.
    func testAShuffledInCopyBeingDrawnDoesNotCostTheDeckListACard() {
        let drawn = card("A", 1)
        drawn.isCreated = true
        let groups = CardZoneGroups.make(deckList: [card("A", 2)],
                                         knownInDeck: [],
                                         predictedInDeck: [],
                                         cardsInHand: [drawn],
                                         leftDeck: [card("A", 1)],
                                         shuffledIntoDeck: [:],
                                         shuffledLeftDeck: ["A": 1],
                                         inHandFromDeck: ["A": 1])

        XCTAssertEqual(totals(groups.deck), ["A": 2])
        XCTAssertEqual(totals(groups.hand), ["A": 1])
        XCTAssertTrue(groups.played.isEmpty)
        assertNoCardIsLost(groups, known: ["A": 3])
        assertDeckHasNoZeroCount(groups)
    }

    /// The same copy once it has been played: it leaves the hand section for the
    /// played section, and the deck list still owes its own two copies.
    func testAShuffledInCopyBeingPlayedDoesNotCostTheDeckListACard() {
        let groups = CardZoneGroups.make(deckList: [card("A", 2)],
                                         knownInDeck: [],
                                         predictedInDeck: [],
                                         cardsInHand: [],
                                         leftDeck: [card("A", 1)],
                                         shuffledIntoDeck: [:],
                                         shuffledLeftDeck: ["A": 1],
                                         inHandFromDeck: [:])

        XCTAssertEqual(totals(groups.deck), ["A": 2])
        XCTAssertEqual(totals(groups.played), ["A": 1])
        assertNoCardIsLost(groups, known: ["A": 3])
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

    // MARK: - Where a card came from, not who holds it

    /// The host app fills `Cards` on a background queue while the first tests
    /// are already running, so anything that reads the card database has to wait
    /// for the card it needs to show up.
    @discardableResult
    private func waitForCard(_ cardId: String, line: UInt = #line) -> Card? {
        let deadline = Date().addingTimeInterval(60)
        while Cards.any(byId: cardId) == nil && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        let card = Cards.any(byId: cardId)
        XCTAssertNotNil(card, "\(cardId) never showed up in the card database", line: line)
        return card
    }

    private func makeGame() -> Game {
        let game = Game(hearthstoneRunState: HearthstoneRunState(isRunning: false, isActive: false))
        game.player.id = 1
        game.opponent.id = 2
        return game
    }

    /// A card that started in someone's deck and is on the board now.
    private func addPlayedDeckCard(_ game: Game, id: Int, cardId: String,
                                   controller: Int, originalController: Int) {
        let entity = Entity(id: id)
        entity.cardId = cardId
        entity[.zone] = Zone.play.rawValue
        entity[.controller] = controller
        entity[.cardtype] = CardType.minion.rawValue
        entity.info.originalZone = .deck
        entity.info.originalController = originalController
        game.entities[id] = entity
    }

    /// A card that started in someone's deck and is in their hand now.
    private func addDrawnDeckCard(_ game: Game, id: Int, cardId: String,
                                  controller: Int, originalController: Int,
                                  shuffledIn: Bool = false) {
        let entity = Entity(id: id)
        entity.cardId = cardId
        entity[.zone] = Zone.hand.rawValue
        entity[.controller] = controller
        entity[.cardtype] = CardType.minion.rawValue
        entity.info.originalZone = .deck
        entity.info.originalController = originalController
        entity.info.created = shuffledIn
        entity.wasShuffledIntoDeck = shuffledIn
        game.entities[id] = entity
    }

    /// Bug T8, end to end over `Player`: a copy of a deck list card was shuffled
    /// in and then drawn. It is in the hand section, and the two copies the list
    /// owns are still owed — the deck section used to report 1.
    func testAShuffledInCopyThatWasDrawnStillLeavesTheListInTheDeck() {
        let previous = Player.knownOpponentDeck
        defer { Player.knownOpponentDeck = previous }

        waitForCard("BT_753")
        let game = makeGame()
        Player.knownOpponentDeck = [card("BT_753", 2)]
        addDrawnDeckCard(game, id: 10, cardId: "BT_753", controller: 2,
                         originalController: 2, shuffledIn: true)

        guard let groups = game.opponent.opponentCardGroups else {
            return XCTFail("a linked opponent deck is grouped")
        }
        XCTAssertEqual(totals(groups.deck)["BT_753"], 2,
                       "the drawn copy was never the deck list's, the list still owes both")
        XCTAssertEqual(totals(groups.hand)["BT_753"], 1)
        XCTAssertNil(totals(groups.played)["BT_753"])
    }

    /// The control: the very same entity without the shuffled in flag is one of
    /// the list's own copies, so drawing it does take one out of the deck.
    func testADrawnDeckListCardStillLeavesTheDeckSection() {
        let previous = Player.knownOpponentDeck
        defer { Player.knownOpponentDeck = previous }

        waitForCard("BT_753")
        let game = makeGame()
        Player.knownOpponentDeck = [card("BT_753", 2)]
        addDrawnDeckCard(game, id: 10, cardId: "BT_753", controller: 2,
                         originalController: 2, shuffledIn: false)

        guard let groups = game.opponent.opponentCardGroups else {
            return XCTFail("a linked opponent deck is grouped")
        }
        XCTAssertEqual(totals(groups.deck)["BT_753"], 1)
        XCTAssertEqual(totals(groups.hand)["BT_753"], 1)
    }

    /// Feeds one real `DISPLAYED_CREATOR` tag change through `TagChangeHandler`
    /// for a card of ours sitting in the deck and already flagged `info.created`
    /// — which an ordinary draw is too (bug T6) — and reports whether the parser
    /// latched it as a copy shuffled in.
    private func latchesShuffledIn(creatorCardId: String) -> Bool {
        let game = makeGame()
        let creator = Entity(id: 20)
        creator.cardId = creatorCardId
        game.entities[20] = creator

        let inDeck = Entity(id: 21)
        inDeck.cardId = "BT_753"
        inDeck[.zone] = Zone.deck.rawValue
        inDeck[.controller] = 1
        inDeck[.cardtype] = CardType.minion.rawValue
        inDeck.info.originalZone = .deck
        inDeck.info.originalController = 1
        inDeck.info.created = true
        game.entities[21] = inDeck

        TagChangeHandler().tagChange(eventHandler: game, tag: .displayed_creator, id: 21, value: 20)
        return inDeck.wasShuffledIntoDeck
    }

    /// Codex review 2026-09-15: 视界术 names itself as the `DISPLAYED_CREATOR` of
    /// the card it *draws*, not of a created copy. That card going back into the
    /// deck must not be taken for a copy shuffled in, or the deck list stops
    /// paying for it when it is drawn again and the deck section reads one high.
    func testFarSightDoesNotMakeTheCardItDrawsLookShuffledIn() {
        for farSight in [CardIds.Collectible.Shaman.FarSight,
                         CardIds.Collectible.Shaman.FarSightCore,
                         CardIds.Collectible.Shaman.FarSightVanilla] {
            XCTAssertFalse(latchesShuffledIn(creatorCardId: farSight),
                           "\(farSight) creates nothing, it only draws")
        }
        // The control: any other card naming itself as creator of something in
        // the deck really did put a new copy in there.
        XCTAssertTrue(latchesShuffledIn(creatorCardId: "VAC_933"),
                      "a card that does create copies still has to be latched")
    }

    /// Codex review 2026-09-15 #2: the sections used to ask who controls a card
    /// right now. A mind controlled minion then counts against the wrong deck in
    /// both directions.
    func testAChangeOfControlDoesNotMoveCardsBetweenTheDecks() {
        let previous = Player.knownOpponentDeck
        defer { Player.knownOpponentDeck = previous }

        waitForCard("BT_753")
        waitForCard("SC_010")
        let game = makeGame()
        Player.knownOpponentDeck = [card("BT_753", 1), card("SC_010", 1)]
        // Their card, drawn from their deck, now under our control.
        addPlayedDeckCard(game, id: 10, cardId: "BT_753", controller: 1, originalController: 2)
        // Our card, drawn from our deck, now under their control.
        addPlayedDeckCard(game, id: 11, cardId: "SC_010", controller: 2, originalController: 1)

        guard let groups = game.opponent.opponentCardGroups else {
            return XCTFail("a linked opponent deck is grouped")
        }
        XCTAssertNil(totals(groups.deck)["BT_753"],
                     "their card left their deck, whoever controls it now")
        XCTAssertEqual(totals(groups.played)["BT_753"], 1)
        XCTAssertEqual(totals(groups.deck)["SC_010"], 1,
                       "our card was never in their deck, it cannot take a copy out of it")
    }

    /// Codex review 2026-09-15 #3: a customised Zilliax is in the deck list as
    /// the base card and comes out of the deck as its cosmetic module, so the
    /// two never cancelled out and the base card stayed in the deck all game.
    func testACustomisedZilliaxLeavesTheDeckSectionOnceItIsDrawn() {
        let previous = Player.knownOpponentDeck
        defer { Player.knownOpponentDeck = previous }

        let zilliax = CardIds.Collectible.Neutral.ZilliaxDeluxe3000
        waitForCard(zilliax)
        // One of Zilliax's cosmetic modules; this is the id the drawn entity
        // carries, while the deck list only ever names the base card.
        guard let cosmetic = waitForCard("TOY_330t10") else { return }
        XCTAssertTrue(cosmetic.zilliaxCustomizableCosmeticModule,
                      "TOY_330t10 is no longer flagged as a Zilliax cosmetic module")

        let game = makeGame()
        Player.knownOpponentDeck = [card(zilliax, 1)]
        addPlayedDeckCard(game, id: 10, cardId: cosmetic.id, controller: 2, originalController: 2)

        guard let groups = game.opponent.opponentCardGroups else {
            return XCTFail("a linked opponent deck is grouped")
        }
        XCTAssertNil(totals(groups.deck)[zilliax],
                     "the customised Zilliax was drawn, the base card cannot stay in the deck")
        XCTAssertEqual(totals(groups.played)[zilliax], 1)
    }

    // MARK: - Sideboards (bug T9)

    /// Gives the game an active deck so `playerCardGroups` is defined. Our own
    /// side is the one that sees its sideboard revealed, so this is where the
    /// sideboard has to be tested.
    private func setActiveDeck(_ game: Game, _ cards: [(String, Int)]) {
        let deck = Deck()
        deck.name = "bug-t9"
        deck.playerClass = .demonhunter
        for (id, count) in cards {
            deck.cards.append(RealmCard(id: id, count: count))
        }
        game.set(activeDeck: deck, autoDetected: false)
        let deadline = Date().addingTimeInterval(5)
        while game.currentDeck == nil && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        XCTAssertNotNil(game.currentDeck, "the test needs an active deck to group by zone")
    }

    /// A card the game creates straight into SETASIDE during CREATE_GAME, the
    /// shape of `FULL_ENTITY - Creating ID=34 CardID=TOY_644 / tag=ZONE
    /// value=SETASIDE` from the 2026-09-17 Power.log, fed through the real
    /// parser rather than flagged by hand.
    @discardableResult
    private func createSideboardCardAtSetup(_ game: Game, id: Int, cardId: String,
                                            controller: Int) -> Entity {
        let entity = Entity(id: id)
        entity.cardId = cardId
        game.entities[id] = entity
        let handler = TagChangeHandler()
        handler.tagChange(eventHandler: game, tag: .controller, id: id,
                          value: controller, isCreationTag: true)
        handler.tagChange(eventHandler: game, tag: .zone, id: id,
                          value: Zone.setaside.rawValue, isCreationTag: true)
        handler.invokeQueuedActions(eventHandler: game)
        return entity
    }

    /// The parser side: upstream still calls a sideboard card a deck card, the
    /// new latch is what says otherwise.
    func testSideboardCardsCreatedAtSetupAreLatchedAsNeverHavingBeenInTheDeck() {
        let game = makeGame()
        let sideboard = createSideboardCardAtSetup(game, id: 34, cardId: "TOY_644", controller: 1)

        XCTAssertEqual(sideboard.info.originalZone, .deck,
                       "upstream's setup branch still files it under the deck")
        XCTAssertTrue(sideboard.wasSetAsideAtSetup,
                      "it was created set aside, it was never in the deck")

        // The control: a card created into the deck at setup is a deck card.
        let inDeck = Entity(id: 6)
        inDeck.cardId = "ETC_080"
        game.entities[6] = inDeck
        let handler = TagChangeHandler()
        handler.tagChange(eventHandler: game, tag: .controller, id: 6, value: 1, isCreationTag: true)
        handler.tagChange(eventHandler: game, tag: .zone, id: 6,
                          value: Zone.deck.rawValue, isCreationTag: true)
        handler.invokeQueuedActions(eventHandler: game)
        XCTAssertFalse(inDeck.wasSetAsideAtSetup)
    }

    /// Bug T9, the user's report: the deck list holds E.T.C., E.T.C. is played,
    /// one sideboard card is picked into hand and played too. The played section
    /// may only hold E.T.C.; the sideboard card belongs to the sideboard panel
    /// and to none of the three sections.
    func testTheSideboardIsInNoZoneSection() {
        waitForCard("ETC_080")
        waitForCard("TOY_644")
        waitForCard("JAIL_205")
        waitForCard("BT_753")

        let game = makeGame()
        setActiveDeck(game, [("ETC_080", 1), ("BT_753", 1)])

        // E.T.C. itself: drawn from the deck and played.
        addPlayedDeckCard(game, id: 6, cardId: "ETC_080", controller: 1, originalController: 1)
        // Its sideboard, created set aside during CREATE_GAME.
        createSideboardCardAtSetup(game, id: 34, cardId: "TOY_644", controller: 1)
        createSideboardCardAtSetup(game, id: 35, cardId: "JAIL_205", controller: 1)
        // The copy E.T.C. hands over when one is picked is a separate entity
        // created mid game, so it starts in hand; here it has been played.
        let picked = Entity(id: 186)
        picked.cardId = "TOY_644"
        picked[.zone] = Zone.graveyard.rawValue
        picked[.controller] = 1
        picked[.cardtype] = CardType.spell.rawValue
        picked.info.originalZone = .hand
        picked.info.originalController = 1
        picked.info.created = true
        game.entities[186] = picked

        guard let groups = game.player.playerCardGroups else {
            return XCTFail("an active deck is grouped by zone")
        }
        XCTAssertEqual(totals(groups.played), ["ETC_080": 1],
                       "only E.T.C. was played out of the deck list")
        for sideboardCard in ["TOY_644", "JAIL_205"] {
            XCTAssertNil(totals(groups.deck)[sideboardCard])
            XCTAssertNil(totals(groups.hand)[sideboardCard])
            XCTAssertNil(totals(groups.played)[sideboardCard])
        }
    }

    /// The same for Zilliax: its modules are created set aside at setup as well,
    /// and `zoneCardId` folds a cosmetic module into the base card (bug T7), so
    /// an unassembled module used to report Zilliax as played from turn zero.
    func testZilliaxModulesAreInNoZoneSection() {
        let zilliax = CardIds.Collectible.Neutral.ZilliaxDeluxe3000
        waitForCard(zilliax)
        guard let cosmetic = waitForCard("TOY_330t10") else { return }
        XCTAssertTrue(cosmetic.zilliaxCustomizableCosmeticModule,
                      "TOY_330t10 is no longer flagged as a Zilliax cosmetic module")

        let game = makeGame()
        setActiveDeck(game, [(zilliax, 1)])
        createSideboardCardAtSetup(game, id: 34, cardId: cosmetic.id, controller: 1)

        guard let groups = game.player.playerCardGroups else {
            return XCTFail("an active deck is grouped by zone")
        }
        XCTAssertTrue(groups.played.isEmpty, "nothing has been played yet")
        XCTAssertEqual(totals(groups.deck)[zilliax], 1,
                       "the assembled Zilliax is still in the deck")
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

    // MARK: - Perf P1 / 2: one getDeckState() per refresh

    /// The tracker refresh used to reach `getDeckState()` four times (three
    /// `annotateCards` plus the sideboards Game passes separately). The
    /// snapshot is the single entry point, so it must evaluate it once.
    func testZoneRefreshEvaluatesTheDeckStateOnce() {
        waitForCard("ETC_080")
        waitForCard("BT_753")

        let game = makeGame()
        setActiveDeck(game, [("ETC_080", 1), ("BT_753", 1)])

        let before = game.player.deckStateEvaluations
        let snapshot = game.player.playerTrackerSnapshot(useZoneGroups: true)
        XCTAssertEqual(game.player.deckStateEvaluations - before, 1,
                       "one refresh must compute the deck state exactly once")
        XCTAssertNotNil(snapshot.groups, "an active deck is grouped by zone")
        XCTAssertTrue(snapshot.cards.isEmpty, "zone mode ignores the flat list")
    }

    func testFlatRefreshEvaluatesTheDeckStateOnce() {
        waitForCard("ETC_080")
        waitForCard("BT_753")

        let game = makeGame()
        setActiveDeck(game, [("ETC_080", 1), ("BT_753", 1)])

        let before = game.player.deckStateEvaluations
        let snapshot = game.player.playerTrackerSnapshot(useZoneGroups: false)
        XCTAssertEqual(game.player.deckStateEvaluations - before, 1,
                       "one refresh must compute the deck state exactly once")
        XCTAssertNil(snapshot.groups)
        XCTAssertFalse(snapshot.cards.isEmpty, "flat mode draws the list")
    }

    /// Without a deck there is no deck state to compute at all, and the flat
    /// list is the one `playerCardList` used to return on that branch.
    func testSnapshotWithoutADeckSkipsTheDeckState() {
        let game = makeGame()
        let before = game.player.deckStateEvaluations
        let snapshot = game.player.playerTrackerSnapshot(useZoneGroups: true)
        XCTAssertEqual(game.player.deckStateEvaluations - before, 0)
        XCTAssertNil(snapshot.groups)
        XCTAssertTrue(snapshot.sideboards.isEmpty)
    }

    /// The snapshot must draw the same thing the old accessors did.
    func testSnapshotMatchesTheOldAccessors() {
        waitForCard("ETC_080")
        waitForCard("BT_753")

        let game = makeGame()
        setActiveDeck(game, [("ETC_080", 1), ("BT_753", 1)])
        addPlayedDeckCard(game, id: 6, cardId: "ETC_080", controller: 1, originalController: 1)

        guard let expected = game.player.playerCardGroups,
              let snapshot = game.player.playerTrackerSnapshot(useZoneGroups: true).groups else {
            return XCTFail("an active deck is grouped by zone")
        }
        XCTAssertEqual(totals(snapshot.deck), totals(expected.deck))
        XCTAssertEqual(totals(snapshot.hand), totals(expected.hand))
        XCTAssertEqual(totals(snapshot.played), totals(expected.played))

        let flat = game.player.playerTrackerSnapshot(useZoneGroups: false).cards
        XCTAssertEqual(totals(flat), totals(game.player.playerCardList))
    }
}
