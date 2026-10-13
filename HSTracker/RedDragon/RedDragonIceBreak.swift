//
//  RedDragonIceBreak.swift
//  HSTracker
//
//  破冰模式（T8）：对手挂着寒冰屏障时算两回合斩杀 —— 本回合把冰打掉，下回合打掉剩下的血。
//  寒冰屏障的规则只有一条，落在引擎里（`RDEngine.dealDamage` + `RDOpponent.ice`）：搜索、重放校验、公式生成、
//  跟手核对都经过 `RDEngine.apply`，吃的是同一条。这个文件只管引擎之外的事：给根局面标冰、把本回合的终局折成
//  下回合起手、探下回合能打多少、按口径排出结论，以及跟手。束搜索里破冰的那一遍在 RedDragonSearch.swift
//  （`config.iceBreakPass`、`iceBreakPasses`）。
//

import Foundation

/// 破冰搜索自己的闸门和取舍（`RedDragonConfig.iceBreak`）。状态数是可复现的闸门，CPU 只做兜底
struct RDIceBreakConfig {
    /// 整次 `solveIceBreak` 的 CPU 兜底（秒）：破冰搜索 + 准备步 + 下回合探针合计。正常应先撞状态闸门
    /// （最坏约 40 万 + 6 万 + 32 × 6000 ≈ 65 万态）；撞上它时结果随机器负载变，由 `cpuBudgetHit` 标出来
    var cpuBudget: Double = 2.6
    /// 冰打掉之后「为下回合做准备」的展开状态数上限、每层束宽
    var prepMaxStates: Int = 60_000
    var prepBeamWidth: Int = 300
    /// 最浅的破冰出现之后，冰还在的节点再往下展开几层：克制一点的破法（留着阿莱、换别的伤害补最后一下）可能多一两步
    var extraBreakLayers: Int = 2
    /// 最浅的破冰出现之后最多再走几层（更深的破冰 + 准备步）
    var maxPrepLayers: Int = 12
    /// 每个步数留几个候选去探下回合（按便宜分），以及总共最多探几个
    var keepPerDepth: Int = 4
    var maxProbes: Int = 32
    /// 一次下回合探针的闸门（一遍主搜索，不补搜、不找缺件）
    var probeStates: Int = 6_000
    var probeBeamWidth: Int = 300
    var probeCpuBudget: Double = 0.25
}

enum RDIceVerdict: Equatable {
    /// 不适用：对方既没有奥秘也没有免疫，没有冰可破
    case notApplicable
    /// ① 本回合能破冰，下回合可斩（不靠随机抽牌，下回合线重放校验过）
    case lethalNextTurn
    /// ② 本回合能破冰，下回合斩杀没找到：给「下回合伤害 − 剩余血量」最高的线，`shortBy` 是差多少
    case shortNextTurn
    /// ③ 本回合破不了冰（没找到不靠随机抽牌的破法）
    case cannotBreak
}

/// 一条本回合的线（终局冰已打掉）和它的下回合
struct RDIceCandidate {
    var line: RedDragonLine
    /// 破冰后对方剩余血量（血 + 甲）
    var remaining: Int
    /// 下回合起手（`RDIceBreak.nextTurn(终局)`）
    var nextTurnRoot: RDState
    /// 从 `nextTurnRoot` 出发伤害最高的线：已在它上面逐步重放过，伤害 = `nextTurnDamage`。探不出能打伤害的线时 nil
    var nextTurnLine: RedDragonLine?
    var nextTurnDamage: Int
    /// `nextTurnLine` 打到第几步对方就死了（下回合不可斩时 nil）
    var nextTurnLethalSteps: Int?
    /// 进候选的先后（只用来打破平局）
    var order = 0

    var steps: Int { return line.actions.count }
    /// 下回合伤害超出剩余血量多少（负 = 还差多少）
    var margin: Int { return nextTurnDamage - remaining }
}

