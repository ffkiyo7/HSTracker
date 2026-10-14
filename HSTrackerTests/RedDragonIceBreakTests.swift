//
//  RedDragonIceBreakTests.swift
//  HSTrackerTests
//
//  T8 破冰模式 · 阶段 A（引擎和搜索）：寒冰屏障的规则、下回合起手的费用、构造局面上的三种结论、
//  跟手和公式吃同一条规则，以及把现有 fixture 的每个我方回合都当成「对方有冰」跑一遍的扫表（打印 `T8SURVEY`）。
//

import XCTest
@testable import HSTracker
@testable import RedDragonCore

class RedDragonIceBreakTests: HSTrackerTests {

    override class func setUp() {
        super.setUp()
        if Cards.by(cardId: CardIds.Collectible.Rogue.Shadowstep) == nil {
            Database().loadDatabase(splashscreen: nil, withLanguages: [.enUS])
        }
    }

    // MARK: - 手工局面

    /// 对方 `enemy` 血、挂着 `secrets` 个奥秘。乐队清空：手工局面里没有 E.T.C.，边牌够不着
    private func root(mana: Int, maxMana: Int = 10, enemy: Int, armor: Int = 0, secrets: Int = 1,
                      immune: Bool = false) -> RDState {
        var s = RDState(maxMana: maxMana, mana: mana,
                        opponent: RDOpponent(health: enemy, armor: armor, immune: immune, secretCount: secrets))
        s.sideboard = []
        return s
    }

    @discardableResult
    private func minion(_ s: inout RDState, _ c: RDCard, canAttack: Bool = false) -> Int {
        let d = RDCards.def(c)
        let id = s.takeEntityId()
        s.board.append(RDBoardMinion(entityId: id, card: c, attack: d.attack, health: d.health,
                                     maxHealth: d.health, statsSetTo1x1: false, silenced: false,
                                     summoningSick: !canAttack, attacksThisTurn: 0, enchants: [],
                                     playOrder: s.takePlayOrder()))
        return id
    }

    /// `cost`：费用被设成这个数（永久的，像复制体的 1 费）；`copy`：1/1 复制体
    @discardableResult
    private func card(_ s: inout RDState, _ c: RDCard, cost: Int? = nil, copy: Bool = false) -> Int {
        let id = s.takeEntityId()
        s.hand.append(RDHandCard(entityId: id, card: c, enchants: cost.map { [.set($0)] } ?? [],
                                 statsOverride: copy ? RDStats(attack: 1, health: 1) : nil,
                                 isShadowOfDemise: c == .shadowOfDemise))
        return id
    }

    private func play(_ id: Int, _ c: RDCard, _ target: RDTarget = .none) -> RDAction {
        return .play(entityId: id, identity: c, target: target, choices: [])
    }

    /// 闸门只留状态数（可复现），CPU 兜底全部放开
    static func detConfig() -> RedDragonConfig {
        var c = RedDragonLiveReplayTests.deterministic
        c.iceBreak.cpuBudget = 1e9
        c.iceBreak.probeCpuBudget = 1e9
        return c
    }

    private func solve(_ s: RDState) -> RDIceBreakResult {
        return RedDragonSearch.solveIceBreak(s, config: Self.detConfig())
    }

    private func hasRandomDraw(_ actions: [RDAction]) -> Bool {
        return actions.contains { a in
            a.choices.contains { c in
                if case .pick(let card) = c { return !RDCards.sideboardCards.contains(card) }
                return false
            }
        }
    }

    /// 结论自洽：给出去的线都是引擎重放得出来的
    private func assertBacked(_ r: RDIceBreakResult, file: StaticString = #filePath, line: UInt = #line) {
        guard r.verdict == .lethalNextTurn || r.verdict == .shortNextTurn else {
            XCTAssertNil(r.line, "破不了冰 / 不适用时不给线", file: file, line: line)
            return
        }
        guard let now = r.line, let next = r.nextTurnRoot else {
            return XCTFail("能破冰就要有本回合的线和下回合起手", file: file, line: line)
        }
        XCTAssertFalse(hasRandomDraw(now.actions), "本回合的线不靠随机抽牌", file: file, line: line)
        guard let end = try? RDReplay.run(now.actions, from: r.root).finalState else {
            return XCTFail("本回合的线在标好冰的根局面上重放不过", file: file, line: line)
        }
        XCTAssertEqual(end.opponent.ice, .broken, "终局冰已打掉", file: file, line: line)
        XCTAssertTrue(end.opponent.immune, file: file, line: line)
        XCTAssertEqual(end.opponent.effectiveHealth, r.remaining, file: file, line: line)
        XCTAssertEqual(RDIceBreak.nextTurn(end).canonicalHash(), next.canonicalHash(), file: file, line: line)
        XCTAssertEqual(next.opponent.effectiveHealth, r.remaining, "下回合对方就是剩余血量", file: file, line: line)
        XCTAssertFalse(next.opponent.immune, file: file, line: line)
        XCTAssertNil(next.opponent.ice, "下回合回到平常规则", file: file, line: line)
        if let nl = r.nextTurnLine {
            XCTAssertFalse(hasRandomDraw(nl.actions), "下回合的线不靠随机抽牌", file: file, line: line)
            let ev = RDIceBreak.evidence(nl, on: next)
            XCTAssertEqual(ev?.damage, r.nextTurnDamage, "下回合伤害是那条线重放出来的", file: file, line: line)
            XCTAssertEqual(ev?.lethalSteps, r.nextTurnLethalSteps, file: file, line: line)
        } else {
            XCTAssertEqual(r.nextTurnDamage, 0, file: file, line: line)
        }
        if r.verdict == .lethalNextTurn {
            XCTAssertNotNil(r.nextTurnLethalSteps, "说可斩就得有打死对方的下回合线", file: file, line: line)
            XCTAssertGreaterThanOrEqual(r.nextTurnDamage, r.remaining, file: file, line: line)
            XCTAssertEqual(r.shortBy, 0, file: file, line: line)
        } else {
            XCTAssertNil(r.nextTurnLethalSteps, file: file, line: line)
            XCTAssertEqual(r.shortBy, r.remaining - r.nextTurnDamage, file: file, line: line)
            XCTAssertGreaterThan(r.shortBy, 0, file: file, line: line)
        }
    }

    // MARK: - 规则（口径 1）

