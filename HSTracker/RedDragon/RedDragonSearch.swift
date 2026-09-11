//
//  RedDragonSearch.swift
//  HSTracker
//
//  同步、单线程、纯函数的搜索核心。预算按 CPU 时间（CLOCK_THREAD_CPUTIME_ID），
//  不按墙钟 —— 否则同一局面在系统忙时会给出不同答案。线程与去抖是 T2 的事。
//

import Foundation

enum RDTermination: String {
    case reachedUpperBound
    case exhausted
    case budgetExceeded
}

struct RedDragonLine {
    var actions: [RDAction]
    var damage: Int
    var difficulty: Double
    var components: RDDifficulty.Components
    var tier: RDDifficulty.Tier
    /// 抽牌分叉：这条线沿途抽到 / 发现到的牌
    var branchKey: [RDCard]
    /// 线里包含异教地图 / 垂钓时光这类不展开的过牌
    var truncated: Bool
}

struct RedDragonBranch {
    var drawn: [RDCard]
    var line: RedDragonLine
}

struct RedDragonResult {
    var maxDamage: Int
    var effectiveEnemyHealth: Int
    var isLethal: Bool
    var chosenLine: RedDragonLine?
    var lethalLines: [RedDragonLine]
    var branches: [RedDragonBranch]
    var missingPieces: [RDCard]
    var termination: RDTermination
    var cpuTime: Double
    var statesExpanded: Int
    var depthReached: Int
}

struct RedDragonConfig {
    /// CPU 时间预算（秒）
    var cpuBudget: Double = 1.0
    /// 展开状态数上限。CPU 预算截断时结果依赖机器负载，这一项给「确定性」一个可复现的闸门
    var maxStatesExpanded: Int?
    /// nil = 精确搜索（每层保留全部去重后的状态）；否则每层只留分数最高的这么多个
    var beamWidth: Int? = 1500
    /// 每个节点最多展开几个动作（按卡表推出的先验排序）。nil = 全展开
    var maxActionsPerNode: Int? = 14
    var maxDepth: Int = 40
    var maxLethalLines: Int = 12
    var enableMissingPieces: Bool = true
    var missingPieceBudget: Double = 0.4
    var weights: RDDifficultyWeights = .standard
    var options: RDOptions = .search

    static let exact: RedDragonConfig = {
        var c = RedDragonConfig()
        c.beamWidth = nil
        c.maxActionsPerNode = nil
        return c
    }()
}

enum RedDragonSearch {

    // MARK: - CPU 时间

    static func threadCPUTime() -> Double {
        var ts = timespec()
        if clock_gettime(CLOCK_THREAD_CPUTIME_ID, &ts) != 0 { return 0 }
        return Double(ts.tv_sec) + Double(ts.tv_nsec) / 1_000_000_000.0
    }

    // MARK: - 节点

    private struct Node {
        var state: RDState
        var parent: Int
        var action: RDAction?
        var branchKey: [RDCard]
    }

    private struct Child {
        var state: RDState
        var parent: Int
        var action: RDAction
        var branchKey: [RDCard]
        var score: Int
        var builderScore: Int
        var hash: UInt64
    }

    // MARK: - 入口

    static func solve(_ root: RDState, config: RedDragonConfig = RedDragonConfig())
        -> RedDragonResult {
        let start = threadCPUTime()
        var run = search(root, config: config, deadline: start + config.cpuBudget)

        if !run.isLethal && config.enableMissingPieces {
            run.missingPieces = findMissingPieces(root, config: config,
                                                  deadline: threadCPUTime()
                                                      + config.missingPieceBudget)
        }
        run.cpuTime = threadCPUTime() - start
        return run
    }

    // MARK: - 主搜索

