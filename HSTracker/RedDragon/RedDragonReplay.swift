//
//  RedDragonReplay.swift
//  HSTracker
//
//  路径重放校验（P0）。任何返回给调用方的序列，先由同一套规则引擎从初始状态重放一遍，
//  费用 / 格子 / 手牌数 / 目标合法性全过才允许返回 —— 宁可不给路径，也不给打不出来的路径。
//

import Foundation

struct RDReplayFailure: Error {
    var stepIndex: Int
    var reason: RDIllegal
}

enum RDReplay {

    struct Outcome {
        var finalState: RDState
        /// 每一步结算完剩余的可用法力（含临时水晶），给公式表逐 token 对账用
        var manaAfterEachStep: [Int]
        var damage: Int
    }

    static func run(_ actions: [RDAction], from state: RDState,
                    options: RDOptions = .search) throws -> Outcome {
        var s = state
        var mana: [Int] = []
        mana.reserveCapacity(actions.count)
        for (i, action) in actions.enumerated() {
            do {
                s = try RDEngine.apply(action, to: s, options: options)
            } catch let e as RDIllegal {
                throw RDReplayFailure(stepIndex: i, reason: e)
            }
            mana.append(s.availableMana)
        }
        return Outcome(finalState: s, manaAfterEachStep: mana, damage: s.damageDealt)
    }

    /// 校验成功返回终局状态，失败返回 nil（调用方据此丢掉这条线）
    static func validate(_ actions: [RDAction], from state: RDState,
                         expectedDamage: Int, options: RDOptions = .search) -> RDState? {
        guard let outcome = try? run(actions, from: state, options: options) else { return nil }
        guard outcome.damage == expectedDamage else { return nil }
        return outcome.finalState
    }
}

/// 跟手（T3）：用户照着屏上的斩杀线打了几步，新局面就是引擎推出来的那个局面时，不重新搜索，
/// 把线剩下的部分换成真实编号、在真实局面上重放校验一遍接着用。重放不过、对不上、剩下的要靠随机抽牌，都返回 nil，
/// 调用方照常搜索
enum RDContinuation {

    struct Resumed {
        var line: RedDragonLine
        /// 真实局面对上的是线的第几步之后（0 = 一步没走）
        var stepsTaken: Int
        /// `line` 是从这个局面重放校验的：真实局面，只是新编号的起点换成了推演局面的
        var root: RDState
    }

    /// 一组候选线（各带自己的根局面）都试着接到同一个真实局面上，通过的线共用一个根局面（新编号起点取各自
    /// 起点的最大值，重放校验也在它上面做），可以一起交给分析器。顺序保持候选的顺序（屏上那条在前）
    static func resumeAll(_ candidates: [(root: RDState, line: RedDragonLine)], onto real: RDState) -> [Resumed] {
        let first = candidates.compactMap { resume($0.line, from: $0.root, onto: real) }
        guard let common = first.map({ $0.root.nextEntityId }).max() else { return [] }
        guard first.contains(where: { $0.root.nextEntityId != common }) else { return first }
        return candidates.compactMap { resume($0.line, from: $0.root, onto: real, startId: common) }
    }

    /// `startId`：真实局面新编号的起点，nil = 用推演局面的。比推演局面的大时，线里引擎新造的编号整体后移
    static func resume(_ line: RedDragonLine, from root: RDState, onto real: RDState,
                       startId: Int? = nil) -> Resumed? {
        guard !line.truncated, !line.actions.isEmpty else { return nil }
        var predicted = root
        for k in 0..<line.actions.count {
            if k > 0 {
                guard let next = try? RDEngine.apply(line.actions[k - 1], to: predicted) else { return nil }
                predicted = next
            }
            guard let map = correspondence(predicted, real) else { continue }
            // 线后面的步骤会用到引擎新造的编号（从 `predicted.nextEntityId` 起）。真实局面从同一个号起编
            // （或整体后移到 `startId`），编号就对得上；真实实体的编号必须都比起点小，否则会撞号
            let base = predicted.nextEntityId
            let next = startId ?? base
            guard next >= base else { return nil }
            let realIds = real.hand.map { $0.entityId } + real.board.map { $0.entityId }
                + real.opponent.board.map { $0.entityId }
            guard realIds.allSatisfy({ $0 < next }) else { return nil }
            var start = real
            start.nextEntityId = next
            let rest = line.actions[k...].map { translate($0, map, generatedFrom: base, shift: next - base) }
            guard let outcome = try? RDReplay.run(rest, from: start),
                  outcome.finalState.opponent.health <= 0,
                  !RDLineWalker.dependsOnDraw(rest, root: start) else { return nil }
            let taken = start.sideboard.count - outcome.finalState.sideboard.count
            let comps = RDDifficulty.components(for: rest, sideboardCardsTaken: taken)
            let resumed = RedDragonLine(actions: rest, damage: outcome.damage, difficulty: comps.score,
                                        components: comps, tier: RDDifficulty.tier(comps.score),
                                        branchKey: [], truncated: false)
            return Resumed(line: resumed, stepsTaken: k, root: start)
        }
        return nil
    }

    /// 接着用的线包成搜索结果：`lines` 是 `resumeAll` 的结果（同一个根局面），全部进 `lethalLines`，
    /// 分析器据此区分必打 / 可选；展示的是第一条
    static func result(_ lines: [RedDragonLine], root: RDState) -> RedDragonResult {
        precondition(!lines.isEmpty)
        return RedDragonResult(maxDamage: lines.map { $0.damage }.max() ?? 0,
                               effectiveEnemyHealth: root.opponent.effectiveHealth,
                               isLethal: true, chosenLine: lines[0], lethalLines: lines, branches: [],
                               missingPieces: [], missingPiecesBudgetExceeded: false,
                               termination: .reachedUpperBound, cpuTime: 0, statesExpanded: 0,
                               depthReached: lines.map { $0.actions.count }.max() ?? 0)
    }

