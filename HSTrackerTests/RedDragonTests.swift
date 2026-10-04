//
//  RedDragonTests.swift
//  HSTrackerTests
//
//  红龙贼搜索核心（spike RDR / T1）的规则单测。
//  公式表 fixture 的逐行重放 / 反推 / 齐件缺件分组在 RedDragonFormulaTests.swift（T2a）。
//

import XCTest
@testable import HSTracker

class RedDragonTests: HSTrackerTests {

    override class func setUp() {
        super.setUp()
        if Cards.by(cardId: CardIds.Collectible.Rogue.Shadowstep) == nil {
            Database().loadDatabase(splashscreen: nil, withLanguages: [.enUS])
        }
    }

    // MARK: - 1. 卡库

    func testCardLibraryResolvesEveryCard() {
        XCTAssertFalse(RDCards.table.isEmpty)
        var checked = 0
        for def in RDCards.table where !def.isPlaceholder {
            guard let first = def.ids.first else { continue }
            guard let card = Cards.by(cardId: first) else {
                XCTFail("\(def.enName) (\(first)) 在卡库里查不到")
                continue
            }
            XCTAssertEqual(card.enName, def.enName, "\(first) 名字对不上")
            XCTAssertEqual(card.dbfId, def.dbfId, "\(first) dbfId 对不上")
            XCTAssertEqual(card.cost, def.printedCost, "\(first) 印刷费用对不上")
            if def.type == .minion {
                XCTAssertEqual(card.attack, def.attack, "\(first) 攻击力对不上")
                XCTAssertEqual(card.health, def.health, "\(first) 生命值对不上")
                XCTAssertEqual(card.races.contains(.dragon), def.isDragon, "\(first) 龙牌判定")
            }
            // 备用 id（Core / 非 Core）也要查得到
            for extra in def.ids.dropFirst() {
                XCTAssertNotNil(Cards.by(cardId: extra), "备用 id \(extra) 查不到")
            }
            if !def.verificationOnly { checked += 1 }
        }
        XCTAssertEqual(checked, 23, "牌组是 20 主牌 + 3 边牌 = 23 种")
        XCTAssertEqual(RDCards.table.filter { $0.verificationOnly }.map { $0.card },
                       [.backstab, .pocketSand, .dehydrate], "只用于验证的牌：背刺 / 袋底藏沙 / 脱水")

        // 英雄与英雄技能：Cards.by(cardId:) 会过滤 hero / hero_power，只能用 any(byId:)
        XCTAssertEqual(Cards.any(byId: RDCards.heroId)?.enName, "Mathias Shaw")
        XCTAssertEqual(Cards.any(byId: RDCards.heroPowerId)?.enName, "Dagger Mastery")
    }

    /// `RDCards.def(_:)` 按 rawValue 直接索引排序后的表，少登记一条就静默错位
    func testCardTableIsCompleteAndAligned() {
        XCTAssertEqual(RDCards.table.count, RDCard.allCases.count,
                       "RDCards.table 的条目数要等于 RDCard 的 case 数")
        for card in RDCard.allCases {
            let hits = RDCards.table.filter { $0.card == card }
            XCTAssertEqual(hits.count, 1, "\(card) 在表里有 \(hits.count) 条，应恰好 1 条")
            XCTAssertEqual(RDCards.def(card).card, card, "RDCards.def(\(card)) 取到了别的牌")
        }
    }

    /// 挖掘宝藏的「海盗 → 给币」在本牌组永远不触发，换牌时这条断言会失败
    func testNoPirateAmongDeckMinions() {
        for card in RDCards.deckMinions {
            guard let id = RDCards.def(card).ids.first,
                  let c = Cards.by(cardId: id) else {
                XCTFail("\(card) 查不到")
                continue
            }
            XCTAssertFalse(c.races.contains(.pirate), "\(c.enName) 是海盗，挖掘宝藏的分支要建模了")
        }
    }

    // MARK: - 2. 缺件

    /// 缺件：8 水晶 8 费、手里只有一张 9 费的阿莱 —— 差的就是牌库里那张币
    func testMissingPiecesFindsTheCardThatEnablesLethal() {
        var s = stateWith(hand: [.alexstrasza], board: [], mana: 8, maxMana: 8)
        s.opponent = RDOpponent(health: 8)
        s.deck = RDDeck([(.coin, 1)])
        var config = RedDragonConfig()
        config.cpuBudget = 4
        config.beamWidth = 200
        let result = RedDragonSearch.solve(s, config: config)
        XCTAssertFalse(result.isLethal, "没有币时打不出 9 费的龙")
        XCTAssertEqual(result.missingPieces, [.coin])
    }

    private func missingPieceProbe() -> RDState {
        var s = stateWith(hand: [.alexstrasza, .foxyFraud], board: [], mana: 8, maxMana: 8)
        s.opponent = RDOpponent(health: 8)
        s.deck = RDDeck([(.coin, 1), (.shadowstep, 1), (.preparation, 1)])
        return s
    }

    /// 没撞 CPU 兜底时，缺件结果只由状态闸门决定：两次逐项相同、不报截断
    func testMissingPiecesReproducibleWhenCPUFallbackNotHit() {
        var config = RedDragonConfig()
        config.cpuBudget = 600
        config.missingPieceBudget = 600
        config.missingPieceMaxStates = 6_000
        let a = RedDragonSearch.solve(missingPieceProbe(), config: config)
        let b = RedDragonSearch.solve(missingPieceProbe(), config: config)
        XCTAssertEqual(a.missingPieces, [.coin])
        XCTAssertEqual(a.missingPieces, b.missingPieces)
        XCTAssertFalse(a.missingPiecesBudgetExceeded)
        XCTAssertFalse(b.missingPiecesBudgetExceeded)
    }

    /// 状态闸门真的会截断：总量 3 平分到 3 个候选，每个子搜索只展开 1 个节点，找不到币；
    /// 这是闸门（可复现）不是 CPU 兜底，所以不标截断
    func testMissingPiecesStateGateCutsTheSubSearch() {
        var config = RedDragonConfig()
        config.cpuBudget = 600
        config.missingPieceBudget = 600
        config.missingPieceMaxStates = 3
        let a = RedDragonSearch.solve(missingPieceProbe(), config: config)
        let b = RedDragonSearch.solve(missingPieceProbe(), config: config)
        XCTAssertTrue(a.missingPieces.isEmpty, "每个候选只给 1 个状态，搜不到斩杀")
        XCTAssertEqual(a.missingPieces, b.missingPieces)
        XCTAssertFalse(a.missingPiecesBudgetExceeded)
    }

    /// 撞上 CPU 兜底时结果不可复现，必须标出来
    func testMissingPiecesCPUFallbackIsFlagged() {
        var config = RedDragonConfig()
        config.cpuBudget = 600
        config.missingPieceBudget = 0
        let r = RedDragonSearch.solve(missingPieceProbe(), config: config)
        XCTAssertFalse(r.isLethal)
        XCTAssertTrue(r.missingPiecesBudgetExceeded)
    }

    // MARK: - 3. 幸运彗星前提 / 组件 / 占位牌

    /// 幸运彗星（T2a 前提字段）：下一张连击随从的连击触发两次，用掉一次；
    /// 刀油两层 -2 共两槽 → 首刀之后的牌 -4
    func testLuckyCometDoublesNextComboMinionOnce() {
        var s = stateWith(hand: [.scabbsCutterbutter, .scabbsCutterbutter, .foxyFraud],
                          board: [], mana: 10, maxMana: 10)
        s.cardsPlayedThisTurn = 1
        s.luckyCometCharges = 1
        let first = s.hand[0]
        let t = try! RDEngine.apply(.play(entityId: first.entityId, identity: .scabbsCutterbutter,
                                          target: .none, choices: []), to: s)
        XCTAssertEqual(t.luckyCometCharges, 0, "彗星被首张连击随从用掉")
        XCTAssertEqual(t.layers.count, 2, "连击触发两次 = 两层")
        let second = t.hand.first { $0.card == .scabbsCutterbutter }!
        XCTAssertEqual(t.cost(of: second, as: .scabbsCutterbutter), 0, "4 - 2 - 2")
        let u = try! RDEngine.apply(.play(entityId: second.entityId, identity: .scabbsCutterbutter,
                                          target: .none, choices: []), to: t)
        XCTAssertEqual(u.layers.filter { $0.slots == 2 }.count, 1, "第二张刀只触发一次")

        // 彗星状态进 canonicalHash：同局面有无彗星不能被去重成一个
        var noComet = s
        noComet.luckyCometCharges = 0
        XCTAssertNotEqual(s.canonicalHash(), noComet.canonicalHash())
    }