    /// 致命的那一下整个不生效：血量、护甲停在这一下之前，对方免疫，奥秘少一个
    func testFatalHitIsNegated() throws {
        var s = root(mana: 9, enemy: 5, armor: 2)
        let alex = card(&s, .alexstrasza)
        let armed = try XCTUnwrap(RDIceBreak.armed(s))
        XCTAssertEqual(armed.opponent.ice, .armed)
        let out = try RDEngine.apply(play(alex, .alexstrasza, .enemyHero), to: armed)
        XCTAssertEqual(out.opponent.health, 5)
        XCTAssertEqual(out.opponent.armor, 2, "护甲也不掉")
        XCTAssertTrue(out.opponent.immune)
        XCTAssertEqual(out.opponent.secretCount, 0)
        XCTAssertEqual(out.opponent.ice, .broken)
        XCTAssertEqual(out.damageDealt, 0, "这一下没有造成伤害")

        // 刚好等于血 + 甲也算致命
        var t = root(mana: 9, enemy: 6, armor: 2)
        let a2 = card(&t, .alexstrasza)
        let exact = try RDEngine.apply(play(a2, .alexstrasza, .enemyHero), to: try XCTUnwrap(RDIceBreak.armed(t)))
        XCTAssertEqual(exact.opponent.ice, .broken)
        XCTAssertEqual(exact.opponent.effectiveHealth, 8)
    }

    /// 之前的伤害照常：不致命的一下正常扣（先扣甲），冰还在
    func testNonFatalHitGoesThrough() throws {
        var s = root(mana: 9, enemy: 10, armor: 3)
        let alex = card(&s, .alexstrasza)
        let out = try RDEngine.apply(play(alex, .alexstrasza, .enemyHero), to: try XCTUnwrap(RDIceBreak.armed(s)))
        XCTAssertEqual(out.opponent.armor, 0)
        XCTAssertEqual(out.opponent.health, 5)
        XCTAssertEqual(out.opponent.ice, .armed)
        XCTAssertFalse(out.opponent.immune)
        XCTAssertEqual(out.opponent.secretCount, 1)
        XCTAssertEqual(out.damageDealt, 8)
    }

    /// 鲨鱼下阿莱的两次 8 分开判：前一次不致命照常扣，后一次致命才触发；触发之后同一张牌剩下的伤害也没了
    func testTwoHitsUnderSharkAreJudgedSeparately() throws {
        func after(_ enemy: Int) throws -> RDState {
            var s = root(mana: 9, enemy: enemy)
            minion(&s, .spiritOfTheShark)
            let alex = card(&s, .alexstrasza)
            return try RDEngine.apply(play(alex, .alexstrasza, .enemyHero), to: try XCTUnwrap(RDIceBreak.armed(s)))
        }
        var out = try after(12)
        XCTAssertEqual(out.opponent.health, 4, "第一次 8 照常，第二次 8 ≥ 4 被挡")
        XCTAssertEqual(out.opponent.ice, .broken)
        XCTAssertEqual(out.damageDealt, 8)

        out = try after(16)
        XCTAssertEqual(out.opponent.health, 8, "第二次 8 刚好致命，被挡，剩 8")
        XCTAssertEqual(out.opponent.ice, .broken)

        out = try after(20)
        XCTAssertEqual(out.opponent.health, 4, "两次都不致命")
        XCTAssertEqual(out.opponent.ice, .armed)
        XCTAssertEqual(out.damageDealt, 16)

        out = try after(8)
        XCTAssertEqual(out.opponent.health, 8, "第一次就致命：被挡；第二次打在免疫上")
        XCTAssertEqual(out.opponent.secretCount, 0, "只触发一次")
        XCTAssertEqual(out.damageDealt, 0)
    }

    /// 随从 / 英雄的攻击致命时一样被挡
    func testFatalAttackIsNegated() throws {
        var s = root(mana: 0, enemy: 3)
        let knife = minion(&s, .scabbsCutterbutter, canAttack: true)
        let out = try RDEngine.apply(.attack(attacker: .friendlyMinion(knife), defender: .enemyHero),
                                     to: try XCTUnwrap(RDIceBreak.armed(s)))
        XCTAssertEqual(out.opponent.health, 3)
        XCTAssertEqual(out.opponent.ice, .broken)
        XCTAssertEqual(out.board[0].attacksThisTurn, 1, "攻击还是用掉了")
    }

    /// 冰打掉之后对方英雄免疫：不能攻击、指不到；阿莱要下场只能指别的（我方英雄 / 敌方随从）
    func testBrokenHeroCannotBeTargeted() throws {
        var s = root(mana: 10, enemy: 3)
        let knife = minion(&s, .scabbsCutterbutter, canAttack: true)
        let fox = minion(&s, .foxyFraud, canAttack: true)
        let alex = card(&s, .alexstrasza, cost: 1)
        s.opponent.board = [RDEnemyMinion(entityId: 900, attack: 1, health: 1, taunt: false, divineShield: false,
                                          immune: false, stealth: false)]
        let broken = try RDEngine.apply(.attack(attacker: .friendlyMinion(knife), defender: .enemyHero),
                                        to: try XCTUnwrap(RDIceBreak.armed(s)))
        XCTAssertThrowsError(try RDEngine.apply(.attack(attacker: .friendlyMinion(fox), defender: .enemyHero),
                                                to: broken))
        XCTAssertThrowsError(try RDEngine.apply(play(alex, .alexstrasza, .enemyHero), to: broken))
        var dropped = false
        let actions = RDEngine.legalActions(broken, options: .search, dropped: &dropped)
        var alexTargets: [RDTarget] = []
        for a in actions {
            switch a {
            case .play(_, .alexstrasza, let t, _, _): alexTargets.append(t)
            case .attack(_, let d, _): XCTAssertNotEqual(d, .enemyHero, "免疫的英雄不能攻击")
            default: break
            }
        }
        XCTAssertFalse(alexTargets.contains(.enemyHero))
        XCTAssertTrue(alexTargets.contains(.friendlyHero), "对方英雄指不到时阿莱可以奶自己下场")
        XCTAssertTrue(alexTargets.contains(.enemyMinion(900)))
        let healed = try RDEngine.apply(play(alex, .alexstrasza, .friendlyHero), to: broken)
        XCTAssertEqual(healed.opponent.health, 3)
        XCTAssertEqual(healed.board.count, 3)
    }

    /// 不在破冰模式：对方挂着奥秘、甚至免疫，规则和以前逐字相同（免疫的英雄指得到、打不动；奥秘不触发）
    func testRulesAreUnchangedWhenIceModeIsOff() throws {
        var s = root(mana: 9, enemy: 5)
        let alex = card(&s, .alexstrasza)
        let out = try RDEngine.apply(play(alex, .alexstrasza, .enemyHero), to: s)
        XCTAssertEqual(out.opponent.health, -3, "没标冰：照常打死")
        XCTAssertEqual(out.opponent.secretCount, 1)
        XCTAssertFalse(out.opponent.immune)
        XCTAssertNil(out.opponent.ice)

        var t = root(mana: 9, enemy: 5, secrets: 0, immune: true)
        let a2 = card(&t, .alexstrasza)
        var dropped = false
        let targets = RDEngine.legalActions(t, options: .search, dropped: &dropped).compactMap { a -> RDTarget? in
            if case .play(_, .alexstrasza, let x, _, _) = a { return x }
            return nil
        }
        XCTAssertEqual(targets, [.enemyHero], "原来的口径：免疫的英雄照样列为目标，也不多出奶自己的目标")
        let hit = try RDEngine.apply(play(a2, .alexstrasza, .enemyHero), to: t)
        XCTAssertEqual(hit.opponent.health, 5)
    }

