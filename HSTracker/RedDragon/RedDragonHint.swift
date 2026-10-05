//
//  RedDragonHint.swift
//  HSTracker
//
//  展示模型：搜索结果 → overlay 该画什么。与 SwiftUI 无关的值类型，T2c 只读。
//  需求出处：docs/research/red-dragon-rogue-spike.md 第二节（揭示节奏 / 多条线 / 同名牌 / 抽牌 / 对手侧 /
//  预启动 / 重编号）与第六节（已决）。
//

import Foundation

/// 三档揭示（spike 二、1）
enum RDRevealLevel: Int, CaseIterable, Comparable {
    /// L0 判定：只一个角标「可斩杀 28 / 27」或「最大 19 / 27」
    case verdict = 0
    /// L1 参与牌：参与 combo 的手牌高亮，分必打 / 可选
    case cards = 1
    /// L2 顺序：前 3 步的手牌序号 + 场面标记 + 一行「下一步」
    case order = 2

    static func < (lhs: RDRevealLevel, rhs: RDRevealLevel) -> Bool { return lhs.rawValue < rhs.rawValue }
}

/// 搜索做到了什么程度。`.capped` 是生产配置下不斩杀局面的常态（40 万状态闸门），可复现，
/// 不该当成「被截断」吓用户；只有撞上 CPU 兜底（结果随机器负载变）才是 `.truncated`
enum RDCompleteness: Equatable {
    /// 找到斩杀，或把搜索空间走完
    case complete
    /// 没找到斩杀、状态预算用完：不是穷举，但同一局面总给同一个答案
    case capped
    /// 撞上 CPU 兜底，同一局面换个时候算可能不同
    case truncated
}

/// 手牌上的一张参与牌（L1）
struct RDHandMark: Equatable {
    enum Role: Equatable {
        /// 每条斩杀线都要打这张
        case required
        /// 有的线用、有的线不用
        case optional
    }
    var entityId: Int
    var zonePosition: Int
    var role: Role
}

/// 步骤里指到的东西。`entityId` 都是游戏里的 entity id；指的是这回合才会造出来的牌（复制体等）时为 nil
enum RDStepTarget: Equatable {
    case friendlyMinion(entityId: Int?, cardId: String)
    case enemyMinion(entityId: Int, cardId: String)
    case enemyHero
}

/// 发现 / 抽牌的结果。`isDraw` = 随机抽牌（取决于抽到什么），false = E.T.C. 发现（自己选）
struct RDPick: Equatable {
    var cardId: String
    var isDraw: Bool
}

struct RDStep: Equatable {
    enum Kind: Equatable {
        /// 打一张现在就在手里的牌（`handEntityId` / `zonePosition` 有值）
        case playFromHand
        /// 打一张这回合才会进手的牌（复制体、弹回、发现、抽到的）
        case playGenerated
        /// 随从或英雄攻击（`attacker` 有值）
        case attack
        case heroPower
    }
    /// 从 1 起
    var index: Int
    var kind: Kind
    var cardId: String?
    var handEntityId: Int?
    var zonePosition: Int?
    /// 攻击方：我方随从的 entity id（英雄攻击为 nil）
    var attacker: RDStepTarget?
    var target: RDStepTarget?
    var picks: [RDPick]
    /// 随从落位：插在场上第几格之前（0 = 最左），nil = 最右
    var boardPosition: Int?
}

/// 场上随从位置要画的小标记（spike 二、7：不在手牌上的步骤）
struct RDBoardMark: Equatable {
    enum Role: Equatable { case attacker, target }
    var entityId: Int
    var isEnemy: Bool
    var stepIndex: Int
    var role: Role
}

/// 抽牌分叉：沿途随机抽到这些牌时这一支能打多少
struct RDDrawBranch: Equatable {
    var drawn: [String]
    var damage: Int
    var isLethal: Bool
}