    /// 非连击随从不消耗彗星（卡面原文）。
    /// **待核假设**（T2b 用日志验，验不过就改引擎和这条测试）：鲨鱼在场时与彗星不叠加，仍是两次不是四次，
    /// 且彗星照样被这张刀用掉
    func testLuckyCometSkipsNonCombo_UnverifiedAssumptionNoStackWithShark() {
        var s = stateWith(hand: [.foxyFraud, .scabbsCutterbutter], board: [.spiritOfTheShark],
                          mana: 10, maxMana: 10)
        s.luckyCometCharges = 1
        let fox = s.hand[0]
        var t = try! RDEngine.apply(.play(entityId: fox.entityId, identity: .foxyFraud,
                                          target: .none, choices: []), to: s)
        XCTAssertEqual(t.luckyCometCharges, 1, "狐人老千不是连击牌")
        let scabbs = t.hand.first { $0.card == .scabbsCutterbutter }!
        t = try! RDEngine.apply(.play(entityId: scabbs.entityId, identity: .scabbsCutterbutter,
                                      target: .none, choices: []), to: t)
        XCTAssertEqual(t.luckyCometCharges, 0)
        XCTAssertEqual(t.layers.filter { $0.slots == 2 }.count, 2, "鲨鱼 ×2，彗星不再叠成 ×4")
    }

    /// 组件 = 主牌库六随从；看手牌（含 1/1 复制体）+ 我方场面，不看组名
    func testComponentsAreTheSixDeckMinionsInHandOrBoard() {
        var s = stateWith(hand: [.spiritOfTheShark, .foxyFraud, .scabbsCutterbutter, .coin],
                          board: [.shadowcaster], mana: 10, maxMana: 10)
        let id = s.takeEntityId()
        s.hand.append(RDHandCard(entityId: id, card: .etcBandManager, enchants: [.set(1)],
                                 statsOverride: RDStats(attack: 1, health: 1)))
        XCTAssertEqual(Set(RDComponents.minionPieces), Set(RDCards.deckMinions))
        XCTAssertEqual(RDComponents.minionPieces.count, 6)
        XCTAssertEqual(RDComponents.missing(in: s), [.darkscaleBroodmother])
        XCTAssertFalse(RDComponents.isComplete(s))
        let id2 = s.takeEntityId()
        s.hand.append(RDHandCard(entityId: id2, card: .darkscaleBroodmother))
        XCTAssertTrue(RDComponents.isComplete(s))
    }

    /// **待核假设**（T2b 用日志验）：连击没开时打出连击随从也会用掉彗星（连击效果本身没触发）
    func testLuckyComet_UnverifiedAssumptionConsumedEvenWithoutCombo() {
        var s = stateWith(hand: [.scabbsCutterbutter], board: [], mana: 10, maxMana: 10)
        s.luckyCometCharges = 1
        let t = try! RDEngine.apply(.play(entityId: s.hand[0].entityId, identity: .scabbsCutterbutter,
                                          target: .none, choices: []), to: s)
        XCTAssertEqual(t.luckyCometCharges, 0)
        XCTAssertTrue(t.layers.isEmpty, "连击没开，刀油不压层")
    }

    /// 生产搜索里不出现任何占位牌（「杂」「腾格」都只占手牌格）：带效果的「腾格」占位也打不出
    func testPlaceholdersNeverPlayableInSearch() {
        var s = stateWith(hand: [], board: [.foxyFraud], mana: 10, maxMana: 10)
        let slotId = s.takeEntityId()
        s.hand.append(RDHandCard(entityId: slotId, card: .freeSlotPlaceholder, printedCostOverride: 1))
        let junkId = s.takeEntityId()
        s.hand.append(RDHandCard.unmodeled(entityId: junkId, cardId: nil))
        let plays = RDEngine.legalActions(s).compactMap { action -> Int? in
            if case .play(let eid, _, _, _, _) = action { return eid }
            return nil
        }
        XCTAssertFalse(plays.contains(slotId))
        XCTAssertFalse(plays.contains(junkId))
        XCTAssertThrowsError(try RDEngine.apply(.play(entityId: slotId, identity: .freeSlotPlaceholder,
                                                      target: .friendlyMinion(s.board[0].entityId),
                                                      choices: []), to: s))
    }

    // MARK: - 5. 难度

    /// 模板齐全的一条标准启动：鱼 → 狐 → 刀 → 暗 → 牛 → 龙
    private var canonicalOpening: [RDAction] {
        return [play(.spiritOfTheShark), play(.foxyFraud), play(.scabbsCutterbutter),
                play(.shadowcaster), play(.etcBandManager), play(.alexstrasza)]
    }

    /// 更长的线更难（同一套模板牌，后面多接几步）
    func testDifficultyLongerLineIsHarder() {
        let short = RDDifficulty.components(for: canonicalOpening, sideboardCardsTaken: 1)
        let long = RDDifficulty.components(for: canonicalOpening
                                            + [play(.shadowstep), play(.bounceAround),
                                               play(.alexstrasza)],
                                           sideboardCardsTaken: 1)
        XCTAssertEqual(short.inversionPairs, 0)
        XCTAssertEqual(long.inversionPairs, 0)
        XCTAssertEqual(long.missingTemplateCards, 0)
        XCTAssertGreaterThan(long.score, short.score)
    }

    /// 边牌拿得越多越难
    func testDifficultyMoreSideboardCardsIsHarder() {
        let one = RDDifficulty.components(for: canonicalOpening, sideboardCardsTaken: 1)
        let three = RDDifficulty.components(for: canonicalOpening, sideboardCardsTaken: 3)
        XCTAssertGreaterThan(three.score, one.score)
    }

    /// v2 的重点：逆序启动。狐 → 鱼 比 鱼 → 狐 难，且必须由「颠倒对数」体现，
    /// 不是靠操作数或缺件（两条线的牌完全一样）
    func testDifficultyReversedOpeningIsHarder() {
        let canonical = RDDifficulty.components(for: canonicalOpening, sideboardCardsTaken: 1)
        let reversed = RDDifficulty.components(for: [
            play(.foxyFraud), play(.spiritOfTheShark), play(.scabbsCutterbutter),
            play(.shadowcaster), play(.etcBandManager), play(.alexstrasza)
        ], sideboardCardsTaken: 1)
        XCTAssertEqual(canonical.inversionPairs, 0)
        XCTAssertEqual(reversed.inversionPairs, 1, "只有鱼 / 狐这一对颠倒")
        XCTAssertEqual(reversed.actionCount, canonical.actionCount)
        XCTAssertEqual(reversed.missingTemplateCards, canonical.missingTemplateCards)
        XCTAssertGreaterThan(reversed.score, canonical.score)

        // 刀起手颠倒得更多：刀 排在鱼 / 狐前面 = 2 对
        let knifeFirst = RDDifficulty.components(for: [
            play(.scabbsCutterbutter), play(.spiritOfTheShark), play(.foxyFraud),
            play(.shadowcaster), play(.etcBandManager), play(.alexstrasza)
        ], sideboardCardsTaken: 1)
        XCTAssertEqual(knifeFirst.inversionPairs, 2)
        XCTAssertGreaterThan(knifeFirst.score, reversed.score)
    }