    /// 哈希：没标冰时和以前一样（新字段都不喂）；标了冰，冰在 / 已破、费用是不是只在本回合有效都要分得开
    func testHashOnlyChangesInIceMode() {
        var s = root(mana: 5, enemy: 20)
        card(&s, .scabbsCutterbutter, cost: 1)
        let plain = s.canonicalHash()
        var flagged = s
        flagged.hand[0].costThisTurnOnly = true
        XCTAssertEqual(flagged.canonicalHash(), plain, "不在破冰模式：本回合费用标记不进哈希")

        var armed = s
        armed.opponent.ice = .armed
        var broken = s
        broken.opponent.ice = .broken
        XCTAssertNotEqual(armed.canonicalHash(), plain)
        XCTAssertNotEqual(broken.canonicalHash(), plain)
        XCTAssertNotEqual(armed.canonicalHash(), broken.canonicalHash())
        var armedFlagged = armed
        armedFlagged.hand[0].costThisTurnOnly = true
        XCTAssertNotEqual(armedFlagged.canonicalHash(), armed.canonicalHash(),
                          "破冰模式：同是 1 费，舞动给的和永久的不是一个局面")
    }

    func testArming() {
        XCTAssertNil(RDIceBreak.armed(root(mana: 1, enemy: 10, secrets: 0)), "没奥秘也没免疫：不适用")
        XCTAssertEqual(RDIceBreak.armed(root(mana: 1, enemy: 10, secrets: 2))?.opponent.ice, .armed)
        XCTAssertEqual(RDIceBreak.armed(root(mana: 1, enemy: 10, secrets: 0, immune: true))?.opponent.ice, .broken)
        XCTAssertEqual(RedDragonSearch.solveIceBreak(root(mana: 1, enemy: 10, secrets: 0)).verdict, .notApplicable)
    }

    // MARK: - 下回合起手的费用和资源

    /// 只在本回合有效的不带到下回合：舞动的 1 费、快枪、临时水晶、减费层、冻结。永久的留着：暗影步 −2、复制体 1 费
    func testNextTurnDropsThisTurnOnlyCosts() throws {
        var s = root(mana: 5, enemy: 30)
        minion(&s, .scabbsCutterbutter)
        minion(&s, .darkscaleBroodmother)
        let dance = card(&s, .bounceAround)
        card(&s, .alexstrasza, cost: 1, copy: true)
        var t = try RDEngine.apply(play(dance, .bounceAround), to: s)
        func cost(_ x: RDState, _ c: RDCard) -> Int? {
            return x.hand.first { $0.card == c }.map { x.cost(of: $0, as: c) }
        }
        XCTAssertEqual(cost(t, .scabbsCutterbutter), 1)
        XCTAssertEqual(cost(t, .darkscaleBroodmother), 1)
        XCTAssertTrue(t.hand.first { $0.card == .scabbsCutterbutter }?.costThisTurnOnly ?? false)
        t.tempMana = 1
        t.layers = [RDDiscountLayer(amount: 2, slots: 1, filter: .any)]
        t.heroFrozen = true
        var n = RDSetup.nextTurn(t)
        XCTAssertEqual(cost(n, .scabbsCutterbutter), 4, "舞动的 1 费回合结束就没了")
        XCTAssertEqual(cost(n, .darkscaleBroodmother), 3)
        XCTAssertEqual(cost(n, .alexstrasza), 1, "复制体的 1 费是永久的")
        XCTAssertFalse(n.hand.contains { $0.costThisTurnOnly })
        XCTAssertEqual(n.tempMana, 0)
        XCTAssertTrue(n.layers.isEmpty)
        XCTAssertFalse(n.heroFrozen)
        XCTAssertEqual(n.mana, 10)

        // 舞动回手 → 1 费打出 → 暗影步弹回：4 − 2 = 2，是永久的
        var u = root(mana: 5, enemy: 30)
        minion(&u, .scabbsCutterbutter)
        let d2 = card(&u, .bounceAround)
        let step = card(&u, .shadowstep)
        u = try RDEngine.apply(play(d2, .bounceAround), to: u)
        let knife = try XCTUnwrap(u.hand.first { $0.card == .scabbsCutterbutter })
        u = try RDEngine.apply(play(knife.entityId, .scabbsCutterbutter), to: u)
        u = try RDEngine.apply(play(step, .shadowstep, .friendlyMinion(u.board[0].entityId)), to: u)
        // 本回合还压着刀油自己的减费层（连击，−2 还剩一张）：2 − 2 = 0；层是本回合的，底费 2 是永久的
        XCTAssertEqual(cost(u, .scabbsCutterbutter), 0)
        XCTAssertEqual(u.hand.first { $0.card == .scabbsCutterbutter }.map { u.effectiveBaseCost($0, as: $0.card) }, 2)
        n = RDSetup.nextTurn(u)
        XCTAssertEqual(cost(n, .scabbsCutterbutter), 2, "暗影步的 −2 带到下回合，减费层不带")

        // 快枪：本回合进手 1 费，下回合回到印刷费
        var q = root(mana: 5, enemy: 30)
        q.hand.append(RDHandCard(entityId: q.takeEntityId(), card: .dehydrate, enteredHandThisTurn: true))
        XCTAssertEqual(cost(q, .dehydrate), 1)
        XCTAssertEqual(cost(RDSetup.nextTurn(q), .dehydrate), 3)
    }

    /// 读取层：手牌上挂着舞动的附魔（`ETC_079e`）才标「只在本回合有效」，复制体的 1 费不标
    func testReaderFlagsBounceAroundCost() {
        func hand(_ enchantments: [String]) -> RDGameSnapshot.HandCard {
            return RDGameSnapshot.HandCard(entityId: 5, cardId: "BAR_552", cost: 1, zonePosition: 1, attack: 3,
                                           health: 3, isCoin: false, enchantments: enchantments)
        }
        XCTAssertTrue(RDStateReader.handCard(hand(["ETC_079e"]), layers: []).0.costThisTurnOnly)
        XCTAssertFalse(RDStateReader.handCard(hand(["SCH_352e", "SCH_352e2"]), layers: []).0.costThisTurnOnly)
        XCTAssertFalse(RDStateReader.handCard(hand([]), layers: []).0.costThisTurnOnly)
    }