/// 判定的确定程度。「没搜到斩杀」和「证明不能斩杀」是两回事：撞状态上限、束裁剪、手牌费用是推断的，
/// 都只能说没搜到；斩杀要靠随机抽牌的也不是确定能斩
enum RDLethalVerdict: Equatable {
    /// 有不靠随机抽牌的斩杀线
    case lethal
    /// 能斩，但每条线都要抽到某张牌
    case lethalIfDraw
    /// 没搜到斩杀，但不能排除（搜索有裁剪 / 撞了上限 / 有费用是推断的 / 动作生成丢了分支 / 有未建模的牌）
    case notFound
    /// 按本模型穷举过（束、动作上限、组合上限都没裁过）、手牌费用全是读出来的、手里和牌库里没有未建模的牌、
    /// 没有跳过的过牌：不能斩杀。「本模型」之外的东西（对手的奥秘、未建模的随机效果）仍不在证明范围内
    case provenNotLethal
}

/// 一次搜索的完整结论（不含揭示档 / 答题判定，那两样随用户操作变，见 `RedDragonHint`）
struct RDAnalysis: Equatable {
    var turn: Int
    var availableMana: Int
    /// `verdict` 是 `.lethal` 或 `.lethalIfDraw`
    var isLethal: Bool
    var verdict: RDLethalVerdict
    /// 有手牌的底费看不出来、按上限估的（`RDLiveState.inferredBaseCostEntities` 非空）。
    /// 估贵不会算出打不出的斩杀线，但「没搜到」就不能当证明
    var costsInferred: Bool
    /// 能斩，但每条斩杀线都要靠随机抽到某张牌
    var lethalDependsOnDraw: Bool
    var maxDamage: Int
    var effectiveEnemyHealth: Int
    /// `maxDamage - effectiveEnemyHealth`，≥ 0 即斩杀
    var margin: Int { return maxDamage - effectiveEnemyHealth }
    var completeness: RDCompleteness
    /// 最简斩杀线的难度档；不斩杀时为 nil
    var tier: RDDifficulty.Tier?
    var handMarks: [RDHandMark]
    /// 前 3 步（不斩杀时是伤害最高那条线的前 3 步）
    var steps: [RDStep]
    var totalSteps: Int
    var boardMarks: [RDBoardMark]
    var nextStepText: String
    var drawBranches: [RDDrawBranch]
    /// 牌库里「多这一张就能斩」的牌（只在不斩杀时算）
    var missingPieces: [String]
    /// 缺件子搜索撞上 CPU 兜底，列表可能不全
    var missingPiecesIncomplete: Bool
    /// 「单回合不够，考虑预启动」（spike 二、6）。只在 `verdict == .provenNotLethal` 时为 true
    var singleTurnInsufficient: Bool
    /// 「场面危险，必须下怪」：对方下回合场攻 ≥ 我方血量 + 护甲 − `RDHintBuilder.dangerMargin`
    var boardDanger: Bool
    var opponentHasSecrets: Bool
    /// 本回合已经做过的操作数（`NUM_OPTIONS_PLAYED_THIS_TURN`：出牌、攻击、英雄技能），回合内只增不减。
    /// 答题模式用它判断「做了一步」；不从场面推（攻击后死掉、被弹回的随从会让推出来的数倒退）
    var actionsTaken: Int

    // 这个结论对应的手牌 / 场面排位（entity id，从左到右）。overlay 用它把标记落到第几张 / 第几格；
    // 只在结论不过时画标记，所以排位和屏上一致
    var handOrder: [Int] = []
    var boardSlots: [Int] = []
    var opponentBoardSlots: [Int] = []
}

/// 答题模式（spike 二、1）：不显示序号，每做一步判卷
enum RDQuizMark: Equatable {
    /// 打完这一步仍在某条斩杀线上
    case onLine
    /// 这一步打完已经不可能斩杀
    case offLine
}

/// overlay 读的全部状态
struct RedDragonHint: Equatable {
    enum Phase: Equatable {
        /// 开关关着 / 不在对局 / 不是红龙贼套牌：什么都不画
        case inactive
        /// 对方回合
        case opponentTurn
        /// 局面变了、新结果在算（`analysis` 若非空是上一个局面的，已过时）
        case computing
        case ready
    }
    var phase: Phase
    var analysis: RDAnalysis?
    /// `analysis` 对应的不是当前局面
    var isStale: Bool
    /// 当前生效的揭示档（已按难度封顶）
    var revealLevel: RDRevealLevel
    /// 这个结论最多能揭示到哪一档
    var maxRevealLevel: RDRevealLevel
    var quizMode: Bool
    var quiz: RDQuizMark?