    /// 缺零件的替代线更难 —— 但要算成「缺」，不能记成「乱」
    func testDifficultyMissingTemplateCardIsHarder() {
        let withFox = RDDifficulty.components(for: canonicalOpening, sideboardCardsTaken: 1)
        let noFox = RDDifficulty.components(for: [
            play(.spiritOfTheShark), play(.scabbsCutterbutter), play(.shadowcaster),
            play(.etcBandManager), play(.alexstrasza)
        ], sideboardCardsTaken: 1)
        XCTAssertEqual(noFox.missingTemplateCards, 1)
        XCTAssertEqual(noFox.inversionPairs, 0, "缺的牌不算颠倒")
        XCTAssertGreaterThan(noFox.score, withFox.score)
    }

    /// 中途插牌：鱼和狐之间先打个步，模板顺序没变但更卡手
    func testDifficultyInterleavedActionIsHarder() {
        let clean = RDDifficulty.components(for: canonicalOpening, sideboardCardsTaken: 1)
        let interleaved = RDDifficulty.components(for: [
            play(.spiritOfTheShark), play(.shadowstep), play(.foxyFraud),
            play(.scabbsCutterbutter), play(.shadowcaster), play(.etcBandManager),
            play(.alexstrasza)
        ], sideboardCardsTaken: 1)
        XCTAssertEqual(clean.interleavedActions, 0)
        XCTAssertEqual(interleaved.interleavedActions, 1)
        XCTAssertEqual(interleaved.inversionPairs, 0)
        XCTAssertGreaterThan(interleaved.score, clean.score)

        // 模板开始之前的偷费不算插牌（币 / 伺是常规启动的一部分）
        let prefixed = RDDifficulty.components(for: [play(.coin), play(.preparation)]
                                                + canonicalOpening,
                                               sideboardCardsTaken: 1)
        XCTAssertEqual(prefixed.interleavedActions, 0)
    }

    private func play(_ card: RDCard) -> RDAction {
        return .play(entityId: 0, identity: card, target: .none, choices: [])
    }

    // MARK: - 6. 规则边界

    private func stateWith(hand: [RDCard], board: [RDCard], mana: Int, maxMana: Int,
                           handLimit: Int = 10) -> RDState {
        var s = RDState(maxMana: maxMana, mana: mana, opponent: RDOpponent(health: 30))
        s.handLimit = handLimit
        for c in hand {
            let id = s.takeEntityId()
            s.hand.append(RDHandCard(entityId: id, card: c,
                                     isShadowOfDemise: c == .shadowOfDemise))
        }
        for c in board {
            let def = RDCards.def(c)
            let id = s.takeEntityId()
            s.board.append(RDBoardMinion(entityId: id, card: c, attack: def.attack,
                                         health: def.health, maxHealth: def.health,
                                         statsSetTo1x1: false, silenced: false,
                                         summoningSick: false, attacksThisTurn: 0,
                                         enchants: []))
        }
        return s
    }

    func testEighthMinionCannotBePlayed() {
        let s = stateWith(hand: [.foxyFraud],
                          board: [.foxyFraud, .scabbsCutterbutter, .spiritOfTheShark,
                                  .shadowcaster, .etcBandManager, .darkscaleBroodmother,
                                  .alexstrasza],
                          mana: 10, maxMana: 10)
        XCTAssertEqual(s.board.count, 7)
        let action = RDAction.play(entityId: s.hand[0].entityId, identity: .foxyFraud,
                                   target: .none, choices: [])
        XCTAssertThrowsError(try RDEngine.apply(action, to: s)) { error in
            XCTAssertEqual(error as? RDIllegal, .boardFull)
        }
        XCTAssertFalse(RDEngine.legalActions(s).contains(action))
    }

    /// 用户定的一般规则：**状态里若出现卡表没建模的牌，当作不可打的杂牌，只占手牌格**
    /// （spike 六「未建模的牌」）。`RDCard.junkPlaceholder` 直接承担这个角色，新增的
    /// `unmodeledCardId` 只给 T2 显示用，不进搜索。幸运彗星（GDB_873）就走这条路：
    /// 不建模 → 搜不出依赖它的线 → 最多算保守，不会算出假线。
    func testUnmodeledCardIsUnplayableJunkThatOnlyOccupiesAHandSlot() {
        var s = stateWith(hand: [.alexstrasza], board: [], mana: 10, maxMana: 10, handLimit: 3)
        // 幸运彗星没进卡表 → 塞成杂牌占位，原 cardId 留着给 overlay 显示
        let junkId = s.takeEntityId()
        s.hand.append(RDHandCard.unmodeled(entityId: junkId, cardId: "GDB_873"))
        XCTAssertEqual(s.hand.count, 2)
        XCTAssertEqual(s.handSlotsFree, 1, "杂牌占掉一个手牌格")
        XCTAssertEqual(s.hand.last?.unmodeledCardId, "GDB_873")

        // 打不出去：legalActions 里没有它，apply 直接拒绝
        let actions = RDEngine.legalActions(s)
        for action in actions {
            if case .play(let eid, _, _, _, _) = action {
                XCTAssertNotEqual(eid, junkId, "未建模的牌不该产生动作")
            }
        }
        let playJunk = RDAction.play(entityId: junkId, identity: .junkPlaceholder,
                                     target: .none, choices: [])
        XCTAssertThrowsError(try RDEngine.apply(playJunk, to: s)) { error in
            XCTAssertEqual(error as? RDIllegal, .unplayableJunk)
        }
        // 它也不会被当成「缺的那一张」去试
        var probe = s
        probe.opponent = RDOpponent(health: 60)
        probe.deck = RDDeck([(.junkPlaceholder, 1)])
        var config = RedDragonConfig()
        config.cpuBudget = 2
        config.beamWidth = 120
        let result = RedDragonSearch.solve(probe, config: config)
        XCTAssertFalse(result.isLethal)
        XCTAssertTrue(result.missingPieces.isEmpty, "杂牌不可能是缺件")

        // 公式表重放口径下仍然打得出（表里的「杂」是真牌，只是表没写是哪张）
        let replayed = try? RDEngine.apply(playJunk, to: s, options: .replay)
        XCTAssertNotNil(replayed)
        XCTAssertEqual(replayed?.hand.count, 1)
    }

    /// 暗影施法者的战吼是**下场前**选目标，自己不在候选里。
    /// 公式表重放口径（目标未指定）的身份池同样要剔掉施法者自己；
    /// 场上没有别的随从时不产生复制。
    func testShadowcasterCannotCopyItself() {
        // 场上只有施法者自己 → 复制不出来
        var alone = stateWith(hand: [.shadowcaster], board: [], mana: 10, maxMana: 10)
        let caster = alone.hand[0]
        alone = try! RDEngine.apply(.play(entityId: caster.entityId, identity: .shadowcaster,
                                          target: .none, choices: []), to: alone,
                                    options: .replay)
        XCTAssertEqual(alone.board.count, 1)
        XCTAssertTrue(alone.hand.isEmpty, "场上没有别的随从 → 没有复制进手")

        // 场上有一条龙 → 复制的只能是龙，池子里不该出现暗影施法者自己
        let s = stateWith(hand: [.shadowcaster], board: [.alexstrasza], mana: 10, maxMana: 10)
        let caster2 = s.hand[0]
        let next = try! RDEngine.apply(.play(entityId: caster2.entityId, identity: .shadowcaster,
                                             target: .unspecifiedFriendly, choices: []),
                                       to: s, options: .replay)
        XCTAssertEqual(next.hand.count, 1)
        let copy = next.hand[0]
        XCTAssertEqual(copy.identities, [.alexstrasza], "身份池里只有龙，没有施法者自己")
        XCTAssertEqual(copy.statsOverride, RDStats(attack: 1, health: 1))
    }