    /// 实录对照（任务书「现状」里怀疑的那条）：10-05 第 7 局 T13 舞动弹回手、回合结束时还留在手里的三张牌。
    /// 回合结束（MAIN_CLEANUP）时舞动的附魔自己移除、费用回到印刷费，这时解析器还算我方回合，所以这一局的边界里
    /// 既有「附魔还在」的最后一个局面，也有「附魔刚没」的局面：前者折成下回合起手算出来的费用，要等于后者日志里的真实费用
    func testNextTurnCostsMatchTheLogAfterBounceAround() {
        let bs = RedDragonSetupTests.boundaries(lines: RedDragonFeedbackTests.lines("2026-10-05-g7-rewind"),
                                                playerId: 2)
        var checked: [String] = []
        // 每张牌各自跟：附魔还在的最后一个边界（三个附魔是一个一个移除的，中间各有一个边界）→ 紧接着附魔没了的那个边界。
        // 中途离开过手牌的（打出去了）不比
        var lastWith: [Int: RedDragonFeedbackTests.Boundary] = [:]
        for b in bs {
            for id in lastWith.keys where !b.snapshot.hand.contains(where: { $0.entityId == id }) {
                lastWith[id] = nil
            }
            for real in b.snapshot.hand {
                if real.enchantments.contains("ETC_079e") {
                    lastWith[real.entityId] = b
                    continue
                }
                guard let last = lastWith.removeValue(forKey: real.entityId),
                      let h = last.snapshot.hand.first(where: { $0.entityId == real.entityId }) else { continue }
                let predicted = RDSetup.nextTurn(RDStateReader.read(last.snapshot).state)
                guard let p = predicted.hand.first(where: { $0.entityId == real.entityId }) else { continue }
                XCTAssertEqual(h.cost, 1, "舞动弹回的牌本回合 1 费")
                XCTAssertEqual(predicted.cost(of: p, as: p.card), real.cost, "#\(h.entityId) \(h.cardId)")
                checked.append("T\(last.snapshot.turn) 行\(last.line)→行\(b.line) #\(h.entityId) "
                    + "\(RedDragonLiveReplayTests.short(h.cardId))：附魔在时 \(h.cost) 费，附魔没了日志 \(real.cost) 费，"
                    + "折算 \(predicted.cost(of: p, as: p.card)) 费")
            }
        }
        print("T8COST\n" + checked.joined(separator: "\n"))
        XCTAssertGreaterThanOrEqual(checked.count, 3, "T13 结束时有三张舞动弹回的牌留在手里（E.T.C.、晦鳞巢母、刀油）")
    }

    // MARK: - 构造局面（口径 2–5）

    /// 对方 16 血。3 水晶 + 2 临时水晶，鲨鱼在场，手里 1 费阿莱（复制体）+ 幻觉药水
    private func breakAndLethalRoot() -> (state: RDState, alex: Int, potion: Int) {
        var s = root(mana: 3, maxMana: 3, enemy: 16)
        s.tempMana = 2
        minion(&s, .spiritOfTheShark)
        let alex = card(&s, .alexstrasza, cost: 1, copy: true)
        let potion = card(&s, .potionOfIllusion)
        return (s, alex, potion)
    }

    /// ① 能破冰、下回合可斩，破冰之后的准备步算在线里（口径 2）：阿莱打脸（第二个 8 破冰，剩 8）→ 喝药水
    /// （鲨鱼、阿莱各一张 1 费复制体进手），下回合 4 费下 1 费阿莱 16 ≥ 8。
    /// 只破冰不喝药水：临时水晶下回合没了，4 费只够喝药水、下不了阿莱，斩不了 —— 所以最优是两步的那条
    func testBreakThenLethalNextTurn() throws {
        let (s, alexId, potionId) = breakAndLethalRoot()
        let r = solve(s)
        XCTAssertEqual(r.verdict, .lethalNextTurn)
        assertBacked(r)
        XCTAssertEqual(try XCTUnwrap(r.line).actions,
                       [play(alexId, .alexstrasza, .enemyHero), play(potionId, .potionOfIllusion)])
        XCTAssertEqual(r.breakStep, 1)
        XCTAssertEqual(r.remaining, 8)
        XCTAssertFalse(r.alreadyBroken)
        XCTAssertGreaterThanOrEqual(r.nextTurnDamage, 16)
        // 下回合起手：4 费、没有临时水晶；阿莱的 1 费复制体在手（永久的 1 费）；留场的随从不算攻击
        let next = try XCTUnwrap(r.nextTurnRoot)
        XCTAssertEqual(next.availableMana, 4)
        let alex = try XCTUnwrap(next.hand.first { $0.card == .alexstrasza })
        XCTAssertEqual(next.cost(of: alex, as: .alexstrasza), 1)
        XCTAssertTrue(next.board.allSatisfy { $0.summoningSick })
        // 只破冰的那条也探过，下回合不够
        let bare = try XCTUnwrap(r.candidates.first { $0.steps == 1 })
        XCTAssertLessThan(bare.margin, 0)
    }

    /// 全押卡格子：对方 3 血。场上 6 个随从（鲨鱼、能攻击的刀油、4 个不能动的），只剩 1 格；手里两张 1 费阿莱、1 费。
    /// 全押 = 现在就下一张阿莱破冰 → 场满，下回合手里那张阿莱下不来，斩不了；
    /// 克制 = 刀油攻脸破冰（3 ≥ 3），两张阿莱都留着 → 下回合那 1 格下阿莱，16 ≥ 3。搜索要给克制的那条
    func testRestrainedLineBeatsAllInThatClogsTheBoard() throws {
        var s = root(mana: 1, maxMana: 9, enemy: 3)
        minion(&s, .spiritOfTheShark)
        let knife = minion(&s, .scabbsCutterbutter, canAttack: true)
        for _ in 0..<4 { minion(&s, .foxyFraud) }
        card(&s, .alexstrasza, cost: 1, copy: true)
        card(&s, .alexstrasza, cost: 1, copy: true)
        let r = solve(s)
        XCTAssertEqual(r.verdict, .lethalNextTurn)
        assertBacked(r)
        let line = try XCTUnwrap(r.line)
        XCTAssertEqual(line.actions, [.attack(attacker: .friendlyMinion(knife), defender: .enemyHero)],
                       "克制的那条：刀油攻脸破冰，阿莱留在手里")
        XCTAssertEqual(r.remaining, 3)
        XCTAssertEqual(try XCTUnwrap(r.nextTurnRoot).boardSlotsFree, 1)

        // 全押的那条也在候选里、也真能破冰，只是下回合场满下不了阿莱
        let allIn = try XCTUnwrap(r.candidates.first { c in
            if case .play(_, .alexstrasza, .enemyHero, _, _)? = c.line.actions.first { return c.steps == 1 }
            return false
        }, "全押的破法应该被搜到并比较过")
        XCTAssertEqual(allIn.nextTurnRoot.boardSlotsFree, 0)
        XCTAssertTrue(allIn.nextTurnRoot.hand.contains { $0.card == .alexstrasza }, "手里还有阿莱，但没格子")
        XCTAssertLessThan(allIn.margin, 0, "全押：下回合斩不了")

        // 同一个局面不开破冰模式：照常是斩杀（搜索不知道有冰）
        XCTAssertTrue(RedDragonSearch.solve(s, config: RedDragonLiveReplayTests.deterministic).isLethal)
    }

