//
//  RedDragonIceBreakTests.swift
//  HSTrackerTests
//
//  T8 破冰模式 · 阶段 A（引擎和搜索）：寒冰屏障的规则、下回合起手的费用、构造局面上的三种结论、
//  跟手和公式吃同一条规则，以及把现有 fixture 的每个我方回合都当成「对方有冰」跑一遍的扫表（打印 `T8SURVEY`）。
//
//  规则一句话：对方挂着寒冰屏障时，敌方英雄受到的某一次伤害 ≥ 当前血量 + 护甲，这一次就整个不生效、对方本回合免疫、
//  奥秘没了；不致命的伤害照常扣。「破冰」= 本回合把它触发掉，下回合再斩。「口径订正」一节是 10-14 的订正：
//  最好的破法是把血压到最低再触发（剩余血量低的优先），鲨鱼下阿莱的两次 8 分开判。
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

    /// 读 fixture 日志的测试先等宿主 app 启动完：日志回放会走到 `AppDelegate.instance().coreManager`（隐式解包），
    /// 它在启动后异步才建好。只跑这一组时测试在启动后 0.1 秒内就开始，不等会崩在 TagChangeActions（做法同
    /// `RedDragonLiveReplayTests.setUp`）
    private func waitForHostApp() {
        let launched = Date().addingTimeInterval(30)
        while AppDelegate.instance().coreManager == nil && Date() < launched {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        XCTAssertNotNil(AppDelegate.instance().coreManager)
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

    /// `attack`：把攻击力改成这个数（构造「一下打 N」用），不给就是卡面的
    @discardableResult
    private func minion(_ s: inout RDState, _ c: RDCard, canAttack: Bool = false, attack: Int? = nil) -> Int {
        let d = RDCards.def(c)
        let id = s.takeEntityId()
        s.board.append(RDBoardMinion(entityId: id, card: c, attack: attack ?? d.attack, health: d.health,
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

    /// 测试自己的判断：从 `root` 起逐步重放，看每个 `.pick` 选的牌是不是从边牌里拿走的 —— 选了某张、边牌里却没少
    /// 这一张，就是从牌库随机抽到的。故意不用牌名单（`RDCards.sideboardCards`，原来就是它，牌库里有同名牌时挡不住）
    /// 也不用被测的 `RDEngine.picksRandomDraw`，只看结算的结果。（同一张牌既抽牌又发现、两边都是同一张时会认漏，
    /// 本牌组没有这种牌。）走不通的线按「有」算
    private func hasRandomDraw(_ actions: [RDAction], from root: RDState) -> Bool {
        var s = root
        for a in actions {
            guard let t = try? RDEngine.apply(a, to: s) else { return true }
            var taken: [RDCard: Int] = [:]
            for c in s.sideboard { taken[c, default: 0] += 1 }
            for c in t.sideboard { taken[c, default: 0] -= 1 }
            for case .pick(let c) in a.choices {
                guard let n = taken[c], n > 0 else { return true }
                taken[c] = n - 1
            }
            s = t
        }
        return false
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
        XCTAssertFalse(hasRandomDraw(now.actions, from: r.root), "本回合的线不靠随机抽牌", file: file, line: line)
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
            XCTAssertFalse(hasRandomDraw(nl.actions, from: next), "下回合的线不靠随机抽牌", file: file, line: line)
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

        // 用户点名的两个数（口径 13）。当成「一次 16」会算错的正是这种：
        out = try after(9)
        XCTAssertEqual(out.opponent.health, 1, "第一次 8 照扣剩 1，第二次 8 触发：剩 1，不是「16 ≥ 9 被挡、剩 9」")
        XCTAssertEqual(out.opponent.ice, .broken)
        XCTAssertEqual(out.damageDealt, 8)

        out = try after(17)
        XCTAssertEqual(out.opponent.health, 1, "两次 8 都不致命，都照扣")
        XCTAssertEqual(out.opponent.ice, .armed, "剩 1 血、冰还在：要另补一下才触发")
        XCTAssertEqual(out.opponent.secretCount, 1)
        XCTAssertEqual(out.damageDealt, 16)
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
        waitForHostApp()
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

    /// Codex review P1（10-14）：「抽牌」还是「E.T.C. 的发现」按效果来源分，不按牌名。牌库里有和边牌同名的牌
    /// （主牌里放了幻觉药水）时，行骗随机抽到它照样是随机抽牌。原来按牌名分，下面这个局面报「下回合可斩、伤害 9」，
    /// 下回合线是「行骗选药水 → 药水 → 1 费阿莱 → 英雄技能 → 攻脸」—— 行骗换成抽到伺机待发，第二步就走不通。
    /// 对方冰已碎（免疫）、剩 8；我方 10 水晶、本回合 0 费，场上阿莱，手里只有行骗，牌库幻觉药水、伺机待发各一张
    func testRandomDrawOfACardNamedLikeASideboardCardIsStillRandom() throws {
        var s = root(mana: 0, enemy: 8, secrets: 0, immune: true)
        minion(&s, .alexstrasza)
        let swindle = card(&s, .swindle)
        s.deck = RDDeck([(.potionOfIllusion, 1), (.preparation, 1)])
        let r = solve(s)
        assertBacked(r)
        XCTAssertTrue(r.alreadyBroken)
        XCTAssertEqual(r.verdict, .shortNextTurn, "下回合要靠行骗抽到药水才斩得了：不算可斩")
        XCTAssertLessThan(r.nextTurnDamage, 8)
        XCTAssertFalse(r.candidates.contains { c in
            c.nextTurnLine.map { RDEngine.lineHasRandomDraw($0.actions, from: c.nextTurnRoot) } ?? false
        }, "候选里的下回合线一条都不靠随机抽牌")

        // 那条靠运气的线本身：运气好确实斩得了，但探针收线、缓存复用、跟手（`evidence`）都不认
        let next = try XCTUnwrap(r.nextTurnRoot)
        let lucky = RDAction.play(entityId: swindle, identity: .swindle, target: .none,
                                  choices: [.pick(.potionOfIllusion)])
        XCTAssertTrue(RDEngine.picksRandomDraw(lucky, in: next))
        var t = try RDEngine.apply(lucky, to: next)
        let potion = try XCTUnwrap(t.hand.first { $0.card == .potionOfIllusion }).entityId
        let drink = play(potion, .potionOfIllusion)
        XCTAssertFalse(RDEngine.picksRandomDraw(drink, in: t))
        t = try RDEngine.apply(drink, to: t)
        let copy = try XCTUnwrap(t.hand.first { $0.card == .alexstrasza }).entityId
        let blast = play(copy, .alexstrasza, .enemyHero)
        t = try RDEngine.apply(blast, to: t)
        XCTAssertLessThanOrEqual(t.opponent.health, 0, "抽到药水的话确实斩得了")
        let comps = RDDifficulty.components(for: [], sideboardCardsTaken: 0, weights: .standard)
        let luckyLine = RedDragonLine(actions: [lucky, drink, blast], damage: t.damageDealt,
                                      difficulty: comps.score, components: comps,
                                      tier: RDDifficulty.tier(comps.score), branchKey: [], truncated: false)
        XCTAssertNil(RDIceBreak.evidence(luckyLine, on: next), "靠随机抽牌的下回合线不算数")
        XCTAssertTrue(RDEngine.lineHasRandomDraw(luckyLine.actions, from: next))
        XCTAssertTrue(hasRandomDraw(luckyLine.actions, from: next), "测试自己的判断也认得出")
        // 抽到的是伺机待发：这条线第二步就走不通
        let unlucky = lucky.replacingChoices([.pick(.preparation)])
        let other = try RDEngine.apply(unlucky, to: next)
        XCTAssertThrowsError(try RDEngine.apply(drink, to: other))

        // 对照：同一张药水从 E.T.C. 发现来（边牌里还有两张可选）是自己选的，照收
        var d = root(mana: 0, enemy: 8, secrets: 0, immune: true)
        d.sideboard = [.bounceAround, .potionOfIllusion]
        minion(&d, .alexstrasza)
        card(&d, .etcBandManager)
        d.deck = RDDeck([(.potionOfIllusion, 1), (.preparation, 1)])
        let chosen = solve(d)
        assertBacked(chosen)
        XCTAssertEqual(chosen.verdict, .lethalNextTurn, "发现是自己选的")
        let nl = try XCTUnwrap(chosen.nextTurnLine)
        XCTAssertTrue(nl.actions.contains { a in a.choices.contains { if case .pick = $0 { return true }; return false } },
                      "下回合线里有发现的选择")
    }

    /// `RDEngine.picksRandomDraw` 逐种钉住：抽牌槽上的选择是随机的（不管牌名），发现槽上的是自己选的，盲抽不算「选」；
    /// 跟手（`RDContinuation.resume` 的破冰支）同一个判断
    func testRandomDrawIsJudgedBySourceNotName() throws {
        // 行骗（抽一张法术）：牌库两种法术，选哪张都是随机的 —— 包括和边牌同名的药水
        var s = root(mana: 10, enemy: 30)
        let swindle = card(&s, .swindle)
        let etc = card(&s, .etcBandManager)
        s.sideboard = [.bounceAround, .potionOfIllusion]
        s.deck = RDDeck([(.potionOfIllusion, 1), (.preparation, 1)])
        func draw(_ choices: [RDChoice]) -> RDAction {
            return .play(entityId: swindle, identity: .swindle, target: .none, choices: choices)
        }
        XCTAssertTrue(RDEngine.picksRandomDraw(draw([.pick(.potionOfIllusion)]), in: s))
        XCTAssertTrue(RDEngine.picksRandomDraw(draw([.pick(.preparation)]), in: s))
        XCTAssertFalse(RDEngine.picksRandomDraw(draw([.blind]), in: s), "盲抽不靠抽到哪张")
        // E.T.C.（从边牌发现）：选药水是自己选的
        let discover = RDAction.play(entityId: etc, identity: .etcBandManager, target: .none,
                                     choices: [.pick(.potionOfIllusion)])
        XCTAssertFalse(RDEngine.picksRandomDraw(discover, in: s))
        // 牌库的法术只剩药水：必抽到它，引擎不出选择，不算随机；硬塞一个选择 = 对不上槽位，按「有」算
        var only = s
        only.deck = RDDeck([(.potionOfIllusion, 1), (.foxyFraud, 1)])
        XCTAssertFalse(RDEngine.picksRandomDraw(draw([]), in: only))
        XCTAssertTrue(RDEngine.picksRandomDraw(draw([.pick(.potionOfIllusion)]), in: only))
        // 连击的行骗（法术 + 随从各一张）：第一抽确定、第二抽随机
        var combo = only
        combo.cardsPlayedThisTurn = 1
        combo.deck = RDDeck([(.potionOfIllusion, 1), (.foxyFraud, 1), (.alexstrasza, 1)])
        XCTAssertTrue(combo.comboActive)
        XCTAssertTrue(RDEngine.picksRandomDraw(draw([.pick(.alexstrasza)]), in: combo),
                      "随从槽里阿莱和狐人老千二选一：阿莱同名也是随机的")
        XCTAssertFalse(RDEngine.picksRandomDraw(draw([.blind, .blind]), in: combo))
        // 疾速矿锄攻击后的抽牌
        var pick = root(mana: 0, enemy: 30)
        pick.weapon = RDWeapon(attack: 1, durability: 2, drawOnHeroAttack: true)
        pick.deck = RDDeck([(.potionOfIllusion, 1), (.coin, 1)])
        XCTAssertTrue(RDEngine.picksRandomDraw(.attack(attacker: .friendlyHero, defender: .enemyHero,
                                                       choices: [.pick(.potionOfIllusion)]), in: pick))
        XCTAssertFalse(RDEngine.picksRandomDraw(.attack(attacker: .friendlyHero, defender: .enemyHero,
                                                        choices: [.blind]), in: pick))
        // 认不出的（手里没有这张）按「有」算
        XCTAssertTrue(RDEngine.picksRandomDraw(.play(entityId: 9999, identity: .swindle, target: .none,
                                                     choices: [.pick(.preparation)]), in: s))

        // 跟手：本回合的破冰线里有一步靠随机抽到药水 → 接不上；同样的药水从 E.T.C. 发现来 → 接得上。
        // 对方 8 血挂冰，场上能攻击的阿莱一下 8 就是破冰的那一下
        func position(hand: RDCard, mana: Int) -> (RDState, Int) {
            var s = root(mana: mana, enemy: 8)
            minion(&s, .alexstrasza, canAttack: true)
            let id = card(&s, hand)
            s.sideboard = [.bounceAround, .potionOfIllusion]
            s.deck = RDDeck([(.potionOfIllusion, 1), (.preparation, 1)])
            return (s, id)
        }
        func plan(_ actions: [RDAction]) -> RedDragonLine {
            let comps = RDDifficulty.components(for: actions, sideboardCardsTaken: 0, weights: .standard)
            return RedDragonLine(actions: actions, damage: 0, difficulty: comps.score, components: comps,
                                 tier: RDDifficulty.tier(comps.score), branchKey: [], truncated: false)
        }
        let (r1, sw) = position(hand: .swindle, mana: 2)
        let a1 = try XCTUnwrap(RDIceBreak.armed(r1))
        let alex1 = a1.board[0].entityId
        let luckyBreak = plan([.play(entityId: sw, identity: .swindle, target: .none, choices: [.pick(.potionOfIllusion)]),
                               .attack(attacker: .friendlyMinion(alex1), defender: .enemyHero)])
        XCTAssertEqual(try RDReplay.run(luckyBreak.actions, from: a1).finalState.opponent.ice, .broken)
        XCTAssertNil(RDContinuation.resume(luckyBreak, from: a1, onto: a1, iceBreak: true),
                     "靠随机抽牌的破冰线不接")
        let (r2, e) = position(hand: .etcBandManager, mana: 4)
        let a2 = try XCTUnwrap(RDIceBreak.armed(r2))
        let alex2 = a2.board[0].entityId
        let chosenBreak = plan([.play(entityId: e, identity: .etcBandManager, target: .none,
                                      choices: [.pick(.potionOfIllusion)]),
                                .attack(attacker: .friendlyMinion(alex2), defender: .enemyHero)])
        XCTAssertNotNil(RDContinuation.resume(chosenBreak, from: a2, onto: a2, iceBreak: true),
                        "发现来的照接")
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

    // MARK: - 口径订正（11–13）：剩余血量低的优先，鲨鱼下的阿莱是两次 8
    //
    // 寒冰屏障让对方这回合掉不到 1 血以下：致命的那一下整个不算。所以破冰的好坏不看打出去多少，看触发之前把血压到了多低
    // —— 对方 10 血，一下打 10 被免疫、剩 10；先打 9 再打 1，剩 1。下面几条各管一件事：怎么排（`better`）、
    // 搜索会不会因为已经有一条浅的破冰线就不往下找、压得最低的那条下回合斩不了怎么办、两次 8 在搜索里有没有被当成一次 16。

    /// 排序用的假候选：只有 `RDIceBreak.better` 看的几项是真的（剩余血量、下回合伤害、本回合步数、探没探）
    private func candidate(remaining: Int, nextTurn: Int, steps: Int, probed: Bool = true) -> RDIceCandidate {
        let comps = RDDifficulty.components(for: [], sideboardCardsTaken: 0, weights: .standard)
        let line = RedDragonLine(actions: Array(repeating: .heroPower, count: steps), damage: 0,
                                 difficulty: comps.score, components: comps, tier: RDDifficulty.tier(comps.score),
                                 branchKey: [], truncated: false)
        return RDIceCandidate(line: line, remaining: remaining, nextTurnRoot: root(mana: 0, enemy: remaining),
                              nextTurnLine: nil, nextTurnDamage: nextTurn, nextTurnLethalSteps: nil, probed: probed)
    }

    /// 口径 11 的先后，一项一项钉住。每一对里前一个应该排在后一个前面
    func testOrderingPutsLowestRemainingFirstAmongLethalLines() {
        func assertFirst(_ a: RDIceCandidate, _ b: RDIceCandidate, _ why: String, line: UInt = #line) {
            XCTAssertTrue(RDIceBreak.better(a, b), why, line: line)
            XCTAssertFalse(RDIceBreak.better(b, a), why, line: line)
        }
        // 都可斩：先比剩余血量。剩 1、下回合刚好够、走了 9 步 > 剩 8、下回合溢出 40、只走 1 步
        // （订正前先比溢出的 8 分档，这一对是反过来的）
        assertFirst(candidate(remaining: 1, nextTurn: 1, steps: 9),
                    candidate(remaining: 8, nextTurn: 48, steps: 1), "可斩的里面剩余血量低的在前")
        // 剩余相同：下回合超出的部分按 8 分档，档高的在前（超出 16 是 2 档，超出 15 是 1 档），步数不管
        assertFirst(candidate(remaining: 4, nextTurn: 20, steps: 9),
                    candidate(remaining: 4, nextTurn: 19, steps: 1), "同剩余：8 分档高的在前")
        // 同剩余同档（超出 8 和 15 都是 1 档）：步数少的在前
        assertFirst(candidate(remaining: 4, nextTurn: 12, steps: 2),
                    candidate(remaining: 4, nextTurn: 19, steps: 3), "同剩余同档：步数少的在前")
        // 再同：超得多的在前
        assertFirst(candidate(remaining: 4, nextTurn: 19, steps: 2),
                    candidate(remaining: 4, nextTurn: 12, steps: 2), "同剩余同档同步数：超得多的在前")
        // 可斩永远在不可斩前面，哪怕剩得多：压得再低，下回合斩不掉也不如能斩的
        assertFirst(candidate(remaining: 8, nextTurn: 8, steps: 5),
                    candidate(remaining: 1, nextTurn: 0, steps: 1), "可斩的在不可斩的前面")
        // 都不可斩：差得少的在前（差 1 > 差 2）
        assertFirst(candidate(remaining: 8, nextTurn: 7, steps: 5),
                    candidate(remaining: 2, nextTurn: 0, steps: 1), "都不可斩：差得少的在前")
        // 同差（都差 1）：剩余低的在前；再同：步数少的在前
        assertFirst(candidate(remaining: 2, nextTurn: 1, steps: 5),
                    candidate(remaining: 8, nextTurn: 7, steps: 1), "都不可斩、同差：剩余低的在前")
        assertFirst(candidate(remaining: 2, nextTurn: 1, steps: 1),
                    candidate(remaining: 2, nextTurn: 1, steps: 5), "都不可斩、同差同剩余：步数少的在前")
        // 下回合没探的排在探过的后面（它的伤害是「不知道」）；都没探：剩余低的在前，再按步数
        assertFirst(candidate(remaining: 9, nextTurn: 0, steps: 5),
                    candidate(remaining: 1, nextTurn: 0, steps: 1, probed: false), "探过的在没探的前面")
        assertFirst(candidate(remaining: 1, nextTurn: 0, steps: 5, probed: false),
                    candidate(remaining: 3, nextTurn: 0, steps: 1, probed: false), "都没探：剩余低的在前")
        assertFirst(candidate(remaining: 3, nextTurn: 0, steps: 1, probed: false),
                    candidate(remaining: 3, nextTurn: 0, steps: 2, probed: false), "都没探、同剩余：步数少的在前")

        // 放在一起排一遍
        let sorted = [candidate(remaining: 8, nextTurn: 48, steps: 1), candidate(remaining: 1, nextTurn: 0, steps: 1),
                      candidate(remaining: 3, nextTurn: 3, steps: 6), candidate(remaining: 1, nextTurn: 1, steps: 9),
                      candidate(remaining: 2, nextTurn: 30, steps: 2, probed: false)]
            .sorted(by: RDIceBreak.better)
        XCTAssertEqual(sorted.map { $0.remaining }, [1, 3, 8, 1, 2], "可斩的按剩余 1 / 3 / 8，然后是斩不了的剩 1，最后是没探的")
        XCTAssertEqual(sorted.map { $0.nextTurnDamage }, [1, 3, 48, 0, 30])
    }

    /// 订正验收 ①（用户的例子）：对方 10 血。场上三个能攻击的随从，攻击力 10 / 9 / 1；鲨鱼在场、手里一张 1 费阿莱留给下回合
    /// （本回合 0 费，只有攻击可做）。一下打 10：这一下被挡，剩 10。先打 9 再打 1：9 照扣剩 1，那 1 点触发，剩 1。
    /// 两条下回合都可斩（阿莱 8 + 8），要的是剩 1 的那条
    func testUserExampleNineThenOneBeatsOneHitOfTen() throws {
        var s = root(mana: 0, maxMana: 9, enemy: 10)
        minion(&s, .spiritOfTheShark)
        let ten = minion(&s, .foxyFraud, canAttack: true, attack: 10)
        let nine = minion(&s, .foxyFraud, canAttack: true, attack: 9)
        let one = minion(&s, .foxyFraud, canAttack: true, attack: 1)
        card(&s, .alexstrasza, cost: 1, copy: true)
        let r = solve(s)
        XCTAssertEqual(r.verdict, .lethalNextTurn)
        assertBacked(r)
        XCTAssertEqual(r.remaining, 1, "先打 9 再触发：剩 1")
        XCTAssertEqual(r.breakStep, 2, "冰是第二下碎的")
        let line = try XCTUnwrap(r.line)
        XCTAssertEqual(line.actions.count, 2)
        XCTAssertEqual(line.actions.first, .attack(attacker: .friendlyMinion(nine), defender: .enemyHero),
                       "第一下必须是不致命的 9")
        // 第二下用 1 还是用 10 都行：剩 1 血时任何伤害都触发
        XCTAssertTrue([one, ten].map { RDAction.attack(attacker: .friendlyMinion($0), defender: .enemyHero) }
            .contains(line.actions[1]))

        // 一下打满的那条也搜到了、也真能破冰（剩 10），它的下回合同样可斩 —— 它输在剩余血量上，不是输在斩不了
        let best = try XCTUnwrap(r.candidates.first)
        var oneHit = try XCTUnwrap(r.candidates.first { $0.steps == 1 }, "一下打 10 的破法应该在候选里")
        XCTAssertEqual(oneHit.line.actions, [.attack(attacker: .friendlyMinion(ten), defender: .enemyHero)])
        XCTAssertEqual(oneHit.remaining, 10)
        // 剩 1 的那一档已经探出可斩，剩得更多的档不用探（探了也排不到前面）；这里手工探一下，证明它确实可斩
        XCTAssertFalse(oneHit.probed)
        let probe = RDIceBreak.probe(oneHit.nextTurnRoot, config: Self.detConfig(), deadline: .infinity)
        XCTAssertGreaterThanOrEqual(probe.damage, 10, "一下打满的那条下回合也可斩")
        oneHit.probed = true
        oneHit.nextTurnDamage = probe.damage
        XCTAssertTrue(RDIceBreak.better(best, oneHit))
        // 先打 1 再打 9 / 10：1 照扣剩 9，后一下触发，剩 9 —— 先后顺序反了也不行
        XCTAssertTrue(r.candidates.contains { $0.remaining == 9 && $0.steps == 2 })
    }

    /// 订正验收 ②：浅的破法剩得多，多走几步的剩得少，两条下回合都可斩 —— 要剩得少的那条，搜索不能因为已经有了浅的就停。
    /// 对方 11 血，鲨鱼在场，2 费 + 一枚硬币，手里两张 1 费阿莱。
    ///   浅：阿莱打脸（8 照扣剩 3，第二个 8 触发）—— 1 步，剩 3。
    ///   深：硬币 → 英雄技能 → 匕首攻脸（剩 10）→ 阿莱打脸（8 照扣剩 2，第二个 8 触发）—— 4 步，剩 2。
    /// 两条下回合都是另一张阿莱 16 + 匕首 1 = 17，超出 14 和 15 同在 1 档：订正前「同档取步数少的」给的是浅的那条，
    /// 而且深的那条比最浅的破冰多 3 层，超过原来的「再走两层」，根本搜不到
    func testDeeperBreakThatLeavesLessBeatsTheShallowOne() throws {
        var s = root(mana: 2, maxMana: 9, enemy: 11)
        minion(&s, .spiritOfTheShark)
        let coin = card(&s, .coin)
        card(&s, .alexstrasza, cost: 1, copy: true)
        card(&s, .alexstrasza, cost: 1, copy: true)
        let r = solve(s)
        XCTAssertEqual(r.verdict, .lethalNextTurn)
        assertBacked(r)
        XCTAssertEqual(r.remaining, 2)
        let line = try XCTUnwrap(r.line)
        XCTAssertEqual(line.actions.count, 4)
        XCTAssertEqual(Array(line.actions.prefix(3)),
                       [play(coin, .coin), .heroPower, .attack(attacker: .friendlyHero, defender: .enemyHero)])
        guard case .play(_, .alexstrasza, .enemyHero, _, _) = line.actions[3] else {
            return XCTFail("最后一步是阿莱打脸")
        }
        XCTAssertEqual(r.breakStep, 4)

        // 浅的那条也在候选里：1 步、剩 3，下回合同样可斩
        let shallow = try XCTUnwrap(r.candidates.first { $0.steps == 1 })
        XCTAssertEqual(shallow.remaining, 3)
        XCTAssertGreaterThan(line.actions.count - shallow.steps, RDIceBreakConfig().extraBreakLayers,
                             "步数差超过「剩 1 之后再走几层」：靠的是压血那一段不因为有了破冰线就停")
        let probe = RDIceBreak.probe(shallow.nextTurnRoot, config: Self.detConfig(), deadline: .infinity)
        XCTAssertGreaterThanOrEqual(probe.damage, shallow.remaining)
        // 两条超出的部分在同一个 8 分档里（订正前就会按步数选浅的）
        XCTAssertEqual((probe.damage - shallow.remaining) / 8, (r.nextTurnDamage - r.remaining) / 8)
    }

    /// 订正验收 ③：剩得最少的那条下回合斩不了、剩得多一点的能斩 —— 要能斩的。
    /// 局面同 `breakAndLethalRoot`（对方 16 血；3 水晶 + 2 临时水晶；鲨鱼在场；1 费阿莱 + 4 费幻觉药水）。
    ///   剩 7：英雄技能 → 匕首攻脸（15）→ 阿莱（8 照扣剩 7，第二个 8 触发）。法力花光，药水没喝；下回合 4 费只够喝药水，
    ///         复制出来的阿莱下不来，只有匕首的 1 点 —— 斩不了。
    ///   剩 8：阿莱（剩 8）→ 喝药水。下回合 4 费下 1 费阿莱，16 ≥ 8 —— 可斩。
    func testLowestRemainingThatCannotKillLosesToOneThatCan() throws {
        let state = breakAndLethalRoot().state
        let r = solve(state)
        XCTAssertEqual(r.verdict, .lethalNextTurn)
        assertBacked(r)
        XCTAssertEqual(r.remaining, 8, "剩 7 的那条下回合斩不了，取能斩的剩 8")
        XCTAssertEqual(r.candidates.map { $0.remaining }.min(), 7, "压得最低的破法是剩 7")
        let lowest = r.candidates.filter { $0.remaining == 7 }
        XCTAssertFalse(lowest.isEmpty)
        XCTAssertTrue(lowest.allSatisfy { $0.probed }, "最低的一档都探过了，不是没轮到")
        XCTAssertTrue(lowest.allSatisfy { $0.margin < 0 }, "探出来都斩不了")
        XCTAssertEqual(lowest.map { $0.steps }.min(), 3)

        // 探针从剩余最低的一档探起（口径 12）：只给 1 个名额，探的就是剩 7 的；结论只能说「下回合没搜到斩杀」
        var few = Self.detConfig()
        few.iceBreak.maxProbes = 1
        let one = RedDragonSearch.solveIceBreak(state, config: few)
        XCTAssertEqual(one.candidates.filter { $0.probed }.map { $0.remaining }, [7])
        XCTAssertEqual(one.verdict, .shortNextTurn)
        XCTAssertEqual(one.remaining, 7)

        // 2 个名额：剩 7 的一档只有 1 条，另 1 个名额给剩 8 的一档的队首 —— 那一档便宜分最高的「阿莱 → 药水」
        // （剩 8 的一档里步数最少的「只下阿莱」下回合斩不了；队首若是它，这 2 个名额就都白花）
        few.iceBreak.maxProbes = 2
        let two = RedDragonSearch.solveIceBreak(state, config: few)
        XCTAssertEqual(two.candidates.filter { $0.probed }.map { $0.remaining }.sorted(), [7, 8])
        XCTAssertEqual(two.verdict, .lethalNextTurn)
        XCTAssertEqual(two.remaining, 8)
        XCTAssertEqual(two.line?.actions.count, 2)
    }

    /// 探针名额怎么分（`RDIceBreak.scheduleProbes`，口径 12）：每一档都先探一两条，再回头把低档补满。
    /// 只按「低档先探满」分的话，最低的几档探满了、都斩不了，名额就用完了，更高的档里有可斩的线也轮不到
    func testEveryRemainingLevelIsProbedBeforeLowLevelsAreFilled() {
        // 五档（剩 1…5），每档 10 条；只有剩 5 的那一档可斩。名额 32、每档先 2 条、再补到 8 条
        var calls: [(level: Int, index: Int)] = []
        let done = RDIceBreak.scheduleProbes(remaining: [1, 2, 3, 4, 5], counts: [10, 10, 10, 10, 10], quota: 32,
                                             first: 2, perLevel: 8) { level, index in
            calls.append((level, index))
            return level == 4
        }
        XCTAssertEqual(done, [8, 8, 8, 6, 2], "第一轮每档 2 条（剩 5 的那档探出可斩），第二轮从低档起补到 8 条，名额用完为止")
        XCTAssertEqual(calls.count, 32)
        XCTAssertEqual(calls.prefix(10).map { $0.level }, [0, 0, 1, 1, 2, 2, 3, 3, 4, 4], "第一轮：每一档都轮到")
        XCTAssertTrue(calls.allSatisfy { $0.index < 10 })
        // 对照：不先给每档探一两条（`first` = 0），32 个名额全花在最低的四档上，剩 5 的那档一条都轮不到
        let starved = RDIceBreak.scheduleProbes(remaining: [1, 2, 3, 4, 5], counts: [10, 10, 10, 10, 10], quota: 32,
                                                first: 0, perLevel: 8) { level, _ in level == 4 }
        XCTAssertEqual(starved, [8, 8, 8, 8, 0])

        // 低档探出可斩，高档就不再探（剩得多的线排不到它前面）；低档自己接着探满
        let low = RDIceBreak.scheduleProbes(remaining: [1, 2, 3], counts: [10, 10, 10], quota: 32,
                                            first: 2, perLevel: 8) { level, _ in level == 0 }
        XCTAssertEqual(low, [10, 0, 0])
        // 进来之前已知可斩的最低剩余（`lethalAt`，盲抽线那一轮用）：比它高的档一条不探
        let known = RDIceBreak.scheduleProbes(remaining: [3, 4], counts: [5, 5], quota: 8,
                                              first: 2, perLevel: 8, lethalAt: 3) { _, _ in false }
        XCTAssertEqual(known, [5, 0])
        // 探不成（CPU 份额用完 / 被取消）：到此为止，后面一条都不再探
        var n = 0
        let stopped = RDIceBreak.scheduleProbes(remaining: [1, 2], counts: [5, 5], quota: 32,
                                                first: 2, perLevel: 8) { _, _ in
            n += 1
            return n <= 2 ? false : nil
        }
        XCTAssertEqual(stopped, [2, 0])
        XCTAssertEqual(n, 3)
    }

    /// 订正验收 ④（口径 13）：鲨鱼在场时阿莱的战吼是两次 8，每一次单独看是不是致命 —— 搜出来的线和剩余血量。
    /// 局面：鲨鱼在场，手里两张 1 费阿莱（一张本回合用，一张留给下回合，所以下回合总是可斩，只看剩余血量）
    func testSharkAlexIsTwoEightsNotOneSixteen() throws {
        func position(mana: Int, enemy: Int) -> RDState {
            var s = root(mana: mana, maxMana: 9, enemy: enemy)
            minion(&s, .spiritOfTheShark)
            card(&s, .alexstrasza, cost: 1, copy: true)
            card(&s, .alexstrasza, cost: 1, copy: true)
            return s
        }
        func isAlexToFace(_ a: RDAction) -> Bool {
            if case .play(_, .alexstrasza, .enemyHero, _, _) = a { return true }
            return false
        }
        let swing = RDAction.attack(attacker: .friendlyHero, defender: .enemyHero)

        // 对方 9 血、1 费：第一个 8 照扣剩 1，第二个 8 触发 → 剩 1。（当成一次 16：16 ≥ 9 被挡，会算成剩 9）
        var r = solve(position(mana: 1, enemy: 9))
        XCTAssertEqual(r.verdict, .lethalNextTurn)
        assertBacked(r)
        XCTAssertEqual(r.remaining, 1)
        XCTAssertEqual(try XCTUnwrap(r.line).actions.count, 1)
        XCTAssertTrue(isAlexToFace(try XCTUnwrap(r.line).actions[0]))

        // 对方 16 血、1 费：第一个 8 照扣剩 8，第二个 8 刚好致命、触发 → 剩 8。（当成一次 16 会算成剩 16）
        r = solve(position(mana: 1, enemy: 16))
        XCTAssertEqual(r.verdict, .lethalNextTurn)
        assertBacked(r)
        XCTAssertEqual(r.remaining, 8)
        XCTAssertEqual(try XCTUnwrap(r.line).actions.count, 1)

        // 对方 17 血、1 费：两个 8 都不致命、都照扣，对方剩 1 血而冰还在；没有别的伤害了 → 破不了
        r = solve(position(mana: 1, enemy: 17))
        XCTAssertEqual(r.verdict, .cannotBreak)
        XCTAssertTrue(r.exhaustive)
        XCTAssertNil(r.line)

        // 对方 17 血、3 费：阿莱（剩 1，冰还在）→ 英雄技能 → 匕首攻脸，这 1 点才是触发的那一下 → 剩 1。
        // 冰是第 3 步碎的，不是阿莱那一步。（另一条：两张阿莱都下，第二张的第一个 8 触发，也剩 1、少一步，
        // 但下回合手里没阿莱了、只有匕首的 1 点 —— 同剩余时取下回合余量高一档的）
        r = solve(position(mana: 3, enemy: 17))
        XCTAssertEqual(r.verdict, .lethalNextTurn)
        assertBacked(r)
        XCTAssertEqual(r.remaining, 1)
        var line = try XCTUnwrap(r.line)
        XCTAssertEqual(line.actions.count, 3)
        XCTAssertTrue(isAlexToFace(line.actions[0]))
        XCTAssertEqual(Array(line.actions.suffix(2)), [.heroPower, swing])
        XCTAssertEqual(r.breakStep, 3)
        XCTAssertGreaterThanOrEqual(r.nextTurnDamage, 16)
        let bothAlex = try XCTUnwrap(r.candidates.first { $0.steps == 2 && $0.remaining == 1 }, "两张阿莱都下的那条")
        XCTAssertTrue(bothAlex.line.actions.allSatisfy(isAlexToFace))
        XCTAssertEqual(bothAlex.nextTurnDamage, 1, "下回合只剩匕首的 1 点：够斩（剩 1），但没有余量")

        // 对方 17 血、2 费：只够两张阿莱。第二张的第一个 8 ≥ 1 触发 → 剩 1；下回合靠英雄技能的 1 点斩
        r = solve(position(mana: 2, enemy: 17))
        XCTAssertEqual(r.verdict, .lethalNextTurn)
        assertBacked(r)
        XCTAssertEqual(r.remaining, 1)
        XCTAssertEqual(try XCTUnwrap(r.line).actions.count, 2)
        XCTAssertEqual(r.breakStep, 2)
        XCTAssertEqual(r.nextTurnDamage, 1)

        // 对方 16 血、3 费：多出来的 2 费先用匕首垫 1 点（剩 15），阿莱的第一个 8 照扣剩 7，第二个 8 触发 → 剩 7，
        // 比直接下阿莱（剩 8）低 1。垫的那一下必须在阿莱之前：反过来阿莱先把冰打掉，匕首就打在免疫上了
        r = solve(position(mana: 3, enemy: 16))
        XCTAssertEqual(r.verdict, .lethalNextTurn)
        assertBacked(r)
        XCTAssertEqual(r.remaining, 7)
        line = try XCTUnwrap(r.line)
        XCTAssertEqual(Array(line.actions.prefix(2)), [.heroPower, swing])
        XCTAssertTrue(isAlexToFace(line.actions[2]))
        XCTAssertEqual(r.breakStep, 3)
        XCTAssertTrue(r.candidates.contains { $0.remaining == 8 && $0.steps == 1 }, "直接下阿莱（剩 8）的也搜到了，排在后面")
    }

    /// 压血靠的是「零头伤害」（英雄技能的匕首、对脸的攻击），而搜索每个节点只展开先验最高的 14 个动作，英雄技能的先验
    /// 最低、最先被裁 —— 斩杀搜索不在乎那 1 点，破冰在乎。冰还在时这两类动作不受上限裁（`search` 里补回来）。
    /// 局面：对方 16 血、2 费。场上 6 个各不相同的随从，手里 3 张要指目标的 1 费牌（每张 6 个目标，共 18 个动作）
    /// + 一张 0 费阿莱。垫 1 点只能在第一步按英雄技能（2 费）：别的牌一打就只剩 1 费，按不了了。
    ///   直接下阿莱：剩 8。  英雄技能 → 匕首攻脸（15）→ 阿莱（剩 7，第二个 8 触发）：剩 7。两条下回合都可斩
    func testChipDamageIsNotCutByTheActionCap() throws {
        var s = root(mana: 2, maxMana: 9, enemy: 16)
        for c in [RDCard.spiritOfTheShark, .scabbsCutterbutter, .foxyFraud, .darkscaleBroodmother, .shadowcaster,
                  .etcBandManager] {
            minion(&s, c)
        }
        card(&s, .shadowstep, cost: 1)
        card(&s, .deafen, cost: 1)
        card(&s, .serratedBoneSpike, cost: 1)
        card(&s, .alexstrasza, cost: 0, copy: true)
        // 前提：根局面的动作数超过上限（否则这条测不到要测的东西）
        var listOptions = RDOptions.search
        listOptions.expandPlacements = false
        var dropped = false
        let rootActions = RDEngine.legalActions(try XCTUnwrap(RDIceBreak.armed(s)), options: listOptions,
                                                dropped: &dropped)
        XCTAssertGreaterThan(rootActions.count, try XCTUnwrap(Self.detConfig().maxActionsPerNode))
        XCTAssertTrue(rootActions.contains(.heroPower))

        let r = solve(s)
        XCTAssertEqual(r.verdict, .lethalNextTurn)
        assertBacked(r)
        XCTAssertEqual(r.remaining, 7, "英雄技能没被裁掉：先垫 1 点再下阿莱")
        let line = try XCTUnwrap(r.line)
        XCTAssertEqual(Array(line.actions.prefix(2)), [.heroPower, .attack(attacker: .friendlyHero, defender: .enemyHero)])
        XCTAssertEqual(line.actions.count, 3)
        XCTAssertEqual(r.breakStep, 3)
        XCTAssertTrue(r.candidates.contains { $0.remaining == 8 && $0.steps == 1 })
        // 不开破冰时动作上限照旧：同一个局面的斩杀搜索不受这条影响（16 血一张阿莱正好斩）
        XCTAssertTrue(RedDragonSearch.solve(s, config: RedDragonLiveReplayTests.deterministic).isLethal)
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
        waitForHostApp()
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
        /// 选中的线破冰后剩多少血：剩余血量 → 行数（两张表合计），① 和 ② 分开记
        var remainingOfLethal: [Int: Int] = [:]
        var remainingOfShort: [Int: Int] = [:]
        var notLowest = 0
        var cpuBudgetHits = 0
        /// 牌库里有和边牌同名的牌（幻觉药水 / 舞动 / 阿莱）的回合：Codex review P1 的局面在实战里会不会出现
        var sideboardNamedInDeck: [String] = []
        // 斩杀搜索只用来对照「能斩 ⇔ 能破冰」，不找缺件
        var lethalConfig = RedDragonLiveReplayTests.deterministic
        lethalConfig.enableMissingPieces = false
        /// 一个根局面跑一遍，记一行。`low` = 把对方血量改小的那张附表
        func run(_ name: String, line: Int, _ state: RDState, low: Bool) {
            var s = state
            if !low, RDCards.sideboardCards.contains(where: { s.deck.count($0) > 0 }) {
                sideboardNamedInDeck.append(name)
            }
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
            // 口径 11 / 12：搜到的破冰线里剩余血量最低到多少、一共几档，选中的是不是最低的那一档
            // （不是的话 = 更低的档探过、下回合斩不了，或者没排上探针）。再记它比最浅的破冰线多走了几步
            if let line = r.line, let lowest = r.candidates.map({ $0.remaining }).min(),
               let shallowest = r.candidates.map({ $0.steps }).min() {
                let levels = Set(r.candidates.map { $0.remaining }).count
                row += "｜候选 \(levels) 档、最低剩\(lowest)"
                if r.remaining > lowest {
                    let below = r.candidates.filter { $0.remaining < r.remaining }
                    row += "（更低的 \(below.count) 条里探过 \(below.filter { $0.probed }.count) 条，都斩不了）"
                    notLowest += 1
                }
                if r.verdict == .lethalNextTurn { remainingOfLethal[r.remaining, default: 0] += 1 }
                if r.verdict == .shortNextTurn { remainingOfShort[r.remaining, default: 0] += 1 }
                if line.actions.count > shallowest {
                    extraSteps.append(line.actions.count - shallowest)
                    row += "，最浅的破冰线 \(shallowest) 步"
                }
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
        func distribution(_ d: [Int: Int]) -> String {
            return d.isEmpty ? "无" : d.keys.sorted().map { "剩\($0)×\(d[$0] ?? 0)" }.joined(separator: " ")
        }
        print("T8SURVEY\n" + out.joined(separator: "\n")
            + "\n汇总：\(out.count) 个回合，\(summary(tally))"
            + "\nT8SURVEY-LOW（同一批局面，对方改成 12 血）\n" + lowOut.joined(separator: "\n")
            + "\n汇总：\(lowOut.count) 个回合，\(summary(lowTally))"
            + "\n两张表合计：最慢 \(String(format: "%.2f", maxCpu)) s，最多 \(maxStates) 态；撞 CPU 兜底 \(cpuBudgetHits) 次"
            + "\n斩杀搜索能斩（确定线）而破冰说破不了：\(lethalButCannotBreak)"
            + "\n斩杀搜索不斩而破冰说能破：\(breakWithoutLethal)"
            + "\n选中的线破冰后剩余血量的分布（剩N×行数，两张表合计）：① \(distribution(remainingOfLethal))；② \(distribution(remainingOfShort))"
            + "\n选中的不是候选里剩余最低那一档的有 \(notLowest) 行"
            + "\n选中的线比最浅的破冰线长的有 \(extraSteps.count) 行，各多 \(extraSteps.sorted()) 步"
            + "\n牌库里有和边牌同名的牌的回合：\(sideboardNamedInDeck.count) / \(out.count) \(sideboardNamedInDeck)")
        // 根局面（已当成有冰）打成字面量：给 scratchpad 里 `swiftc -O` 的基准和调闸门用。破不了的（三遍搜索跑满）
        // 取最慢的 6 个；破得了的（压血 + 准备步 + 探针）全打出来，按耗时降序
        for s in slow.filter({ !$0.broke }).prefix(6) + slow.filter({ $0.broke }) {
            print("T8ROOT \(s.name) \(String(format: "%.2f", s.cpu))s :: \(s.literal)")
        }
        XCTAssertGreaterThan(rows, 0)
        XCTAssertEqual(cpuBudgetHits, 0, "测试配置把 CPU 兜底放开了")
        XCTAssertTrue(lethalButCannotBreak.isEmpty, "能斩（不靠抽牌）就一定能破冰：致命的那一下就是破冰的那一下")
    }
}
