//
//  RedDragonTests.swift
//  HSTrackerTests
//
//  红龙贼搜索核心（spike RDR / T1）的验收测试。
//  公式表 fixture 行 → 初始状态的映射照 HSTrackerTests/Fixtures/RedDragon/sim.py 的
//  seed_for / run_row 约定：法力 = cost，水晶上限 = crystals，
//  起手 = 六个核心随从 + 特殊杂牌各两张 + 常见偷费牌各一张。
//

import XCTest
@testable import HSTracker

// MARK: - 公式表缩写

private let rdAbbreviations: [String: RDCard] = [
    "鱼": .spiritOfTheShark,
    "狐": .foxyFraud,
    "刀": .scabbsCutterbutter,
    "暗": .shadowcaster,
    "牛": .etcBandManager,
    "晦": .darkscaleBroodmother,
    "龙": .alexstrasza,
    "舞": .bounceAround,
    "幻": .potionOfIllusion,
    "步": .shadowstep,
    "骨": .serratedBoneSpike,
    "伺": .preparation,
    "殒": .shadowOfDemise,
    "币": .coin,
    "帷幕": .shroudOfConcealment,
    "杂": .junkPlaceholder,
    "腾格": .freeSlotPlaceholder
]

/// sim.py 的 seed_for 里会被当作「特殊杂牌各两张」加进起手的缩写（PRINTED 的键）
private let rdSeedableJunk: Set<String> = [
    "鱼", "狐", "刀", "暗", "牛", "晦", "龙", "舞", "幻", "步", "骨", "伺", "殒", "币", "帷幕"
]

// MARK: - fixture 数据

private struct RDToken {
    var card: String
    var target: String?
    var manaAfter: Int?
}

private struct RDRow {
    var id: String
    var group: String
    var crystals: Int?
    var cost: Int?
    var damage: Int?
    var specialJunk: [String]
    /// 每一阶段的 token；阶段为 nil 且没有 expandedLines 时截断
    var phases: [[RDToken]?]
    var expandedLines: [[RDToken]]
    var hasNullPhase: Bool
}

private struct RDReplayReport {
    var id: String
    var ok: Bool
    var failure: String?
    var group: String = ""
    var actions: [RDAction] = []
    var difficulty: Double = 0
    var sideboardTaken: Int = 0
    var damage: Int = 0
    var components: RDDifficulty.Components?
}

// MARK: - 重放失败白名单（card-model G 节「原表的错」）

/// 白名单之外不许有失败。每条写清为什么。
private let rdExpectedReplayFailures: [String: String] = {
    // ① 彗逆序 18 行：**不是原表算错，是前提条件没进转录**（2026-09-11 用户看图纠正）。
    //    表 2 那一组的组名是「提前**彗**」= 上回合已打过幸运彗星（Lucky Comet，GDB_873，dbfId
    //    111292，2 费潜行者法术：发现一张连击随从，你打出的下一张连击随从的连击效果触发两次，
    //    效果不限本回合）。有它在，首张刀油的连击就是两层 -2 = -4，这 18 行全部自洽。
    //    **本牌组不带幸运彗星**（spike 六「牌表」），所以这 18 行对它不适用，引擎也不建模这张牌
    //    —— 一般规则是「卡表没建模的牌 = 不可打的杂牌，只占手牌格」，见
    //    testUnmodeledCardIsUnplayableJunkThatOnlyOccupiesAHandSlot。
    let cometReason = "依赖幸运彗星（GDB_873）：首刀连击双触发 -4，本牌组不带这张牌，不建模"
    return [
    "t2-huqs-01": cometReason,
    "t2-huqs-02": cometReason,
    "t2-huqs-03": cometReason,
    "t2-huqs-04a": cometReason,
    "t2-huqs-04b": cometReason,
    "t2-huqs-05": cometReason,
    "t2-daoqs-01": cometReason + "；另「刀1」应为「刀0」",
    "t2-daoqs-02": cometReason,
    "t2-daoqs-03": cometReason,
    "t2-daoqs-04a": cometReason + "；另「刀1」应为「刀0」",
    "t2-daoqs-04b": cometReason + "；另「刀1」应为「刀0」",
    "t2-daoqs-05": cometReason,
    "t2-wuhui2-01": cometReason,
    "t2-wuhui2-02": cometReason,
    "t2-16-01a": cometReason,
    "t2-16-01b": cometReason,
    "t2-pre-01": cometReason,
    "t2-pre-02": cometReason,
    // ② 单格笔误
    "t1-48-02": "水晶列笔误：4 水晶时晦鳞回不到 5，应为 5（fixture inference 已核高清图）",
    "t1-48-06b": "合并单元格：4 水晶那一半照抄了 5 水晶的二阶段，晦少回 1 费，走不完",
    "t1-48-11": "二阶段起手「鱼0」应为「鱼1」（fixture inference，旁证 t1-48p-01 同一阶段写的就是鱼1）",
    "t1-48p-08": "二阶段「殒舞3」漏了连字符，应为单 token「殒-舞3」；拆成两个 token 时手里没有第二张舞"
    ]
}()