    /// 阿莱的战吼对友方是治疗 8，不是伤害 —— 这条线打不出来，`legalActions` 里不该有，
    /// `apply` 要判 illegalTarget（card-model 第三部分第 9 条「治疗友方分支不展开」照旧成立）
    func testAlexstraszaCannotDamageFriendlyMinions() {
        var s = stateWith(hand: [.alexstrasza], board: [.foxyFraud], mana: 10, maxMana: 10)
        let friendlyId = s.board[0].entityId
        let enemyId = s.takeEntityId()
        s.opponent.board.append(RDEnemyMinion(entityId: enemyId, attack: 3, health: 9,
                                              taunt: false, divineShield: false,
                                              immune: false, stealth: false))
        let alex = s.hand[0]

        let atFriendly = RDAction.play(entityId: alex.entityId, identity: .alexstrasza,
                                       target: .friendlyMinion(friendlyId), choices: [])
        XCTAssertThrowsError(try RDEngine.apply(atFriendly, to: s)) { error in
            XCTAssertEqual(error as? RDIllegal, .illegalTarget)
        }
        // 公式表重放口径（未指定目标）也不能绕过去
        let unspecified = RDAction.play(entityId: alex.entityId, identity: .alexstrasza,
                                        target: .unspecifiedFriendly, choices: [])
        XCTAssertThrowsError(try RDEngine.apply(unspecified, to: s, options: .replay)) { error in
            XCTAssertEqual(error as? RDIllegal, .illegalTarget)
        }

        let actions = RDEngine.legalActions(s)
        for action in actions {
            guard case .play(_, let identity, let target, _, _) = action,
                  identity == .alexstrasza else { continue }
            if case .friendlyMinion = target {
                XCTFail("legalActions 里出现了阿莱指向友方随从的动作")
            }
        }
        XCTAssertTrue(actions.contains(.play(entityId: alex.entityId, identity: .alexstrasza,
                                             target: .enemyHero, choices: [])),
                      "打脸仍然合法")
        XCTAssertTrue(actions.contains(.play(entityId: alex.entityId, identity: .alexstrasza,
                                             target: .enemyMinion(enemyId), choices: [])),
                      "指敌方随从仍然合法")
        let hit = try! RDEngine.apply(.play(entityId: alex.entityId, identity: .alexstrasza,
                                            target: .enemyMinion(enemyId), choices: []), to: s)
        XCTAssertEqual(hit.opponent.board.first?.health, 1, "9 血的敌方随从吃 8 伤")
        XCTAssertEqual(hit.board.first { $0.entityId == friendlyId }?.health, 2,
                       "友方随从一点血没掉")
    }

    func testBounceAroundBurnsRightmostWhenHandIsFull() {
        // 手牌满 10（含舞动）；场上 3 个随从，打完舞动只剩 1 个手牌格
        var s = stateWith(hand: [.coin, .coin, .preparation, .preparation, .evasion, .evasion,
                                 .digForTreasure, .digForTreasure, .shroudOfConcealment,
                                 .bounceAround],
                          board: [.foxyFraud, .scabbsCutterbutter, .alexstrasza],
                          mana: 10, maxMana: 10)
        s.handLimit = 10
        XCTAssertEqual(s.hand.count, 10)
        let dance = s.hand.last!
        let next = try! RDEngine.apply(.play(entityId: dance.entityId, identity: .bounceAround,
                                             target: .none, choices: []), to: s)
        XCTAssertTrue(next.board.isEmpty, "舞动清空场面")
        XCTAssertEqual(next.hand.count, 10, "只有 1 个手牌格，只收得回 1 个随从")
        // 弹回顺序从左到右：只有最左的狐人进了手，最右侧的阿莱被烧
        XCTAssertTrue(next.hand.contains { $0.card == .foxyFraud })
        XCTAssertFalse(next.hand.contains { $0.card == .alexstrasza })
        XCTAssertFalse(next.hand.contains { $0.card == .scabbsCutterbutter })
    }

    func testBroodmotherRefreshClampsToCrystalsAndCoinDoesNotRaiseIt() {
        // 4 水晶、法力 4、鲨鱼在场、手里还有一张龙：付 3 剩 1，双触发 1→3→4（不 clamp 会是 5）
        var s = stateWith(hand: [.darkscaleBroodmother, .alexstrasza],
                          board: [.spiritOfTheShark], mana: 4, maxMana: 4)
        s.board[0].summoningSick = false
        let brood = s.hand[0]
        let after = try! RDEngine.apply(.play(entityId: brood.entityId,
                                              identity: .darkscaleBroodmother,
                                              target: .none, choices: []), to: s)
        XCTAssertEqual(after.mana, 4, "min(cur+2, maxMana) 每次触发各自 clamp")
        XCTAssertEqual(after.tempMana, 0)

        // 币的临时水晶不抬上限（G4）：4 水晶 + 1 张币 = 可用 5，复原仍只到 4
        var withCoin = stateWith(hand: [.coin, .darkscaleBroodmother, .alexstrasza],
                                 board: [], mana: 4, maxMana: 4)
        withCoin.handLimit = 10
        let coin = withCoin.hand[0]
        withCoin = try! RDEngine.apply(.play(entityId: coin.entityId, identity: .coin,
                                             target: .none, choices: []), to: withCoin)
        XCTAssertEqual(withCoin.mana, 4)
        XCTAssertEqual(withCoin.tempMana, 1)
        let brood2 = withCoin.hand.first { $0.card == .darkscaleBroodmother }!
        let after2 = try! RDEngine.apply(.play(entityId: brood2.entityId,
                                              identity: .darkscaleBroodmother,
                                              target: .none, choices: []), to: withCoin)
        // 3 费先花掉 1 点临时法力 + 2 点法力 → 法力 2，复原 min(2+2, 4) = 4，不是 5
        XCTAssertEqual(after2.tempMana, 0)
        XCTAssertEqual(after2.mana, 4, "币的临时水晶不抬高复原上限")
        XCTAssertEqual(after2.availableMana, 4)
    }

    func testDeafenCannotKillAlexstraszaCopyButKillsFoxyCopy() {
        // 1/1 阿莱复制体：沉默拿掉 1/1 附魔 → 变回 8/8，连击 2 伤打不死
        var s = stateWith(hand: [.deafen, .coin], board: [], mana: 10, maxMana: 10)
        let alexId = s.takeEntityId()
        s.board.append(RDBoardMinion(entityId: alexId, card: .alexstrasza, attack: 1, health: 1,
                                     maxHealth: 1, statsSetTo1x1: true, silenced: false,
                                     summoningSick: true, attacksThisTurn: 0, enchants: []))
        let foxId = s.takeEntityId()
        s.board.append(RDBoardMinion(entityId: foxId, card: .foxyFraud, attack: 1, health: 1,
                                     maxHealth: 1, statsSetTo1x1: true, silenced: false,
                                     summoningSick: true, attacksThisTurn: 0, enchants: []))
        s.cardsPlayedThisTurn = 1   // 连击已开

        let deafen = s.hand[0]
        let a = try! RDEngine.apply(.play(entityId: deafen.entityId, identity: .deafen,
                                          target: .friendlyMinion(alexId), choices: []), to: s)
        XCTAssertTrue(a.board.contains { $0.entityId == alexId }, "阿莱复制体沉默后是 8/8，活着")
        XCTAssertEqual(a.board.first { $0.entityId == alexId }?.health, 6, "8/8 吃 2 伤")

        var s2 = s
        s2.cardsPlayedThisTurn = 1
        let b = try! RDEngine.apply(.play(entityId: deafen.entityId, identity: .deafen,
                                          target: .friendlyMinion(foxId), choices: []), to: s2)
        XCTAssertFalse(b.board.contains { $0.entityId == foxId }, "狐人老千基础 3/2，沉默 + 2 伤会死")
    }