    /// 推出来的局面就是真实局面（用户照着线打了这几步）时给出编号对应（推出来的 → 真实的）。
    /// 手牌按牌比（与顺序无关），场面和敌方随从按位置比。手牌的费用附魔链按求值结果比：读取层给根局面手牌记的是
    /// 「设为当前底费」，引擎一路推下来的是附魔序列，两者以后再挂附魔时结果相同（链是逐个折叠的）。
    /// 这里只负责「对上了、编号怎么换」，线能不能打由调用方在真实局面上重放决定
    static func correspondence(_ p: RDState, _ r: RDState) -> [Int: Int]? {
        guard p.mana == r.mana, p.tempMana == r.tempMana, p.maxMana == r.maxMana,
              p.cardsPlayedThisTurn == r.cardsPlayedThisTurn, p.spellDamage == r.spellDamage,
              p.heroAttackedThisTurn == r.heroAttackedThisTurn, p.heroPowerUsed == r.heroPowerUsed,
              p.heroFrozen == r.heroFrozen, p.luckyCometCharges == r.luckyCometCharges,
              p.layers == r.layers, p.truncatedDraws == 0,
              p.sideboard.map({ $0.rawValue }).sorted() == r.sideboard.map({ $0.rawValue }).sorted(),
              p.deck.counts == r.deck.counts,
              p.secretsInPlay.map({ $0.rawValue }).sorted() == r.secretsInPlay.map({ $0.rawValue }).sorted(),
              p.boardLimit == r.boardLimit, p.handLimit == r.handLimit,
              p.opponent.health == r.opponent.health, p.opponent.armor == r.opponent.armor,
              p.opponent.immune == r.opponent.immune, p.opponent.secretCount == r.opponent.secretCount,
              p.weapon?.attack == r.weapon?.attack, p.weapon?.durability == r.weapon?.durability,
              p.weapon?.drawOnHeroAttack == r.weapon?.drawOnHeroAttack,
              p.hand.count == r.hand.count, p.board.count == r.board.count,
              p.opponent.board.count == r.opponent.board.count else { return nil }
        var map: [Int: Int] = [:]
        for (a, b) in zip(p.opponent.board, r.opponent.board) {
            guard a.attack == b.attack, a.health == b.health, a.taunt == b.taunt,
                  a.divineShield == b.divineShield, a.immune == b.immune, a.stealth == b.stealth,
                  a.damaged == b.damaged else { return nil }
            map[a.entityId] = b.entityId
        }
        let pOrder = p.boardIndicesByPlayOrder()
        let rOrder = r.boardIndicesByPlayOrder()
        guard pOrder == rOrder else { return nil }
        for (a, b) in zip(p.board, r.board) {
            // 场上费用附魔不影响后续动作：舞动的 1 费在打出时失效，复制附魔回手时清除。
            // 复制体的身材仍须一致，剩余动作再用真实局面重放。
            guard a.card == b.card, a.attack == b.attack, a.health == b.health, a.maxHealth == b.maxHealth,
                  a.statsSetTo1x1 == b.statsSetTo1x1, a.silenced == b.silenced,
                  a.summoningSick == b.summoningSick, a.attacksThisTurn == b.attacksThisTurn else { return nil }
            map[a.entityId] = b.entityId
        }
        var unused = Array(r.hand.indices)
        for a in p.hand {
            guard let j = unused.firstIndex(where: { sameHandCard(a, r.hand[$0]) }) else { return nil }
            map[a.entityId] = r.hand[unused[j]].entityId
            unused.remove(at: j)
        }
        return map
    }

    private static func sameHandCard(_ a: RDHandCard, _ b: RDHandCard) -> Bool {
        guard a.card == b.card, a.pool.isEmpty, b.pool.isEmpty, a.isShadowOfDemise == b.isShadowOfDemise,
              a.statsOverride == b.statsOverride, a.printedCostOverride == b.printedCostOverride,
              fold(a.enchants, a.card) == fold(b.enchants, b.card) else { return false }
        return !RDCards.hasQuickdraw(a.card) || a.enteredHandThisTurn == b.enteredHandThisTurn
    }

    /// 附魔链求值，和 `RDState.effectiveBaseCost` 一样最后截 0。本牌组以后再挂的只有「设为」和减费，
    /// 截 0 后相同的两条链以后也相同；打出后手牌费用附魔清除，再回手重新计费。
    private static func fold(_ chain: [RDEnchant], _ card: RDCard) -> Int {
        var value = RDCards.def(card).printedCost
        for e in chain {
            switch e {
            case .set(let v): value = v
            case .delta(let v): value += v
            }
        }
        return max(0, value)
    }

    /// `map`：推演局面里已有实体的编号 → 真实编号；`generatedFrom` 起的是线里引擎新造的，整体加 `shift`
    static func translate(_ a: RDAction, _ map: [Int: Int], generatedFrom base: Int = .max,
                          shift: Int = 0) -> RDAction {
        func id(_ x: Int) -> Int { return map[x] ?? (x >= base ? x + shift : x) }
        func target(_ t: RDTarget) -> RDTarget {
            switch t {
            case .friendlyMinion(let x): return .friendlyMinion(id(x))
            case .enemyMinion(let x): return .enemyMinion(id(x))
            default: return t
            }
        }
        switch a {
        case .play(let e, let identity, let t, let c, let p):
            return .play(entityId: id(e), identity: identity, target: target(t), choices: c, position: p)
        case .attack(let x, let y, let c):
            return .attack(attacker: target(x), defender: target(y), choices: c)
        case .heroPower:
            return a
        }
    }
}
