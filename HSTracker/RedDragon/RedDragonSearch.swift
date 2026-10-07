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
    /// 搜索内部用：每一步爆手时选定的场面顺序（只在爆手的全场弹回 / 复制处非空）。
    /// 返回前由 `RedDragonSearch` 翻译成 `actions` 里每次下随从的落位（并改写编号），然后清空
    var pendingBoardOrders: [RDOrderDecision?]? = nil
    /// 准备线（T4）：终局阿莱对友方回血的总量；`potential` = 终局作为下回合起手能打的伤害（探针，见 `RDSetup`）
    var healed = 0
    var potential = 0
}

struct RedDragonBranch {
    var drawn: [RDCard]
    var line: RedDragonLine
}

struct RedDragonResult {
    var maxDamage: Int
    var effectiveEnemyHealth: Int
    var isLethal: Bool
    /// `lethalLines` 里有不靠随机抽牌的线（`RDLineWalker.dependsOnDraw` 为 false）。`isLethal` 为真而它为假 =
    /// 只找到「抽到才斩」的线：搜索没有在那一层收口，补搜照跑（T5 A1）
    var deterministicLethal = false
    var chosenLine: RedDragonLine?
    var lethalLines: [RedDragonLine]
    var branches: [RedDragonBranch]
    var missingPieces: [RDCard]
    /// 缺件子搜索被 CPU 兜底截断（此时 `missingPieces` 不保证可复现）
    var missingPiecesBudgetExceeded: Bool
    var termination: RDTermination
    var cpuTime: Double
    /// 主搜索 + 采样补搜合计（不含缺件子搜索）
    var statesExpanded: Int
    var depthReached: Int
    /// 主搜索自己展开的状态数
    var mainStatesExpanded = 0
    /// 跑了采样补搜
    var samplingPassRan = false
    /// 跑了排法补搜
    var boardOrderPassRan = false
    /// 要返回的线里，场面顺序翻译成落位失败、被丢掉的条数（主搜索 + 补搜）
    var placementTranslationFailures = 0
    /// 撞上了 CPU 兜底（`cpuBudget` / 缺件的 `missingPieceBudget` 不算）。只有它才说明结果随机器负载变，
    /// 撞状态闸门（`maxStatesExpanded`）是可复现的正常收口
    var cpuBudgetHit = false
    /// 被 `RedDragonConfig.cancellation` 取消。取消了的结果不完整，调用方应丢掉
    var cancelled = false
    /// 有一遍搜索把可达局面**穷举**完了：束没裁过、每个节点的动作没截过、爆手排法没截过、没撞深度 / 状态 /
    /// CPU 上限、没取消。只有这时「没找到斩杀」才等于「按本模型不能斩杀」。生产配置下只有小局面能做到
    var exhaustive = false
    /// 准备线搜索（`config.setup` 非 nil）的结果，按优劣排好；斩杀搜索恒空
    var setupLines: [RedDragonLine] = []
}

/// 本回合不斩杀时为下回合做准备的两类线（T4）
enum RDSetupGoal: Equatable {
    /// 打 / 回 16：一张阿莱在鲨鱼下对友方英雄回满 16（危险时用，目标永远是自己）
    case heal16
    /// 预启动：不要求回血，只要终局留下的东西让下回合伤害最高（幻觉药水把一套收回手里、鲨鱼留场）
    case preLaunch
}

/// 后台计算的取消标记：新局面一到，旧的那次搜索就不用算完了。任何线程都可以 `cancel()`
final class RDCancellation {
    private let lock = NSLock()
    private var flag = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return flag
    }

    func cancel() {
        lock.lock()
        flag = true
        lock.unlock()
    }
}

struct RedDragonConfig {
    /// CPU 时间兜底（秒）。正常应先撞上 `maxStatesExpanded`；撞上 CPU 兜底时结果随机器负载变，
    /// 由 `termination == .budgetExceeded` 且 `statesExpanded` 没到上限标出来
    var cpuBudget: Double = 3.0
    /// 展开状态数上限（主搜索 + 采样补搜合计），可复现的闸门。nil = 只靠 CPU（只给测试 / 精确搜索用）。
    /// 生产默认 40 万：-O 下约 30 万态 / 秒，最坏约 1.3 s，CPU 兜底 3 s 正常碰不到
    var maxStatesExpanded: Int? = 400_000
    /// 采样补搜开着时，总状态预算里留给补搜的份额：主搜索最多用 (1 − 份额) × 总量，
    /// 补搜用总量减去主搜索实际用掉的。份额是确定的，不随机器负载变
    var samplingShare: Double = 0.5
    /// nil = 精确搜索（每层保留全部去重后的状态）；否则每层只留分数最高的这么多个
    var beamWidth: Int? = 1500
    /// 每个节点最多展开几个动作（按卡表推出的先验排序）。nil = 全展开
    var maxActionsPerNode: Int? = 14
    /// 主搜索 / 采样补搜在爆手的全场复制（幻觉药水；舞动 T2b 起按上场先后处理，没有排法）处，
    /// 除现有顺序外最多再展开几种「进手集合」的排法（共识分、蓄力分各取前几）。nil = 全展开。
    /// **这是有损的**：需要的排法两种分都排不进前几时就漏。T2a 时舞动也走这里，主搜索全展开会把束挤满
    /// （t1-48p-06 / t1-48p-07 / t2-wuhui-03 掉线），所以留 1，漏掉的交给 `boardOrderPass`。数据见 T2a 任务书
    var maxBoardOrderVariants: Int? = 1
    /// 束里留给「爆手时现有顺序之外的排法」的份额上限（nil = 不分开，和其他子节点一起竞争）。
    /// 主搜索 / 采样补搜不用；排法补搜用 `boardOrderPass.beamShare`
    var boardOrderVariantShare: Double? = nil
    /// 排法补搜：主搜索没斩杀时，排法**不设上限**、但只在每层束里争 `beamShare` 的份额，
    /// 最多用总状态预算的 `budgetShare`。nil = 不跑。见 `solve`
    var boardOrderPass: (beamShare: Double, budgetShare: Double)? = (0.25, 0.25)
    /// 采样补搜的束宽（nil = 不补搜）。只在主搜索没找到斩杀时跑，和主搜索共用 `cpuBudget`
    /// 与 `maxStatesExpanded`（按 `samplingShare` 分）。见 `RedDragonSearch.solve`
    var samplingPassWidth: Int? = 6000
    var maxDepth: Int = 40
    var maxLethalLines: Int = 12
    var enableMissingPieces: Bool = true
    /// 缺件子搜索的可复现闸门：总展开状态数，向下取整平分到每个候选（每个至少 1）。
    /// 各候选的份额之和不超过这个数；每个子搜索在份额用完后的那一个节点内还会把该节点的子动作展开完，
    /// 所以实际展开数最多超出「候选数 × 单节点动作数」。
    /// **只要没撞上下面的 CPU 兜底，结果就只由它决定、可复现**；撞上兜底时不可复现，并由
    /// `missingPiecesBudgetExceeded` 标出来
    var missingPieceMaxStates: Int = 120_000
    /// 缺件的 CPU 兜底（秒）。只防极端局面卡住，正常应先撞上面的状态闸门
    var missingPieceBudget: Double = 2.0
    var weights: RDDifficultyWeights = .standard
    var options: RDOptions = .search
    /// nil = 不可取消。和 CPU 兜底在同一处检查（每展开一个节点一次）
    var cancellation: RDCancellation? = nil
    /// 非 nil = 准备线搜索：不找斩杀，收集满足目标的终局（见 `RedDragonSearch.solveSetup`）
    var setup: RDSetupGoal? = nil
    /// 准备线搜索自己的闸门（`solveSetup` 用，不动斩杀搜索的 `maxStatesExpanded` / `cpuBudget`）
    var setupMaxStates: Int = 200_000
    var setupCpuBudget: Double = 2.0

