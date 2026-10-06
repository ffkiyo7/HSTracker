//
//  RedDragonCards.swift
//  HSTracker
//
//  红龙贼（狂野「致聋双闪避」）的卡牌效果数据表。
//  规格见 docs/research/red-dragon-card-model.md 第一部分 / 第二部分 C 节。
//  引擎只读这张表，不写 `if cardId == ...`。
//

import Foundation

enum RDCardType {
    case minion, spell, weapon, placeholder
}

enum RDCardFilter {
    case any, spell, minion, comboCard
}

enum RDTargetScope {
    case none, friendlyMinion, enemyMinion, anyMinion, anyCharacter
    /// 敌方随从或敌方英雄。阿莱的战吼对友方是**治疗 8**，不是伤害 ——
    /// 用 `.anyCharacter` 会让搜索生成「战吼打死自己的复制体」这种游戏里不存在的动作，
    /// 而重放用的是同一套规则，挡不住它。
    case enemyCharacter
    /// 阿莱（T4）：敌方随从 / 敌方英雄打 8，**我方英雄回 8**。友方随从也能点，但回血对本模型没有意义，不列。
    /// 我方英雄这个目标只在 `RDOptions.healFriendlyHero` 打开时才由 `legalActions` 列出（斩杀搜索不需要，
    /// 列了只会多出一个无用分支）；校验（`apply`）永远认
    case enemyCharacterOrOwnHero
}

/// 不展开的随机源。v1 把它们当「花费用 + 结果未知」截断（spike 六、）。
enum RDTruncation {
    case dredge          // 垂钓时光
    case discoverFromDeck // 异教地图
}

enum RDEffect {
    /// `usesSpellDamage` = 卡面写 `$N`（骨刺 / 致聋术）；阿莱的 `#8` 不吃法术伤害加成
    case damageTarget(Int, usesSpellDamage: Bool)
    case silenceTarget
    case bounceTarget(costDelta: Int)
    case bounceAllFriendly(setCostThisTurn: Int)
    case copyTargetToHand(setCost: Int, attack: Int, health: Int)
    case copyAllFriendlyToHand(setCost: Int, attack: Int, health: Int)
    case refreshMana(Int, requiresDragonInHand: Bool)
    case gainTempMana(Int)
    case pushDiscount(amount: Int, slots: Int, filter: RDCardFilter)
    /// 锯齿骨刺：只有目标因这次伤害死亡才压层
    case discountIfTargetDied(amount: Int, slots: Int)
    case draw(filter: RDCardFilter, count: Int)
    case discoverFromSideboard(count: Int)
    case truncatedDraw(RDTruncation)
    case equipWeapon(attack: Int, durability: Int, drawOnHeroAttack: Bool)
    case castSecret
    /// 公式表占位 token「腾格」专用：把自己场上一个随从弄走
    case removeOneFriendlyMinion
}

/// 24 张牌 + 两个公式表占位。identity 用英文名，公式表缩写的映射在测试侧。
enum RDCard: Int, CaseIterable {
    case coin, preparation, shadowstep, shadowOfDemise
    case goneFishin, digForTreasure, deafen, blackwaterCutlass
    case cultistMap, foxyFraud, quickPick, swindle, serratedBoneSpike, evasion
    case darkscaleBroodmother, shroudOfConcealment
    case etcBandManager, scabbsCutterbutter, spiritOfTheShark
    case shadowcaster
    case bounceAround, potionOfIllusion, alexstrasza
    case junkPlaceholder, freeSlotPlaceholder
    /// 不在本牌组、只用于验证公式表的牌（公式表是给带持枪要挟的另一版牌组写的）。
    /// 生产搜索只在手里真有这张牌时才会打它；它们不进牌库 / 边牌，也不会被当成缺件。
    case backstab, pocketSand, dehydrate
}

