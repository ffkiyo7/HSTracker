//
//  RedDragonSnapshot.swift
//  HSTracker
//
//  红龙辅助的「局面读取」第一步：把对局里用得到的数据拷成纯值。
//  在解析线程上、一批日志处理完且没有未闭合的 BLOCK 时拷（`RedDragonAssistant.parserBatchDidEnd`）：
//  这时只有本线程会改实体，实体 tag、`BoardState`、`getDeckState()` 读到的是同一时刻。
//  后台线程只碰这份快照，不碰 `Entity`。
//  第二步（快照 → `RDState`）在 RedDragonReader.swift，是纯函数，测试直接喂快照。
//  快照这个值类型（`RDGameSnapshot`）在本地包 RedDragonCore 里（RedDragonGameSnapshot.swift），
//  拷的过程要碰 `Game` / `Entity`，留在 app。
//

import Foundation
@testable import RedDragonCore

extension RDGameSnapshot {

    /// 解析线程在一致边界上调用（见文件头）。读不到双方玩家时返回 nil。
    static func capture(game: Game) -> RDGameSnapshot? {
        let playerId = game.player.id
        let opponentId = game.opponent.id
        guard playerId > 0, opponentId > 0 else { return nil }
        let all = game.entities.values
        let board = BoardState(game: game)
        var deck: [String: Int] = [:]
        if game.currentDeck != nil {
            for card in game.player.getDeckState().remainingInDeck where card.count > 0 {
                deck[card.id, default: 0] += card.count
            }
        }
        let band = game.currentDeck?.sideboards
            .first { $0.ownerCardId == CardIds.Collectible.Neutral.ETCBandManager }?
            .cards.map { $0.id }
        return capture(entities: all, playerId: playerId, opponentId: opponentId,
                       deck: deck, band: band,
                       opponentBoardDamage: board.opponent.damage,
                       deadToBoard: board.isPlayerDeadToBoard(),
                       match: game.startTime)
    }

    /// 回溯（GAME_RESET）重发玩家实体时写的是「FULL_ENTITY - Updating 玩家名」，解析器认不出，后面的 tag 落到
    /// 解析器当前的实体上（10-05 第 7 局落到了 id 0）：多出一个带 PLAYER_ID、但 ENTITY_ID 对不上自己的假玩家实体，
    /// 而 `Game.playerEntity` 按最小 id 取会取到它（回合、法力从此冻住）。真玩家实体的 ENTITY_ID 就是自己的 id
    static func isPlayerEntityCandidate(_ e: Entity) -> Bool {
        return e.id > 0 && (e[.entity_id] == 0 || e[.entity_id] == e.id)
    }

    /// 我方玩家实体，跳过上面那种假实体
    static func playerEntity(game: Game) -> Entity? {
        let id = game.player.id
        return game.entities.values.filter { $0[.player_id] == id && isPlayerEntityCandidate($0) }
            .min { $0.id < $1.id }
    }

    /// 牌现在是什么。解析器碰到 CHANGE_ENTITY 不改 `cardId`（留着原卡），新身份记在 `info.latestCardId`：
    /// 殒命暗影变成上一张法术就是这样（10-05 第 4 局 T11，殒命暗影在舞动后变成舞动，按 `cardId` 读还是殒命暗影）
    static func currentCardId(_ e: Entity) -> String {
        let latest = e.info.latestCardId
        return latest.isEmpty ? e.cardId : latest
    }