    /// ③ 破不了冰：不给线
    func testCannotBreak() {
        var s = root(mana: 2, enemy: 30)
        card(&s, .foxyFraud)
        let r = solve(s)
        XCTAssertEqual(r.verdict, .cannotBreak)
        XCTAssertNil(r.line)
        XCTAssertNil(r.nextTurnLine)
        XCTAssertTrue(r.exhaustive, "小局面穷举完了：按本模型确实破不了")
        assertBacked(r)
    }

    /// ② 能破冰、下回合差一点：阿莱打脸破冰剩 8，手里没东西了，下回合只有英雄技能的 1 点 → 差 7，线照给
    func testBreakButShortNextTurn() throws {
        var s = root(mana: 9, maxMana: 9, enemy: 16)
        minion(&s, .spiritOfTheShark)
        card(&s, .alexstrasza)
        let r = solve(s)
        XCTAssertEqual(r.verdict, .shortNextTurn)
        assertBacked(r)
        XCTAssertEqual(try XCTUnwrap(r.line).actions.count, 1)
        XCTAssertEqual(r.remaining, 8)
        XCTAssertEqual(r.nextTurnDamage, 1, "留场的阿莱不算攻击，只剩匕首的 1 点")
        XCTAssertEqual(r.shortBy, 7)
    }

    /// 根局面进来对方已经免疫（冰已打掉）：只算准备步。3 水晶 + 1 临时水晶，场上鲨鱼 + 阿莱，手里幻觉药水：
    /// 现在喝药水（复制体 1 费）→ 下回合 4 费下 1 费阿莱，16 ≥ 8；不喝的话下回合 4 费只够喝药水，斩不了
    func testAlreadyBrokenRootOnlyPrepares() throws {
        var s = root(mana: 3, maxMana: 3, enemy: 8, secrets: 0, immune: true)
        s.tempMana = 1
        minion(&s, .spiritOfTheShark)
        minion(&s, .alexstrasza)
        let potion = card(&s, .potionOfIllusion)
        let r = solve(s)
        XCTAssertEqual(r.verdict, .lethalNextTurn)
        assertBacked(r)
        XCTAssertTrue(r.alreadyBroken)
        XCTAssertEqual(r.breakStep, 0)
        XCTAssertEqual(r.remaining, 8)
        XCTAssertEqual(try XCTUnwrap(r.line).actions, [play(potion, .potionOfIllusion)])
        let next = try XCTUnwrap(r.nextTurnRoot)
        XCTAssertEqual(next.mana, 4)
        XCTAssertEqual(next.tempMana, 0, "临时水晶不带到下回合")
        // 「什么都不打」也比较过，下回合不够
        let idle = try XCTUnwrap(r.candidates.first { $0.steps == 0 })
        XCTAssertLessThan(idle.margin, 0)
    }

    /// 进来已经免疫、本回合什么都打不了：结论照给，线是 0 步
    func testAlreadyBrokenRootWithNothingToDo() throws {
        var s = root(mana: 0, maxMana: 9, enemy: 8, secrets: 0, immune: true)
        minion(&s, .spiritOfTheShark)
        card(&s, .alexstrasza)
        let r = solve(s)
        XCTAssertEqual(r.verdict, .lethalNextTurn)
        assertBacked(r)
        XCTAssertTrue(r.alreadyBroken)
        XCTAssertEqual(try XCTUnwrap(r.line).actions.count, 0)
        XCTAssertEqual(r.nextTurnDamage, 16)
    }

    /// 只给不靠随机抽牌的破法（对方 3 血，行骗抽一张法术）：牌库里两种法术、抽到袋底藏沙才破得了 → 不算；
    /// 牌库的法术只剩袋底藏沙（必抽到，引擎不出 pick）→ 算
    func testBreakLineNeverDependsOnRandomDraws() throws {
        func position(deck: [(RDCard, Int)]) -> RDState {
            var s = root(mana: 4, enemy: 3)
            card(&s, .swindle)
            s.deck = RDDeck(deck)
            return s
        }
        let random = position(deck: [(.pocketSand, 1), (.preparation, 1)])
        XCTAssertEqual(solve(random).verdict, .cannotBreak)
        XCTAssertTrue(RedDragonSearch.solve(random, config: RedDragonLiveReplayTests.deterministic).isLethal,
                      "平常的斩杀搜索会报「抽到才斩」，破冰不收这种")

        let forced = solve(position(deck: [(.pocketSand, 1), (.foxyFraud, 2)]))
        XCTAssertEqual(forced.verdict, .shortNextTurn)
        assertBacked(forced)
        XCTAssertEqual(try XCTUnwrap(forced.line).actions.count, 2)
        XCTAssertEqual(forced.remaining, 3)
    }