    func testShadowstepAndBounceAroundOrderMatters() {
        // 先舞动后步 = 0
        var s = stateWith(hand: [.bounceAround, .shadowstep], board: [.alexstrasza],
                          mana: 10, maxMana: 10)
        s.handLimit = 10
        let dance = s.hand[0]
        var t = try! RDEngine.apply(.play(entityId: dance.entityId, identity: .bounceAround,
                                          target: .none, choices: []), to: s)
        let alexCard = t.hand.first { $0.card == .alexstrasza }!
        XCTAssertEqual(t.cost(of: alexCard, as: .alexstrasza), 1, "舞动：本回合费用设为 1")
        t = try! RDEngine.apply(.play(entityId: alexCard.entityId, identity: .alexstrasza,
                                      target: .enemyHero, choices: []), to: t)
        let step = t.hand.first { $0.card == .shadowstep }!
        let alexOnBoard = t.board.first { $0.card == .alexstrasza }!
        t = try! RDEngine.apply(.play(entityId: step.entityId, identity: .shadowstep,
                                      target: .friendlyMinion(alexOnBoard.entityId),
                                      choices: []), to: t)
        let after = t.hand.first { $0.card == .alexstrasza }!
        XCTAssertEqual(t.cost(of: after, as: .alexstrasza), 0, "先舞动后步 = 0")

        // 先步后舞动 = 1
        var u = stateWith(hand: [.shadowstep, .bounceAround], board: [.alexstrasza],
                          mana: 10, maxMana: 10)
        u.handLimit = 10
        let step2 = u.hand[0]
        let alex2 = u.board[0]
        u = try! RDEngine.apply(.play(entityId: step2.entityId, identity: .shadowstep,
                                      target: .friendlyMinion(alex2.entityId),
                                      choices: []), to: u)
        let stepped = u.hand.first { $0.card == .alexstrasza }!
        XCTAssertEqual(u.cost(of: stepped, as: .alexstrasza), 7, "暗影步：印刷 9 - 2")
        u = try! RDEngine.apply(.play(entityId: stepped.entityId, identity: .alexstrasza,
                                      target: .enemyHero, choices: []), to: u)
        let dance2 = u.hand.first { $0.card == .bounceAround }!
        u = try! RDEngine.apply(.play(entityId: dance2.entityId, identity: .bounceAround,
                                      target: .none, choices: []), to: u)
        let bounced = u.hand.first { $0.card == .alexstrasza }!
        XCTAssertEqual(u.cost(of: bounced, as: .alexstrasza), 1, "先步后舞动 = 1")
    }

    func testScabbsLayerSurvivesBounceAroundPhase() {
        // G2：舞动分出的「阶段」不是回合，刀油的层带着剩余槽进入下一阶段
        var s = stateWith(hand: [.scabbsCutterbutter, .bounceAround, .spiritOfTheShark],
                          board: [], mana: 10, maxMana: 10)
        s.cardsPlayedThisTurn = 1   // 连击已开
        let scabbs = s.hand[0]
        var t = try! RDEngine.apply(.play(entityId: scabbs.entityId,
                                          identity: .scabbsCutterbutter,
                                          target: .none, choices: []), to: s)
        XCTAssertEqual(t.layers.count, 1)
        XCTAssertEqual(t.layers[0].slots, 2)
        let dance = t.hand.first { $0.card == .bounceAround }!
        t = try! RDEngine.apply(.play(entityId: dance.entityId, identity: .bounceAround,
                                      target: .none, choices: []), to: t)
        XCTAssertEqual(t.layers.count, 1, "舞动只吃掉一个槽，层还在")
        XCTAssertEqual(t.layers[0].slots, 1)
        let shark = t.hand.first { $0.card == .spiritOfTheShark }!
        XCTAssertEqual(t.cost(of: shark, as: .spiritOfTheShark), 2, "下一阶段的鱼吃第 2 槽")
    }

    func testZeroCostCardStillEatsScabbsSlot() {
        var s = stateWith(hand: [.scabbsCutterbutter, .coin, .spiritOfTheShark],
                          board: [], mana: 10, maxMana: 10)
        s.cardsPlayedThisTurn = 1
        var t = try! RDEngine.apply(.play(entityId: s.hand[0].entityId,
                                          identity: .scabbsCutterbutter,
                                          target: .none, choices: []), to: s)
        let coin = t.hand.first { $0.card == .coin }!
        t = try! RDEngine.apply(.play(entityId: coin.entityId, identity: .coin,
                                      target: .none, choices: []), to: t)
        XCTAssertEqual(t.layers[0].slots, 1, "0 费牌照样消耗刀油的槽")
    }

    func testSharkDoublesMinionBattlecryButNotSpellCombo() {
        // 鲨鱼在场：阿莱两次独立的 8 伤
        var s = stateWith(hand: [.alexstrasza], board: [.spiritOfTheShark],
                          mana: 10, maxMana: 10)
        s.mana = 9
        let alex = s.hand[0]
        let t = try! RDEngine.apply(.play(entityId: alex.entityId, identity: .alexstrasza,
                                          target: .enemyHero, choices: []), to: s)
        XCTAssertEqual(t.damageDealt, 16)

        // 致聋术是法术，连击不翻倍
        var u = stateWith(hand: [.deafen], board: [.spiritOfTheShark], mana: 10, maxMana: 10)
        u.cardsPlayedThisTurn = 1
        let target = u.board[0].entityId
        let v = try! RDEngine.apply(.play(entityId: u.hand[0].entityId, identity: .deafen,
                                          target: .friendlyMinion(target), choices: []), to: u)
        // 0/3 的鲨鱼被沉默后仍是 0/3，只吃一次 2 伤 → 1 血
        XCTAssertEqual(v.board.first?.health, 1)
    }

    func testBoneSpikeDiscountOnlyWhenTargetDies() {
        let s = stateWith(hand: [.serratedBoneSpike, .serratedBoneSpike],
                          board: [.spiritOfTheShark, .etcBandManager], mana: 10, maxMana: 10)
        let sharkId = s.board[0].entityId
        let etcId = s.board[1].entityId
        let kill = try! RDEngine.apply(.play(entityId: s.hand[0].entityId,
                                             identity: .serratedBoneSpike,
                                             target: .friendlyMinion(sharkId),
                                             choices: []), to: s)
        XCTAssertEqual(kill.board.count, 1, "0/3 的鲨鱼被 3 伤打死")
        XCTAssertEqual(kill.layers.count, 1, "击杀 → 下一张牌 -2")

        let miss = try! RDEngine.apply(.play(entityId: s.hand[0].entityId,
                                             identity: .serratedBoneSpike,
                                             target: .friendlyMinion(etcId),
                                             choices: []), to: s)
        XCTAssertEqual(miss.board.count, 2, "4/4 的牛头人吃 3 伤不死")
        XCTAssertTrue(miss.layers.isEmpty, "没打死就不减费")
    }

    // MARK: - 7. 随从落位

    /// 舞动按场上从左到右收回、手牌放不下的烧掉（用户 09-11 定的规则）——
    /// 新下的随从插在哪一格，直接决定烧掉谁
    func testPlacementDecidesWhichMinionBounceBurns() {
        // 手牌 10 张：鲨鱼 + 舞动 + 8 张币；场上 狐、阿莱
        var s = stateWith(hand: [.spiritOfTheShark, .bounceAround] + Array(repeating: .coin, count: 8),
                          board: [.foxyFraud, .alexstrasza], mana: 10, maxMana: 10)
        s.handLimit = 10
        let shark = s.hand[0]
        let dance = s.hand[1]
        let plays = RDEngine.legalActions(s).compactMap { a -> Int?? in
            guard case .play(let eid, _, _, _, let p) = a, eid == shark.entityId else { return nil }
            return .some(p)
        }
        XCTAssertEqual(plays, [nil, 1, 0], "场上 2 个不同随从：最右 / 中间 / 最左三种落位")

        func burned(after position: Int?) -> [RDCard] {
            var t = try! RDEngine.apply(.play(entityId: shark.entityId, identity: .spiritOfTheShark,
                                              target: .none, choices: [], position: position), to: s)
            let order = t.board.map { $0.card }
            t = try! RDEngine.apply(.play(entityId: dance.entityId, identity: .bounceAround,
                                          target: .none, choices: []), to: t)
            XCTAssertEqual(t.hand.count, 10)
            return order.filter { card in !t.hand.contains { $0.card == card } }
        }
        // 打完鲨鱼手里 9 张，舞动打出后 8 张 → 只剩 2 格，3 个随从烧掉最右那个
        XCTAssertEqual(burned(after: nil), [.spiritOfTheShark], "放最右 → 烧鲨鱼")
        XCTAssertEqual(burned(after: 0), [.alexstrasza], "放最左 → 鲨鱼收回，烧阿莱")
        XCTAssertEqual(burned(after: 1), [.alexstrasza], "放中间 → 烧阿莱")

        // 越界 / 法术带落位 → 非法
        XCTAssertThrowsError(try RDEngine.apply(.play(entityId: shark.entityId, identity: .spiritOfTheShark,
                                                      target: .none, choices: [], position: 3), to: s)) {
            XCTAssertEqual($0 as? RDIllegal, .illegalPosition)
        }
        XCTAssertThrowsError(try RDEngine.apply(.play(entityId: dance.entityId, identity: .bounceAround,
                                                      target: .none, choices: [], position: 0), to: s)) {
            XCTAssertEqual($0 as? RDIllegal, .illegalPosition)
        }
    }

