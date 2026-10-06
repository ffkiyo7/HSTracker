//
//  RedDragonSetupTests.swift
//  HSTrackerTests
//
//  T4：阿莱对友方回血、打 / 回 16 与预启动准备线、危险回合的提示、「顺序」档完整公式的锁定。
//  两组公式表的逐行验证在 RedDragonFormulaTests（`testSetupLinesCoverHealAndPreLaunchRows`，用它的私有起手和重放）；
//  效果图在 RedDragonOverlayTests。
//

import XCTest
@testable import HSTracker
@testable import RedDragonCore

class RedDragonSetupTests: HSTrackerTests {

    override class func setUp() {
        super.setUp()
        if Cards.by(cardId: CardIds.Collectible.Rogue.Shadowstep) == nil {
            Database().loadDatabase(splashscreen: nil, withLanguages: [.enUS])
        }
    }

    // MARK: - 手工局面

    private func makeState(mana: Int, hand: [RDCard], board: [RDCard] = [], hero: Int = 10,
                           enemy: Int = 30, maxMana: Int = 10) -> RDState {
        var s = RDState(maxMana: maxMana, mana: mana, opponent: RDOpponent(health: enemy))
        for c in hand {
            s.hand.append(RDHandCard(entityId: s.takeEntityId(), card: c, isShadowOfDemise: c == .shadowOfDemise))
        }
        for c in board {
            let d = RDCards.def(c)
            s.board.append(RDBoardMinion(entityId: s.takeEntityId(), card: c, attack: d.attack, health: d.health,
                                         maxHealth: d.health, statsSetTo1x1: false, silenced: false,
                                         summoningSick: false, attacksThisTurn: 0, enchants: [],
                                         playOrder: s.takePlayOrder()))
        }
        s.heroHealth = hero
        s.heroMaxHealth = 30
        return s
    }

    private func alexPlay(_ s: RDState, target: RDTarget) -> RDAction {
        let alex = s.hand.first { $0.card == .alexstrasza }!
        return .play(entityId: alex.entityId, identity: .alexstrasza, target: target, choices: [])
    }

    // MARK: - 阿莱对友方回血

    /// 战吼对友方是治疗：无鲨鱼 8、鲨鱼下两次 16；回血封顶在血量上限，但「回了多少」按原始量记；对手一点不动
    func testAlexstraszaHealsOwnHero() throws {
        var s = makeState(mana: 9, hand: [.alexstrasza], hero: 10)
        var out = try RDEngine.apply(alexPlay(s, target: .friendlyHero), to: s)
        XCTAssertEqual(out.healedRaw, 8)
        XCTAssertEqual(out.heroHealth, 18)
        XCTAssertEqual(out.opponent.health, 30)
        XCTAssertEqual(out.damageDealt, 0)

        s = makeState(mana: 9, hand: [.alexstrasza], board: [.spiritOfTheShark], hero: 10)
        out = try RDEngine.apply(alexPlay(s, target: .friendlyHero), to: s)
        XCTAssertEqual(out.healedRaw, 16)
        XCTAssertEqual(out.heroHealth, 26)

        s = makeState(mana: 9, hand: [.alexstrasza], board: [.spiritOfTheShark], hero: 20)
        out = try RDEngine.apply(alexPlay(s, target: .friendlyHero), to: s)
        XCTAssertEqual(out.healedRaw, 16, "回血量按原始量记（「奶 16」看打了几次战吼）")
        XCTAssertEqual(out.heroHealth, 30, "实际血量封顶在上限")
    }

    /// 我方英雄只有阿莱能指；别的牌指它仍然非法
    func testOwnHeroIsOnlyATargetForAlexstrasza() {
        let s = makeState(mana: 9, hand: [.shadowstep, .scabbsCutterbutter], board: [.spiritOfTheShark])
        let step = s.hand[0]
        XCTAssertThrowsError(try RDEngine.apply(
            .play(entityId: step.entityId, identity: .shadowstep, target: .friendlyHero, choices: []), to: s))
    }

    /// 回血目标只在 `healFriendlyHero` 开着时才列进合法动作（斩杀搜索不受影响）
    func testHealTargetIsListedOnlyWhenAsked() {
        let s = makeState(mana: 9, hand: [.alexstrasza], board: [.spiritOfTheShark])
        func targets(_ o: RDOptions) -> [RDTarget] {
            var dropped = false
            return RDEngine.legalActions(s, options: o, dropped: &dropped).compactMap { a in
                if case .play(_, .alexstrasza, let t, _, _) = a { return t }
                return nil
            }
        }
        XCTAssertFalse(targets(.search).contains(.friendlyHero))
        var o = RDOptions.search
        o.healFriendlyHero = true
        XCTAssertTrue(targets(o).contains(.friendlyHero))
    }

    /// 斩杀搜索的结果不受回血改动影响：同一局面带不带回血选项，斩杀线逐条相同
    func testLethalSearchIgnoresHealing() {
        let s = makeState(mana: 9, hand: [.alexstrasza], board: [.spiritOfTheShark], enemy: 16)
        let r = RedDragonSearch.solve(s)
        XCTAssertTrue(r.isLethal)
        for line in r.lethalLines {
            for a in line.actions {
                if case .play(_, _, .friendlyHero, _, _) = a { XCTFail("斩杀线不会指自己英雄") }
            }
        }
    }