    static let inactive = RedDragonHint(phase: .inactive, analysis: nil, isStale: false,
                                        revealLevel: .verdict, maxRevealLevel: .verdict,
                                        quizMode: false, quiz: nil)
}

// MARK: - 揭示档规则

enum RDRevealPolicy {

    /// 难度档 → 最多揭示到哪一档。spike 二、1：最简可用线是「基础」档 → 不许升到 L2；
    /// 不斩杀时只有判定（L1 / L2 没有可指的线）。
    /// 设置选了「顺序」（`preference == .order`）时不按难度封顶：斩杀线一律给顺序，连招中途重算出更简单的线
    /// 也不降档（10-05 用户定：猎人那把打出幸运币后线变「基础」，顺序被封成参与牌，公式中途消失）
    static func cap(isLethal: Bool, tier: RDDifficulty.Tier?, preference: RDRevealLevel? = nil) -> RDRevealLevel {
        guard isLethal, let tier = tier else { return .verdict }
        if preference == .order { return .order }
        switch tier {
        case .basic: return .cards
        case .advanced, .hard: return .order
        }
    }

    /// 进回合时的默认档：只有难线可用 → 兜底引导默认开；其余按用户偏好，再按难度封顶
    static func defaultLevel(preference: RDRevealLevel, isLethal: Bool,
                             tier: RDDifficulty.Tier?) -> RDRevealLevel {
        let top = cap(isLethal: isLethal, tier: tier, preference: preference)
        if isLethal && tier == .hard { return top }
        return min(preference, top)
    }

    /// `requested`：本回合用户按热键选的档（nil = 没按过）。结论变了（打出一张后重算）时照样封顶
    static func effective(requested: RDRevealLevel?, preference: RDRevealLevel,
                          isLethal: Bool, tier: RDDifficulty.Tier?) -> RDRevealLevel {
        let top = cap(isLethal: isLethal, tier: tier, preference: preference)
        if let r = requested { return min(r, top) }
        return defaultLevel(preference: preference, isLethal: isLethal, tier: tier)
    }
}

// MARK: - 答题模式

/// 一回合内的判卷状态。T2b 第四轮改成「按一个操作完成的边界，把场面和计数配对」：
/// 日志里出牌时 `NUM_OPTIONS_PLAYED_THIS_TURN` **先于** PLAY 块在顶层 +1（g2 fixture 第 16164 → 16184 行），
/// 攻击时却**在**攻击、矿锄抽牌、死亡结算这几个块**之后**才 +1（g2 第 4078、5824 行）。所以：
/// - 计数涨了、场面还没变 → 出牌开始了，还没完成，等；
/// - 计数没涨、攻击计数（英雄 / 随从本回合攻击次数）、出牌数或英雄技能先动了 → 攻击（或技能）进行中，等，
///   **不拿进行中的结论覆盖「操作之前」的结论**；
/// - 计数涨了、场面也变了 → 这一步完成，用「操作之前」那次结论和现在的结论判卷；
/// - 计数没涨、也没有操作在进行 → 同一个局面的后续（出牌后的死亡结算、回合开始的抽牌、重算），
///   更新「当前结论」，上一步的判定用同一个「操作之前」的结论重判。
///
/// 「操作已开始」只认**操作计数器**（`RDOpCounters`：英雄攻击次数、玩家实体的「本回合攻击过的友方随从数」、
/// 出牌数、英雄技能），不认场面增减。T2b 第五轮：原来按「仍在场随从的攻击次数」认随从攻击，攻击随从撞死就
/// 认不出来，死亡后的局面被当成新的「操作之前」。这几个计数器基本只在玩家做操作时涨，回合开始的效果、死亡结算、
/// 亡语连锁清场都不动它们；例外是效果触发的攻击（耐普图隆之手，10-04 21:10 日志第 267976 行）也会让随从攻击计数涨，
/// 红龙流程里没有这类牌，最坏是那一步推迟到下一步完成时才判。
/// `pending` 的解除：① 计数涨了（这一步完成）；② 换回合；③ 计数器在 pending 期间**又**涨了（上一个操作计数
/// 没涨就结束了、下一个已经开始）→ 用 pending 期间最后一份局面把上一步判完，再进入新的 pending；
/// ④ 计数器比 pending 开始时小（不该发生，回合内只增不减）→ 当作重来，解除。
struct RDQuizState: Equatable {
    var turn: Int
    /// 判过卷的最大操作数（本回合单调不减：快照里的计数就算倒退也不会重判）
    var lastActions: Int
    /// 最近一个「已完成」的局面（上一步完成时 / 回合开始，之后被同一局面的后续更新）
    var settled: RDGameSnapshot
    /// `settled` 的结论 = 下一步「操作之前」的结论
    var baseline: RDLethalVerdict
    /// 上一步「操作之前」的结论和判定（同一步的后续重判用）；本回合还没做过操作时为 nil
    var lastOp: RDQuizOp?
    /// 攻击 / 技能已经开始、计数还没涨（nil = 没有）
    var pendingOp: RDQuizPending?
    var mark: RDQuizMark?