    /// 只展开结果上不等价的落位：① 手牌 / 边牌 / 牌库里都没有按顺序处理全场的效果 → 只有最右一种；
    /// ② 插在完全相同的随从之间 → 场面序列相同，只留一种
    func testPlacementsOnlyExpandInequivalentPositions() {
        var noBounce = stateWith(hand: [.spiritOfTheShark], board: [.foxyFraud, .alexstrasza],
                                 mana: 10, maxMana: 10)
        noBounce.sideboard = []   // 默认边牌池里有舞动 / 幻觉药水
        noBounce.deck = RDDeck([])
        XCTAssertFalse(RDEngine.boardOrderMatters(noBounce))
        let plays = RDEngine.legalActions(noBounce).filter {
            if case .play = $0 { return true }
            return false
        }
        XCTAssertEqual(plays.count, 1, "没有舞动 / 幻觉药水 → 落位全等价")

        var same = stateWith(hand: [.spiritOfTheShark, .bounceAround],
                             board: [.spiritOfTheShark, .spiritOfTheShark], mana: 10, maxMana: 10)
        for i in same.board.indices { same.board[i].summoningSick = true }
        XCTAssertTrue(RDEngine.boardOrderMatters(same))
        XCTAssertEqual(RDEngine.placements(for: same.hand[0], identity: .spiritOfTheShark, state: same), [nil],
                       "三条一模一样的鲨鱼：插哪都是同一个场面")

        // 边牌池里有舞动也算（牛能发现出来）
        var side = noBounce
        side.sideboard = [.bounceAround]
        XCTAssertTrue(RDEngine.boardOrderMatters(side))
        XCTAssertEqual(RDEngine.placements(for: side.hand[0], identity: .spiritOfTheShark, state: side),
                       [nil, 1, 0])
    }

    /// 「爆手时再决定收回哪几张」（`RDBoardOrder`）和「下随从时逐格展开落位」得到的舞动后局面集合相同。
    /// 场上已有牛、刀油（锁定，牛在左），手里狐、鲨鱼、舞动，手牌上限 3：舞动时 4 个随从只收得回 3 个
    func testDeferredBoardOrderReachesSameOutcomesAsFullPlacement() {
        var s = stateWith(hand: [.foxyFraud, .spiritOfTheShark, .bounceAround],
                          board: [.etcBandManager, .scabbsCutterbutter], mana: 10, maxMana: 10, handLimit: 3)
        s.sideboard = []
        let n = assertDeferredMatchesFull(s, terminal: .bounceAround)
        XCTAssertGreaterThan(n, 3, "要有因落位不同而不同的结果")
    }

    /// 幻觉药水保留场面：爆手时只定了「复制到的在没复制到的左边」，两边内部的顺序还没定，
    /// 之后的舞动还能再选。A、B、C 三个自由随从（0 费狐 / 母龙 / 鲨鱼），药水只复制得了两个，
    /// 舞动只收得回一个：ABC 和 BAC 复制的都是 A、B，但舞动一个收 A、一个收 B，是两种结果
    func testDeferredBoardOrderKeepsFreedomAfterPotion() {
        var s = stateWith(hand: [.potionOfIllusion, .bounceAround], board: [], mana: 10, maxMana: 10,
                          handLimit: 3)
        s.sideboard = []
        for card in [RDCard.foxyFraud, .darkscaleBroodmother, .spiritOfTheShark] {
            s.hand.append(RDHandCard(entityId: s.takeEntityId(), card: card, enchants: [.set(0)]))
        }
        let n = assertDeferredMatchesFull(s, terminal: .bounceAround)
        XCTAssertGreaterThanOrEqual(n, 3, "舞动收回的那张可以是三张里任一张")
    }

    /// 从 `s` 出发、只打起手里那几张牌，比较「逐格展开落位」和「爆手时再定（`RDBoardOrder`）」打出
    /// `terminal` 之后的局面集合，必须相同；延后决定的每条路径翻译成落位后，引擎原样重放也要到同一个局面。
    /// 返回不同结果的个数
    @discardableResult
    private func assertDeferredMatchesFull(_ s: RDState, terminal: RDCard,
                                           file: StaticString = #filePath, line: UInt = #line) -> Int {
        let original = Set(s.hand.map { $0.entityId })
        func allowed(_ a: RDAction) -> (ok: Bool, isTerminal: Bool) {
            guard case .play(let eid, let identity, _, _, _) = a, original.contains(eid) else { return (false, false) }
            return (true, identity == terminal)
        }
        var full = Set<UInt64>()
        func dfsFull(_ t: RDState) {
            for a in RDEngine.legalActions(t) {
                let k = allowed(a)
                guard k.ok, let next = try? RDEngine.apply(a, to: t) else { continue }
                if k.isTerminal { full.insert(next.canonicalHash()) } else { dfsFull(next) }
            }
        }
        dfsFull(s)

        var deferred = Set<UInt64>()
        var translated = 0
        var noPlacements = RDOptions.search
        noPlacements.expandPlacements = false
        var path: [RDAction] = []
        var decisions: [RDOrderDecision?] = []
        func dfsDeferred(_ t: RDState, _ c: RDBoardConstraints) {
            for a in RDEngine.legalActions(t, options: noPlacements) {
                let k = allowed(a)
                guard k.ok, let first = try? RDEngine.apply(a, to: t) else { continue }
                for o in RDBoardOrder.outcomes(of: a, from: t, constraints: c, first: first, options: .search) {
                    path.append(a)
                    decisions.append(o.decision)
                    if k.isTerminal {
                        deferred.insert(o.state.canonicalHash())
                        let placed = RDBoardOrder.assignPositions(path, decisions: decisions, root: s,
                                                                  options: .search)
                        let end = placed.flatMap { try? RDReplay.run($0, from: s) }
                        XCTAssertEqual(end?.finalState.canonicalHash(), o.state.canonicalHash(),
                                       "翻译成落位后重放结果不同", file: file, line: line)
                        translated += 1
                    } else {
                        dfsDeferred(o.state, o.constraints)
                    }
                    path.removeLast()
                    decisions.removeLast()
                }
            }
        }
        dfsDeferred(s, RDBoardConstraints.root(s))
        XCTAssertGreaterThan(translated, 0, file: file, line: line)
        XCTAssertEqual(full, deferred, file: file, line: line)
        return full.count
    }