    // MARK: - 准备线搜索

    /// 鲨鱼在场、9 费、阿莱在手：一步奶 16
    func testHealSearchFindsOneStepLine() throws {
        let s = makeState(mana: 9, hand: [.alexstrasza], board: [.spiritOfTheShark])
        let r = RedDragonSearch.solveSetup(s, goal: .heal16)
        let line = try XCTUnwrap(r.setupLines.first)
        XCTAssertEqual(line.actions.count, 1)
        XCTAssertEqual(line.healed, 16)
        let end = try RDReplay.run(line.actions, from: s).finalState
        XCTAssertEqual(end.healedRaw, 16)
        guard case .play(_, .alexstrasza, .friendlyHero, _, _) = line.actions[0] else {
            return XCTFail("应该是阿莱指向我方英雄")
        }
        let advice = RDHintBuilder.setupAdvice(result: r, goal: .heal16, root: s)
        XCTAssertEqual(advice?.kind, .heal16)
        XCTAssertEqual(advice?.formula?.tokens.map { RDText.formulaToken($0) }, ["龙-奶0"])
    }

    /// 没有鲨鱼、凑不出第二次战吼：奶 16 凑不出 → 等死
    func testHealSearchGivesDoomedWhenImpossible() {
        let s = makeState(mana: 9, hand: [.alexstrasza], board: [])
        let r = RedDragonSearch.solveSetup(s, goal: .heal16)
        XCTAssertTrue(r.setupLines.isEmpty)
        XCTAssertEqual(RDHintBuilder.setupAdvice(result: r, goal: .heal16, root: s)?.kind, .doomed)
    }

    /// 准备线都不靠随机抽牌（发现是自己选的，不算）
    func testSetupLinesNeverDependOnRandomDraws() {
        let s = makeState(mana: 10, hand: [.alexstrasza, .digForTreasure, .spiritOfTheShark, .swindle])
        let r = RedDragonSearch.solveSetup(s, goal: .heal16)
        for line in r.setupLines {
            for a in line.actions {
                for c in a.choices {
                    if case .pick(let card) = c {
                        XCTAssertTrue(RDCards.sideboardCards.contains(card), "准备线里不该有随机抽牌")
                    }
                }
            }
        }
    }

    // MARK: - 公式文字

    func testFormulaTokenText() {
        func t(_ kind: RDFormulaToken.Kind, _ card: RDCard?, _ mana: Int, _ target: RDFormulaTarget? = nil,
               original: Bool = false, draws: [RDCard] = []) -> RDFormulaToken {
            return RDFormulaToken(kind: kind, card: card, original: original, mana: mana, target: target, draws: draws)
        }
        XCTAssertEqual(RDText.formulaToken(t(.play, .spiritOfTheShark, 4)), "鱼4")
        XCTAssertEqual(RDText.formulaToken(t(.play, .serratedBoneSpike, 2, .card(.foxyFraud))), "骨-狐2")
        XCTAssertEqual(RDText.formulaToken(t(.play, .alexstrasza, 0, .enemyHero)), "龙0", "对脸不写目标（公式表惯例）")
        XCTAssertEqual(RDText.formulaToken(t(.play, .alexstrasza, 0, .ownHero)), "龙-奶0")
        XCTAssertEqual(RDText.formulaToken(t(.play, .shadowstep, 1, .card(.etcBandManager), original: true)),
                       "步（殒）-牛1", "殒命暗影写它变成的那张牌的缩写 +（殒）")
        var etc = t(.play, .etcBandManager, 1)
        etc.picks = [.alexstrasza, .bounceAround]
        XCTAssertEqual(RDText.formulaToken(etc), "牛（龙舞）1", "乐队经理拿的牌写在括号里")
        XCTAssertEqual(RDText.formulaPicks(etc), "（龙舞）")
        XCTAssertEqual(RDText.formulaToken(t(.attack, .scabbsCutterbutter, 0, .enemyHero)), "刀攻脸")
        XCTAssertEqual(RDText.formulaToken(t(.attack, nil, 0, .enemyMinion)), "英攻怪")
        XCTAssertEqual(RDText.formulaNote(t(.play, .digForTreasure, 1, draws: [.alexstrasza])), "抽到龙才继续")
        XCTAssertEqual(RDText.formulaNote(t(.play, .goneFishin, 1)), "看结果后重算")
        XCTAssertNil(RDText.formulaNote(t(.play, .spiritOfTheShark, 4)))
    }

    /// 沿线推出来的每步剩余法力和公式表同款写法一致：表第一行 32 公式的开头「鱼4 狐2 刀2」
    /// （8 费、4 水晶、手里有鱼狐刀）
    func testBuilderWritesTheTableNotation() throws {
        var s = RDState(maxMana: 4, mana: 8, opponent: RDOpponent(health: 400))
        for c in [RDCard.spiritOfTheShark, .foxyFraud, .scabbsCutterbutter] {
            s.hand.append(RDHandCard(entityId: s.takeEntityId(), card: c))
        }
        var cur = s
        var actions: [RDAction] = []
        for card in [RDCard.spiritOfTheShark, .foxyFraud, .scabbsCutterbutter] {
            let h = cur.hand.first { $0.card == card }!
            let a = RDAction.play(entityId: h.entityId, identity: card, target: .none, choices: [])
            cur = try RDEngine.apply(a, to: cur)
            actions.append(a)
        }
        let f = RDFormulaBuilder.formula(.lethal, actions, root: s)
        XCTAssertEqual(f.tokens.map { RDText.formulaToken($0) }.joined(separator: " "), "鱼4 狐2 刀2")
        XCTAssertEqual(RDOverlayModel.pieces(f).map { $0.state }, [.next, .pending, .pending])
    }