struct RDCardDef {
    let card: RDCard
    /// 全部可能的 cardId（三张牌用 Core 版，识别按集合不写死单串）
    let ids: [String]
    let dbfId: Int
    let enName: String
    let printedCost: Int
    let type: RDCardType
    let attack: Int
    let health: Int
    let isDragon: Bool
    let isCombo: Bool
    let targetScope: RDTargetScope
    /// 无合法目标时能不能打（法术不能，随从的指向性战吼可以裸下）
    let needsTargetToPlay: Bool
    let effects: [RDEffect]
    let comboEffects: [RDEffect]
    /// 鲨鱼之灵的光环只翻倍随从的战吼 / 连击
    let doubledByShark: Bool
    /// 鲨鱼之灵本体：在场时提供光环
    let providesSharkAura: Bool
    /// 殒命暗影：每次施放法术时变形成它的复制
    let mirrorsLastSpell: Bool
    let isSideboard: Bool
    /// 牌库里有几张（用于缺件枚举与抽牌池）
    let deckCount: Int
    /// 指向性效果只能指「未受伤」的随从（背刺）
    let targetMustBeUndamaged: Bool
    /// 快枪：本回合进手时费用变成这个值（脱水）
    let quickdrawCost: Int?
    /// 不在本牌组、只用于验证公式表（见 `RDCard.backstab` 处的说明）
    let verificationOnly: Bool

    var isPlaceholder: Bool { return type == .placeholder }
}

enum RDCards {

    private static func def(_ card: RDCard,
                           _ ids: [String],
                           _ dbfId: Int,
                           _ enName: String,
                           cost: Int,
                           type: RDCardType,
                           attack: Int = 0,
                           health: Int = 0,
                           dragon: Bool = false,
                           combo: Bool = false,
                           scope: RDTargetScope = .none,
                           needsTarget: Bool = false,
                           effects: [RDEffect] = [],
                           comboEffects: [RDEffect] = [],
                           shark: Bool = false,
                           aura: Bool = false,
                           mirror: Bool = false,
                           sideboard: Bool = false,
                           deckCount: Int = 0,
                           undamagedOnly: Bool = false,
                           quickdraw: Int? = nil,
                           verificationOnly: Bool = false) -> RDCardDef {
        return RDCardDef(card: card, ids: ids, dbfId: dbfId, enName: enName,
                         printedCost: cost, type: type, attack: attack, health: health,
                         isDragon: dragon, isCombo: combo, targetScope: scope,
                         needsTargetToPlay: needsTarget, effects: effects,
                         comboEffects: comboEffects, doubledByShark: shark,
                         providesSharkAura: aura, mirrorsLastSpell: mirror,
                         isSideboard: sideboard, deckCount: deckCount,
                         targetMustBeUndamaged: undamagedOnly, quickdrawCost: quickdraw,
                         verificationOnly: verificationOnly)
    }

