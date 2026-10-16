//
//  RedDragonIceBreak.swift
//  HSTracker
//
//  破冰模式（T8）：对手挂着寒冰屏障时算两回合斩杀 —— 本回合把冰打掉，下回合打掉剩下的血。
//  下回合的伤害只信手里的牌（口径 15，`reliable`），手里阿莱多的破法排在前面（`better`），card-model J3。
//
//  寒冰屏障的规则只有一条，落在引擎里（`RDEngine.dealDamage` + `RDOpponent.ice`）：敌方英雄受到的**某一次**伤害
//  ≥ 当前血量 + 护甲时，这一次整个不生效、对方本回合免疫、奥秘少一个；不致命的伤害照常扣。搜索、重放校验、
//  公式生成、跟手核对都经过 `RDEngine.apply`，吃的是同一条。两个推论，这个文件里的取舍都从它们来：
//    · 对方这回合掉不到 1 血以下。所以最好的破法不是打得多，而是先用不致命的伤害把血压到最低、最后一下才触发
//      （对方 10 血：一下打 10 被免疫，剩 10；先打 9 再打 1，剩 1）。「破冰后剩余血量」= 触发那一下之前的血量 + 护甲。
//    · 每一次伤害单独判。鲨鱼之灵在场时阿莱克丝塔萨的战吼是**两次 8**，不是一次 16：对方 16 血，第一个 8 照扣、
//      第二个 8 触发，剩 8；对方 9 血，剩 1；对方 17 血，两个 8 都照扣、冰还在，剩 1 血要另补一下才触发。
//
//  这个文件只管引擎之外的事：给根局面标冰、把本回合的终局折成下回合起手、探下回合能打多少、按口径排出结论，
//  以及跟手。束搜索里破冰的那一遍在 RedDragonSearch.swift（`config.iceBreakPass`、`iceBreakPasses`）。
//

import Foundation

/// 破冰搜索自己的闸门和取舍（`RedDragonConfig.iceBreak`）。状态数是可复现的闸门，CPU 只做兜底
public struct RDIceBreakConfig {
    /// 全部取默认值；public 是为了能当 public 函数的默认参数
    public init() {}

