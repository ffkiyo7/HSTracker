//
//  RedDragonOverlayTests.swift
//  HSTrackerTests
//
//  T2c：overlay 的「画不画」规则（揭示档 / 答题 / 过时 / 奥秘）、重编号后标记落到的 entity、几何不重叠、
//  热切换、热键规则、视图只在自己的状态变化时重算（body 求值次数 + 主线程耗时），以及离屏效果图。
//
//  效果图：设了 `RD_RENDER_DIR` 才跑（xcodebuild 把 `TEST_RUNNER_RD_RENDER_DIR` 传成测试进程的 `RD_RENDER_DIR`），
//  PNG 写到那个目录，不入库。
//

import XCTest
import SwiftUI
@testable import HSTracker
@testable import RedDragonCore

class RedDragonOverlayTests: HSTrackerTests {

    override class func setUp() {
        super.setUp()
        if Cards.by(cardId: CardIds.Collectible.Rogue.Shadowstep) == nil {
            Database().loadDatabase(splashscreen: nil, withLanguages: [.enUS])
        }
    }

    static func id(_ c: RDCard) -> String { return RDHintBuilder.cardId(c) }

    /// 效果图和文字用的中文卡名（不依赖本机卡库的语言）
    static let zhNames: [String: String] = {
        let pairs: [(RDCard, String)] = [
            (.coin, "伪造的幸运币"), (.preparation, "伺机待发"), (.shadowstep, "暗影步"), (.shadowOfDemise, "殒命暗影"),
            (.goneFishin, "垂钓时光"), (.digForTreasure, "挖掘宝藏"), (.deafen, "致聋术"), (.blackwaterCutlass, "黑水弯刀"),
            (.cultistMap, "异教地图"), (.foxyFraud, "狐人老千"), (.quickPick, "疾速矿锄"), (.swindle, "行骗"),
            (.serratedBoneSpike, "锯齿骨刺"), (.evasion, "闪避"), (.darkscaleBroodmother, "晦鳞巢母"),
            (.shroudOfConcealment, "潜伏帷幕"), (.etcBandManager, "精英牛头人酋长"), (.scabbsCutterbutter, "斯卡布斯·刀油"),
            (.spiritOfTheShark, "鲨鱼之灵"), (.shadowcaster, "暗影施法者"), (.bounceAround, "舞动全场"),
            (.potionOfIllusion, "幻觉药水"), (.alexstrasza, "阿莱克丝塔萨")
        ]
        var out: [String: String] = ["CS2_179": "森金持盾卫士", "EX1_082": "疯狂投弹者"]
        for (c, n) in pairs { out[id(c)] = n }
        return out
    }()

    static func zh(_ id: String) -> String { return zhNames[id] ?? id }

    // MARK: - 构造

    static func analysis(verdict: RDLethalVerdict, damage: Int, health: Int, tier: RDDifficulty.Tier? = nil,
                         hand: [Int] = [], handMarks: [RDHandMark] = [], steps: [RDStep] = [], total: Int = 0,
                         boardMarks: [RDBoardMark] = [], next: String = "", branches: [RDDrawBranch] = [],
                         missing: [String] = [], insufficient: Bool = false, danger: Bool = false,
                         secrets: Bool = false, completeness: RDCompleteness = .complete,
                         board: [Int] = [], enemyBoard: [Int] = [], actions: Int = 0) -> RDAnalysis {
        let lethal = verdict == .lethal || verdict == .lethalIfDraw
        return RDAnalysis(turn: 9, availableMana: 7, isLethal: lethal, verdict: verdict, costsInferred: false,
                          lethalDependsOnDraw: verdict == .lethalIfDraw, maxDamage: damage,
                          effectiveEnemyHealth: health, completeness: completeness, tier: lethal ? tier : nil,
                          handMarks: handMarks, steps: steps, totalSteps: max(total, steps.count),
                          boardMarks: boardMarks, nextStepText: next, drawBranches: branches,
                          missingPieces: missing, missingPiecesIncomplete: false,
                          singleTurnInsufficient: insufficient, boardDanger: danger, opponentHasSecrets: secrets,
                          actionsTaken: actions, handOrder: hand, boardSlots: board, opponentBoardSlots: enemyBoard)
    }

    static func hint(_ a: RDAnalysis?, phase: RedDragonHint.Phase = .ready, level: RDRevealLevel = .verdict,
                     stale: Bool = false, quiz: RDQuizMark? = nil, quizMode: Bool = false) -> RedDragonHint {
        let cap = RDRevealPolicy.cap(isLethal: a?.isLethal ?? false, tier: a?.tier)
        return RedDragonHint(phase: phase, analysis: a, isStale: stale, revealLevel: min(level, cap),
                             maxRevealLevel: cap, quizMode: quizMode, quiz: quiz)
    }

    static func step(_ i: Int, _ kind: RDStep.Kind, card: RDCard? = nil, hand: Int? = nil, zone: Int? = nil,
                     attacker: RDStepTarget? = nil, target: RDStepTarget? = nil) -> RDStep {
        return RDStep(index: i, kind: kind, cardId: card.map(id), handEntityId: hand, zonePosition: zone,
                      attacker: attacker, target: target, picks: [], boardPosition: nil)
    }

    /// 一手 7 张、进阶斩杀线：前三步 = 刀油（手 3）→ 狐（场 201）撞嘲讽（敌 301）→ 暗影步（手 6）收回阿莱（场 202）
    static func sampleLethal() -> RDAnalysis {
        let hand = [101, 102, 103, 104, 105, 106, 107]
        return analysis(
            verdict: .lethal, damage: 32, health: 30, tier: .advanced, hand: hand,
            handMarks: [RDHandMark(entityId: 103, zonePosition: 3, role: .required),
                        RDHandMark(entityId: 106, zonePosition: 6, role: .required),
                        RDHandMark(entityId: 101, zonePosition: 1, role: .optional)],
            steps: [step(1, .playFromHand, card: .scabbsCutterbutter, hand: 103, zone: 3),
                    step(2, .attack, attacker: .friendlyMinion(entityId: 201, cardId: id(.foxyFraud)),
                         target: .enemyMinion(entityId: 301, cardId: "CS2_179")),
                    step(3, .playFromHand, card: .shadowstep, hand: 106, zone: 6,
                         target: .friendlyMinion(entityId: 202, cardId: id(.alexstrasza)))],
            total: 14,
            boardMarks: [RDBoardMark(entityId: 201, isEnemy: false, stepIndex: 2, role: .attacker),
                         RDBoardMark(entityId: 301, isEnemy: true, stepIndex: 2, role: .target),
                         RDBoardMark(entityId: 202, isEnemy: false, stepIndex: 3, role: .target)],
            next: "斯卡布斯·刀油", board: [201, 202], enemyBoard: [300, 301, 302])
    }

    // MARK: - 规则：画不画

    func testHiddenWhenInactiveOrOpponentTurn() {
        XCTAssertFalse(RDOverlayModel.make(.inactive, cardName: Self.zh).isVisible)
        var h = RedDragonHint.inactive
        h.phase = .opponentTurn
        XCTAssertFalse(RDOverlayModel.make(h, cardName: Self.zh).isVisible)
        let computing = RDOverlayModel.make(Self.hint(nil, phase: .computing), cardName: Self.zh)
        XCTAssertTrue(computing.isVisible)
        XCTAssertEqual(computing.badge?.statuses, [.computing])
    }

    /// L0 只有角标；L2 加一行「下一步」。手牌 / 场面上不画任何标记（10-06 用户定，L1 一并删掉）
    func testRevealLevelsGateLines() {
        let a = Self.sampleLethal()
        let l0 = RDOverlayModel.make(Self.hint(a, level: .verdict), cardName: Self.zh)
        XCTAssertEqual(l0.badge?.title, RDText.lethal)
        XCTAssertEqual(l0.badge?.numbers, "32 / 30")
        XCTAssertEqual(l0.badge?.margin, "+2")
        XCTAssertEqual(l0.badge?.tier, "进阶")
        XCTAssertTrue(l0.lines.isEmpty)

        let l2 = RDOverlayModel.make(Self.hint(a, level: .order), cardName: Self.zh)
        XCTAssertEqual(l2.lines.first?.kind, .nextStep)
        XCTAssertEqual(l2.lines.first?.text, "下一步：斯卡布斯·刀油（共 14 步）")
    }

    /// 基础线封顶在判定：请求 L2 也不出「下一步」（封顶在展示模型里，overlay 照 `revealLevel` 画）
    func testBasicLineCappedAtVerdict() {
        var a = Self.sampleLethal()
        a.tier = .basic
        let m = RDOverlayModel.make(Self.hint(a, level: .order), cardName: Self.zh)
        XCTAssertEqual(m.badge?.level, .verdict)
        XCTAssertEqual(m.badge?.maxLevel, .verdict)
        XCTAssertTrue(m.lines.isEmpty)
    }

    /// 答题模式：不给怎么打，角标旁给对 / 错
    func testQuizModeHidesMarksAndShowsJudgement() {
        let a = Self.sampleLethal()
        let right = RDOverlayModel.make(Self.hint(a, level: .order, quiz: .onLine, quizMode: true), cardName: Self.zh)
        XCTAssertFalse(right.lines.contains { $0.kind == .nextStep })
        XCTAssertEqual(right.badge?.quizMode, true)
        XCTAssertEqual(right.badge?.quiz, .onLine)
        let wrong = RDOverlayModel.make(Self.hint(Self.analysis(verdict: .provenNotLethal, damage: 21, health: 30),
                                                  quiz: .offLine, quizMode: true), cardName: Self.zh)
        XCTAssertEqual(wrong.badge?.quiz, .offLine)
        XCTAssertEqual(wrong.badge?.title, RDText.provenNotLethal)
        XCTAssertEqual(wrong.badge?.margin, "差 9")
    }

    /// 过时 / 正在算：整块置灰，内容原样留着（标签行、建议行都不增不减 —— 面板不变形，10-06 用户定）
    func testStaleDimsWithoutChangingContent() {
        let a = Self.sampleLethal()
        let fresh = RDOverlayModel.make(Self.hint(a, level: .order), cardName: Self.zh)
        for h in [Self.hint(a, phase: .computing, level: .order, stale: true), Self.hint(a, level: .order, stale: true)] {
            let m = RDOverlayModel.make(h, cardName: Self.zh)
            XCTAssertTrue(m.isVisible)
            XCTAssertEqual(m.badge?.dimmed, true)
            XCTAssertEqual(m.badge?.statuses, fresh.badge?.statuses)
            XCTAssertEqual(m.lines, fresh.lines)
        }
    }

    /// 已偏离：旧公式置灰留在原位、不再高亮下一步，行数和锁定时一样
    func testDeviatedKeepsTheOldFormulaDimmed() {
        var a = Self.sampleLethal()
        a.formula = Self.t4Formula(.lethal, done: 3)
        var locked = Self.hint(a, level: .order)
        locked.locked = true
        var deviated = locked
        deviated.locked = false
        deviated.deviated = true
        let before = RDOverlayModel.make(locked, cardName: Self.zh)
        let after = RDOverlayModel.make(deviated, cardName: Self.zh)
        XCTAssertEqual(after.badge?.title, RDText.deviated)
        XCTAssertEqual(after.badge?.dimmed, true)
        XCTAssertEqual(after.lines.map { $0.pieces.map { $0.text } }, before.lines.map { $0.pieces.map { $0.text } })
        XCTAssertFalse(after.lines.contains { $0.pieces.contains { $0.state == .next } })
        XCTAssertTrue(before.lines.contains { $0.pieces.contains { $0.state == .next } })
        // 标签行、行的种类都不增不减（面板不变形）
        XCTAssertEqual(after.lines.map { $0.kind }, before.lines.map { $0.kind })
        XCTAssertEqual(after.badge.map(RDPanelMetrics.hasChipRow), before.badge.map(RDPanelMetrics.hasChipRow))
        XCTAssertEqual(after.badge?.statuses, before.badge?.statuses)
        for width in [RDOverlayGeometry.panelMaxWidth, RDOverlayGeometry.panelMinWidth] {
            XCTAssertEqual(RDPanelMetrics.height(badge: after.badge!, lines: after.lines, width: width),
                           RDPanelMetrics.height(badge: before.badge!, lines: before.lines, width: width))
        }

        // 奶 16 线偏离：「回合末」那行也留着
        var heal = Self.analysis(verdict: .provenNotLethal, damage: 16, health: 27, danger: true)
        heal.setup = RDSetupAdvice(kind: .heal16, formula: Self.t4Formula(.heal16, done: 2))
        var healLocked = Self.hint(heal)
        healLocked.locked = true
        var healDeviated = healLocked
        healDeviated.locked = false
        healDeviated.deviated = true
        let healBefore = RDOverlayModel.make(healLocked, cardName: Self.zh)
        let healAfter = RDOverlayModel.make(healDeviated, cardName: Self.zh)
        XCTAssertEqual(healAfter.badge?.title, RDText.deviated)
        XCTAssertEqual(healAfter.lines.map { $0.kind }, healBefore.lines.map { $0.kind })
        XCTAssertTrue(healAfter.lines.contains { $0.kind == .leftover })
        XCTAssertEqual(RDPanelMetrics.height(badge: healAfter.badge!, lines: healAfter.lines,
                                             width: RDOverlayGeometry.panelMaxWidth),
                       RDPanelMetrics.height(badge: healBefore.badge!, lines: healBefore.lines,
                                             width: RDOverlayGeometry.panelMaxWidth))
    }

    /// 完整公式按阶段分行：打出「舞」「幻」的那一步收尾一行，只有第一行带标签
    func testFormulaBreaksAfterBounceAndPotion() {
        func play(_ c: RDCard, _ mana: Int) -> RDFormulaToken { return RDFormulaToken(kind: .play, card: c, mana: mana) }
        let f = RDFormula(goal: .lethal, tokens: [play(.spiritOfTheShark, 4), play(.bounceAround, 3),
                                                   play(.scabbsCutterbutter, 2), play(.potionOfIllusion, 1),
                                                   play(.alexstrasza, 0)], done: 1)
        let lines = RDOverlayModel.formulaLines(f, setup: false)
        XCTAssertEqual(lines.map { $0.pieces.map { $0.text } }, [["鱼4", "舞3"], ["刀2", "幻1"], ["龙0"]])
        XCTAssertEqual(lines.map { $0.label }, [RDText.lethalLabel, nil, nil])
        XCTAssertEqual(lines.flatMap { $0.pieces.map { $0.state } }, [.done, .next, .pending, .pending, .pending])
    }

    /// 对方有奥秘：判定角标旁必须出「⚠ 对方有奥秘」，可斩 / 不可斩都出
    func testOpponentSecretsWarning() {
        var a = Self.sampleLethal()
        a.opponentHasSecrets = true
        XCTAssertEqual(RDOverlayModel.make(Self.hint(a), cardName: Self.zh).badge?.opponentSecrets, true)
        let b = Self.analysis(verdict: .notFound, damage: 12, health: 30, secrets: true)
        XCTAssertEqual(RDOverlayModel.make(Self.hint(b), cardName: Self.zh).badge?.opponentSecrets, true)
        a.opponentHasSecrets = false
        XCTAssertEqual(RDOverlayModel.make(Self.hint(a), cardName: Self.zh).badge?.opponentSecrets, false)
    }