    static let exact: RedDragonConfig = {
        var c = RedDragonConfig()
        c.beamWidth = nil
        c.maxActionsPerNode = nil
        c.maxBoardOrderVariants = nil
        c.boardOrderPass = nil
        c.samplingPassWidth = nil
        c.maxStatesExpanded = nil
        // 抽牌 / 发现组合也不截断（T2b 第三轮）
        c.options.maxChoiceCombinations = .max
        return c
    }()
}

enum RedDragonSearch {
    /// 一层束的取法
    private enum BeamSelection {
        /// 分桶保底 + 共识分 + 蓄力分（主搜索）
        case scored
        /// 按资源阶段分层采样（采样补搜）
        case sampled
    }

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
        /// 见「落位」一节：场上已经定下来的先后关系
        var constraints = RDBoardConstraints()
        /// 这一步是爆手的全场弹回 / 复制时选定的顺序
        var decision: RDOrderDecision? = nil
    }

    private struct Child {
        var state: RDState
        var parent: Int
        var action: RDAction
        var branchKey: [RDCard]
        var score: Int
        var builderScore: Int
        var hash: UInt64
        var constraints: RDBoardConstraints
        var decision: RDOrderDecision?
        /// 爆手时「现有顺序」之外的排法（见 `boardOrderVariantShare`）
        var isVariant: Bool
    }

    // MARK: - 入口

    static func solve(_ root: RDState, config: RedDragonConfig = RedDragonConfig())
        -> RedDragonResult {
        let start = threadCPUTime()
        let deadline = start + config.cpuBudget
        let sampling = config.samplingPassWidth != nil && root.opponent.effectiveHealth > 0
        var mainConfig = config
        if sampling, let total = config.maxStatesExpanded {
            mainConfig.maxStatesExpanded = max(1, Int(Double(total) * (1 - config.samplingShare)))
        }
        var run = search(root, config: mainConfig, deadline: deadline)
        run.mainStatesExpanded = run.statesExpanded
        if run.cancelled {
            run.cpuTime = threadCPUTime() - start
            return run
        }

        // 排法补搜：主搜索每次爆手只展开「现有顺序 + 共识分最高的 1 种」排法（`maxBoardOrderVariants`），
        // 需要别的排法的线搜不到；而主搜索里排法不设上限又会把束挤满、别的线掉了。
        // 所以主搜索没斩杀时再跑一遍：排法全展开，但只在每层束里争固定份额，状态数也只拿总预算的一部分。
        // T2b 起舞动按上场先后处理、不再有排法，只剩幻觉药水爆手（待核）依赖场位：起手够不着药水就不跑，
        // 否则它只是把主搜索换个小预算重跑一遍，白占采样补搜的份额
        // 「没斩杀」按「没有确定的斩杀线」算：只找到抽到才斩的线时补搜照跑（T5 A1）
        if !run.deterministicLethal, !run.cancelled, let pass = config.boardOrderPass,
           RDEngine.boardOrderMatters(root),
           threadCPUTime() < deadline {
            let left = config.maxStatesExpanded.map { $0 - run.statesExpanded }
            let share = config.maxStatesExpanded.map { max(1, Int(Double($0) * pass.budgetShare)) }
            if (left ?? 1) > 0 {
                var c = config
                c.maxBoardOrderVariants = nil
                c.boardOrderVariantShare = pass.beamShare
                c.maxStatesExpanded = left.map { min($0, share ?? $0) }
                let v = search(root, config: c, deadline: deadline)
                run = merge(run, v)
                run.boardOrderPassRan = true
            }
        }

        // 采样补搜：主搜索没找到斩杀、还有预算时，用剩余预算按资源阶段分层保留候选。
        // 打分束会被「已经打出一条龙、伤害更高」的节点挤满，少数「先把整手牌弹回成 0 费、
        // 最后连下两条龙」的线（公式表 t2-wuhui-03）在打分束里加宽到 24000 都会掉，
        // 各阶段轮流保留蓄力分最高的候选，不让已经打过龙的节点挤掉回收阶段，也不靠哈希抽中它。
        // 它只在不斩杀时跑，主搜索已斩杀的局面耗时不变。
        // 状态预算两遍共用：补搜拿总量减去主搜索实际用掉的部分。
        let remaining = config.maxStatesExpanded.map { $0 - run.statesExpanded }
        if !run.deterministicLethal, !run.cancelled, sampling, threadCPUTime() < deadline, (remaining ?? 1) > 0 {
            var sampledConfig = config
            sampledConfig.maxStatesExpanded = remaining
            let sampled = search(root, config: sampledConfig, deadline: deadline, selection: .sampled)
            run = merge(run, sampled)
            run.samplingPassRan = true
        }

        if !run.isLethal && !run.cancelled && config.enableMissingPieces {
            let found = findMissingPieces(root, config: config,
                                          deadline: threadCPUTime() + config.missingPieceBudget)
            run.missingPieces = found.cards
            run.missingPiecesBudgetExceeded = found.budgetExceeded
            if config.cancellation?.isCancelled == true { run.cancelled = true }
        }
        run.cpuTime = threadCPUTime() - start
        return run
    }

    /// 主搜索 + 采样补搜合并：斩杀线以补搜为准（主搜索没有确定的斩杀线才会跑补搜；主搜索已有「抽到才斩」
    /// 的线时，补搜找到确定线才换），伤害取大，展开状态数相加。分叉表只保留主搜索的（补搜是抽样，不代表分叉全貌）。
    private static func merge(_ main: RedDragonResult, _ sampled: RedDragonResult) -> RedDragonResult {
        var sampled = sampled
        if main.isLethal && !sampled.deterministicLethal { sampled.isLethal = false }
        var out = main
        out.statesExpanded += sampled.statesExpanded
        out.placementTranslationFailures += sampled.placementTranslationFailures
        out.cpuBudgetHit = main.cpuBudgetHit || sampled.cpuBudgetHit
        out.cancelled = main.cancelled || sampled.cancelled
        // 任何一遍穷举完了都算证明（各遍搜的是同一棵树，只是裁法不同）
        out.exhaustive = (main.exhaustive || sampled.exhaustive) && !out.cancelled
        out.depthReached = max(main.depthReached, sampled.depthReached)
        if sampled.isLethal {
            out.isLethal = true
            out.deterministicLethal = sampled.deterministicLethal
            out.lethalLines = sampled.lethalLines
            out.chosenLine = sampled.chosenLine
        } else if !main.isLethal, sampled.maxDamage > main.maxDamage, let line = sampled.chosenLine {
            out.chosenLine = line
        }
        out.maxDamage = max(main.maxDamage, sampled.maxDamage)
        if main.termination == .budgetExceeded || sampled.termination == .budgetExceeded {
            out.termination = .budgetExceeded
        } else if sampled.isLethal {
            out.termination = sampled.termination
        }
        return out
    }

    // MARK: - 主搜索

    private static func search(_ root: RDState, config: RedDragonConfig,
                               deadline: Double,
                               selection: BeamSelection = .scored) -> RedDragonResult {
        let beamWidth = selection == .scored ? config.beamWidth : config.samplingPassWidth
        let setupGoal = config.setup
        // 准备线搜索不找斩杀：门槛放到够不着，伤害账只给斩杀线用
        let enemyHealth = root.opponent.effectiveHealth
        let threshold = setupGoal == nil ? enemyHealth : Int.max
        let rootSideboard = root.sideboard.count
        // 束里不逐个展开落位（见「落位」一节）
        var listOptions = config.options
        listOptions.expandPlacements = false

        let rootConstraints = RDBoardConstraints.root(root)
        var nodes: [Node] = [Node(state: root, parent: -1, action: nil, branchKey: [],
                                  constraints: rootConstraints)]
        var frontier: [Int] = [0]
        // 去重键 = 局面哈希 + 场上已定的先后关系（同一局面、可排的余地不同，后面能走的线不同）
        func dedupKey(_ hash: UInt64, _ c: RDBoardConstraints, _ board: [RDBoardMinion]) -> UInt64 {
            return RedDragonSearch.dedupKey(hash, c, board)
        }
        var seen = Set<UInt64>([dedupKey(root.canonicalHash(), rootConstraints, root.board)])

        var bestLine: RedDragonLine? = nil
        var maxDamage = root.damageDealt
        var lethal: [RedDragonLine] = []
        var bestByBranch: [String: RedDragonLine] = [:]
        var statesExpanded = 0
        var termination = RDTermination.exhausted
        var depth = 0
        var cpuBudgetHit = false
        var cancelled = false
        /// 有损的裁剪发生过（束、动作上限、排法上限、深度上限）：没找到斩杀也不能说明不能斩
        var pruned = false
        /// 准备线候选：按质量降序、同质量按步数升序，只留前 `setupKeep` 条
        var setupKept: [(quality: Int, steps: Int, line: RedDragonLine)] = []
        func isCancelled() -> Bool { return config.cancellation?.isCancelled == true }

        func makeLine(parent: Int, action: RDAction, state: RDState,
                      branchKey: [RDCard], order: RDOrderDecision?) -> RedDragonLine {
            var actions: [RDAction] = [action]
            var orders: [RDOrderDecision?] = [order]
            var cursor = parent
            while cursor > 0, let a = nodes[cursor].action {
                actions.append(a)
                orders.append(nodes[cursor].decision)
                cursor = nodes[cursor].parent
            }
            actions.reverse()
            orders.reverse()
            let taken = rootSideboard - state.sideboard.count
            let comps = RDDifficulty.components(for: actions, sideboardCardsTaken: taken,
                                                weights: config.weights)
            var line = RedDragonLine(actions: actions, damage: state.damageDealt,
                                     difficulty: comps.score, components: comps,
                                     tier: RDDifficulty.tier(comps.score),
                                     branchKey: branchKey,
                                     truncated: state.truncatedDraws > 0)
            if orders.contains(where: { $0 != nil }) { line.pendingBoardOrders = orders }
            return line
        }

        func branchId(_ key: [RDCard]) -> String {
            return key.map { String($0.rawValue) }.joined(separator: ",")
        }

        // 场面顺序翻译成落位，之后的去重 / 签名 / 重放校验都看带落位的动作
        // 翻译不出来的线丢掉：只保证不返回假线，避免不了漏解，所以计数（测试断言公式表上为 0）
        var translationFailures = 0
        func placed(_ line: RedDragonLine) -> RedDragonLine? {
            guard line.pendingBoardOrders != nil else { return line }
            guard !isCancelled() else { return nil }
            let out = withPlacements(line, root: root, options: config.options)
            if out == nil { translationFailures += 1 }
            return out
        }
        // 斩杀线的收尾：去重、排序、截到 `maxLethalLines`。没有随机抽牌的线排在前面（截断时先留它们），
        // 其余按难度升序（「最简单的那条」）
        func drawsRandomly(_ line: RedDragonLine) -> Bool {
            return !line.branchKey.allSatisfy { RDCards.sideboardCards.contains($0) }
        }
        func ranked(_ lines: [RedDragonLine]) -> [RedDragonLine] {
            var out = dedupe(lines)
            out.sort { a, b in
                let (x, y) = (drawsRandomly(a), drawsRandomly(b))
                if x != y { return !x }
                if a.difficulty != b.difficulty { return a.difficulty < b.difficulty }
                if a.damage != b.damage { return a.damage > b.damage }
                return signature(a) < signature(b)
            }
            if out.count > config.maxLethalLines {
                out.removeSubrange(config.maxLethalLines...)
            }
            return out
        }
        /// 只找到「抽到才斩」的线的那些层留下的线（已翻译落位、已排序截断）：更深处没有确定线时拿它们兜底
        var drawOnlyLethal: [RedDragonLine] = []
        var deterministicLethal = false
        /// 把这一层攒下的斩杀线收尾。有**确定**的斩杀线（重放校验过、不依赖抽到的牌）→ 留下这一层的线，返回 true；
        /// 只有「抽到才斩」的 → 并进兜底，返回 false
        func closeLethalLayer() -> Bool {
            let layer = ranked(lethal.compactMap(placed))
            lethal = []
            guard !isCancelled() else { return false }
            if layer.contains(where: {
                validated($0, root: root, config: config)
                    && !RDLineWalker.dependsOnDraw($0.actions, root: root, options: config.options)
            }) {
                lethal = layer
                deterministicLethal = true
                return true
            }
            drawOnlyLethal = ranked(drawOnlyLethal + layer)
            return false
        }

        outer: while !frontier.isEmpty && depth < config.maxDepth {
            var children: [Child] = []
            children.reserveCapacity(frontier.count * 8)

            func consider(_ index: Int, _ node: Node, _ action: RDAction, _ next: RDState,
                          _ constraints: RDBoardConstraints, _ order: RDOrderDecision?, _ isVariant: Bool) {
                statesExpanded += 1
                let hash = next.canonicalHash()
                guard seen.insert(dedupKey(hash, constraints, next.board)).inserted else { return }
                var key = node.branchKey
                appendBranchKey(&key, action: action)
                if let goal = setupGoal {
                    let eval = RDSetup.evaluate(next, goal: goal)
                    // 只收不靠随机抽牌的线（发现是自己选的，不算随机）
                    if RDSetup.isCandidate(next, goal: goal, root: root, potential: eval.greedy),
                       key.allSatisfy({ RDCards.sideboardCards.contains($0) }) {
                        let steps = depth + 1
                        let quality = goal == .preLaunch ? eval.greedy : RDSetup.quality(next)
                        let worse = setupKept.count >= RDSetup.keep
                            && (quality, -steps) <= (setupKept[setupKept.count - 1].quality,
                                                      -setupKept[setupKept.count - 1].steps)
                        if !worse {
                            var line = makeLine(parent: index, action: action, state: next,
                                                branchKey: key, order: order)
                            line.healed = next.healedRaw
                            line.potential = quality
                            setupKept.append((quality, steps, line))
                            setupKept.sort { ($0.quality, -$0.steps) > ($1.quality, -$1.steps) }
                            if setupKept.count > RDSetup.keep { setupKept.removeLast() }
                        }
                    }
                    children.append(Child(state: next, parent: index, action: action,
                                          branchKey: key, score: eval.greedy,
                                          builderScore: eval.builder, hash: hash,
                                          constraints: constraints, decision: order, isVariant: isVariant))
                    return
                }
                if next.damageDealt > maxDamage {
                    maxDamage = next.damageDealt
                    bestLine = makeLine(parent: index, action: action, state: next,
                                        branchKey: key, order: order)
                }
                var reachedLethal = false
                if next.damageDealt >= threshold && threshold > 0 {
                    let line = makeLine(parent: index, action: action, state: next,
                                        branchKey: key, order: order)
                    if !line.truncated {
                        lethal.append(line)
                        reachedLethal = true
                    }
                }
                // 伤害比该分叉已记的线低就不用造线（造线要算难度分，是这里最贵的一步）
                let bid = key.isEmpty ? "" : branchId(key)
                if !key.isEmpty, bestByBranch[bid].map({ next.damageDealt >= $0.damage }) ?? true {
                    let line = makeLine(parent: index, action: action, state: next,
                                        branchKey: key, order: order)
                    if let old = bestByBranch[bid] {
                        if line.damage > old.damage
                            || (line.damage == old.damage && line.difficulty < old.difficulty) {
                            bestByBranch[bid] = line
                        }
                    } else {
                        bestByBranch[bid] = line
                    }
                }
                // 已经致死的局面不再往下展开：这一层只有「抽到才斩」的线时搜索接着往深处找确定线，
                // 它们的后代只是同一条线后面加废步
                if reachedLethal { return }
                let eval = evaluate(next)
                children.append(Child(state: next, parent: index, action: action,
                                      branchKey: key, score: eval.greedy,
                                      builderScore: eval.builder, hash: hash,
                                      constraints: constraints, decision: order, isVariant: isVariant))
            }

            for index in frontier {
                if threadCPUTime() > deadline {
                    termination = .budgetExceeded
                    cpuBudgetHit = true
                    break outer
                }
                if let token = config.cancellation, token.isCancelled {
                    termination = .budgetExceeded
                    cancelled = true
                    break outer
                }
                if let cap = config.maxStatesExpanded, statesExpanded >= cap {
                    termination = .budgetExceeded
                    break outer
                }
                let node = nodes[index]
                var dropped = false
                var actions = RDEngine.legalActions(node.state, options: listOptions, dropped: &dropped)
                // 动作生成层丢了合法分支（组合截断 / 跳过的过牌 / 未建模牌）：走完也不算穷举
                if dropped { pruned = true }
                if let cap = config.maxActionsPerNode, actions.count > cap {
                    // 先把执行后等价的友方目标并掉，免得同款随从的几个目标挤占动作上限
                    actions = collapseEquivalentTargets(actions, node.state, node.constraints,
                                                        options: config.options)
                    if actions.count > cap {
                        actions = topActions(actions, node.state, cap: cap)
                        pruned = true
                    }
                }
                for action in actions {
                    guard let first = try? RDEngine.apply(action, to: node.state,
                                                          options: config.options) else { continue }
                    // 爆手的全场弹回 / 复制：此刻才决定场面顺序，展开结果不同的每种排法
                    if case .play(_, let identity, _, _, _) = action, RDEngine.processesBoardInOrder(identity) {
                        let outcomes = orderOutcomes(parent: node, action: action, first: first,
                                                     options: config.options,
                                                     maxVariants: config.maxBoardOrderVariants,
                                                     truncated: &pruned)
                        for (i, o) in outcomes.enumerated() {
                            consider(index, node, action, o.state, o.constraints, o.decision, i > 0)
                        }
                    } else {
                        consider(index, node, action, first, RDBoardOrder.carry(node.constraints, to: first),
                                 nil, false)
                    }
                }
            }

            depth += 1
            if !lethal.isEmpty {
                // 最浅的一层就有斩杀 —— 同层的线操作数相同，正是「最简单的那条」所在的层。
                // 只在这一层有**确定**的斩杀线时收口（T5 A1）：行骗 / 挖宝 / 帷幕 / 矿锄的抽牌按牌库逐种分叉，
                // 「抽到 X 就斩」的线常比确定线浅一两层，在它那里收口会把确定线丢掉，面板只剩「需抽到才斩杀」
                if closeLethalLayer() {
                    termination = .reachedUpperBound
                    break outer
                }
                if isCancelled() {
                    termination = .budgetExceeded
                    cancelled = true
                    break outer
                }
            }
            if children.isEmpty { break }

            children.sort { a, b in
                if a.score != b.score { return a.score > b.score }
                return a.hash < b.hash
            }
            if let width = beamWidth, children.count > width {
                pruned = true
                func pick(_ cs: [Child], _ w: Int) -> [Child] {
                    guard cs.count > w else { return cs }
                    guard w > 0 else { return [] }
                    switch selection {
                    case .scored:
                        return setupGoal == .heal16
                            ? selectBeam(cs, width: w, bucket: { min($0.healedRaw, RDSetup.healTarget) })
                            // 桶 = 已造成伤害 × 场上有没有阿莱：舞动把全场收回手里的节点分数骤降，和「场上还有
                            // 阿莱」的节点挤同一个伤害桶时排在桶底、保底名额轮不到（T5 A2：t2-wuhu-10 补狐在
                            // 第二次舞动那一层掉，t2-wuhui-04 补晦分开后就能搜到）
                            : selectBeam(cs, width: w, bucket: { s in
                                s.damageDealt &* 2 &+ (s.board.contains { $0.card == .alexstrasza } ? 1 : 0)
                            })
                    case .sampled: return sampleBeam(cs, width: w)
                    }
                }
                if let share = config.boardOrderVariantShare {
                    // 爆手的其他排法只在束里争一个固定份额（defaults 不够时可以多占），
                    // 不会把「现有顺序」那一路的线挤出去 —— 排法不设上限时束被它们挤满是掉线的原因
                    let variants = children.filter { $0.isVariant }
                    let defaults = children.filter { !$0.isVariant }
                    let quota = min(variants.count, max(Int(Double(width) * share), width - defaults.count))
                    let keptVariants = pick(variants, quota)
                    let keptDefaults = pick(defaults, width - keptVariants.count)
                    children = (keptDefaults + keptVariants).sorted { a, b in
                        if a.score != b.score { return a.score > b.score }
                        return a.hash < b.hash
                    }
                } else {
                    children = pick(children, width)
                }
            }
            frontier = []
            frontier.reserveCapacity(children.count)
            for c in children {
                nodes.append(Node(state: c.state, parent: c.parent, action: c.action,
                                  branchKey: c.branchKey, constraints: c.constraints, decision: c.decision))
                frontier.append(nodes.count - 1)
            }
        }

        if threadCPUTime() > deadline && termination == .exhausted {
            termination = .budgetExceeded
            cpuBudgetHit = true
        }
        if !frontier.isEmpty && depth >= config.maxDepth { pruned = true }
        func cancelledResult() -> RedDragonResult {
            return RedDragonResult(maxDamage: maxDamage, effectiveEnemyHealth: enemyHealth, isLethal: false,
                                   chosenLine: nil, lethalLines: [], branches: [], missingPieces: [],
                                   missingPiecesBudgetExceeded: false, termination: .budgetExceeded,
                                   cpuTime: 0, statesExpanded: statesExpanded, depthReached: depth,
                                   cancelled: true)
        }
        if cancelled { return cancelledResult() }

        // 收尾（落位翻译、去重排序、重放校验）每条线都要重放，线多时不便宜：每一步之间、每条线之前都看取消
        if let goal = setupGoal {
            var lines = setupKept.compactMap { placed($0.line) }
            if isCancelled() { return cancelledResult() }
            lines = dedupe(lines)
            // 重放校验：同一套规则从根重放一遍，伤害对得上、回血 / 目标达成才留
            lines = lines.filter { line in
                guard !isCancelled(), let end = RDReplay.validate(line.actions, from: root,
                                                                  expectedDamage: line.damage,
                                                                  options: config.options) else { return false }
                return RDSetup.accepts(end, goal: goal)
            }
            if isCancelled() { return cancelledResult() }
            var out = RedDragonResult(maxDamage: 0, effectiveEnemyHealth: enemyHealth, isLethal: false,
                                      chosenLine: nil, lethalLines: [], branches: [], missingPieces: [],
                                      missingPiecesBudgetExceeded: false, termination: termination, cpuTime: 0,
                                      statesExpanded: statesExpanded, depthReached: depth,
                                      placementTranslationFailures: translationFailures,
                                      cpuBudgetHit: cpuBudgetHit, exhaustive: false)
            out.setupLines = lines
            return out
        }
        // 斩杀线在收口的那一层已经翻译、去重、排序、截断过。预算在半层用完时，这半层攒下的线照样收尾；
        // 没有确定线时用只靠抽牌的那些兜底
        if !deterministicLethal, !closeLethalLayer() { lethal = drawOnlyLethal }
        if let best = bestLine { bestLine = placed(best) }
        for (bid, line) in bestByBranch where line.pendingBoardOrders != nil {
            if isCancelled() { break }
            bestByBranch[bid] = placed(line)
        }
        if isCancelled() { return cancelledResult() }

        // 路径重放校验（P0）：任何要返回的线，先用同一套规则从根重放一遍
        func checked(_ line: RedDragonLine) -> Bool {
            return !isCancelled() && validated(line, root: root, config: config)
        }
        lethal = lethal.filter(checked)
        if let best = bestLine, !checked(best) {
            bestLine = nil
        }
        if isCancelled() { return cancelledResult() }

        let chosen = lethal.first ?? bestLine
        let validBranches = bestByBranch.values.filter(checked)
        if isCancelled() { return cancelledResult() }
        let branches = validBranches
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
                               effectiveEnemyHealth: enemyHealth,
                               isLethal: !lethal.isEmpty,
                               deterministicLethal: deterministicLethal && !lethal.isEmpty,
                               chosenLine: chosen,
                               lethalLines: lethal,
                               branches: branches,
                               missingPieces: [],
                               missingPiecesBudgetExceeded: false,
                               termination: termination,
                               cpuTime: 0,
                               statesExpanded: statesExpanded,
                               depthReached: depth,
                               placementTranslationFailures: translationFailures,
                               cpuBudgetHit: cpuBudgetHit,
                               exhaustive: termination == .exhausted && !pruned)
    }

    /// 三件事：① 分桶保底（斩杀搜索按「已造成伤害 × 场上有没有阿莱」，见调用处；只取全局 Top-K 会把
    /// 「龙数低、还在蓄力」的桶整个砍掉，那正是 48 / 64 线所在的桶）；② 共识分占一半；③ 蓄力分（正交）占另一半。
    /// `children` 必须已按共识分降序排好。
    private static func selectBeam(_ children: [Child], width: Int,
                                   bucket bucketOf: (RDState) -> Int = { $0.damageDealt }) -> [Child] {
        var taken = [Bool](repeating: false, count: children.count)
        var picked: [Int] = []
        picked.reserveCapacity(width)

        var buckets: [Int] = []
        for c in children where !buckets.contains(bucketOf(c.state)) {
            buckets.append(bucketOf(c.state))
        }
        buckets.sort()
        if buckets.count > 1 {
            let quota = max(3, width / (3 * buckets.count))
            for bucket in buckets {
                var n = 0
                for (i, c) in children.enumerated() where bucketOf(c.state) == bucket {
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

    /// 按伤害、法力、场面/手牌格数、边牌余量分层，层内按蓄力分取，层间轮流取。
    /// 这样回收前后都有名额；哈希仅打破同分，不再决定哪种资源阶段能留下。
    private static func sampleBeam(_ children: [Child], width: Int) -> [Child] {
        var groups: [[Int]: [Int]] = [:]
        for (i, c) in children.enumerated() {
            let s = c.state
            let key = [s.damageDealt, s.availableMana, s.board.count, s.hand.count, s.sideboard.count]
            groups[key, default: []].append(i)
        }
        let ordered = groups.keys.sorted { $0.lexicographicallyPrecedes($1) }.map { key in
            groups[key]!.sorted { a, b in
                if children[a].builderScore != children[b].builderScore {
                    return children[a].builderScore > children[b].builderScore
                }
                if children[a].score != children[b].score { return children[a].score > children[b].score }
                return children[a].hash < children[b].hash
            }
        }
        var picked: [Int] = []
        var rank = 0
        while picked.count < width {
            for group in ordered where rank < group.count {
                picked.append(group[rank])
                if picked.count == width { break }
            }
            rank += 1
        }
        return picked.sorted().map { children[$0] }
    }

    private static func validated(_ line: RedDragonLine, root: RDState,
                                  config: RedDragonConfig) -> Bool {
        return RDReplay.validate(line.actions, from: root, expectedDamage: line.damage,
                                 options: config.options) != nil
    }

    private static func signature(_ line: RedDragonLine) -> String {
        return line.actions.map { action -> String in
            switch action {
            case .play(_, let identity, let target, let choices, let position):
                return "p\(identity.rawValue)/\(targetCode(target))/"
                    + choices.map { c -> String in
                        if case .pick(let card) = c { return String(card.rawValue) }
                        return "?"
                    }.joined(separator: "-")
                    + (position.map { "@\($0)" } ?? "")
            case .heroPower: return "hp"
            case .attack(let a, let d, let choices):
                return "a\(targetCode(a))>\(targetCode(d))"
                    + (choices.isEmpty ? "" : "/" + choices.map { c -> String in
                        if case .pick(let card) = c { return String(card.rawValue) }
                        return "?"
                    }.joined(separator: "-"))
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
        for c in action.choices {
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

        var handDiscount = 0
        var spellFaceDamage = 0
        var alexCosts: [Int] = []
        for c in s.hand {
            let def = RDCards.def(c.identity(at: 0))
            if !def.isPlaceholder {
                handDiscount += max(0, def.printedCost - s.effectiveBaseCost(c, as: c.identity(at: 0)))
            }
            for e in def.effects {
                switch e {
                case .damageTarget(let n, _) where RDCards.canTargetEnemyHero(def):
                    if def.type == .minion {
                        alexInHand += 1
                        alexCosts.append(s.cost(of: c, as: c.identity(at: 0)))
                        faceDamagePerTrigger = max(faceDamagePerTrigger, n)
                    } else {
                        // 打脸法术（袋底藏沙）只打一次，不吃弹回 / 复制的放大
                        spellFaceDamage += n
                    }
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
        let ub = s.damageDealt + attackPotential + spellFaceDamage
            + faceDamagePerTrigger * multiplier * triggers

        // handDiscount：手里已经降下来的费（弹回 / 复制出来的 1 费牌、殒变出的 0 费牌）。
        // 不计它时，「弹回之后、龙还没下」的节点分数骤降，48 / 64 长线在弹回后一层掉出束。
        // 权重 3 / 4 是 2026-10-04 在 65 个公式案例上扫出来的（0/0 过 61，2/3、3/4、4/4 都是 64，
        // 3/6、6/8、10/14 反而变差），取中间值。
        // ready：手里现在就打得出的阿莱（按当前费用从便宜的起、法力和格子够几条算几条，鲨鱼在场才翻倍）。
        // 乐观估计只数「够得着几次触发」、不看费用：鲨鱼 / 刀油 / 晦鳞已下场、手里两条 1 费阿莱的局面，和手里
        // 三条 9 费阿莱却没法力的局面比，前者分数反而低，在收口前一步掉出束（T5 A2：t2-wuhu-10 补狐在第 19 步掉）。
        // 权重 8 是在两条已知漏线上试出来的（只试了这一个值）；公式表 80 个案例达标数不变（齐件 53、缺件 27），
        // 只有 t1-48p-04 的搜索伤害 65 → 64（目标 64）
        var ready = 0
        if !alexCosts.isEmpty {
            alexCosts.sort()
            var left = s.availableMana
            var slots = s.boardSlotsFree
            for cost in alexCosts where cost <= left && slots > 0 {
                left -= cost
                slots -= 1
                ready += faceDamagePerTrigger * (s.sharkAuraActive ? 2 : 1)
            }
        }
        let greedy = ub * 10 + s.damageDealt * 4 + s.availableMana * 6
            + layerValue * 4 + s.boardSlotsFree * 2 + (s.sharkAuraActive ? 20 : 0)
            + handDiscount * 3 + ready * 8
        let builder = s.availableMana * 8 + layerValue * 8 + s.boardSlotsFree * 6
            + s.handSlotsFree * 2 + (s.sharkAuraActive ? 40 : 0)
            + handDiscount * 4
            + bouncesAndCopies * 25 + (alexInHand + alexOnBoard + fromSideboard) * 30
            + s.damageDealt * 2
        return RDEval(greedy: greedy, builder: builder, upperBound: ub)
    }

    /// 每个节点的动作先验，只用来在展开前砍掉低价值动作
    private static func actionPrior(_ action: RDAction, _ s: RDState) -> Int {
        switch action {
        case .play(_, let identity, let target, _, _):
            let def = RDCards.def(identity)
            var p = 40
            for e in def.effects + def.comboEffects {
                switch e {
                case .damageTarget(let n, _):
                    p = max(p, target == .enemyHero || target == .friendlyHero ? 900 + n * 10 : 120)
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
        case .attack(_, let defender, _):
            return defender == .enemyHero ? 200 : 90
        }
    }

    /// 去重键 = 局面哈希 + 场上已定的先后关系（同一局面、可排的余地不同，后面能走的线不同）
    static func dedupKey(_ hash: UInt64, _ c: RDBoardConstraints, _ board: [RDBoardMinion]) -> UInt64 {
        return hash ^ (c.positionMask(board) &* 0x9e37_79b9_7f4a_7c15)
    }

    /// 场序起作用时引擎按实体列出全部友方目标（见 `RDEngine.appendFriendlyTargets`）。只差在「指的是
    /// 哪一个同款随从」的动作（同一张牌、同选择、同落位，目标的 `minionKey` 相同）逐个执行，
    /// 执行后「局面 + 偏序」相同的只留第一个；执行失败的原样留着，由主循环照常跳过
    static func collapseEquivalentTargets(_ actions: [RDAction], _ s: RDState, _ c: RDBoardConstraints,
                                          options: RDOptions) -> [RDAction] {
        var groups: [String: [Int]] = [:]
        for (i, a) in actions.enumerated() {
            guard case .play(let eid, let identity, .friendlyMinion(let tid), let choices, let position) = a,
                  !RDEngine.processesBoardInOrder(identity),
                  let m = s.board.first(where: { $0.entityId == tid }) else { continue }
            groups["\(eid)|\(identity.rawValue)|\(choices)|\(String(describing: position))|\(RDEngine.minionKey(m))",
                   default: []].append(i)
        }
        var drop = Set<Int>()
        for (_, members) in groups where members.count > 1 {
            var keys = Set<UInt64>()
            for i in members {
                guard let next = try? RDEngine.apply(actions[i], to: s, options: options) else { continue }
                let key = dedupKey(next.canonicalHash(), RDBoardOrder.carry(c, to: next), next.board)
                if !keys.insert(key).inserted { drop.insert(i) }
            }
        }
        guard !drop.isEmpty else { return actions }
        return actions.enumerated().filter { !drop.contains($0.offset) }.map { $0.element }
    }

    private static func topActions(_ actions: [RDAction], _ s: RDState, cap: Int) -> [RDAction] {
        var scored = actions.enumerated().map { (i, a) in (prior: actionPrior(a, s), index: i, action: a) }
        scored.sort { a, b in
            if a.prior != b.prior { return a.prior > b.prior }
            return a.index < b.index
        }
        return scored.prefix(cap).map { $0.action }
    }

    // MARK: - 落位

    // 束搜索不在下随从时逐格展开落位（`expandPlacements = false`，随从先放最右），而在爆手的全场
    // 复制（幻觉药水，待核；舞动 T2b 起按上场先后、不在此列）那一步展开「复制哪几张」（`RDBoardOrder`，
    // 原理见那里）。线要返回时再翻译回每次下随从的落位，并由 `validated` 用真实落位重放一遍。

    /// `RDBoardOrder.outcomes`，排法只留共识分最高的 `maxVariants` 种（现有顺序那一种总在）：
    /// 排法全放进束会把别的线挤掉（公式表上全展开时 4 个案例掉线）
    private static func orderOutcomes(parent: Node, action: RDAction, first: RDState,
                                      options: RDOptions, maxVariants: Int?,
                                      truncated: inout Bool) -> [RDBoardOutcome] {
        let all = RDBoardOrder.outcomes(of: action, from: parent.state, constraints: parent.constraints,
                                        first: first, options: options)
        guard let cap = maxVariants, all.count > cap + 1 else { return all }
        truncated = true
        // 和束一样用两种正交的分各取前 cap 个：共识分（收口）和蓄力分（留下能回费 / 降费的随从）。
        // 只按共识分取时，留下回费随从的排法排不进来（T2a 时舞动也按场位，公式表 t2-wuhu-03 的清杂分支靠它；
        // T2b 起舞动不走这里，现在只剩药水爆手）
        let scored = all.dropFirst().map { v -> (RDBoardOutcome, RDEval, UInt64) in
            (v, evaluate(v.state), v.state.canonicalHash())
        }
        let byGreedy = scored.sorted { $0.1.greedy != $1.1.greedy ? $0.1.greedy > $1.1.greedy : $0.2 < $1.2 }
        let byBuilder = scored.sorted { $0.1.builder != $1.1.builder ? $0.1.builder > $1.1.builder : $0.2 < $1.2 }
        var picked: [RDBoardOutcome] = [all[0]]
        var hashes: [UInt64] = []
        for v in byGreedy.prefix(cap) + byBuilder.prefix(cap) where !hashes.contains(v.2) {
            hashes.append(v.2)
            picked.append(v.0)
        }
        return picked
    }

    private static func withPlacements(_ line: RedDragonLine, root: RDState,
                                       options: RDOptions) -> RedDragonLine? {
        guard let orders = line.pendingBoardOrders else { return line }
        guard let actions = RDBoardOrder.assignPositions(line.actions, decisions: orders, root: root,
                                                         options: options) else { return nil }
        var out = line
        out.pendingBoardOrders = nil
        out.actions = actions
        return out
    }

    // MARK: - 缺件

    /// 无解时，对牌库剩余的每种零件试「加进手牌再算」。
    /// 闸门和主搜索同一种：按展开状态数，总量平分到候选上 —— 同一局面在哪台机器、多忙都给同一个答案。
    /// CPU 时间只做兜底，撞上了就停并标出来。缺件是锦上添花，不能拖垮主搜索。
    private static func findMissingPieces(_ root: RDState, config: RedDragonConfig,
                                          deadline: Double) -> (cards: [RDCard], budgetExceeded: Bool) {
        // 牌库里没建模的牌（占位「杂」）打不出去，不可能是缺的那一张，别浪费预算去试
        let candidates = root.deck.remaining(filter: .any)
            .filter { !RDCards.def($0).isPlaceholder }
        // 手牌已满：多抽到的那一张会被烧掉，「多这一张」不成立
        guard !candidates.isEmpty, root.handSlotsFree > 0 else { return ([], false) }
        let perCard = max(1, config.missingPieceMaxStates / candidates.count)
        var out: [RDCard] = []
        for card in candidates {
            if threadCPUTime() > deadline { return (out, true) }
            if config.cancellation?.isCancelled == true { return (out, false) }
            var probe = root
            probe.deck.remove(card)
            let id = probe.takeEntityId()
            probe.hand.append(RDHandCard(entityId: id, card: card,
                                         isShadowOfDemise: card == .shadowOfDemise))
            var sub = config
            sub.enableMissingPieces = false
            sub.maxStatesExpanded = perCard
            // 缺件是「多这一张能不能斩」的粗判，束宽压到主搜索的一小半，别让它吃掉主线的预算
            sub.beamWidth = min(300, config.beamWidth ?? 300)
            let r = search(probe, config: sub, deadline: deadline)
            if r.isLethal { out.append(card) }
            if r.termination == .budgetExceeded && r.statesExpanded < perCard {
                return (out, true)
            }
        }
        return (out, false)
    }

    // MARK: - 准备线（T4）

    /// 本回合不斩杀时的准备线。和斩杀搜索共用同一个 `search`（`config.setup`）：束搜索 + 同一套规则引擎 +
    /// 同一遍重放校验，只是不找斩杀，而是收集「满足目标的终局」。收完再给每个终局的「下回合能打多少」
    /// 做一次小预算的探针（把终局当下回合起手、对手血量放到够不着，量 `maxDamage`），按它排。
    /// 排序：下回合伤害按 8（一次阿莱触发）分档 → 步数少 → 伤害高。（档内差 < 8 的两条线不分高低，选步数少的）
    static func solveSetup(_ root: RDState, goal: RDSetupGoal,
                           config base: RedDragonConfig = RedDragonConfig()) -> RedDragonResult {
        let start = threadCPUTime()
        var c = base
        c.setup = goal
        c.options.healFriendlyHero = goal == .heal16
        c.maxStatesExpanded = base.setupMaxStates
        c.cpuBudget = base.setupCpuBudget
        c.boardOrderPass = nil
        c.samplingPassWidth = nil
        c.enableMissingPieces = false
        var r = search(root, config: c, deadline: start + c.cpuBudget)
        if !r.cancelled {
            var probed = r.setupLines
            // 探针合计有 CPU 兜底：候选已按便宜的分排好，撞上了就只留探过的
            let probeDeadline = threadCPUTime() + RDSetup.probeTotalBudget
            for i in probed.indices {
                if base.cancellation?.isCancelled == true {
                    r.cancelled = true
                    break
                }
                if threadCPUTime() > probeDeadline {
                    probed = Array(probed.prefix(i))
                    break
                }
                guard let end = try? RDReplay.run(probed[i].actions, from: root, options: c.options).finalState else {
                    continue
                }
                probed[i].potential = RDSetup.probe(end, config: base)
            }
            if !r.cancelled {
                probed.sort { a, b in
                    let (x, y) = (a.potential / 8, b.potential / 8)
                    if x != y { return x > y }
                    if a.actions.count != b.actions.count { return a.actions.count < b.actions.count }
                    return a.potential > b.potential
                }
                r.setupLines = probed
            }
        }
        r.cpuTime = threadCPUTime() - start
        return r
    }
}

enum RDSetup {
    /// 回血线的目标：一张阿莱在鲨鱼下回 16
    static let healTarget = 16
    /// 每个搜索留的候选条数（探针只对这些做）
    static let keep = 30
    static let probeStates = 8_000
    static let probeBudget = 0.25
    static let probeTotalBudget = 1.0

    /// 把回合结束时的局面当成下回合起手：法力 +1（封顶 10）、减费层 / 本回合计数清零、随从都能动
    static func nextTurn(_ s: RDState) -> RDState {
        var t = s
        t.maxMana = min(10, s.maxMana + 1)
        t.mana = t.maxMana
        t.tempMana = 0
        t.layers = []
        t.cardsPlayedThisTurn = 0
        t.heroAttackedThisTurn = false
        t.heroPowerUsed = false
        t.damageDealt = 0
        t.healedRaw = 0
        for i in t.board.indices {
            t.board[i].summoningSick = false
            t.board[i].attacksThisTurn = 0
        }
        return t
    }

    /// 便宜的「下回合潜力」：把终局当下回合起手跑一遍共识分
    static func quality(_ s: RDState) -> Int {
        return RedDragonSearch.evaluate(nextTurn(s)).greedy
    }

    static func evaluate(_ s: RDState, goal: RDSetupGoal) -> RedDragonSearch.RDEval {
        switch goal {
        case .heal16:
            // 回血记进「伤害」栏（封顶 16）：共识分里的乐观上界 / 已完成量都按它走，阿莱对自己和对脸同价
            var t = s
            t.damageDealt = min(s.healedRaw, healTarget)
            return RedDragonSearch.evaluate(t)
        case .preLaunch:
            var e = RedDragonSearch.evaluate(nextTurn(s))
            e.builder = RedDragonSearch.evaluate(s).builder
            return e
        }
    }

    static func isCandidate(_ s: RDState, goal: RDSetupGoal, root: RDState, potential: Int) -> Bool {
        switch goal {
        case .heal16:
            return s.healedRaw >= healTarget
        case .preLaunch:
            // 比不动强才算：至少打过一张牌，且下回合潜力高于根局面
            return s.cardsPlayedThisTurn > root.cardsPlayedThisTurn
                && potential > quality(root)
        }
    }

    static func accepts(_ end: RDState, goal: RDSetupGoal) -> Bool {
        return goal == .heal16 ? end.healedRaw >= healTarget : true
    }

    /// 终局当下回合起手，小预算搜一遍能打多少（对手血量放到够不着）
    static func probe(_ end: RDState, config base: RedDragonConfig) -> Int {
        var t = nextTurn(end)
        t.opponent.health = 999
        t.opponent.armor = 0
        var c = RedDragonConfig()
        c.weights = base.weights
        c.maxStatesExpanded = probeStates
        c.cpuBudget = probeBudget
        c.beamWidth = 400
        c.samplingPassWidth = nil
        c.boardOrderPass = nil
        c.enableMissingPieces = false
        c.cancellation = base.cancellation
        return RedDragonSearch.solve(t, config: c).maxDamage
    }
}