    /// 整次 `solveIceBreak` 的 CPU 兜底（秒）：破冰搜索 + 准备步 + 下回合探针合计。正常应先撞状态闸门
    /// （破不了：压血连补搜 40 万态，没有准备步和探针；破得了：压血 20 万 + 准备步 12 万 + 探针 64 × 6000，
    /// 丢过随机抽牌的分支时再加盲抽补搜和探针的第二遍）。各闸门同时用满时会超过它，那时由它截断：
    /// 结果随机器负载变，由 `cpuBudgetHit` 标出来
    var cpuBudget: Double = 2.6
    /// 其中留给下回合探针的（秒）：破冰搜索 + 准备步最多用到 `cpuBudget − probeReserve`，搜索把自己那份用光时探针
    /// 仍有这么多。探针的份额也用完时，已经重放校验过的本回合线照留（`RDIceCandidate.probed == false`），不会因为
    /// 探针没做就说成破不了。测试里给负数 = 搜索不受 `cpuBudget` 限制，用来复现「搜索做完、探针一个没做」
    var probeReserve: Double = 0.3
    /// 冰打掉之后「为下回合做准备」的展开状态数上限（各档合计）、每档每层的束宽。「一档」= 破冰后剩余血量相同的
    /// 那些破法；准备步按剩余血量从低到高一档一档展开，每档最多用掉还剩的状态数的一半（最后一档拿走全部剩下的）。
    /// 束宽 600：准备步的打分（下回合的乐观估计）认不出「先换掉随从腾格子、再铺下回合的件」这种要走六七步的准备，
    /// 300 宽时束会被几步就把法力花光的局面占满（fixture 扫表里有 1 行因此同剩余、下回合低了四档）
    var prepMaxStates: Int = 120_000
    var prepBeamWidth: Int = 600
    /// 冰还在的那一半**不因为已经有破冰线就停**（口径 12：浅的破法往往剩得多，压得更低的要多走几步），一直走到
    /// 束走空或状态闸门（`RedDragonConfig.maxStatesExpanded`）。唯一的提前收口：出现了剩余 1 的破冰（不可能更低了）
    /// 之后只再走这么多层 —— 克制一点的同档破法（留着阿莱、换别的伤害补最后一下）可能多一两步
    var extraBreakLayers: Int = 2
    /// 每一档破冰之后最多走几步准备
    var maxPrepLayers: Int = 12
    /// 每一档、每个步数（这条线本回合一共几步，含破冰之后的准备步）留几个候选去探下回合，按便宜分取。
    /// 分步数留，是因为便宜分只是下回合的乐观估计：混在一起取，深处估得高的会把浅的整批挤掉，
    /// 而「同档取步数少的」正要拿浅的来比
    var keepPerDepth: Int = 4
    /// 下回合探针总共最多几个，以及怎么分（`RDIceBreak.scheduleProbes`，每一轮都从剩余最低的一档往上走）：
    /// 第一轮每档先探 `firstProbesPerRemaining` 条（每一档都先轮到一次），第二轮每档补到 `probesPerRemaining` 条，
    /// 名额还有剩再把各档没探的补上。
    /// 64：最低的一档探过斩不了时（它要先花掉一份名额），再上一档还够把同档的 8 分档和步数比出来 —— fixture 扫表的
    /// 23 个破得了的局面上，64 个名额选中的线和「全部探完」逐行相同；48 个时有 1 行同剩余同档、多走 2 步，
    /// 32 个时 2 行。探针便宜（每个最多 `probeStates` 态），多这些名额耗时看不出来
    var maxProbes: Int = 64
    var firstProbesPerRemaining: Int = 2
    var probesPerRemaining: Int = 8
    /// 一次下回合探针的闸门（一遍主搜索，不补搜、不找缺件）
    var probeStates: Int = 6_000
    var probeBeamWidth: Int = 300
    var probeCpuBudget: Double = 0.25
    /// 盲抽补搜（`RedDragonConfig.blindDraws`：随机抽牌照常发生、抽到的牌不能用）拿主搜索束宽 / 状态数的多少。
    /// 只在主搜索丢过随机抽牌的分支时才跑
    var blindShare: Double = 0.25
    /// 盲抽补搜找到的线另有这么多探针名额（排在主搜索的线之后，不挤占 `maxProbes`）
    var maxBlindProbes: Int = 8
    /// 「稳」的门槛（口径 14）：下回合伤害比破冰后剩余血量多出至少这么多，才算稳斩。稳的排在不稳的前面
    /// （`RDIceBreak.better`），探针只在探出稳的线之后才不再探剩得更多的档（`RDIceBreak.scheduleProbes`）。
    /// 8 = 一次阿莱，和同剩余时的分档同一个单位。设成 0 = 可斩的都算稳，排序回到口径 11 原样
    var safeMargin: Int = 8
}

public enum RDIceVerdict: Equatable {
    /// 不适用：对方既没有奥秘也没有免疫，没有冰可破
    case notApplicable
    /// ① 本回合能破冰，下回合可斩（不靠随机抽牌，下回合线重放校验过）
    case lethalNextTurn
    /// ② 本回合能破冰，下回合斩杀没找到：给差得最少（「剩余血量 − 下回合伤害」最小）的线，同差取剩余血量低的；
    /// `shortBy` 是差多少
    case shortNextTurn
    /// ③ 本回合破不了冰（没找到不靠随机抽牌的破法）
    case cannotBreak
}

/// 一条本回合的线（终局冰已打掉）和它的下回合
public struct RDIceCandidate {
    public var line: RedDragonLine
    /// 破冰后对方剩余血量（血 + 甲）
    public var remaining: Int
    /// 下回合起手（`RDIceBreak.nextTurn(终局)`，场上的随从还在）
    var nextTurnRoot: RDState
    /// 下回合起手手里有几张阿莱（口径 15，`RDIceBreak.dragons`）。不用探针，终局就定了
    public var dragons = 0
    /// `nextTurnLine` 是在哪一种下回合起手上量的（口径 15）：true = 对方回合把我方场面清光了（`RDIceBreak.cleared`），
    /// false = 场面原样留着（`nextTurnRoot`）。两种里伤害低的那种
    var nextTurnBoardCleared = false
    /// 从 `nextTurnLineRoot` 出发伤害最高的线：已在它上面逐步重放过，伤害 = `nextTurnDamage`。探不出能打伤害的线时 nil
    var nextTurnLine: RedDragonLine?
    /// 下回合靠得住的伤害（口径 15）：清场、不清场两种起手里打得少的那个
    public var nextTurnDamage: Int
    /// `nextTurnLine` 打到第几步对方就死了（下回合不可斩时 nil）
    var nextTurnLethalSteps: Int?
    /// 下回合探过没有。false = 轮到它之前探针的预算用完了（CPU 兜底 / `maxProbes`）：本回合线照样是重放校验过的，
    /// 只是下回合伤害不知道（记 0）
    var probed = true
    /// 进候选的先后（只用来打破平局）
    public var order = 0

