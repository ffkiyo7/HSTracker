//
//  HdtPortTests.swift
//  HSTracker
//
//  Package 3: constructed fixes ported from HDT (N'Zoth, C'Thun, Gloomstone Guardian).
//

import XCTest

@testable import HSTracker

/// A match's game type only comes from HearthMirror, so counters that gate on
/// `isTraditionalHearthstoneMatch` get a game that says it is one.
private class TraditionalMatchGame: Game {
    override var isTraditionalHearthstoneMatch: Bool { true }
}

class HdtPortTests: HSTrackerTests {

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

    private func deadMinion(id: Int, cardId: String, controller: Int) -> Entity {
        let entity = Entity(id: id)
        entity.cardId = cardId
        entity[.zone] = Zone.graveyard.rawValue
        entity[.controller] = controller
        entity[.cardtype] = CardType.minion.rawValue
        return entity
    }

    // MARK: - W3a N'Zoth, Dream's End (HDT ff1e3ea)

    func testNzothShowsOurDeadDeathrattleMinionsOnceEach() {
        let thalnos = CardIds.Collectible.Neutral.BloodmageThalnos
        let chow = CardIds.Collectible.Neutral.ZombieChow
        let yeti = CardIds.Collectible.Neutral.ChillwindYeti
        let golem = CardIds.Collectible.Neutral.HarvestGolem
        [thalnos, chow, yeti, golem].forEach { waitForCard($0) }

        let game = makeGame()
        game.player.deadMinionsCards = [
            deadMinion(id: 10, cardId: thalnos, controller: 1),
            deadMinion(id: 11, cardId: chow, controller: 1),
            deadMinion(id: 12, cardId: thalnos, controller: 1),
            deadMinion(id: 13, cardId: yeti, controller: 1)
        ]
        game.opponent.deadMinionsCards = [deadMinion(id: 20, cardId: golem, controller: 2)]

        let related = NzothDreamsEnd().getRelatedCards(player: game.player).compactMap { $0?.id }

        XCTAssertEqual(Set(related), [thalnos, chow], "only our dead minions with Deathrattle")
        XCTAssertEqual(related.count, 2, "each minion is listed once")
    }

    func testNzothShowsNothingBeforeAnyDeathrattleMinionDied() {
        let game = makeGame()

        XCTAssertTrue(NzothDreamsEnd().getRelatedCards(player: game.player).isEmpty)
        XCTAssertFalse(NzothDreamsEnd().shouldShowForOpponent(opponent: game.opponent))
    }

    // MARK: - W3b C'Thun, Eye of the Empire (HDT ba5eb9e)

    private let wrath = CardIds.NonCollectible.Neutral.CThunEyeoftheEmpire_WrathOfCthunToken
    private let domain = CardIds.NonCollectible.Neutral.CThunEyeoftheEmpire_DomainOfCthunToken
    private let glare = CardIds.NonCollectible.Neutral.CThunEyeoftheEmpire_GlareOfCthunToken1
    private let servants = CardIds.NonCollectible.Neutral.CThunEyeoftheEmpire_ServantsOfCthunToken

    /// Our C'Thun in hand, so the player counter has something to show before any ability.
    private func makeCthunCounter() -> (TraditionalMatchGame, CthunAbilitiesTriggeredCounter, Entity) {
        let game = TraditionalMatchGame(hearthstoneRunState: HearthstoneRunState(isRunning: false, isActive: false))
        game.player.id = 1
        game.opponent.id = 2
        let cthun = Entity(id: 30)
        cthun.cardId = CardIds.Collectible.Neutral.CthunEyeOfTheEmpire
        cthun[.zone] = Zone.hand.rawValue
        cthun[.controller] = 1
        cthun[.cardtype] = CardType.minion.rawValue
        cthun.info.originalZone = .deck
        game.entities[cthun.id] = cthun
        return (game, CthunAbilitiesTriggeredCounter(controlledByPlayer: true, game: game), cthun)
    }

    private func trigger(_ tag: GameTag, on counter: CthunAbilitiesTriggeredCounter, by entity: Entity) {
        counter.handleTagChange(tag: tag, entity: entity, value: 1, prevValue: 0)
    }

    func testCthunCounterShowsCthunBeforeAnyAbility() {
        let (_, counter, _) = makeCthunCounter()

        XCTAssertEqual(counter.counter, 0)
        XCTAssertEqual(counter.getCardsToDisplay(), [CardIds.Collectible.Neutral.CthunEyeOfTheEmpire])
    }