    /// 阶段 A 复核 1：「发生了抽牌」不等于「靠抽到的牌」。对方 1 血挂冰，我方 0 费、装着能攻击的疾速矿锄（攻击后抽一张），
    /// 牌库剩硬币和暗影步 —— 攻击的伤害在抽牌之前，抽到哪张冰都碎。原来带随机抽牌的动作整支丢掉，报成破不了、还说穷举了
    func testDrawThatHappensIsNotADrawThatIsReliedOn() throws {
        func position(enemy: Int, deck: [(RDCard, Int)]) -> RDState {
            var s = root(mana: 0, enemy: enemy)
            s.weapon = RDWeapon(attack: 1, durability: 2, drawOnHeroAttack: true)
            s.deck = RDDeck(deck)
            return s
        }
        let swing = RDAction.attack(attacker: .friendlyHero, defender: .enemyHero, choices: [.blind])
        let r = solve(position(enemy: 1, deck: [(.coin, 1), (.shadowstep, 1)]))
        assertBacked(r)
        XCTAssertEqual(try XCTUnwrap(r.line).actions, [swing], "攻击那一下破冰，抽牌照常发生（盲抽）")
        XCTAssertEqual(r.breakStep, 1)
        XCTAssertEqual(r.remaining, 1)
        // 抽牌的副作用照实算：牌库少一张（不知道是哪张）、手里多一张打不出去的牌
        let end = try RDReplay.run([swing], from: r.root).finalState
        XCTAssertEqual(end.deck.total, 1)
        XCTAssertEqual(end.deck.unknownGone, 1)
        XCTAssertEqual(end.hand.count, 1)
        XCTAssertTrue(end.hand[0].blindDraw)
        XCTAssertEqual(end.hand[0].card, .junkPlaceholder)
        XCTAssertFalse(RDEngine.legalActions(end).contains { if case .play = $0 { return true }; return false },
                       "抽到的那张本回合不能用")
        // 下回合：矿锄还剩 1 点耐久，再攻击一次 1 ≥ 1（探针原来也漏掉这 1 点）。抽到的牌下回合照样不算资源
        XCTAssertEqual(r.verdict, .lethalNextTurn)
        XCTAssertEqual(r.nextTurnDamage, 1)
        XCTAssertEqual(try XCTUnwrap(r.nextTurnLine).actions.first, swing)
        let next = try XCTUnwrap(r.nextTurnRoot)
        XCTAssertTrue(next.hand.allSatisfy { $0.card == .junkPlaceholder })
        // 手牌满：抽到的被烧，牌库照样少一张
        var full = r.root
        for _ in 0..<full.handLimit { card(&full, .foxyFraud) }
        let burned = try RDEngine.apply(swing, to: full)
        XCTAssertEqual(burned.hand.count, full.handLimit)
        XCTAssertEqual(burned.deck.total, 1)

        // 靠抽到的牌才破得了的不收：对方 2 血，攻击只打掉 1；手里 1 费阿莱没费，抽到硬币才下得来。
        // 走过盲抽的搜索丢了「抽到硬币并用上」的走法 → 不能报穷举
        var needsCoin = position(enemy: 2, deck: [(.coin, 1), (.shadowstep, 1)])
        card(&needsCoin, .alexstrasza, cost: 1, copy: true)
        let no = solve(needsCoin)
        XCTAssertEqual(no.verdict, .cannotBreak)
        XCTAssertFalse(no.exhaustive, "因为随机性丢过分支：只是没搜到，不是证明")
        XCTAssertTrue(RedDragonSearch.solve(needsCoin, config: RedDragonLiveReplayTests.deterministic).isLethal,
                      "平常的斩杀搜索会报「抽到才斩」")
        // 牌库只剩硬币：必抽到，不算随机，可以用
        var onlyCoins = position(enemy: 2, deck: [(.coin, 2)])
        card(&onlyCoins, .alexstrasza, cost: 1, copy: true)
        let sure = solve(onlyCoins)
        XCTAssertNotEqual(sure.verdict, .cannotBreak)
        assertBacked(sure)
        XCTAssertEqual(try XCTUnwrap(sure.line).actions.count, 3, "攻击（必抽到硬币）→ 硬币 → 阿莱")
        // 没有抽牌的小局面照旧穷举
        XCTAssertTrue(solve(position(enemy: 30, deck: [])).exhaustive)
    }

    /// 盲抽那一步之后跟手：真实局面里抽到的是一张真牌、牌库少的是那一张，和推演的「不知道哪张」对得上
    func testFollowAcrossABlindDraw() throws {
        var s = root(mana: 0, enemy: 1)
        s.weapon = RDWeapon(attack: 1, durability: 2, drawOnHeroAttack: true)
        s.deck = RDDeck([(.coin, 1), (.shadowstep, 1)])
        let plan = solve(s)
        let line = try XCTUnwrap(plan.line)
        var real = try RDEngine.apply(line.actions[0], to: plan.root)
        real.opponent.ice = nil
        let k = try XCTUnwrap(real.hand.firstIndex { $0.blindDraw })
        real.hand[k] = RDHandCard(entityId: real.hand[k].entityId, card: .coin, enteredHandThisTurn: true)
        real.deck = RDDeck([(.shadowstep, 1)])
        let f = try XCTUnwrap(RDIceBreak.follow(plan, onto: real), "严格核对（不用宽松口径）就该对上")
        XCTAssertEqual(f.stepsTaken, 1)
        XCTAssertEqual(f.result.verdict, plan.verdict)
        XCTAssertEqual(f.result.line?.actions.count, 0)
        XCTAssertEqual(f.result.nextTurnDamage, plan.nextTurnDamage)
        // 牌库对不上（多了一张推演里没有的）就不算照着打
        var wrong = real
        wrong.deck = RDDeck([(.foxyFraud, 1)])
        XCTAssertNil(RDIceBreak.follow(plan, onto: wrong))
    }

    /// 阶段 A 复核 2：「本回合能破冰」和「下回合探针做没做完」分开。探针的预算用完时，已经重放过的破冰线照留，
    /// 结论落在「能破冰、下回合没搜到斩杀」并标出预算和「没探」，不是破不了
    func testBreakLineSurvivesWhenProbesRunOutOfBudget() throws {
        let state = breakAndLethalRoot().state
        // 搜索做完、进第一个探针前就过了截止时间（负的预留 = 搜索不受限，见 `RDIceBreakConfig.probeReserve`）
        var c = Self.detConfig()
        c.iceBreak.cpuBudget = -1
        c.iceBreak.probeReserve = -1e9
        let r = RedDragonSearch.solveIceBreak(state, config: c)
        XCTAssertEqual(r.verdict, .shortNextTurn, "原来这里是 cannotBreak")
        XCTAssertTrue(r.cpuBudgetHit)
        XCTAssertFalse(r.nextTurnProbed)
        XCTAssertNil(r.nextTurnLine)
        XCTAssertFalse(r.candidates.isEmpty)
        XCTAssertTrue(r.candidates.allSatisfy { !$0.probed })
        assertBacked(r)
        XCTAssertGreaterThan(r.breakStep, 0)
        // 同一个局面探针做完是 ①
        XCTAssertEqual(solve(state).verdict, .lethalNextTurn)
        XCTAssertTrue(solve(state).nextTurnProbed)

        // 进来已免疫、搜索和探针都没有预算：「什么都不打」那条照留，不会同时报 alreadyBroken 和 cannotBreak
        var immune = root(mana: 0, maxMana: 9, enemy: 8, secrets: 0, immune: true)
        minion(&immune, .spiritOfTheShark)
        card(&immune, .alexstrasza)
        c.iceBreak.probeReserve = 0
        let b = RedDragonSearch.solveIceBreak(immune, config: c)
        XCTAssertTrue(b.alreadyBroken)
        XCTAssertEqual(b.verdict, .shortNextTurn)
        XCTAssertEqual(b.line?.actions.count, 0)
        XCTAssertTrue(b.cpuBudgetHit)
        XCTAssertFalse(b.nextTurnProbed)
        assertBacked(b)

        // 探针的个数闸门同理：排在 `maxProbes` 之后的线照留，只是没探；探过的排在前面
        var few = Self.detConfig()
        few.iceBreak.maxProbes = 1
        let one = RedDragonSearch.solveIceBreak(state, config: few)
        XCTAssertNotEqual(one.verdict, .cannotBreak)
        XCTAssertTrue(one.nextTurnProbed)
        XCTAssertFalse(one.cpuBudgetHit)
        XCTAssertEqual(one.candidates.filter { $0.probed }.count, 1)
        XCTAssertTrue(try XCTUnwrap(one.candidates.first).probed)
        XCTAssertGreaterThan(one.candidates.count, 1)
    }