    private static func search(_ root: RDState, config: RedDragonConfig,
                               deadline: Double) -> RedDragonResult {
        let threshold = root.opponent.effectiveHealth
        let rootSideboard = root.sideboard.count

        var nodes: [Node] = [Node(state: root, parent: -1, action: nil, branchKey: [])]
        var frontier: [Int] = [0]
        var seen = Set<UInt64>([root.canonicalHash()])

        var bestLine: RedDragonLine? = nil
        var maxDamage = root.damageDealt
        var lethal: [RedDragonLine] = []
        var bestByBranch: [String: RedDragonLine] = [:]
        var statesExpanded = 0
        var termination = RDTermination.exhausted
        var depth = 0

        func makeLine(parent: Int, action: RDAction, state: RDState,
                      branchKey: [RDCard]) -> RedDragonLine {
            var actions: [RDAction] = [action]
            var cursor = parent
            while cursor > 0, let a = nodes[cursor].action {
                actions.append(a)
                cursor = nodes[cursor].parent
            }
            actions.reverse()
            let taken = rootSideboard - state.sideboard.count
            let comps = RDDifficulty.components(for: actions, sideboardCardsTaken: taken,
                                                weights: config.weights)
            return RedDragonLine(actions: actions, damage: state.damageDealt,
                                 difficulty: comps.score, components: comps,
                                 tier: RDDifficulty.tier(comps.score),
                                 branchKey: branchKey,
                                 truncated: state.truncatedDraws > 0)
        }

        func branchId(_ key: [RDCard]) -> String {
            return key.map { String($0.rawValue) }.joined(separator: ",")
        }

        outer: while !frontier.isEmpty && depth < config.maxDepth {
            var children: [Child] = []
            children.reserveCapacity(frontier.count * 8)

            for index in frontier {
                if threadCPUTime() > deadline {
                    termination = .budgetExceeded
                    break outer
                }
                if let cap = config.maxStatesExpanded, statesExpanded >= cap {
                    termination = .budgetExceeded
                    break outer
                }
                let node = nodes[index]
                var actions = RDEngine.legalActions(node.state, options: config.options)
                if let cap = config.maxActionsPerNode, actions.count > cap {
                    actions = topActions(actions, node.state, cap: cap)
                }
                for action in actions {
                    guard let next = try? RDEngine.apply(action, to: node.state,
                                                         options: config.options) else { continue }
                    statesExpanded += 1
                    let hash = next.canonicalHash()
                    guard seen.insert(hash).inserted else { continue }
                    var key = node.branchKey
                    appendBranchKey(&key, action: action)
                    if next.damageDealt > maxDamage {
                        maxDamage = next.damageDealt
                        bestLine = makeLine(parent: index, action: action, state: next,
                                            branchKey: key)
                    }
                    if next.damageDealt >= threshold && threshold > 0 {
                        let line = makeLine(parent: index, action: action, state: next,
                                            branchKey: key)
                        if !line.truncated { lethal.append(line) }
                    }
                    if !key.isEmpty {
                        let bid = branchId(key)
                        let line = makeLine(parent: index, action: action, state: next,
                                            branchKey: key)
                        if let old = bestByBranch[bid] {
                            if line.damage > old.damage
                                || (line.damage == old.damage && line.difficulty < old.difficulty) {
                                bestByBranch[bid] = line
                            }
                        } else {
                            bestByBranch[bid] = line
                        }
                    }
                    let eval = evaluate(next)
                    children.append(Child(state: next, parent: index, action: action,
                                          branchKey: key, score: eval.greedy,
                                          builderScore: eval.builder, hash: hash))
                }
            }

            depth += 1
            if !lethal.isEmpty {
                // 最浅的一层就有斩杀 —— 同层的线操作数相同，正是「最简单的那条」所在的层
                termination = .reachedUpperBound
                break outer
            }
            if children.isEmpty { break }

            children.sort { a, b in
                if a.score != b.score { return a.score > b.score }
                return a.hash < b.hash
            }
            if let width = config.beamWidth, children.count > width {
                children = selectBeam(children, width: width)
            }
            frontier = []
            frontier.reserveCapacity(children.count)
            for c in children {
                nodes.append(Node(state: c.state, parent: c.parent, action: c.action,
                                  branchKey: c.branchKey))
                frontier.append(nodes.count - 1)
            }
        }

        if threadCPUTime() > deadline && termination == .exhausted {
            termination = .budgetExceeded
        }

        lethal = dedupe(lethal)
        lethal.sort { a, b in
            if a.difficulty != b.difficulty { return a.difficulty < b.difficulty }
            if a.damage != b.damage { return a.damage > b.damage }
            return signature(a) < signature(b)
        }
        if lethal.count > config.maxLethalLines {
            lethal.removeSubrange(config.maxLethalLines...)
        }

        // 路径重放校验（P0）：任何要返回的线，先用同一套规则从根重放一遍
        lethal = lethal.filter { validated($0, root: root, config: config) }
        if let best = bestLine, !validated(best, root: root, config: config) {
            bestLine = nil
        }

        let chosen = lethal.first ?? bestLine
        let branches = bestByBranch.values
            .filter { validated($0, root: root, config: config) }
            .sorted { a, b in
                if a.branchKey.count != b.branchKey.count {
                    return a.branchKey.count < b.branchKey.count
                }
                for (x, y) in zip(a.branchKey, b.branchKey) where x != y {
                    return x.rawValue < y.rawValue
                }
                return a.damage > b.damage
            }
            .map { RedDragonBranch(drawn: $0.branchKey, line: $0) }

        return RedDragonResult(maxDamage: maxDamage,
                               effectiveEnemyHealth: threshold,
                               isLethal: !lethal.isEmpty,
                               chosenLine: chosen,
                               lethalLines: lethal,
                               branches: branches,
                               missingPieces: [],
                               termination: termination,
                               cpuTime: 0,
                               statesExpanded: statesExpanded,
                               depthReached: depth)
    }