    var pending: Bool { return pendingOp != nil }

    /// 判卷：
    /// - 现在有确定斩杀线 → 绿；
    /// - 操作之前有确定斩杀线（或之前已经判红）、现在**证明**不能斩 → 红；
    /// - 其余（没搜到但没证明、要靠抽牌、之前就不确定）→ 不判。没证明的结论不能把人判错
    static func judge(before: RDLethalVerdict, markBefore: RDQuizMark?, after: RDLethalVerdict) -> RDQuizMark? {
        if after == .lethal { return .onLine }
        if after == .provenNotLethal && (before == .lethal || markBefore == .offLine) { return .offLine }
        return nil
    }

    /// 新结论到了（`snapshot` 是算出这个结论的局面）
    static func next(_ previous: RDQuizState?, snapshot: RDGameSnapshot,
                     verdict: RDLethalVerdict) -> RDQuizState {
        let actions = snapshot.optionsPlayedThisTurn
        guard let p = previous, p.turn == snapshot.turn else {
            return RDQuizState(turn: snapshot.turn, lastActions: actions, settled: snapshot, baseline: verdict,
                               lastOp: nil, pendingOp: nil, mark: nil)
        }
        let changed = !sameIgnoringOptionCount(snapshot, p.settled)
        if actions > p.lastActions {
            // 出牌：计数先涨、场面还没动 → 等
            guard changed else { return p }
            return completed(p, at: snapshot, verdict: verdict, actions: actions)
        }
        let counters = RDOpCounters(snapshot)
        if let pend = p.pendingOp {
            if counters.anyBelow(pend.counters) {
                // 计数器倒退：不是同一个回合内的延续，当作重来
                var q = p
                q.pendingOp = nil
                q.settled = snapshot
                q.baseline = verdict
                return q
            }
            if counters.anyAbove(pend.counters) {
                // 上一个操作计数没涨就结束了，下一个已经开始：用 pending 期间最后一份局面把上一步判完
                var q = completed(p, at: pend.lastSnapshot, verdict: pend.lastVerdict, actions: p.lastActions)
                q.pendingOp = RDQuizPending(counters: counters, lastSnapshot: snapshot, lastVerdict: verdict)
                return q
            }
            var q = p
            q.pendingOp?.lastSnapshot = snapshot
            q.pendingOp?.lastVerdict = verdict
            return q
        }
        if operationStarted(snapshot, since: p.settled) {
            var q = p
            q.pendingOp = RDQuizPending(counters: counters, lastSnapshot: snapshot, lastVerdict: verdict)
            return q
        }
        var q = p
        q.settled = snapshot
        q.baseline = verdict
        if let op = p.lastOp {
            q.mark = judge(before: op.before, markBefore: op.markBefore, after: verdict)
        }
        return q
    }

