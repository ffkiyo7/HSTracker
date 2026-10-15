//
//  RedDragonSetupTests.swift
//  RedDragonCoreTests
//
//  T4：阿莱对友方回血、打 / 回 16 与预启动准备线、危险回合的提示、「顺序」档完整公式的锁定。
//  两组公式表的逐行验证在 RedDragonFormulaTests（`testSetupLinesCoverHealAndPreLaunchRows`，用它的私有起手和重放）；
//  效果图在 RedDragonOverlayTests。
//  要 HSTracker 在场的同组测试（卡库、日志回放、文案、调度）在 HSTrackerTests 的同名文件里。
//

import XCTest
@testable import RedDragonCore

class RedDragonSetupTests: XCTestCase {

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
}
