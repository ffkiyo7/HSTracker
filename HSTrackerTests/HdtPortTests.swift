//
//  HdtPortTests.swift
//  HSTracker
//
//  Package 3: constructed fixes ported from HDT (N'Zoth, C'Thun, Gloomstone Guardian).
//

import XCTest

@testable import HSTracker

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
}
