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
//  只碰引擎的测试在 Packages/RedDragonCore/Tests/RedDragonCoreTests/ 的同名文件里（`swift test` 直接跑）；
//  这里只留要 HSTracker 在场的（卡库、日志回放、文案、调度）。
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
        XCTAssertEqual(r.nextTurnDragons, RDIceBreak.dragons(next), file: file, line: line)
        if let nl = r.nextTurnLine {
            // 下回合线在它量的那种起手上重放：清场的（口径 15）或场面留着的
            let start = r.nextTurnBoardCleared ? RDIceBreak.cleared(next) : next
            XCTAssertFalse(hasRandomDraw(nl.actions, from: start), "下回合的线不靠随机抽牌", file: file, line: line)
            let ev = RDIceBreak.evidence(nl, on: start)
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

    // MARK: - 对法师实录（10-16，口径 15）

    /// 10-14 第 7 局（对法师，赢）、10-15 第 2 局（对法师，输）
    static let mageGames: [(String, Int)] = [("2026-10-14-g7-mage-won", 1), ("2026-10-15-g2-mage-lost", 2)]

    /// 用户实战里的误判（10-15 第 2 局 T15）：对方 37 血挂着冰，破冰线把手里的阿莱全用掉了，面板却报「剩 4、下回合 17 可斩」——
    /// 那 17 点是「鲨鱼 → E.T.C. 发现药水 → 复制场上的阿莱 → 1 费阿莱 16 + 匕首」，靠的是场上那条阿莱熬过对方回合。
    /// 实际对方回合又挂了一个冰（T17 对方 5 + 8 甲、奥秘 1），这局输了。口径 15 起下回合伤害只信手里的牌、
    /// 手里阿莱多的破法排在前面：这一回合不再报可斩。
    /// 对方真挂着奥秘的每个我方回合开头都跑一遍，打印 `MAGEDUMP`（结论、剩余、下回合手里几张阿莱、伤害、两条线）
    func testMageGamesIceBreak() throws {
        waitForHostApp()
        var rows: [String: RDIceBreakResult] = [:]
        for (fixture, pid) in Self.mageGames {
            let bs = RedDragonSetupTests.boundaries(lines: RedDragonFeedbackTests.lines(fixture), playerId: pid)
            var byTurn: [Int: [RedDragonFeedbackTests.Boundary]] = [:]
            for b in bs { byTurn[b.snapshot.turn, default: []].append(b) }
            for turn in byTurn.keys.sorted() {
                guard let all = byTurn[turn], let top = all.map({ $0.snapshot.resources }).max(),
                      let b = all.first(where: { $0.snapshot.resources == top && $0.snapshot.resourcesUsed == 0 })
                        ?? all.first(where: { $0.snapshot.resources == top }) else { continue }
                let s = RDStateReader.read(b.snapshot).state
                guard s.opponent.secretCount > 0 || s.opponent.immune else { continue }
                let r = RedDragonSearch.solveIceBreak(s, config: Self.detConfig())
                assertBacked(r)
                rows["\(fixture) T\(turn)"] = r
                var row = "\(fixture) T\(turn) 行\(b.line) 法力\(s.availableMana)/\(s.maxMana) 对方\(s.opponent.health)+\(s.opponent.armor)"
                    + " 奥秘\(s.opponent.secretCount) 手里龙\(RDIceBreak.dragons(s)) → \(r.verdict)"
                if let line = r.line, let next = r.nextTurnRoot {
                    row += " 剩\(r.remaining) 下回合手里龙\(r.nextTurnDragons) 伤害\(r.nextTurnDamage)"
                        + (r.nextTurnBoardCleared ? "（清场）" : "（不清场）")
                        + "\n  本回合：" + RDFormulaBuilder.formula(.preLaunch, line.actions, root: r.root).tokens
                        .map { RDText.formulaToken($0) }.joined(separator: " ")
                    if let nl = r.nextTurnLine {
                        let start = r.nextTurnBoardCleared ? RDIceBreak.cleared(next) : next
                        row += "\n  下回合：" + RDFormulaBuilder.formula(.preLaunch, nl.actions, root: start).tokens
                            .map { RDText.formulaToken($0) }.joined(separator: " ")
                    }
                }
                print("MAGEDUMP " + row)
            }
        }
        let t15 = try XCTUnwrap(rows["2026-10-15-g2-mage-lost T15"])
        XCTAssertNotEqual(t15.verdict, .cannotBreak, "这一回合破得了冰")
        // 原来报的那条（阿莱全用掉、下回合手里 0 张）不再排第一
        XCTAssertFalse(t15.verdict == .lethalNextTurn && t15.nextTurnDragons == 0 && t15.nextTurnDamage >= 16,
                       "不再报「下回合手里没阿莱、伤害 16+ 可斩」")
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
            + [("2026-10-13-g12-chain", 1)] + Self.mageGames
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
        /// ① 的行里稳斩（富余 ≥ `safeMargin`，口径 14）和不稳的
        let safeMargin = RDIceBreakConfig().safeMargin
        var safeRows = 0
        var unsafeRows: [String] = []
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
            // 口径 11 / 12 / 14：搜到的破冰线里剩余血量最低到多少、一共几档，选中的是不是最低的那一档
            // （不是的话 = 更低的档探过、下回合斩不了或不稳，或者没排上探针）。再记它比最浅的破冰线多走了几步
            if let line = r.line, let lowest = r.candidates.map({ $0.remaining }).min(),
               let shallowest = r.candidates.map({ $0.steps }).min() {
                let levels = Set(r.candidates.map { $0.remaining }).count
                row += "｜候选 \(levels) 档、最低剩\(lowest)"
                if r.remaining > lowest {
                    let below = r.candidates.filter { $0.remaining < r.remaining }
                    let probed = below.filter { $0.probed }
                    row += "（更低的 \(below.count) 条里探过 \(probed.count) 条，"
                        + "可斩不稳 \(probed.filter { $0.margin >= 0 }.count) 条，其余斩不了）"
                    notLowest += 1
                }
                if r.verdict == .lethalNextTurn {
                    remainingOfLethal[r.remaining, default: 0] += 1
                    if r.nextTurnDamage - r.remaining >= safeMargin { safeRows += 1 } else { unsafeRows.append(name) }
                }
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
            + "\n① 里稳斩（富余 ≥ \(safeMargin)）\(safeRows) 行、不稳 \(unsafeRows.count) 行 \(unsafeRows)"
            + "\n选中的不是候选里剩余最低那一档的有 \(notLowest) 行"
            + "\n选中的线比最浅的破冰线长的有 \(extraSteps.count) 行，各多 \(extraSteps.sorted()) 步"
            + "\n牌库里有和边牌同名的牌的回合：\(sideboardNamedInDeck.count) / \(out.count) \(sideboardNamedInDeck)")
        // 根局面（已当成有冰）打成字面量：给 scratchpad 里 `swiftc -O` 的基准、新旧对比和调闸门用。全部打出来，按耗时降序
        for s in slow {
            print("T8ROOT \(s.name) \(String(format: "%.2f", s.cpu))s :: \(s.literal)")
        }
        XCTAssertGreaterThan(rows, 0)
        XCTAssertEqual(cpuBudgetHits, 0, "测试配置把 CPU 兜底放开了")
        XCTAssertTrue(lethalButCannotBreak.isEmpty, "能斩（不靠抽牌）就一定能破冰：致命的那一下就是破冰的那一下")
    }
}