    public var steps: Int { return line.actions.count }
    /// 下回合伤害超出剩余血量多少（负 = 还差多少）
    public var margin: Int { return nextTurnDamage - remaining }
    /// `nextTurnLine` 从哪个局面重放
    var nextTurnLineRoot: RDState { return nextTurnBoardCleared ? RDIceBreak.cleared(nextTurnRoot) : nextTurnRoot }
}

public struct RDIceBreakResult {
    public var verdict: RDIceVerdict
    /// 标好冰的根局面。`line` 从它重放；公式（`RDFormulaBuilder.formula`）、逐步提示（`RDLineWalker.walk`）
    /// 都要用它当根，不要用没标冰的那个（那样重放出来对方会被打死）
    public var root: RDState
    /// 进来时冰就已经打掉了（对方免疫）：`line` 只有准备步，可以是 0 步
    var alreadyBroken = false
    /// 本回合的线：破冰 + 之后为下回合做的准备。① ② 时非 nil（可以是 0 步），③ / 不适用时 nil
    public var line: RedDragonLine?
    /// 冰是 `line` 的第几步打掉的（从 1 起）。`alreadyBroken` 或没有线时 0
    public var breakStep = 0
    /// 破冰后对方剩余血量（血 + 甲）
    public var remaining = 0
    /// `line` 的终局过一个回合（法力 +1、留场随从不算攻击、对方不再免疫），和下回合线。
    /// 下回合线在 `nextTurnBoardCleared` 为真时从清场后的起手（`RDIceBreak.cleared(nextTurnRoot)`）重放
    var nextTurnRoot: RDState?
    var nextTurnLine: RedDragonLine?
    var nextTurnBoardCleared = false
    /// 下回合起手手里几张阿莱（口径 15）
    public var nextTurnDragons = 0
    /// 下回合不靠随机抽牌、不靠场上随从能打的伤害（`nextTurnLine` 的，重放校验过；口径 15）
    public var nextTurnDamage = 0
    /// ① 时：`nextTurnLine` 的前几步就够斩杀
    var nextTurnLethalSteps: Int?
    /// ② 时还差多少（剩余血量 − 下回合伤害）；其余为 0
    var shortBy = 0
    /// `line` 的下回合探过没有。false = 探针的预算在轮到它之前用完了（`cpuBudgetHit`，或 `maxProbes` 给的是 0）：
    /// 「本回合能破冰」照样成立（`line` 重放校验过），结论落在 ②，但 `nextTurnDamage` / `shortBy` 只是「没探」，
    /// 不是「探过、只有这么多」—— 面板要写成下回合没算完，不能写破不了，也不能写差多少
    public var nextTurnProbed = true
    /// 被 `config.cancellation` 取消：结果不完整，调用方丢掉
    public var cancelled = false
    /// 撞了 CPU 兜底（结果随机器负载变）
    var cpuBudgetHit = false
    /// ③ 时：不靠随机抽牌的打法穷举完了，按本模型确实破不了（否则只是没搜到）
    var exhaustive = false
    var cpuTime = 0.0
    /// 破冰搜索 + 准备步 + 探针合计
    var statesExpanded = 0
    /// 全部候选（重放得过的本回合线），按口径排好（第一条就是 `line`）；下回合没探的排在后面。给测试和调参看
    public var candidates: [RDIceCandidate] = []
}

public enum RDIceBreak {

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

    /// 下回合起手里对方回合把我方场面清光了（口径 15）：场上的随从（连同鲨鱼的光环）一个都不在，下回合只剩手牌、
    /// 英雄武器和英雄技能。和 `nextTurn` 只差场面
    static func cleared(_ next: RDState) -> RDState {
        var t = next
        t.board = []
        return t
    }

    /// 手里有几张阿莱（口径 15：下回合靠得住的斩杀上限、对方再挂一个冰时还有没有得用，都看它）。
    /// 1 费复制体也算；E.T.C. 能发现的、场上的不算
    static func dragons(_ s: RDState) -> Int {
        return s.hand.reduce(0) { $0 + ($1.card == .alexstrasza ? 1 : 0) }
    }