    /// 一步完成：用 `settled` 的结论（操作之前）判卷，`snapshot` 成为新的 `settled`
    private static func completed(_ p: RDQuizState, at snapshot: RDGameSnapshot, verdict: RDLethalVerdict,
                                  actions: Int) -> RDQuizState {
        let mark = judge(before: p.baseline, markBefore: p.mark, after: verdict)
        return RDQuizState(turn: p.turn, lastActions: actions, settled: snapshot, baseline: verdict,
                           lastOp: RDQuizOp(before: p.baseline, markBefore: p.mark), pendingOp: nil, mark: mark)
    }

    /// 只差操作数的两个局面
    static func sameIgnoringOptionCount(_ a: RDGameSnapshot, _ b: RDGameSnapshot) -> Bool {
        var x = a
        x.optionsPlayedThisTurn = b.optionsPlayedThisTurn
        return x == b
    }

    /// 计数还没涨、但已经有操作在进行：操作计数器（见 `RDOpCounters`）有一个涨了。
    /// 回合开始的抽牌 / 移走随从、出牌后的死亡结算、亡语连锁都不会动这几个数
    static func operationStarted(_ s: RDGameSnapshot, since settled: RDGameSnapshot) -> Bool {
        return RDOpCounters(s).anyAbove(RDOpCounters(settled))
    }
}

struct RDQuizOp: Equatable {
    var before: RDLethalVerdict
    var markBefore: RDQuizMark?
}

struct RDQuizPending: Equatable {
    /// pending 开始时的操作计数器
    var counters: RDOpCounters
    /// pending 期间最后一份局面和它的结论（计数一直不涨、下一个操作先开始时，用它把这一步判完）
    var lastSnapshot: RDGameSnapshot
    var lastVerdict: RDLethalVerdict
}

/// 只在玩家做操作时才涨的计数器，回合内只增不减
struct RDOpCounters: Equatable {
    var heroAttacks: Int
    /// 玩家实体的 `NUM_FRIENDLY_MINIONS_THAT_ATTACKED_THIS_TURN`：攻击随从死了也不回退
    var minionsAttacked: Int
    var cardsPlayed: Int
    var heroPowerUsed: Int

    init(_ s: RDGameSnapshot) {
        heroAttacks = s.heroAttacksThisTurn
        minionsAttacked = s.minionsAttackedThisTurn
        cardsPlayed = s.cardsPlayedThisTurn
        heroPowerUsed = s.heroPowerExhausted ? 1 : 0
    }

    func anyAbove(_ o: RDOpCounters) -> Bool {
        return heroAttacks > o.heroAttacks || minionsAttacked > o.minionsAttacked
            || cardsPlayed > o.cardsPlayed || heroPowerUsed > o.heroPowerUsed
    }

    func anyBelow(_ o: RDOpCounters) -> Bool {
        return heroAttacks < o.heroAttacks || minionsAttacked < o.minionsAttacked
            || cardsPlayed < o.cardsPlayed || heroPowerUsed < o.heroPowerUsed
    }
}

// MARK: - 搜索结果 → 结论

enum RDHintBuilder {

    /// 手牌序号只标前几步（spike 二、7）
    static let stepsShown = 3
    /// 「场面危险」的余量：对方场攻离我方有效血量还差这么多以内就算危险
    static let dangerMargin = 3

