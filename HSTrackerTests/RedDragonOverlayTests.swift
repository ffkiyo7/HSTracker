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
        XCTAssertTrue(computing.handMarks.isEmpty)
    }

    /// L0 只有角标；L1 加手牌高亮（必打 / 可选）、没有序号；L2 加序号、场面标记、「下一步」
    func testRevealLevelsGateMarks() {
        let a = Self.sampleLethal()
        let l0 = RDOverlayModel.make(Self.hint(a, level: .verdict), cardName: Self.zh)
        XCTAssertEqual(l0.badge?.title, RDText.lethal)
        XCTAssertEqual(l0.badge?.numbers, "32 / 30")
        XCTAssertEqual(l0.badge?.margin, "+2")
        XCTAssertEqual(l0.badge?.tier, "进阶")
        XCTAssertTrue(l0.handMarks.isEmpty)
        XCTAssertTrue(l0.boardMarks.isEmpty)
        XCTAssertTrue(l0.lines.isEmpty)

        let l1 = RDOverlayModel.make(Self.hint(a, level: .cards), cardName: Self.zh)
        XCTAssertEqual(l1.handMarks.map { $0.entityId }, [101, 103, 106])
        XCTAssertEqual(l1.handMarks.map { $0.role }, [.optional, .required, .required])
        XCTAssertTrue(l1.handMarks.allSatisfy { $0.steps.isEmpty })
        XCTAssertTrue(l1.boardMarks.isEmpty)
        XCTAssertFalse(l1.lines.contains { $0.kind == .nextStep })

        let l2 = RDOverlayModel.make(Self.hint(a, level: .order), cardName: Self.zh)
        XCTAssertEqual(l2.handMarks.first { $0.entityId == 103 }?.steps, [1])
        XCTAssertEqual(l2.handMarks.first { $0.entityId == 106 }?.steps, [3])
        XCTAssertEqual(l2.handMarks.first { $0.entityId == 103 }?.index, 2)
        XCTAssertEqual(l2.handMarks.first { $0.entityId == 103 }?.count, 7)
        XCTAssertEqual(l2.boardMarks.map { $0.entityId }, [201, 202, 301])
        XCTAssertEqual(l2.boardMarks.first { $0.entityId == 301 }?.index, 1)
        XCTAssertEqual(l2.boardMarks.first { $0.entityId == 301 }?.count, 3)
        XCTAssertEqual(l2.boardMarks.first { $0.entityId == 301 }?.isTarget, true)
        XCTAssertEqual(l2.boardMarks.first { $0.entityId == 201 }?.isTarget, false)
        XCTAssertEqual(l2.lines.first?.kind, .nextStep)
        XCTAssertEqual(l2.lines.first?.text, "下一步：斯卡布斯·刀油（共 14 步）")
    }

    /// 基础线封顶 L1：请求 L2 也不出序号（封顶在展示模型里，overlay 照 `revealLevel` 画）
    func testBasicLineCappedAtCards() {
        var a = Self.sampleLethal()
        a.tier = .basic
        let m = RDOverlayModel.make(Self.hint(a, level: .order), cardName: Self.zh)
        XCTAssertEqual(m.badge?.level, .cards)
        XCTAssertEqual(m.badge?.maxLevel, .cards)
        XCTAssertFalse(m.handMarks.isEmpty)
        XCTAssertTrue(m.handMarks.allSatisfy { $0.steps.isEmpty })
        XCTAssertTrue(m.boardMarks.isEmpty)
    }

    /// 答题模式：不画高亮和序号，角标旁给对 / 错
    func testQuizModeHidesMarksAndShowsJudgement() {
        let a = Self.sampleLethal()
        let right = RDOverlayModel.make(Self.hint(a, level: .order, quiz: .onLine, quizMode: true), cardName: Self.zh)
        XCTAssertTrue(right.handMarks.isEmpty)
        XCTAssertTrue(right.boardMarks.isEmpty)
        XCTAssertTrue(right.heroTargetSteps.isEmpty)
        XCTAssertFalse(right.lines.contains { $0.kind == .nextStep })
        XCTAssertEqual(right.badge?.quizMode, true)
        XCTAssertEqual(right.badge?.quiz, .onLine)
        let wrong = RDOverlayModel.make(Self.hint(Self.analysis(verdict: .provenNotLethal, damage: 21, health: 30),
                                                  quiz: .offLine, quizMode: true), cardName: Self.zh)
        XCTAssertEqual(wrong.badge?.quiz, .offLine)
        XCTAssertEqual(wrong.badge?.title, RDText.provenNotLethal)
        XCTAssertEqual(wrong.badge?.margin, "差 9")
    }

    /// 过时 / 正在算：只留变暗的角标，不画标记和建议（排位可能已经变了）
    func testStaleHidesMarksKeepsBadge() {
        let a = Self.sampleLethal()
        for h in [Self.hint(a, phase: .computing, level: .order, stale: true), Self.hint(a, level: .order, stale: true)] {
            let m = RDOverlayModel.make(h, cardName: Self.zh)
            XCTAssertTrue(m.isVisible)
            XCTAssertEqual(m.badge?.dimmed, true)
            XCTAssertTrue(m.badge?.statuses.contains(.stale) ?? false)
            XCTAssertTrue(m.handMarks.isEmpty)
            XCTAssertTrue(m.boardMarks.isEmpty)
            XCTAssertTrue(m.lines.isEmpty)
        }
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

    /// 场面格子按占格实体排（地标也占格）：随从前面有一个地标时落在第 2 格
    func testBoardMarksCountLocationsAsSlots() {
        var a = Self.sampleLethal()
        a.opponentBoardSlots = [399, 300, 301, 302]
        let m = RDOverlayModel.make(Self.hint(a, level: .order), cardName: Self.zh)
        XCTAssertEqual(m.boardMarks.first { $0.entityId == 301 }?.index, 2)
        XCTAssertEqual(m.boardMarks.first { $0.entityId == 301 }?.count, 4)
    }

    // MARK: - 重编号后序号落到正确的 entity（走真的读取 + 搜索 + 展示模型）

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

    /// 手牌 [阿莱 a, 闪避, 阿莱 b]，对方 16 血：L2 的 1、2 落在 a、b 所在的第 1、3 张。
    /// 打出 a 后重算：手牌变成 [闪避, b]，第 1 步落在 b、也就是现在的第 2 张（不是原来第 1 张的位置）
    func testRenumberedStepLandsOnEntity() {
        let t = Table(resources: 2)
        t.opponentHero[.health] = 16
        let a = t.add("LEG_CS3_031", zone: .hand, position: 1, tags: [.cost: 1, .atk: 1, .health: 1])
        t.enchant("SCH_352e", on: a)
        let evasion = t.add("LOOT_214", zone: .hand, position: 2)
        let b = t.add("LEG_CS3_031", zone: .hand, position: 3, tags: [.cost: 1, .atk: 1, .health: 1])
        t.enchant("SCH_352e", on: b)

        let first = RDOverlayModel.make(Self.hint(analyze(t.snapshot()), level: .order), cardName: { $0 })
        let firstSteps = first.handMarks.filter { !$0.steps.isEmpty }
        XCTAssertEqual(Set(firstSteps.map { $0.entityId }), [a.id, b.id])
        XCTAssertEqual(Set(firstSteps.flatMap { $0.steps }), [1, 2])
        XCTAssertEqual(firstSteps.first { $0.entityId == a.id }?.index, 0)
        XCTAssertEqual(firstSteps.first { $0.entityId == b.id }?.index, 2)
        XCTAssertTrue(firstSteps.allSatisfy { $0.count == 3 })
        XCTAssertEqual(first.heroTargetSteps, [1, 2])

        a[.zone] = Zone.play.rawValue
        a[.zone_position] = 1
        a[.exhausted] = 1
        t.player[.resources_used] = 1
        t.player[.num_cards_played_this_turn] = 1
        t.player[.num_options_played_this_turn] = 1
        t.opponentHero[.damage] = 8
        evasion[.zone_position] = 1
        b[.zone_position] = 2
        let second = RDOverlayModel.make(Self.hint(analyze(t.snapshot()), level: .order), cardName: { $0 })
        let secondSteps = second.handMarks.filter { !$0.steps.isEmpty }
        XCTAssertEqual(secondSteps.map { $0.entityId }, [b.id])
        XCTAssertEqual(secondSteps.first?.steps, [1])
        XCTAssertEqual(secondSteps.first?.index, 1)
        XCTAssertEqual(secondSteps.first?.count, 2)
        XCTAssertNil(second.handMarks.first { $0.entityId == a.id }, "打出去的牌不再有标记")
    }

    // MARK: - 几何：不和现有组件重叠

    /// 最高的面板：标签行（进阶 + 被截断 + 奥秘）+ 6 行文字（3 条分叉 + 缺件 + 单回合不够 + 危险），长卡名
    static func tallestPanel() -> RDOverlayModel {
        let a = analysis(verdict: .lethalIfDraw, damage: 32, health: 30, tier: .advanced,
                         branches: [RDDrawBranch(drawn: [id(.scabbsCutterbutter), id(.darkscaleBroodmother)], damage: 32, isLethal: true),
                                    RDDrawBranch(drawn: [id(.shadowOfDemise), id(.spiritOfTheShark)], damage: 31, isLethal: true),
                                    RDDrawBranch(drawn: [id(.evasion)], damage: 16, isLethal: false)],
                         missing: [id(.scabbsCutterbutter), id(.darkscaleBroodmother), id(.shroudOfConcealment)],
                         insufficient: true, danger: true, secrets: true, completeness: .truncated)
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
    /// 常见的 L2 面板在 16:9 下原样（×1）放在默认位置
    func testPanelClearOfHandAndWidgets() {
        let usual = RDOverlayModel.make(Self.hint(Self.sampleLethal(), level: .order), cardName: Self.zh)
        let wide = CGSize(width: 1920, height: 1080)
        let usualLayout = RDOverlayGeometry.panelLayout(canvas: wide, badge: usual.badge!, lines: usual.lines, trackers: [])
        XCTAssertEqual(usualLayout?.scale, 1)
        XCTAssertEqual(usualLayout?.frame.minX ?? 0,
                       SizeHelper.getScaledXPos(RDOverlayGeometry.panelInsetFraction, width: wide.width,
                                                ratio: BoardOverlayView.ratio(wide)), accuracy: 0.5)
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
        for model in [Self.tallestPanel(), RDOverlayModel.make(Self.hint(Self.sampleLethal(), level: .order), cardName: Self.zh)] {
            let layout = RDOverlayGeometry.panelLayout(canvas: canvas, badge: model.badge!, lines: model.lines,
                                                       trackers: [tracker])
            guard let frame = layout?.frame else { continue }
            XCTAssertFalse(frame.intersects(tracker), "\(frame) \(tracker)")
            for card in Self.handCardBounds(canvas) {
                XCTAssertFalse(frame.intersects(card), "panel \(frame) card \(card)")
            }
        }
        // 72% 高的默认记牌器（底在 84.5% H）不挡面板：不挪、不缩
        let short = RDOverlayGeometry.trackerBox(
            .init(isOpponent: true, isShown: true, left: 0.5, top: 12.5, height: 72, scaling: 100),
            cardSize: .big, canvas: canvas)!
        let m = RDOverlayModel.make(Self.hint(Self.sampleLethal(), level: .order), cardName: Self.zh)
        let free = RDOverlayGeometry.panelLayout(canvas: canvas, badge: m.badge!, lines: m.lines, trackers: [])
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
        let models = [Self.tallestPanel(),
                      RDOverlayModel.make(Self.hint(Self.sampleLethal(), level: .order), cardName: Self.zh),
                      RDOverlayModel.make(Self.hint(Self.sampleLethal(), level: .order, quiz: .onLine, quizMode: true), cardName: Self.zh)]
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
                                        let inset = SizeHelper.getScaledXPos(RDOverlayGeometry.panelInsetFraction, width: canvas.width,
                                                                             ratio: BoardOverlayView.ratio(canvas))
                                        let aboveHand = abs(f.maxY - (handBox.minY - RDOverlayGeometry.panelGap * canvas.height / 1080)) < 0.5
                                        let key = layout.hidesNumbers ? "numbers-hidden"
                                            : layout.droppedLines > 0 ? "lines-dropped"
                                            : abs(f.maxY - canvas.height * RDOverlayGeometry.panelBottomFraction) > 0.5
                                                ? (aboveHand ? "above-hand" : "above-tracker")
                                            : f.minX > inset + 0.5 ? "moved-right"
                                            : f.minX < inset - 0.5 ? "canvas-left"
                                            : layout.scale < 1 ? "default-shrunk"
                                            : "default"
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

    /// 估计值只会偏大：实测面板内容（NSHostingView）的高不超过 `RDPanelMetrics.height`，
    /// 去掉文字行后的理想宽（标题行 / 标签行不截断所需）不超过 `minWidth`
    @MainActor
    func testPanelMetricsAreUpperBounds() {
        var models = Self.scenes().map { RDOverlayModel.make($0.hint, cardName: Self.zh) }.filter { $0.isVisible }
        models.append(Self.tallestPanel())
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

    /// 场面标记挂在随从格下沿，入场序号挂在上沿（`badgeTopMargin`）：两者纵向不重叠
    func testBoardMarksClearOfEntryOrderBadges() {
        let canvas = CGSize(width: 1920, height: 1080)
        let badge = RDOverlayGeometry.badgeSize(canvas)
        for isEnemy in [false, true] {
            let rect = RDOverlayGeometry.minionRect(isEnemy: isEnemy, index: 3, count: 7, canvas: canvas)
            let entryTop = rect.minY + BoardOrderSlotViewModel.badgeTopMargin(height: rect.height)
            let entry = CGRect(x: rect.midX - badge, y: entryTop, width: 2 * badge, height: badge)
            let center = RDOverlayGeometry.boardMarkCenter(rect, canvas: canvas)
            let mark = CGRect(x: center.x - badge, y: center.y - badge * 0.6, width: 2 * badge, height: badge * 1.2)
            XCTAssertFalse(entry.intersects(mark))
        }
        // 英雄目标标记不压到对方场面中间那格的入场序号
        let hero = RDOverlayGeometry.heroTargetCenter(canvas)
        let middle = RDOverlayGeometry.minionRect(isEnemy: true, index: 3, count: 7, canvas: canvas)
        XCTAssertLessThan(hero.y + badge * 0.6, middle.minY + BoardOrderSlotViewModel.badgeTopMargin(height: middle.height))
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
        XCTAssertEqual(assistant.hint.revealLevel, .cards)
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

        // 3. L1 参与牌
        out.append(Scene(file: "03-L1-cards.png", title: "L1 参与牌（实线必打 / 虚线可选）",
                         hint: hint(sampleLethal(), level: .cards), handCards: hand7, board: [.foxyFraud, .alexstrasza],
                         enemyBoard: ["CS2_179", "CS2_179", "EX1_082"]))

        // 4. L2 中途重编号：已经做了 2 步（手里少了两张），剩下的重新从 1 编
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
        out.append(Scene(file: "04-L2-renumbered.png", title: "L2 中途重编号（已出 2 步，剩下的从 1 重编；场面目标标记）",
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
                         title: "1440×1080，对手记牌器 150% / 85% 高，10 张手牌：左下没地方，面板贴到记牌器头顶（收起各行、去掉伤害数字）",
                         hint: hint(a13), handCards: hand10, board: [], enemyBoard: ["CS2_179", "EX1_082"],
                         size: CGSize(width: 1440, height: 1080),
                         trackers: [player, .init(isOpponent: true, isShown: true, left: 0.5, top: 12.5, height: 85,
                                                  scaling: 150)]))
        out.append(Scene(file: "14-yield-tracker-dragged.png",
                         title: "1920×1080，对手记牌器被拖进 4:3 区域左下：面板退到它左边的黑边里（缩到 ×0.72，内容不减）",
                         hint: hint(a13), handCards: hand10, board: [], enemyBoard: ["CS2_179", "EX1_082"],
                         trackers: [player, .init(isOpponent: true, isShown: true, left: 12, top: 30, height: 70,
                                                  scaling: 100)]))
        return out
    }

    @MainActor
    func testRenderGallery() throws {
        guard let dir = ProcessInfo.processInfo.environment["RD_RENDER_DIR"], !dir.isEmpty else {
            throw XCTSkip("设 TEST_RUNNER_RD_RENDER_DIR 才渲染效果图")
        }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for scene in Self.scenes() {
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
        Settings.redDragonRevealLevel = 1
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