    // MARK: - 危险回合的提示（逐回合调查）

    static func boundaries(lines: [String], playerId: Int) -> [RedDragonFeedbackTests.Boundary] {
        let game = RedDragonFeedbackTests.makeGame(playerId: playerId)
        var byPass: [Int: [RedDragonFeedbackTests.Boundary]] = [:]
        var topBlock = ""
        var wasIdle = true
        RedDragonFeedbackTests.replayWithRewinds(lines, game: game, playerId: playerId, assistant: nil) { n, pass, parser in
            let line = lines[n - 1]
            if wasIdle && line.contains("BLOCK_START") { topBlock = line }
            let idle = parser.currentBlock == nil
            defer { wasIdle = idle }
            guard idle, line.contains("BLOCK_END") || line.contains("tag=STEP value=MAIN_ACTION"),
                  RDGameSnapshot.playerEntity(game: game)?.isCurrentPlayer == true,
                  let snap = RDGameSnapshot.capture(game: game) else { return }
            if let last = byPass[pass]?.last, last.snapshot == snap { return }
            byPass[pass, default: []].append(RedDragonFeedbackTests.Boundary(
                line: n, block: line.contains("BLOCK_END") ? topBlock : "", snapshot: snap))
        }
        return byPass[byPass.keys.max() ?? 0] ?? []
    }

    /// 一个边界上线上会给的完整提示：判定 + （斩不了且危险时）奶 16 / 等死
    struct Advice {
        var analysis: RDAnalysis
        var setup: RedDragonResult?
        var live: RDLiveState
        var lethalResult: RedDragonResult
        var setupCpu = 0.0
        var kind: String {
            if analysis.isLethal { return "斩杀线" }
            guard analysis.boardDanger else { return "不危险·无提示" }
            switch analysis.setup?.kind {
            case .heal16?: return "奶16 \(analysis.setup?.formula?.tokens.count ?? 0) 步"
            case .doomed?: return "等死"
            case .preLaunch?: return "预启动"
            case nil: return "危险·无准备建议"
            }
        }
    }

    static func advise(_ b: RedDragonFeedbackTests.Boundary, config: RedDragonConfig) -> Advice {
        let live = RDStateReader.read(b.snapshot)
        let r = RedDragonSearch.solve(live.state, config: config)
        var a = RDHintBuilder.analyze(snapshot: b.snapshot, live: live, result: r, cardName: { $0 })
        var setup: RedDragonResult?
        var cpu = 0.0
        if !a.isLethal && a.boardDanger {
            let s = RedDragonSearch.solveSetup(live.state, goal: .heal16, config: config)
            setup = s
            cpu = s.cpuTime
            a.setup = RDHintBuilder.setupAdvice(result: s, goal: .heal16, root: live.state)
        }
        return Advice(analysis: a, setup: setup, live: live, lethalResult: r, setupCpu: cpu)
    }

    static func detConfig() -> RedDragonConfig {
        var c = RedDragonLiveReplayTests.deterministic
        c.setupCpuBudget = 1e9
        return c
    }

