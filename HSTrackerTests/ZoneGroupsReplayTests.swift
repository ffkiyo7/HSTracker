//
//  ZoneGroupsReplayTests.swift
//  HSTracker
//
//  Bug T6: offline replay of one standard game from the 2026-09-14 Power.log.
//  The fixture is the verbatim stream of that game as LogReaderManager filters
//  it (`GameState.` and `PowerTaskList.DebugPrintPower` both kept), cut right
//  after the last checkpoint. Feeding only the GameState half leaves
//  `info.hidden` / `originalController` unlike the live app.
//

import XCTest

@testable import HSTracker

class ZoneGroupsReplayTests: HSTrackerTests {

    /// The deck of the replayed game, as far as it was revealed over the whole
    /// game (13 of 30 cards). The unrevealed rest never leaves the deck during
    /// the replayed window, so it cannot change any assertion below.
    private static let deckList: [(String, Int)] = [
        ("BT_490", 1), ("BT_753", 1), ("JAIL_206", 1), ("MAW_014", 1),
        ("SCH_702", 1), ("SC_010", 1), ("SW_037", 2), ("SW_039", 1),
        ("SW_041", 1), ("TIME_020", 1), ("VAC_928", 1), ("VAC_933", 1)
    ]

    /// Patches the Pilot shuffles six Parachutes into the deck.
    private static let parachute = CardIds.NonCollectible.DemonHunter.PatchesthePilot_ParachuteToken

    // Checkpoints, given as the block that must NOT be fed yet.
    private static let beforePatchesPlayed =
        "BLOCK_START BlockType=PLAY Entity=[entityName=飞行员帕奇斯 id=16"
    private static let beforeDarkBargain =
        "BLOCK_START BlockType=POWER Entity=[entityName=黑暗贿赂 id=28"
    private static let beforeFelosophy =
        "BLOCK_START BlockType=POWER Entity=[entityName=邪能学说 id=27"
    private static let beforeCopiedBruteIsPlayed =
        "BLOCK_START BlockType=POWER Entity=[entityName=怒缚蛮兵 id=116"

    private var game: Game!
    private var parser: PowerGameStateParser!
    private var lines = [String]()
    private var cursor = 0

    private var savedActiveDeck: String?
    private var savedShowPlayerGet = false

