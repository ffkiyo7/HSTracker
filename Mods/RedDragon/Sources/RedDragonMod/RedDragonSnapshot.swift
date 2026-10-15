//
//  RedDragonSnapshot.swift
//  RedDragonMod
//
//  红龙辅助的「局面读取」第一步：把对局里用得到的数据拷成纯值。
//  在解析线程上、一致边界（ModKit 的 `batchEnded(idle: true)` / `topBlockClosed`）上拷（`RedDragonAssistant`）：
//  这时只有解析线程会改实体，实体 tag、场攻、剩余牌库读到的是同一时刻。
//  只读 ModKit 的 `ModGameState` / `ModEntity`（宿主的对局对象，只在回调期间有效），后台线程只碰这份快照。
//  第二步（快照 → `RDState`）在 RedDragonReader.swift，是纯函数，测试直接喂快照。
//  快照这个值类型（`RDGameSnapshot`）在本地包 RedDragonCore 里（RedDragonGameSnapshot.swift）。
//

import Foundation
import ModKit
import RedDragonCore

extension RDGameSnapshot {

    /// 解析线程在一致边界上调用（见文件头）。读不到双方玩家时返回 nil。
    static func capture(state: any ModGameState) -> RDGameSnapshot? {
        let playerId = state.playerId
        let opponentId = state.opponentId
        guard playerId > 0, opponentId > 0 else { return nil }
        let deck = state.currentDeck != nil ? state.remainingDeck : [:]
        let band = state.currentDeck?.sideboards.first { RDCards.card(forId: $0.key) == .etcBandManager }?.value
        return capture(entities: state.entities, playerId: playerId, opponentId: opponentId,
                       deck: deck, band: band,
                       opponentBoardDamage: state.opponentBoardDamage,
                       deadToBoard: state.isPlayerDeadToBoard,
                       match: state.matchStartTime)
    }

    /// 回溯（GAME_RESET）重发玩家实体时写的是「FULL_ENTITY - Updating 玩家名」，解析器认不出，后面的 tag 落到
    /// 解析器当前的实体上（10-05 第 7 局落到了 id 0）：多出一个带 PLAYER_ID、但 ENTITY_ID 对不上自己的假玩家实体，
    /// 按最小 id 取会取到它（回合、法力从此冻住）。真玩家实体的 ENTITY_ID 就是自己的 id
    static func isPlayerEntityCandidate(_ e: any ModEntity) -> Bool {
        return e.id > 0 && (e.tag(.entityId) == 0 || e.tag(.entityId) == e.id)
    }

    /// 我方玩家实体，跳过上面那种假实体
    static func playerEntity(state: any ModGameState) -> (any ModEntity)? {
        let id = state.playerId
        return state.entities.filter { $0.tag(.playerId) == id && isPlayerEntityCandidate($0) }
            .min { $0.id < $1.id }
    }

    /// 占场面格子的（随从、地标、酒馆法术），和宿主入场序号徽章的口径一致
    static func takesBoardSlot(_ e: any ModEntity) -> Bool {
        return e.isMinion || e.isLocation || e.cardType == .battlegroundSpell
    }