    /// 取消：标记一立起来就停，结果标 `cancelled`
    func testCancellation() {
        var c = Self.detConfig()
        let token = RDCancellation()
        token.cancel()
        c.cancellation = token
        let r = RedDragonSearch.solveIceBreak(breakAndLethalRoot().state, config: c)
        XCTAssertTrue(r.cancelled)
        XCTAssertNil(r.line)
    }

    // MARK: - 跟手、公式吃同一条规则

    /// 照着线打：破冰那一步之后的真实局面（读取层读出来的，没有标冰，对方免疫、奥秘少一个）接得上；
    /// 全部打完也接得上（剩 0 步）；下回合线换成真实编号后重放得过。打了别的、或那个奥秘不是冰，就接不上
    func testFollowAcrossTheBreak() throws {
        let (s, alexId, potionId) = breakAndLethalRoot()
        let plan = solve(s)
        let line = try XCTUnwrap(plan.line)
        XCTAssertEqual(line.actions.count, 2)

        // 第 1 步之后的真实局面：阿莱还是它在手里时的那个实体号（引擎推演时会新编号）
        var predicted = try RDEngine.apply(line.actions[0], to: plan.root)
        var real = predicted
        real.opponent.ice = nil
        let onBoard = try XCTUnwrap(real.board.firstIndex { $0.card == .alexstrasza })
        real.board[onBoard].entityId = alexId
        let first = try XCTUnwrap(RDIceBreak.follow(plan, onto: real))
        XCTAssertEqual(first.stepsTaken, 1)
        XCTAssertEqual(first.result.verdict, .lethalNextTurn)
        XCTAssertTrue(first.result.alreadyBroken)
        XCTAssertEqual(first.result.breakStep, 0)
        XCTAssertEqual(first.result.line?.actions, [play(potionId, .potionOfIllusion)])
        XCTAssertEqual(first.result.root.board[onBoard].entityId, alexId, "接过去的根局面是真实局面")
        XCTAssertEqual(first.result.nextTurnDamage, plan.nextTurnDamage)
        assertBacked(first.result)

        // 第 2 步之后：从原来的结论接、从上一次接出来的结论接，都剩 0 步
        predicted = try RDEngine.apply(line.actions[1], to: predicted)
        var done = try RDEngine.apply(try XCTUnwrap(first.result.line).actions[0], to: first.result.root)
        done.opponent.ice = nil
        let second = try XCTUnwrap(RDIceBreak.follow(first.result, onto: done))
        XCTAssertEqual(second.stepsTaken, 1)
        XCTAssertEqual(second.result.line?.actions.count, 0)
        XCTAssertEqual(second.result.verdict, .lethalNextTurn)
        assertBacked(second.result)
        var plain = predicted
        plain.opponent.ice = nil
        XCTAssertEqual(RDIceBreak.follow(plan, onto: plain)?.stepsTaken, 2)

        // 一步没打：接在第 0 步
        XCTAssertEqual(RDIceBreak.follow(plan, onto: s)?.stepsTaken, 0)
        // 打了别的（英雄技能）：对不上
        let other = try RDEngine.apply(.heroPower, to: s)
        XCTAssertNil(RDIceBreak.follow(plan, onto: other))
        // 那个奥秘不是寒冰屏障：阿莱照常打死 / 打掉血，对方没免疫 —— 和推演的对不上，调用方重算（阶段 B 报「已偏离」）
        let notIce = try RDEngine.apply(line.actions[0], to: s)
        XCTAssertNil(RDIceBreak.follow(plan, onto: notIce))
    }

    /// 公式沿标好冰的根局面推：破冰那一步照常写对脸，之后的准备步接着写；冰打掉之后阿莱下场写「奶」
    func testFormulaUsesTheSameRule() throws {
        let plan = solve(breakAndLethalRoot().state)
        let f = RDFormulaBuilder.formula(.preLaunch, try XCTUnwrap(plan.line).actions, root: plan.root,
                                         potential: plan.nextTurnDamage)
        XCTAssertEqual(f.tokens.map { RDText.formulaToken($0) }, ["龙4", "幻0"])
        XCTAssertEqual(f.leftBoard, [.spiritOfTheShark, .alexstrasza])
        XCTAssertEqual(f.leftHand, [.spiritOfTheShark, .alexstrasza])

        var s = root(mana: 10, enemy: 3)
        let knife = minion(&s, .scabbsCutterbutter, canAttack: true)
        let alex = card(&s, .alexstrasza, cost: 1)
        let actions: [RDAction] = [.attack(attacker: .friendlyMinion(knife), defender: .enemyHero),
                                   play(alex, .alexstrasza, .friendlyHero)]
        let armed = try XCTUnwrap(RDIceBreak.armed(s))
        XCTAssertEqual(RDFormulaBuilder.formula(.preLaunch, actions, root: armed).tokens.map { RDText.formulaToken($0) },
                       ["刀攻脸", "龙-奶9"])
        // 逐步提示也走同一个引擎：两步都走得通
        XCTAssertEqual(RDLineWalker.walk(actions, root: armed, zones: [:]).count, 2)
    }

    // MARK: - fixture 扫表