    override func setUp() {
        super.setUp()
        savedActiveDeck = Settings.activeDeck
        savedShowPlayerGet = Settings.showPlayerGet
        // The machine the feedback came from: "show my gifts" off.
        Settings.showPlayerGet = false

        // `blockStart` reaches through `AppDelegate.instance().coreManager`, which
        // the host app only wires up once it has finished launching.
        let launched = Date().addingTimeInterval(30)
        while AppDelegate.instance().coreManager == nil && Date() < launched {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        XCTAssertNotNil(AppDelegate.instance().coreManager, "the test host app never finished launching")

        game = Game(hearthstoneRunState: HearthstoneRunState(isRunning: false, isActive: false))
        parser = PowerGameStateParser(with: game)
        // HearthMirror is not running offline; the replayed game is player 1.
        game.player.id = 1
        game.opponent.id = 2

        loadDeck()
        loadFixture()
    }

    override func tearDown() {
        Settings.showPlayerGet = savedShowPlayerGet
        Settings.activeDeck = savedActiveDeck
        super.tearDown()
    }

    // MARK: - Harness

    private func loadDeck() {
        let deck = Deck()
        deck.name = "bug-t6 replay"
        deck.playerClass = .demonhunter
        for (id, count) in Self.deckList {
            deck.cards.append(RealmCard(id: id, count: count))
        }
        game.set(activeDeck: deck, autoDetected: false)
        // `set(activeDeck:)` publishes `currentDeck` from the main queue.
        let deadline = Date().addingTimeInterval(5)
        while game.currentDeck == nil && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        XCTAssertNotNil(game.currentDeck, "the replay needs an active deck to group by zone")
    }

    private func loadFixture() {
        guard let url = Bundle(for: ZoneGroupsReplayTests.self)
            .url(forResource: "2026-09-14-standard", withExtension: "log"),
            let content = try? String(contentsOf: url, encoding: .utf8) else {
            XCTFail("the replay fixture is missing from the test bundle")
            return
        }
        lines = content.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        XCTAssertGreaterThan(lines.count, 3000)
    }

    /// Feeds the fixture up to — and not including — the first line containing
    /// `marker`, continuing from wherever the previous checkpoint stopped.
    private func feed(upTo marker: String) {
        guard let stop = lines[cursor...].firstIndex(where: { $0.contains(marker) }) else {
            XCTFail("checkpoint not found in the fixture: \(marker)")
            return
        }
        while cursor < stop {
            parser.handle(logLine: LogLine(namespace: .power, line: lines[cursor]))
            cursor += 1
        }
    }

    private func counts(_ cards: [Card]) -> [String: Int] {
        var result = [String: Int]()
        for card in cards {
            result[card.id] = (result[card.id] ?? 0) + abs(card.count)
        }
        return result
    }

    /// What the hand section has to show: every card actually sitting in the
    /// player's hand, gifts included.
    private func handFromEntities() -> [String: Int] {
        var result = [String: Int]()
        for entity in game.player.hand where entity.hasCardId && Cards.by(cardId: entity.cardId) != nil {
            result[entity.cardId] = (result[entity.cardId] ?? 0) + 1
        }
        return result
    }

    private func groups(line: UInt = #line) -> CardZoneGroups {
        guard let groups = game.player.playerCardGroups else {
            XCTFail("zone groups are not available", line: line)
            return CardZoneGroups(deck: [], hand: [], played: [])
        }
        return groups
    }

    // MARK: - The hand section is the hand

    /// Symptom ②: cards that enter the hand without being drawn from the deck
    /// list (the Coin, a Felosophy copy, a Parachute) never reach the hand
    /// section, because it was still filtered by `Settings.showPlayerGet`.
    func testHandSectionMatchesTheHandAtEveryCheckpoint() {
        for marker in [Self.beforePatchesPlayed, Self.beforeDarkBargain,
                       Self.beforeFelosophy, Self.beforeCopiedBruteIsPlayed] {
            feed(upTo: marker)
            XCTAssertEqual(counts(groups().hand), handFromEntities(),
                           "hand section does not match the hand at \(marker)")
        }
    }

    /// The Coin is in hand from the first turn on: a created card, and the most
    /// visible instance of the section disagreeing with the hand.
    func testTheCoinIsInTheHandSection() {
        feed(upTo: Self.beforePatchesPlayed)
        XCTAssertNotNil(game.player.hand.first { $0.cardId == "TTN_COIN2" },
                        "the replayed hand holds the Coin")
        XCTAssertEqual(counts(groups().hand)["TTN_COIN2"], 1)
    }

    /// 怒缚蛮兵 is drawn out of the deck and flagged `info.created` by the
    /// parser all the same — the flag that used to hide it from the section.
    func testACardCreatedIntoTheHandShowsUp() {
        feed(upTo: Self.beforeCopiedBruteIsPlayed)
        let created = game.player.hand.filter { $0.cardId == "SW_037" }
        XCTAssertFalse(created.isEmpty, "the replayed hand holds the copied brute")
        XCTAssertEqual(counts(groups().hand)["SW_037"], created.count)
    }

    // MARK: - Cards drawn out of the deck

    /// Drawing a deck card moves it from the deck section to the hand section
    /// in the same refresh, and leaves no zero count row behind.
    func testDrawnDeckCardsMoveFromDeckToHand() {
        feed(upTo: Self.beforePatchesPlayed)
        let deck = counts(groups().deck)
        for drawn in ["SW_039", "SW_041", "SCH_702", "VAC_933"] {
            XCTAssertNil(deck[drawn], "\(drawn) was drawn, it must not be in the deck section")
            XCTAssertEqual(counts(groups().hand)[drawn], 1, "\(drawn) must be in the hand section")
        }
        XCTAssertTrue(groups().deck.all { $0.count > 0 })
    }

    // MARK: - Cards shuffled into the deck

    /// Patches shuffles six Parachutes in; they are in the deck section right
    /// away and the count comes down as they are drawn.
    func testShuffledInCardsAreTrackedInTheDeckSection() {
        feed(upTo: Self.beforePatchesPlayed)
        XCTAssertNil(counts(groups().deck)[Self.parachute], "nothing shuffled in yet")

        feed(upTo: Self.beforeDarkBargain)
        XCTAssertEqual(counts(groups().deck)[Self.parachute], 6,
                       "the six shuffled in Parachutes belong to the deck section")

        // Dark Bargain draws three cards; all three turn out to be Parachutes.
        feed(upTo: Self.beforeFelosophy)
        XCTAssertEqual(counts(groups().deck)[Self.parachute], 3,
                       "drawn Parachutes must leave the deck section")
    }

    /// The "shuffled in" signal (a card as creator) must fire on the Parachutes
    /// and on nothing else: if it also fired on a deck list card sitting in the
    /// deck, that card would be counted once by the list and once as an extra
    /// copy, and its deck section row would go above its deck list count.
    func testNoDeckListCardIsCountedAboveItsListCount() {
        for marker in [Self.beforePatchesPlayed, Self.beforeDarkBargain,
                       Self.beforeFelosophy, Self.beforeCopiedBruteIsPlayed] {
            feed(upTo: marker)
            let deck = counts(groups().deck)
            for (id, count) in Self.deckList {
                XCTAssertLessThanOrEqual(deck[id] ?? 0, count,
                                         "\(id) is counted twice in the deck section at \(marker)")
            }
        }
    }

    /// Bug T8: the signal is latched while parsing, so on our side it has to be
    /// on the six Parachutes and on nothing else — and it has to stay on them
    /// once they are drawn, which is the whole point of latching it.
    ///
    /// Scoped to our entities on purpose: the replayed opponent opens with
    /// 阿札莉娜 (`JAIL_430`, entity 52), which builds their deck out of created
    /// copies, so twenty of their cards are legitimately flagged too.
    func testTheShuffledInSignalIsLatchedOnTheShuffledInCopiesOnly() {
        func ourFlagged() -> [Entity] {
            return game.entities.values.filter {
                $0.wasShuffledIntoDeck && $0.isControlled(by: game.player.id)
            }
        }

        feed(upTo: Self.beforeDarkBargain)
        XCTAssertEqual(ourFlagged().count, 6, "the six Parachutes are the only copies shuffled in")
        XCTAssertTrue(ourFlagged().all { $0.cardId == Self.parachute })

        // Dark Bargain draws three of them out of the deck.
        feed(upTo: Self.beforeFelosophy)
        XCTAssertEqual(ourFlagged().count, 6, "being drawn does not undo the signal")
        XCTAssertEqual(ourFlagged().filter { !$0.isInDeck }.count, 3)

        // And it never lands on a card of ours that came from the deck list:
        // dredge, a card coming back from the graveyard and an ordinary draw all
        // set `info.created` too.
        let listIds = Set(Self.deckList.map { $0.0 })
        XCTAssertTrue(ourFlagged().all { !listIds.contains($0.cardId) },
                      "a deck list card was taken for a shuffled in copy")
    }

    /// Bug T9: the sideboard latch only fires while the board is being built, on
    /// entities the game creates straight into SETASIDE. The replayed deck has no
    /// sideboard, so what this asserts is that it does not misfire — nothing that
    /// really came out of the deck list, and nothing shuffled in, may carry it.
    func testTheSetAsideAtSetupSignalNeverLandsOnADeckCard() {
        let listIds = Set(Self.deckList.map { $0.0 })
        for marker in [Self.beforePatchesPlayed, Self.beforeDarkBargain,
                       Self.beforeFelosophy, Self.beforeCopiedBruteIsPlayed] {
            feed(upTo: marker)
            let flagged = game.entities.values.filter { $0.wasSetAsideAtSetup }
            XCTAssertTrue(flagged.all { !listIds.contains($0.cardId) },
                          "a deck list card was taken for a sideboard card at \(marker)")
            XCTAssertTrue(flagged.all { !$0.wasShuffledIntoDeck },
                          "a copy shuffled into the deck was taken for a sideboard card at \(marker)")
            XCTAssertTrue(flagged.all { !$0.isInDeck },
                          "a card in the deck cannot be a sideboard card at \(marker)")
        }
    }

    // MARK: - Cards that change controller

    /// 跳虫 (SC_010, entity 18) is drawn out of the deck and then handed to the
    /// opponent by 黑暗贿赂. It left our deck, so it may not sit in the deck
    /// section waiting to be drawn again — and it is not in our hand either.
    func testADeckCardGivenToTheOpponentLeavesTheDeckSection() {
        feed(upTo: Self.beforeCopiedBruteIsPlayed)
        let stolen = game.entities.values.first { $0.id == 18 }
        XCTAssertEqual(stolen?.cardId, "SC_010")
        XCTAssertEqual(stolen?.info.originalController, game.player.id)
        XCTAssertFalse(stolen?.isControlled(by: game.player.id) ?? true,
                       "the replayed card is under the opponent's control by now")

        XCTAssertNil(counts(groups().deck)["SC_010"],
                     "a card that was drawn and given away is not in the deck anymore")
        XCTAssertNil(counts(groups().hand)["SC_010"], "it is not in our hand either")
        XCTAssertEqual(counts(groups().played)["SC_010"], 1)
    }
}