    /// 不经过对局对象的版本（测试用手工构造的实体）。牌现在是什么按 `currentCardId`：解析器碰到 CHANGE_ENTITY
    /// 不改 `cardId`（留着原卡），殒命暗影变成上一张法术就是这样（10-05 第 4 局 T11，殒命暗影在舞动后变成舞动）
    static func capture(entities all: [any ModEntity], playerId: Int, opponentId: Int,
                        deck: [String: Int], band: [String]?,
                        opponentBoardDamage: Int = 0, deadToBoard: Bool = false,
                        match: Date? = nil) -> RDGameSnapshot {
        var enchantsByTarget: [Int: [any ModEntity]] = [:]
        var mine: [any ModEntity] = []
        var theirs: [any ModEntity] = []
        var playerEntity: (any ModEntity)?
        var opponentEntity: (any ModEntity)?
        var gameEntity: (any ModEntity)?
        var maxId = 0
        var byId: [Int: any ModEntity] = [:]
        for e in all {
            maxId = max(maxId, e.id)
            byId[e.id] = e
            let real = isPlayerEntityCandidate(e)
            if real, e.tag(.playerId) == playerId, playerEntity.map({ e.id < $0.id }) ?? true { playerEntity = e }
            if real, e.tag(.playerId) == opponentId, opponentEntity.map({ e.id < $0.id }) ?? true { opponentEntity = e }
            if e.name == "GameEntity" || e.cardType == .game { gameEntity = e }
            if e.isEnchantment && e.isInPlay && e.tag(.attached) > 0 {
                enchantsByTarget[e.tag(.attached), default: []].append(e)
            }
            if e.isControlled(by: playerId) { mine.append(e) } else if e.isControlled(by: opponentId) { theirs.append(e) }
        }
        func enchantIds(_ e: any ModEntity) -> [String] {
            return (enchantsByTarget[e.id] ?? []).sorted { $0.id < $1.id }.map { $0.cardId }
        }
        func minion(_ e: any ModEntity) -> Minion {
            return Minion(entityId: e.id, cardId: e.currentCardId, zonePosition: e.zonePosition,
                          attack: e.attack, health: e.health, maxHealth: e.tag(.health), damage: e.tag(.damage),
                          exhausted: e.has(.exhausted), attacksThisTurn: e.tag(.numAttacksThisTurn),
                          silenced: e.has(.silenced), frozen: e.has(.frozen),
                          cantAttack: e.has(.cantAttack), charge: e.has(.charge),
                          windfury: e.has(.windfury), taunt: e.has(.taunt),
                          divineShield: e.has(.divineShield), immune: e.has(.immune),
                          stealth: e.has(.stealth), dormant: e.has(.dormant),
                          untouchable: e.has(.untouchable),
                          elusive: e.has(.cantBeTargetedByAbilities),
                          poisonous: e.has(.poisonous), venomous: e.has(.venomous),
                          enchantments: enchantIds(e),
                          playOrder: e.boardOrder)
        }

        let hand = mine.filter { $0.isInHand }
            .sorted { ($0.zonePosition, $0.id) < ($1.zonePosition, $1.id) }
            .map { e in
                HandCard(entityId: e.id, cardId: e.currentCardId, cost: e.tag(.cost), zonePosition: e.zonePosition,
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
            Weapon(cardId: $0.cardId, attack: $0.attack, durability: $0.tag(.durability) - $0.tag(.damage))
        }
        let secrets = mine.filter { $0.isInSecretZone && $0.isSecret }.map { $0.cardId }.sorted()

        let theirPlay = theirs.filter { $0.isInPlay }
        let theirHero = theirPlay.filter { $0.isHero }.min { $0.id < $1.id }
        let theirBoard = theirPlay.filter { $0.isMinion }
            .sorted { ($0.zonePosition, $0.id) < ($1.zonePosition, $1.id) }
            .map(minion)
        let theirSecrets = theirs.filter { $0.isInSecretZone && $0.isSecret }.count
        func slots(_ play: [any ModEntity]) -> [Int] {
            return play.filter(takesBoardSlot)
                .sorted { ($0.zonePosition, $0.id) < ($1.zonePosition, $1.id) }
                .map { $0.id }
        }

        var playerEnchants: [PlayerEnchantment] = []
        if let p = playerEntity {
            for e in (enchantsByTarget[p.id] ?? []).sorted(by: { $0.id < $1.id }) {
                playerEnchants.append(PlayerEnchantment(entityId: e.id, cardId: e.cardId,
                                                        scriptData1: e.tag(.tagScriptDataNum1)))
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
                let source = e.tag(.copiedFromEntityId)
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
            turn: gameEntity?.tag(.turn) ?? 0,
            isPlayerTurn: playerEntity?.isCurrentPlayer ?? false,
            optionsPlayedThisTurn: playerEntity?.tag(.numOptionsPlayedThisTurn) ?? 0,
            resources: playerEntity?.tag(.resources) ?? 0,
            resourcesUsed: playerEntity?.tag(.resourcesUsed) ?? 0,
            overloadLocked: playerEntity?.tag(.overloadLocked) ?? 0,
            tempResources: playerEntity?.tag(.tempResources) ?? 0,
            cardsPlayedThisTurn: playerEntity?.tag(.numCardsPlayedThisTurn) ?? 0,
            minionsAttackedThisTurn: playerEntity?.tag(.numFriendlyMinionsThatAttackedThisTurn) ?? 0,
            spellPower: playerEntity?.tag(.currentSpellPower) ?? 0,
            playerEnchantments: playerEnchants,
            heroHealth: hero?.health ?? 0,
            heroArmor: hero?.tag(.armor) ?? 0,
            heroAttacksThisTurn: hero?.tag(.numAttacksThisTurn) ?? 0,
            heroFrozen: hero?.has(.frozen) ?? false,
            heroPowerExhausted: heroPower?.has(.exhausted) ?? true,
            weapon: weapon,
            hand: hand,
            board: myBoard,
            secrets: secrets,
            opponentHeroCardId: theirHero?.cardId ?? "",
            opponentHeroHealth: theirHero?.health ?? 0,
            opponentHeroArmor: theirHero?.tag(.armor) ?? 0,
            opponentHeroImmune: theirHero?.has(.immune) ?? false,
            opponentBoard: theirBoard,
            opponentSecretCount: theirSecrets,
            opponentBoardDamage: opponentBoardDamage,
            deadToBoard: deadToBoard,
            deck: deck,
            sideboard: sideboard,
            maxEntityId: maxId,
            boardSlots: slots(inPlay),
            opponentBoardSlots: slots(theirPlay),
            heroMaxHealth: hero.map { $0.tag(.health) } ?? 30)
    }
}