    /// 各局的我方回合：每个危险回合给了什么提示。要读真实 Power.log 时设 `RD_T4_POWER_LOG`（路径）；
    /// 默认只跑 fixture（10-01 四局 + 10-05 五局）。打印逐回合表，断言只管「危险回合斩得了先斩、准备线都重放过」
    func testDangerTurnSurvey() throws {
        var games: [(name: String, lines: [String], playerId: Int)] = []
        let fixtures: [(String, Int)] = [("2026-10-01-g2-bounce-overflow", 1), ("2026-10-01-g3-lost", 1),
                                         ("2026-10-01-g4-second", 2), ("2026-10-01-g5-first", 1)]
            + RedDragonFeedbackTests.games.map { ($0.fixture, $0.playerId) }
        for (f, pid) in fixtures {
            games.append((f, RedDragonFeedbackTests.lines(f), pid))
        }
        if let path = ProcessInfo.processInfo.environment["RD_T4_POWER_LOG"],
           let text = try? String(contentsOfFile: path, encoding: .utf8) {
            let all = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            let starts = all.indices.filter { all[$0].contains("GameState.DebugPrintPower() - CREATE_GAME") }
            let pids = [1, 2, 1, 2, 1, 1, 2]
            for (i, s) in starts.enumerated() where i < pids.count {
                let e = i + 1 < starts.count ? starts[i + 1] : all.count
                games.append(("Power.log 第 \(i + 1) 局", Array(all[s..<e]), pids[i]))
            }
        }
        var out: [String] = []
        var dangerTurns = 0, healed = 0, doomed = 0, lethalFirst = 0
        var maxSetupCpu = 0.0
        for g in games {
            let bs = Self.boundaries(lines: g.lines, playerId: g.playerId)
            var byTurn: [Int: [RedDragonFeedbackTests.Boundary]] = [:]
            for b in bs { byTurn[b.snapshot.turn, default: []].append(b) }
            for turn in byTurn.keys.sorted() {
                let danger = byTurn[turn]!.filter { RDHintBuilder.isDanger($0.snapshot) }
                guard !danger.isEmpty else { continue }
                dangerTurns += 1
                // 回合开始（第一个边界）+ 最后一个危险边界；中间每个危险边界只在提示变了时记
                var lastKind = ""
                for b in danger {
                    let adv = Self.advise(b, config: Self.detConfig())
                    maxSetupCpu = max(maxSetupCpu, adv.setupCpu)
                    if adv.analysis.isLethal == false, adv.analysis.boardDanger {
                        if adv.analysis.setup?.kind == .heal16 { healed += 1 } else { doomed += 1 }
                    } else if adv.analysis.isLethal { lethalFirst += 1 }
                    // 准备线都重放过：不靠随机、真能回满 16
                    if let line = adv.setup?.setupLines.first {
                        let end = try? RDReplay.run(line.actions, from: adv.live.state, options: .search).finalState
                        XCTAssertGreaterThanOrEqual(end?.healedRaw ?? 0, 16, "\(g.name) T\(turn) 行\(b.line)")
                    }
                    let s = b.snapshot
                    let kind = adv.kind
                    if kind != lastKind || b.line == danger.first!.line {
                        out.append("\(g.name) T\(turn) 行\(b.line) 血\(s.heroHealth)+\(s.heroArmor) 对方场攻\(s.opponentBoardDamage)"
                            + " 死于场面\(s.deadToBoard) → 判定 \(adv.analysis.verdict) → \(kind)"
                            + (adv.analysis.setup?.formula.map { "：" + $0.tokens.map { RDText.formulaToken($0) }.joined(separator: " ") } ?? ""))
                        lastKind = kind
                    }
                }
            }
        }
        print("T4SURVEY\n" + out.joined(separator: "\n")
            + "\n汇总：危险回合 \(dangerTurns)，其中危险边界上 斩杀 \(lethalFirst) / 奶16 \(healed) / 等死 \(doomed)；"
            + "准备线搜索最慢 \(String(format: "%.2f", maxSetupCpu)) s")
    }

    // MARK: - 锁定（顺序档完整公式）的逐步结论

    struct LockRow {
        var turn: Int
        var line: Int
        var block: String
        var status: String
    }

    /// 和助手同一套规则的离线模拟：每个边界核对锁定的线（`RDContinuation.advance`，不搜索），在线上就记已走几步，
    /// 走不通记「偏离」再搜新线锁定。返回逐边界结论，并断言「锁定的线在真实局面上重放都能走到底」
    static func simulateLock(_ bs: [RedDragonFeedbackTests.Boundary], config: RedDragonConfig,
                             file: StaticString = #filePath, line: UInt = #line) -> [LockRow] {
        struct Lock {
            var turn: Int
            var goal: RDFormula.Goal
            var candidates: [(root: RDState, line: RedDragonLine)]
            var done: Int
            var total: Int
        }
        var rows: [LockRow] = []
        var lock: Lock?
        func lockNew(_ b: RedDragonFeedbackTests.Boundary) -> String {
            let adv = advise(b, config: config)
            if adv.analysis.isLethal {
                let lines = adv.lethalResult.lethalLines.filter {
                    !RDLineWalker.dependsOnDraw($0.actions, root: adv.live.state)
                }
                guard !lines.isEmpty else { return "有斩杀线但都靠抽牌（不锁定）" }
                lock = Lock(turn: b.snapshot.turn, goal: .lethal, candidates: lines.map { (adv.live.state, $0) },
                            done: 0, total: lines[0].actions.count)
                return "锁定斩杀线 \(lines[0].actions.count) 步（候选 \(lines.count) 条）"
            }
            if adv.analysis.boardDanger, let s = adv.setup, !s.setupLines.isEmpty {
                lock = Lock(turn: b.snapshot.turn, goal: .heal16, candidates: s.setupLines.map { (adv.live.state, $0) },
                            done: 0, total: s.setupLines[0].actions.count)
                return "锁定奶16 \(s.setupLines[0].actions.count) 步"
            }
            return adv.analysis.boardDanger ? "危险·等死" : "无斩杀线"
        }
        for b in bs {
            let blockName = RedDragonFeedbackTests.blockCard(b.block)
            if let l = lock, l.turn != b.snapshot.turn { lock = nil }
            guard var l = lock else {
                rows.append(LockRow(turn: b.snapshot.turn, line: b.line, block: blockName, status: lockNew(b)))
                continue
            }
            let live = RDStateReader.read(b.snapshot)
            let adv = RDContinuation.advance(l.candidates, onto: live.state, goal: l.goal, tolerant: true)
            if let first = adv.first {
                // 锁定的线在真实局面上必须真能走到底（斩杀线打死对手；奶 16 回满）
                for item in adv {
                    guard let out = try? RDReplay.run(item.resumed.line.actions, from: item.resumed.root) else {
                        XCTFail("锁定的线重放不过 行\(b.line)", file: file, line: line)
                        continue
                    }
                    if l.goal == .lethal {
                        XCTAssertLessThanOrEqual(out.finalState.opponent.health, 0, "行\(b.line)", file: file, line: line)
                    } else {
                        XCTAssertGreaterThanOrEqual(out.finalState.healedRaw, 16, "行\(b.line)", file: file, line: line)
                    }
                }
                l.done += first.resumed.stepsTaken
                l.candidates = adv.map { ($0.resumed.root, $0.resumed.line) }
                lock = l
                rows.append(LockRow(turn: b.snapshot.turn, line: b.line, block: blockName,
                                    status: "仍在线上（已走 \(l.done)/\(l.total)）"))
            } else {
                let diag = nearest(l.candidates, live.state)
                lock = nil
                let result = lockNew(b)
                rows.append(LockRow(turn: b.snapshot.turn, line: b.line, block: blockName,
                                    status: "偏离[\(diag)] → 重算：" + result))
            }
        }
        return rows
    }

