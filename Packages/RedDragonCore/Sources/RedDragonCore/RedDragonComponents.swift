//
//  RedDragonComponents.swift
//  HSTracker
//
//  起手局面的「随从组件齐不齐」。由局面本身判定，不看公式表的组名。
//
//  组件 = 主牌库里的 6 张随从（鱼 / 狐 / 刀 / 暗 / 牛 / 晦）。理由：
//  ① 公式表每一条线都是这 6 张的排列，加上边牌三张；② 边牌（龙 / 舞 / 幻）只能经牛发现，
//  不会在起手里，它们是牛的产物而不是组件；③ 法术（步 / 骨 / 伺 / 殒 / 币）在表里归「特殊杂牌」，
//  是减费 / 腾格手段，有替代品，缺了改的是费用不是线型。
//  1/1 复制体也算组件（预启动下回合手里拿的就是复制体）。
//

import Foundation

enum RDComponents {

    /// 组件清单：卡表里 `deckCount > 0` 的随从，即主牌库那 6 张
    static let minionPieces: [RDCard] = RDCards.deckMinions

    /// 局面里（手牌 + 我方场面）出现过的组件，按 `minionPieces` 顺序
    static func present(in state: RDState) -> [RDCard] {
        var seen = [Bool](repeating: false, count: RDCard.allCases.count)
        for c in state.hand {
            for i in 0..<c.identityCount { seen[c.identity(at: i).rawValue] = true }
        }
        for m in state.board { seen[m.card.rawValue] = true }
        return minionPieces.filter { seen[$0.rawValue] }
    }

    static func missing(in state: RDState) -> [RDCard] {
        let have = present(in: state)
        return minionPieces.filter { !have.contains($0) }
    }

    static func isComplete(_ state: RDState) -> Bool {
        return missing(in: state).isEmpty
    }
}