    func testCthunCounterShowsTheOneAbilityUsed() {
        let (_, counter, cthun) = makeCthunCounter()

        trigger(.cthun_ability3_used, on: counter, by: cthun)

        XCTAssertEqual(counter.counter, 1)
        XCTAssertEqual(counter.getCardsToDisplay(), [glare])
    }

    func testCthunCounterShowsAllFourAbilitiesInHdtOrder() {
        let (_, counter, cthun) = makeCthunCounter()

        for tag in [GameTag.cthun_ability4_used, .cthun_ability1_used, .cthun_ability3_used,
                    .cthun_ability2_used, .cthun_ability1_used] {
            trigger(tag, on: counter, by: cthun)
        }

        XCTAssertEqual(counter.counter, 4, "an ability counts once however often it triggers")
        XCTAssertEqual(counter.getCardsToDisplay(), [wrath, domain, glare, servants])
    }

    // MARK: - W3c Gloomstone Guardian's options when forged (HDT 9564545)

    private let option = CardIds.Collectible.Neutral.ChillwindYeti

    /// A card in hand (id 40) that has been forged, and one of its pre-created
    /// Choose One options (id 81) waiting in SETASIDE.
    private func makeForgeGame(controller: Int, forged: Bool = true) -> (Game, PowerGameStateParser) {
        // `blockStart` reaches through `AppDelegate.instance().coreManager`, which
        // the host app only wires up once it has finished launching.
        let launched = Date().addingTimeInterval(30)
        while AppDelegate.instance().coreManager == nil && Date() < launched {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        XCTAssertNotNil(AppDelegate.instance().coreManager, "the test host app never finished launching")
        waitForCard(option)

        let game = makeGame()
        let parser = PowerGameStateParser(with: game)

        let source = Entity(id: 40)
        source[.zone] = Zone.hand.rawValue
        source[.controller] = controller
        source[.cardtype] = CardType.minion.rawValue
        source.info.forged = forged
        game.entities[source.id] = source

        let choice = Entity(id: 81)
        choice[.zone] = Zone.setaside.rawValue
        choice[.controller] = controller
        game.entities[choice.id] = choice

        return (game, parser)
    }

    private func feed(_ parser: PowerGameStateParser, _ contents: [String]) {
        for content in contents {
            parser.handle(logLine: LogLine(namespace: .power,
                                           line: "D 14:04:05.1234567 GameState.DebugPrintPower() - " + content))
        }
    }

    private func forgeLines(blockType: String, player: Int) -> [String] {
        let source = "[entityName=UNKNOWN ENTITY [cardType=INVALID] id=40 zone=HAND zonePos=3 cardId= player=\(player)]"
        let effect = "EffectCardId=System.Collections.Generic.List`1[System.String]"
        return [
            "BLOCK_START BlockType=\(blockType) Entity=\(source) \(effect) EffectIndex=0 Target=0 SubOption=-1 ",
            "    BLOCK_START BlockType=POWER Entity=\(source) \(effect) EffectIndex=0 Target=0 SubOption=-1 ",
            "        SHOW_ENTITY - Updating Entity=[entityName=UNKNOWN ENTITY [cardType=INVALID] id=81 zone=SETASIDE zonePos=0 cardId= player=\(player)] CardID=\(option)",
            "            tag=CONTROLLER value=\(player)",
            "            tag=CARDTYPE value=MINION",
            "            tag=ZONE value=SETASIDE"
        ]
    }

    func testOpponentForgeHidesTheRevealedOption() {
        let (game, parser) = makeForgeGame(controller: 2)

        feed(parser, forgeLines(blockType: "DECK_ACTION", player: 2))

        XCTAssertEqual(game.entities[81]?.cardId, option)
        XCTAssertEqual(game.entities[81]?.info.hidden, true, "the option would give away the forged card in hand")
    }

    func testOurForgeLeavesTheRevealedOptionVisible() {
        let (game, parser) = makeForgeGame(controller: 1)

        feed(parser, forgeLines(blockType: "DECK_ACTION", player: 1))

        XCTAssertEqual(game.entities[81]?.cardId, option)
        XCTAssertEqual(game.entities[81]?.info.hidden, false)
    }

    func testOpponentPowerOutsideADeckActionIsNotHidden() {
        let (game, parser) = makeForgeGame(controller: 2)

        feed(parser, forgeLines(blockType: "PLAY", player: 2))

        XCTAssertEqual(game.entities[81]?.info.hidden, false)
    }

    func testOpponentDeckActionOfAnUnforgedCardIsNotHidden() {
        let (game, parser) = makeForgeGame(controller: 2, forged: false)

        feed(parser, forgeLines(blockType: "DECK_ACTION", player: 2))

        XCTAssertEqual(game.entities[81]?.info.hidden, false)
    }
}