    /// 锁定回放表里「偏离」的依据：最接近的 (候选, k) 在哪些检查上对不上
    static func mismatchNames(_ p: RDState, _ r: RDState) -> [String] {
        var out: [String] = []
        func chk(_ ok: Bool, _ name: String) { if !ok { out.append(name) } }
        chk(p.mana == r.mana, "mana \(p.mana)/\(r.mana)")
        chk(p.tempMana == r.tempMana, "temp \(p.tempMana)/\(r.tempMana)")
        chk(p.maxMana == r.maxMana, "maxMana")
        chk(p.cardsPlayedThisTurn == r.cardsPlayedThisTurn, "cardsPlayed \(p.cardsPlayedThisTurn)/\(r.cardsPlayedThisTurn)")
        chk(p.spellDamage == r.spellDamage, "spellDamage")
        chk(p.heroAttackedThisTurn == r.heroAttackedThisTurn, "heroAttacked")
        chk(p.heroPowerUsed == r.heroPowerUsed, "heroPower")
        chk(p.layers == r.layers, "layers \(p.layers.map { "\($0.amount)x\($0.slots)" })/\(r.layers.map { "\($0.amount)x\($0.slots)" })")
        chk(p.sideboard.map({ $0.rawValue }).sorted() == r.sideboard.map({ $0.rawValue }).sorted(), "sideboard \(p.sideboard.map { RDText.abbr($0) })/\(r.sideboard.map { RDText.abbr($0) })")
        chk(p.deck.counts == r.deck.counts, "deck")
        chk(p.opponent.health == r.opponent.health && p.opponent.armor == r.opponent.armor, "oppHealth \(p.opponent.health)/\(r.opponent.health)")
        chk(p.hand.count == r.hand.count, "hand.count \(p.hand.count)/\(r.hand.count)")
        chk(p.board.count == r.board.count, "board.count \(p.board.count)/\(r.board.count)")
        chk(p.opponent.board.count == r.opponent.board.count, "oppBoard.count \(p.opponent.board.count)/\(r.opponent.board.count)")
        if p.board.count == r.board.count {
            chk(p.boardIndicesByPlayOrder() == r.boardIndicesByPlayOrder(), "playOrder \(p.boardIndicesByPlayOrder())/\(r.boardIndicesByPlayOrder())")
            for (i, (a, b)) in zip(p.board, r.board).enumerated() {
                chk(a.card == b.card, "board[\(i)].card \(RDText.abbr(a.card))/\(RDText.abbr(b.card))")
                chk(a.attack == b.attack && a.health == b.health, "board[\(i)].stats \(a.attack)/\(a.health) vs \(b.attack)/\(b.health)")
                chk(a.maxHealth == b.maxHealth, "board[\(i)].maxHealth")
                chk(a.statsSetTo1x1 == b.statsSetTo1x1, "board[\(i)].1x1")
                chk(a.summoningSick == b.summoningSick, "board[\(i)].sick")
                chk(a.attacksThisTurn == b.attacksThisTurn, "board[\(i)].attacks")
                chk(a.silenced == b.silenced, "board[\(i)].silenced")
            }
        }
        var unused = Array(r.hand.indices)
        var handMiss: [String] = []
        for a in p.hand {
            if let j = unused.firstIndex(where: { r.hand[$0].card == a.card && r.hand[$0].isShadowOfDemise == a.isShadowOfDemise
                && r.hand[$0].statsOverride == a.statsOverride && r.cost(of: r.hand[$0], as: a.card) == p.cost(of: a, as: a.card) }) {
                unused.remove(at: j)
            } else {
                handMiss.append("\(RDText.abbr(a.card))\(p.cost(of: a, as: a.card))")
            }
        }
        chk(handMiss.isEmpty, "hand 缺 \(handMiss) 多 \(unused.map { RDText.abbr(r.hand[$0].card) + "\(r.cost(of: r.hand[$0], as: r.hand[$0].card))" })")
        return out
    }