    static let table: [RDCardDef] = [
        def(.coin, ["CFM_630"], 40437, "Counterfeit Coin", cost: 0, type: .spell,
            effects: [.gainTempMana(1)], deckCount: 2),
        def(.preparation, ["CORE_EX1_145", "EX1_145"], 69623, "Preparation", cost: 0, type: .spell,
            effects: [.pushDiscount(amount: 2, slots: 1, filter: .spell)], deckCount: 2),
        def(.shadowstep, ["EX1_144", "CORE_EX1_144"], 365, "Shadowstep", cost: 0, type: .spell,
            scope: .friendlyMinion, needsTarget: true,
            effects: [.bounceTarget(costDelta: -2)], deckCount: 2),
        def(.shadowOfDemise, ["CORE_RLK_567", "RLK_567"], 126088, "Shadow of Demise",
            cost: 0, type: .spell, mirror: true, deckCount: 1),
        def(.goneFishin, ["TSC_916"], 72119, "Gone Fishin'", cost: 1, type: .spell, combo: true,
            effects: [.truncatedDraw(.dredge)], comboEffects: [.truncatedDraw(.dredge)],
            deckCount: 1),
        def(.digForTreasure, ["TOY_510"], 103341, "Dig for Treasure", cost: 1, type: .spell,
            effects: [.draw(filter: .minion, count: 1)], deckCount: 2),
        def(.deafen, ["JAM_022"], 98377, "Deafen", cost: 1, type: .spell,
            combo: true, scope: .anyMinion, needsTarget: true,
            effects: [.silenceTarget],
            comboEffects: [.silenceTarget, .damageTarget(2, usesSpellDamage: true)], deckCount: 1),
        def(.blackwaterCutlass, ["DED_004"], 65597, "Blackwater Cutlass", cost: 1, type: .weapon,
            attack: 2, health: 2,
            effects: [.equipWeapon(attack: 2, durability: 2, drawOnHeroAttack: false)],
            deckCount: 1),
        def(.cultistMap, ["TLC_515"], 117697, "Cultist Map", cost: 2, type: .spell,
            effects: [.truncatedDraw(.discoverFromDeck)], deckCount: 2),
        def(.foxyFraud, ["CORE_DMF_511", "DMF_511"], 120460, "Foxy Fraud", cost: 2, type: .minion,
            attack: 3, health: 2,
            effects: [.pushDiscount(amount: 2, slots: 1, filter: .comboCard)],
            shark: true, deckCount: 1),
        def(.quickPick, ["DEEP_014"], 102254, "Quick Pick", cost: 2, type: .weapon,
            attack: 1, health: 2,
            effects: [.equipWeapon(attack: 1, durability: 2, drawOnHeroAttack: true)],
            deckCount: 2),
        def(.swindle, ["DMF_515"], 61159, "Swindle", cost: 2, type: .spell, combo: true,
            effects: [.draw(filter: .spell, count: 1)],
            comboEffects: [.draw(filter: .spell, count: 1), .draw(filter: .minion, count: 1)],
            deckCount: 2),
        def(.serratedBoneSpike, ["REV_939"], 77557, "Serrated Bone Spike", cost: 2, type: .spell,
            scope: .anyMinion, needsTarget: true,
            effects: [.damageTarget(3, usesSpellDamage: true),
                      .discountIfTargetDied(amount: 2, slots: 1)],
            deckCount: 2),
        def(.evasion, ["LOOT_214"], 45535, "Evasion", cost: 2, type: .spell,
            effects: [.castSecret], deckCount: 2),
        def(.darkscaleBroodmother, ["CATA_111"], 122500, "Darkscale Broodmother",
            cost: 3, type: .minion, attack: 4, health: 3, dragon: true,
            effects: [.refreshMana(2, requiresDragonInHand: true)], shark: true, deckCount: 1),
        def(.shroudOfConcealment, ["WC_016"], 63358, "Shroud of Concealment", cost: 3, type: .spell,
            effects: [.draw(filter: .minion, count: 2)], deckCount: 2),
        def(.etcBandManager, ["ETC_080"], 90749, "E.T.C., Band Manager", cost: 4, type: .minion,
            attack: 4, health: 4,
            effects: [.discoverFromSideboard(count: 1)], shark: true, deckCount: 1),
        def(.scabbsCutterbutter, ["BAR_552"], 63517, "Scabbs Cutterbutter", cost: 4, type: .minion,
            attack: 3, health: 3, combo: true,
            comboEffects: [.pushDiscount(amount: 2, slots: 2, filter: .any)],
            shark: true, deckCount: 1),
        def(.spiritOfTheShark, ["TRL_092"], 49972, "Spirit of the Shark", cost: 4, type: .minion,
            attack: 0, health: 3, aura: true, deckCount: 1),
        def(.shadowcaster, ["OG_291"], 38876, "Shadowcaster", cost: 5, type: .minion,
            attack: 4, health: 4, scope: .friendlyMinion,
            effects: [.copyTargetToHand(setCost: 1, attack: 1, health: 1)],
            shark: true, deckCount: 1),
        def(.bounceAround, ["ETC_079"], 90606, "Bounce Around (ft. Garona)", cost: 3, type: .spell,
            effects: [.bounceAllFriendly(setCostThisTurn: 1)], sideboard: true),
        def(.potionOfIllusion, ["SCH_352"], 59621, "Potion of Illusion", cost: 4, type: .spell,
            effects: [.copyAllFriendlyToHand(setCost: 1, attack: 1, health: 1)], sideboard: true),
        def(.alexstrasza, ["LEG_CS3_031"], 113183, "Alexstrasza the Life-Binder",
            cost: 9, type: .minion, attack: 8, health: 8, dragon: true,
            scope: .enemyCharacterOrOwnHero, effects: [.damageTarget(8, usesSpellDamage: false)],
            shark: true, sideboard: true),
        def(.junkPlaceholder, [], 0, "(junk)", cost: 0, type: .placeholder),
        def(.freeSlotPlaceholder, [], 0, "(free slot)", cost: 0, type: .placeholder,
            scope: .friendlyMinion, needsTarget: true,
            effects: [.removeOneFriendlyMinion]),
        // —— 以下三张不在本牌组，只用于验证（spike「腾格」：能把自己场上随从弄走的 ≤2 费牌）——
        // 背刺：对一个未受伤的随从造成 $2 点伤害。
        def(.backstab, ["CS2_072", "CORE_CS2_072", "VAN_CS2_072"], 180, "Backstab",
            cost: 0, type: .spell, scope: .anyMinion, needsTarget: true,
            effects: [.damageTarget(2, usesSpellDamage: true)],
            undamagedOnly: true, verificationOnly: true),
        // 袋底藏沙：造成 $3 点伤害。快枪：对手的下一张牌费用 +1（只影响对手，这里不建模）。
        def(.pocketSand, ["WW_403"], 100359, "Pocket Sand", cost: 2, type: .spell,
            scope: .anyCharacter, needsTarget: true,
            effects: [.damageTarget(3, usesSpellDamage: true)], verificationOnly: true),
        // 脱水：吸血。对一个随从造成 $4 点伤害。快枪：本回合进手时费用为 (1)。
        // 吸血只回英雄血，本模型不追踪我方英雄生命，不影响伤害与费用。
        def(.dehydrate, ["WW_325"], 100015, "Dehydrate", cost: 3, type: .spell,
            scope: .anyMinion, needsTarget: true,
            effects: [.damageTarget(4, usesSpellDamage: true)],
            quickdraw: 1, verificationOnly: true)
    ]