// MARK: -

class RedDragonTests: HSTrackerTests {

    private static var rows: [RDRow] = []

    override class func setUp() {
        super.setUp()
        if Cards.by(cardId: CardIds.Collectible.Rogue.Shadowstep) == nil {
            Database().loadDatabase(splashscreen: nil, withLanguages: [.enUS])
        }
        rows = loadFixture()
    }

    private static func loadFixture() -> [RDRow] {
        guard let url = Bundle(for: RedDragonTests.self).url(forResource: "formulas",
                                                            withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = json["rows"] as? [[String: Any]] else {
            return []
        }
        return raw.map { dict in
            var special: [String] = []
            if let s = dict["specialJunk"] as? String {
                special = [s]
            } else if let a = dict["specialJunk"] as? [String] {
                special = a
            }
            var phases: [[RDToken]?] = []
            var hasNull = false
            if let steps = dict["steps"] as? [Any] {
                for phase in steps {
                    guard let tokens = phase as? [[String: Any]] else {
                        phases.append(nil)
                        hasNull = true
                        continue
                    }
                    phases.append(tokens.map {
                        RDToken(card: ($0["card"] as? String) ?? "",
                                target: $0["target"] as? String,
                                manaAfter: $0["manaAfter"] as? Int)
                    })
                }
            }
            var expanded: [[RDToken]] = []
            if let lines = dict["expandedLines"] as? [[String: Any]] {
                for line in lines {
                    guard let tokens = line["steps"] as? [[String: Any]] else { continue }
                    expanded.append(tokens.map {
                        RDToken(card: ($0["card"] as? String) ?? "",
                                target: $0["target"] as? String,
                                manaAfter: $0["manaAfter"] as? Int)
                    })
                }
            }
            return RDRow(id: (dict["id"] as? String) ?? "?",
                         group: (dict["group"] as? String) ?? "",
                         crystals: dict["crystals"] as? Int,
                         cost: dict["cost"] as? Int,
                         damage: dict["damage"] as? Int,
                         specialJunk: special,
                         phases: phases,
                         expandedLines: expanded,
                         hasNullPhase: hasNull)
        }
    }

    // MARK: - 初始状态

    /// 照 sim.py 的 seed_for。注意它给出的起手是 12~18 张，超过手牌上限 10 ——
    /// 公式表这批用例把 handLimit 放开，手牌上限单独由 testHandLimitBurnsRightmost 覆盖。
    private func seedState(_ row: RDRow) -> RDState? {
        guard let cost = row.cost else { return nil }
        var state = RDState(maxMana: row.crystals ?? 99, mana: cost,
                            opponent: RDOpponent(health: 400))
        state.handLimit = 99
        var names: [String] = ["鱼", "狐", "刀", "暗", "牛", "晦"]
        for j in row.specialJunk where rdSeedableJunk.contains(j) {
            names.append(j)
            names.append(j)
        }
        names.append(contentsOf: ["步", "骨", "伺", "殒", "币", "帷幕"])
        for name in names {
            guard let card = rdAbbreviations[name] else { continue }
            let id = state.takeEntityId()
            state.hand.append(RDHandCard(entityId: id, card: card,
                                         isShadowOfDemise: card == .shadowOfDemise))
        }
        state.deck = RDDeck()
        state.sideboard = RDCards.sideboardCards
        return state
    }

    /// 每一阶段：非 null 用 steps，null 用 expandedLines 的第 variant 条，没有就截断
    private func tokens(_ row: RDRow, variant: Int) -> [RDToken] {
        var out: [RDToken] = []
        for phase in row.phases {
            if let phase = phase {
                out.append(contentsOf: phase)
            } else if !row.expandedLines.isEmpty {
                out.append(contentsOf: row.expandedLines[min(variant,
                                                             row.expandedLines.count - 1)])
            } else {
                break
            }
        }
        return out
    }

    // MARK: - token → 动作

    private struct RDScriptError: Error {
        var message: String
    }

    /// 挑一张手牌：优先让打完剩余法力与表里的 manaAfter 对上（同名多张时的消歧），
    /// 否则取最便宜的那张。与 sim.py 的 take() 同口径。
    private func pickHandCard(_ state: RDState, identity: RDCard,
                              manaAfter: Int?) throws -> RDHandCard {
        // 身份已定的牌优先，通配牌（牛的发现 / 暗影施法者的复制）留到真的只能用它时才消耗
        let candidates = state.hand.filter { $0.identities.contains(identity) }
            .sorted { a, b in
                let ra = a.pool.isEmpty ? 0 : 1
                let rb = b.pool.isEmpty ? 0 : 1
                return ra != rb ? ra < rb : a.entityId < b.entityId
            }
        guard !candidates.isEmpty else {
            throw RDScriptError(message: "手里没有 \(identity)")
        }
        if let want = manaAfter {
            for c in candidates {
                let cost = state.cost(of: c, as: identity)
                var after = state.availableMana - cost
                let def = RDCards.def(identity)
                let triggers = (def.doubledByShark && state.sharkAuraActive) ? 2 : 1
                for e in def.effects {
                    switch e {
                    case .refreshMana(let n, let needsDragon):
                        if !needsDragon || state.holdingDragon {
                            for _ in 0..<triggers { after = min(after + n, state.maxMana) }
                        }
                    case .gainTempMana(let n):
                        after += n
                    default:
                        break
                    }
                }
                if after == want { return c }
            }
        }
        return candidates.min { state.cost(of: $0, as: identity)
            < state.cost(of: $1, as: identity) }!
    }

    private func resolveTarget(_ token: RDToken, identity: RDCard,
                               state: RDState) throws -> RDTarget {
        let def = RDCards.def(identity)
        if def.targetScope == .none { return .none }
        if identity == .alexstrasza { return .enemyHero }

        func boardEntity(_ card: RDCard) -> Int? {
            return state.board.first { $0.card == card }?.entityId
        }
        if let t = token.target, let card = rdAbbreviations[t], t != "某随",
           t != "鱼之外某随" {
            guard let id = boardEntity(card) else {
                throw RDScriptError(message: "目标 \(t) 不在场")
            }
            return .friendlyMinion(id)
        }
        // 「某随」/「鱼之外某随」/没写目标：照 sim.py 取最后一个（优先非鲨鱼）
        switch identity {
        case .shadowcaster:
            return state.board.isEmpty ? .none : .unspecifiedFriendly
        case .shadowstep:
            let pool = state.board.filter { $0.card != .spiritOfTheShark }
            let pick = pool.last ?? state.board.last
            guard let id = pick?.entityId else {
                throw RDScriptError(message: "暗影步无目标")
            }
            return .friendlyMinion(id)
        case .freeSlotPlaceholder:
            for preferred in [RDCard.scabbsCutterbutter, .foxyFraud, .darkscaleBroodmother,
                              .etcBandManager, .shadowcaster] {
                if let id = boardEntity(preferred) { return .friendlyMinion(id) }
            }
            guard let id = state.board.last?.entityId else {
                throw RDScriptError(message: "腾格无目标")
            }
            return .friendlyMinion(id)
        default:
            guard let id = state.board.last?.entityId else {
                throw RDScriptError(message: "\(identity) 无目标")
            }
            return .friendlyMinion(id)
        }
    }

    /// 逐 token 重放。每步校验 manaAfter，最后校验总伤害。
    private func replay(_ row: RDRow, variant: Int = 0) -> RDReplayReport {
        guard var state = seedState(row) else {
            return RDReplayReport(id: row.id, ok: false, failure: "没有费用列，跳过")
        }
        var actions: [RDAction] = []
        let script = tokens(row, variant: variant)
        guard !script.isEmpty else {
            return RDReplayReport(id: row.id, ok: false, failure: "没有可重放的序列")
        }
        let rootSideboard = state.sideboard.count

        for (i, token) in script.enumerated() {
            guard var identity = rdAbbreviations[token.card] else {
                return RDReplayReport(id: row.id, ok: false,
                                      failure: "第 \(i) 步未知 token \(token.card)")
            }
            // 殒命暗影已经变形成最后一张施放的法术，按变形后的身份打，且必须打它本人
            var forcedEntity: Int?
            if identity == .shadowOfDemise {
                guard let mirror = state.hand.first(where: { $0.isShadowOfDemise }) else {
                    return RDReplayReport(id: row.id, ok: false,
                                          failure: "第 \(i) 步 殒：手里没有殒命暗影")
                }
                identity = mirror.card
                forcedEntity = mirror.entityId
                if let t = token.target, let expected = rdAbbreviations[t], expected != identity {
                    return RDReplayReport(id: row.id, ok: false,
                                          failure: "第 \(i) 步 殒 变形成了 \(identity)，表里写的是 \(t)")
                }
            }
            do {
                var working = state
                // 占位「杂」/「腾格」不在起手里，按表值反推印刷费后现场补一张
                if identity == .junkPlaceholder || identity == .freeSlotPlaceholder {
                    let disc = working.layers.filter {
                        RDDiscountLayer.filterCode($0.filter) == 0
                    }.reduce(0) { $0 + $1.amount }
                    let spend = token.manaAfter.map { working.availableMana - $0 } ?? 0
                    let eid = working.takeEntityId()
                    working.hand.append(RDHandCard(entityId: eid, card: identity,
                                                   printedCostOverride: max(0, spend + disc)))
                }
                let card: RDHandCard
                if let forced = forcedEntity, let idx = working.handIndex(ofEntity: forced) {
                    card = working.hand[idx]
                } else {
                    card = try pickHandCard(working, identity: identity,
                                            manaAfter: token.manaAfter)
                }
                let target = try resolveTarget(token, identity: identity, state: working)
                let action = RDAction.play(entityId: card.entityId, identity: identity,
                                           target: target, choices: [])
                let next = try RDEngine.apply(action, to: working, options: .replay)
                if let expected = token.manaAfter, next.availableMana != expected {
                    return RDReplayReport(id: row.id, ok: false,
                                          failure: "第 \(i) 步 \(token.card)"
                                              + " manaAfter 表=\(expected)"
                                              + " 实=\(next.availableMana)")
                }
                actions.append(action)
                state = next
            } catch let e as RDScriptError {
                return RDReplayReport(id: row.id, ok: false,
                                      failure: "第 \(i) 步 \(token.card)：\(e.message)")
            } catch let e as RDIllegal {
                return RDReplayReport(id: row.id, ok: false,
                                      failure: "第 \(i) 步 \(token.card) 非法：\(e)")
            } catch {
                return RDReplayReport(id: row.id, ok: false,
                                      failure: "第 \(i) 步 \(token.card)：\(error)")
            }
        }

        if let damage = row.damage, !row.hasNullPhase || !row.expandedLines.isEmpty,
           state.damageDealt != damage {
            return RDReplayReport(id: row.id, ok: false,
                                  failure: "伤害 表=\(damage) 实=\(state.damageDealt)")
        }
        let taken = rootSideboard - state.sideboard.count
        let comps = RDDifficulty.components(for: actions, sideboardCardsTaken: taken)
        return RDReplayReport(id: row.id, ok: true, failure: nil, group: row.group,
                              actions: actions, difficulty: comps.score,
                              sideboardTaken: taken, damage: state.damageDealt,
                              components: comps)
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
            checked += 1
        }
        XCTAssertEqual(checked, 23, "牌组是 20 主牌 + 3 边牌 = 23 种")

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

    // MARK: - 2. fixture 重放

    func testFixtureReplay() {
        XCTAssertEqual(RedDragonTests.rows.count, 75, "fixture 应有 75 行")
        var passed: [RDReplayReport] = []
        var failed: [RDReplayReport] = []
        var skipped: [String] = []

        for row in RedDragonTests.rows {
            guard row.cost != nil else {
                skipped.append("\(row.id)（没有费用列）")
                continue
            }
            if tokens(row, variant: 0).isEmpty {
                skipped.append("\(row.id)（没有可重放的序列）")
                continue
            }
            // 有 expandedLines 的行逐条试，任一条过即算过
            let variants = max(1, row.expandedLines.count)
            var best: RDReplayReport?
            for v in 0..<variants {
                let r = replay(row, variant: v)
                if r.ok { best = r; break }
                if best == nil { best = r }
            }
            guard let report = best else { continue }
            if report.ok { passed.append(report) } else { failed.append(report) }
        }

        print("== 公式表重放：通过 \(passed.count) / 失败 \(failed.count) / 跳过 \(skipped.count)")
        for s in skipped { print("   跳过 \(s)") }
        for f in failed {
            let note = rdExpectedReplayFailures[f.id]
            print("   失败 \(f.id)：\(f.failure ?? "?")"
                  + (note == nil ? "  ⚠️ 不在白名单" : "  [白名单] \(note!)"))
        }

        for f in failed {
            XCTAssertNotNil(rdExpectedReplayFailures[f.id],
                            "\(f.id) 重放失败但不在白名单里：\(f.failure ?? "?")")
        }
        for (id, reason) in rdExpectedReplayFailures.sorted(by: { $0.key < $1.key }) {
            if passed.contains(where: { $0.id == id }) {
                XCTFail("白名单行 \(id) 现在过了，该把它从白名单里删掉（原因：\(reason)）")
            }
        }
        XCTAssertGreaterThanOrEqual(passed.count, 45, "重放通过的行数明显变少了")

        // 难度分分布（v2：颠倒 / 缺件 / 插牌 / 操作 / 边牌）。
        // 整块一次 print —— 分行 print 在只跑单个用例时尾部会被 xcodebuild 吞掉。
        let scores = passed.map { $0.difficulty }.sorted()
        if !scores.isEmpty {
            func pct(_ p: Double) -> Double {
                return scores[max(0, min(scores.count - 1, Int(p * Double(scores.count))))]
            }
            func pad(_ s: String, _ n: Int) -> String {
                return s + String(repeating: " ", count: max(1, n - s.count))
            }
            var out = [String(format: "== 难度分 v2：min %.0f  p25 %.0f  中位 %.0f"
                              + "  p75 %.0f  max %.0f  (n=%d)",
                              scores.first!, pct(0.25), pct(0.5), pct(0.75), scores.last!,
                              scores.count)]
            for r in passed.sorted(by: { $0.difficulty < $1.difficulty }) {
                let c = r.components
                out.append("   " + pad(r.id, 13) + pad(r.group, 18)
                           + String(format: "难度 %5.1f  颠倒 %d  缺件 %d  插牌 %2d"
                                    + "  操作 %2d  边牌 %d  伤害 %3d  ",
                                    r.difficulty, c?.inversionPairs ?? 0,
                                    c?.missingTemplateCards ?? 0, c?.interleavedActions ?? 0,
                                    r.actions.count, r.sideboardTaken, r.damage)
                           + RDDifficulty.tier(r.difficulty).rawValue)
            }
            // 逐组落点
            var byGroup: [String: [Double]] = [:]
            for r in passed { byGroup[r.group, default: []].append(r.difficulty) }
            out.append("== 逐组落点")
            for (g, list) in byGroup.sorted(by: { $0.key < $1.key }) {
                let sorted = list.sorted()
                out.append("   " + pad(g, 20)
                           + String(format: "n=%2d  min %.0f  中位 %.0f  max %.0f",
                                    sorted.count, sorted.first!,
                                    sorted[sorted.count / 2], sorted.last!))
            }
            print(out.joined(separator: "\n"))
        }
        RedDragonTests.replayPassed = passed
    }

    private static var replayPassed: [RDReplayReport] = []

    // MARK: - 3. 搜索

    func testSearchReachesTableDamage() {
        var config = RedDragonConfig()
        // 测试跑的是 Debug（-Onone）宿主，同一份代码比 -O 慢约 12 倍
        // （scratchpad 基准：-O 全 48 行平均 0.29s / 最慢 0.62s，-Onone 平均 3.5s / 最慢 5.8s）。
        // 生产路径（T2）跑 Release，默认预算 1s 就够；这里放到 12s 只为让 Debug 也能跑完。
        config.cpuBudget = 12.0
        var times: [(String, Double, Int, Int, String, Int)] = []
        var failures: [String] = []
        var checked = 0

        for row in RedDragonTests.rows {
            guard let damage = row.damage, damage > 0, let root0 = seedState(row) else { continue }
            if rdExpectedReplayFailures[row.id] != nil { continue }
            if tokens(row, variant: 0).isEmpty { continue }
            var root = root0
            root.opponent = RDOpponent(health: damage)
            let result = RedDragonSearch.solve(root, config: config)
            checked += 1
            times.append((row.id, result.cpuTime, result.maxDamage,
                          result.statesExpanded, result.termination.rawValue,
                          result.depthReached))
            if result.maxDamage < damage {
                failures.append("\(row.id) 搜索 \(result.maxDamage) < 表 \(damage)"
                                + "（\(result.termination.rawValue)）")
            }
            // 返回的每条线都必须能重放
            if let chosen = result.chosenLine {
                XCTAssertNotNil(RDReplay.validate(chosen.actions, from: root,
                                                  expectedDamage: chosen.damage),
                                "\(row.id) chosenLine 重放失败")
            }
            for line in result.lethalLines {
                XCTAssertNotNil(RDReplay.validate(line.actions, from: root,
                                                  expectedDamage: line.damage),
                                "\(row.id) lethalLine 重放失败")
            }
        }

        let sorted = times.sorted { $0.1 > $1.1 }
        print("== 搜索：\(checked) 行，CPU 时间前十")
        for t in sorted.prefix(12) {
            print(String(format: "   %-14s %.3fs  伤害 %3d  状态 %7d  深度 %2d  %@",
                         (t.0 as NSString).utf8String!, t.1, t.2, t.3, t.5, t.4))
        }
        let total = times.reduce(0.0) { $0 + $1.1 }
        print(String(format: "   合计 %.2fs 平均 %.3fs 超 1s 的行 %d",
                     total, total / Double(max(1, times.count)),
                     times.filter { $0.1 > 1.0 }.count))
        for f in failures { print("   ⚠️ \(f)") }
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "; "))
    }

    // MARK: - 4. 确定性

    func testDeterminism() {
        guard let row = RedDragonTests.rows.first(where: { $0.id == "t1-32-01" }),
              var root = seedState(row) else {
            XCTFail("t1-32-01 缺失")
            return
        }
        root.opponent = RDOpponent(health: 32)
        // CPU 预算截断的位置取决于机器负载，确定性要靠可复现的闸门：这里用状态数上限，
        // 并把预算放得足够大，保证两次都是被同一个闸门在同一个位置截断。
        var config = RedDragonConfig()
        config.cpuBudget = 600
        config.maxStatesExpanded = 20_000
        let a = RedDragonSearch.solve(root, config: config)
        let b = RedDragonSearch.solve(root, config: config)
        XCTAssertEqual(a.statesExpanded, b.statesExpanded)
        XCTAssertEqual(a.depthReached, b.depthReached)
        XCTAssertEqual(a.maxDamage, b.maxDamage)
        XCTAssertEqual(a.isLethal, b.isLethal)
        XCTAssertEqual(a.termination, b.termination)
        XCTAssertEqual(a.lethalLines.count, b.lethalLines.count)
        for (x, y) in zip(a.lethalLines, b.lethalLines) {
            XCTAssertEqual(x.damage, y.damage)
            XCTAssertEqual(x.difficulty, y.difficulty)
            XCTAssertEqual(x.actions, y.actions)
        }
        XCTAssertEqual(a.chosenLine?.actions, b.chosenLine?.actions)
        XCTAssertEqual(a.missingPieces, b.missingPieces)
    }

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
            if case .play(let eid, _, _, _) = action {
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
            guard case .play(_, let identity, let target, _) = action,
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
}