    /// 偏离定因用：逐步推演，找对应成立的那一步，说清剩下的线在真实局面上卡在哪；都对应不上就把
    /// `mismatchNames` 不看的项（手牌附魔链、对手场面等）在最接近的那步打出来
    static func deepDiff(_ c: (root: RDState, line: RedDragonLine), _ real: RDState) -> String {
        var p = c.root
        var closest: (Int, Int, RDState)?
        for k in 0...c.line.actions.count {
            if k > 0 {
                guard let n = try? RDEngine.apply(c.line.actions[k - 1], to: p) else { break }
                p = n
            }
            if let map = RDContinuation.correspondence(p, real, tolerant: true) {
                var start = real
                start.nextEntityId = p.nextEntityId
                start.healedRaw = p.healedRaw
                let ids = real.hand.map { $0.entityId } + real.board.map { $0.entityId }
                guard ids.allSatisfy({ $0 < p.nextEntityId }) else { return "k=\(k) 对应成立，真实编号撞号" }
                let rest = c.line.actions[k...].map { RDContinuation.translate($0, map, generatedFrom: p.nextEntityId) }
                var s = start
                for (i, a) in rest.enumerated() {
                    do { s = try RDEngine.apply(a, to: s) } catch {
                        return "k=\(k) 对应成立，重放卡在剩余第 \(i + 1) 步 \(a)：\(error)"
                    }
                }
                return "k=\(k) 对应成立，重放走完，对手 \(s.opponent.health)，靠抽牌 \(RDLineWalker.dependsOnDraw(Array(rest), root: start))"
            }
            let m = mismatchNames(p, real).count
            if closest == nil || m < closest!.1 { closest = (k, m, p) }
        }
        guard let (k, _, q) = closest else { return "无" }
        func hand(_ s: RDState) -> String {
            return s.hand.map { "\(RDText.abbr($0.card)){\($0.enchants) o\(String(describing: $0.printedCostOverride)) n\($0.enteredHandThisTurn) p\($0.pool.count)}" }
                .sorted().joined(separator: " ")
        }
        return "k=\(k) 对应不成立。推演手[\(hand(q))] 真实手[\(hand(real))]"
            + " 对手场 \(q.opponent.board.map { "\($0.attack)/\($0.health)" })/\(real.opponent.board.map { "\($0.attack)/\($0.health)" })"
            + " 冻 \(q.heroFrozen)/\(real.heroFrozen) 彗 \(q.luckyCometCharges)/\(real.luckyCometCharges)"
            + " 奥秘 \(q.secretsInPlay.count)/\(real.secretsInPlay.count) 对手奥秘 \(q.opponent.secretCount)/\(real.opponent.secretCount)"
            + " 血 \(q.heroHealth)/\(real.heroHealth) 已奶 \(q.healedRaw) 截抽 \(q.truncatedDraws)"
            + " 上限 \(q.boardLimit),\(q.handLimit)/\(real.boardLimit),\(real.handLimit)"
    }

    static func nearest(_ cands: [(root: RDState, line: RedDragonLine)], _ real: RDState) -> String {
        var best: (Int, String)?
        for (ci, c) in cands.enumerated() {
            var p = c.root
            for k in 0...c.line.actions.count {
                if k > 0 {
                    guard let n = try? RDEngine.apply(c.line.actions[k - 1], to: p) else { break }
                    p = n
                }
                let m = mismatchNames(p, real)
                if best == nil || m.count < best!.0 {
                    best = (m.count, "cand\(ci) k=\(k) \(m)")
                }
            }
        }
        return best?.1 ?? "无候选"
    }