struct RDIceBreakResult {
    var verdict: RDIceVerdict
    /// 标好冰的根局面。`line` 从它重放；公式（`RDFormulaBuilder.formula`）、逐步提示（`RDLineWalker.walk`）
    /// 都要用它当根，不要用没标冰的那个（那样重放出来对方会被打死）
    var root: RDState
    /// 进来时冰就已经打掉了（对方免疫）：`line` 只有准备步，可以是 0 步
    var alreadyBroken = false
    /// 本回合的线：破冰 + 之后为下回合做的准备。① ② 时非 nil（可以是 0 步），③ / 不适用时 nil
    var line: RedDragonLine?
    /// 冰是 `line` 的第几步打掉的（从 1 起）。`alreadyBroken` 或没有线时 0
    var breakStep = 0
    /// 破冰后对方剩余血量（血 + 甲）
    var remaining = 0
    /// `line` 的终局过一个回合（法力 +1、留场随从不算攻击、对方不再免疫），和从它出发的下回合线
    var nextTurnRoot: RDState?
    var nextTurnLine: RedDragonLine?
    /// 下回合不靠随机抽牌能打的伤害（`nextTurnLine` 的，重放校验过）
    var nextTurnDamage = 0
    /// ① 时：`nextTurnLine` 的前几步就够斩杀
    var nextTurnLethalSteps: Int?
    /// ② 时还差多少（剩余血量 − 下回合伤害）；其余为 0
    var shortBy = 0
    /// 被 `config.cancellation` 取消：结果不完整，调用方丢掉
    var cancelled = false
    /// 撞了 CPU 兜底（结果随机器负载变）
    var cpuBudgetHit = false
    /// ③ 时：不靠随机抽牌的打法穷举完了，按本模型确实破不了（否则只是没搜到）
    var exhaustive = false
    var cpuTime = 0.0
    /// 破冰搜索 + 准备步 + 探针合计
    var statesExpanded = 0
    /// 探过的全部候选，按口径排好（第一条就是 `line`）。给测试和调参看
    var candidates: [RDIceCandidate] = []
}

enum RDIceBreak {

    /// 给读取层读出来的根局面标上冰的状态。对方已经免疫 = 冰打掉了（本回合剩下的只是准备）；
    /// 不免疫、有奥秘 = 当它是寒冰屏障；两样都没有 = 不适用（nil）
    static func armed(_ root: RDState) -> RDState? {
        var s = root
        if root.opponent.immune {
            s.opponent.ice = .broken
            return s
        }
        guard root.opponent.secretCount > 0 else { return nil }
        s.opponent.ice = .armed
        return s
    }

    /// 本回合的终局（冰已打掉）当下回合起手（口径 3）：`RDSetup.nextTurn` 的那些（法力 +1 封顶 10、只在本回合有效的
    /// 费用和资源清掉），再加：对方不再免疫、血量就是剩余血量，回到平常规则；留在场上的随从照样占格子、光环照旧，
    /// 但**不算下回合的攻击伤害**（按不能攻击处理）。英雄武器和英雄技能照算，下回合的抽牌不算
    static func nextTurn(_ end: RDState) -> RDState {
        var t = RDSetup.nextTurn(end)
        t.opponent.immune = false
        t.opponent.ice = nil
        for i in t.board.indices { t.board[i].summoningSick = true }
        return t
    }

    /// 冰已打掉的局面在束里的分：共识分 = 把它当下回合起手的共识分 − 10 × 剩余血量（共识分里伤害的权重是 10，
    /// 两项相抵就是「下回合乐观伤害 − 剩余血量」）；蓄力分看本回合还剩多少操作空间
    static func evaluate(_ s: RDState) -> RedDragonSearch.RDEval {
        var e = RedDragonSearch.evaluate(nextTurn(s))
        e.greedy -= 10 * s.opponent.effectiveHealth
        e.builder = RedDragonSearch.evaluate(s).builder
        return e
    }