    static func analyze(snapshot snap: RDGameSnapshot, live: RDLiveState, result: RedDragonResult,
                        cardName: (String) -> String) -> RDAnalysis {
        let root = live.state
        // 优先不靠随机抽牌的斩杀线；搜索已按难度升序排好，所以第一条就是「最简单的那条」
        let deterministic = result.lethalLines.filter { !RDLineWalker.dependsOnDraw($0.actions, root: root) }
        let lethalPool = deterministic.isEmpty ? result.lethalLines : deterministic
        let chosen = lethalPool.first ?? result.chosenLine
        let isLethal = result.isLethal && !result.lethalLines.isEmpty

        var steps: [RDStep] = []
        var total = 0
        var boardMarks: [RDBoardMark] = []
        if let line = chosen {
            var enemyCards: [Int: String] = [:]
            for m in snap.opponentBoard { enemyCards[m.entityId] = m.cardId }
            let walked = RDLineWalker.walk(line.actions, root: root, zones: live.handZonePositions,
                                           enemyCards: enemyCards)
            total = walked.count
            steps = Array(walked.prefix(stepsShown))
            for s in steps {
                if case .friendlyMinion(let id?, _)? = s.attacker {
                    boardMarks.append(RDBoardMark(entityId: id, isEnemy: false, stepIndex: s.index, role: .attacker))
                }
                switch s.target {
                case .friendlyMinion(let id?, _)?:
                    boardMarks.append(RDBoardMark(entityId: id, isEnemy: false, stepIndex: s.index, role: .target))
                case .enemyMinion(let id, _)?:
                    boardMarks.append(RDBoardMark(entityId: id, isEnemy: true, stepIndex: s.index, role: .target))
                default:
                    break
                }
            }
        }

        // L1：每条斩杀线都打的手牌是必打，只在部分线里出现的是可选
        var handMarks: [RDHandMark] = []
        if isLethal {
            let used = lethalPool.map { RDLineWalker.handEntitiesPlayed($0.actions, root: root) }
            let all = used.reduce(Set<Int>()) { $0.union($1) }
            let every = used.dropFirst().reduce(used.first ?? []) { $0.intersection($1) }
            for c in snap.hand where all.contains(c.entityId) {
                handMarks.append(RDHandMark(entityId: c.entityId, zonePosition: c.zonePosition,
                                            role: every.contains(c.entityId) ? .required : .optional))
            }
        }

        // 抽牌分叉：分叉键里去掉 E.T.C. 的发现（那是自己选的），只留随机抽到的牌
        var byDraw: [[RDCard]: Int] = [:]
        for b in result.branches {
            let drawn = b.drawn.filter { !RDCards.sideboardCards.contains($0) }
            guard !drawn.isEmpty else { continue }
            byDraw[drawn] = max(byDraw[drawn] ?? 0, b.line.damage)
        }
        let branches = byDraw
            .map { RDDrawBranch(drawn: $0.key.map(cardId), damage: $0.value,
                                isLethal: $0.value >= result.effectiveEnemyHealth) }
            .sorted { a, b in a.damage != b.damage ? a.damage > b.damage : a.drawn.lexicographicallyPrecedes(b.drawn) }

        let completeness: RDCompleteness
        if isLethal || result.termination != .budgetExceeded {
            completeness = .complete
        } else {
            completeness = result.cpuBudgetHit ? .truncated : .capped
        }

        let myHealth = snap.heroHealth + snap.heroArmor
        let costsInferred = !live.inferredBaseCostEntities.isEmpty
        // 牌库里有未建模的牌（读取层记成占位杂牌）：抽到它在搜索里是废牌，真实对局里未必 —— 不能当证明。
        // 手里的未建模牌、跳过的过牌由动作生成层报「丢弃」，已经让 `exhaustive` 为 false
        let unmodeledInDeck = root.deck.counts[RDCard.junkPlaceholder.rawValue] > 0
        let verdict: RDLethalVerdict
        if isLethal {
            verdict = deterministic.isEmpty ? .lethalIfDraw : .lethal
        } else if result.exhaustive && !costsInferred && !unmodeledInDeck && !result.cancelled {
            verdict = .provenNotLethal
        } else {
            verdict = .notFound
        }

        return RDAnalysis(
            turn: snap.turn,
            availableMana: root.availableMana,
            isLethal: isLethal,
            verdict: verdict,
            costsInferred: costsInferred,
            lethalDependsOnDraw: isLethal && deterministic.isEmpty,
            maxDamage: result.maxDamage,
            effectiveEnemyHealth: result.effectiveEnemyHealth,
            completeness: completeness,
            tier: isLethal ? chosen?.tier : nil,
            handMarks: handMarks,
            steps: steps,
            totalSteps: total,
            boardMarks: boardMarks,
            nextStepText: steps.first.map {
                text(for: $0, opponentHeroCardId: snap.opponentHeroCardId, cardName: cardName)
            } ?? "",
            drawBranches: branches,
            missingPieces: result.missingPieces.map(cardId),
            missingPiecesIncomplete: result.missingPiecesBudgetExceeded,
            singleTurnInsufficient: verdict == .provenNotLethal,
            boardDanger: snap.deadToBoard || snap.opponentBoardDamage + dangerMargin >= myHealth,
            opponentHasSecrets: snap.opponentSecretCount > 0,
            actionsTaken: snap.optionsPlayedThisTurn,
            handOrder: snap.hand.map { $0.entityId },
            boardSlots: snap.boardSlots.isEmpty ? snap.board.map { $0.entityId } : snap.boardSlots,
            opponentBoardSlots: snap.opponentBoardSlots.isEmpty
                ? snap.opponentBoard.map { $0.entityId } : snap.opponentBoardSlots)
    }

