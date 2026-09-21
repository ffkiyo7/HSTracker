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

/// Bug T10: the **first** game of the 2026-09-19 Power.log (12:13:00), replayed
/// into the 12:16:10 – 12:18:32 window. That is the window the screenshot was
/// taken in: one 发挥优势 (id 59) and one 幽灵视觉 (id 68) are in the graveyard,
/// their second copies (id 60 / id 61) are still in the deck, and
/// 第三道阿古斯传送门 (id 229) has been shuffled in — the three rows the deck
/// section drew. Our side is `player = 2`, our deck is the 30 entities 51…80,
/// all of which are revealed at some point, so the list below is the real one.
///
/// The task book pointed at the fourth game (12:28:39). It does not fit: there
/// the deck section never holds 幽灵视觉 and 发挥优势 together with a portal.
/// This one matches the screenshot card for card, headers included.
class ZoneGroupsT10ReplayTests: HSTrackerTests {

    /// Entities 51…80 of the replayed game, counted by card id.
    private static let deckList: [(String, Int)] = [
        ("BT_354", 1), ("CORE_BT_035", 2), ("CORE_BT_491", 2), ("DEEP_014", 1),
        ("EDR_840", 2), ("END_007", 2), ("ETC_411", 1), ("JAIL_206", 2),
        ("KAR_114", 1), ("NX2_033", 1), ("REV_511", 1), ("RLK_206", 2),
        ("TIME_020", 1), ("TIME_020t1", 1), ("TIME_020t2", 1), ("TOY_645", 2),
        ("TSC_006", 2), ("TSC_608", 2), ("TTN_841", 2), ("WW_403", 1)
    ]

    // Checkpoints inside the screenshot window, given as the block that must
    // NOT be fed yet. The window opens right after 发挥优势 id 59 is played
    // (12:16:10) and closes when 幽灵视觉 id 61 is drawn and played (12:18:32).
    private static let beforeSigilPlayed =
        "BLOCK_START BlockType=PLAY Entity=[entityName=轻蔑印记 id=72"
    private static let beforeMultiStrikePlayed =
        "BLOCK_START BlockType=PLAY Entity=[entityName=多重打击 id=56"
    private static let beforeBladeDancePlayed =
        "BLOCK_START BlockType=PLAY Entity=[entityName=刃舞 id=80"
    private static let beforeSecondPortalPlayed =
        "BLOCK_START BlockType=PLAY Entity=[entityName=第二道阿古斯传送门 id=136"
    private static let beforeAxePlayed =
        "BLOCK_START BlockType=PLAY Entity=[entityName=塞纳留斯之斧 id=70"
    private static let beforeSpectralSightPlayed =
        "BLOCK_START BlockType=PLAY Entity=[entityName=幽灵视觉 id=61"

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
        Settings.showPlayerGet = false

        let launched = Date().addingTimeInterval(30)
        while AppDelegate.instance().coreManager == nil && Date() < launched {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        XCTAssertNotNil(AppDelegate.instance().coreManager, "the test host app never finished launching")

        game = Game(hearthstoneRunState: HearthstoneRunState(isRunning: false, isActive: false))
        parser = PowerGameStateParser(with: game)
        // HearthMirror is not running offline; the replayed game is player 2.
        game.player.id = 2
        game.opponent.id = 1

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
        deck.name = "bug-t10 replay"
        deck.playerClass = .demonhunter
        for (id, count) in Self.deckList {
            deck.cards.append(RealmCard(id: id, count: count))
        }
        game.set(activeDeck: deck, autoDetected: false)
        let deadline = Date().addingTimeInterval(5)
        while game.currentDeck == nil && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        XCTAssertNotNil(game.currentDeck, "the replay needs an active deck to group by zone")
    }

    private func loadFixture() {
        guard let url = Bundle(for: ZoneGroupsT10ReplayTests.self)
            .url(forResource: "2026-09-19-bug-t10", withExtension: "log"),
            let content = try? String(contentsOf: url, encoding: .utf8) else {
            XCTFail("the replay fixture is missing from the test bundle")
            return
        }
        lines = content.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        XCTAssertGreaterThan(lines.count, 10000)
    }

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

