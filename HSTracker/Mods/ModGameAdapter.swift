//
//  ModGameAdapter.swift
//  HSTracker
//
//  Fork：ModKit 口子 2（读对局状态）在 app 里的实现。mod 只看见 `ModGameState` / `ModEntity`，
//  上游改 `Game` / `Entity` 时只改这里，mod 不动。
//
//  `ModManager` 每次派发对局事件都新造一个 `ModGameAdapter`，只在那次回调里交给 mod（解析线程，同步）：
//  场攻、剩余牌库这类要算一遍的值在一次回调里只算一次（`lazy`），出了回调这个对象就作废。
//  实体包一层薄壳（`ModEntityAdapter`），不复制 tag。
//

import Foundation
import ModKit

final class ModGameAdapter: ModGameState {
    let game: Game

    init(_ game: Game) {
        self.game = game
    }

    var matchStartTime: Date? { game.isInMenu ? nil : game.startTime }
    var isInMenu: Bool { game.isInMenu }
    var isGameOver: Bool { game.gameEnded }
    var isMulliganDone: Bool { game.isMulliganDone() }
    var isBattlegrounds: Bool { game.isBattlegroundsMatch() }
    var isMercenaries: Bool { game.isMercenariesMatch() }

    var playerId: Int { game.player?.id ?? 0 }
    var opponentId: Int { game.opponent?.id ?? 0 }

    var entities: [any ModEntity] {
        game.entities.values.map { ModEntityAdapter($0) }
    }

    func entity(id: Int) -> (any ModEntity)? {
        game.entities[id].map { ModEntityAdapter($0) }
    }

    var currentDeck: ModDeck? {
        game.currentDeck.map(Self.modDeck)
    }

    static func modDeck(_ deck: PlayingDeck) -> ModDeck {
        var cards: [String: Int] = [:]
        for card in deck.cards {
            cards[card.id, default: 0] += max(card.count, 1)
        }
        var sideboards: [String: [String]] = [:]
        for s in deck.sideboards {
            sideboards[s.ownerCardId, default: []] += s.cards.flatMap { Array(repeating: $0.id, count: max($0.count, 1)) }
        }
        return ModDeck(id: deck.id, name: deck.name, cards: cards, sideboards: sideboards)
    }

    private(set) lazy var remainingDeck: [String: Int] = {
        guard game.currentDeck != nil, let player = game.player else { return [:] }
        var deck: [String: Int] = [:]
        for card in player.getDeckState().remainingInDeck where card.count > 0 {
            deck[card.id, default: 0] += card.count
        }
        return deck
    }()

    private lazy var board = BoardState(game: game)

    var opponentBoardDamage: Int { board.opponent.damage }
    var isPlayerDeadToBoard: Bool { board.isPlayerDeadToBoard() }
}

/// 宿主实体的薄壳。规则由宿主算：区域按 FAKE_ZONE、控制者按佣兵的 LETTUCE_CONTROLLER、
/// 幸运币、CHANGE_ENTITY 之后的新身份；`tag(.zonePosition)` 同样按 FAKE_ZONE_POSITION 修正（宿主的 `zonePosition`）
final class ModEntityAdapter: ModEntity {
    let entity: Entity

    init(_ entity: Entity) {
        self.entity = entity
    }

    var id: Int { entity.id }
    var cardId: String { entity.cardId }

    var currentCardId: String {
        let latest = entity.info.latestCardId
        return latest.isEmpty ? entity.cardId : latest
    }

    var name: String { entity.name ?? "" }

    func tag(_ tag: ModGameTag) -> Int {
        if tag == .zonePosition { return entity.zonePosition }
        guard let known = GameTag(rawValue: tag.rawValue) else { return 0 }
        return entity[known]
    }

    var zone: ModZone {
        let fake = entity[.fake_zone]
        return ModZone(rawValue: fake > 0 ? fake : entity[.zone])
    }

    func isControlled(by playerId: Int) -> Bool { entity.isControlled(by: playerId) }
    var isTheCoin: Bool { entity.isTheCoin }
    var boardOrder: Int? { entity.info.boardOrder }
}