    /// 一条下回合线在下回合起手上逐步重放：全走得通才算数，返回它实际打出的伤害和打到第几步对方死
    static func evidence(_ line: RedDragonLine, on next: RDState,
                         options: RDOptions = .search) -> (damage: Int, lethalSteps: Int?)? {
        var s = next
        var lethalSteps: Int?
        for (i, a) in line.actions.enumerated() {
            guard let t = try? RDEngine.apply(a, to: s, options: options) else { return nil }
            s = t
            if lethalSteps == nil && s.opponent.health <= 0 { lethalSteps = i + 1 }
        }
        return (s.damageDealt, lethalSteps)
    }

    struct Probe {
        var damage = 0
        var line: RedDragonLine?
        var lethalSteps: Int?
        var states = 0
        var cpuBudgetHit = false
        var cancelled = false
    }

    /// 下回合从 `next` 起手、不靠随机抽牌能打多少：对方血量放到够不着，小预算跑一遍斩杀搜索量伤害最高的线，
    /// 再把那条线拿回真实的 `next`（对方是剩余血量）上逐步重放。重放不过或伤害对不上的不算（伤害记 0）
    static func probe(_ next: RDState, config base: RedDragonConfig, deadline: Double) -> Probe {
        var dummy = next
        dummy.opponent.health = 999
        var c = RedDragonConfig()
        c.weights = base.weights
        c.maxStatesExpanded = base.iceBreak.probeStates
        c.cpuBudget = max(0, min(base.iceBreak.probeCpuBudget, deadline - RedDragonSearch.threadCPUTime()))
        c.beamWidth = base.iceBreak.probeBeamWidth
        c.samplingPassWidth = nil
        c.boardOrderPass = nil
        c.enableMissingPieces = false
        c.deterministicOnly = true
        c.cancellation = base.cancellation
        let r = RedDragonSearch.solve(dummy, config: c)
        var out = Probe(states: r.statesExpanded, cpuBudgetHit: r.cpuBudgetHit, cancelled: r.cancelled)
        guard !r.cancelled, let line = r.chosenLine, line.damage > 0,
              let ev = evidence(line, on: next, options: c.options), ev.damage == line.damage else { return out }
        out.damage = ev.damage
        out.line = line
        out.lethalSteps = ev.lethalSteps
        return out
    }

    /// 口径 4 / 5 的先后：下回合可斩的在前；可斩的里面，超出剩余血量按 8（一次阿莱）分档、档高的在前，同档本回合
    /// 步数少的在前，再同就超得多的在前；都不可斩时差得少的在前、再按步数少
    static func better(_ a: RDIceCandidate, _ b: RDIceCandidate) -> Bool {
        let (x, y) = (a.margin >= 0, b.margin >= 0)
        if x != y { return x }
        if x {
            if a.margin / 8 != b.margin / 8 { return a.margin / 8 > b.margin / 8 }
            if a.steps != b.steps { return a.steps < b.steps }
            if a.margin != b.margin { return a.margin > b.margin }
        } else {
            if a.margin != b.margin { return a.margin > b.margin }
            if a.steps != b.steps { return a.steps < b.steps }
        }
        if a.line.difficulty != b.line.difficulty { return a.line.difficulty < b.line.difficulty }
        return a.order < b.order
    }

    struct Followed {
        /// 接到真实局面上的结论：`root` 是真实局面（标好冰），`line` 是剩下没打的步骤，下回合线已换成真实编号重放过
        var result: RDIceBreakResult
        /// 真实局面对上的是原来那条线的第几步之后（0 = 一步没走）
        var stepsTaken: Int
    }