    /// 落位翻译要改写编号：场上鲨鱼，手里狐、药水、舞动、7 张杂。线是 下狐 → 药水（不爆手，鲨鱼和狐
    /// 各复制一张）→ 舞动只收得回一个、收狐 → 下药水复制出的狐。搜索口径里狐在最右，复制出的狐是
    /// 第二张复制品；翻译后狐要插到最左，药水的进手顺序跟着变，那个编号就成了鲨鱼的复制品。
    func testPlacementTranslationRemapsEntityIds() throws {
        var s = stateWith(hand: [.foxyFraud, .potionOfIllusion, .bounceAround]
                            + Array(repeating: .junkPlaceholder, count: 7),
                          board: [.spiritOfTheShark], mana: 10, maxMana: 10)
        s.sideboard = []
        let sharkId = s.board[0].entityId
        let fox = s.hand[0], potion = s.hand[1], dance = s.hand[2]
        let a1 = RDAction.play(entityId: fox.entityId, identity: .foxyFraud, target: .none, choices: [])
        let s1 = try RDEngine.apply(a1, to: s)
        let foxOnBoard = s1.board.last!.entityId
        let a2 = RDAction.play(entityId: potion.entityId, identity: .potionOfIllusion, target: .none, choices: [])
        let s2 = try RDEngine.apply(a2, to: s1)
        let foxCopy = s2.hand.first { $0.card == .foxyFraud && $0.statsOverride != nil }!
        let a3 = RDAction.play(entityId: dance.entityId, identity: .bounceAround, target: .none, choices: [])
        let a4 = RDAction.play(entityId: foxCopy.entityId, identity: .foxyFraud, target: .none, choices: [])
        let decisions: [RDOrderDecision?] = [nil, nil, RDOrderDecision(order: [foxOnBoard, sharkId], front: 1), nil]

        // 搜索口径（舞动处按 decision 重排）能走通
        var t = try RDEngine.apply(a2, to: s1)
        t.board = [t.board[1], t.board[0]]
        t = try RDEngine.apply(a4, to: RDEngine.apply(a3, to: t))
        XCTAssertTrue(t.hand.contains { $0.card == .foxyFraud && $0.statsOverride == nil }, "舞动收回的是狐")

        // 只改落位、不改编号的话，第 4 步打的是鲨鱼的复制品
        let positionOnly: [RDAction] = [
            .play(entityId: fox.entityId, identity: .foxyFraud, target: .none, choices: [], position: 0),
            a2, a3, a4]
        XCTAssertThrowsError(try RDReplay.run(positionOnly, from: s))

        let placed = try XCTUnwrap(RDBoardOrder.assignPositions([a1, a2, a3, a4], decisions: decisions,
                                                                root: s, options: .search))
        guard case .play(_, _, _, _, let p) = placed[0] else { return XCTFail() }
        XCTAssertEqual(p, 0, "狐插最左，舞动才收得回它")
        guard case .play(let copyId, _, _, _, _) = placed[3] else { return XCTFail() }
        XCTAssertNotEqual(copyId, foxCopy.entityId, "编号已改写成带落位重放时狐的复制品")
        let end = try RDReplay.run(placed, from: s)
        XCTAssertEqual(end.finalState.canonicalHash(), t.canonicalHash())
    }

    /// 一模一样的友方随从站位不同就不是等价目标（Codex 第五轮复现）：剩 3 费、对手 16 血，场面从左到右
    /// 1/1 阿莱 A、暗影施法者、鲨鱼、1/1 阿莱 B，都不能攻击；手里 −2 费骨刺、幻觉药水、8 张杂。
    /// 0 费骨刺杀**右边**的 B → 药水（骨刺击杀减 2）2 费，手里只剩 2 格，复制最左的 A 和施法者 →
    /// 1 费阿莱打脸 8，鲨鱼触发两次 = 16。原来同款随从只留最左那个目标，骨刺只能杀 A，最多 8
    func testIdenticalFriendlyMinionsAtDifferentPositionsAreDistinctTargets() throws {
        var s = stateWith(hand: [], board: [], mana: 3, maxMana: 10)
        s.sideboard = []
        s.opponent = RDOpponent(health: 16)
        func alexCopy() -> RDBoardMinion {
            RDBoardMinion(entityId: s.takeEntityId(), card: .alexstrasza, attack: 1, health: 1, maxHealth: 1,
                          statsSetTo1x1: true, silenced: false, summoningSick: true, attacksThisTurn: 0,
                          enchants: [])
        }
        func minion(_ c: RDCard) -> RDBoardMinion {
            let def = RDCards.def(c)
            return RDBoardMinion(entityId: s.takeEntityId(), card: c, attack: def.attack, health: def.health,
                                 maxHealth: def.health, statsSetTo1x1: false, silenced: false,
                                 summoningSick: true, attacksThisTurn: 0, enchants: [])
        }
        let a = alexCopy(), caster = minion(.shadowcaster), shark = minion(.spiritOfTheShark), b = alexCopy()
        s.board = [a, caster, shark, b]
        let spike = RDHandCard(entityId: s.takeEntityId(), card: .serratedBoneSpike, enchants: [.delta(-2)])
        let potion = RDHandCard(entityId: s.takeEntityId(), card: .potionOfIllusion)
        s.hand = [spike, potion]
        for _ in 0..<8 { s.hand.append(RDHandCard(entityId: s.takeEntityId(), card: .junkPlaceholder)) }

        let spikeTargets = RDEngine.legalActions(s).compactMap { act -> Int? in
            guard case .play(let eid, _, .friendlyMinion(let t), _, _) = act, eid == spike.entityId else { return nil }
            return t
        }
        XCTAssertTrue(spikeTargets.contains(a.entityId) && spikeTargets.contains(b.entityId),
                      "两只 1/1 阿莱都要能被指到")

        // 手工走一遍合法斩杀
        var t = try RDEngine.apply(.play(entityId: spike.entityId, identity: .serratedBoneSpike,
                                         target: .friendlyMinion(b.entityId), choices: []), to: s)
        t = try RDEngine.apply(.play(entityId: potion.entityId, identity: .potionOfIllusion,
                                     target: .none, choices: []), to: t)
        let copy = try XCTUnwrap(t.hand.first { $0.card == .alexstrasza })
        t = try RDEngine.apply(.play(entityId: copy.entityId, identity: .alexstrasza,
                                     target: .enemyHero, choices: []), to: t)
        XCTAssertEqual(t.damageDealt, 16)

        for (name, config) in [("精确", RedDragonConfig.exact), ("默认", RedDragonConfig())] {
            let result = RedDragonSearch.solve(s, config: config)
            XCTAssertTrue(result.isLethal, "\(name)搜索只到 \(result.maxDamage)")
            if let line = result.chosenLine {
                XCTAssertNotNil(RDReplay.validate(line.actions, from: s, expectedDamage: 16), name)
            }
        }
    }

    /// 「等价目标合并」的独立核对（不经 `legalActions` 的合并）：对每张要指目标的手牌，把所有友方 / 敌方
    /// 实体和英雄都当目标逐个执行，每个结果（局面 + 场序偏序）都必须能由 `legalActions` 给出的某个动作、
    /// 再经搜索的 `collapseEquivalentTargets` 之后到达。覆盖伤害（骨刺）、弹回（暗影步）、复制（施法者）
    /// 三类单体目标，场上 / 敌方都有一模一样的随从；有、没有按场序处理全场的牌各一遍
    func testTargetMergingCoversEveryEntityTarget() throws {
        for withPotion in [true, false] {
            var s = stateWith(hand: [.serratedBoneSpike, .shadowstep, .shadowcaster]
                                + (withPotion ? [.potionOfIllusion] : []),
                              board: [.foxyFraud, .spiritOfTheShark, .foxyFraud], mana: 10, maxMana: 10)
            s.sideboard = []
            s.deck = RDDeck([])
            // 场面：狐(失调) 鲨鱼 狐(能攻击) 狐(失调)。第 1、4 只一模一样但不相邻：药水在手时指哪只不等价；
            // 第 3 只能攻击，和另两只本来就不等价
            s.board[0].summoningSick = true
            s.board.append(RDBoardMinion(entityId: s.takeEntityId(), card: .foxyFraud, attack: 3, health: 2,
                                         maxHealth: 2, statsSetTo1x1: false, silenced: false,
                                         summoningSick: true, attacksThisTurn: 0, enchants: []))
            for _ in 0..<2 {
                s.opponent.board.append(RDEnemyMinion(entityId: s.takeEntityId(), attack: 2, health: 2,
                                                      taunt: false, divineShield: false, immune: false,
                                                      stealth: false))
            }
            XCTAssertEqual(RDEngine.boardOrderMatters(s), withPotion)
            let c = RDBoardConstraints.root(s)
            // 没有按场序处理全场的牌时场序不影响任何结果：按 minionKey 排好再比（哈希本身对场序敏感）
            func key(_ next: RDState) -> UInt64 {
                guard withPotion else {
                    var t = next
                    t.board.sort { RDEngine.minionKey($0) < RDEngine.minionKey($1) }
                    return t.canonicalHash()
                }
                return RedDragonSearch.dedupKey(next.canonicalHash(), RDBoardOrder.carry(c, to: next), next.board)
            }
            let listed = RedDragonSearch.collapseEquivalentTargets(RDEngine.legalActions(s), s, c,
                                                                   options: .search)
            let reached = Set(listed.compactMap { try? RDEngine.apply($0, to: s) }.map(key))
            let allTargets: [RDTarget] = s.board.map { .friendlyMinion($0.entityId) }
                + s.opponent.board.map { .enemyMinion($0.entityId) } + [.enemyHero]
            var checked = 0
            for card in s.hand where RDCards.def(card.card).targetScope != .none {
                for target in allTargets {
                    let act = RDAction.play(entityId: card.entityId, identity: card.card, target: target, choices: [])
                    guard let next = try? RDEngine.apply(act, to: s) else { continue }
                    checked += 1
                    XCTAssertTrue(reached.contains(key(next)),
                                  "\(card.card) 指 \(target) 的结果没被覆盖（药水在手：\(withPotion)）")
                }
            }
            XCTAssertGreaterThan(checked, 8)
        }
    }