    private func groups(line: UInt = #line) -> CardZoneGroups {
        guard let groups = game.player.playerCardGroups else {
            XCTFail("zone groups are not available", line: line)
            return CardZoneGroups(deck: [], hand: [], played: [])
        }
        return groups
    }

    private func handFromEntities() -> [String: Int] {
        var result = [String: Int]()
        for entity in game.player.hand where entity.hasCardId && Cards.by(cardId: entity.cardId) != nil {
            result[entity.cardId] = (result[entity.cardId] ?? 0) + 1
        }
        return result
    }

    // MARK: - The window in the screenshot

    /// The instant the screenshot was taken: 12:17:49, right before 塞纳留斯之斧
    /// is played. This is the whole point of the replay — the numbers the panel
    /// drew (`发挥优势 ×2`, `幽灵视觉 ×2`, a hand section of three with two rows)
    /// are **not** what the zone split says. The split says three rows of one in
    /// each section, which is exactly what the two section headers read, so the
    /// disagreement is in the drawing, not in the accounting.
    func testTheScreenshotMomentIsThreeSingleCopiesInEachSection() {
        feed(upTo: Self.beforeAxePlayed)
        let deck = counts(groups().deck)
        XCTAssertEqual(deck, ["TIME_020t4": 1, "END_007": 1, "CORE_BT_491": 1],
                       "the three rows the screenshot shows, one copy each")
        XCTAssertEqual(groups().deck.count, 3)
        XCTAssertEqual(groups().deck.reduce(0) { $0 + abs($1.count) }, 3,
                       "the deck section header said (3)")

        let hand = counts(groups().hand)
        XCTAssertEqual(hand, ["NX2_033": 1, "TIME_020t1": 1, "TSC_608": 1],
                       "无底海渊, 塞纳留斯之斧 and 巨怪塔迪乌斯 — the screenshot drew two of them")
        XCTAssertEqual(groups().hand.reduce(0) { $0 + abs($1.count) }, 3,
                       "the hand section header said (3)")
    }

    /// The bug: one 发挥优势 (id 59) was played at 12:16:10, so the deck section
    /// owes exactly one — the screenshot shows two.
    func testOnlyOnePressTheAdvantageIsLeftInTheDeck() {
        feed(upTo: Self.beforeSpectralSightPlayed)
        XCTAssertEqual(counts(groups().deck)["END_007"], 1,
                       "one copy was played at 12:16:10, the other is still in the deck")
        XCTAssertEqual(counts(groups().played)["END_007"], 1)
    }

    /// One 幽灵视觉 (id 68) was played at 12:15:19; the other (id 61) is the one
    /// still in the deck, so the section owes one, not two.
    func testOnlyOneSpectralSightIsLeftInTheDeck() {
        // At the screenshot moment; by 12:18:32 the second copy has been drawn
        // and the deck section is rightly empty of it.
        feed(upTo: Self.beforeAxePlayed)
        XCTAssertEqual(counts(groups().deck)["CORE_BT_491"], 1,
                       "one copy was played at 12:15:19, the other is still in the deck")
        XCTAssertEqual(counts(groups().played)["CORE_BT_491"], 1)
    }

    /// The hand section is the hand, all the way through the window.
    func testHandSectionMatchesTheHandThroughTheWindow() {
        for marker in [Self.beforeSigilPlayed, Self.beforeMultiStrikePlayed,
                       Self.beforeBladeDancePlayed, Self.beforeSecondPortalPlayed,
                       Self.beforeAxePlayed, Self.beforeSpectralSightPlayed] {
            feed(upTo: marker)
            XCTAssertEqual(counts(groups().hand), handFromEntities(),
                           "hand section does not match the hand at \(marker)")
        }
    }

    /// The regression guard T7 / T8 left behind, on this game's deck: no card of
    /// the deck list may be counted in the deck section above its list count.
    func testNoDeckListCardIsCountedAboveItsListCount() {
        for marker in [Self.beforeSigilPlayed, Self.beforeMultiStrikePlayed,
                       Self.beforeBladeDancePlayed, Self.beforeSecondPortalPlayed,
                       Self.beforeAxePlayed, Self.beforeSpectralSightPlayed] {
            feed(upTo: marker)
            let deck = counts(groups().deck)
            for (id, count) in Self.deckList {
                XCTAssertLessThanOrEqual(deck[id] ?? 0, count,
                                         "\(id) is counted above its deck list count at \(marker)")
            }
        }
    }
}