    /// 跟手：用户照着 `plan.line` 打了几步（或一步没打）之后的真实局面 `real`（读取层读出来的，不用先标冰）还在线上时，
    /// 不重算，把结论接过去。对不上、剩下的步骤在真实局面上走不通、下回合线在真实终局上重放不过或结论变了，都返回 nil，
    /// 调用方照常重算（`solveIceBreak`）。`tolerant` 同 `RDContinuation.advance`（真实局面多抽了牌也算对上）
    static func follow(_ plan: RDIceBreakResult, onto real: RDState, tolerant: Bool = false) -> Followed? {
        guard plan.verdict == .lethalNextTurn || plan.verdict == .shortNextTurn, let line = plan.line,
              let live = armed(real),
              let resumed = RDContinuation.resume(line, from: plan.root, onto: live, tolerant: tolerant,
                                                  iceBreak: true),
              let end = try? RDReplay.run(resumed.line.actions, from: resumed.root).finalState,
              end.opponent.ice == .broken else { return nil }
        var out = plan
        out.root = resumed.root
        out.line = resumed.line
        out.alreadyBroken = resumed.root.opponent.ice == .broken
        out.breakStep = max(0, plan.breakStep - resumed.stepsTaken)
        out.remaining = end.opponent.effectiveHealth
        out.candidates = []
        let next = nextTurn(end)
        out.nextTurnRoot = next
        if var nextLine = plan.nextTurnLine {
            nextLine.actions = nextLine.actions.map(resumed.translate)
            guard let ev = evidence(nextLine, on: next) else { return nil }
            nextLine.damage = ev.damage
            out.nextTurnLine = nextLine
            out.nextTurnDamage = ev.damage
            out.nextTurnLethalSteps = ev.lethalSteps
        } else {
            out.nextTurnDamage = 0
            out.nextTurnLethalSteps = nil
        }
        // 结论不能在跟手时悄悄变：可斩的还得可斩，不可斩的差额照真实终局重算
        let lethal = out.nextTurnDamage >= out.remaining
        guard lethal == (plan.verdict == .lethalNextTurn) else { return nil }
        out.shortBy = lethal ? 0 : out.remaining - out.nextTurnDamage
        return Followed(result: out, stepsTaken: resumed.stepsTaken)
    }
}

extension RedDragonSearch {