    /// 不经过 `Game` 的版本（测试用手工构造的实体）
    static func capture(entities all: [Entity], playerId: Int, opponentId: Int,
                        deck: [String: Int], band: [String]?,
                        opponentBoardDamage: Int = 0, deadToBoard: Bool = false,
                        match: Date? = nil) -> RDGameSnapshot {
        var enchantsByTarget: [Int: [Entity]] = [:]
        var mine: [Entity] = []
        var theirs: [Entity] = []
        var playerEntity: Entity?
        var opponentEntity: Entity?
        var gameEntity: Entity?
        var maxId = 0
        var byId: [Int: Entity] = [:]
        for e in all {
            maxId = max(maxId, e.id)
            byId[e.id] = e
            let real = isPlayerEntityCandidate(e)
            if real, e[.player_id] == playerId, playerEntity.map({ e.id < $0.id }) ?? true { playerEntity = e }
            if real, e[.player_id] == opponentId, opponentEntity.map({ e.id < $0.id }) ?? true { opponentEntity = e }
            if e.name == "GameEntity" || e[.cardtype] == CardType.game.rawValue { gameEntity = e }
            if e.isEnchantment && e.isInPlay && e[.attached] > 0 {
                enchantsByTarget[e[.attached], default: []].append(e)
            }
            if e.isControlled(by: playerId) { mine.append(e) } else if e.isControlled(by: opponentId) { theirs.append(e) }
        }
        func enchantIds(_ e: Entity) -> [String] {
            return (enchantsByTarget[e.id] ?? []).sorted { $0.id < $1.id }.map { $0.cardId }
        }
        func minion(_ e: Entity) -> Minion {
            return Minion(entityId: e.id, cardId: currentCardId(e), zonePosition: e.zonePosition,
                          attack: e.attack, health: e.health, maxHealth: e[.health], damage: e[.damage],
                          exhausted: e.has(tag: .exhausted), attacksThisTurn: e[.num_attacks_this_turn],
                          silenced: e.has(tag: .silenced), frozen: e.has(tag: .frozen),
                          cantAttack: e.has(tag: .cant_attack), charge: e.has(tag: .charge),
                          windfury: e.has(tag: .windfury), taunt: e.has(tag: .taunt),
                          divineShield: e.has(tag: .divine_shield), immune: e.has(tag: .immune),
                          stealth: e.has(tag: .stealth), dormant: e.has(tag: .dormant),
                          untouchable: e.has(tag: .untouchable),
                          elusive: e.has(tag: .cant_be_targeted_by_abilities),
                          poisonous: e.has(tag: .poisonous), venomous: e.has(tag: .venomous),
                          enchantments: enchantIds(e),
                          playOrder: e.info.boardOrder)
        }

        let hand = mine.filter { $0.isInHand }
            .sorted { ($0.zonePosition, $0.id) < ($1.zonePosition, $1.id) }
            .map { e in
                HandCard(entityId: e.id, cardId: currentCardId(e), cost: e[.cost], zonePosition: e.zonePosition,
                         attack: e.attack, health: e.health, isCoin: e.isTheCoin,
                         enchantments: enchantIds(e))
            }
        let inPlay = mine.filter { $0.isInPlay }
        let myBoard = inPlay.filter { $0.isMinion }
            .sorted { ($0.zonePosition, $0.id) < ($1.zonePosition, $1.id) }
            .map(minion)
        let hero = inPlay.filter { $0.isHero }.min { $0.id < $1.id }
        let heroPower = inPlay.filter { $0.isHeroPower }.min { $0.id < $1.id }
        let weapon = inPlay.filter { $0.isWeapon }.min { $0.id < $1.id }.map {
            Weapon(cardId: $0.cardId, attack: $0.attack, durability: $0[.durability] - $0[.damage])
        }
        let secrets = mine.filter { $0.isInSecret && $0.isSecret }.map { $0.cardId }.sorted()

        let theirPlay = theirs.filter { $0.isInPlay }
        let theirHero = theirPlay.filter { $0.isHero }.min { $0.id < $1.id }
        let theirBoard = theirPlay.filter { $0.isMinion }
            .sorted { ($0.zonePosition, $0.id) < ($1.zonePosition, $1.id) }
            .map(minion)
        let theirSecrets = theirs.filter { $0.isInSecret && $0.isSecret }.count
        func slots(_ play: [Entity]) -> [Int] {
            return play.filter { $0.takesBoardSlot }
                .sorted { ($0.zonePosition, $0.id) < ($1.zonePosition, $1.id) }
                .map { $0.id }
        }

        var playerEnchants: [PlayerEnchantment] = []
        if let p = playerEntity {
            for e in (enchantsByTarget[p.id] ?? []).sorted(by: { $0.id < $1.id }) {
                playerEnchants.append(PlayerEnchantment(entityId: e.id, cardId: e.cardId,
                                                        scriptData1: e[.tag_script_data_num_1]))
            }
        }

        // 已被 E.T.C. 发现的边牌：发现出来的实体带 COPIED_FROM_ENTITY_ID 指回开局放在 SETASIDE 的那张乐队牌，
        // 选中的那张离开 SETASIDE（进手 / 上场 / 进坟场），没选的留在 SETASIDE（日志实测）。
        // 随从被弹回手（舞动 / 暗影步）时这个 tag 被清成 0（10-06 04:18 会话第 11 局第 18658 行，另两局同）：
        // tag 为 0 的也算已发现 —— 主牌库没有和乐队同名的牌，SETASIDE 之外出现一张就说明它被发现过
        // （它的复制体、殒命暗影变成的那张也只在它被发现之后才会有）
        var sideboard: [String]?
        if let band = band {
            var left = band
            let bandSet = Set(band)
            for e in mine where bandSet.contains(e.cardId) && !e.isInSetAside {
                let source = e[.copied_from_entity_id]
                if source > 0 {
                    guard let original = byId[source], original.isInSetAside, original.cardId == e.cardId,
                          !copyStatEnchantments.contains(where: { enchantIds(e).contains($0) }) else { continue }
                }
                if let i = left.firstIndex(of: e.cardId) { left.remove(at: i) }
            }
            sideboard = left
        }

        return RDGameSnapshot(
            match: match,
            turn: gameEntity?[.turn] ?? 0,
            isPlayerTurn: playerEntity?.isCurrentPlayer ?? false,
            optionsPlayedThisTurn: playerEntity?[.num_options_played_this_turn] ?? 0,
            resources: playerEntity?[.resources] ?? 0,
            resourcesUsed: playerEntity?[.resources_used] ?? 0,
            overloadLocked: playerEntity?[.overload_locked] ?? 0,
            tempResources: playerEntity?[.temp_resources] ?? 0,
            cardsPlayedThisTurn: playerEntity?[.num_cards_played_this_turn] ?? 0,
            minionsAttackedThisTurn: playerEntity?[.num_friendly_minions_that_attacked_this_turn] ?? 0,
            spellPower: playerEntity?[.current_spellpower] ?? 0,
            playerEnchantments: playerEnchants,
            heroHealth: hero?.health ?? 0,
            heroArmor: hero?[.armor] ?? 0,
            heroAttacksThisTurn: hero?[.num_attacks_this_turn] ?? 0,
            heroFrozen: hero?.has(tag: .frozen) ?? false,
            heroPowerExhausted: heroPower?.has(tag: .exhausted) ?? true,
            weapon: weapon,
            hand: hand,
            board: myBoard,
            secrets: secrets,
            opponentHeroCardId: theirHero?.cardId ?? "",
            opponentHeroHealth: theirHero?.health ?? 0,
            opponentHeroArmor: theirHero?[.armor] ?? 0,
            opponentHeroImmune: theirHero?.has(tag: .immune) ?? false,
            opponentBoard: theirBoard,
            opponentSecretCount: theirSecrets,
            opponentBoardDamage: opponentBoardDamage,
            deadToBoard: deadToBoard,
            deck: deck,
            sideboard: sideboard,
            maxEntityId: maxId,
            boardSlots: slots(inPlay),
            opponentBoardSlots: slots(theirPlay),
            heroMaxHealth: hero.map { $0[.health] } ?? 30)
    }
}