    /// 束搜索不逐格展开落位，而在爆手的舞动那一步展开「收回哪几张」，再翻译回落位。
    /// 场上已有 狐、牛（回合开始就在，顺序锁定），手里 1 费阿莱复制 + 舞动，手牌上限 2：
    /// 阿莱放最右会被烧，插到牛的左边才能收回、再打一次凑够 16（狐的相对位置锁定，插第 2 格最贴近原顺序）
    func testSearchPlacesMinionSoBounceKeepsIt() {
        var s = stateWith(hand: [.bounceAround], board: [.foxyFraud, .etcBandManager],
                          mana: 10, maxMana: 10, handLimit: 2)
        let alexId = s.takeEntityId()
        s.hand.insert(RDHandCard(entityId: alexId, card: .alexstrasza, enchants: [.set(1)],
                                 statsOverride: RDStats(attack: 1, health: 1)), at: 0)
        s.opponent = RDOpponent(health: 16)
        let result = RedDragonSearch.solve(s, config: RedDragonConfig())
        XCTAssertTrue(result.isLethal, "搜到 \(result.maxDamage)")
        guard let line = result.chosenLine else { return XCTFail("没有线") }
        XCTAssertNotNil(RDReplay.validate(line.actions, from: s, expectedDamage: 16))
        let alexPositions = line.actions.compactMap { a -> Int?? in
            guard case .play(_, let identity, _, _, let p) = a, identity == .alexstrasza else { return nil }
            return .some(p)
        }
        // 第一次插在狐和牛之间（第 2 格）；舞动后场面已空，第二次放哪都一样（最右）
        XCTAssertEqual(alexPositions, [1, nil])
        XCTAssertNil(line.pendingBoardOrders, "返回的线已经翻译成落位")
    }

    // MARK: - 8. 只用于验证的牌（背刺 / 袋底藏沙 / 脱水）

    func testVerificationCardsAreNotInTheDeck() {
        for card in [RDCard.backstab, .pocketSand, .dehydrate] {
            let def = RDCards.def(card)
            XCTAssertTrue(def.verificationOnly)
            XCTAssertEqual(def.deckCount, 0, "\(card) 不在本牌组")
            XCTAssertFalse(def.isSideboard)
            XCTAssertFalse(RDCards.sideboardCards.contains(card))
            XCTAssertFalse(def.isPlaceholder, "按官方文本建模，不是占位")
        }
        // 生产搜索只会在手里真有这张牌时才打得出它：牌库按 deckCount 建，里面没有它们
        XCTAssertEqual(RDCards.card(forId: "CS2_072"), .backstab)
        XCTAssertEqual(RDCards.card(forId: "WW_403"), .pocketSand)
        XCTAssertEqual(RDCards.card(forId: "WW_325"), .dehydrate)
    }

    /// 背刺：只能指未受伤的随从
    func testBackstabNeedsAnUndamagedMinion() {
        var s = stateWith(hand: [.backstab], board: [.spiritOfTheShark, .etcBandManager],
                          mana: 10, maxMana: 10)
        s.board[0].health = 2   // 鲨鱼 0/3 已受伤
        let hurt = s.board[0].entityId
        let fresh = s.board[1].entityId
        let enemyId = s.takeEntityId()
        s.opponent.board.append(RDEnemyMinion(entityId: enemyId, attack: 2, health: 5,
                                              taunt: false, divineShield: false,
                                              immune: false, stealth: false))
        let stab = s.hand[0]
        XCTAssertThrowsError(try RDEngine.apply(.play(entityId: stab.entityId, identity: .backstab,
                                                      target: .friendlyMinion(hurt), choices: []), to: s)) {
            XCTAssertEqual($0 as? RDIllegal, .illegalTarget)
        }
        let targets = RDEngine.legalActions(s).compactMap { a -> RDTarget? in
            guard case .play(let eid, _, let t, _, _) = a, eid == stab.entityId else { return nil }
            return t
        }
        XCTAssertFalse(targets.contains(.friendlyMinion(hurt)))
        XCTAssertTrue(targets.contains(.friendlyMinion(fresh)))
        XCTAssertTrue(targets.contains(.enemyMinion(enemyId)))
        XCTAssertFalse(targets.contains(.enemyHero), "背刺不能打脸")

        // 敌方随从挨过一次伤之后就不能再背刺
        var t = s
        t.hand.append(RDHandCard(entityId: t.takeEntityId(), card: .backstab))
        t = try! RDEngine.apply(.play(entityId: stab.entityId, identity: .backstab,
                                      target: .enemyMinion(enemyId), choices: []), to: t)
        XCTAssertEqual(t.opponent.board.first?.health, 3)
        let second = t.hand.first { $0.card == .backstab }!
        XCTAssertThrowsError(try RDEngine.apply(.play(entityId: second.entityId, identity: .backstab,
                                                      target: .enemyMinion(enemyId), choices: []), to: t)) {
            XCTAssertEqual($0 as? RDIllegal, .illegalTarget)
        }
    }

    /// 脱水的快枪：本回合进手时 1 费，起手就在手里的按印刷 3 费
    func testDehydrateQuickdrawOnlyWhenItEnteredHandThisTurn() {
        var s = stateWith(hand: [.dehydrate], board: [], mana: 10, maxMana: 10)
        XCTAssertEqual(s.cost(of: s.hand[0], as: .dehydrate), 3)
        let before = s.canonicalHash()
        s.hand[0].enteredHandThisTurn = true
        XCTAssertEqual(s.cost(of: s.hand[0], as: .dehydrate), 1)
        XCTAssertNotEqual(s.canonicalHash(), before, "快枪牌的进手时机影响费用，要进哈希")

        // 快枪费用是固定值，盖过减费层（待核口径，card-model H 节）；没进手的照常吃减费
        s.layers.append(RDDiscountLayer(amount: 3, slots: 1, filter: .spell))
        XCTAssertEqual(s.cost(of: s.hand[0], as: .dehydrate), 1, "快枪 (1) 不再被减到 0")
        s.hand[0].enteredHandThisTurn = false
        XCTAssertEqual(s.cost(of: s.hand[0], as: .dehydrate), 0, "印刷 3 费吃 -3")
        s.hand[0].enteredHandThisTurn = true

        // 非快枪牌的进手时机不进哈希（不制造假的不同状态）
        var u = stateWith(hand: [.pocketSand], board: [], mana: 10, maxMana: 10)
        let h = u.canonicalHash()
        u.hand[0].enteredHandThisTurn = true
        XCTAssertEqual(u.canonicalHash(), h)
        XCTAssertEqual(u.cost(of: u.hand[0], as: .pocketSand), 2)
    }
}
