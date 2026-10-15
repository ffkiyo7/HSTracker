//
//  RedDragonTests.swift
//  HSTrackerTests
//
//  红龙贼搜索核心（spike RDR / T1）的规则单测。
//  公式表 fixture 的逐行重放 / 反推 / 齐件缺件分组在 RedDragonFormulaTests.swift（T2a）。
//  只碰引擎的测试在 Packages/RedDragonCore/Tests/RedDragonCoreTests/ 的同名文件里（`swift test` 直接跑）；
//  这里只留要 HSTracker 在场的（卡库、日志回放、文案、调度）。
//

import XCTest
@testable import HSTracker
@testable import RedDragonCore

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
}