    /// 三件事：① 按「已造成伤害」分桶保底（只取全局 Top-K 会把「龙数低、还在蓄力」的桶整个砍掉，
    /// 那正是 48 / 64 线所在的桶）；② 共识分占一半；③ 蓄力分（正交）占另一半。
    /// `children` 必须已按共识分降序排好。
    private static func selectBeam(_ children: [Child], width: Int) -> [Child] {
        var taken = [Bool](repeating: false, count: children.count)
        var picked: [Int] = []
        picked.reserveCapacity(width)

        var buckets: [Int] = []
        for c in children where !buckets.contains(c.state.damageDealt) {
            buckets.append(c.state.damageDealt)
        }
        buckets.sort()
        if buckets.count > 1 {
            let quota = max(3, width / (3 * buckets.count))
            for bucket in buckets {
                var n = 0
                for (i, c) in children.enumerated() where c.state.damageDealt == bucket {
                    if n >= quota || picked.count >= width { break }
                    if taken[i] { continue }
                    taken[i] = true
                    picked.append(i)
                    n += 1
                }
            }
        }

        let consensusTarget = min(width, picked.count + width / 2)
        for (i, _) in children.enumerated() where !taken[i] {
            if picked.count >= consensusTarget { break }
            taken[i] = true
            picked.append(i)
        }

        if picked.count < width {
            var byBuilder = Array(children.indices)
            byBuilder.sort { a, b in
                if children[a].builderScore != children[b].builderScore {
                    return children[a].builderScore > children[b].builderScore
                }
                return children[a].hash < children[b].hash
            }
            for i in byBuilder where !taken[i] {
                if picked.count >= width { break }
                taken[i] = true
                picked.append(i)
            }
        }

        picked.sort()
        return picked.map { children[$0] }
    }

    private static func validated(_ line: RedDragonLine, root: RDState,
                                  config: RedDragonConfig) -> Bool {
        return RDReplay.validate(line.actions, from: root, expectedDamage: line.damage,
                                 options: config.options) != nil
    }

    private static func signature(_ line: RedDragonLine) -> String {
        return line.actions.map { action -> String in
            switch action {
            case .play(_, let identity, let target, let choices):
                return "p\(identity.rawValue)/\(targetCode(target))/"
                    + choices.map { c -> String in
                        if case .pick(let card) = c { return String(card.rawValue) }
                        return "?"
                    }.joined(separator: "-")
            case .heroPower: return "hp"
            case .attack(let a, let d): return "a\(targetCode(a))>\(targetCode(d))"
            }
        }.joined(separator: " ")
    }