/// Bug T11, symptom ①: the 2026-09-20 Power.log, wild ladder, one whole game
/// (23:35:12 → 23:51:43) fed the way the live app sees it, **reconnect and all**.
/// Our side is `player = 2`, a 40 card Renathal deck (entities 51…93 minus the
/// starship pieces 57/58/59, which are set aside).
///
/// The client drops at 23:41:57 and the server dumps a second `CREATE_GAME`
/// with every entity re-created. `PowerGameStateParser` answers that with its
/// own `reset()` only — `eventHandler.gameStart` is commented out there — so
/// `Game` keeps every entity, every latched flag and every `info` field from
/// before the drop and has the re-dump land on top. The fixture starts at the
/// *first* `CREATE_GAME` so the replay goes through that, rather than starting
/// clean at the second one.
///
/// The opponent's 爆破工头索格伦 (`WW_372`) shuffles TNT (`WW_372t`) into our
/// deck. Two of them go off:
///
/// - 23:41:27, **before** the reconnect: destroys 混乱吞噬 (`TTN_932`, entity 72)
///   out of the hand and 嫉妒乐章 (`ETC_085t`, entity 202 — a copy 罪孽交响曲
///   shuffled in) straight out of the deck.
/// - 23:49:03, **after** it: 情势反转 (`DAL_602`, entity 89) has just shuffled
///   our hand back into the deck, 火焰之灾祸 (`ULD_717`, entity 67) among it;
///   the same draw turns up TNT (entity 217) and its CASTS_WHEN_DRAWN trigger
///   destroys 亵渎 (entity 79) out of the hand and 火焰之灾祸 straight out of the
///   deck — `SHOW_ENTITY … zone=DECK` and `ZONE=GRAVEYARD` in the same block.
class ZoneGroupsT11ReplayTests: HSTrackerTests {

    /// The 31 of our 40 deck cards the game reveals. The rest never leaves the
    /// deck, so it cannot move any assertion below.
    private static let deckList: [(String, Int)] = [
        ("BAR_910", 1), ("BOT_913", 1), ("CATA_496", 1), ("CORE_KAR_061", 1),
        ("CORE_SCH_713", 1), ("DAL_602", 1), ("DEEP_032", 1), ("END_017", 1),
        ("ETC_071", 1), ("ETC_080", 1), ("ETC_084", 1), ("ETC_085", 1),
        ("GVG_108", 1), ("ICC_041", 1), ("ICC_903", 1), ("JAIL_515", 1),
        ("LOOT_017", 1), ("MIS_027", 1), ("REV_018", 1), ("RLK_536", 1),
        ("SCH_514", 1), ("TLC_106", 1), ("TLC_451", 1), ("TSC_908", 1),
        ("TTN_932", 1), ("TTN_960", 1), ("ULD_003", 1), ("ULD_717", 1),
        ("WW_0700", 1)
    ]

    /// 火焰之灾祸, the deck list card the second bomb destroys inside the deck.
    private static let plagueOfFlames = "ULD_717"
    /// 亵渎, the deck list card the same bomb destroys out of the hand.
    private static let defile = "ICC_041"
    /// 嫉妒乐章, the shuffled in copy the first bomb destroys inside the deck.
    private static let envy = "ETC_085t"
    /// 混乱吞噬, the deck list card the first bomb destroys out of the hand.
    private static let chaos = "TTN_932"
    /// TNT, shuffled into our deck by the opponent's 爆破工头索格伦.
    private static let bomb = "WW_372t"