    /// `def(_:)` 按 rawValue 直接索引这张表 —— 少登记一条就会静默错位，
    /// 所以建表时就断言「条目数 = case 数、第 i 条正好是 rawValue == i 的那张」。
    /// Release 下 `assert` 不编译，同一条不变量由 `testCardTableIsCompleteAndAligned` 守着。
    private static let byCard: [RDCardDef] = {
        var list = table
        list.sort { $0.card.rawValue < $1.card.rawValue }
        assert(list.count == RDCard.allCases.count,
               "RDCards.table 有 \(list.count) 条，RDCard 有 \(RDCard.allCases.count) 个 case")
        for (i, d) in list.enumerated() {
            assert(d.card.rawValue == i, "RDCards.table 错位：\(d.card) 落在索引 \(i)")
        }
        return list
    }()

    /// 能指敌方英雄的效果（阿莱）。搜索的启发式靠这个识别「打脸战吼」，不写死单张牌。
    static func canTargetEnemyHero(_ def: RDCardDef) -> Bool {
        return def.targetScope == .anyCharacter || def.targetScope == .enemyCharacter
            || def.targetScope == .enemyCharacterOrOwnHero
    }

    static func def(_ card: RDCard) -> RDCardDef {
        return byCard[card.rawValue]
    }

    /// 有快枪费用的牌（`canonicalHash` 每张手牌都要问，预先按 rawValue 算好，省掉整张 def 的拷贝）
    static func hasQuickdraw(_ card: RDCard) -> Bool {
        return quickdrawCards[card.rawValue]
    }

    private static let quickdrawCards: [Bool] = byCard.map { $0.quickdrawCost != nil }

    /// 可交易（TRADEABLE）的牌。交易不是打牌，引擎不展开，只用来判「有没有漏掉的走法」。
    /// 本牌组的 25 张逐张对过卡表（T2b 第四轮）：只有黑水弯刀
    static let tradeableCards: Set<RDCard> = [.blackwaterCutlass]

    static func isTradeable(_ card: RDCard) -> Bool {
        return tradeableCards.contains(card)
    }

    /// 本牌组的英雄与英雄技能（`Cards.by(cardId:)` 过滤 hero / hero_power，查它们要用 `Cards.any(byId:)`）
    static let heroId = "HERO_03bm"
    static let heroPowerId = "HERO_03bmhp"

    /// E.T.C. 的三张边牌
    static let sideboardCards: [RDCard] = [.bounceAround, .potionOfIllusion, .alexstrasza]

    /// 主牌库里的 6 张随从（阿莱在边牌，不在牌库）
    static let deckMinions: [RDCard] = RDCards.table
        .filter { $0.deckCount > 0 && $0.type == .minion }
        .map { $0.card }
        .sorted { $0.rawValue < $1.rawValue }

    static func card(forId id: String) -> RDCard? {
        for d in table where d.ids.contains(id) {
            return d.card
        }
        return nil
    }

    static func card(forDbfId dbfId: Int) -> RDCard? {
        for d in table where d.dbfId == dbfId && dbfId != 0 {
            return d.card
        }
        return nil
    }

    static func matches(_ def: RDCardDef, _ filter: RDCardFilter) -> Bool {
        switch filter {
        case .any: return true
        case .spell: return def.type == .spell
        case .minion: return def.type == .minion
        case .comboCard: return def.isCombo
        }
    }
}