    static func cardId(_ c: RDCard) -> String {
        return RDCards.def(c).ids.first ?? ""
    }

    /// 一行「下一步」。只拼卡名和符号，不写死任何语言的文字（译文只放 .xcstrings）
    static func text(for step: RDStep, opponentHeroCardId: String,
                     cardName: (String) -> String) -> String {
        func targetName(_ t: RDStepTarget) -> String {
            switch t {
            case .friendlyMinion(_, let id), .enemyMinion(_, let id): return cardName(id)
            case .enemyHero: return cardName(opponentHeroCardId)
            }
        }
        switch step.kind {
        case .attack:
            let who = step.attacker.map(targetName) ?? cardName(RDCards.heroId)
            return who + " ⚔ " + (step.target.map(targetName) ?? "")
        case .heroPower:
            return cardName(RDCards.heroPowerId)
        case .playFromHand, .playGenerated:
            var s = step.cardId.map(cardName) ?? ""
            if let t = step.target { s += " → " + targetName(t) }
            if !step.picks.isEmpty { s += " ▸ " + step.picks.map { cardName($0.cardId) }.joined(separator: " / ") }
            return s
        }
    }
}

// MARK: - 沿一条线走一遍，把引擎编号翻回游戏 entity id

/// 引擎打出 / 弹回一张牌时会新编号，游戏里却是同一个实体（手 → 场 → 手 entity id 不变）。
/// 沿线重放，记下「新编号 → 游戏 id」，才能把第 2、3 步的目标落到场上具体的随从上。
/// 复制体是游戏里也还不存在的新实体，落不到 id（nil），打出一张后重算时它就有 id 了。
enum RDLineWalker {

    static func walk(_ actions: [RDAction], root: RDState, zones: [Int: Int],
                     enemyCards: [Int: String] = [:]) -> [RDStep] {
        func target(_ t: RDTarget, _ s: RDState, _ real: [Int: Int]) -> RDStepTarget? {
            switch t {
            case .friendlyMinion(let id):
                let card = s.board.first { $0.entityId == id }?.card
                return .friendlyMinion(entityId: real[id], cardId: card.map(RDHintBuilder.cardId) ?? "")
            case .enemyMinion(let id):
                return .enemyMinion(entityId: id, cardId: enemyCards[id] ?? "")
            case .enemyHero:
                return .enemyHero
            default:
                return nil
            }
        }
        var real = Dictionary(uniqueKeysWithValues: root.hand.map { ($0.entityId, $0.entityId) })
        for m in root.board { real[m.entityId] = m.entityId }
        let rootHand = Set(root.hand.map { $0.entityId })
        var s = root
        var out: [RDStep] = []
        for (i, action) in actions.enumerated() {
            let before = s
            guard let after = try? RDEngine.apply(action, to: s) else { break }
            var step = RDStep(index: i + 1, kind: .heroPower, cardId: nil, handEntityId: nil, zonePosition: nil,
                              attacker: nil, target: nil, picks: [], boardPosition: nil)
            switch action {
            case .heroPower:
                break
            case .attack(let attacker, let defender, let choices):
                step.kind = .attack
                step.attacker = attacker == .friendlyHero ? nil : target(attacker, before, real)
                step.target = target(defender, before, real)
                // 疾速矿锄攻击后抽到的牌
                step.picks = choices.compactMap { c in
                    guard case .pick(let card) = c else { return nil }
                    return RDPick(cardId: RDHintBuilder.cardId(card), isDraw: true)
                }
            case .play(let eid, let identity, let t, let choices, let position):
                let fromRootHand = rootHand.contains(eid)
                step.kind = fromRootHand ? .playFromHand : .playGenerated
                step.cardId = RDHintBuilder.cardId(identity)
                if fromRootHand {
                    step.handEntityId = eid
                    step.zonePosition = zones[eid]
                }
                step.target = target(t, before, real)
                step.boardPosition = position
                step.picks = choices.compactMap { c in
                    guard case .pick(let card) = c else { return nil }
                    return RDPick(cardId: RDHintBuilder.cardId(card), isDraw: !RDCards.sideboardCards.contains(card))
                }
                // 手 → 场：新随从就是这张牌
                if RDCards.def(identity).type == .minion,
                   let new = after.board.first(where: { m in !before.board.contains { $0.entityId == m.entityId } }),
                   let r = real[eid] {
                    real[new.entityId] = r
                }
            }
            // 场 → 手：弹回的随从按上场先后依次进手（手牌满时后上场的被销毁）
            let gone = before.boardIndicesByPlayOrder().map { before.board[$0] }
                .filter { m in !after.board.contains { $0.entityId == m.entityId } }
            let arrived = after.hand.filter { h in !before.hand.contains { $0.entityId == h.entityId } }
            var pool = arrived
            for m in gone {
                // 复制（药水 / 暗影施法者）不会让随从离场，所以离场 + 同名进手只可能是弹回
                guard let k = pool.firstIndex(where: { $0.card == m.card }) else { continue }
                let h = pool.remove(at: k)
                if let r = real[m.entityId] { real[h.entityId] = r }
            }
            out.append(step)
            s = after
        }
        return out
    }