    // Checkpoints, given as the block that must NOT be fed yet. All of them are
    // `PowerTaskList` lines, because that is the only half `feedOne` parses.
    private static let beforeTheFirstBomb =
        "PowerTaskList.DebugPrintPower() - BLOCK_START BlockType=TRIGGER Entity=[entityName=TNT炸药 id=215"
    /// The reconnect itself: the second `CREATE_GAME`. Reached from a cursor
    /// that is already past the first one.
    private static let beforeTheReconnect =
        "PowerTaskList.DebugPrintPower() -     CREATE_GAME"
    /// The first block of real play after the re-dump, 23:42:15.
    private static let afterTheReconnect =
        "PowerTaskList.DebugPrintPower() - BLOCK_START BlockType=PLAY Entity=[entityName=血色狂欢者 id=93"
    private static let beforeTheBombGoesOff =
        "PowerTaskList.DebugPrintPower() - BLOCK_START BlockType=TRIGGER Entity=[entityName=TNT炸药 id=217"
    /// The next bomb, 23:49:12 — the first block after the one we watch, so the
    /// block we watch is closed and its queued creation tags have been flushed.
    private static let afterTheBombWentOff =
        "PowerTaskList.DebugPrintPower() - BLOCK_START BlockType=TRIGGER Entity=[entityName=TNT炸药 id=219"

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
        Settings.showPlayerGet = false

        let launched = Date().addingTimeInterval(30)
        while AppDelegate.instance().coreManager == nil && Date() < launched {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        XCTAssertNotNil(AppDelegate.instance().coreManager, "the test host app never finished launching")

        game = Game(hearthstoneRunState: HearthstoneRunState(isRunning: false, isActive: false))
        parser = PowerGameStateParser(with: game)
        // HearthMirror is not running offline; the replayed game is player 2.
        game.player.id = 2
        game.opponent.id = 1

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
        deck.name = "bug-t11 replay"
        deck.playerClass = .warlock
        for (id, count) in Self.deckList {
            deck.cards.append(RealmCard(id: id, count: count))
        }
        game.set(activeDeck: deck, autoDetected: false)
        let deadline = Date().addingTimeInterval(5)
        while game.currentDeck == nil && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        XCTAssertNotNil(game.currentDeck, "the replay needs an active deck to group by zone")
    }

    private func loadFixture() {
        guard let url = Bundle(for: ZoneGroupsT11ReplayTests.self)
            .url(forResource: "2026-09-20-bug-t11", withExtension: "log"),
            let content = try? String(contentsOf: url, encoding: .utf8) else {
            XCTFail("the replay fixture is missing from the test bundle")
            return
        }
        lines = content.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        XCTAssertGreaterThan(lines.count, 10000)
    }

    /// One line, routed the way `LogReaderManager.processLine` routes it: a
    /// `GameState.` line goes to the power log and the choices handler and
    /// **never** reaches `PowerGameStateParser`. Only the
    /// `PowerTaskList.DebugPrintPower` half is parsed.
    ///
    /// The T6 / T10 classes above feed both halves, which is not what the app
    /// does — and in this game it is not harmless: the GameState half writes
    /// `FULL_ENTITY - Creating ID=<n>` where PowerTaskList writes
    /// `FULL_ENTITY - Updating [… id=<n> …]`, and only the second form matches
    /// `PowerGameStateParser.CreationRegex`. So the creating form leaves
    /// `currentEntityId` on the previous entity and the whole tag block lands on
    /// it. Here that put a stray `CREATOR` on 末日管弦家林恩 (entity 69) and
    /// `markShuffledIntoDeck` latched a deck list card, counting it twice.
    private func feedOne(_ line: String) {
        let logLine = LogLine(namespace: .power, line: line)
        guard logLine.content.hasPrefix("PowerTaskList.DebugPrintPower") else { return }
        parser.handle(logLine: logLine)
    }