    /// 现有 fixture 的每个我方回合（回合开始的局面）都当成「对方有冰」跑一遍：回合、对方血量、结论档、本回合步数、
    /// 破冰后剩余、下回合伤害、耗时。断言只管结论自洽（线都重放得过、不靠随机抽牌）和「能斩就能破冰」，
    /// 数字看打印的 `T8SURVEY` / `T8SURVEY-LOW`；最慢的几个根局面打成字面量（`T8ROOT`）给 -O 基准用
    func testEveryFixtureTurnAsIfOpponentHadIceBlock() {
        let fixtures: [(String, Int)] = [("2026-10-01-g2-bounce-overflow", 1), ("2026-10-01-g3-lost", 1),
                                         ("2026-10-01-g4-second", 2), ("2026-10-01-g5-first", 1)]
            + RedDragonFeedbackTests.games.map { ($0.fixture, $0.playerId) }
            + [("2026-10-13-g12-chain", 1)]
        var out: [String] = []
        var lowOut: [String] = []
        var tally: [RDIceVerdict: Int] = [:]
        var lowTally: [RDIceVerdict: Int] = [:]
        var rows = 0
        var maxCpu = 0.0
        var maxStates = 0
        var slow: [(cpu: Double, name: String, literal: String, broke: Bool)] = []
        var lethalButCannotBreak: [String] = []
        var breakWithoutLethal: [String] = []
        var extraSteps: [Int] = []
        var cpuBudgetHits = 0
        // 斩杀搜索只用来对照「能斩 ⇔ 能破冰」，不找缺件
        var lethalConfig = RedDragonLiveReplayTests.deterministic
        lethalConfig.enableMissingPieces = false
        /// 一个根局面跑一遍，记一行。`low` = 把对方血量改小的那张附表
        func run(_ name: String, line: Int, _ state: RDState, low: Bool) {
            var s = state
            let lethal = RedDragonSearch.solve(s, config: lethalConfig)
            // 当成对方有冰：至少一个奥秘、没免疫
            s.opponent.secretCount = max(1, s.opponent.secretCount)
            s.opponent.immune = false
            let r = RedDragonSearch.solveIceBreak(s, config: Self.detConfig())
            assertBacked(r)
            rows += 1
            if low { lowTally[r.verdict, default: 0] += 1 } else { tally[r.verdict, default: 0] += 1 }
            maxCpu = max(maxCpu, r.cpuTime)
            maxStates = max(maxStates, r.statesExpanded)
            if r.cpuBudgetHit { cpuBudgetHits += 1 }
            slow.append((r.cpuTime, name, RedDragonLiveReplayTests.literal(s), r.line != nil))
            if lethal.deterministicLethal && r.verdict == .cannotBreak { lethalButCannotBreak.append(name) }
            if !lethal.isLethal && r.verdict != .cannotBreak { breakWithoutLethal.append(name) }
            var row = "\(name) 行\(line) 法力\(s.availableMana)/\(s.maxMana) 对方\(s.opponent.health)+\(s.opponent.armor)"
                + " 斩杀搜索:\(lethal.deterministicLethal ? "斩" : (lethal.isLethal ? "抽到才斩" : "不斩"))"
            switch r.verdict {
            case .lethalNextTurn:
                row += " → ①可破·下回合可斩"
            case .shortNextTurn:
                row += " → ②可破·下回合差\(r.shortBy)"
            case .cannotBreak:
                row += " → ③破不了" + (r.exhaustive ? "（穷举）" : "")
            case .notApplicable:
                row += " → 不适用"
            }
            if let line = r.line {
                row += " 本回合\(line.actions.count)步(第\(r.breakStep)步破冰) 剩\(r.remaining) 下回合\(r.nextTurnDamage)"
                    + (r.nextTurnLethalSteps.map { "(\($0)步斩)" } ?? "")
            }
            // 口径 4 先比「超出多少（按 8 分档）」再比步数：记下它比「步数最少的可斩候选」多走了几步
            if r.verdict == .lethalNextTurn, let line = r.line,
               let shortest = r.candidates.filter({ $0.margin >= 0 })
                .min(by: { ($0.steps, -$0.margin) < ($1.steps, -$1.margin) }),
               shortest.steps < line.actions.count {
                extraSteps.append(line.actions.count - shortest.steps)
                row += "｜步数最少的可斩候选 \(shortest.steps) 步、超出 \(shortest.margin)，选中的超出 \(r.nextTurnDamage - r.remaining)"
            }
            row += String(format: " %d态 %.2fs", r.statesExpanded, r.cpuTime)
            if let line = r.line, !line.actions.isEmpty {
                row += "：" + RDFormulaBuilder.formula(.preLaunch, line.actions, root: r.root).tokens
                    .map { RDText.formulaToken($0) }.joined(separator: " ")
            }
            if low { lowOut.append(row) } else { out.append(row) }
        }
        for (fixture, pid) in fixtures {
            let bs = RedDragonSetupTests.boundaries(lines: RedDragonFeedbackTests.lines(fixture), playerId: pid)
            var byTurn: [Int: [RedDragonFeedbackTests.Boundary]] = [:]
            for b in bs { byTurn[b.snapshot.turn, default: []].append(b) }
            for turn in byTurn.keys.sorted() {
                // 回合开始的局面：水晶已经涨好、还一点没花的第一个边界（回合头几个边界在涨水晶之前，法力还是上回合的）
                guard let all = byTurn[turn], let top = all.map({ $0.snapshot.resources }).max(),
                      let b = all.first(where: { $0.snapshot.resources == top && $0.snapshot.resourcesUsed == 0 })
                        ?? all.first(where: { $0.snapshot.resources == top }) else { continue }
                let s = RDStateReader.read(b.snapshot).state
                run("\(fixture) T\(turn)", line: b.line, s, low: false)
                // 附表：同一个局面把对方改成 12 血。实录里对方回合开始时大多 30 血上下、本回合破不了，
                // 这张表看的是真实手牌上破得了时给什么线、花多久
                var t = s
                t.opponent.health = 12
                t.opponent.armor = 0
                run("\(fixture) T\(turn) 改12血", line: b.line, t, low: true)
            }
        }
        slow.sort { $0.cpu > $1.cpu }
        func summary(_ t: [RDIceVerdict: Int]) -> String {
            return "①可斩 \(t[.lethalNextTurn] ?? 0) / ②差一点 \(t[.shortNextTurn] ?? 0) / ③破不了 \(t[.cannotBreak] ?? 0)"
        }
        print("T8SURVEY\n" + out.joined(separator: "\n")
            + "\n汇总：\(out.count) 个回合，\(summary(tally))"
            + "\nT8SURVEY-LOW（同一批局面，对方改成 12 血）\n" + lowOut.joined(separator: "\n")
            + "\n汇总：\(lowOut.count) 个回合，\(summary(lowTally))"
            + "\n两张表合计：最慢 \(String(format: "%.2f", maxCpu)) s，最多 \(maxStates) 态；撞 CPU 兜底 \(cpuBudgetHits) 次"
            + "\n斩杀搜索能斩（确定线）而破冰说破不了：\(lethalButCannotBreak)"
            + "\n斩杀搜索不斩而破冰说能破：\(breakWithoutLethal)"
            + "\n①里选中的线比步数最少的可斩候选长的有 \(extraSteps.count) 个，各多 \(extraSteps.sorted()) 步")
        // 最慢的几个根局面（已当成有冰）：给 scratchpad 里 `swiftc -O` 的基准用。破不了的（三遍搜索跑满）和
        // 破得了的（搜索 + 准备步 + 探针）各取最慢的 6 个
        for s in slow.filter({ !$0.broke }).prefix(6) + slow.filter({ $0.broke }).prefix(6) {
            print("T8ROOT \(s.name) \(String(format: "%.2f", s.cpu))s :: \(s.literal)")
        }
        XCTAssertGreaterThan(rows, 0)
        XCTAssertEqual(cpuBudgetHits, 0, "测试配置把 CPU 兜底放开了")
        XCTAssertTrue(lethalButCannotBreak.isEmpty, "能斩（不靠抽牌）就一定能破冰：致命的那一下就是破冰的那一下")
    }
}