    /// 这条线里打出过的「现在就在手里」的牌（L1 参与牌）
    static func handEntitiesPlayed(_ actions: [RDAction], root: RDState) -> Set<Int> {
        let rootHand = Set(root.hand.map { $0.entityId })
        var out = Set<Int>()
        for a in actions {
            if case .play(let eid, _, _, _, _) = a, rootHand.contains(eid) { out.insert(eid) }
        }
        return out
    }

    /// 线里有随机抽牌（抽牌池里不止一种牌时引擎才要选择；E.T.C. 发现的是边牌，是自己选的）
    /// T2b 第五轮：区分「过程中发生了随机抽牌」和「斩杀依赖抽到的牌」。线里每一步带随机抽牌的（打牌、矿锄攻击），
    /// 把这一步的抽牌换成每一种可能的结果（发现的选择不动），剩下的步骤原样重放：每种结果都能在剩下的步骤里
    /// 打到致死（或这一步结算完已经致死），这次抽牌就不降低确定性。抽到的牌后面没用上、或抽牌发生在致死之后，
    /// 都属于这一类；抽到的牌后面要打（换一张就打不出、编号对不上）就依赖。
    /// 每一步单独换（其余步骤保持原样）；换了之后后面的抽牌对不上的，按依赖算（保守）
    static func dependsOnDraw(_ actions: [RDAction], root: RDState) -> Bool {
        func isDraw(_ c: RDChoice) -> Bool {
            if case .pick(let card) = c { return !RDCards.sideboardCards.contains(card) }
            return false
        }
        func discoverPicks(_ cs: [RDChoice]) -> [RDChoice] { return cs.filter { !isDraw($0) } }
        func lethal(_ t: RDState) -> Bool { return t.opponent.health <= 0 }

        var s = root
        for (i, a) in actions.enumerated() {
            if a.choices.contains(where: isDraw) {
                guard let variants = RDEngine.choiceVariants(for: a, in: s) else { return true }
                for v in variants where discoverPicks(v) == discoverPicks(a.choices) {
                    guard var t = try? RDEngine.apply(a.replacingChoices(v), to: s) else { return true }
                    var k = i + 1
                    while !lethal(t) && k < actions.count {
                        guard let next = try? RDEngine.apply(actions[k], to: t) else { return true }
                        t = next
                        k += 1
                    }
                    if !lethal(t) { return true }
                }
            }
            guard let next = try? RDEngine.apply(a, to: s) else { return true }
            s = next
        }
        return false
    }
}
