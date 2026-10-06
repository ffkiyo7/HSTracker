//
//  RedDragonReader.swift
//  HSTracker
//
//  快照 → 搜索的根局面。纯函数，任何线程都能调。
//  分界照 docs/research/red-dragon-card-model.md B3：根局面里日志已经算好的（手牌费用、随从身材与 tag）
//  一律直接读；日志里没有的（减费层的剩余槽、手牌在减费层之外的「底费」）才自己推。逐字段出处见 T2b 任务书执行结果。
//

import Foundation

/// 读取结果：搜索输入 + 展示层要用的对照
struct RDLiveState {
    var state: RDState
    /// 手牌 entityId → zonePosition（从 1 起）。根局面的手牌 / 场面 entityId 就是游戏里的 entity id
    var handZonePositions: [Int: Int]
    /// 「底费」靠推断的手牌（减费层把当前费用压到 0、看不出原值，按印刷费 / 复制体的 1 费封顶）
    var inferredBaseCostEntities: [Int]
}

enum RDDeckGate {

    /// 判据（spike 二、8）：套牌里有 E.T.C.，它的乐队里有生命的缚誓者阿莱克丝塔萨，主牌里至少有
    /// 刀油 / 鲨鱼之灵 / 暗影施法者 / 晦鳞巢母 / 狐人老千里的 3 张。只看套牌，不看对局里出现了什么。
    /// E.T.C. 按卡表认（本地包里没有 app 的 `CardIds`）；收 `PlayingDeck` 的那个在 app 侧（RedDragonAssistant.swift）
    static func isRedDragonDeck(cardIds: [String], sideboards: [String: [String]]) -> Bool {
        func isETC(_ id: String) -> Bool { return RDCards.card(forId: id) == .etcBandManager }
        guard cardIds.contains(where: isETC),
              let band = sideboards.first(where: { isETC($0.key) })?.value,
              band.contains(where: { RDCards.card(forId: $0) == .alexstrasza }) else { return false }
        let engine: Set<RDCard> = [.scabbsCutterbutter, .spiritOfTheShark, .shadowcaster,
                                   .darkscaleBroodmother, .foxyFraud]
        var found = Set<RDCard>()
        for id in cardIds {
            if let c = RDCards.card(forId: id), engine.contains(c) { found.insert(c) }
        }
        return found.count >= 3
    }
}

enum RDStateReader {

    static func read(_ snap: RDGameSnapshot) -> RDLiveState {
        // 回合内的减费层：玩家实体上的附魔。存在 = 还有槽；刀油的层由 TAG_SCRIPT_DATA_NUM_1 记已用张数
        var layers: [RDDiscountLayer] = []
        var comet = 0
        for e in snap.playerEnchantments {
            switch e.cardId {
            case "BAR_552o":
                let slots = 2 - e.scriptData1
                if slots > 0 { layers.append(RDDiscountLayer(amount: 2, slots: slots, filter: .any)) }
            case "EX1_145o":
                layers.append(RDDiscountLayer(amount: 2, slots: 1, filter: .spell))
            case "DMF_511e":
                layers.append(RDDiscountLayer(amount: 2, slots: 1, filter: .comboCard))
            case "REV_939e":
                layers.append(RDDiscountLayer(amount: 2, slots: 1, filter: .any))
            case "GDB_873e":
                comet += 1
            default:
                break
            }
        }

        var opponent = RDOpponent(health: snap.opponentHeroHealth, armor: snap.opponentHeroArmor,
                                  immune: snap.opponentHeroImmune, secretCount: snap.opponentSecretCount)
        // 潜行 / 休眠 / 不可触碰的敌方随从既不能被攻击也不能被法术指到，搜索里当作不存在
        opponent.board = snap.opponentBoard
            .filter { !$0.stealth && !$0.dormant && !$0.untouchable }
            .map { m in
                RDEnemyMinion(entityId: m.entityId, attack: m.attack, health: m.health, taunt: m.taunt,
                              divineShield: m.divineShield, immune: m.immune, stealth: m.stealth,
                              damaged: m.damage > 0)
            }

        let maxMana = snap.resources
        let mana = max(0, snap.resources - snap.resourcesUsed - snap.overloadLocked)
        var s = RDState(maxMana: maxMana, mana: mana, opponent: opponent)
        s.tempMana = snap.tempResources
        s.cardsPlayedThisTurn = snap.cardsPlayedThisTurn
        s.spellDamage = snap.spellPower
        s.heroAttackedThisTurn = snap.heroAttacksThisTurn > 0
        // 冻结的英雄不能攻击：武器（含搜索中途装上的）都打不出去
        s.heroFrozen = snap.heroFrozen
        s.heroPowerUsed = snap.heroPowerExhausted
        s.heroHealth = snap.heroHealth
        s.heroArmor = snap.heroArmor
        s.heroMaxHealth = max(snap.heroMaxHealth, snap.heroHealth)
        if let w = snap.weapon, w.durability > 0 {
            s.weapon = RDWeapon(attack: w.attack, durability: w.durability,
                                drawOnHeroAttack: RDCards.card(forId: w.cardId) == .quickPick)
        }
        s.layers = layers
        s.luckyCometCharges = comet

        var zones: [Int: Int] = [:]
        var inferred: [Int] = []
        for c in snap.hand {
            zones[c.entityId] = c.zonePosition
            var (card, wasInferred) = handCard(c, layers: layers)
            if wasInferred { inferred.append(c.entityId) }
            card.baseCostInferred = wasInferred
            s.hand.append(card)
        }

        // 上场先后（舞动按它处理）：`EntityInfo.boardOrder` 排名次 1…n。没有它的（直接建在场上的实体，
        // 本牌组没有这种来源）排在有的之后、彼此按实体编号
        let arrival = snap.board.sorted {
            ($0.playOrder ?? Int.max, $0.entityId) < ($1.playOrder ?? Int.max, $1.entityId)
        }
        var playOrder: [Int: Int] = [:]
        for (i, m) in arrival.enumerated() { playOrder[m.entityId] = i + 1 }
        s.nextPlayOrder = arrival.count + 1

        for m in snap.board {
            let identity = RDCards.card(forId: m.cardId) ?? .junkPlaceholder
            let isCopy = m.enchantments.contains { RDGameSnapshot.copyStatEnchantments.contains($0) }
            // 不能攻击的原因引擎只认「召唤失调」一种，冻结 / 不能攻击 / 休眠都折进去（只影响能不能攻击）
            let sick = m.frozen || m.cantAttack || m.dormant
                || (m.exhausted && m.attacksThisTurn == 0 && !m.charge)
            s.board.append(RDBoardMinion(entityId: m.entityId, card: identity,
                                         attack: m.attack, health: m.health, maxHealth: m.maxHealth,
                                         statsSetTo1x1: isCopy, silenced: m.silenced,
                                         summoningSick: sick, attacksThisTurn: m.attacksThisTurn,
                                         enchants: boardCostEnchants(m.enchantments),
                                         playOrder: playOrder[m.entityId] ?? 0))
        }

        var deckPairs: [(RDCard, Int)] = []
        for (id, n) in snap.deck.sorted(by: { $0.key < $1.key }) where n > 0 {
            deckPairs.append((RDCards.card(forId: id) ?? .junkPlaceholder, n))
        }
        s.deck = RDDeck(deckPairs)
        if let band = snap.sideboard {
            s.sideboard = RDCards.sideboardCards.filter { c in
                band.contains { RDCards.card(forId: $0) == c }
            }
        }
        s.secretsInPlay = snap.secrets.compactMap { RDCards.card(forId: $0) }
        // 引擎新造的实体从这里往后编号，不和游戏里的 id 撞
        s.nextEntityId = max(snap.maxEntityId, 0) + 1000
        return RDLiveState(state: s, handZonePositions: zones, inferredBaseCostEntities: inferred)
    }