    private static func targetCode(_ t: RDTarget) -> String {
        switch t {
        case .none: return "-"
        case .friendlyMinion(let id): return "f\(id)"
        case .enemyMinion(let id): return "e\(id)"
        case .enemyHero: return "H"
        case .friendlyHero: return "h"
        case .unspecifiedFriendly: return "?"
        }
    }

    private static func dedupe(_ lines: [RedDragonLine]) -> [RedDragonLine] {
        var seen = Set<String>()
        var out: [RedDragonLine] = []
        for l in lines where seen.insert(signature(l)).inserted {
            out.append(l)
        }
        return out
    }

    private static func appendBranchKey(_ key: inout [RDCard], action: RDAction) {
        guard case .play(_, _, _, let choices) = action else { return }
        for c in choices {
            if case .pick(let card) = c { key.append(card) }
        }
    }

    // MARK: - 启发

    /// 两个**正交**的排序分，束搜索两边各留一半。
    /// 单一分数要么急着打龙（长线被砍）、要么只会蓄力（永远不转化）——
    /// win 项目 V1.4 的结论是「多路搜索的收益来自正交，不来自多」，这里用同一批子节点的两种排序实现。
    struct RDEval {
        /// 共识：乐观上界 + 已造成伤害，负责把线收口
        var greedy: Int
        /// 操作空间 / 回收放大：法力、减费层、格子、可回收的龙，负责把引擎搭起来
        var builder: Int
        /// card-model F1 的乐观估计。⚠️ 它**不是**真上界：药水 / 暗影施法者能无限造复制，
        /// 「还能触发几次阿莱」没有闭式上限。实测拿它当硬剪枝会砍掉 48 / 64 线，所以只进排序分。
        var upperBound: Int
    }

    static func evaluate(_ s: RDState) -> RDEval {
        var faceDamagePerTrigger = 0
        var alexInHand = 0
        var alexOnBoard = 0
        var fromSideboard = 0
        var bouncesAndCopies = 0
        var sharkReachable = s.sharkAuraActive

        for c in s.hand {
            let def = RDCards.def(c.identity(at: 0))
            for e in def.effects {
                switch e {
                case .damageTarget(let n, _) where RDCards.canTargetEnemyHero(def):
                    alexInHand += 1
                    faceDamagePerTrigger = max(faceDamagePerTrigger, n)
                case .bounceTarget, .bounceAllFriendly,
                     .copyTargetToHand, .copyAllFriendlyToHand:
                    bouncesAndCopies += 1
                default:
                    break
                }
            }
            if def.providesSharkAura { sharkReachable = true }
        }
        for m in s.board {
            let def = RDCards.def(m.card)
            for e in def.effects {
                switch e {
                case .damageTarget(let n, _) where RDCards.canTargetEnemyHero(def):
                    alexOnBoard += 1
                    faceDamagePerTrigger = max(faceDamagePerTrigger, n)
                case .copyTargetToHand, .copyAllFriendlyToHand:
                    bouncesAndCopies += 1
                default:
                    break
                }
            }
        }
        for c in s.sideboard {
            let def = RDCards.def(c)
            for e in def.effects {
                if case .damageTarget(let n, _) = e, RDCards.canTargetEnemyHero(def) {
                    fromSideboard += 1
                    faceDamagePerTrigger = max(faceDamagePerTrigger, n)
                }
            }
        }

        var layerValue = 0
        for l in s.layers { layerValue += l.amount * l.slots }

        // 平 A / 武器也能打脸，上界要算进去，否则剪枝就不是上界了
        var attackPotential = 0
        for m in s.board where !m.summoningSick && m.attacksThisTurn < 1 {
            attackPotential += max(0, m.attack)
        }
        if !s.heroAttackedThisTurn {
            attackPotential += max(s.weapon?.attack ?? 0, s.heroPowerUsed ? 0 : 1)
        }

        let multiplier = sharkReachable ? 2 : 1
        let triggers = alexInHand
            + (alexOnBoard > 0 ? bouncesAndCopies + alexOnBoard : 0)
            + fromSideboard
        let ub = s.damageDealt + attackPotential
            + faceDamagePerTrigger * multiplier * triggers

        let greedy = ub * 10 + s.damageDealt * 4 + s.availableMana * 6
            + layerValue * 4 + s.boardSlotsFree * 2 + (s.sharkAuraActive ? 20 : 0)
        let builder = s.availableMana * 8 + layerValue * 8 + s.boardSlotsFree * 6
            + s.handSlotsFree * 2 + (s.sharkAuraActive ? 40 : 0)
            + bouncesAndCopies * 25 + (alexInHand + alexOnBoard + fromSideboard) * 30
            + s.damageDealt * 2
        return RDEval(greedy: greedy, builder: builder, upperBound: ub)
    }