    /// 缺件、抽牌分叉、单回合不够、场面危险、截断
    func testWarningLines() {
        let a = Self.analysis(verdict: .provenNotLethal, damage: 19, health: 27,
                              branches: [RDDrawBranch(drawn: [Self.id(.spiritOfTheShark)], damage: 30, isLethal: true)],
                              missing: [Self.id(.scabbsCutterbutter), Self.id(.spiritOfTheShark)],
                              insufficient: true, danger: true, completeness: .truncated)
        let m = RDOverlayModel.make(Self.hint(a), cardName: Self.zh)
        XCTAssertEqual(m.lines.map { $0.kind }, [.branch(lethal: true), .missing, .insufficient, .danger])
        XCTAssertEqual(m.lines[0].text, "抽到 鲨鱼之灵 → 30")
        XCTAssertEqual(m.lines[1].text, "缺：斯卡布斯·刀油 或 鲨鱼之灵")
        XCTAssertEqual(m.badge?.statuses, [.truncated])
        XCTAssertEqual(m.badge?.numbers, "19 / 27")
        XCTAssertEqual(m.badge?.margin, "差 8")
        // 可斩杀（不靠抽）时不列抽牌分叉
        var lethal = Self.sampleLethal()
        lethal.drawBranches = [RDDrawBranch(drawn: [Self.id(.coin)], damage: 40, isLethal: true)]
        XCTAssertFalse(RDOverlayModel.make(Self.hint(lethal), cardName: Self.zh).lines.contains { $0.kind == .branch(lethal: true) })
    }

    // MARK: - 破冰模式（T8 阶段 B）：按键、破冰口径的面板

    /// 一条破冰线：鱼3 刀1 龙0（冰在这一步碎）币1 步-龙1
    static func iceFormula(done: Int = 0) -> RDFormula {
        var f = RDFormula(goal: .iceBreak,
                          tokens: [tok(.spiritOfTheShark, 3), tok(.scabbsCutterbutter, 1),
                                   tok(.alexstrasza, 0, target: .enemyHero), tok(.coin, 1),
                                   tok(.shadowstep, 1, target: .card(.alexstrasza))],
                          done: done)
        f.breakStep = 3
        return f
    }

    /// 破冰口径的结论（`RDHintBuilder.iceAnalysis` 给的那种：没有斩杀判定，只有 `ice`）
    static func iceAnalysis(_ kind: RDIceAdvice.Kind, formula: RDFormula? = nil, remaining: Int = 0, damage: Int = 0,
                            broken: Bool = false, probed: Bool = true, proven: Bool = false, secrets: Bool = true,
                            danger: Bool = false, completeness: RDCompleteness = .complete) -> RDAnalysis {
        var a = analysis(verdict: .notFound, damage: 0, health: 12, hand: [101, 102, 103, 104, 105, 106, 107],
                         danger: danger, secrets: secrets, completeness: completeness)
        a.ice = RDIceAdvice(kind: kind, formula: formula, broken: broken, remaining: remaining, nextTurnDamage: damage,
                            nextTurnProbed: probed, proven: proven)
        return a
    }

    /// 破冰开着的提示。有线就锁定（`RedDragonAssistant` 里破冰线一律锁定）
    static func iceHint(_ a: RDAnalysis?, phase: RedDragonHint.Phase = .ready, deviated: Bool = false,
                        stale: Bool = false, quizMode: Bool = false) -> RedDragonHint {
        var h = hint(a, phase: phase, stale: stale, quizMode: quizMode)
        h.iceMode = true
        h.locked = a?.ice?.formula != nil && !deviated
        h.deviated = deviated
        return h
    }

    private func make(_ h: RedDragonHint) -> RDOverlayModel { return RDOverlayModel.make(h, cardName: Self.zh) }

    /// 口径 10：按键只在对方有奥秘时出现；破冰开着时一直在（冰碎之后对方奥秘数是 0，没有它就关不掉）；
    /// 按键上写着开 / 关。面板不画时（对方回合 / 不在对局）自然也没有
    func testIceButtonOnlyWithSecretsOrWhileOn() {
        var a = Self.sampleLethal()
        XCTAssertNil(make(Self.hint(a)).badge?.iceButton, "对方没有奥秘：没有按键")
        XCTAssertNil(make(Self.hint(Self.analysis(verdict: .provenNotLethal, damage: 9, health: 30))).badge?.iceButton)
        XCTAssertNil(make(Self.hint(nil, phase: .computing)).badge?.iceButton, "还没有结论：不知道有没有奥秘")

        a.opponentHasSecrets = true
        let off = make(Self.hint(a)).badge
        XCTAssertEqual(off?.iceButton, false, "有奥秘、没开：按键在，画成关")
        XCTAssertEqual(off.flatMap(RDPanelMetrics.buttonText), "破冰：关")
        XCTAssertEqual(off?.opponentSecrets, true, "「⚠ 对方有奥秘」照旧")
        XCTAssertEqual(make(Self.hint(Self.analysis(verdict: .notFound, damage: 12, health: 30, secrets: true)))
            .badge?.iceButton, false, "斩不了也一样")
        // 过时 / 正在算：按键还在（内容不增不减）
        XCTAssertEqual(make(Self.hint(a, phase: .computing, stale: true)).badge?.iceButton, false)

        // 开着：刚点完、破冰的结论还没到（屏上还是斩杀判定）就已经画成开
        var waiting = Self.hint(a, phase: .computing, stale: true)
        waiting.iceMode = true
        XCTAssertEqual(make(waiting).badge?.iceButton, true)
        XCTAssertEqual(make(waiting).badge.flatMap(RDPanelMetrics.buttonText), "破冰：开")
        // 开着、对方奥秘数已经是 0（冰是本回合打掉的）：按键还在
        let broken = Self.iceAnalysis(.lethalNextTurn, formula: Self.iceFormula(done: 3), remaining: 1, damage: 16,
                                      broken: true, secrets: false)
        XCTAssertEqual(make(Self.iceHint(broken)).badge?.iceButton, true)
        XCTAssertEqual(make(Self.iceHint(Self.iceAnalysis(.cannotBreak, secrets: true))).badge?.iceButton, true)
        // 开着、还没有任何结论（对方回合过后的第一份局面在算）
        XCTAssertEqual(make(Self.iceHint(nil, phase: .computing)).badge?.iceButton, true)
        XCTAssertTrue(RDPanelMetrics.hasChipRow(make(Self.iceHint(broken)).badge!), "只有按键也占标签行")
        // 关掉之后屏上还是破冰的结论（等斩杀判定）：按键跟对方有没有奥秘走
        var turnedOff = Self.iceHint(Self.iceAnalysis(.cannotBreak, secrets: true), phase: .computing, stale: true)
        turnedOff.iceMode = false
        XCTAssertEqual(make(turnedOff).badge?.iceButton, false)

        // 面板不画
        var opponent = Self.iceHint(broken)
        opponent.phase = .opponentTurn
        XCTAssertFalse(make(opponent).isVisible)
        // 按键算进面板最小宽度（T6：估计值不小于实际，见 testPanelMetricsAreUpperBounds）
        let withButton = make(Self.iceHint(Self.iceAnalysis(.cannotBreak, secrets: true, completeness: .truncated))).badge!
        var without = withButton
        without.iceButton = nil
        XCTAssertGreaterThan(RDPanelMetrics.chipRowWidth(withButton), RDPanelMetrics.chipRowWidth(without))
    }

    /// 口径 8 / 9：破冰口径的面板。标题说结论、不放斩杀数字；本回合的线是完整公式（冰在哪一步碎有记号、之后另起一行），
    /// 不受揭示档和答题模式影响；一行下回合摘要；① 另有一行前提；② 不写「差多少」；③ 写破不了冰
    func testIcePanelContents() {
        // ① 破冰，下回合可斩
        let lethal = Self.iceAnalysis(.lethalNextTurn, formula: Self.iceFormula(done: 1), remaining: 4, damage: 16)
        let m1 = make(Self.iceHint(lethal))
        XCTAssertEqual(m1.badge?.title, "破冰，下回合可斩")
        XCTAssertEqual(m1.badge?.tone, .setup)
        XCTAssertNil(m1.badge?.numbers, "斩杀搜索的「伤害 / 血量」假定没有冰，不放")
        XCTAssertNil(m1.badge?.margin)
        XCTAssertEqual(m1.badge?.opponentSecrets, false, "奥秘的提醒让给按键")
        XCTAssertEqual(m1.lines.map { $0.kind }, [.formula(setup: true), .formula(setup: true),
                                                  .iceNextTurn(lethal: true), .icePremise])
        XCTAssertEqual(m1.lines[0].label, "破冰")
        XCTAssertNil(m1.lines[1].label)
        XCTAssertEqual(m1.lines[0].pieces.map { $0.text }, ["鱼3", "刀1", "龙0", "冰碎"], "冰在第 3 步碎，记号跟在那一步后面")
        XCTAssertEqual(m1.lines[1].pieces.map { $0.text }, ["币1", "步-龙1"], "冰碎之后的准备步另起一行")
        XCTAssertEqual(m1.lines.flatMap { $0.pieces.map { $0.state } }, [.done, .next, .pending, .note, .pending, .pending])
        XCTAssertEqual(m1.lines[2].text, "破冰后剩 4｜下回合伤害 16")
        XCTAssertEqual(m1.lines[3].text, "前提：对方回合不动场面、不回血")
        XCTAssertFalse(m1.lines.contains { $0.kind == .nextStep || $0.kind == .leftover })

        // 不受揭示档 / 答题模式影响：判定档、答题模式下还是整条公式，不画答题行
        var quiz = Self.iceHint(lethal, quizMode: true)
        quiz.quiz = .onLine
        let mq = make(quiz)
        XCTAssertEqual(mq.lines, m1.lines)
        XCTAssertEqual(mq.badge?.quizMode, false)
        XCTAssertNil(mq.badge?.quiz)
        XCTAssertEqual(m1.badge?.level, .verdict, "判定档也给整条线")

        // 打过冰碎那一步：前面的划掉，高亮落在准备步上
        let after = make(Self.iceHint(Self.iceAnalysis(.lethalNextTurn, formula: Self.iceFormula(done: 3), remaining: 4,
                                                       damage: 16, broken: true, secrets: false)))
        XCTAssertEqual(after.badge?.title, "冰已碎，下回合可斩")
        XCTAssertEqual(after.lines.flatMap { $0.pieces.map { $0.state } }, [.done, .done, .done, .note, .next, .pending])

        // ② 能破冰、下回合没搜到斩杀：不写「差 N」，写已知伤害和剩余血量
        let short = make(Self.iceHint(Self.iceAnalysis(.shortNextTurn, formula: Self.iceFormula(), remaining: 9, damage: 8)))
        XCTAssertEqual(short.badge?.title, "能破冰")
        XCTAssertEqual(short.badge?.tone, .notFound)
        XCTAssertEqual(short.lines.map { $0.kind }, [.formula(setup: true), .formula(setup: true), .iceNextTurn(lethal: false)])
        XCTAssertEqual(short.lines[2].text, "下回合没搜到斩杀：已知伤害 8｜破冰后剩 9")
        XCTAssertFalse(short.lines.contains { $0.kind == .icePremise }, "没说可斩，不用前提")
        for line in short.lines { XCTAssertFalse(line.text.contains("差"), line.text) }
        XCTAssertFalse(short.badge?.title.contains("差") ?? true)
        // ② 而且下回合没探完（预算用完，阶段 A 复核 2）：不报伤害，更不能写成破不了
        let unprobed = make(Self.iceHint(Self.iceAnalysis(.shortNextTurn, formula: Self.iceFormula(), remaining: 9,
                                                          probed: false, completeness: .truncated)))
        XCTAssertEqual(unprobed.badge?.title, "能破冰")
        XCTAssertEqual(unprobed.lines[2].text, "下回合没算完｜破冰后剩 9")
        XCTAssertEqual(unprobed.badge?.statuses, [.truncated])
        // 冰已碎、一步都不用打
        var zero = RDFormula(goal: .iceBreak, tokens: [])
        zero.done = 0
        let nothing = make(Self.iceHint(Self.iceAnalysis(.shortNextTurn, formula: zero, remaining: 20, damage: 8,
                                                         broken: true, secrets: false)))
        XCTAssertEqual(nothing.badge?.title, "冰已碎")
        XCTAssertEqual(nothing.lines.first?.pieces.map { $0.text }, ["本回合不用再出牌"])
        XCTAssertEqual(nothing.lines.first?.label, "破冰")

        // ③ 破不了冰：穷举过和只是没搜到写的一样，只在颜色上分开；没有公式行、没有下回合摘要
        let cannot = make(Self.iceHint(Self.iceAnalysis(.cannotBreak, danger: true)))
        XCTAssertEqual(cannot.badge?.title, "破不了冰")
        XCTAssertEqual(cannot.badge?.tone, .notFound)
        XCTAssertEqual(cannot.lines.map { $0.kind }, [.danger], "场面危险照常提醒")
        XCTAssertEqual(make(Self.iceHint(Self.iceAnalysis(.cannotBreak, proven: true))).badge?.tone, .provenNotLethal)
        XCTAssertTrue(make(Self.iceHint(Self.iceAnalysis(.cannotBreak, proven: true))).lines.isEmpty)

        // 打偏：旧的破冰线置灰留在原位、不再高亮下一步，标题换成「已偏离，重算中」；行不增不减
        let deviated = make(Self.iceHint(lethal, phase: .computing, deviated: true, stale: true))
        XCTAssertEqual(deviated.badge?.title, RDText.deviated)
        XCTAssertEqual(deviated.badge?.dimmed, true)
        XCTAssertEqual(deviated.badge?.iceButton, true)
        XCTAssertEqual(deviated.lines.map { $0.kind }, m1.lines.map { $0.kind })
        XCTAssertEqual(deviated.lines.map { $0.pieces.map { $0.text } }, m1.lines.map { $0.pieces.map { $0.text } })
        XCTAssertFalse(deviated.lines.contains { $0.pieces.contains { $0.state == .next } })
        // 锁定的破冰线：日志晚到的窗口里不变暗
        XCTAssertEqual(make(Self.iceHint(lethal, phase: .computing, stale: true)).badge?.dimmed, false)

        // 面板挤的时候：公式行不收，下回合摘要先于前提留下
        let kept = RDOverlayGeometry.compact(m1.lines, keep: 3)
        XCTAssertEqual(kept.map { $0.kind }, [.formula(setup: true), .formula(setup: true), .iceNextTurn(lethal: true)])
        XCTAssertEqual(RDOverlayGeometry.lineCaps(m1.lines), [4, 2])
    }

