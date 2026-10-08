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
        // 2.7 round 3: the pick went through our hand and was played, so it is
        // a gift in the played section like any other. What T9 keeps out is the
        // sideboard itself — the cards set aside at setup that never were in
        // hand, JAIL_205 here and the TOY_644 original (id 34).
        XCTAssertEqual(totals(groups.played), ["ETC_080": 1, "TOY_644": 1],
                       "E.T.C. out of the deck list, and the pick played from hand")
        XCTAssertTrue(groups.played.contains { $0.id == "TOY_644" && $0.isCreated },
                      "the pick is a gift")
        XCTAssertNil(totals(groups.deck)["TOY_644"])
        XCTAssertNil(totals(groups.hand)["TOY_644"])
        XCTAssertNil(totals(groups.deck)["JAIL_205"])
        XCTAssertNil(totals(groups.hand)["JAIL_205"])
        XCTAssertNil(totals(groups.played)["JAIL_205"])
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
    /// snapshot evaluates it once and hands it down; what it hands back has to
    /// be what the separate accessors computed on their own.
    func testZoneSnapshotCarriesTheSideboardsOfTheOldAccessor() {
        waitForCard("ETC_080")
        waitForCard("BT_753")

        let game = makeGame()
        setActiveDeck(game, [("ETC_080", 1), ("BT_753", 1)])

        let snapshot = game.player.playerTrackerSnapshot(useZoneGroups: true)
        XCTAssertNotNil(snapshot.groups, "an active deck is grouped by zone")
        XCTAssertTrue(snapshot.cards.isEmpty, "zone mode ignores the flat list")
        XCTAssertEqual(sideboardTotals(snapshot.sideboards),
                       sideboardTotals(game.player.playerSideboardsDict))
    }

    func testFlatSnapshotCarriesTheSideboardsOfTheOldAccessor() {
        waitForCard("ETC_080")
        waitForCard("BT_753")

        let game = makeGame()
        setActiveDeck(game, [("ETC_080", 1), ("BT_753", 1)])

        let snapshot = game.player.playerTrackerSnapshot(useZoneGroups: false)
        XCTAssertNil(snapshot.groups)
        XCTAssertFalse(snapshot.cards.isEmpty, "flat mode draws the list")
        XCTAssertEqual(sideboardTotals(snapshot.sideboards),
                       sideboardTotals(game.player.playerSideboardsDict))
    }

    /// Without a deck there is no deck state, and the flat list is the one
    /// `playerCardList` used to return on that branch.
    func testSnapshotWithoutADeckHasNoGroupsOrSideboards() {
        let game = makeGame()
        let snapshot = game.player.playerTrackerSnapshot(useZoneGroups: true)
        XCTAssertNil(snapshot.groups)
        XCTAssertTrue(snapshot.sideboards.isEmpty)
        XCTAssertEqual(totals(snapshot.cards), totals(game.player.playerCardList))
    }

    private func sideboardTotals(_ sideboards: [Sideboard]) -> [String: [String: Int]] {
        var result = [String: [String: Int]]()
        for sideboard in sideboards {
            result[sideboard.ownerCardId] = totals(sideboard.cards)
        }
        return result
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

    // MARK: - Phase 2 / 2.7: gifts and where a played copy ended up

    private func state(_ card: Card) -> CardZoneRowState {
        return CardZoneRowState(gift: card.isCreated, status: card.zoneStatus)
    }

    /// Rows of one card: every state at most once, and the copies per state.
    private func rowStates(_ cards: [Card], _ cardId: String,
                           line: UInt = #line) -> [CardZoneRowState: Int] {
        var result = [CardZoneRowState: Int]()
        for card in cards where card.id == cardId {
            XCTAssertNil(result[state(card)], "\(cardId) has two rows in the same state", line: line)
            result[state(card)] = abs(card.count)
        }
        return result
    }

    private let graveyard = CardZoneRowState(gift: false, status: .graveyard)
    private let burned = CardZoneRowState(gift: false, status: .burned)

    /// Two copies in the graveyard and one burned are two rows, each counting
    /// only its own copies; together they are still the three that left.
    func testPlayedCopiesAreSplitByWhereTheyEndedUp() {
        let groups = CardZoneGroups.make(deckList: [card("A", 3)],
                                         knownInDeck: [],
                                         predictedInDeck: [],
                                         cardsInHand: [],
                                         leftDeck: [card("A", 3)],
                                         inHandFromDeck: [:],
                                         playedStates: ["A": [graveyard: 2, burned: 1]])

        XCTAssertEqual(rowStates(groups.played, "A"), [graveyard: 2, burned: 1])
        XCTAssertTrue(groups.played.all { $0.count < 0 }, "played rows stay dark")
        assertNoCardIsLost(groups, known: ["A": 3])
    }

    /// The breakdown can split the copies, never change how many there are.
    func testTheBreakdownCannotAddOrDropCopies() {
        let groups = CardZoneGroups.make(deckList: [card("A", 2), card("B", 2)],
                                         knownInDeck: [],
                                         predictedInDeck: [],
                                         cardsInHand: [],
                                         leftDeck: [card("A", 2), card("B", 2)],
                                         inHandFromDeck: [:],
                                         playedStates: ["A": [graveyard: 5], "B": [burned: 1]])

        XCTAssertEqual(rowStates(groups.played, "A"), [graveyard: 2])
        XCTAssertEqual(rowStates(groups.played, "B"), [burned: 1, .plain: 1])
        assertNoCardIsLost(groups, known: ["A": 2, "B": 2])
    }

    /// A copy shuffled in on top of the list's own is a gift, so it is a row of
    /// its own in the deck section; the section still holds all three.
    func testAShuffledInCopyIsAGiftRowInTheDeckSection() {
        let groups = CardZoneGroups.make(deckList: [card("A", 2)],
                                         knownInDeck: [],
                                         predictedInDeck: [],
                                         cardsInHand: [],
                                         leftDeck: [],
                                         shuffledIntoDeck: ["A": 1],
                                         inHandFromDeck: [:])

        XCTAssertEqual(rowStates(groups.deck, "A"),
                       [.plain: 2, CardZoneRowState(gift: true, status: .none): 1])
        assertNoCardIsLost(groups, known: ["A": 3])
        assertDeckHasNoZeroCount(groups)
    }

    /// Gifts that went through the hand join the played section as gift rows,
    /// and a shuffled in copy of the same card in the same state shares the
    /// row with them rather than repeating it.
    func testGiftsPlayedFromHandJoinThePlayedSection() {
        let discovered = card("X", 1)
        discovered.isCreated = true
        discovered.zoneStatus = .graveyard
        let alsoShuffled = card("A", 1)
        alsoShuffled.isCreated = true
        alsoShuffled.zoneStatus = .graveyard
        let giftInGraveyard = CardZoneRowState(gift: true, status: .graveyard)

        let groups = CardZoneGroups.make(deckList: [card("A", 1)],
                                         knownInDeck: [],
                                         predictedInDeck: [],
                                         cardsInHand: [],
                                         leftDeck: [card("A", 1)],
                                         shuffledLeftDeck: ["A": 1],
                                         inHandFromDeck: [:],
                                         playedStates: ["A": [giftInGraveyard: 1]],
                                         giftsPlayed: [discovered, alsoShuffled])

        XCTAssertEqual(rowStates(groups.played, "X"), [giftInGraveyard: 1])
        XCTAssertEqual(rowStates(groups.played, "A"), [giftInGraveyard: 2])
        XCTAssertEqual(totals(groups.deck), ["A": 1], "the list's own copy is still in the deck")
        // The list's A, the shuffled in A, the A made in hand, and X.
        assertNoCardIsLost(groups, known: ["A": 3, "X": 1])
    }

    private func addEntity(_ game: Game, id: Int, cardId: String, zone: Zone,
                           controller: Int, originalZone: Zone?, originalController: Int,
                           type: CardType = .minion) -> Entity {
        let entity = Entity(id: id)
        entity.cardId = cardId
        entity[.zone] = zone.rawValue
        entity[.controller] = controller
        entity[.cardtype] = type.rawValue
        entity.info.originalZone = originalZone
        entity.info.originalController = originalController
        game.entities[id] = entity
        return entity
    }

    /// One opponent turn's worth of every case the icons tell apart, over real
    /// entities and the lists `Player` keeps.
    func testEveryCopyGetsItsGiftAndStatus() {
        let previous = Player.knownOpponentDeck
        defer { Player.knownOpponentDeck = previous }

        for id in ["BT_753", "SC_010", "SW_041", "VAC_933", "SW_039", "VAC_933t"] {
            waitForCard(id)
        }
        let game = makeGame()
        let opponent: Player = game.opponent
        Player.knownOpponentDeck = [card("BT_753", 2), card("SC_010", 1), card("SW_041", 1)]

        // Deck list card played from hand, now dead: skull, no gift.
        let dead = addEntity(game, id: 10, cardId: "BT_753", zone: .graveyard, controller: 2,
                             originalZone: .deck, originalController: 2)
        opponent.cardsPlayedThisMatch.append(dead)
        opponent.playToGraveyard(entity: dead, turn: 3)
        // Its second copy, discarded out of the hand: burned.
        let discarded = addEntity(game, id: 11, cardId: "BT_753", zone: .graveyard, controller: 2,
                                  originalZone: .deck, originalController: 2)
        opponent.handDiscard(entity: discarded, turn: 3)
        // Deck list card played and still on the board: no status.
        let alive = addEntity(game, id: 12, cardId: "SW_041", zone: .play, controller: 2,
                              originalZone: .deck, originalController: 2)
        opponent.cardsPlayedThisMatch.append(alive)
        // A discovered card played from hand, on the board: gift, no status.
        let discovered = addEntity(game, id: 13, cardId: "VAC_933", zone: .play, controller: 2,
                                   originalZone: .hand, originalController: 2)
        discovered.info.created = true
        opponent.cardsPlayedThisMatch.append(discovered)
        // A deck list card in hand that the parser flagged created, as it does
        // on ordinary draws (bug T6): not a gift.
        let drawn = addEntity(game, id: 14, cardId: "SC_010", zone: .hand, controller: 2,
                              originalZone: .deck, originalController: 2)
        drawn.info.created = true
        // A card made in hand and still there: a gift.
        _ = addEntity(game, id: 15, cardId: "SW_039", zone: .hand, controller: 2,
                      originalZone: .hand, originalController: 2)
        // A token summoned straight onto the board and dead: 2.9, it is in the
        // graveyard like any minion that died, so it is a gift with a skull.
        let token = addEntity(game, id: 16, cardId: "VAC_933t", zone: .graveyard, controller: 2,
                              originalZone: .play, originalController: 2)
        opponent.playToGraveyard(entity: token, turn: 3)

        guard let groups = opponent.opponentCardGroups else {
            return XCTFail("a linked opponent deck is grouped")
        }
        XCTAssertEqual(rowStates(groups.played, "BT_753"), [graveyard: 1, burned: 1])
        XCTAssertEqual(rowStates(groups.played, "SW_041"), [.plain: 1])
        XCTAssertEqual(rowStates(groups.played, "VAC_933"),
                       [CardZoneRowState(gift: true, status: .none): 1])
        XCTAssertEqual(rowStates(groups.hand, "SC_010"), [.plain: 1],
                       "an ordinary draw is not a gift, whatever info.created says")
        XCTAssertEqual(rowStates(groups.hand, "SW_039"), [CardZoneRowState(gift: true, status: .none): 1])
        XCTAssertEqual(rowStates(groups.played, "VAC_933t"), [giftInGraveyard: 1],
                       "a token that died is in the graveyard")
        XCTAssertTrue(groups.deck.all { !$0.isCreated && $0.zoneStatus == .none })
        assertNoCardIsLost(groups, known: ["BT_753": 2, "SC_010": 1, "SW_041": 1,
                                           "VAC_933": 1, "SW_039": 1, "VAC_933t": 1])
    }

    /// Taken by the other side without being played is burned, for a deck
    /// list card as for a card that was made in hand.
    func testACardTakenByTheOtherSideIsBurned() {
        let previous = Player.knownOpponentDeck
        defer { Player.knownOpponentDeck = previous }

        waitForCard("BT_753")
        waitForCard("SW_039")
        let game = makeGame()
        Player.knownOpponentDeck = [card("BT_753", 1)]
        // Their deck card, drawn and now in our hand.
        _ = addEntity(game, id: 10, cardId: "BT_753", zone: .hand, controller: 1,
                      originalZone: .deck, originalController: 2)
        // A card made in their hand, now in ours.
        _ = addEntity(game, id: 11, cardId: "SW_039", zone: .hand, controller: 1,
                      originalZone: .hand, originalController: 2)

        guard let groups = game.opponent.opponentCardGroups else {
            return XCTFail("a linked opponent deck is grouped")
        }
        XCTAssertEqual(rowStates(groups.played, "BT_753"), [burned: 1])
        XCTAssertEqual(rowStates(groups.played, "SW_039"),
                       [CardZoneRowState(gift: true, status: .burned): 1])
        XCTAssertTrue(groups.hand.isEmpty, "neither is in their hand")
    }

    /// Nothing the opponent has not shown may reach a section: a secret played
    /// from hand is still an entity without a card id.
    func testAnUnrevealedOpponentCardIsInNoSection() {
        let previous = Player.knownOpponentDeck
        defer { Player.knownOpponentDeck = previous }

        let game = makeGame()
        Player.knownOpponentDeck = [card("A", 1)]
        let secret = addEntity(game, id: 10, cardId: "", zone: .secret, controller: 2,
                               originalZone: .hand, originalController: 2, type: .spell)
        game.opponent.spellsPlayedCards.append(secret)

        guard let groups = game.opponent.opponentCardGroups else {
            return XCTFail("a linked opponent deck is grouped")
        }
        XCTAssertTrue(groups.played.isEmpty)
        XCTAssertTrue(groups.hand.isEmpty)
    }

    // MARK: - 2.7 review round 2

    private let gift = CardZoneRowState(gift: true, status: .none)
    private let giftInGraveyard = CardZoneRowState(gift: true, status: .graveyard)
    private let giftBurned = CardZoneRowState(gift: true, status: .burned)

    /// Review #1: a card made in their hand that reaches the board without
    /// being played (pulled by 肮脏的鼠辈, cast by a trigger) left the hand all
    /// the same. It is in the played section on the board and once it is dead.
    func testAGiftThatReachedTheBoardWithoutBeingPlayedIsInThePlayedSection() {
        let previous = Player.knownOpponentDeck
        defer { Player.knownOpponentDeck = previous }

        waitForCard("VAC_933")
        let game = makeGame()
        Player.knownOpponentDeck = [card("A", 1)]
        let pulled = addEntity(game, id: 10, cardId: "VAC_933", zone: .play, controller: 2,
                               originalZone: .hand, originalController: 2)

        guard let onBoard = game.opponent.opponentCardGroups else {
            return XCTFail("a linked opponent deck is grouped")
        }
        XCTAssertEqual(rowStates(onBoard.played, "VAC_933"), [gift: 1])

        pulled[.zone] = Zone.graveyard.rawValue
        game.opponent.playToGraveyard(entity: pulled, turn: 4)
        guard let dead = game.opponent.opponentCardGroups else {
            return XCTFail("a linked opponent deck is grouped")
        }
        XCTAssertEqual(rowStates(dead.played, "VAC_933"), [giftInGraveyard: 1])
    }

    /// Review #2: a secret they discovered is played face down, so it never
    /// reaches `spellsPlayedCards`; once it fires and shows its card id it has
    /// to be in the played section like any other gift. 2.9: a secret is not a
    /// minion, so being in the graveyard gives it no skull.
    func testARevealedSecretTheOpponentDiscoveredIsInThePlayedSection() {
        let previous = Player.knownOpponentDeck
        defer { Player.knownOpponentDeck = previous }

        waitForCard("EX1_610")
        let game = makeGame()
        Player.knownOpponentDeck = [card("A", 1)]
        _ = addEntity(game, id: 10, cardId: "EX1_610", zone: .graveyard, controller: 2,
                      originalZone: .hand, originalController: 2, type: .spell)

        guard let groups = game.opponent.opponentCardGroups else {
            return XCTFail("a linked opponent deck is grouped")
        }
        XCTAssertEqual(rowStates(groups.played, "EX1_610"), [gift: 1])
    }

    /// Review #3: played, bounced back to hand, then discarded. What happened
    /// last is that it was thrown away, so it is burned, not a skull.
    func testACardPlayedBouncedAndThenDiscardedIsBurned() {
        let previous = Player.knownOpponentDeck
        defer { Player.knownOpponentDeck = previous }

        waitForCard("BT_753")
        let game = makeGame()
        let opponent: Player = game.opponent
        Player.knownOpponentDeck = [card("BT_753", 1)]
        let bounced = addEntity(game, id: 10, cardId: "BT_753", zone: .graveyard, controller: 2,
                                originalZone: .deck, originalController: 2)
        opponent.cardsPlayedThisMatch.append(bounced)
        opponent.boardToHand(entity: bounced, turn: 4)
        opponent.handDiscard(entity: bounced, turn: 5)

        guard let groups = opponent.opponentCardGroups else {
            return XCTFail("a linked opponent deck is grouped")
        }
        XCTAssertEqual(rowStates(groups.played, "BT_753"), [burned: 1])
    }

    /// Review #4: a gift shuffled back into the deck and destroyed in there
    /// (a bomb, a full hand) never went through a discard from hand. It still
    /// left, so it is a burned gift in the played section.
    func testAGiftDestroyedBackInTheDeckIsBurned() {
        let previous = Player.knownOpponentDeck
        defer { Player.knownOpponentDeck = previous }

        waitForCard("VAC_933")
        let game = makeGame()
        let opponent: Player = game.opponent
        Player.knownOpponentDeck = [card("A", 1)]
        let destroyed = addEntity(game, id: 10, cardId: "VAC_933", zone: .graveyard, controller: 2,
                                  originalZone: .hand, originalController: 2)
        opponent.deckDiscard(entity: destroyed, turn: 5)

        guard let groups = opponent.opponentCardGroups else {
            return XCTFail("a linked opponent deck is grouped")
        }
        XCTAssertEqual(rowStates(groups.played, "VAC_933"), [giftBurned: 1])
    }

    /// Review #5: a gift that went back into the deck without T8's latch (the
    /// Coin, a discovered copy) is a gift in the deck section too, and it does
    /// not take the place of the list's own unrevealed copies.
    func testAGiftBackInTheDeckIsAGiftRowThere() {
        let previous = Player.knownOpponentDeck
        defer { Player.knownOpponentDeck = previous }

        waitForCard("BT_753")
        let game = makeGame()
        Player.knownOpponentDeck = [card("BT_753", 2)]
        _ = addEntity(game, id: 10, cardId: "BT_753", zone: .deck, controller: 2,
                      originalZone: .hand, originalController: 2)

        guard let groups = game.opponent.opponentCardGroups else {
            return XCTFail("a linked opponent deck is grouped")
        }
        XCTAssertEqual(rowStates(groups.deck, "BT_753"), [.plain: 2, gift: 1])
    }

    /// 2.7 round 3: E.T.C.'s pick, played from hand, is a gift in the played
    /// section even when it names a sideboard original as its source; only the
    /// original, set aside at setup and never in hand, stays out (bug T9).
    func testASideboardPickPlayedFromHandIsAGiftInThePlayedSection() {
        waitForCard("ETC_080")
        waitForCard("TOY_644")
        waitForCard("BT_753")

        let game = makeGame()
        setActiveDeck(game, [("ETC_080", 1), ("BT_753", 1)])
        addPlayedDeckCard(game, id: 6, cardId: "ETC_080", controller: 1, originalController: 1)
        createSideboardCardAtSetup(game, id: 34, cardId: "TOY_644", controller: 1)
        let picked = addEntity(game, id: 186, cardId: "TOY_644", zone: .graveyard, controller: 1,
                               originalZone: .hand, originalController: 1, type: .spell)
        picked[.copied_from_entity_id] = 34
        game.player.cardsPlayedThisMatch.append(picked)

        guard let groups = game.player.playerCardGroups else {
            return XCTFail("an active deck is grouped by zone")
        }
        XCTAssertEqual(totals(groups.played), ["ETC_080": 1, "TOY_644": 1])
        // 2.9: the pick is a spell, a spell that was cast has no skull.
        XCTAssertEqual(rowStates(groups.played, "TOY_644"), [gift: 1])
    }

    // MARK: - 2.7 review round 3

    /// Round 3 #1: a card we discovered that also happens to be in E.T.C.'s
    /// sideboard is our gift, not a sideboard card; the sideboard panel does not
    /// account for it, so hiding it would lose it.
    func testADiscoveredCardThatIsAlsoASideboardCardIsAGift() {
        waitForCard("ETC_080")
        waitForCard("TOY_644")
        waitForCard("BT_753")

        let game = makeGame()
        setActiveDeck(game, [("ETC_080", 1), ("BT_753", 1)])
        createSideboardCardAtSetup(game, id: 34, cardId: "TOY_644", controller: 1)
        let discovered = addEntity(game, id: 90, cardId: "TOY_644", zone: .graveyard, controller: 1,
                                   originalZone: .hand, originalController: 1, type: .spell)
        game.player.cardsPlayedThisMatch.append(discovered)

        guard let groups = game.player.playerCardGroups else {
            return XCTFail("an active deck is grouped by zone")
        }
        XCTAssertEqual(rowStates(groups.played, "TOY_644"), [gift: 1])
    }

    /// Round 3 #2: a gift set aside out of the hand and handed back (upstream
    /// calls the first half a discard and never clears it for a card made in
    /// hand), then played and dead. What happened last is that it was played.
    func testAGiftSetAsideAndBackBeforeBeingPlayedIsASkull() {
        let previous = Player.knownOpponentDeck
        defer { Player.knownOpponentDeck = previous }

        waitForCard("VAC_933")
        let game = makeGame()
        let opponent: Player = game.opponent
        Player.knownOpponentDeck = [card("A", 1)]
        let gift = addEntity(game, id: 10, cardId: "VAC_933", zone: .graveyard, controller: 2,
                             originalZone: .hand, originalController: 2)
        opponent.handDiscard(entity: gift, turn: 3)
        opponent.cardsPlayedThisMatch.append(gift)
        opponent.playToGraveyard(entity: gift, turn: 4)

        guard let groups = opponent.opponentCardGroups else {
            return XCTFail("a linked opponent deck is grouped")
        }
        XCTAssertEqual(rowStates(groups.played, "VAC_933"), [giftInGraveyard: 1])
    }

    /// Round 3 #3: a gift in hand replaced by a transformation (恶魔计划) is
    /// left behind in SETASIDE. It is gone, not played and not discarded: it is
    /// in no section — the card that replaced it is the one in hand.
    func testAGiftReplacedInHandIsInNoSection() {
        let previous = Player.knownOpponentDeck
        defer { Player.knownOpponentDeck = previous }

        waitForCard("VAC_933")
        let game = makeGame()
        let opponent: Player = game.opponent
        Player.knownOpponentDeck = [card("A", 1)]
        let replaced = addEntity(game, id: 10, cardId: "VAC_933", zone: .setaside, controller: 2,
                                 originalZone: .hand, originalController: 2)
        opponent.handDiscard(entity: replaced, turn: 3)

        guard let groups = opponent.opponentCardGroups else {
            return XCTFail("a linked opponent deck is grouped")
        }
        for section in [groups.deck, groups.hand, groups.played] {
            XCTAssertNil(totals(section)["VAC_933"])
        }
    }

    /// The same for a deck list card: it did leave the deck, so it stays in the
    /// played section as before 2.7, only without a status icon.
    func testADeckListCardReplacedInHandStaysPlayedWithoutAStatus() {
        let previous = Player.knownOpponentDeck
        defer { Player.knownOpponentDeck = previous }

        waitForCard("BT_753")
        let game = makeGame()
        let opponent: Player = game.opponent
        Player.knownOpponentDeck = [card("BT_753", 1)]
        let replaced = addEntity(game, id: 10, cardId: "BT_753", zone: .setaside, controller: 2,
                                 originalZone: .deck, originalController: 2)
        opponent.handDiscard(entity: replaced, turn: 3)

        guard let groups = opponent.opponentCardGroups else {
            return XCTFail("a linked opponent deck is grouped")
        }
        XCTAssertEqual(rowStates(groups.played, "BT_753"), [.plain: 1])
        assertNoCardIsLost(groups, known: ["BT_753": 1])
    }

    /// Round 3 #4: a token summoned straight onto the board, bounced to hand,
    /// then pulled back onto the board without being played. It has been in
    /// hand (`info.returned`), so it is a gift in the played section.
    func testABouncedTokenPulledOntoTheBoardIsInThePlayedSection() {
        let previous = Player.knownOpponentDeck
        defer { Player.knownOpponentDeck = previous }

        waitForCard("VAC_933")
        let game = makeGame()
        let opponent: Player = game.opponent
        Player.knownOpponentDeck = [card("A", 1)]
        let token = addEntity(game, id: 10, cardId: "VAC_933", zone: .play, controller: 2,
                              originalZone: .play, originalController: 2)
        opponent.boardToHand(entity: token, turn: 3)

        guard let groups = opponent.opponentCardGroups else {
            return XCTFail("a linked opponent deck is grouped")
        }
        XCTAssertEqual(rowStates(groups.played, "VAC_933"), [gift: 1])
    }

    // MARK: - Phase 2 / 2.9: the skull is a minion that died

    /// A minion on the board that then dies the way the parser reports it:
    /// PLAY → GRAVEYARD under `controller`.
    private func die(_ entity: Entity, _ player: Player) {
        entity[.zone] = Zone.graveyard.rawValue
        player.playToGraveyard(entity: entity, turn: 5)
    }

    /// The user's report: a spell that was cast and a weapon that was used up
    /// are in the graveyard zone too, and used to carry the skull. Only the
    /// minion that died does. A minion card that reached the graveyard zone
    /// without dying (a discover option nobody picked goes there) has none.
    func testOnlyAMinionThatDiedCarriesTheSkull() {
        let previous = Player.knownOpponentDeck
        defer { Player.knownOpponentDeck = previous }

        for id in ["BT_753", "SC_010", "SW_041", "VAC_933", "SW_039", "EX1_610"] {
            waitForCard(id)
        }
        let game = makeGame()
        let opponent: Player = game.opponent
        Player.knownOpponentDeck = [card("BT_753", 1), card("SC_010", 1), card("SW_041", 1),
                                    card("VAC_933", 1), card("SW_039", 1)]

        let spell = addEntity(game, id: 10, cardId: "BT_753", zone: .graveyard, controller: 2,
                              originalZone: .deck, originalController: 2, type: .spell)
        opponent.cardsPlayedThisMatch.append(spell)
        opponent.spellsPlayedCards.append(spell)
        let weapon = addEntity(game, id: 11, cardId: "SC_010", zone: .graveyard, controller: 2,
                               originalZone: .deck, originalController: 2, type: .weapon)
        opponent.cardsPlayedThisMatch.append(weapon)
        // Upstream files a weapon and a location leaving play under the same
        // handler as a death; neither is a minion.
        opponent.playToGraveyard(entity: weapon, turn: 4)
        let location = addEntity(game, id: 12, cardId: "SW_041", zone: .graveyard, controller: 2,
                                 originalZone: .deck, originalController: 2, type: .location)
        opponent.cardsPlayedThisMatch.append(location)
        opponent.playToGraveyard(entity: location, turn: 4)
        // A minion that died silenced and buffed is still its own card.
        let minion = addEntity(game, id: 13, cardId: "VAC_933", zone: .play, controller: 2,
                               originalZone: .deck, originalController: 2)
        minion[.silenced] = 1
        minion[.atk] = 9
        opponent.cardsPlayedThisMatch.append(minion)
        die(minion, opponent)
        // A gift secret that fired, and a minion card in the graveyard zone
        // that never was on the board.
        _ = addEntity(game, id: 14, cardId: "EX1_610", zone: .graveyard, controller: 2,
                      originalZone: .hand, originalController: 2, type: .spell)
        let notDead = addEntity(game, id: 15, cardId: "SW_039", zone: .graveyard, controller: 2,
                                originalZone: .deck, originalController: 2)
        opponent.cardsPlayedThisMatch.append(notDead)

        guard let groups = opponent.opponentCardGroups else {
            return XCTFail("a linked opponent deck is grouped")
        }
        XCTAssertEqual(rowStates(groups.played, "BT_753"), [.plain: 1], "a spell that was cast")
        XCTAssertEqual(rowStates(groups.played, "SC_010"), [.plain: 1], "a weapon that was used up")
        XCTAssertEqual(rowStates(groups.played, "SW_041"), [.plain: 1], "a location that was used up")
        XCTAssertEqual(rowStates(groups.played, "VAC_933"), [graveyard: 1], "the minion that died")
        XCTAssertEqual(rowStates(groups.played, "EX1_610"), [gift: 1], "a secret that fired")
        XCTAssertEqual(rowStates(groups.played, "SW_039"), [.plain: 1],
                       "in the graveyard zone, but it did not die")
        assertNoCardIsLost(groups, known: ["BT_753": 1, "SC_010": 1, "SW_041": 1,
                                           "VAC_933": 1, "SW_039": 1, "EX1_610": 1])
    }

    /// User, 10-07: a token summoned straight onto the board is in no section
    /// while it lives (2.7), and in the played section with a skull once it is
    /// dead. The invariant grows by exactly the minions that died.
    func testATokenJoinsThePlayedSectionWhenItDies() {
        let previous = Player.knownOpponentDeck
        defer { Player.knownOpponentDeck = previous }

        waitForCard("BT_753")
        waitForCard("VAC_933t")
        let game = makeGame()
        let opponent: Player = game.opponent
        Player.knownOpponentDeck = [card("BT_753", 1)]
        let first = addEntity(game, id: 10, cardId: "VAC_933t", zone: .play, controller: 2,
                              originalZone: .play, originalController: 2)
        let second = addEntity(game, id: 11, cardId: "VAC_933t", zone: .play, controller: 2,
                               originalZone: .play, originalController: 2)
        // A token copy of a deck list card: its skull may not land on, or
        // take away, the list's own copy.
        let copy = addEntity(game, id: 12, cardId: "BT_753", zone: .play, controller: 2,
                             originalZone: .play, originalController: 2)

        guard let alive = opponent.opponentCardGroups else {
            return XCTFail("a linked opponent deck is grouped")
        }
        XCTAssertTrue(alive.played.isEmpty, "a living token is in no section")
        assertNoCardIsLost(alive, known: ["BT_753": 1])

        die(first, opponent)
        die(copy, opponent)
        guard let oneDead = opponent.opponentCardGroups else {
            return XCTFail("a linked opponent deck is grouped")
        }
        XCTAssertEqual(rowStates(oneDead.played, "VAC_933t"), [giftInGraveyard: 1])
        XCTAssertEqual(rowStates(oneDead.played, "BT_753"), [giftInGraveyard: 1])
        XCTAssertEqual(rowStates(oneDead.deck, "BT_753"), [.plain: 1], "the list's copy is still in the deck")
        assertNoCardIsLost(oneDead, known: ["BT_753": 2, "VAC_933t": 1])

        die(second, opponent)
        guard let bothDead = opponent.opponentCardGroups else {
            return XCTFail("a linked opponent deck is grouped")
        }
        XCTAssertEqual(rowStates(bothDead.played, "VAC_933t"), [giftInGraveyard: 2])
        assertNoCardIsLost(bothDead, known: ["BT_753": 2, "VAC_933t": 2])
    }

    /// The transformation the user reported, fed through the real parser with
    /// the lines of the 2026-10-07 Power.log (16:37:50 / 16:38:57): entity 139
    /// is a 索利托斯 token on our board, CHANGE_ENTITY turns it into
    /// 希拉柯丝教徒 (TSC_955) in place, and that is what dies. The parser keeps
    /// `cardId` on the token and the new card in `info.latestCardId`.
    func testAMinionTransformedInPlayDiesAsWhatItBecame() {
        waitForCard("TLC_817t5")
        waitForCard("TSC_955")
        waitForCard("BT_753")
        let launched = Date().addingTimeInterval(30)
        while AppDelegate.instance().coreManager == nil && Date() < launched {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }

        let game = makeGame()
        game.player.id = 2
        game.opponent.id = 1
        setActiveDeck(game, [("BT_753", 1)])
        let token = addEntity(game, id: 139, cardId: "TLC_817t5", zone: .play, controller: 2,
                              originalZone: .play, originalController: 2)
        // It was summoned as the token; the latch itself is fed through the
        // parser in `testAMinionThatChangedInHandDiesOnItsOwnRow`.
        token.cardIdOnEnteringPlay = "TLC_817t5"

        let parser = PowerGameStateParser(with: game)
        // swiftlint:disable line_length
        let lines = [
            "D 16:37:50.2525630 PowerTaskList.DebugPrintPower() -     CHANGE_ENTITY - Updating Entity=[entityName=索利托斯，循环新生 id=139 zone=PLAY zonePos=1 cardId=TLC_817t5 player=2] CardID=TSC_955",
            "D 16:37:50.2525630 PowerTaskList.DebugPrintPower() -         tag=CARDTYPE value=MINION",
            "D 16:38:57.3923170 PowerTaskList.DebugPrintPower() -     TAG_CHANGE Entity=[entityName=希拉柯丝教徒 id=139 zone=PLAY zonePos=1 cardId=TSC_955 player=2] tag=ZONE value=GRAVEYARD "
        ]
        // swiftlint:enable line_length
        parser.handle(logLine: LogLine(namespace: .power, line: lines[0]))
        parser.handle(logLine: LogLine(namespace: .power, line: lines[1]))
        guard let transformed = game.player.playerCardGroups else {
            return XCTFail("an active deck is grouped by zone")
        }
        XCTAssertTrue(transformed.played.isEmpty, "still a living token")

        parser.handle(logLine: LogLine(namespace: .power, line: lines[2]))
        XCTAssertEqual(game.entities[139]?.cardId, "TLC_817t5", "the parser keeps the card it started as")
        XCTAssertEqual(game.entities[139]?.info.latestCardId, "TSC_955")
        XCTAssertTrue(game.entities[139]?.isInGraveyard ?? false)
        XCTAssertTrue(game.player.deadMinionsCards.contains { $0.id == 139 },
                      "PLAY → GRAVEYARD is what upstream records as a minion's death")

        guard let groups = game.player.playerCardGroups else {
            return XCTFail("an active deck is grouped by zone")
        }
        XCTAssertEqual(rowStates(groups.played, "TSC_955"), [giftInGraveyard: 1],
                       "the graveyard holds what it was when it died")
        XCTAssertNil(totals(groups.played)["TLC_817t5"], "the token itself never was in hand and did not die")
        assertNoCardIsLost(groups, known: ["BT_753": 1, "TSC_955": 1])
    }

    /// User, 10-07: a card played from hand, transformed on the board and then
    /// dead is two rows — the card that was played, without an icon, and what
    /// it died as, with the skull. For a deck list card and for a gift alike.
    func testAPlayedCardThatDiedTransformedKeepsARowWithoutAnIcon() {
        let previous = Player.knownOpponentDeck
        defer { Player.knownOpponentDeck = previous }

        for id in ["BT_753", "VAC_933", "TSC_955"] {
            waitForCard(id)
        }
        let game = makeGame()
        let opponent: Player = game.opponent
        Player.knownOpponentDeck = [card("BT_753", 1)]
        let listed = addEntity(game, id: 10, cardId: "BT_753", zone: .play, controller: 2,
                               originalZone: .deck, originalController: 2)
        opponent.cardsPlayedThisMatch.append(listed)
        let discovered = addEntity(game, id: 11, cardId: "VAC_933", zone: .play, controller: 2,
                                   originalZone: .hand, originalController: 2)
        opponent.cardsPlayedThisMatch.append(discovered)
        for entity in [listed, discovered] {
            entity.cardIdOnEnteringPlay = entity.cardId
            entity.info.latestCardId = "TSC_955"
        }

        guard let alive = opponent.opponentCardGroups else {
            return XCTFail("a linked opponent deck is grouped")
        }
        XCTAssertEqual(rowStates(alive.played, "BT_753"), [.plain: 1])
        XCTAssertEqual(rowStates(alive.played, "VAC_933"), [gift: 1])
        XCTAssertNil(totals(alive.played)["TSC_955"], "nothing died yet")

        die(listed, opponent)
        die(discovered, opponent)
        guard let groups = opponent.opponentCardGroups else {
            return XCTFail("a linked opponent deck is grouped")
        }
        XCTAssertEqual(rowStates(groups.played, "BT_753"), [.plain: 1], "played, but it did not die as this")
        XCTAssertEqual(rowStates(groups.played, "VAC_933"), [gift: 1])
        XCTAssertEqual(rowStates(groups.played, "TSC_955"), [giftInGraveyard: 2])
        XCTAssertNil(totals(groups.deck)["BT_753"], "the list's copy left the deck")
        assertNoCardIsLost(groups, known: ["BT_753": 1, "VAC_933": 1, "TSC_955": 2])
    }

    // MARK: - 2.9 round 2: a card that changed in hand is not a transformation

    /// A deck list card of ours in hand, fed through the real parser from
    /// there on. The user's logs only hold hand CHANGE_ENTITY on spells, so
    /// the first line is one of those verbatim (2026-10-07 Power.log line
    /// 13633, 造物协议 TTN_430 → TTN_430t being forged) and the entity it lands
    /// on is tagged a minion by hand: what is under test is where the parser
    /// leaves `cardId` / `latestCardId` and what the latch reads when the
    /// entity enters play, neither of which looks at the card type. The ZONE
    /// lines are that log's own lines 2614 and 43333 with the entity swapped.
    // swiftlint:disable line_length
    private static let changedInHand =
        "D 16:28:32.2215440 PowerTaskList.DebugPrintPower() -     CHANGE_ENTITY - Updating Entity=[entityName=造物协议 id=41 zone=HAND zonePos=2 cardId=TTN_430 player=2] CardID=TTN_430t"
    private static let played =
        "D 16:28:40.0860650 PowerTaskList.DebugPrintPower() -     TAG_CHANGE Entity=[entityName=造物协议 id=41 zone=HAND zonePos=2 cardId=TTN_430t player=2] tag=ZONE value=PLAY "
    private static let transformedInPlay =
        "D 16:37:50.2525630 PowerTaskList.DebugPrintPower() -     CHANGE_ENTITY - Updating Entity=[entityName=造物协议 id=41 zone=PLAY zonePos=1 cardId=TTN_430t player=2] CardID=TSC_955"
    private static let died =
        "D 16:38:57.3923170 PowerTaskList.DebugPrintPower() -     TAG_CHANGE Entity=[entityName=造物协议 id=41 zone=PLAY zonePos=1 cardId=TTN_430t player=2] tag=ZONE value=GRAVEYARD "
    // swiftlint:enable line_length

    private func ourGameWithACardInHand() -> (Game, PowerGameStateParser) {
        for id in ["TTN_430", "TTN_430t", "TSC_955"] {
            waitForCard(id)
        }
        let launched = Date().addingTimeInterval(30)
        while AppDelegate.instance().coreManager == nil && Date() < launched {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        let game = makeGame()
        game.player.id = 2
        game.opponent.id = 1
        setActiveDeck(game, [("TTN_430", 1)])
        _ = addEntity(game, id: 41, cardId: "TTN_430", zone: .hand, controller: 2,
                      originalZone: .deck, originalController: 2)
        return (game, PowerGameStateParser(with: game))
    }

    /// Changed in hand, played, dead: one row, the deck list's card, with the
    /// skull. No second row for what it had become, and no gift.
    func testAMinionThatChangedInHandDiesOnItsOwnRow() {
        let (game, parser) = ourGameWithACardInHand()
        for line in [Self.changedInHand, Self.played] {
            parser.handle(logLine: LogLine(namespace: .power, line: line))
        }
        XCTAssertEqual(game.entities[41]?.cardId, "TTN_430")
        XCTAssertEqual(game.entities[41]?.info.latestCardId, "TTN_430t")
        XCTAssertEqual(game.entities[41]?.cardIdOnEnteringPlay, "TTN_430t",
                       "it came into play as what it had become in hand")
        XCTAssertTrue(game.entities[41]?.isInPlay ?? false)

        parser.handle(logLine: LogLine(namespace: .power, line: Self.died))
        XCTAssertTrue(game.player.deadMinionsCards.contains { $0.id == 41 })
        guard let groups = game.player.playerCardGroups else {
            return XCTFail("an active deck is grouped by zone")
        }
        XCTAssertEqual(rowStates(groups.played, "TTN_430"), [graveyard: 1])
        XCTAssertNil(totals(groups.played)["TTN_430t"], "a change in hand is not a second card")
        assertNoCardIsLost(groups, known: ["TTN_430": 1])
    }

    /// Changed in hand, played, transformed on the board, dead: the board
    /// transformation is the one that counts, so the played card keeps a row
    /// without an icon and the skull is on what it died as.
    func testAMinionThatChangedInHandAndWasTransformedInPlayDiesAsWhatItBecame() {
        let (game, parser) = ourGameWithACardInHand()
        for line in [Self.changedInHand, Self.played, Self.transformedInPlay, Self.died] {
            parser.handle(logLine: LogLine(namespace: .power, line: line))
        }
        XCTAssertEqual(game.entities[41]?.cardIdOnEnteringPlay, "TTN_430t")
        XCTAssertEqual(game.entities[41]?.info.latestCardId, "TSC_955")
        guard let groups = game.player.playerCardGroups else {
            return XCTFail("an active deck is grouped by zone")
        }
        XCTAssertEqual(rowStates(groups.played, "TTN_430"), [.plain: 1])
        XCTAssertEqual(rowStates(groups.played, "TSC_955"), [giftInGraveyard: 1])
        XCTAssertNil(totals(groups.played)["TTN_430t"])
        assertNoCardIsLost(groups, known: ["TTN_430": 1, "TSC_955": 1])
    }

    /// A gift that changed in hand before it was played and died: one gift
    /// row with the skull. And without the latch (the tracker was started
    /// after the minion came into play) a dead minion keeps its one row.
    func testAGiftThatChangedInHandDiesOnItsOwnRow() {
        let previous = Player.knownOpponentDeck
        defer { Player.knownOpponentDeck = previous }

        for id in ["BT_753", "VAC_933", "TSC_955"] {
            waitForCard(id)
        }
        let game = makeGame()
        let opponent: Player = game.opponent
        Player.knownOpponentDeck = [card("BT_753", 1)]
        let discovered = addEntity(game, id: 10, cardId: "VAC_933", zone: .play, controller: 2,
                                   originalZone: .hand, originalController: 2)
        discovered.info.latestCardId = "TSC_955"
        discovered.cardIdOnEnteringPlay = "TSC_955"
        opponent.cardsPlayedThisMatch.append(discovered)
        let unlatched = addEntity(game, id: 11, cardId: "BT_753", zone: .play, controller: 2,
                                  originalZone: .deck, originalController: 2)
        unlatched.info.latestCardId = "TSC_955"
        opponent.cardsPlayedThisMatch.append(unlatched)
        die(discovered, opponent)
        die(unlatched, opponent)

        guard let groups = opponent.opponentCardGroups else {
            return XCTFail("a linked opponent deck is grouped")
        }
        XCTAssertEqual(rowStates(groups.played, "VAC_933"), [giftInGraveyard: 1])
        XCTAssertEqual(rowStates(groups.played, "BT_753"), [graveyard: 1])
        XCTAssertNil(totals(groups.played)["TSC_955"])
        assertNoCardIsLost(groups, known: ["BT_753": 1, "VAC_933": 1])
    }

    /// The graveyard is the side the minion died on. Ours, played from hand,
    /// taken by them and killed over there: on our side a card that was
    /// played, on theirs a minion that died.
    func testAMinionDiesInTheGraveyardOfWhoeverControlledIt() {
        let previous = Player.knownOpponentDeck
        defer { Player.knownOpponentDeck = previous }

        waitForCard("BT_753")
        waitForCard("SC_010")
        let game = makeGame()
        setActiveDeck(game, [("BT_753", 1)])
        Player.knownOpponentDeck = [card("SC_010", 1)]
        let taken = addEntity(game, id: 10, cardId: "BT_753", zone: .play, controller: 2,
                              originalZone: .deck, originalController: 1)
        game.player.cardsPlayedThisMatch.append(taken)
        die(taken, game.opponent)

        guard let ours = game.player.playerCardGroups, let theirs = game.opponent.opponentCardGroups else {
            return XCTFail("both sides are grouped")
        }
        XCTAssertEqual(rowStates(ours.played, "BT_753"), [.plain: 1])
        XCTAssertEqual(rowStates(theirs.played, "BT_753"), [giftInGraveyard: 1])
    }
}
