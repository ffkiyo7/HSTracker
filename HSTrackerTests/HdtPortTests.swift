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
}