    /// 按键上报点击区域（`InteractiveRegionPreferenceKey`，`RootOverlayWindow` 据此只在这一块里接鼠标）：
    /// 画了按键才报，报的就是按键那一小块、落在面板里；没有按键 / 面板不画时一块都不报（整层照旧点击穿透）。
    /// 点那一块 → view model → `RedDragonAssistant.toggleIceBreak`；点面板别处不触发
    @MainActor
    func testIceButtonReportsItsClickRegionAndTakesTheClick() throws {
        let canvas = CGSize(width: 1920, height: 1080)
        let env = RedDragonAssistant.Environment(
            isEnabled: { true }, revealPreference: { .verdict }, quizMode: { false },
            debounce: 0, config: RedDragonConfig(), cardName: { $0 })
        let assistant = RedDragonAssistant(environment: env)
        let vm = RedDragonOverlayViewModel(assistant: assistant, cardName: Self.zh)
        final class Sink { var regions: [CGRect] = [] }
        let sink = Sink()
        let view = RedDragonOverlayView(viewModel: vm, canvasSize: canvas)
            .coordinateSpace(name: "rootOverlayCanvas")
            .onPreferenceChange(InteractiveRegionPreferenceKey.self) { sink.regions = $0 }
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(origin: .zero, size: canvas)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        // SwiftUI 的点击手势只在排上屏的窗口里走得通（离屏窗口里合成的按下 / 抬起没有反应）：全透明地排上去
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.orderFrontRegardless()
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }
        // 面板换内容带一小段动画（`RDStyle.animation`）：等它走完再量
        func settle() {
            for _ in 0..<4 {
                spin(until: { false }, timeout: 0.1)
                hosting.layoutSubtreeIfNeeded()
                hosting.display()
            }
        }
        /// 在画布坐标（左上原点）的一点上按下、抬起
        func click(_ p: CGPoint) throws {
            let at = hosting.convert(p, to: nil)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let e = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: at, modifierFlags: [],
                                                         timestamp: ProcessInfo.processInfo.systemUptime,
                                                         windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                                                         clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0))
                window.sendEvent(e)
            }
            settle()
        }

        // 对方没有奥秘：没有按键，不报区域
        var snap = lethalSnapshot()
        assistant.submit(.snapshot(snap))
        spin { vm.model.badge?.title == RDText.lethal }
        settle()
        XCTAssertNil(vm.model.badge?.iceButton)
        XCTAssertTrue(sink.regions.isEmpty, "\(sink.regions)")
        let noButton = try XCTUnwrap(RedDragonOverlayView.lastPanelLayout).frame
        try click(CGPoint(x: noButton.midX, y: noButton.midY))
        XCTAssertFalse(assistant.iceMode, "没有按键时点面板不触发任何东西")

        // 对方有奥秘：按键在（关），报一块，就是按键
        snap.opponentSecretCount = 1
        assistant.submit(.snapshot(snap))
        spin { vm.model.badge?.iceButton == false && vm.model.badge?.statuses.isEmpty == true }
        settle()
        XCTAssertEqual(sink.regions.count, 1, "\(sink.regions)")
        let panel = try XCTUnwrap(RedDragonOverlayView.lastPanelLayout)
        let button = try XCTUnwrap(sink.regions.first)
        XCTAssertTrue(panel.frame.contains(button), "按键 \(button) 在面板 \(panel.frame) 里")
        XCTAssertLessThan(button.width * button.height, panel.frame.width * panel.frame.height / 4,
                          "只有按键这一小块接鼠标，不是整块面板")
        let u = RDOverlayGeometry.unit(canvas) * panel.scale
        XCTAssertLessThanOrEqual(button.width, RDPanelMetrics.buttonWidth(RDText.iceButton(on: false)) * u + 0.5,
                                 "按键实际宽度不超过估计（T6）")
        XCTAssertGreaterThanOrEqual(button.height, 14 * u, "点得中")

        // 点面板别处（标题行、按键左边的标签、按键外沿之外一点）：不触发
        let scheduled = assistant.scheduledComputations
        try click(CGPoint(x: panel.frame.minX + 40 * u, y: panel.frame.minY + 14 * u))
        try click(CGPoint(x: button.minX - 12 * u, y: button.midY))
        try click(CGPoint(x: button.maxX + 6 * u, y: button.midY))
        XCTAssertFalse(assistant.iceMode)
        XCTAssertEqual(assistant.scheduledComputations, scheduled)
        // 点按键：破冰打开，立即重算（没有新局面进来），面板换成破冰口径、按键画成开
        try click(CGPoint(x: button.midX, y: button.midY))
        XCTAssertTrue(assistant.iceMode, "点按键 → view model → assistant")
        XCTAssertEqual(assistant.scheduledComputations, scheduled + 1)
        spin { vm.model.badge?.iceButton == true && assistant.hint.analysis?.ice != nil && assistant.hint.phase == .ready }
        settle()
        XCTAssertEqual(vm.model.badge?.iceButton, true)
        XCTAssertNotNil(assistant.hint.analysis?.ice)
        XCTAssertEqual(sink.regions.count, 1)
        let onButton = try XCTUnwrap(sink.regions.first)
        XCTAssertTrue(try XCTUnwrap(RedDragonOverlayView.lastPanelLayout).frame.contains(onButton))
        // 再点：关掉
        try click(CGPoint(x: onButton.midX, y: onButton.midY))
        XCTAssertFalse(assistant.iceMode)
        spin { vm.model.badge?.iceButton == false && assistant.hint.analysis?.ice == nil && assistant.hint.phase == .ready }
        XCTAssertEqual(vm.model.badge?.title, RDText.lethal)

        // 面板不画（对方回合）：不报区域
        assistant.submit(.opponentTurn)
        spin { !vm.model.isVisible }
        settle()
        XCTAssertTrue(sink.regions.isEmpty, "\(sink.regions)")

        // 只画不接点击的面板（效果图 / 尺寸测试用的 `RDPanel`，`onToggleIce == nil`）也不报
        let model = make(Self.iceHint(Self.iceAnalysis(.cannotBreak)))
        let layout = try XCTUnwrap(RDOverlayGeometry.panelLayout(canvas: canvas, badge: model.badge!, lines: model.lines,
                                                                 trackers: []))
        let plainSink = Sink()
        let plain = NSHostingView(rootView: ZStack(alignment: .topLeading) {
            Color.clear
            RDPanel(badge: model.badge!, layout: layout, canvas: canvas)
        }
        .frame(width: canvas.width, height: canvas.height, alignment: .topLeading)
        .coordinateSpace(name: "rootOverlayCanvas")
        .onPreferenceChange(InteractiveRegionPreferenceKey.self) { plainSink.regions = $0 })
        plain.frame = CGRect(origin: .zero, size: canvas)
        window.contentView = plain
        spin(until: { false }, timeout: 0.05)
        plain.layoutSubtreeIfNeeded()
        spin(until: { false }, timeout: 0.05)
        XCTAssertTrue(plainSink.regions.isEmpty)
    }

    /// 真的 `RootOverlayView`（坐标空间和 `onPreferenceChange` 都是上游现成的，T8 没动 `Overlay/Root/`）：
    /// 按键的外框进到 `RootOverlayViewModel.interactiveRegions` —— `RootOverlayWindow` 判断点击穿透用的就是这一份；
    /// 没有按键 / 面板不画时红龙不贡献任何区域
    func testIceButtonRegionReachesTheRootOverlay() throws {
        try waitForCoreManager()
        let root = RootOverlayViewModel()
        let size = CGSize(width: 1920, height: 1080)
        let hosting = NSHostingView(rootView: RootOverlayView(viewModel: root))
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        defer { window.contentView = nil }
        func settle() {
            for _ in 0..<4 {
                spin(until: { false }, timeout: 0.1)
                hosting.layoutSubtreeIfNeeded()
                hosting.display()
            }
        }
        settle()
        var a = Self.sampleLethal()
        root.redDragon.receive(Self.hint(a, level: .order))
        spin { root.redDragon.commits > 0 }
        settle()
        let before = root.interactiveRegions
        let plainPanel = try XCTUnwrap(RedDragonOverlayView.lastPanelLayout).frame
        XCTAssertNil(before.first { plainPanel.intersects($0) }, "没有按键：红龙面板上没有接鼠标的区域")

        a.opponentHasSecrets = true
        root.redDragon.receive(Self.hint(a, level: .order))
        spin { root.redDragon.model.badge?.iceButton == false }
        settle()
        let panel = try XCTUnwrap(RedDragonOverlayView.lastPanelLayout).frame
        let added = root.interactiveRegions.filter { !before.contains($0) }
        XCTAssertEqual(added.count, 1, "\(added)")
        if let button = added.first {
            XCTAssertTrue(panel.contains(button), "按键 \(button) 在面板 \(panel) 里")
            XCTAssertLessThan(button.width * button.height, panel.width * panel.height / 4)
        }

        var opponent = RedDragonHint.inactive
        opponent.phase = .opponentTurn
        root.redDragon.receive(opponent)
        spin { !root.redDragon.model.isVisible }
        settle()
        XCTAssertEqual(root.interactiveRegions, before, "面板不画：区域撤掉")
    }

    /// T6：尺寸估计把按键算进去，估计值不小于实际。标签行（标签 + 按键）单独撑宽面板的情形逐种实测
    /// （标题留空，标题行让开）：每个缩放档下实际宽、高都不超过估计。
    /// 按键和标签同一行放不下（难度 + 被截断 + 对方有奥秘 + 按键，实测超过面板最大宽度）时另起一行，高度多算一行
    @MainActor
    func testChipRowWithIceButtonIsAnUpperBound() {
        func badge(tier: String? = nil, statuses: [RDOverlayModel.Status] = [], secrets: Bool = false,
                   button: Bool? = nil) -> RDOverlayModel.Badge {
            return RDOverlayModel.Badge(title: "", numbers: nil, margin: nil, tone: .neutral, tier: tier, statuses: statuses,
                                        opponentSecrets: secrets, level: .verdict, maxLevel: .verdict, quizMode: false,
                                        quiz: nil, dimmed: false, iceButton: button)
        }
        let cases: [(name: String, badge: RDOverlayModel.Badge, rows: Int)] = [
            ("关", badge(button: false), 1), ("开", badge(button: true), 1),
            ("难度 + 关", badge(tier: "困难", button: false), 1),
            ("奥秘 + 关", badge(secrets: true, button: false), 1),
            ("难度 + 奥秘 + 关", badge(tier: "进阶", secrets: true, button: false), 1),
            ("被截断 + 奥秘 + 关", badge(statuses: [.truncated], secrets: true, button: false), 1),
            ("被截断 + 开", badge(statuses: [.truncated], button: true), 1),
            ("正在算 + 开", badge(statuses: [.computing], button: true), 1),
            ("难度 + 被截断 + 奥秘 + 关", badge(tier: "困难", statuses: [.truncated], secrets: true, button: false), 2),
            ("难度 + 被截断 + 奥秘 + 开", badge(tier: "进阶", statuses: [.truncated], secrets: true, button: true), 2),
            ("只有标签", badge(tier: "困难", statuses: [.truncated], secrets: true), 1)
        ]
        var worst: CGFloat = 0
        for c in cases {
            XCTAssertEqual(RDPanelMetrics.chipRows(c.badge), c.rows, c.name)
            XCTAssertEqual(RDPanelMetrics.buttonInline(c.badge), c.rows == 1, c.name)
            let est = RDPanelMetrics.minWidth(badge: c.badge, dropped: 0)
            XCTAssertLessThanOrEqual(est, RDOverlayGeometry.panelMaxWidth, "\(c.name)：面板最大宽度放得下")
            for u in RDOverlayGeometry.panelScales {
                let ideal = NSHostingView(rootView: RDPanelContent(badge: c.badge, lines: [], dropped: 0, u: u).fixedSize())
                    .fittingSize
                XCTAssertLessThanOrEqual(ideal.width, est * u + 0.5, "\(c.name) ×\(u)")
                XCTAssertLessThanOrEqual(ideal.height, RDPanelMetrics.height(badge: c.badge, lines: [], width: est) * u + 0.5,
                                         "\(c.name) ×\(u)")
                if RDPanelMetrics.chipRowWidth(c.badge) > RDOverlayGeometry.panelMinWidth {
                    worst = max(worst, (est * u - ideal.width) / (est * u))
                }
            }
        }
        // 按键另起一行的面板比同一行的高出一行标签
        let inline = cases[5].badge, wrapped = cases[8].badge
        XCTAssertEqual(RDPanelMetrics.height(badge: wrapped, lines: [], width: 320)
                       - RDPanelMetrics.height(badge: inline, lines: [], width: 320),
                       RDPanelMetrics.spacing + RDPanelMetrics.chipHeight(), accuracy: 0.01)
        print(String(format: "[rd-metrics] chip row with ice button: estimate over actual by at most %.0f%%", worst * 100))
    }

    // MARK: - 打出一张后重算：「下一步」跟着换（走真的读取 + 搜索 + 展示模型）

    private final class Table {
        var entities: [Entity] = []
        var nextId = 100
        let player: Entity
        let opponentHero: Entity

        init(resources: Int) {
            let gameEntity = Entity(id: 1)
            gameEntity.name = "GameEntity"
            gameEntity[.cardtype] = CardType.game.rawValue
            gameEntity[.turn] = 9
            player = Entity(id: 2)
            player[.player_id] = 1
            player[.resources] = resources
            player[.current_player] = 1
            let opponent = Entity(id: 3)
            opponent[.player_id] = 2
            let hero = Entity(id: 4)
            hero.cardId = RDCards.heroId
            hero[.cardtype] = CardType.hero.rawValue
            hero[.controller] = 1
            hero[.zone] = Zone.play.rawValue
            hero[.health] = 30
            let power = Entity(id: 5)
            power.cardId = RDCards.heroPowerId
            power[.cardtype] = CardType.hero_power.rawValue
            power[.controller] = 1
            power[.zone] = Zone.play.rawValue
            opponentHero = Entity(id: 6)
            opponentHero.cardId = "HERO_01"
            opponentHero[.cardtype] = CardType.hero.rawValue
            opponentHero[.controller] = 2
            opponentHero[.zone] = Zone.play.rawValue
            opponentHero[.health] = 30
            entities = [gameEntity, player, opponent, hero, power, opponentHero]
        }

        @discardableResult
        func add(_ cardId: String, zone: Zone, position: Int, tags: [GameTag: Int] = [:]) -> Entity {
            let e = Entity(id: nextId)
            nextId += 1
            e.cardId = cardId
            let card = Cards.any(byId: cardId)
            e[.cardtype] = card?.type == .minion ? CardType.minion.rawValue : CardType.spell.rawValue
            e[.controller] = 1
            e[.zone] = zone.rawValue
            e[.cost] = card?.cost ?? 0
            e[.atk] = card?.attack ?? 0
            e[.health] = card?.health ?? 0
            e[.zone_position] = position
            for (k, v) in tags { e[k] = v }
            entities.append(e)
            return e
        }

        func enchant(_ cardId: String, on target: Entity) {
            let e = Entity(id: nextId)
            nextId += 1
            e.cardId = cardId
            e[.cardtype] = CardType.enchantment.rawValue
            e[.controller] = 1
            e[.zone] = Zone.play.rawValue
            e[.attached] = target.id
            entities.append(e)
        }

        func snapshot() -> RDGameSnapshot {
            return RDGameSnapshot.capture(entities: entities, playerId: 1, opponentId: 2, deck: [:],
                                          band: RDCards.sideboardCards.map(RedDragonOverlayTests.id))
        }
    }

    private func analyze(_ snap: RDGameSnapshot) -> RDAnalysis {
        let live = RDStateReader.read(snap)
        let result = RedDragonSearch.solve(live.state)
        return RDHintBuilder.analyze(snapshot: snap, live: live, result: result, cardName: { $0 })
    }

    /// 手牌 [阿莱 a, 闪避, 阿莱 b]，对方 16 血：L2 给「下一步（共 2 步）」。
    /// 打出 a 后重算：手牌变成 [闪避, b]，剩 1 步
    func testNextStepFollowsAfterAPlay() {
        let t = Table(resources: 2)
        t.opponentHero[.health] = 16
        let a = t.add("LEG_CS3_031", zone: .hand, position: 1, tags: [.cost: 1, .atk: 1, .health: 1])
        t.enchant("SCH_352e", on: a)
        let evasion = t.add("LOOT_214", zone: .hand, position: 2)
        let b = t.add("LEG_CS3_031", zone: .hand, position: 3, tags: [.cost: 1, .atk: 1, .health: 1])
        t.enchant("SCH_352e", on: b)

        let firstAnalysis = analyze(t.snapshot())
        let first = RDOverlayModel.make(Self.hint(firstAnalysis, level: .order), cardName: { $0 })
        XCTAssertEqual(firstAnalysis.totalSteps, 2)
        XCTAssertEqual(first.lines.first?.kind, .nextStep)

        a[.zone] = Zone.play.rawValue
        a[.zone_position] = 1
        a[.exhausted] = 1
        t.player[.resources_used] = 1
        t.player[.num_cards_played_this_turn] = 1
        t.player[.num_options_played_this_turn] = 1
        t.opponentHero[.damage] = 8
        evasion[.zone_position] = 1
        b[.zone_position] = 2
        let secondAnalysis = analyze(t.snapshot())
        let second = RDOverlayModel.make(Self.hint(secondAnalysis, level: .order), cardName: { $0 })
        XCTAssertEqual(secondAnalysis.totalSteps, 1)
        XCTAssertEqual(secondAnalysis.steps.first?.handEntityId, b.id)
        XCTAssertEqual(second.lines.first?.kind, .nextStep)
    }

    // MARK: - 几何：不和现有组件重叠

    /// 最高的面板：标签行（进阶 + 被截断 + 奥秘）+ 6 行文字（3 条分叉 + 缺件 + 单回合不够 + 危险），长卡名
    /// `secrets`（T8 起分开）：对方有奥秘时标签行多一个「⚠ 对方有奥秘」和破冰按键，连同难度、被截断四样一行放不下，
    /// 按键另起一行，面板比不带奥秘的高出一行标签。T6 的「没有记牌器挡路一律 ×1.6、贴手牌」量的是不带奥秘的这一个
    /// （和 T8 之前同高同宽：那时奥秘标签和另外两个挤在同一行）；带奥秘的那一个在 16:9 上退到 ×1.36，
    /// 见 `testPanelNeverCoversHand`
    static func tallestPanel(secrets: Bool = false) -> RDOverlayModel {
        let a = analysis(verdict: .lethalIfDraw, damage: 32, health: 30, tier: .advanced,
                         branches: [RDDrawBranch(drawn: [id(.scabbsCutterbutter), id(.darkscaleBroodmother)], damage: 32, isLethal: true),
                                    RDDrawBranch(drawn: [id(.shadowOfDemise), id(.spiritOfTheShark)], damage: 31, isLethal: true),
                                    RDDrawBranch(drawn: [id(.evasion)], damage: 16, isLethal: false)],
                         missing: [id(.scabbsCutterbutter), id(.darkscaleBroodmother), id(.shroudOfConcealment)],
                         insufficient: true, danger: true, secrets: secrets, completeness: .truncated)
        return RDOverlayModel.make(hint(a), cardName: zh)
    }

    /// 1~10 张手牌每一张（转过角的悬停矩形外接框）
    static func handCardBounds(_ canvas: CGSize) -> [CGRect] {
        var out: [CGRect] = []
        let size = RDOverlayGeometry.handCardSize(canvas)
        for count in 1...10 {
            for i in 0..<count {
                let card = RDOverlayGeometry.handCard(index: i, count: count, canvas: canvas)
                let rect = CGRect(x: card.center.x - size.width / 2, y: card.center.y - size.height / 2,
                                  width: size.width, height: size.height)
                out.append(rect.applying(CGAffineTransform(translationX: -rect.midX, y: -rect.midY)
                    .concatenating(CGAffineTransform(rotationAngle: CGFloat(card.angle * .pi / 180)))
                    .concatenating(CGAffineTransform(translationX: rect.midX, y: rect.midY))))
            }
        }
        return out
    }

    /// 没有记牌器挡路时：最高的面板也放在默认那一行、不收行（必要时缩字号），不压手牌、场攻图标、计数器、场面；
    /// 常见的 L2 面板在 16:9 下 ×1.6、宽 320 u × 1.6，右沿贴手牌禁区、左边长进黑边（T6）
    func testPanelClearOfHandAndWidgets() {
        let usual = RDOverlayModel.make(Self.hint(Self.sampleLethal(), level: .order), cardName: Self.zh)
        let wide = CGSize(width: 1920, height: 1080)
        let usualLayout = RDOverlayGeometry.panelLayout(canvas: wide, badge: usual.badge!, lines: usual.lines, trackers: [])
        XCTAssertEqual(usualLayout?.scale, 1.6)
        XCTAssertEqual(usualLayout?.frame.width ?? 0, RDOverlayGeometry.panelMaxWidth * 1.6, accuracy: 0.5)
        XCTAssertEqual(usualLayout?.frame.maxX ?? 0,
                       RDOverlayGeometry.handBox(wide).minX - RDOverlayGeometry.panelGap, accuracy: 0.5)
        XCTAssertLessThan(usualLayout?.frame.minX ?? .infinity, (wide.width - wide.height * 4 / 3) / 2, "左沿在黑边里")
        let tallest = Self.tallestPanel()
        for canvas in [CGSize(width: 1920, height: 1080), CGSize(width: 2560, height: 1080),
                       CGSize(width: 1440, height: 1080), CGSize(width: 1280, height: 800)] {
            guard let layout = RDOverlayGeometry.panelLayout(canvas: canvas, badge: tallest.badge!, lines: tallest.lines,
                                                             trackers: []) else {
                XCTFail("\(canvas) 放不下")
                continue
            }
            let panel = layout.frame
            XCTAssertEqual(layout.droppedLines, 0, "\(canvas)")
            XCTAssertEqual(panel.maxY, canvas.height * RDOverlayGeometry.panelBottomFraction, accuracy: 0.5)
            for card in Self.handCardBounds(canvas) {
                XCTAssertFalse(panel.intersects(card), "\(canvas) panel \(panel) card \(card)")
            }
            for o in RDOverlayGeometry.fixedObstacles(canvas) {
                XCTAssertFalse(panel.intersects(o), "\(canvas) panel \(panel) obstacle \(o)")
            }
            let board = RDOverlayGeometry.minionRect(isEnemy: false, index: 0, count: 1, canvas: canvas)
            XCTAssertLessThan(board.maxY, panel.minY, "\(canvas) 场面")
        }
    }

    /// Codex 复现的局面：1440×1080、对手记牌器 150% / 85% 高、10 张手牌。旧版面板右缘压进手牌约 80 px
    func testPanelYieldsToWideOpponentTracker() {
        let canvas = CGSize(width: 1440, height: 1080)
        let tracker = RDOverlayGeometry.trackerBox(
            .init(isOpponent: true, isShown: true, left: 0.5, top: 12.5, height: 85, scaling: 150),
            cardSize: .big, canvas: canvas)!
        for model in [Self.tallestPanel(), Self.tallestPanel(secrets: true),
                      RDOverlayModel.make(Self.hint(Self.sampleLethal(), level: .order), cardName: Self.zh)] {
            let layout = RDOverlayGeometry.panelLayout(canvas: canvas, badge: model.badge!, lines: model.lines,
                                                       trackers: [tracker])
            guard let frame = layout?.frame else { continue }
            XCTAssertFalse(frame.intersects(tracker), "\(frame) \(tracker)")
            for card in Self.handCardBounds(canvas) {
                XCTAssertFalse(frame.intersects(card), "panel \(frame) card \(card)")
            }
        }
        // 60% 高的记牌器（底在 72.5% H）够不着面板：不挪、不缩
        let short = RDOverlayGeometry.trackerBox(
            .init(isOpponent: true, isShown: true, left: 0.5, top: 12.5, height: 60, scaling: 100),
            cardSize: .big, canvas: canvas)!
        let m = RDOverlayModel.make(Self.hint(Self.sampleLethal(), level: .order), cardName: Self.zh)
        let free = RDOverlayGeometry.panelLayout(canvas: canvas, badge: m.badge!, lines: m.lines, trackers: [])
        XCTAssertNotNil(free)
        XCTAssertEqual(RDOverlayGeometry.panelLayout(canvas: canvas, badge: m.badge!, lines: m.lines, trackers: [short]), free)
        // 记牌器藏起来时不算障碍
        XCTAssertNil(RDOverlayGeometry.trackerBox(
            .init(isOpponent: true, isShown: false, left: 0.5, top: 12.5, height: 85, scaling: 150),
            cardSize: .big, canvas: canvas))
    }

    /// 扫一组画布比例 × 对手记牌器（位置 / 缩放 / 高度）× 我方记牌器 × 卡牌尺寸 × 面板内容：
    /// 面板要么放得下且不和手牌（每一张）、任何记牌器、固定组件相交、不出画布，要么不画。统计各降级档的次数
    func testPanelSweepNeverOverlaps() {
        let canvases = [CGSize(width: 1920, height: 1080), CGSize(width: 2560, height: 1080), CGSize(width: 3440, height: 1440),
                        CGSize(width: 1440, height: 1080), CGSize(width: 1280, height: 1024), CGSize(width: 1024, height: 768),
                        CGSize(width: 1280, height: 800), CGSize(width: 1680, height: 1050)]
        let models = [Self.tallestPanel(), Self.tallestPanel(secrets: true), Self.sceneModel("29-ice-locked.png"),
                      RDOverlayModel.make(Self.hint(Self.sampleLethal(), level: .order), cardName: Self.zh),
                      RDOverlayModel.make(Self.hint(Self.sampleLethal(), level: .order, quiz: .onLine, quizMode: true), cardName: Self.zh),
                      Self.sceneModel("18-formula-locked.png"), Self.sceneModel("15-danger-heal16.png")]
        var tally: [String: Int] = [:]
        var usualTally: [String: Int] = [:]
        var total = 0
        var usualTotal = 0
        var usualHidden: Set<String> = []
        for canvas in canvases {
            let hands = Self.handCardBounds(canvas)
            let fixed = RDOverlayGeometry.fixedObstacles(canvas)
            let handBox = RDOverlayGeometry.handBox(canvas)
            for scaling in [50.0, 100, 150, 200] {
                for height in [40.0, 72, 85, 100] {
                    for left in [0.0, 0.5, 8, 15] {
                        for top in [0.0, 12.5, 30] {
                            for playerLeft in [99.5, 70] {
                                for cardSize in [CardSize.tiny, .big, .huge] {
                                    let trackers = [
                                        RDOverlayGeometry.trackerBox(.init(isOpponent: true, isShown: true, left: left, top: top,
                                                                           height: height, scaling: scaling),
                                                                     cardSize: cardSize, canvas: canvas)!,
                                        RDOverlayGeometry.trackerBox(.init(isOpponent: false, isShown: true, left: playerLeft, top: 2,
                                                                           height: 88, scaling: scaling),
                                                                     cardSize: cardSize, canvas: canvas)!
                                    ]
                                    // 常见配置：缩放 ≤ 100%、对手记牌器在左边黑边 / 4:3 左沿、上沿 12.5%
                                    let usual = scaling <= 100 && left <= 0.5 && top == 12.5 && playerLeft == 99.5
                                    for model in models {
                                        total += 1
                                        if usual { usualTotal += 1 }
                                        guard let layout = RDOverlayGeometry.panelLayout(canvas: canvas, badge: model.badge!,
                                                                                         lines: model.lines, trackers: trackers) else {
                                            tally["hidden", default: 0] += 1
                                            if usual {
                                                usualTally["hidden", default: 0] += 1
                                                usualHidden.insert("\(Int(canvas.width))x\(Int(canvas.height)) s\(Int(scaling)) h\(Int(height))")
                                            }
                                            continue
                                        }
                                        let f = layout.frame
                                        let gap = RDOverlayGeometry.panelGap * canvas.height / 1080
                                        let aboveHand = abs(f.maxY - (handBox.minY - gap)) < 0.5
                                        // 默认一行里：贴手牌（hug）还是被别的障碍挡在左边（left），各缩放档分开数
                                        let key = layout.hidesNumbers ? "numbers-hidden"
                                            : layout.droppedLines > 0 ? "lines-dropped"
                                            : abs(f.maxY - canvas.height * RDOverlayGeometry.panelBottomFraction) > 0.5
                                                ? (aboveHand ? "above-hand" : "above-tracker")
                                            : (abs(f.maxX - (handBox.minX - gap)) < 0.5 ? "hug" : "left") + "-x\(layout.scale)"
                                        tally[key, default: 0] += 1
                                        if usual { usualTally[key, default: 0] += 1 }
                                        XCTAssertTrue(CGRect(origin: .zero, size: canvas).contains(f))
                                        let hit = (hands + fixed + trackers).first { $0.intersects(f) }
                                        XCTAssertNil(hit, "\(canvas) s\(scaling) h\(height) l\(left) t\(top) p\(playerLeft) \(cardSize) panel \(f) hits \(hit.map { "\($0)" } ?? "")")
                                        if hit != nil { return }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        print("[rd-sweep] \(total) combos: " + tally.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
              + " | usual \(usualTotal): " + usualTally.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
              + " | usual hidden in: " + usualHidden.sorted().joined(separator: ", "))
    }

    static func sceneModel(_ file: String) -> RDOverlayModel {
        return RDOverlayModel.make(scenes().first { $0.file == file }!.hint, cardName: zh)
    }

    /// T6 硬约束：任何情况下不遮手牌。画布比例（16:9 / 16:10 / 4:3 / 5:4 / 超宽，大小各几种）× 面板内容
    /// （全部效果图局面 + 最高的面板：0~6 行文字、3 行公式、公式 + 回合末）× 记牌器（无 / 默认 / 加高 / 放大 / 拖进左下）：
    /// 面板不和 1~10 张手牌里任何一张的外接框相交，也不进手牌禁区（外接框并集）；
    /// 没有记牌器挡路时一定画得出来，在默认那一行、右沿贴手牌禁区（留 8 u）、不收行
    func testPanelNeverCoversHand() {
        let canvases = [CGSize(width: 1920, height: 1080), CGSize(width: 2560, height: 1440), CGSize(width: 1366, height: 768),
                        CGSize(width: 1728, height: 1117), CGSize(width: 1680, height: 1050), CGSize(width: 1280, height: 800),
                        CGSize(width: 1440, height: 1080), CGSize(width: 1024, height: 768), CGSize(width: 1280, height: 1024),
                        CGSize(width: 2560, height: 1080), CGSize(width: 3440, height: 1440), CGSize(width: 5120, height: 1440)]
        // 最高的面板再带上对方奥秘（T8）：按键另起一行，比 T6 量的那个高一行标签。不遮手牌、画得出来、不收行这几条照样要守；
        // 16:9 及更宽时放不进 ×1.6 的默认位置（退到 ×1.36，或超宽屏上挪进黑边），这两条单独放宽
        let tallestWithButton = Self.tallestPanel(secrets: true)
        XCTAssertEqual(tallestWithButton.badge.map(RDPanelMetrics.chipRows), 2)
        let models = Self.scenes().map { RDOverlayModel.make($0.hint, cardName: Self.zh) }.filter { $0.isVisible }
            + [Self.tallestPanel(), tallestWithButton]
        XCTAssertGreaterThanOrEqual(Set(models.map { $0.lines.count }).count, 5, "\(Set(models.map { $0.lines.count }).sorted())")
        let placements: [[RDOverlayGeometry.TrackerPlacement]] = [
            [],
            [.init(isOpponent: true, isShown: true, left: 0.5, top: 12.5, height: 72, scaling: 100)],
            [.init(isOpponent: true, isShown: true, left: -0.8, top: 10, height: 88, scaling: 100)],
            [.init(isOpponent: true, isShown: true, left: 0.5, top: 12.5, height: 85, scaling: 150)],
            [.init(isOpponent: true, isShown: true, left: 12, top: 30, height: 70, scaling: 100)],
            [.init(isOpponent: true, isShown: true, left: 25, top: 40, height: 60, scaling: 100),
             .init(isOpponent: false, isShown: true, left: 45, top: 50, height: 50, scaling: 100)]
        ]
        var checked = 0
        var hidden = 0
        for canvas in canvases {
            let hands = Self.handCardBounds(canvas)
            XCTAssertEqual(hands.count, 55)
            let handBox = RDOverlayGeometry.handBox(canvas)
            let gap = RDOverlayGeometry.panelGap * RDOverlayGeometry.unit(canvas)
            for placement in placements {
                let trackers = placement.compactMap { RDOverlayGeometry.trackerBox($0, cardSize: .big, canvas: canvas) }
                for model in models {
                    let layout = RDOverlayGeometry.panelLayout(canvas: canvas, badge: model.badge!, lines: model.lines,
                                                               trackers: trackers)
                    let what = "\(canvas) trackers \(placement.count) \(model.badge!.title) lines \(model.lines.count)"
                    guard let layout else {
                        XCTAssertFalse(placement.isEmpty, "\(what)：没有记牌器挡路却画不出来")
                        hidden += 1
                        continue
                    }
                    checked += 1
                    let f = layout.frame
                    XCTAssertFalse(f.intersects(handBox), "\(what) panel \(f) hand \(handBox)")
                    XCTAssertNil(hands.first { $0.intersects(f) }, "\(what) panel \(f)")
                    XCTAssertNil(trackers.first { $0.intersects(f) }, "\(what) panel \(f)")
                    XCTAssertTrue(CGRect(origin: .zero, size: canvas).contains(f), "\(what) panel \(f)")
                    XCTAssertEqual(layout.lines.filter { $0.isFormula }, model.lines.filter { $0.isFormula }, "\(what) 公式行不收")
                    if placement.isEmpty {
                        let wide = canvas.width / canvas.height >= 16.0 / 9 - 0.01
                        XCTAssertEqual(f.maxY, canvas.height * RDOverlayGeometry.panelBottomFraction, accuracy: 0.5, "\(what)")
                        XCTAssertEqual(layout.droppedLines, 0, "\(what)")
                        if model == tallestWithButton {
                            if wide { XCTAssertGreaterThanOrEqual(layout.scale, 1.36, "\(what)") }
                            continue
                        }
                        XCTAssertEqual(f.maxX, handBox.minX - gap, accuracy: 0.5, "\(what)")
                        // 16:9 及更宽：黑边够长，所有内容都是 ×1.6
                        if wide {
                            XCTAssertEqual(layout.scale, 1.6, "\(what)")
                        }
                    }
                }
            }
        }
        print("[rd-hand] \(checked) layouts checked against 55 hand cards each, \(hidden) hidden (trackers in the way)")

        // 报告用：锁定公式 / 奶 16 面板的实际像素
        let defaultTracker = RDOverlayGeometry.TrackerPlacement(isOpponent: true, isShown: true, left: 0.5, top: 12.5,
                                                                height: 72, scaling: 100)
        for canvas in [CGSize(width: 1920, height: 1080), CGSize(width: 1728, height: 1117), CGSize(width: 1440, height: 1080)] {
            for file in ["18-formula-locked.png", "15-danger-heal16.png"] {
                let model = Self.sceneModel(file)
                var nudged = defaultTracker
                nudged.left = -0.83
                nudged.top = 10.09
                for (tag, placement) in [("no tracker", []), ("default tracker", [defaultTracker]),
                                         ("tracker left -0.83 top 10.09", [nudged])] {
                    let trackers = placement.compactMap { RDOverlayGeometry.trackerBox($0, cardSize: .big, canvas: canvas) }
                    let l = RDOverlayGeometry.panelLayout(canvas: canvas, badge: model.badge!, lines: model.lines, trackers: trackers)
                    print("[rd-size] \(Int(canvas.width))x\(Int(canvas.height)) \(file) \(tag): "
                          + (l.map { String(format: "x%.2f %.0f×%.0f px at (%.0f, %.0f) dropped %d", $0.scale, $0.frame.width,
                                            $0.frame.height, $0.frame.minX, $0.frame.minY, $0.droppedLines) } ?? "hidden"))
                }
            }
        }
    }

    /// 估计值只会偏大：实测面板内容（NSHostingView）的高不超过 `RDPanelMetrics.height`，
    /// 去掉文字行后的理想宽（标题行 / 标签行不截断所需）不超过 `minWidth`
    @MainActor
    func testPanelMetricsAreUpperBounds() {
        var models = Self.scenes().map { RDOverlayModel.make($0.hint, cardName: Self.zh) }.filter { $0.isVisible }
        models.append(Self.tallestPanel())
        models.append(Self.tallestPanel(secrets: true))
        var worst: CGFloat = 0
        var worstWidth: CGFloat = 0
        for model in models {
            let badge = model.badge!
            for dropped in [0, 3] {
                for scale in RDOverlayGeometry.panelScales {
                    let u = scale
                    let ideal = NSHostingView(rootView: RDPanelContent(badge: badge, lines: [], dropped: dropped, u: u).fixedSize())
                    let est = RDPanelMetrics.minWidth(badge: badge, dropped: dropped) * u
                    XCTAssertLessThanOrEqual(ideal.fittingSize.width, est + 0.5, "\(badge.title) dropped \(dropped) scale \(scale)")
                    if est > RDOverlayGeometry.panelMinWidth * u + 0.5 {
                        worstWidth = max(worstWidth, (est - ideal.fittingSize.width) / est)
                    }
                    for width in [RDOverlayGeometry.panelMaxWidth, RDPanelMetrics.minWidth(badge: badge, dropped: dropped)] {
                        let view = RDPanelContent(badge: badge, lines: model.lines, dropped: dropped, u: u)
                            .frame(width: width * u).fixedSize(horizontal: false, vertical: true)
                        let actual = NSHostingView(rootView: view).fittingSize.height
                        let estimate = RDPanelMetrics.height(badge: badge, lines: model.lines, width: width) * u
                        XCTAssertLessThanOrEqual(actual, estimate + 0.5, "\(badge.title) lines \(model.lines.count) width \(width) scale \(scale)")
                        worst = max(worst, (estimate - actual) / estimate)
                    }
                }
            }
        }
        print(String(format: "[rd-metrics] height estimate over actual by at most %.0f%%, min-width estimate over ideal by at most %.0f%%",
                     worst * 100, worstWidth * 100))
    }

    /// 画出来的内容不掉到面板底边外面：公式的流式排版在「算高度」和「摆位置」两步必须是同一种排法。
    /// （T6 加非整数缩放档后出现过：摆位置时宽度被对齐到像素、少了零点几，行尾的词多挤出一行画在面板外）
    /// 几种画布 × 记牌器位置下，把带公式的面板按 `panelLayout` 给的位置离屏渲染：底边以下（阴影之外）必须是透明的
    @MainActor
    func testFormulaRowsStayInsidePanel() throws {
        var models: [RDOverlayModel] = []
        for m in Self.scenes().map({ RDOverlayModel.make($0.hint, cardName: Self.zh) })
        where m.lines.contains(where: { $0.isFormula }) && !models.contains(m) {
            models.append(m)
        }
        XCTAssertGreaterThanOrEqual(models.count, 4)
        let placements: [RDOverlayGeometry.TrackerPlacement?] = [
            nil,
            .init(isOpponent: true, isShown: true, left: 0.5, top: 12.5, height: 72, scaling: 100),
            .init(isOpponent: true, isShown: true, left: -0.83, top: 10.09, height: 72, scaling: 100),
            .init(isOpponent: true, isShown: true, left: 12, top: 30, height: 70, scaling: 100)
        ]
        var rendered = 0
        var scales: Set<CGFloat> = []
        for canvas in [CGSize(width: 1920, height: 1080), CGSize(width: 1728, height: 1117), CGSize(width: 1440, height: 1080),
                       CGSize(width: 1366, height: 768), CGSize(width: 2560, height: 1440)] {
            let u = RDOverlayGeometry.unit(canvas)
            for placement in placements {
                let trackers = [placement].compactMap { $0 }
                    .compactMap { RDOverlayGeometry.trackerBox($0, cardSize: .big, canvas: canvas) }
                for model in models {
                    let badge = model.badge!
                    guard let layout = RDOverlayGeometry.panelLayout(canvas: canvas, badge: badge, lines: model.lines,
                                                                     trackers: trackers) else { continue }
                    scales.insert(layout.scale)
                    // 面板在画布里的位置原样保留（小数坐标也照旧），只裁出它和它下面 60 u
                    let frame = layout.frame
                    let origin = CGPoint(x: frame.minX.rounded(.down) - 4, y: frame.minY.rounded(.down) - 4)
                    let crop = CGSize(width: frame.width.rounded(.up) + 10, height: frame.height.rounded(.up) + 8 + 60 * u)
                    let view = ZStack(alignment: .topLeading) {
                        Color.clear
                        RDPanel(badge: badge, layout: layout, canvas: canvas)
                    }
                    .frame(width: canvas.width, height: canvas.height + 80 * u, alignment: .topLeading)
                    .offset(x: -origin.x, y: -origin.y)
                    .frame(width: crop.width, height: crop.height, alignment: .topLeading)
                    .clipped()
                    let renderer = ImageRenderer(content: view)
                    renderer.scale = 1
                    let rep = NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
                    let data = try XCTUnwrap(rep.bitmapData)
                    let bytesPerPixel = rep.bitsPerPixel / 8
                    func inked(_ rows: Range<Int>) -> Int {
                        var n = 0
                        for y in rows where y >= 0 && y < rep.pixelsHigh {
                            let row = data + y * rep.bytesPerRow
                            for i in 0..<(rep.pixelsWide * bytesPerPixel) where row[i] > 40 { n += 1 }
                        }
                        return n
                    }
                    let bottom = Int((frame.maxY - origin.y).rounded(.up))
                    XCTAssertGreaterThan(inked(bottom - Int(20 * u)..<bottom), 0, "面板确实画在裁出的这块里")
                    // 阴影（半径 4 u、下移 1 u）之外
                    XCTAssertEqual(inked(bottom + Int((10 * u).rounded(.up))..<rep.pixelsHigh), 0,
                                   "\(canvas) \(badge.title) ×\(layout.scale) \(frame)：面板底边外有内容")
                    rendered += 1
                }
            }
        }
        XCTAssertGreaterThanOrEqual(scales.count, 4, "\(scales.sorted())")
        print("[rd-flow] \(rendered) panels rendered at scales \(scales.sorted()), nothing below the panel edge")
    }

    // MARK: - 热切换（走真的设置通知）

    private func spin(until condition: () -> Bool, timeout: TimeInterval = 10) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
    }

    private func lethalSnapshot() -> RDGameSnapshot {
        let t = Table(resources: 1)
        t.opponentHero[.health] = 8
        let a = t.add("LEG_CS3_031", zone: .hand, position: 1, tags: [.cost: 1, .atk: 1, .health: 1])
        t.enchant("SCH_352e", on: a)
        return t.snapshot()
    }

    /// 改 `Settings.redDragonAssist`（UserDefault → 通知 → assistant 清空 → onChange → view model main.async 提交）：
    /// 关掉 overlay 立即消失；再开、来一个局面，overlay 出现
    func testHotSwitchShowsAndHidesOverlay() {
        let saved = Settings.redDragonAssist
        defer { Settings.redDragonAssist = saved }
        Settings.redDragonAssist = true
        spin(until: { false }, timeout: 0.05)
        let env = RedDragonAssistant.Environment(
            isEnabled: { Settings.redDragonAssist }, revealPreference: { .verdict }, quizMode: { false },
            debounce: 0, config: RedDragonConfig(), cardName: { $0 })
        let assistant = RedDragonAssistant(environment: env, observeSettings: true)
        let vm = RedDragonOverlayViewModel(assistant: assistant, cardName: Self.zh)
        XCTAssertEqual(assistant.subscriberCount, 1)
        XCTAssertNil(assistant.onChange, "overlay 不占单回调位")
        XCTAssertFalse(vm.model.isVisible)

        assistant.submit(.snapshot(lethalSnapshot()))
        spin { vm.model.badge?.title == RDText.lethal }
        XCTAssertTrue(vm.model.isVisible)
        XCTAssertEqual(vm.model.badge?.numbers, "8 / 8")

        Settings.redDragonAssist = false
        spin { !vm.model.isVisible }
        XCTAssertFalse(vm.model.isVisible, "关掉开关 overlay 消失")
        XCTAssertEqual(assistant.hint, .inactive)

        Settings.redDragonAssist = true
        spin(until: { false }, timeout: 0.1)
        assistant.submit(.snapshot(lethalSnapshot()))
        spin { vm.model.isVisible && vm.model.badge?.statuses.isEmpty == true }
        XCTAssertTrue(vm.model.isVisible, "再打开、来了局面就出现")
    }

    /// 多订阅：两个 view model 都收到；`onChange` 已被别人占着也不影响；释放的那个自动退订
    func testSubscriptionsCoexistAndUnsubscribeOnRelease() {
        let env = RedDragonAssistant.Environment(
            isEnabled: { true }, revealPreference: { .verdict }, quizMode: { false },
            debounce: 0, config: RedDragonConfig(), cardName: { $0 })
        let assistant = RedDragonAssistant(environment: env)
        var legacy = 0
        assistant.onChange = { _ in legacy += 1 }
        let kept = RedDragonOverlayViewModel(assistant: assistant, cardName: Self.zh)
        var released: RedDragonOverlayViewModel? = RedDragonOverlayViewModel(assistant: assistant, cardName: Self.zh)
        XCTAssertEqual(assistant.subscriberCount, 2)
        assistant.submit(.snapshot(lethalSnapshot()))
        spin { kept.model.badge?.title == RDText.lethal && released?.model.badge?.title == RDText.lethal }
        XCTAssertEqual(kept.model.badge?.title, RDText.lethal)
        XCTAssertEqual(released?.model.badge?.title, RDText.lethal)
        XCTAssertGreaterThan(legacy, 0)
        released = nil
        XCTAssertEqual(assistant.subscriberCount, 1, "释放后退订")
    }

    /// 「下一步」由 overlay 按结构化的步骤拼，不出现 AR LisuGB 没有字形的 ⚔
    func testStepTextAvoidsMissingGlyphs() {
        let attack = Self.step(1, .attack, attacker: .friendlyMinion(entityId: 201, cardId: Self.id(.foxyFraud)),
                               target: .enemyMinion(entityId: 301, cardId: "CS2_179"))
        XCTAssertEqual(RDText.step(attack, cardName: Self.zh), "狐人老千 攻击 森金持盾卫士")
        let face = Self.step(1, .attack, target: .enemyHero)
        XCTAssertEqual(RDText.step(face, cardName: Self.zh), "英雄 攻击 对方英雄")
        var play = Self.step(2, .playGenerated, card: .alexstrasza, target: .enemyHero)
        play.picks = [RDPick(cardId: Self.id(.shadowstep), isDraw: false)]
        XCTAssertEqual(RDText.step(play, cardName: Self.zh), "阿莱克丝塔萨 → 对方英雄（选 暗影步）")
        for scene in Self.scenes() {
            for line in RDOverlayModel.make(scene.hint, cardName: Self.zh).lines {
                XCTAssertFalse(line.text.contains("⚔"), "\(scene.file): \(line.text)")
                XCTAssertFalse(line.text.contains("▸"), "\(scene.file): \(line.text)")
            }
        }
    }

    /// 一个 runloop 里连着来的几份只提交最后一份
    func testViewModelCoalescesWithinOneRunLoopTurn() {
        let vm = RedDragonOverlayViewModel(assistant: nil, cardName: Self.zh)
        vm.receive(Self.hint(nil, phase: .computing))
        vm.receive(Self.hint(Self.sampleLethal(), level: .order))
        XCTAssertFalse(vm.model.isVisible, "提交在下一跳 main.async 里")
        spin { vm.commits > 0 }
        XCTAssertEqual(vm.commits, 1)
        XCTAssertEqual(vm.model.badge?.title, RDText.lethal)
        vm.receive(Self.hint(Self.sampleLethal(), level: .order))
        spin(until: { false }, timeout: 0.05)
        XCTAssertEqual(vm.commits, 1, "同样的内容不重新提交")
    }

    // MARK: - 热键

    func testHotkeyRules() {
        XCTAssertTrue(RedDragonHotkeys.shouldRegister(enabled: true, frontmostBundleId: RedDragonHotkeys.hearthstoneBundleId))
        XCTAssertFalse(RedDragonHotkeys.shouldRegister(enabled: false, frontmostBundleId: RedDragonHotkeys.hearthstoneBundleId))
        XCTAssertFalse(RedDragonHotkeys.shouldRegister(enabled: true, frontmostBundleId: "net.hearthsim.hstracker"))
        XCTAssertFalse(RedDragonHotkeys.shouldRegister(enabled: true, frontmostBundleId: nil))
        // 三个动作各一个键位，都是 ⌃⌥、不带 ⌘ / ⇧（HSTracker 的菜单快捷键都带 ⌘）
        XCTAssertEqual(Set(RedDragonHotkeys.bindings.map { $0.action }), Set(RedDragonHotkeys.Action.allCases))
        XCTAssertEqual(Set(RedDragonHotkeys.bindings.map { $0.keyCode }).count, 3)
        for b in RedDragonHotkeys.bindings {
            XCTAssertEqual(b.modifiers, RedDragonHotkeys.modifiers)
            XCTAssertTrue(b.display.hasPrefix("⌃⌥"))
        }
    }

    func testHotkeyActionsDriveAssistant() {
        let savedQuiz = Settings.redDragonQuizMode
        defer { Settings.redDragonQuizMode = savedQuiz }
        let env = RedDragonAssistant.Environment(
            isEnabled: { true }, revealPreference: { .verdict }, quizMode: { false },
            debounce: 0, config: RedDragonConfig(), cardName: { $0 })
        let assistant = RedDragonAssistant(environment: env)
        assistant.submit(.snapshot(lethalSnapshot()))
        spin { assistant.hint.phase == .ready }
        XCTAssertEqual(assistant.hint.revealLevel, .verdict)
        RedDragonHotkeys.perform(.raise, assistant: assistant)
        XCTAssertEqual(assistant.hint.revealLevel, .order)
        RedDragonHotkeys.perform(.lower, assistant: assistant)
        XCTAssertEqual(assistant.hint.revealLevel, .verdict)
        RedDragonHotkeys.perform(.quiz, assistant: assistant)
        XCTAssertEqual(Settings.redDragonQuizMode, !savedQuiz)
    }

    // MARK: - 不卡顿：只在自己的状态变化时重算

    /// 真的 `RootOverlayView` 里有上游视图直接读 `AppDelegate.instance().coreManager`（隐式解包）：
    /// 宿主 app 启动时它是异步建的，测试跑得早就会崩。等它建好再挂视图
    private func waitForCoreManager() throws {
        spin(until: { AppDelegate.instance().coreManager != nil }, timeout: 60)
        guard AppDelegate.instance().coreManager != nil else {
            throw XCTSkip("宿主 app 的 coreManager 60 秒内没建好")
        }
    }

    /// 把真的 `RootOverlayView` 放进离屏窗口：
    /// - 改 `RootOverlayViewModel` 上与红龙无关的 @Published（RootOverlayView 的 body 因此重算，红龙视图被重新构造），
    ///   红龙视图的 body 不重算；
    /// - 红龙状态变了：红龙视图 body 重算，`RootOverlayViewModel.objectWillChange` 不发（RootOverlayView 不重算）。
    /// 另量一次「receive → 提交 → 布局 + 绘制」的主线程耗时（Debug）
    func testRedrawOnlyOnOwnStateAndMainThreadCost() throws {
        try waitForCoreManager()
        let root = RootOverlayViewModel()
        var rootChanges = 0
        let sink = root.objectWillChange.sink { rootChanges += 1 }
        defer { sink.cancel() }
        let size = CGSize(width: 1920, height: 1080)
        let hosting = NSHostingView(rootView: RootOverlayView(viewModel: root))
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        func settle() {
            spin(until: { false }, timeout: 0.03)
            hosting.layoutSubtreeIfNeeded()
            hosting.display()
        }
        settle()

        let a = Self.sampleLethal()
        root.redDragon.receive(Self.hint(a, level: .order))
        spin { root.redDragon.commits > 0 }
        settle()
        XCTAssertTrue(root.redDragon.model.isVisible)

        // 1. 无关刷新 ×50
        let bodies0 = RedDragonOverlayView.bodyEvaluations
        let builds0 = RedDragonOverlayView.constructions
        let rootChanges0 = rootChanges
        for i in 0..<50 {
            root.interactiveRegions = [CGRect(x: i, y: 0, width: 1, height: 1)]
            settle()
        }
        let unrelatedBodies = RedDragonOverlayView.bodyEvaluations - bodies0
        let unrelatedBuilds = RedDragonOverlayView.constructions - builds0
        XCTAssertGreaterThan(rootChanges - rootChanges0, 0)
        XCTAssertGreaterThan(unrelatedBuilds, 0, "RootOverlayView 确实重算了（红龙视图被重新构造）")
        XCTAssertEqual(unrelatedBodies, 0, "无关刷新不让红龙视图 body 重算")

        // 2. 红龙状态变化 ×40（L2 斩杀 ↔ 正在算，交替）
        let rootChanges1 = rootChanges
        let bodies1 = RedDragonOverlayView.bodyEvaluations
        var costs: [Double] = []
        let alternatives = [Self.hint(a, phase: .computing, level: .order, stale: true), Self.hint(a, level: .order)]
        for i in 0..<40 {
            let commits = root.redDragon.commits
            let start = CFAbsoluteTimeGetCurrent()
            root.redDragon.receive(alternatives[i % 2])
            while root.redDragon.commits == commits {
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.001))
            }
            hosting.layoutSubtreeIfNeeded()
            hosting.display()
            costs.append(CFAbsoluteTimeGetCurrent() - start)
        }
        let ownBodies = RedDragonOverlayView.bodyEvaluations - bodies1
        XCTAssertEqual(rootChanges - rootChanges1, 0, "红龙状态变化不让 RootOverlayView 重算")
        XCTAssertGreaterThanOrEqual(ownBodies, 40)

        // 3. 展示模型 → overlay 模型的纯计算
        let makeStart = CFAbsoluteTimeGetCurrent()
        for _ in 0..<1000 { _ = RDOverlayModel.make(Self.hint(a, level: .order), cardName: Self.zh) }
        let makeCost = (CFAbsoluteTimeGetCurrent() - makeStart) / 1000

        let sorted = costs.sorted()
        let avg = costs.reduce(0, +) / Double(costs.count)
        print(String(format: "[rd-perf] unrelated root refreshes=50 rootBodyRebuilds=%d redDragonBodies=%d | "
                     + "own changes=40 redDragonBodies=%d rootWillChange=%d | receive→commit→layout+display avg %.2f ms "
                     + "median %.2f ms max %.2f ms | RDOverlayModel.make %.1f µs",
                     unrelatedBuilds, unrelatedBodies, ownBodies, rootChanges - rootChanges1,
                     avg * 1000, sorted[sorted.count / 2] * 1000, (sorted.last ?? 0) * 1000, makeCost * 1e6))
        window.contentView = nil
    }

    /// 解锁后拖对手记牌器（只改它 view model 的 @Published，松手前不存设置）：红龙面板跟着让位。
    /// 记牌器的内容 / 计数刷新、重读同样的设置不让红龙 body 重算；只有位置变了才重算
    func testPanelFollowsTrackerDragWithoutUnrelatedRedraws() throws {
        try waitForCoreManager()
        let root = RootOverlayViewModel()
        let size = CGSize(width: 1920, height: 1080)
        let hosting = NSHostingView(rootView: RootOverlayView(viewModel: root))
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        defer { window.contentView = nil }
        func settle() {
            spin(until: { false }, timeout: 0.03)
            hosting.layoutSubtreeIfNeeded()
            hosting.display()
        }
        let tracker = root.opponentTracker
        tracker.isShown = true
        root.redDragon.receive(Self.hint(Self.sampleLethal(), level: .order))
        spin { root.redDragon.commits > 0 }
        settle()
        let before = try XCTUnwrap(RedDragonOverlayView.lastPanelLayout)
        let obstacles = root.redDragon.trackers

        // 1. 无关刷新 ×50：卡牌列表、计数、重读设置（位置没变）
        let bodies0 = RedDragonOverlayView.bodyEvaluations
        let commits0 = obstacles.commits
        for i in 0..<50 {
            tracker.update(cards: [], top: [], bottom: [], sideboards: [], relatedCards: [])
            tracker.updateCardCounter(deckCount: 20 - i % 5, handCount: i % 10, hasCoin: false, gameStarted: true)
            tracker.reloadSettings()
            settle()
        }
        let unrelatedBodies = RedDragonOverlayView.bodyEvaluations - bodies0
        XCTAssertEqual(unrelatedBodies, 0, "记牌器内容刷新不让红龙 body 重算")
        XCTAssertEqual(obstacles.commits, commits0)

        // 2. 拖动 20 步：往右下拖到面板上
        let bodies1 = RedDragonOverlayView.bodyEvaluations
        let commits1 = obstacles.commits
        let savedSettings = (Settings.opponentDeckLeft, Settings.opponentDeckTop)
        for step in 1...20 {
            tracker.drag(translation: CGSize(width: CGFloat(step) * 12, height: CGFloat(step) * 12), canvasSize: size)
            settle()
        }
        let dragBodies = RedDragonOverlayView.bodyEvaluations - bodies1
        let dragCommits = obstacles.commits - commits1
        XCTAssertEqual(Settings.opponentDeckLeft, savedSettings.0, "松手前不存设置（红龙不靠设置）")
        XCTAssertEqual(Settings.opponentDeckTop, savedSettings.1)
        XCTAssertEqual(dragCommits, 20)
        XCTAssertGreaterThanOrEqual(dragBodies, 20)

        let box = try XCTUnwrap(RDOverlayGeometry.trackerBox(obstacles.state.placements[1], cardSize: obstacles.state.cardSize,
                                                              canvas: size))
        XCTAssertTrue(before.frame.intersects(box), "拖完的记牌器压在旧面板位置上（前提）")
        if let after = RedDragonOverlayView.lastPanelLayout {
            XCTAssertFalse(after.frame.intersects(box), "面板让开：\(after.frame) vs \(box)")
            XCTAssertNotEqual(after.frame, before.frame)
        }
        print("[rd-drag] unrelated tracker refreshes=50 redDragonBodies=\(unrelatedBodies) obstacleCommits=0 | "
              + "drag steps=20 obstacleCommits=\(dragCommits) redDragonBodies=\(dragBodies) | panel \(before.frame) → "
              + "\(RedDragonOverlayView.lastPanelLayout.map { "\($0.frame) scale \($0.scale) dropped \($0.droppedLines)" } ?? "hidden")")
    }

    // MARK: - 效果图（RD_RENDER_DIR）

    struct Scene {
        var file: String
        var title: String
        var hint: RedDragonHint
        var handCards: [RDCard]
        var board: [RDCard]
        var enemyBoard: [String]
        var opponentSecrets: Int = 0
        var size = CGSize(width: 1920, height: 1080)
        /// 非空时按这些参数放真的记牌器 view model（面板据此让位），示意图画它们的实际矩形
        var trackers: [RDOverlayGeometry.TrackerPlacement] = []
    }

    static func scenes() -> [Scene] {
        let hand7: [RDCard] = [.coin, .foxyFraud, .scabbsCutterbutter, .etcBandManager, .shadowcaster, .shadowstep, .evasion]
        let hand7Ids = [101, 102, 103, 104, 105, 106, 107]
        var out: [Scene] = []

        // 1. L0 可斩
        var a1 = sampleLethal()
        a1.boardMarks = []
        out.append(Scene(file: "01-L0-lethal.png", title: "L0 可斩杀（进阶，只给判定）",
                         hint: hint(a1, level: .verdict), handCards: hand7, board: [.foxyFraud, .alexstrasza],
                         enemyBoard: ["CS2_179", "CS2_179", "EX1_082"]))

        // 2. L0 不可斩 + 缺件
        let a2 = analysis(verdict: .provenNotLethal, damage: 19, health: 27, hand: hand7Ids,
                          missing: [id(.scabbsCutterbutter), id(.darkscaleBroodmother)], insufficient: true)
        out.append(Scene(file: "02-L0-not-lethal-missing.png", title: "L0 不可斩 + 缺件 + 单回合不够",
                         hint: hint(a2), handCards: [.coin, .foxyFraud, .spiritOfTheShark, .etcBandManager,
                                                      .shadowcaster, .shadowstep, .evasion],
                         board: [], enemyBoard: ["CS2_179"]))

        // 3. （原 L1 参与牌，10-06 删）
        // 4. L2 中途：已经做了 2 步，面板给「下一步」（手牌 / 场面上不再画标记）
        let hand5Ids = [103, 104, 105, 106, 107]
        let a4 = analysis(
            verdict: .lethal, damage: 34, health: 30, tier: .advanced, hand: hand5Ids,
            handMarks: [RDHandMark(entityId: 105, zonePosition: 3, role: .required),
                        RDHandMark(entityId: 106, zonePosition: 4, role: .required)],
            steps: [step(1, .attack, attacker: .friendlyMinion(entityId: 201, cardId: id(.foxyFraud)),
                         target: .enemyMinion(entityId: 302, cardId: "CS2_179")),
                    step(2, .playFromHand, card: .shadowcaster, hand: 105, zone: 3,
                         target: .friendlyMinion(entityId: 202, cardId: id(.alexstrasza))),
                    step(3, .playFromHand, card: .shadowstep, hand: 106, zone: 4,
                         target: .friendlyMinion(entityId: 203, cardId: id(.spiritOfTheShark)))],
            total: 11,
            boardMarks: [RDBoardMark(entityId: 201, isEnemy: false, stepIndex: 1, role: .attacker),
                         RDBoardMark(entityId: 302, isEnemy: true, stepIndex: 1, role: .target),
                         RDBoardMark(entityId: 202, isEnemy: false, stepIndex: 2, role: .target),
                         RDBoardMark(entityId: 203, isEnemy: false, stepIndex: 3, role: .target)],
            next: "狐人老千 ⚔ 森金持盾卫士", board: [201, 202, 203], enemyBoard: [301, 302], actions: 2)
        out.append(Scene(file: "04-L2-renumbered.png", title: "L2 中途（已出 2 步，面板给下一步；不画手牌 / 场面标记）",
                         hint: hint(a4, level: .order), handCards: [.scabbsCutterbutter, .etcBandManager, .shadowcaster,
                                                                     .shadowstep, .evasion],
                         board: [.foxyFraud, .alexstrasza, .spiritOfTheShark], enemyBoard: ["EX1_082", "CS2_179"]))

        // 5 / 6. 答题对 / 错
        out.append(Scene(file: "05-quiz-correct.png", title: "答题模式：这一步仍在斩杀线上",
                         hint: hint(sampleLethal(), level: .order, quiz: .onLine, quizMode: true), handCards: hand7,
                         board: [.foxyFraud, .alexstrasza], enemyBoard: ["CS2_179", "CS2_179", "EX1_082"]))
        let a6 = analysis(verdict: .provenNotLethal, damage: 24, health: 30, hand: [101, 102, 104, 105, 106, 107])
        out.append(Scene(file: "06-quiz-wrong.png", title: "答题模式：这一步打完已不可能斩杀",
                         hint: hint(a6, quiz: .offLine, quizMode: true),
                         handCards: [.coin, .foxyFraud, .etcBandManager, .shadowcaster, .shadowstep, .evasion],
                         board: [.scabbsCutterbutter, .alexstrasza], enemyBoard: ["CS2_179", "CS2_179", "EX1_082"]))

        // 7. 抽牌分叉
        let a7 = analysis(verdict: .lethalIfDraw, damage: 32, health: 30, tier: .advanced, hand: hand7Ids,
                          branches: [RDDrawBranch(drawn: [id(.coin)], damage: 32, isLethal: true),
                                     RDDrawBranch(drawn: [id(.shadowstep)], damage: 32, isLethal: true),
                                     RDDrawBranch(drawn: [id(.evasion)], damage: 16, isLethal: false)])
        out.append(Scene(file: "07-draw-branches.png", title: "抽牌分叉（需抽到才斩杀，L0）",
                         hint: hint(a7), handCards: [.coin, .swindle, .foxyFraud, .etcBandManager, .shadowcaster,
                                                      .spiritOfTheShark, .evasion],
                         board: [], enemyBoard: ["CS2_179", "EX1_082", "CS2_179"]))

        // 8. 危险提示
        let a8 = analysis(verdict: .provenNotLethal, damage: 16, health: 27, hand: hand7Ids,
                          missing: [id(.darkscaleBroodmother)], insufficient: true, danger: true)
        out.append(Scene(file: "08-danger.png", title: "危险提示：场面危险 + 单回合不够 + 缺件",
                         hint: hint(a8), handCards: hand7, board: [],
                         enemyBoard: ["EX1_082", "CS2_179", "CS2_179", "EX1_082", "CS2_179", "CS2_179"]))

        // 9. 正在算（上一份结论过时、变暗、不画标记）
        out.append(Scene(file: "09-computing.png", title: "正在算（旧结论过时、变暗，标记先撤）",
                         hint: hint(sampleLethal(), phase: .computing, level: .order, stale: true),
                         handCards: hand7, board: [.foxyFraud, .alexstrasza], enemyBoard: ["CS2_179", "CS2_179", "EX1_082"]))

        // 10. 对方有奥秘（L2，含打脸的英雄目标标记）
        let a10 = analysis(
            verdict: .lethal, damage: 32, health: 30, tier: .hard, hand: [111, 112, 113, 114, 115, 116],
            handMarks: [RDHandMark(entityId: 111, zonePosition: 1, role: .required),
                        RDHandMark(entityId: 113, zonePosition: 3, role: .required),
                        RDHandMark(entityId: 115, zonePosition: 5, role: .optional)],
            steps: [step(1, .playFromHand, card: .alexstrasza, hand: 111, zone: 1, target: .enemyHero),
                    step(2, .playFromHand, card: .coin, hand: 113, zone: 3),
                    step(3, .playGenerated, card: .alexstrasza, target: .enemyHero)],
            total: 9, next: "阿莱克丝塔萨 → 敌方英雄", secrets: true, enemyBoard: [])
        out.append(Scene(file: "10-opponent-secrets.png", title: "对方有奥秘（⚠ 可能误报；困难线默认开到 L2，含英雄目标）",
                         hint: hint(a10, level: .order),
                         handCards: [.alexstrasza, .evasion, .coin, .shadowstep, .preparation, .shadowcaster],
                         board: [], enemyBoard: [], opponentSecrets: 2))

        // 13 / 14. 4:3 画布、对手记牌器放大：面板让位 / 降级（Codex 复现的配置）
        let a13 = analysis(verdict: .lethalIfDraw, damage: 32, health: 30, tier: .advanced, hand: hand7Ids,
                           branches: [RDDrawBranch(drawn: [id(.coin)], damage: 32, isLethal: true),
                                      RDDrawBranch(drawn: [id(.shadowstep)], damage: 32, isLethal: true),
                                      RDDrawBranch(drawn: [id(.evasion)], damage: 16, isLethal: false)],
                           danger: true)
        let hand10: [RDCard] = [.coin, .swindle, .foxyFraud, .etcBandManager, .shadowcaster, .spiritOfTheShark, .evasion,
                                .preparation, .shadowstep, .deafen]
        let player = RDOverlayGeometry.TrackerPlacement(isOpponent: false, isShown: true, left: 99.5, top: 2, height: 88,
                                                        scaling: 100)
        out.append(Scene(file: "13-yield-tracker-150.png",
                         title: "1440×1080，对手记牌器 150% / 85% 高，10 张手牌：左下没地方，面板让位 / 降级",
                         hint: hint(a13), handCards: hand10, board: [], enemyBoard: ["CS2_179", "EX1_082"],
                         size: CGSize(width: 1440, height: 1080),
                         trackers: [player, .init(isOpponent: true, isShown: true, left: 0.5, top: 12.5, height: 85,
                                                  scaling: 150)]))
        out.append(Scene(file: "14-yield-tracker-dragged.png",
                         title: "1920×1080，对手记牌器被拖进 4:3 区域左下：面板退到它左边的黑边里（内容不减）",
                         hint: hint(a13), handCards: hand10, board: [], enemyBoard: ["CS2_179", "EX1_082"],
                         trackers: [player, .init(isOpponent: true, isShown: true, left: 12, top: 30, height: 70,
                                                  scaling: 100)]))

        // 15–21（T4）：准备线 / 等死 / 预启动 / 锁定的完整公式（全部 / 走了几步 / 已偏离）
        out.append(contentsOf: t4Scenes())
        // 28–34（T8）：破冰按键、破冰口径的面板
        out.append(contentsOf: t8Scenes())
        return out
    }

    static func t8Scenes() -> [Scene] {
        let hand7: [RDCard] = [.coin, .foxyFraud, .scabbsCutterbutter, .etcBandManager, .shadowcaster, .shadowstep, .evasion]
        var out: [Scene] = []

        // 28. 对方有奥秘、没开破冰：标签行里看得到按键（关）
        var a28 = sampleLethal()
        a28.boardMarks = []
        a28.opponentHasSecrets = true
        out.append(Scene(file: "28-ice-button-off.png", title: "T8 对方有奥秘、没开破冰：标签行里有按键（破冰：关）",
                         hint: hint(a28, level: .verdict), handCards: hand7, board: [.foxyFraud, .alexstrasza],
                         enemyBoard: ["CS2_179", "CS2_179", "EX1_082"], opponentSecrets: 1))

        func ice(_ file: String, _ title: String, _ a: RDAnalysis, secrets: Int = 1, deviated: Bool = false) -> Scene {
            return Scene(file: file, title: title,
                         hint: iceHint(a, phase: deviated ? .computing : .ready, deviated: deviated, stale: deviated),
                         handCards: hand7, board: [.spiritOfTheShark], enemyBoard: ["CS2_179"], opponentSecrets: secrets)
        }
        out.append(ice("29-ice-locked.png", "T8 破冰线锁定中（走了 1 步；冰在第 3 步碎，之后是准备步）：下回合可斩 + 前提",
                       iceAnalysis(.lethalNextTurn, formula: iceFormula(done: 1), remaining: 4, damage: 16)))
        out.append(ice("30-ice-short-next-turn.png", "T8 能破冰但下回合不够：不写差多少，写已知伤害和破冰后剩余血量",
                       iceAnalysis(.shortNextTurn, formula: iceFormula(), remaining: 9, damage: 8)))
        out.append(ice("31-ice-cannot-break.png", "T8 破不了冰（场面危险照常提醒）",
                       iceAnalysis(.cannotBreak, danger: true)))
        out.append(ice("32-ice-broken-following.png", "T8 冰已碎（对方奥秘数是 0，按键还在）：剩下的准备步照常跟手",
                       iceAnalysis(.lethalNextTurn, formula: iceFormula(done: 3), remaining: 4, damage: 16,
                                   broken: true, secrets: false), secrets: 0))
        out.append(ice("33-ice-deviated.png", "T8 破冰线打偏：旧线置灰留在原位，标「已偏离，重算中」（重算仍是破冰口径）",
                       iceAnalysis(.lethalNextTurn, formula: iceFormula(done: 1), remaining: 4, damage: 16),
                       deviated: true))
        out.append(ice("34-ice-next-turn-unprobed.png", "T8 能破冰、下回合没算完（预算用完）：不报伤害，带「被截断」",
                       iceAnalysis(.shortNextTurn, formula: iceFormula(), remaining: 9, probed: false,
                                   completeness: .truncated)))
        return out
    }

    static func tok(_ card: RDCard, _ mana: Int, target: RDFormulaTarget? = nil, original: Bool = false,
                    attack: Bool = false, draws: [RDCard] = []) -> RDFormulaToken {
        return RDFormulaToken(kind: attack ? .attack : .play, card: card, original: original, mana: mana,
                              target: target, draws: draws)
    }

    static func t4Formula(_ goal: RDFormula.Goal, done: Int = 0) -> RDFormula {
        let toks = [tok(.spiritOfTheShark, 4), tok(.foxyFraud, 2), tok(.scabbsCutterbutter, 2),
                    tok(.shadowcaster, 1), tok(.etcBandManager, 1), tok(.scabbsCutterbutter, 0),
                    tok(.darkscaleBroodmother, 4), tok(.bounceAround, 4), tok(.shadowOfDemise, 4, original: true),
                    tok(.alexstrasza, 0, target: goal == .lethal ? .enemyHero : .ownHero)]
        var f = RDFormula(goal: goal, tokens: toks, done: done)
        if goal != .lethal {
            f.leftBoard = [.spiritOfTheShark, .foxyFraud, .alexstrasza, .darkscaleBroodmother]
            f.leftHand = [.scabbsCutterbutter, .shadowcaster]
            f.potential = 32
        }
        return f
    }

    static func t4Scenes() -> [Scene] {
        let hand7: [RDCard] = [.coin, .foxyFraud, .scabbsCutterbutter, .etcBandManager, .shadowcaster, .shadowstep, .evasion]
        let hand7Ids = [101, 102, 103, 104, 105, 106, 107]
        let enemy = ["EX1_082", "CS2_179", "CS2_179", "EX1_082", "CS2_179", "CS2_179"]
        var out: [Scene] = []

        func setupScene(_ file: String, _ title: String, _ kind: RDSetupAdvice.Kind, danger: Bool) -> Scene {
            var a = analysis(verdict: .provenNotLethal, damage: 16, health: 27, hand: hand7Ids, danger: danger)
            a.setup = RDSetupAdvice(kind: kind, formula: kind == .doomed ? nil
                                    : t4Formula(kind == .heal16 ? .heal16 : .preLaunch))
            return Scene(file: file, title: title, hint: hint(a), handCards: hand7, board: [], enemyBoard: enemy)
        }
        out.append(setupScene("15-danger-heal16.png", "危险且斩不了：奶 16 线（完整公式 + 回合末留下什么 + 下回合潜力）",
                              .heal16, danger: true))
        out.append(setupScene("16-doomed.png", "危险、斩不了、奶 16 凑不出：等死", .doomed, danger: true))
        out.append(setupScene("17-prelaunch.png", "预启动线（不危险时的准备线，区别于斩杀线）", .preLaunch, danger: false))

        func lethalScene(_ file: String, _ title: String, done: Int, deviated: Bool = false) -> Scene {
            var a = sampleLethal()
            a.boardMarks = []
            a.formula = t4Formula(.lethal, done: done)
            var h = hint(a, level: .order)
            h.locked = !deviated
            h.deviated = deviated
            return Scene(file: file, title: title, hint: h, handCards: hand7, board: [.foxyFraud, .alexstrasza],
                         enemyBoard: ["CS2_179", "CS2_179", "EX1_082"])
        }
        out.append(lethalScene("18-formula-locked.png", "「顺序」档：锁定的完整斩杀公式（一步没走）", done: 0))
        out.append(lethalScene("19-formula-progress.png", "锁定公式走了 5 步（已完成划掉，当前步高亮）", done: 5))
        out.append(lethalScene("20-formula-deviated.png", "锁定的线走不通：旧公式置灰留在原位，标「已偏离，重算中」",
                               done: 3, deviated: true))

        // 21–27（T6）：放大后的面板，10 张手牌；16:9 / 4:3 / 16:10，没有记牌器挡路和默认记牌器（72% 高）两种
        let hand10: [RDCard] = hand7 + [.preparation, .swindle, .deafen]
        let player = RDOverlayGeometry.TrackerPlacement(isOpponent: false, isShown: true, left: 99.5, top: 2, height: 88,
                                                        scaling: 100)
        let opponent = RDOverlayGeometry.TrackerPlacement(isOpponent: true, isShown: true, left: 0.5, top: 12.5, height: 72,
                                                          scaling: 100)
        func big(_ file: String, _ title: String, from source: String, size: CGSize, trackers: Bool) -> Scene {
            var s = out.first { $0.file == source }!
            s.file = file
            s.title = title
            s.handCards = hand10
            s.size = size
            s.trackers = trackers ? [player, opponent] : []
            return s
        }
        let wide = CGSize(width: 1920, height: 1080)
        let narrow = CGSize(width: 1440, height: 1080)
        out.append(big("21-big-formula-169.png", "T6 16:9，10 张手牌，锁定公式", from: "18-formula-locked.png",
                       size: wide, trackers: false))
        out.append(big("22-big-heal16-169.png", "T6 16:9，10 张手牌，奶 16", from: "15-danger-heal16.png",
                       size: wide, trackers: false))
        out.append(big("23-big-formula-43.png", "T6 4:3，10 张手牌，锁定公式", from: "18-formula-locked.png",
                       size: narrow, trackers: false))
        out.append(big("24-big-heal16-43.png", "T6 4:3，10 张手牌，奶 16", from: "15-danger-heal16.png",
                       size: narrow, trackers: false))
        out.append(big("25-big-formula-169-default-tracker.png", "T6 16:9，默认记牌器（72% 高），锁定公式",
                       from: "18-formula-locked.png", size: wide, trackers: true))
        out.append(big("26-big-heal16-43-default-tracker.png", "T6 4:3，默认记牌器（72% 高），奶 16",
                       from: "15-danger-heal16.png", size: narrow, trackers: true))
        out.append(big("27-big-formula-1610-default-tracker.png", "T6 16:10，默认记牌器（72% 高），锁定公式",
                       from: "18-formula-locked.png", size: CGSize(width: 1728, height: 1117), trackers: true))
        return out
    }

    @MainActor
    func testRenderGallery() throws {
        guard let dir = ProcessInfo.processInfo.environment["RD_RENDER_DIR"], !dir.isEmpty else {
            throw XCTSkip("设 TEST_RUNNER_RD_RENDER_DIR 才渲染效果图")
        }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for var scene in Self.scenes() {
            let size = scene.size
            let trackerVMs: [TrackerPanelViewModel] = scene.trackers.map { p in
                let t = TrackerPanelViewModel(playerType: p.isOpponent ? .opponent : .player)
                t.isShown = p.isShown
                t.left = p.left
                t.top = p.top
                t.height = p.height
                t.scaling = p.scaling
                return t
            }
            let vm = RedDragonOverlayViewModel(assistant: nil, trackers: trackerVMs, cardName: Self.zh)
            vm.receive(scene.hint)
            spin { vm.commits > 0 || !RDOverlayModel.make(scene.hint, cardName: Self.zh).isVisible }
            let boxes = scene.trackers.isEmpty ? nil : vm.trackers.boxes(canvas: size)
            // 标题后面注上面板实际的缩放档和像素
            if let badge = vm.model.badge {
                let layout = RDOverlayGeometry.panelLayout(canvas: size, badge: badge, lines: vm.model.lines,
                                                           trackers: boxes ?? [])
                scene.title += layout.map { String(format: "｜面板 ×%.2f，%.0f×%.0f px", $0.scale, $0.frame.width,
                                                    $0.frame.height) } ?? "｜面板不画"
            }
            let view = ZStack(alignment: .topLeading) {
                RDSchematicBoard(scene: scene, canvas: size, trackerBoxes: boxes)
                RedDragonOverlayView(viewModel: vm, canvasSize: size)
            }
            .frame(width: size.width, height: size.height)
            try writePNG(view, size: size, to: (dir as NSString).appendingPathComponent(scene.file))
            withExtendedLifetime(trackerVMs) {}
        }
        try renderSettings(dir: dir)
    }

    @MainActor
    private func writePNG<V: View>(_ view: V, size: CGSize, to path: String) throws {
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(size)
        renderer.scale = 1
        guard let cg = renderer.cgImage else { throw NSError(domain: "render", code: 1) }
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let data = rep.representation(using: .png, properties: [:]) else { throw NSError(domain: "render", code: 2) }
        try data.write(to: URL(fileURLWithPath: path))
    }

    /// 设置页亮 / 暗：AppKit 控件 ImageRenderer 画不出来，放进离屏窗口用 cacheDisplay 抓
    private func renderSettings(dir: String) throws {
        let saved = (Settings.redDragonAssist, Settings.redDragonRevealLevel, Settings.redDragonQuizMode)
        defer {
            Settings.redDragonAssist = saved.0
            Settings.redDragonRevealLevel = saved.1
            Settings.redDragonQuizMode = saved.2
        }
        Settings.redDragonAssist = true
        Settings.redDragonRevealLevel = RDRevealLevel.order.rawValue
        Settings.redDragonQuizMode = false
        for (name, appearance) in [("11-settings-light.png", NSAppearance.Name.aqua), ("12-settings-dark.png", .darkAqua)] {
            let pane = RedDragonPreferences()
            let content = pane.view
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: PreferencePaneController.fixedWidth, height: 400),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            let look = NSAppearance(named: appearance)
            window.appearance = look
            let container = NSView(frame: window.contentRect(forFrameRect: window.frame))
            container.wantsLayer = true
            container.appearance = look
            window.contentView = container
            container.addSubview(content)
            NSLayoutConstraint.activate([
                content.topAnchor.constraint(equalTo: container.topAnchor),
                content.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                content.widthAnchor.constraint(equalToConstant: PreferencePaneController.fixedWidth)
            ])
            container.layoutSubtreeIfNeeded()
            let fit = content.fittingSize
            window.setContentSize(NSSize(width: PreferencePaneController.fixedWidth, height: fit.height))
            container.frame = CGRect(origin: .zero, size: window.contentRect(forFrameRect: window.frame).size)
            spin(until: { false }, timeout: 0.2)
            container.layoutSubtreeIfNeeded()
            look?.performAsCurrentDrawingAppearance {
                container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            }
            container.display()
            guard let rep = container.bitmapImageRepForCachingDisplay(in: container.bounds) else { continue }
            container.cacheDisplay(in: container.bounds, to: rep)
            if let data = rep.representation(using: .png, properties: [:]) {
                try data.write(to: URL(fileURLWithPath: (dir as NSString).appendingPathComponent(name)))
            }
            window.contentView = nil
        }
    }
}

/// 效果图背景：手牌 / 场面 / 英雄位置的示意（不是游戏截图），以及现有组件的占位（虚线框）。
/// 手牌和随从的位置用 overlay 自己的几何公式，所以标记落点和真实对局一致
private struct RDSchematicBoard: View {
    let scene: RedDragonOverlayTests.Scene
    let canvas: CGSize
    /// 记牌器的实际矩形（nil = 画默认位置的示意框）
    var trackerBoxes: [CGRect]?

    var body: some View {
        let h = canvas.height
        let ratio = BoardOverlayView.ratio(canvas)
        let x43 = { (f: CGFloat) in SizeHelper.getScaledXPos(f, width: canvas.width, ratio: ratio) }
        let badge = RDOverlayGeometry.badgeSize(canvas)
        ZStack(alignment: .topLeading) {
            Color(red: 0.10, green: 0.08, blue: 0.07)
            // 4:3 游戏区
            RoundedRectangle(cornerRadius: 30)
                .fill(LinearGradient(colors: [Color(red: 0.42, green: 0.33, blue: 0.22), Color(red: 0.30, green: 0.23, blue: 0.15)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: h * 4 / 3, height: h)
                .position(x: canvas.width / 2, y: h / 2)
            Ellipse().fill(Color(red: 0.55, green: 0.47, blue: 0.33).opacity(0.6))
                .frame(width: h * 1.05, height: h * 0.5).position(x: canvas.width / 2, y: h * 0.48)
            // 标题放左上（16:9 在黑边里；4:3 没有黑边，压在左上角空地）
            caption(scene.title)
                .frame(width: max((canvas.width - h * 4 / 3) / 2 - 20, 420), alignment: .topLeading)
                .offset(x: 10, y: 10)

            // 英雄
            hero("敌方英雄" + (scene.opponentSecrets > 0 ? "（奥秘 ×\(scene.opponentSecrets)）" : ""), y: h * 0.19, health: "30")
            hero("我方英雄", y: h * 0.78, health: "30")
            // 现有组件的占位（虚线框 = 现有组件，不属于红龙）
            placeholder("我方场攻", CGRect(x: x43(0.255), y: h * 0.6762, width: 75, height: 75))
            placeholder("我方计数器", CGRect(x: x43(0.677), y: h * 0.684, width: 210, height: 51))
            placeholder("我方生效中", CGRect(x: x43(0.662), y: h * 0.716 + 52, width: 120, height: 40))
            placeholder("对方计数器", CGRect(x: x43(0.677), y: h - 51 - h * 0.706, width: 210, height: 51))
            placeholder("对方场攻", CGRect(x: x43(0.255), y: h * 0.2239, width: 75, height: 75))
            placeholder("法力", CGRect(x: x43(0.752), y: h * 0.956, width: 160, height: 40))
            if let trackerBoxes {
                ForEach(Array(trackerBoxes.enumerated()), id: \.offset) { i, box in
                    placeholder(box.minX < canvas.width / 2 ? "对手记牌器（实际矩形）" : "我方记牌器（实际矩形）",
                                box.intersection(CGRect(origin: .zero, size: canvas)))
                }
            } else {
                placeholder("对手记牌器", CGRect(x: canvas.width * 0.005, y: h * 0.125, width: 171, height: h * 0.6))
                placeholder("我方记牌器", CGRect(x: canvas.width * 0.995 - 171, y: h * 0.02, width: 171, height: h * 0.8))
            }
            placeholder("对方手牌标记", CGRect(x: canvas.width / 2 - 220, y: 4, width: 440, height: 40))

            // 场面
            ForEach(Array(scene.enemyBoard.enumerated()), id: \.offset) { i, cardId in
                minion(RDOverlayGeometry.minionRect(isEnemy: true, index: i, count: scene.enemyBoard.count, canvas: canvas),
                       name: cardId == "CS2_179" ? "森金持盾卫士" : "疯狂投弹者", order: i + 1, badge: badge)
            }
            ForEach(Array(scene.board.enumerated()), id: \.offset) { i, card in
                minion(RDOverlayGeometry.minionRect(isEnemy: false, index: i, count: scene.board.count, canvas: canvas),
                       name: RedDragonOverlayTests.zh(RedDragonOverlayTests.id(card)), order: i + 1, badge: badge)
            }
            // 手牌
            ForEach(Array(scene.handCards.enumerated()), id: \.offset) { i, card in
                let c = RDOverlayGeometry.handCard(index: i, count: scene.handCards.count, canvas: canvas)
                let size = RDOverlayGeometry.handCardSize(canvas)
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: size.width * 0.1)
                        .fill(Color(red: 0.20, green: 0.17, blue: 0.24))
                        .overlay(RoundedRectangle(cornerRadius: size.width * 0.1).stroke(Color.black.opacity(0.7), lineWidth: 2))
                    Text(verbatim: RedDragonOverlayTests.zh(RedDragonOverlayTests.id(card)))
                        .font(.custom("AR LisuGB Medium", size: 13))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.top, size.height * 0.3)
                        .padding(.horizontal, 6)
                }
                .frame(width: size.width, height: size.height)
                .rotationEffect(.degrees(c.angle))
                .position(c.center)
            }
            // 手牌禁区（1~10 张的外接框并集）：红色虚线
            let hand = RDOverlayGeometry.handBox(canvas)
            Rectangle().stroke(Color.red.opacity(0.8), style: StrokeStyle(lineWidth: 2, dash: [8, 5]))
                .frame(width: hand.width, height: hand.height)
                .position(x: hand.midX, y: hand.midY)
        }
        .frame(width: canvas.width, height: canvas.height, alignment: .topLeading)
    }

    private func caption(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.custom("AR LisuGB Medium", size: 17))
            .foregroundColor(.white.opacity(0.9))
            .fixedSize(horizontal: false, vertical: true)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.5)))
    }

    private func hero(_ name: String, y: CGFloat, health: String) -> some View {
        let d = canvas.height * 0.15
        return ZStack {
            Circle().fill(Color(red: 0.25, green: 0.22, blue: 0.20)).overlay(Circle().stroke(Color.black, lineWidth: 3))
            Text(verbatim: name).font(.custom("AR LisuGB Medium", size: 14)).foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center).frame(width: d * 0.9)
        }
        .frame(width: d, height: d)
        .position(x: canvas.width / 2, y: y)
    }

    private func placeholder(_ name: String, _ rect: CGRect) -> some View {
        Text(verbatim: name)
            .font(.custom("AR LisuGB Medium", size: 12))
            .foregroundColor(.white.opacity(0.55))
            .frame(width: rect.width, height: rect.height)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
            .position(x: rect.midX, y: rect.midY)
    }

    private func minion(_ rect: CGRect, name: String, order: Int, badge: CGFloat) -> some View {
        ZStack(alignment: .top) {
            Ellipse().fill(Color(red: 0.33, green: 0.30, blue: 0.27)).overlay(Ellipse().stroke(Color.black, lineWidth: 2))
                .frame(width: rect.width * 0.85, height: rect.height * 0.9)
                .frame(width: rect.width, height: rect.height)
            Text(verbatim: name).font(.custom("AR LisuGB Medium", size: 12)).foregroundColor(.white.opacity(0.85))
                .multilineTextAlignment(.center).frame(width: rect.width * 0.8)
                .padding(.top, rect.height * 0.4)
            // 现有组件：入场序号（黑底白字，挂在格子上沿）
            Text(verbatim: "\(order)")
                .font(.system(size: badge * 0.6, weight: .bold)).foregroundColor(.white)
                .frame(minWidth: badge).frame(height: badge)
                .background(Capsule().fill(Color.black)).overlay(Capsule().strokeBorder(Color.white, lineWidth: 1))
                .offset(y: BoardOrderSlotViewModel.badgeTopMargin(height: rect.height))
        }
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
    }
}