    /// 每个节点的动作先验，只用来在展开前砍掉低价值动作
    private static func actionPrior(_ action: RDAction, _ s: RDState) -> Int {
        switch action {
        case .play(_, let identity, let target, _):
            let def = RDCards.def(identity)
            var p = 40
            for e in def.effects + def.comboEffects {
                switch e {
                case .damageTarget(let n, _):
                    p = max(p, target == .enemyHero ? 900 + n * 10 : 120)
                case .refreshMana: p = max(p, 300)
                case .pushDiscount(let amount, let slots, _): p = max(p, 240 + amount * slots * 5)
                case .discoverFromSideboard: p = max(p, 320)
                case .copyTargetToHand, .copyAllFriendlyToHand: p = max(p, 280)
                case .bounceAllFriendly: p = max(p, 260)
                case .bounceTarget: p = max(p, 200)
                case .draw: p = max(p, 180)
                case .gainTempMana: p = max(p, 150)
                case .discountIfTargetDied: p = max(p, 160)
                case .removeOneFriendlyMinion: p = max(p, 140)
                default: break
                }
            }
            if def.providesSharkAura && !s.sharkAuraActive { p = max(p, 340) }
            return p
        case .heroPower:
            return 20
        case .attack(_, let defender):
            return defender == .enemyHero ? 200 : 90
        }
    }

    private static func topActions(_ actions: [RDAction], _ s: RDState, cap: Int) -> [RDAction] {
        var scored = actions.enumerated().map { (i, a) in (prior: actionPrior(a, s), index: i, action: a) }
        scored.sort { a, b in
            if a.prior != b.prior { return a.prior > b.prior }
            return a.index < b.index
        }
        return scored.prefix(cap).map { $0.action }
    }

    // MARK: - 缺件

    /// 无解时，对牌库剩余的每种零件试「加进手牌再算」。
    /// 预算单列：总预算平分到候选数上，最少 20 ms，超了就停 —— 缺件是锦上添花，不能拖垮主搜索。
    private static func findMissingPieces(_ root: RDState, config: RedDragonConfig,
                                          deadline: Double) -> [RDCard] {
        // 牌库里没建模的牌（占位「杂」）打不出去，不可能是缺的那一张，别浪费预算去试
        let candidates = root.deck.remaining(filter: .any)
            .filter { !RDCards.def($0).isPlaceholder }
        guard !candidates.isEmpty else { return [] }
        let per = max(0.02, (deadline - threadCPUTime()) / Double(candidates.count))
        var out: [RDCard] = []
        for card in candidates {
            if threadCPUTime() > deadline { break }
            var probe = root
            probe.deck.remove(card)
            let id = probe.takeEntityId()
            probe.hand.append(RDHandCard(entityId: id, card: card,
                                         isShadowOfDemise: card == .shadowOfDemise))
            var sub = config
            sub.enableMissingPieces = false
            sub.cpuBudget = per
            // 缺件是「多这一张能不能斩」的粗判，束宽压到主搜索的一小半，别让它吃掉主线的预算
            sub.beamWidth = min(300, config.beamWidth ?? 300)
            let r = search(probe, config: sub, deadline: threadCPUTime() + per)
            if r.isLethal { out.append(card) }
        }
        return out
    }
}