    /// 破冰模式的入口（T8 口径 1–5）。`root` 是读取层读出来的局面（不用先标冰）；同步、单线程，取消走
    /// `config.cancellation`（和斩杀搜索同一个标记：搜索每展开一个节点、每个探针之前和探针里面都看）。
    ///
    /// 三步：① 破冰搜索（`iceBreakPasses`）：不靠随机抽牌把冰打掉，冰打掉之后接着展开准备步，每个步数留几个终局；
    /// ② 每个终局折成下回合起手（`RDIceBreak.nextTurn`），探下回合不靠随机抽牌能打多少（`RDIceBreak.probe`）；
    /// ③ 按口径 4 / 5 排（`RDIceBreak.better`）。给出去的本回合线和下回合线都是引擎重放校验过的；
    /// 「下回合可斩」只在下回合线真的在下回合起手上把对方打死时才说
    static func solveIceBreak(_ root: RDState, config: RedDragonConfig = RedDragonConfig()) -> RDIceBreakResult {
        let start = threadCPUTime()
        let deadline = start + config.iceBreak.cpuBudget
        guard let armed = RDIceBreak.armed(root) else {
            return RDIceBreakResult(verdict: .notApplicable, root: root)
        }
        var out = RDIceBreakResult(verdict: .cannotBreak, root: armed)
        out.alreadyBroken = armed.opponent.ice == .broken
        func finish() -> RDIceBreakResult {
            out.cpuTime = threadCPUTime() - start
            return out
        }
        func isCancelled() -> Bool { return config.cancellation?.isCancelled == true }

        let run = iceBreakPasses(armed, config: config, deadline: deadline)
        out.statesExpanded = run.statesExpanded
        out.cpuBudgetHit = run.cpuBudgetHit
        out.exhaustive = run.exhaustive
        if run.cancelled || isCancelled() {
            out.cancelled = true
            return finish()
        }

        // 候选 = 搜索收下的终局；进来时冰已经打掉的，再加上「什么都不打」
        var lines = run.iceLines
        if out.alreadyBroken {
            let comps = RDDifficulty.components(for: [], sideboardCardsTaken: 0, weights: config.weights)
            lines.insert(RedDragonLine(actions: [], damage: armed.damageDealt, difficulty: comps.score,
                                       components: comps, tier: RDDifficulty.tier(comps.score),
                                       branchKey: [], truncated: false), at: 0)
        }
        // 探的次序：各步数的第 1 名（步数少的在前）→ 各步数的第 2 名 → …，够 `maxProbes` 个为止
        var byDepth: [Int: [RedDragonLine]] = [:]
        for l in lines { byDepth[l.actions.count, default: []].append(l) }
        let depths = byDepth.keys.sorted()
        var order: [RedDragonLine] = []
        var rank = 0
        while order.count < lines.count {
            for d in depths where rank < (byDepth[d]?.count ?? 0) {
                if let l = byDepth[d]?[rank] { order.append(l) }
            }
            rank += 1
        }
        if order.count > config.iceBreak.maxProbes { order.removeSubrange(config.iceBreak.maxProbes...) }

        // 下回合起手相同的终局（只差本回合剩的法力之类）共用一次探针：编号可能不同，线要在各自的起手上再重放一遍
        var cache: [UInt64: RDIceBreak.Probe] = [:]
        var candidates: [RDIceCandidate] = []
        for line in order {
            if isCancelled() {
                out.cancelled = true
                return finish()
            }
            if threadCPUTime() > deadline {
                out.cpuBudgetHit = true
                break
            }
            guard let end = try? RDReplay.run(line.actions, from: armed, options: config.options).finalState,
                  end.opponent.ice == .broken else { continue }
            let next = RDIceBreak.nextTurn(end)
            let key = next.canonicalHash()
            var probe: RDIceBreak.Probe
            if let hit = cache[key], let known = hit.line, let ev = RDIceBreak.evidence(known, on: next),
               ev.damage == hit.damage {
                probe = hit
                probe.lethalSteps = ev.lethalSteps
            } else {
                probe = RDIceBreak.probe(next, config: config, deadline: deadline)
                out.statesExpanded += probe.states
                if probe.cancelled {
                    out.cancelled = true
                    return finish()
                }
                if probe.cpuBudgetHit { out.cpuBudgetHit = true }
                cache[key] = probe
            }
            candidates.append(RDIceCandidate(line: line, remaining: end.opponent.effectiveHealth,
                                             nextTurnRoot: next, nextTurnLine: probe.line,
                                             nextTurnDamage: probe.damage, nextTurnLethalSteps: probe.lethalSteps,
                                             order: candidates.count))
        }
        candidates.sort(by: RDIceBreak.better)
        out.candidates = candidates
        // 没有候选 = 本回合破不了冰（③）
        guard let best = candidates.first else { return finish() }

        out.line = best.line
        out.remaining = best.remaining
        out.nextTurnRoot = best.nextTurnRoot
        out.nextTurnLine = best.nextTurnLine
        out.nextTurnDamage = best.nextTurnDamage
        out.nextTurnLethalSteps = best.nextTurnLethalSteps
        if best.margin >= 0 {
            out.verdict = .lethalNextTurn
        } else {
            out.verdict = .shortNextTurn
            out.shortBy = -best.margin
        }
        // 冰是第几步打掉的
        if !out.alreadyBroken {
            var s = armed
            for (i, a) in best.line.actions.enumerated() {
                guard let t = try? RDEngine.apply(a, to: s, options: config.options) else { break }
                s = t
                if s.opponent.ice == .broken {
                    out.breakStep = i + 1
                    break
                }
            }
        }
        return finish()
    }
}