    private func feed(upTo marker: String) {
        guard let stop = lines[cursor...].firstIndex(where: { $0.contains(marker) }) else {
            XCTFail("checkpoint not found in the fixture: \(marker)")
            return
        }
        while cursor < stop {
            feedOne(lines[cursor])
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

    private func groups(line: UInt = #line) -> CardZoneGroups {
        guard let groups = game.player.playerCardGroups else {
            XCTFail("zone groups are not available", line: line)
            return CardZoneGroups(deck: [], hand: [], played: [])
        }
        return groups
    }

    private func handFromEntities() -> [String: Int] {
        var result = [String: Int]()
        for entity in game.player.hand where entity.hasCardId && Cards.by(cardId: entity.cardId) != nil {
            result[entity.cardId] = (result[entity.cardId] ?? 0) + 1
        }
        return result
    }

    /// What our deck really holds for `cardId`: the entities sitting in the deck
    /// zone plus the deck list copies that were never revealed. Only usable for
    /// a card whose every copy has been revealed at some point, which is the
    /// case for 火焰之灾祸 and 亵渎 (both drawn, both destroyed).
    private func entitiesInDeck(_ cardId: String) -> Int {
        return game.player.deck.filter { $0.cardId == cardId }.count
    }

    // MARK: - The reconnect

    /// The first bomb, 23:41:27, **before** the drop: 嫉妒乐章 is a copy
    /// 罪孽交响曲 shuffled in, so it is in the deck section as a created row and
    /// has to leave it; 混乱吞噬 is a deck list card in hand and has to leave the
    /// hand section. Both land in the played section.
    func testTheBombBeforeTheReconnectMovesBothCards() {
        feed(upTo: Self.beforeTheFirstBomb)
        XCTAssertEqual(counts(groups().deck)[Self.envy], 1, "the shuffled in copy is in the deck")
        XCTAssertEqual(counts(groups().hand)[Self.chaos], 1)
        let envyPlayedBefore = counts(groups().played)[Self.envy] ?? 0

        feed(upTo: Self.beforeTheReconnect)
        XCTAssertNil(counts(groups().deck)[Self.envy],
                     "a copy destroyed inside the deck may not stay in the deck section")
        XCTAssertEqual(counts(groups().played)[Self.envy], envyPlayedBefore + 1)
        XCTAssertNil(counts(groups().hand)[Self.chaos])
        XCTAssertEqual(counts(groups().played)[Self.chaos], 1)
    }

    /// The drop itself. `PowerGameStateParser` answers the second `CREATE_GAME`
    /// with its own `reset()` and nothing else, so `Game` keeps every entity and
    /// the server's full re-dump lands on top of them. Nothing may be counted
    /// twice, and nothing the first bomb destroyed may come back.
    func testTheReconnectDoesNotDoubleCountOrResurrect() {
        // The first game's own `CREATE_GAME` matches the reconnect marker too,
        // so the cursor has to be past it before asking for the second one.
        feed(upTo: Self.beforeTheFirstBomb)
        feed(upTo: Self.beforeTheReconnect)
        let deckBefore = counts(groups().deck)
        let playedBefore = counts(groups().played)
        XCTAssertNotNil(playedBefore[Self.envy], "the first bomb has gone off by now")

        feed(upTo: Self.afterTheReconnect)
        XCTAssertEqual(counts(groups().played), playedBefore,
                       "the re-dump changed the played section")
        XCTAssertNil(counts(groups().deck)[Self.envy],
                     "the re-dump put a destroyed copy back in the deck")
        XCTAssertEqual(counts(groups().deck)[Self.bomb], deckBefore[Self.bomb],
                       "the shuffled in bombs were counted again")

        // The re-dump may not undo what the parser latched before the drop: a
        // destroyed card that lost `originalZone` / `originalController` would
        // silently fall out of "left the deck" and keep its deck section row.
        for id in [202, 72] {
            let entity = game.entities.values.first { $0.id == id }
            XCTAssertEqual(entity?.info.originalZone, Zone.deck, "\(id) lost its original zone")
            XCTAssertEqual(entity?.info.originalController, game.player.id)
            XCTAssertTrue(entity?.info.discarded ?? false, "\(id) lost its discarded flag")
            XCTAssertFalse(entity?.info.hasOutstandingTagChanges ?? true,
                           "\(id) is still hidden from revealedEntities")
        }
        XCTAssertTrue(game.entities.values.first { $0.id == 202 }?.wasShuffledIntoDeck ?? false,
                      "the T8 latch was wiped by the re-dump")
        XCTAssertFalse(game.entities.values.first { $0.id == 72 }?.wasShuffledIntoDeck ?? true,
                       "the re-dump latched a deck list card")
    }

    /// The T8 latch, swept over the whole game: on our side it may only sit on
    /// cards the deck list does not own. 情势反转 shuffles our hand back into the
    /// deck twice in this game, which is exactly the shape T8's 执行结果 wrote
    /// down as untested — a deck list card going back into the deck with
    /// `info.created` already true.
    func testTheShuffledInLatchNeverLandsOnADeckListCard() {
        let listIds = Set(Self.deckList.map { $0.0 })
        sweep { checkpoint in
            let ours = game.entities.values.filter {
                $0.wasShuffledIntoDeck && $0.info.originalController == game.player.id
            }
            XCTAssertTrue(ours.all { !listIds.contains($0.cardId) },
                          "a deck list card was latched as a shuffled in copy at line \(checkpoint): "
                            + ours.filter { listIds.contains($0.cardId) }
                                .map { "\($0.id):\($0.cardId)" }.joined(separator: ", "))
        }
    }

    // MARK: - Symptom ①: a card destroyed inside the deck

    /// The bomb's card. Before it goes off 火焰之灾祸 is back in the deck
    /// (情势反转 shuffled the hand in); after it, the deck section may not list
    /// it any more and the played section owes it.
    func testTheCardTheBombDestroysInTheDeckLeavesTheDeckSection() {
        feed(upTo: Self.beforeTheBombGoesOff)
        XCTAssertEqual(entitiesInDeck(Self.plagueOfFlames), 1, "情势反转 put it back in the deck")
        XCTAssertEqual(counts(groups().deck)[Self.plagueOfFlames], 1)
        XCTAssertNil(counts(groups().played)[Self.plagueOfFlames])

        feed(upTo: Self.afterTheBombWentOff)
        XCTAssertEqual(entitiesInDeck(Self.plagueOfFlames), 0, "the bomb destroyed it")
        XCTAssertNil(counts(groups().deck)[Self.plagueOfFlames],
                     "a card destroyed inside the deck may not stay in the deck section")
        XCTAssertEqual(counts(groups().played)[Self.plagueOfFlames], 1,
                       "it left the deck, so it belongs to the played section")
        XCTAssertNil(counts(groups().hand)[Self.plagueOfFlames])
    }

    /// The same bomb destroys 亵渎 out of the hand. Both halves have to move in
    /// the same refresh, or one of the two sections is left over-counting.
    func testTheCardTheBombDestroysInTheHandLeavesTheHandSection() {
        feed(upTo: Self.beforeTheBombGoesOff)
        XCTAssertEqual(counts(groups().hand)[Self.defile], 1)

        feed(upTo: Self.afterTheBombWentOff)
        XCTAssertNil(counts(groups().hand)[Self.defile])
        XCTAssertNil(counts(groups().deck)[Self.defile],
                     "it was destroyed out of the hand, it did not go back to the deck")
        XCTAssertEqual(counts(groups().played)[Self.defile], 1)
    }

    /// The hand section is the hand, all the way through the replayed game.
    func testHandSectionMatchesTheHandThroughTheGame() {
        sweep { checkpoint in
            XCTAssertEqual(counts(groups().hand), handFromEntities(),
                           "hand section does not match the hand at line \(checkpoint)")
        }
    }

    /// The T7 / T8 guard on this game's deck, swept over the whole fixture
    /// rather than at a handful of blocks: the bomb, the E.T.C. starship pieces
    /// and 情势反转 shuffling the hand back in all move cards across the three
    /// sections, and none of them may push a deck list card above its count.
    func testNoDeckListCardIsCountedAboveItsListCount() {
        let listed = Dictionary(uniqueKeysWithValues: Self.deckList)
        sweep { checkpoint in
            let deck = counts(groups().deck)
            for (id, count) in listed {
                XCTAssertLessThanOrEqual(deck[id] ?? 0, count,
                                         "\(id) is counted above its deck list count at line \(checkpoint)")
            }
            XCTAssertTrue(groups().deck.all { $0.count > 0 },
                          "a zero count row survived in the deck section at line \(checkpoint)")
        }
    }

    /// Feeds the fixture in chunks and runs `check` at every boundary, so an
    /// accounting slip anywhere in the game is caught, not only at the blocks
    /// this file happens to name.
    private func sweep(_ check: (Int) -> Void) {
        let step = 250
        while cursor < lines.count {
            let stop = min(cursor + step, lines.count)
            while cursor < stop {
                feedOne(lines[cursor])
                cursor += 1
            }
            guard game.currentDeck != nil, game.player.playerCardGroups != nil else { continue }
            check(cursor)
        }
    }
}