    /// 线上流程（「顺序」档锁定）：g2 T13 照线打的每一步在 1 秒内提交（去抖设 3 秒，证明没走去抖 + 搜索）；
    /// 锁定期间不出现「过时」、已走步数只增不减、最后确实锁到了较深的步数
    func testAssistantLocksTheFormulaAndFollowsWithoutStaleness() {
        let debounce: TimeInterval = 3
        let lines = RedDragonFeedbackTests.lines("2026-10-05-g2-dance-lost")
        let game = RedDragonFeedbackTests.makeGame(playerId: 2)
        let assistant = RedDragonAssistant(
            environment: RedDragonFeedbackTests.environment(debounce: debounce, reveal: .order), recordsFeeds: true)
        var scheduled = 0
        var followedLatencies: [TimeInterval] = []
        var dones: [Int] = []
        var lockedStale = 0, lockedCommits = 0
        let token = assistant.subscribe { h in
            if h.locked {
                lockedCommits += 1
                if h.isStale { lockedStale += 1 }
                if let d = h.analysis?.formula?.done { dones.append(d) }
            }
        }
        defer { assistant.unsubscribe(token) }
        RedDragonFeedbackTests.replayWithRewinds(lines, game: game, playerId: 2, assistant: assistant) { _, _, parser in
            guard parser.currentBlock == nil, (game.gameEntity?[.turn] ?? 0) == 13 else { return }
            let hooked = Date()
            let committed = assistant.committedComputations
            let followed = assistant.followedComputations
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.002))
            let newlyScheduled = assistant.scheduledComputations > scheduled
            if newlyScheduled { scheduled = assistant.scheduledComputations }
            // 锁定时新局面不标「正在算」，光看 phase 等不到跟随的结果：下一行一喂，上一次的结果就被作废了
            // （线上两个边界至少隔几百毫秒，测试里是连着喂的）。所以等到这次计算真的提交
            let deadline = Date().addingTimeInterval(15)
            while Date() < deadline
                    && (assistant.hint.phase == .computing || (assistant.hint.isStale && !assistant.hint.locked)
                        || (newlyScheduled && assistant.committedComputations == committed)) {
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.002))
            }
            // 在这里量，不在订阅回调里量：跟随的结果和上一次一样时不发布（`publish` 去重），回调不会来，
            // 耗时会被错记到后面那次去抖搜索上
            if newlyScheduled, assistant.followedComputations > followed {
                followedLatencies.append(Date().timeIntervalSince(hooked))
            }
        }
        XCTAssertGreaterThan(lockedCommits, 5, "T13 的斩杀线要被锁定并持续提交")
        XCTAssertEqual(lockedStale, 0, "锁定期间不出现「过时」")
        // 一次锁定内已走步数只增不减（偏离后重锁会归零，按段看）
        var maxDone = 0
        var segmentsOk = true
        var prev = 0
        for d in dones {
            if d < prev { segmentsOk = segmentsOk && d == 0 }
            prev = d
            maxDone = max(maxDone, d)
        }
        XCTAssertTrue(segmentsOk, "已走步数只增不减（重锁归零除外）：\(dones)")
        XCTAssertGreaterThanOrEqual(maxDone, 8, "照线打到第 8 步以后仍在线上：\(dones)")
        XCTAssertFalse(followedLatencies.isEmpty)
        XCTAssertLessThan(followedLatencies.max() ?? 0, 1, "锁定跟随不等去抖（\(debounce) 秒）")
        print("T4PIPE 锁定提交 \(lockedCommits) 次，跟随 \(followedLatencies.count) 次，最慢 "
              + String(format: "%.3f", followedLatencies.max() ?? 0) + " s，已走步数最大 \(maxDone)")
    }

    /// 10-05 五局：每个有锁定线的回合，逐边界的结论；打印表，断言锁定的线都能走到底（没有「显示的线已走不通却没标偏离」）
    func testLockReplayOnFiveFixtures() {
        var out: [String] = []
        var onLine = 0, deviated = 0
        for g in RedDragonFeedbackTests.games {
            let bs = Self.boundaries(lines: RedDragonFeedbackTests.lines(g.fixture), playerId: g.playerId)
            let rows = Self.simulateLock(bs, config: Self.detConfig())
            var currentTurn = -1
            for r in rows {
                guard r.status.hasPrefix("锁定") || r.status.hasPrefix("仍在线上") || r.status.hasPrefix("偏离")
                        || currentTurn == r.turn else { continue }
                if r.status.hasPrefix("锁定") { currentTurn = r.turn }
                if r.status.hasPrefix("仍在线上") { onLine += 1 }
                if r.status.hasPrefix("偏离") { deviated += 1 }
                guard currentTurn == r.turn else { continue }
                out.append("\(g.fixture) T\(r.turn) 行\(r.line) \(r.block) → \(r.status)")
            }
        }
        print("T4LOCK\n" + out.joined(separator: "\n") + "\n汇总：仍在线上 \(onLine)，偏离 \(deviated)")
        XCTAssertGreaterThan(onLine, 20)
    }

    /// 实测反馈用：任意一局的锁定回放（每次锁定带完整公式）。`RD_T4_LOCK_LOG` = 单局 Power.log 路径，
    /// `RD_T4_LOCK_PID` = 我方 PlayerID；没设就跳过
    func testLockReplayOnExternalLog() throws {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["RD_T4_LOCK_LOG"], let pid = Int(env["RD_T4_LOCK_PID"] ?? ""),
              let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            throw XCTSkip("没设 RD_T4_LOCK_LOG / RD_T4_LOCK_PID")
        }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let bs = Self.boundaries(lines: lines, playerId: pid)
        var out: [String] = []
        var lock: [(root: RDState, line: RedDragonLine)] = []
        var lockTurn = -1
        for b in bs {
            let s = b.snapshot
            let live = RDStateReader.read(s)
            let head = "T\(s.turn) 行\(b.line) \(RedDragonFeedbackTests.blockCard(b.block)) 费\(live.state.mana)+\(live.state.tempMana)"
                + " 对手\(live.state.opponent.health)+\(live.state.opponent.armor) 我\(s.heroHealth)+\(s.heroArmor) 对方场攻\(s.opponentBoardDamage)"
                + " 手[\(live.state.hand.map { RDText.abbr($0.card) + "\(live.state.cost(of: $0, as: $0.card))" }.joined(separator: " "))]"
                + " 场[\(live.state.board.map { RDText.abbr($0.card) }.joined(separator: " "))]"
            if lockTurn == s.turn, !lock.isEmpty {
                let adv = RDContinuation.advance(lock, onto: live.state, goal: .lethal, tolerant: true)
                if let first = adv.first {
                    lock = adv.map { ($0.resumed.root, $0.resumed.line) }
                    out.append(head + " → 仍在线上（+\(first.resumed.stepsTaken)，剩 \(first.resumed.line.actions.count)）")
                    continue
                }
                out.append(head + " → 偏离[\(Self.nearest(lock, live.state))]")
                lock = []
            }
            let adv = Self.advise(b, config: Self.detConfig())
            let lethal = adv.lethalResult.lethalLines.filter { !RDLineWalker.dependsOnDraw($0.actions, root: live.state) }
            if adv.analysis.isLethal, let l = lethal.first {
                lock = lethal.map { (live.state, $0) }
                lockTurn = s.turn
                let f = RDFormulaBuilder.formula(.lethal, l.actions, root: live.state)
                out.append(head + " → 锁定斩杀（候选 \(lethal.count)）：" + f.tokens.map { RDText.formulaToken($0) }.joined(separator: " "))
            } else {
                out.append(head + " → 判定 \(adv.analysis.verdict) / \(adv.kind)"
                    + (adv.analysis.setup?.formula.map { "：" + $0.tokens.map { RDText.formulaToken($0) }.joined(separator: " ") } ?? ""))
            }
        }
        print("T4EXT\n" + out.joined(separator: "\n"))
    }

    /// 偏离定因用：多局批量回放，口径同线上锁定（只认屏上那条公式）。`RD_T4_LOCK_LIST` = 清单文件，
    /// 每行「单局 Power.log 路径 + 空格 + 我方 PlayerID」；没设就跳过。偏离时打印公式该打哪步、实际打了什么、
    /// 最接近的推演局面差在哪几项
    func testLockReplayOnLogList() throws {
        guard let listPath = ProcessInfo.processInfo.environment["RD_T4_LOCK_LIST"],
              let list = try? String(contentsOfFile: listPath, encoding: .utf8) else {
            throw XCTSkip("没设 RD_T4_LOCK_LIST")
        }
        let launched = Date().addingTimeInterval(30)
        while AppDelegate.instance().coreManager == nil && Date() < launched {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        var out: [String] = []
        for entry in list.split(separator: "\n") {
            let parts = entry.split(separator: " ")
            guard parts.count == 2, let pid = Int(parts[1]),
                  let text = try? String(contentsOfFile: String(parts[0]), encoding: .utf8) else { continue }
            out.append("== \(parts[0])")
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            var lock: [(root: RDState, line: RedDragonLine)] = []
            var tokens: [RDFormulaToken] = []
            var done = 0
            var lockTurn = -1
            for b in Self.boundaries(lines: lines, playerId: pid) {
                let s = b.snapshot
                let live = RDStateReader.read(s)
                let played = RedDragonFeedbackTests.blockCard(b.block)
                let head = "T\(s.turn) 行\(b.line) \(played) 费\(live.state.mana)+\(live.state.tempMana)"
                    + " 场[\(live.state.board.map { RDText.abbr($0.card) }.joined(separator: " "))]"
                if lockTurn == s.turn, !lock.isEmpty {
                    let adv = RDContinuation.advance(lock, onto: live.state, goal: .lethal, tolerant: true)
                    if let first = adv.first {
                        lock = adv.map { ($0.resumed.root, $0.resumed.line) }
                        done += first.resumed.stepsTaken
                        out.append(head + " → 在线上 \(done)/\(tokens.count)")
                        continue
                    }
                    guard live.state.opponent.health > 0 else { continue }
                    let expected = done < tokens.count ? tokens[done] : nil
                    let playedCard = played.split(separator: ":").last.flatMap { RDCards.card(forId: String($0)) }
                    let same = played.hasPrefix("PLAY") && expected?.kind == .play && expected?.card == playedCard
                    out.append(head + " → 偏离 \(done)/\(tokens.count) 应打「"
                        + (expected.map { RDText.formulaToken($0) } ?? "-") + "」"
                        + (same ? " 【牌对】" : " 【牌不同】") + " 差[\(Self.nearest(lock, live.state))]")
                    if same { out.append("    细查 " + Self.deepDiff(lock[0], live.state)) }
                    lock = []
                }
                let r = RedDragonFeedbackTests.analyze(b)
                // `RD_T4_LOCK_TIMING`：每个要搜索的边界再用线上配置搜一遍，记墙钟（查「重算好几秒」用）
                if ProcessInfo.processInfo.environment["RD_T4_LOCK_TIMING"] != nil {
                    let t0 = Date()
                    let liveResult = RedDragonSearch.solve(live.state, config: RedDragonConfig())
                    out.append(head + String(format: " … 线上配置搜索 %.2fs（CPU %.2f）斩杀 \(liveResult.isLethal) 终止 \(liveResult.termination) 伤害 \(liveResult.maxDamage)/\(liveResult.effectiveEnemyHealth)",
                                             Date().timeIntervalSince(t0), liveResult.cpuTime)
                        + "；确定性配置判定 \(r.analysis.verdict)")
                }
                let lethal = r.result.lethalLines.filter { !RDLineWalker.dependsOnDraw($0.actions, root: live.state) }
                guard r.analysis.isLethal, let l = lethal.first else { continue }
                tokens = RDFormulaBuilder.formula(.lethal, l.actions, root: live.state).tokens
                // 线上锁定只认屏上那条公式：写出来不同的候选不留
                lock = lethal.filter { RDFormulaBuilder.formula(.lethal, $0.actions, root: live.state).tokens == tokens }
                    .map { (live.state, $0) }
                done = 0
                lockTurn = s.turn
                out.append(head + " → 锁定：" + tokens.map { RDText.formulaToken($0) }.joined(separator: " "))
            }
        }
        print("T4LIST\n" + out.joined(separator: "\n"))
    }
}