    /// 场上随从仍挂着的费用附魔，按附魔实体编号恢复。它们只描述当前实体，回手时全部清除，
    /// 然后叠加回手牌自身的费用效果（T3 日志订正）。只认本牌组会碰到的几种：
    /// 舞动「本回合 1 费」、药水复制品的 1 费、暗影施法者复制品的 1/1 1 费、暗影步的 −2（`GBL_002e`）
    static let boardCostEnchantMap: [String: RDEnchant] = [
        "ETC_079e": .set(1), "SCH_352e2": .set(1), "OG_291e": .set(1), "GBL_002e": .delta(-2)
    ]

    static func boardCostEnchants(_ ids: [String]) -> [RDEnchant] {
        var chain = ids.compactMap { boardCostEnchantMap[$0] }
        // 1/1 复制体本身就是「费用为 1」：只看到管身材的 `SCH_352e`、没看到管费用的 `SCH_352e2` 时
        // 按复制品补一个 1 费在链首（第二轮之前的口径，`testBoardTargetsResolveToRealEntities`）
        if ids.contains(where: { RDGameSnapshot.copyStatEnchantments.contains($0) })
            && !ids.contains(where: { $0 == "SCH_352e2" || $0 == "OG_291e" }) {
            chain.insert(.set(1), at: 0)
        }
        return chain
    }

    /// 根局面的一张手牌。费用只读 `entity[.cost]`；减费层还在时它已经被减过，所以「底费」=
    /// 当前费用 + 匹配层的减免，层用完后费用回到底费（与游戏一致）。当前费用被压到 0 时看不出原值，
    /// 底费按「印刷费 / 复制体的 1 费」封顶——只会往贵里估，不会算出打不出来的线。
    static func handCard(_ c: RDGameSnapshot.HandCard,
                        layers: [RDDiscountLayer]) -> (RDHandCard, inferred: Bool) {
        let demise = c.enchantments.contains { $0.hasPrefix(RDGameSnapshot.shadowOfDemisePrefix) }
        guard let identity = RDCards.card(forId: c.cardId) ?? (c.isCoin ? .coin : nil) else {
            return (RDHandCard.unmodeled(entityId: c.entityId, cardId: c.cardId), false)
        }
        let def = RDCards.def(identity)
        var discount = 0
        for l in layers where RDCards.matches(def, l.filter) { discount += l.amount }
        var base = c.cost + discount
        var inferred = false
        if discount > 0 && c.cost == 0 {
            let setToOne = c.enchantments.contains { RDGameSnapshot.setCostToOneEnchantments.contains($0) }
            let cap = setToOne ? 1 : def.printedCost
            base = min(base, cap)
            // 封顶为 0（印刷费 0 的牌）没有歧义；否则真实底费在 0…cap 之间，按 cap 估
            inferred = cap > 0
        }
        let isCopy = c.enchantments.contains { RDGameSnapshot.copyStatEnchantments.contains($0) }
        let card = RDHandCard(entityId: c.entityId, card: identity, enchants: [.set(base)],
                              statsOverride: isCopy ? RDStats(attack: c.attack, health: c.health) : nil,
                              isShadowOfDemise: demise || identity == .shadowOfDemise)
        return (card, inferred)
    }
}
