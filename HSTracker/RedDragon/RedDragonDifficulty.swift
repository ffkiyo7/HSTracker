//
//  RedDragonDifficulty.swift
//  HSTracker
//
//  一条线的确定性难度分（v2，2026-09-11 用户改口径）。T2 的揭示策略靠它决定
//  「能不能开兜底引导」，所以权重与模板全部是常量，调阈值不用动算法。
//
//  v2 的重点是**逆序启动**：难的不是「多打了几张牌」，而是「打破鱼 → 狐 → 刀 → 暗 → 牛 的定势」。
//  旧版按「与模板前 n 张的编辑距离」算，已被用户否决 —— 编辑距离把「缺一张」和「顺序反了」
//  记成同一回事，而这两件事对记忆的负担完全不同。
//

import Foundation

struct RDDifficultyWeights {
    /// **顺序颠倒对数**（最重）：模板说 x 在 y 前、线里却 y 在 x 前的对数（Kendall tau）
    var perInversionPair: Double
    /// 缺件数：模板五张里这条线没用上的张数。缺零件的替代线本来就更难记，但它不是「乱」
    var perMissingTemplateCard: Double
    /// 中途插牌数：模板牌还没打完之前插进来的非模板动作，「顺序卡手」的来源
    var perInterleavedAction: Double
    /// 操作数：动作序列长度（含攻击、发现选择）
    var perAction: Double
    /// 牛的用量：这条线从边牌一共拿了几张
    var perSideboardCard: Double

    static let standard = RDDifficultyWeights(perInversionPair: 12.0,
                                              perMissingTemplateCard: 6.0,
                                              perInterleavedAction: 2.0,
                                              perAction: 1.0,
                                              perSideboardCard: 3.0)
}

enum RDDifficulty {

    /// 大多数公式的起手：鱼 → 狐 → 刀 → 暗（刀）→ 牛
    static let openingTemplate: [RDCard] = [
        .spiritOfTheShark, .foxyFraud, .scabbsCutterbutter, .shadowcaster, .etcBandManager
    ]

    /// 模板里每张牌的先后等级。**暗与牛同级**（用户 2026-09-11 定：牛暗互换很常见，不算逆序），
    /// 同级之间不计颠倒。
    static let openingRank: [RDCard: Int] = [
        .spiritOfTheShark: 0, .foxyFraud: 1, .scabbsCutterbutter: 2,
        .shadowcaster: 3, .etcBandManager: 3
    ]

    /// 阈值（用户 2026-09-11 校准）：暗 / 牛同级后，公式表 52 条可重放线全部颠倒 = 0，
    /// 分布 min 12 / p25 23 / 中位 27 / p75 30 / max 36。
    /// 基础 = 预启动、32 公式、最简的 48；进阶 = 48 / 48+ / 80 的长线（**纯长不算困难**，
    /// 这套牌拼的是思路不是手速）；困难 = 无狐最长的四条（缺件 + 长）。
    /// 真正的逆序启动线（颠倒 ≥ 1，+12 / 对）不在样本里，一出现就稳进困难档——这正是用户要的。
    static var basicThreshold = 23.0
    static var advancedThreshold = 33.0

    enum Tier: String {
        case basic, advanced, hard
    }

    static func tier(_ score: Double) -> Tier {
        if score <= basicThreshold { return .basic }
        if score <= advancedThreshold { return .advanced }
        return .hard
    }

    struct Components {
        var actionCount: Int
        var sideboardCardsTaken: Int
        /// 模板牌两两之间的顺序颠倒对数
        var inversionPairs: Int
        /// 模板五张里线里没出现的张数
        var missingTemplateCards: Int
        /// 第一张与最后一张模板牌之间插进来的非模板动作数
        var interleavedActions: Int
        var score: Double
    }

    /// 单调不减的那两项 —— 搜索里用来对「已经比最好解更难」的分支做剪枝。
    /// 另外三项（颠倒 / 缺件 / 插牌）都 ≥ 0，所以这仍然是合法下界。
    static func monotonicLowerBound(actionCount: Int, sideboardCardsTaken: Int,
                                    weights: RDDifficultyWeights = .standard) -> Double {
        return Double(actionCount) * weights.perAction
            + Double(sideboardCardsTaken) * weights.perSideboardCard
    }

    static func components(for actions: [RDAction],
                           sideboardCardsTaken: Int,
                           weights: RDDifficultyWeights = .standard) -> Components {
        let order = templateOrder(actions)
        let inversions = inversionPairs(order.map { $0.card })
        let missing = openingTemplate.count - order.count
        let interleaved = interleavedActionCount(actions, order: order)
        let score = Double(inversions) * weights.perInversionPair
            + Double(missing) * weights.perMissingTemplateCard
            + Double(interleaved) * weights.perInterleavedAction
            + Double(actions.count) * weights.perAction
            + Double(sideboardCardsTaken) * weights.perSideboardCard
        return Components(actionCount: actions.count,
                          sideboardCardsTaken: sideboardCardsTaken,
                          inversionPairs: inversions,
                          missingTemplateCards: missing,
                          interleavedActions: interleaved,
                          score: score)
    }

    /// 线里出现的模板牌，各取**首次打出**的位置，按位置升序。
    /// 同一张模板牌打第二次（48 线里刀油常打两次）不算新位置，也不算插牌。
    static func templateOrder(_ actions: [RDAction]) -> [(card: RDCard, index: Int)] {
        var firstIndex = [Int](repeating: -1, count: openingTemplate.count)
        for (i, action) in actions.enumerated() {
            guard case .play(_, let identity, _, _) = action else { continue }
            guard let slot = openingTemplate.firstIndex(of: identity) else { continue }
            if firstIndex[slot] < 0 { firstIndex[slot] = i }
        }
        var out: [(card: RDCard, index: Int)] = []
        for (slot, index) in firstIndex.enumerated() where index >= 0 {
            out.append((card: openingTemplate[slot], index: index))
        }
        out.sort { $0.index < $1.index }
        return out
    }

    /// Kendall tau：模板说 x 在 y 前、线里却 y 在 x 前的对数。缺的牌不算颠倒，同级的不算颠倒。
    static func inversionPairs(_ played: [RDCard]) -> Int {
        let rank = played.map { openingRank[$0] ?? Int.max }
        var n = 0
        guard rank.count > 1 else { return 0 }
        for i in 0..<(rank.count - 1) {
            for j in (i + 1)..<rank.count where rank[i] > rank[j] {
                n += 1
            }
        }
        return n
    }

    /// 第一张模板牌与最后一张模板牌**之间**的非模板动作（鱼和狐之间先打个步）。
    /// 模板开始之前的偷费（币 / 伺）不算 —— 那是常规启动的一部分，不是打断。
    static func interleavedActionCount(_ actions: [RDAction],
                                       order: [(card: RDCard, index: Int)]) -> Int {
        guard let first = order.first?.index, let last = order.last?.index, last > first + 1 else {
            return 0
        }
        var n = 0
        for i in (first + 1)..<last {
            guard case .play(_, let identity, _, _) = actions[i],
                  openingTemplate.contains(identity) else {
                n += 1
                continue
            }
        }
        return n
    }
}