    /// 冰已打掉的局面的便宜分：共识分 = 把它当下回合起手、**场面清光**（口径 15，只看手里的）的共识分；
    /// 蓄力分看本回合还剩多少操作空间。只在**同一档**（下回合手里阿莱张数、破冰后剩余血量都相同）里比：留哪些候选、
    /// 准备步的束都是一档一档做的，档与档之间不拿这个分比（见 `better`），所以分里不含这两项
    static func evaluate(_ s: RDState) -> RedDragonSearch.RDEval {
        var e = RedDragonSearch.evaluate(cleared(nextTurn(s)))
        e.builder = RedDragonSearch.evaluate(s).builder
        return e
    }

    /// 一条下回合线在下回合起手上逐步重放：全走得通、而且没有一步靠随机抽到某张（`RDEngine.picksRandomDraw`，
    /// 按效果来源判）才算数，返回它实际打出的伤害和打到第几步对方死。探针收线、探针缓存复用、跟手都过这一关
    static func evidence(_ line: RedDragonLine, on next: RDState,
                         options: RDOptions = .search) -> (damage: Int, lethalSteps: Int?)? {
        var s = next
        var lethalSteps: Int?
        for (i, a) in line.actions.enumerated() {
            guard !RDEngine.picksRandomDraw(a, in: s),
                  let t = try? RDEngine.apply(a, to: s, options: options) else { return nil }
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
        /// `line` 是在清场后的起手上量的（`reliable` 用）
        var boardCleared = false
    }

    /// 下回合靠得住的伤害（口径 15）。对方回合可能把我方场面清光，也可能一个不动 —— 两种都打得出来的才算：
    /// 清场的那种只剩手牌（场上的阿莱复制不了、弹不回来，鲨鱼的光环也没了）；不清场的那种格子还占着，可能卡住手里的阿莱。
    /// `measure` 在一个起手上探一次（`probe`，调用方可以加缓存）。先探清场的；它那条线在不清场的起手上照样打得出、
    /// 伤害不少，就不用再探（不清场的至少这么多），否则再探一次取低的
    static func reliable(_ next: RDState, measure: (RDState) -> Probe) -> Probe {
        var out = measure(cleared(next))
        out.boardCleared = true
        guard !out.cancelled, out.damage > 0 else { return out }
        if let line = out.line, let ev = evidence(line, on: next), ev.damage >= out.damage { return out }
        var kept = measure(next)
        kept.states += out.states
        kept.cpuBudgetHit = kept.cpuBudgetHit || out.cpuBudgetHit
        guard !kept.cancelled, kept.damage < out.damage else {
            out.states = kept.states
            out.cpuBudgetHit = kept.cpuBudgetHit
            out.cancelled = kept.cancelled
            return out
        }
        return kept
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
        var out = Probe()
        /// 跑一遍，伤害更高（并且重放得过）就换上。返回这一遍有没有丢过带随机抽牌的分支
        func measure(_ c: RedDragonConfig) -> Bool {
            let r = RedDragonSearch.solve(dummy, config: c)
            out.states += r.statesExpanded
            out.cpuBudgetHit = out.cpuBudgetHit || r.cpuBudgetHit
            out.cancelled = out.cancelled || r.cancelled
            guard !r.cancelled, let line = r.chosenLine, line.damage > out.damage,
                  let ev = evidence(line, on: next, options: c.options), ev.damage == line.damage else {
                return r.randomBranchesDropped
            }
            out.damage = ev.damage
            out.line = line
            out.lethalSteps = ev.lethalSteps
            return r.randomBranchesDropped
        }
        // 先照原样跑（带随机抽牌的动作整支不要）；丢过那样的分支才再跑一遍盲抽的（抽牌发生、抽到的不能用），
        // 取伤害高的那条 —— 下回合矿锄再攻击的那 1 点原来算不进来（阶段 A 复核 1）
        if measure(c), !out.cancelled, RedDragonSearch.threadCPUTime() < deadline {
            c.blindDraws = true
            c.cpuBudget = max(0, min(base.iceBreak.probeCpuBudget, deadline - RedDragonSearch.threadCPUTime()))
            _ = measure(c)
        }
        return out
    }

    /// 两条破冰线谁在前（口径 11 + 14 + 15；`a` 在前返回 true）。「富余」= 下回合靠得住的伤害 − 破冰后剩余血量
    /// （`margin`），`safeMargin` 是「稳」的门槛（`RDIceBreakConfig.safeMargin`，默认 8 = 一次阿莱）。依次比：
    ///
    /// 1. 下回合探过的在前。没探的伤害是「不知道」，不拿 0 去和探出来的数比。
    /// 2. 下回合可斩（富余 ≥ 0）的在前。伤害只算手里的（`reliable`），不会再被场上随从骗。
    /// 3. **下回合手里阿莱多的在前**（口径 15，10-16 用户定：「下回合手里的红龙数量 > 破冰后对方剩余血量低」）。
    ///    阿莱越多下回合的斩杀上限越高；对方再挂一个冰，破它还得再耗阿莱 —— 只留刚好够斩的阿莱，再来一个冰就没了。
    ///    排在「可斩」后面：手里的阿莱多、下回合却一张都下不来（费不够、格子满），不如少一张但真能斩的。
    /// 4. 都可斩：**稳（富余 ≥ `safeMargin`）的在前**（口径 14）。「剩 1、下回合刚好 1 点」对方回 1 血就斩不了，
    ///    不如「剩 5、下回合 32」（用户定的）。
    ///    a. 都稳：**破冰后剩余血量低的在前**。对方这回合掉不到 1 血以下，能做的最好的事就是把血压到最低再触发；
    ///       富余已经够一次阿莱，多出来的是溢出，不值得拿剩余血量去换（口径 11）。
    ///       剩余相同：富余按 8（一次阿莱）分档，档高的在前；同档：本回合步数少的在前；再同，富余多的在前。
    ///    b. 都不稳：富余多的在前；再同，剩余血量低的在前；再同，步数少的在前。
    /// 5. 都不可斩：差得少的在前；同差，剩余血量低的在前；再同，步数少的在前。
    ///    （两条都没探时差额 = −剩余血量，这一条就是「剩余低的在前、再按步数」。）
    /// 6. 还分不出：难度低的在前，再按进候选的先后。
    static func better(_ a: RDIceCandidate, _ b: RDIceCandidate,
                       safeMargin: Int = RDIceBreakConfig().safeMargin) -> Bool {
        if a.probed != b.probed { return a.probed }
        let (x, y) = (a.margin >= 0, b.margin >= 0)
        if x != y { return x }
        if a.dragons != b.dragons { return a.dragons > b.dragons }
        if x {
            let (p, q) = (a.margin >= safeMargin, b.margin >= safeMargin)
            if p != q { return p }
            if p {
                if a.remaining != b.remaining { return a.remaining < b.remaining }
                if a.margin / 8 != b.margin / 8 { return a.margin / 8 > b.margin / 8 }
                if a.steps != b.steps { return a.steps < b.steps }
                if a.margin != b.margin { return a.margin > b.margin }
            } else {
                if a.margin != b.margin { return a.margin > b.margin }
                if a.remaining != b.remaining { return a.remaining < b.remaining }
                if a.steps != b.steps { return a.steps < b.steps }
            }
        } else {
            if a.margin != b.margin { return a.margin > b.margin }
            if a.remaining != b.remaining { return a.remaining < b.remaining }
            if a.steps != b.steps { return a.steps < b.steps }
        }
        if a.line.difficulty != b.line.difficulty { return a.line.difficulty < b.line.difficulty }
        return a.order < b.order
    }

    /// 一档候选：下回合手里阿莱张数相同、破冰后剩余血量相同。档的先后 = 阿莱多的在前、同阿莱剩余低的在前（`<`）
    struct Level: Hashable, Comparable {
        var dragons: Int
        var remaining: Int

        static func < (a: Level, b: Level) -> Bool {
            return a.dragons != b.dragons ? a.dragons > b.dragons : a.remaining < b.remaining
        }
    }

    /// 一个探针的结果，按 `better` 的口径分三类
    enum ProbeOutcome {
        /// 下回合斩不了
        case short
        /// 可斩，不稳（富余 < `safeMargin`）
        case lethal
        /// 稳斩
        case safe
    }

    /// 已经探出来的最好结果：哪一档有稳斩、可斩的最多几张阿莱。比它们差的档不用再探（排不到它们前面）
    struct ProbeBound {
        var safe: Level?
        var lethalDragons: Int?

        mutating func note(_ o: ProbeOutcome, at l: Level) {
            guard o != .short else { return }
            lethalDragons = max(lethalDragons ?? l.dragons, l.dragons)
            if o == .safe, safe.map({ l < $0 }) ?? true { safe = l }
        }

        /// 这一档的线能不能排到已知结果前面（`better`：先可斩，再阿莱多，再稳，再剩余低）
        func excludes(_ l: Level) -> Bool {
            if let d = lethalDragons, l.dragons < d { return true }
            if let s = safe, l.dragons == s.dragons, l.remaining > s.remaining { return true }
            if let s = safe, l.dragons < s.dragons { return true }
            return false
        }
    }

    /// 下回合探针的名额怎么分（口径 12 + 15：阿莱多的档先、同阿莱剩余低的先）。`solveIceBreak` 用；不碰局面，单独拿出来好测。
    ///
    /// `levels[i]` 是第 i 档（按 `Level` 的先后排好），`counts[i]` 是这一档排好队的候选条数（队首最该先探）。
    /// `probe(i, k)` 探第 i 档队里的第 k 条，返回它下回合的结果；返回 nil = 探不成了（CPU 份额用完 / 被取消），
    /// 之后一条都不再探。`known` = 进来之前已知的结果。返回每一档探了队里的前几条。
    ///
    /// 分三轮，每一轮都从排在最前的一档往后走：
    /// 1. 每档先探 `first` 条：**每一档都先轮到**。只按「前面的档先探满」分的话，前几档探满了、都斩不了，名额就用完了，
    ///    后面的档里明明有可斩的线也一条探不到，结论会错报成「下回合差一点」。
    /// 2. 每档补到 `perLevel` 条：同档里多探几条，比 8 分档和步数。
    /// 3. 名额还有剩：各档没探的全部补上。
    ///
    /// 探出来的结果把排不到它前面的档挡掉（`ProbeBound.excludes`）：某档可斩，阿莱比它少的档不用探；某档稳斩，
    /// 同阿莱、剩得多的档也不用探。只是可斩、不稳的挡不住同阿莱剩得多的档：那里稳的线排在它前面（口径 14）
    static func scheduleProbes(levels: [Level], counts: [Int], quota: Int, first: Int, perLevel: Int,
                               known: ProbeBound = ProbeBound(),
                               probe: (_ level: Int, _ index: Int) -> ProbeOutcome?) -> [Int] {
        var done = [Int](repeating: 0, count: counts.count)
        var left = quota
        var bound = known
        var stopped = false
        for limit in [first, perLevel, Int.max] {
            for i in counts.indices {
                if bound.excludes(levels[i]) { continue }
                while !stopped, left > 0, done[i] < min(limit, counts[i]) {
                    guard let outcome = probe(i, done[i]) else {
                        stopped = true
                        break
                    }
                    done[i] += 1
                    left -= 1
                    bound.note(outcome, at: levels[i])
                }
            }
        }
        return done
    }

    public struct Followed {
        /// 接到真实局面上的结论：`root` 是真实局面（标好冰），`line` 是剩下没打的步骤，下回合线已换成真实编号重放过
        public var result: RDIceBreakResult
        /// 真实局面对上的是原来那条线的第几步之后（0 = 一步没走）
        public var stepsTaken: Int
    }

    /// 跟手：用户照着 `plan.line` 打了几步（或一步没打）之后的真实局面 `real`（读取层读出来的，不用先标冰）还在线上时，
    /// 不重算，把结论接过去。对不上、剩下的步骤在真实局面上走不通、下回合线在真实终局上重放不过或结论变了，都返回 nil，
    /// 调用方照常重算（`solveIceBreak`）。`tolerant` 同 `RDContinuation.advance`（真实局面多抽了牌也算对上）
    public static func follow(_ plan: RDIceBreakResult, onto real: RDState, tolerant: Bool = false) -> Followed? {
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
        out.nextTurnDragons = dragons(next)
        if var nextLine = plan.nextTurnLine {
            nextLine.actions = nextLine.actions.map(resumed.translate)
            guard let ev = evidence(nextLine, on: plan.nextTurnBoardCleared ? cleared(next) : next) else { return nil }
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

    /// 破冰模式的入口（T8 口径 1–5、11–15）。`root` 是读取层读出来的局面（不用先标冰）；同步、单线程，取消走
    /// `config.cancellation`（和斩杀搜索同一个标记：搜索每展开一个节点、每个探针之前和探针里面都看）。
    ///
    /// 三步：① 破冰搜索（`iceBreakPasses`）：不靠随机抽牌把冰打掉 —— 冰还在时一直往下压血，各种剩余血量的破法都收；
    /// 冰打掉之后接着展开准备步，每档（下回合手里阿莱张数 × 剩余血量）、每个步数留几个终局；
    /// ② 每个终局折成下回合起手（`RDIceBreak.nextTurn`），探下回合不靠随机抽牌、只靠手里的牌能打多少
    /// （`RDIceBreak.reliable`：清场、不清场两种起手取低的），从阿莱多的档、同阿莱剩余低的档探起，排不到前面的档不再探；
    /// ③ 按口径 11 + 14 + 15 排（`RDIceBreak.better`：可斩的在前，再阿莱多的在前，再稳的在前、剩余低的在前）。
    /// 给出去的本回合线和下回合线都是引擎重放校验过的；「下回合可斩」只在下回合线真的在它那种起手上把对方打死时才说
    public static func solveIceBreak(_ root: RDState, config: RedDragonConfig = RedDragonConfig()) -> RDIceBreakResult {
        let start = threadCPUTime()
        // 两个截止时间：搜索（破冰 + 准备步）先到点，探针另有一份 —— 搜索把预算吃光时已经找到的破冰线还轮得到探
        let deadline = start + config.iceBreak.cpuBudget
        let searchDeadline = deadline - config.iceBreak.probeReserve
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

        let run = iceBreakPasses(armed, config: config, deadline: searchDeadline)
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
        // 「本回合能破冰」和「下回合探没探完」是两件事。每条线先在根局面上重放：过了就是候选，顺便知道它破冰后
        // 剩多少、下回合从哪儿起手；探针的预算是之后的事。预算用完（CPU 兜底，或没排上探针名额）的线照留，
        // 只是下回合没探（`probed == false`）—— 不会因为探针没做就把重放过的破冰线报成破不了
        struct Entry {
            var line: RedDragonLine
            var remaining: Int
            var next: RDState
            var level: RDIceBreak.Level { return RDIceBreak.Level(dragons: RDIceBreak.dragons(next), remaining: remaining) }
        }
        // 盲抽补搜找到的线（带 `RDChoice.blind`）排在主搜索的线之后、另有名额：主搜索的线探哪几条和没有它们时一样
        func isBlind(_ l: RedDragonLine) -> Bool { return l.actions.contains { $0.choices.contains(.blind) } }
        var plain: [Entry] = []
        var blind: [Entry] = []
        for line in lines {
            if isCancelled() {
                out.cancelled = true
                return finish()
            }
            // 搜索那边已经不展开靠随机抽牌的分支（`deterministicOnly`）；这里按同一个判断再核一遍，给出去的线不靠运气
            guard let end = try? RDReplay.run(line.actions, from: armed, options: config.options).finalState,
                  end.opponent.ice == .broken,
                  !RDEngine.lineHasRandomDraw(line.actions, from: armed, options: config.options) else { continue }
            let entry = Entry(line: line, remaining: end.opponent.effectiveHealth, next: RDIceBreak.nextTurn(end))
            if isBlind(line) { blind.append(entry) } else { plain.append(entry) }
        }

        var candidates: [RDIceCandidate] = []
        // 下回合起手相同的终局（只差本回合剩的法力之类）共用一次探针：编号可能不同，线要在各自的起手上再重放一遍
        var cache: [UInt64: RDIceBreak.Probe] = [:]
        func unprobed(_ e: Entry) {
            candidates.append(RDIceCandidate(line: e.line, remaining: e.remaining, nextTurnRoot: e.next,
                                             dragons: RDIceBreak.dragons(e.next),
                                             nextTurnLine: nil, nextTurnDamage: 0, nextTurnLethalSteps: nil,
                                             probed: false, order: candidates.count))
        }
        let safeMargin = config.iceBreak.safeMargin
        /// 在一个下回合起手上探一次（带缓存）
        func measure(_ start: RDState) -> RDIceBreak.Probe {
            let key = start.canonicalHash()
            if let hit = cache[key], let known = hit.line, let ev = RDIceBreak.evidence(known, on: start),
               ev.damage == hit.damage {
                var probe = hit
                probe.lethalSteps = ev.lethalSteps
                probe.states = 0
                return probe
            }
            let probe = RDIceBreak.probe(start, config: config, deadline: deadline)
            if !probe.cancelled { cache[key] = probe }
            return probe
        }
        /// 探一条线的下回合（清场、不清场两种起手取低的，口径 15），记进候选，返回它下回合的结果。nil = 没探成
        /// （预算用完，或被取消 —— 取消时 `out.cancelled` 已立）
        func probeNextTurn(_ e: Entry) -> RDIceBreak.ProbeOutcome? {
            if isCancelled() {
                out.cancelled = true
                return nil
            }
            if threadCPUTime() > deadline {
                out.cpuBudgetHit = true
                return nil
            }
            let probe = RDIceBreak.reliable(e.next, measure: measure)
            out.statesExpanded += probe.states
            if probe.cancelled {
                out.cancelled = true
                return nil
            }
            if probe.cpuBudgetHit { out.cpuBudgetHit = true }
            candidates.append(RDIceCandidate(line: e.line, remaining: e.remaining, nextTurnRoot: e.next,
                                             dragons: RDIceBreak.dragons(e.next),
                                             nextTurnBoardCleared: probe.boardCleared,
                                             nextTurnLine: probe.line, nextTurnDamage: probe.damage,
                                             nextTurnLethalSteps: probe.lethalSteps, order: candidates.count))
            let margin = probe.damage - e.remaining
            return margin >= safeMargin ? .safe : (margin >= 0 ? .lethal : .short)
        }
        /// 把 `quota` 个探针名额花在 `entries` 上，没探到的线也记进候选（`probed == false`）。返回 false = 被取消。
        ///
        /// 先分档（下回合手里阿莱多的在前、同阿莱剩余血量低的在前，`RDIceBreak.Level`），每档排一个队：队首是这一档
        /// 便宜分最高的那条（下回合最可能可斩：第一轮每档只探一两条，先看它），之后是各步数的第 1 名（步数少的在前）→
        /// 各步数的第 2 名 → …（`entries` 进来时同档已按便宜分降序）。名额怎么分在 `RDIceBreak.scheduleProbes`
        func spend(_ entries: [Entry], quota: Int, known: RDIceBreak.ProbeBound) -> Bool {
            var byLevel: [RDIceBreak.Level: [Entry]] = [:]
            for e in entries { byLevel[e.level, default: []].append(e) }
            let levels = byLevel.keys.sorted()
            var queues: [[Entry]] = []
            for level in levels {
                let all = byLevel[level] ?? []
                var bySteps: [Int: [Entry]] = [:]
                for e in all.dropFirst() { bySteps[e.line.actions.count, default: []].append(e) }
                let steps = bySteps.keys.sorted()
                var queue = Array(all.prefix(1))
                var rank = 0
                while queue.count < all.count {
                    for s in steps where rank < (bySteps[s]?.count ?? 0) {
                        if let e = bySteps[s]?[rank] { queue.append(e) }
                    }
                    rank += 1
                }
                queues.append(queue)
            }
            let done = RDIceBreak.scheduleProbes(levels: levels, counts: queues.map { $0.count }, quota: quota,
                                                 first: config.iceBreak.firstProbesPerRemaining,
                                                 perLevel: config.iceBreak.probesPerRemaining,
                                                 known: known) { i, k in probeNextTurn(queues[i][k]) }
            if out.cancelled { return false }
            for i in queues.indices {
                for e in queues[i][done[i]...] { unprobed(e) }
            }
            return true
        }
        guard spend(plain, quota: config.iceBreak.maxProbes, known: RDIceBreak.ProbeBound()) else { return finish() }
        // 盲抽线另有名额；主搜索的线里已经探出来的结果挡掉排不到它前面的盲抽线
        var known = RDIceBreak.ProbeBound()
        for c in candidates where c.probed && c.margin >= 0 {
            known.note(c.margin >= safeMargin ? .safe : .lethal, at: RDIceBreak.Level(dragons: c.dragons,
                                                                                       remaining: c.remaining))
        }
        guard spend(blind, quota: config.iceBreak.maxBlindProbes, known: known) else { return finish() }
        candidates.sort { RDIceBreak.better($0, $1, safeMargin: safeMargin) }
        out.candidates = candidates
        // 没有候选 = 本回合破不了冰（③）：没有一条重放得过的破冰线。和探针做没做完无关
        guard let best = candidates.first else { return finish() }

        out.line = best.line
        out.remaining = best.remaining
        out.nextTurnRoot = best.nextTurnRoot
        out.nextTurnLine = best.nextTurnLine
        out.nextTurnBoardCleared = best.nextTurnBoardCleared
        out.nextTurnDragons = best.dragons
        out.nextTurnDamage = best.nextTurnDamage
        out.nextTurnLethalSteps = best.nextTurnLethalSteps
        out.nextTurnProbed = best.probed
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
