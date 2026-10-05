//
//  RedDragonAssistant.swift
//  HSTracker
//
//  红龙辅助的调度：解析边界上的挂点 → 解析线程拷快照 → 主线程去抖调度 → 后台读取 + 搜索 → 主线程一次提交。
//
//  每一跳（AGENTS.md「线程与时序」）：
//  1. 解析线程（LogReaderManager 的串行队列）：每处理完一批日志行调一次 `parserBatchDidEnd`。
//     开关缓存关着直接返回（一次加锁读 Bool，不读 UserDefaults）。这批有新行（或开关刚打开）就记「待拷」；
//     没有未闭合的 BLOCK（`PowerGameStateParser.currentBlock == nil`）时才拷：此刻只有本线程写实体，
//     实体 tag、`BoardState`、`getDeckState()` 读到的是同一时刻。套牌判定按套牌 id 缓存（加锁，任何线程可读）。
//     不是红龙套牌 / 不在对局 → `.inactive`，和上次投递的相同就什么都不做（非本牌组的对局一次 main.async 都不投）。
//     拷出的输入和上次投递的不同 → 局面版本 +1、作废在算的那次、投 **`main.async`（第 1 跳）**。
//     BLOCK 还开着时来了新行、上次投递的是局面 → 先作废（版本 +1、取消在算的），投 `main.async` 让主线程
//     把结果标过时（`markStale`），每段只投一次；到一致边界再拷、再投（即使和上次相同）
//  2. 主线程 `submit`：开关（`env.isEnabled()`）再查一次；记下版本，标「正在算」，
//     `workQueue.asyncAfter(debounce)`。屏上是本回合的斩杀线时改成 `workQueue.async`（不去抖）
//  3. 后台串行队列：读取 + 搜索 + 生成结论；被作废就半路退出（搜索主循环和收尾都看取消标记）
//     → **`main.async`（第 2 跳）**。不去抖的那次先试「接着用」（`RDContinuation`：新局面就是屏上那条线
//     推出来的局面，剩下的步骤在真实局面上重放校验通过）；对不上就在这条队列上再 `asyncAfter(debounce)` 走搜索
//  4. 主线程 `commit`：代号是最新的、局面版本等于解析线程最新拷出的版本、对局身份没变、开关还开着
//     → 结论 + 揭示档 + 答题判定在同一个 block 里提交，回调 `onChange`
//

import Foundation
// 引擎在本地包里（HSTracker/RedDragon/Package.swift），为了 Debug 下也按 -O 编；包带 -enable-testing，
// app 侧用 @testable 访问 internal 符号，不必把引擎改成 public
@testable import RedDragonCore

extension RDDeckGate {
    static func isRedDragonDeck(_ deck: PlayingDeck) -> Bool {
        var sideboards: [String: [String]] = [:]
        for s in deck.sideboards { sideboards[s.ownerCardId] = s.cards.map { $0.id } }
        return isRedDragonDeck(cardIds: deck.cards.map { $0.id }, sideboards: sideboards)
    }
}

/// 解析线程判定出的当前情形
enum RDAssistantInput: Equatable {
    case inactive
    case opponentTurn
    case snapshot(RDGameSnapshot)
}

final class RedDragonAssistant {

    struct Environment {
        var isEnabled: () -> Bool
        var revealPreference: () -> RDRevealLevel
        var quizMode: () -> Bool
        /// 主线程收到新局面后等多久再算：一串连续变化只算最后一次
        var debounce: TimeInterval
        var config: RedDragonConfig
        var cardName: (String) -> String
        /// 跟手（T3）：新局面就是屏上那条斩杀线推出来的局面时，不去抖、不搜索，重放校验剩下的步骤直接上屏
        var followsLine = true

        static let live = Environment(
            isEnabled: { Settings.redDragonAssist },
            revealPreference: { RDRevealLevel(rawValue: Settings.redDragonRevealLevel) ?? .verdict },
            quizMode: { Settings.redDragonQuizMode },
            debounce: 0.12,
            config: RedDragonConfig(),
            cardName: { Cards.any(byId: $0)?.name ?? $0 })
    }

    static let shared = RedDragonAssistant(environment: .live, observeSettings: true)

    private let env: Environment
    private let workQueue = DispatchQueue(label: "net.hearthsim.hstracker.reddragon", qos: .utility)

    // —— 解析线程与主线程共用，全部在 `lock` 下读写 ——

    private let lock = NSLock()
    /// 开关的缓存：解析线程每批都要看一眼，不能每次读 UserDefaults。主线程在开关通知里更新
    private var enabledCache: Bool
    /// 开关刚打开：下一批即使没有新行也拷一次
    private var forceCapture = false
    /// 有新行还没拷（上一批结束时 BLOCK 没闭合）
    private var pendingCapture = false
    /// 最近一次投递到主线程的输入。初值 `.inactive`：不是本牌组时永远不投递
    private var lastFed: RDAssistantInput = .inactive
    /// 解析线程拷出的局面版本（每投递一个不同的输入 +1）
    private var parsedVersion = 0
    /// 最近一次投递的快照的对局身份
    private var parsedMatch: Date?
    /// 键带上 sideboard 张数：同一副牌的乐队可能在会话中途才被补进来（导入时缺了、下次匹配时更新）
    private var deckGateCache: (id: String, sideboardCards: Int, eligible: Bool)?
    /// 在算的那次的取消标记（主线程调度时放进来，解析线程拷出新局面时作废）
    private var sharedToken: RDCancellation?
    /// 上次投递之后、一致边界之前，局面已经作废过（BLOCK 开着时来了新行）。下一个一致边界上的快照
    /// 即使和上次投递的相同也要再投（主线程已经把结果标过时、作废了在算的）
    private var staleMarked = false
    /// 投递过的输入（只在 `recordsFeeds` 时记，测试用）
    private var fedHistory: [RDAssistantInput] = []
    private let recordsFeeds: Bool
    /// 拍快照 + 比较的耗时（纳秒，只在 `recordsFeeds` 时记，测试用）
    private var captureNanos: [UInt64] = []

    /// 测试用：每次「拍快照 + 和上次投递的比较」的耗时（秒）
    var captureTimings: [Double] {
        lock.lock()
        defer { lock.unlock() }
        return captureNanos.map { Double($0) / 1e9 }
    }

    /// 测试用：投递到主线程的输入
    var fedInputs: [RDAssistantInput] {
        lock.lock()
        defer { lock.unlock() }
        return fedHistory
    }

    // —— 以下全部只在主线程读写 ——

    /// overlay 读的状态。T2c 的 overlay 用 `subscribe` 接（`onChange` 只留一个回调位）
    private(set) var hint = RedDragonHint.inactive
    var onChange: ((RedDragonHint) -> Void)?
    /// 调度过几次计算（测试用：关掉开关后它不再涨）
    private(set) var scheduledComputations = 0
    /// 跑完并上屏的次数（测试用）
    private(set) var committedComputations = 0
    /// 跑完但因为局面版本 / 对局身份过时被丢掉的次数（测试用）
    private(set) var discardedComputations = 0
    /// 上屏的结论里走「接着用」（没搜索）的次数（测试用）
    private(set) var followedComputations = 0

    /// 屏上那条斩杀线（第一条）和同一局面上其余不靠抽牌的斩杀线，各带自己的根局面（`RDContinuation` 的起点）。
    /// 用户不一定照屏上的顺序打（10-05 第 7 局 T13 换了顺序，照样能斩），其余的线也接。只在结论是「可斩杀」时有
    private struct FollowBase {
        var candidates: [(root: RDState, line: RedDragonLine)]
        var turn: Int
        var match: Date?
    }

    private var generation = 0
    private var inFlight: RDCancellation?
    private var followBase: FollowBase?
    private var lastSnapshot: RDGameSnapshot?
    private var turn: Int?
    private var requestedReveal: RDRevealLevel?
    private var quizState: RDQuizState?
    private var observers: [NSObjectProtocol] = []

    init(environment: Environment, observeSettings: Bool = false, recordsFeeds: Bool = false) {
        env = environment
        enabledCache = environment.isEnabled()
        self.recordsFeeds = recordsFeeds
        guard observeSettings else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: Notification.Name(rawValue: Settings.red_dragon_assist),
                                            object: nil, queue: .main) { [weak self] _ in
            self?.settingsDidChange()
        })
        for key in [Settings.red_dragon_reveal_level, Settings.red_dragon_quiz_mode] {
            observers.append(center.addObserver(forName: Notification.Name(rawValue: key),
                                                object: nil, queue: .main) { [weak self] _ in
                self?.recompose()
            })
        }
    }

    deinit {
        for o in observers { NotificationCenter.default.removeObserver(o) }
    }

    // MARK: - 挂点（解析线程）

    /// `LogReaderManager` 每处理完一批日志行调一次（包括没有新行的空批）。
    /// `idle`：解析器没有未闭合的 BLOCK
    func parserBatchDidEnd(_ game: Game, linesProcessed: Bool, idle: Bool) {
        lock.lock()
        guard enabledCache else {
            lock.unlock()
            return
        }
        if linesProcessed || forceCapture {
            pendingCapture = true
            forceCapture = false
        }
        // 「旧局面作废」和「新快照可读」分开（T2b 第三轮）：BLOCK 还开着时来了新行，实体可能已经变了，
        // 但还不是一致边界、不能拷。只要上次投递的是局面（可能有结果在算 / 在屏上），就先作废：
        // 版本 +1（在算的那次回来时对不上版本、不上屏）、取消在算的、主线程把结果标过时。每段只作废一次
        var stale: RDCancellation?
        var staleVersion: Int?
        if linesProcessed && !idle && !staleMarked, case .snapshot = lastFed {
            staleMarked = true
            parsedVersion += 1
            staleVersion = parsedVersion
            stale = sharedToken
            sharedToken = nil
        }
        let capture = pendingCapture && idle
        if capture { pendingCapture = false }
        lock.unlock()
        if let version = staleVersion {
            stale?.cancel()
            DispatchQueue.main.async { [weak self] in
                self?.markStale(version: version)
            }
        }
        guard capture else { return }
        let start = recordsFeeds ? DispatchTime.now().uptimeNanoseconds : 0
        feed(input(from: game))
        if recordsFeeds {
            let spent = DispatchTime.now().uptimeNanoseconds - start
            lock.lock()
            captureNanos.append(spent)
            lock.unlock()
        }
    }

    /// 解析线程，一致边界上。先做最便宜的判断：不在对局 / 不是这副牌时不碰实体
    private func input(from game: Game) -> RDAssistantInput {
        guard !game.isInMenu, !game.gameEnded, let deck = game.currentDeck else { return .inactive }
        guard isEligible(deck), !game.isBattlegroundsMatch(), !game.isMercenariesMatch(),
              game.isMulliganDone() else { return .inactive }
        guard RDGameSnapshot.playerEntity(game: game)?.isCurrentPlayer == true else { return .opponentTurn }
        guard let snap = RDGameSnapshot.capture(game: game) else { return .inactive }
        return .snapshot(snap)
    }

    /// 套牌判定，按套牌 id + sideboard 张数缓存。任何线程可调
    func isEligible(_ deck: PlayingDeck) -> Bool {
        let sideboardCards = deck.sideboards.reduce(0) { $0 + $1.cards.count }
        lock.lock()
        if let gate = deckGateCache, gate.id == deck.id, gate.sideboardCards == sideboardCards {
            lock.unlock()
            return gate.eligible
        }
        lock.unlock()
        let eligible = RDDeckGate.isRedDragonDeck(deck)
        lock.lock()
        deckGateCache = (deck.id, sideboardCards, eligible)
        lock.unlock()
        return eligible
    }

    /// 解析线程拷出了一个输入（测试也从这里喂）。和上次投递的相同就不投；不同就局面版本 +1、
    /// 作废在算的那次（它算的已经不是最新局面），再投 `main.async`
    func feed(_ input: RDAssistantInput) {
        lock.lock()
        guard enabledCache else {
            lock.unlock()
            return
        }
        var input = input
        // 只有操作数变了的也投（T2b 第四轮）：攻击的计数在攻击结算之后才涨，那一份就是「这一步完成」的边界。
        // 主线程见到只差操作数的局面不重算，只拿现有结论判卷（`submit`）
        if input == lastFed {
            // 没变：平时不投；但这段里已经作废过，就把上次的局面原样再投一次，让主线程重算
            guard staleMarked else {
                lock.unlock()
                return
            }
            input = lastFed
        }
        staleMarked = false
        lastFed = input
        if recordsFeeds { fedHistory.append(input) }
        parsedVersion += 1
        let version = parsedVersion
        if case .snapshot(let snap) = input { parsedMatch = snap.match }
        let stale = sharedToken
        sharedToken = nil
        lock.unlock()
        stale?.cancel()
        DispatchQueue.main.async { [weak self] in
            self?.submit(input, version: version)
        }
    }

    /// 两个输入只差 `NUM_OPTIONS_PLAYED_THIS_TURN`。出牌时计数先于 PLAY 块涨（g2 fixture 第 16164 → 16184 行），
    /// 攻击时在攻击结算之后才涨（第 4078、5824 行）。第三轮在解析线程上丢掉这种快照，攻击那一步就判不到了；
    /// 第四轮起照投，由 `RDQuizState` 按「一个操作完成」的边界配对（见那里的注释）
    static func onlyOptionCountChanged(_ a: RDAssistantInput, _ b: RDAssistantInput) -> Bool {
        guard case .snapshot(var x) = a, case .snapshot(let y) = b,
              x.optionsPlayedThisTurn != y.optionsPlayedThisTurn else { return false }
        x.optionsPlayedThisTurn = y.optionsPlayedThisTurn
        return x == y
    }

    /// 解析线程最新拷出的局面版本和对局身份
    private func parsedState() -> (version: Int, match: Date?) {
        lock.lock()
        defer { lock.unlock() }
        return (parsedVersion, parsedMatch)
    }

    // MARK: - 主线程

    /// `version`：解析线程给的局面版本。nil = 测试直接喂，不核对版本
    func submit(_ input: RDAssistantInput, version: Int? = nil) {
        guard env.isEnabled() else {
            clear()
            return
        }
        switch input {
        case .inactive:
            guard hint.phase != .inactive else { return }
            invalidate()
            resetTurn(nil)
            publish(.inactive)
        case .opponentTurn:
            guard hint.phase != .opponentTurn else { return }
            invalidate()
            resetTurn(nil)
            var h = RedDragonHint.inactive
            h.phase = .opponentTurn
            publish(h)
        case .snapshot(let snap):
            if snap == lastSnapshot && (hint.phase == .ready || hint.phase == .computing) { return }
            // 只有操作数变了、屏上的结论就是这个局面的：不重算，拿现有结论按新计数判卷
            if let last = lastSnapshot, hint.phase == .ready, !hint.isStale, var a = hint.analysis,
               last.turn == snap.turn, RDQuizState.sameIgnoringOptionCount(snap, last) {
                lastSnapshot = snap
                a.actionsTaken = snap.optionsPlayedThisTurn
                quizState = RDQuizState.next(quizState, snapshot: snap, verdict: a.verdict)
                var h = hint
                h.analysis = a
                publish(composed(h))
                return
            }
            if let last = lastSnapshot, last.match != snap.match { resetTurn(nil) }
            lastSnapshot = snap
            if turn != snap.turn { resetTurn(snap.turn) }
            schedule(snap, version: version)
        }
    }

    /// 解析线程发现 BLOCK 开着时实体在变（还不能拷）：作废在算的、结果标过时，等一致边界上的快照到了再算。
    /// `version` 只用来在测试里对得上号；作废本身不看它
    private func markStale(version: Int) {
        guard env.isEnabled() else { return }
        invalidate()
        // 一致边界上的快照可能和上一份相同（这段日志没改到相关实体），那也要重算
        lastSnapshot = nil
        guard hint.phase == .ready || hint.phase == .computing else { return }
        var h = hint
        h.phase = .computing
        h.isStale = h.analysis != nil
        publish(h)
    }

    private func schedule(_ snap: RDGameSnapshot, version: Int?) {
        invalidate()
        let gen = generation
        let token = RDCancellation()
        inFlight = token
        lock.lock()
        sharedToken = token
        lock.unlock()
        scheduledComputations += 1
        var h = hint
        h.phase = .computing
        h.isStale = h.analysis != nil
        publish(h)

        let env = self.env
        let workQueue = self.workQueue
        // 第 3 跳之后回主线程（第 4 跳）的那一下，搜索和接着用两条路共用
        let deliver: (RDAnalysis, FollowBase?, Bool) -> Void = { [weak self] analysis, base, followed in
            DispatchQueue.main.async {
                guard let self, gen == self.generation, self.env.isEnabled() else { return }
                if let version {
                    // 解析线程已经拷出更新的局面（主线程可能还没收到）、或者换了局：这个结果过时了
                    let parsed = self.parsedState()
                    guard parsed.version == version, parsed.match == snap.match else {
                        self.discardedComputations += 1
                        return
                    }
                }
                if followed { self.followedComputations += 1 }
                self.commit(analysis, snapshot: snap, base: base)
            }
        }
        let search = {
            guard !token.isCancelled else { return }
            let live = RDStateReader.read(snap)
            var config = env.config
            config.cancellation = token
            let result = RedDragonSearch.solve(live.state, config: config)
            guard !token.isCancelled, !result.cancelled else { return }
            let analysis = RDHintBuilder.analyze(snapshot: snap, live: live, result: result,
                                                 cardName: env.cardName)
            let lines = result.lethalLines.filter { !RDLineWalker.dependsOnDraw($0.actions, root: live.state) }
            let base = FollowBase(candidates: lines.map { (live.state, $0) }, turn: snap.turn, match: snap.match)
            deliver(analysis, lines.isEmpty ? nil : base, false)
        }
        // 跟手：屏上是斩杀线、还在同一回合时，先不去抖试一次「接着用」（读取 + 推演 + 重放，毫秒级），
        // 对不上再按原样去抖、搜索。都在同一条串行后台队列上，取消标记照看
        guard env.followsLine, let base = followBase, base.turn == snap.turn, base.match == snap.match else {
            workQueue.asyncAfter(deadline: .now() + env.debounce, execute: search)
            return
        }
        workQueue.async {
            guard !token.isCancelled else { return }
            var live = RDStateReader.read(snap)
            let resumed = RDContinuation.resumeAll(base.candidates, onto: live.state)
            guard let shown = resumed.first else {
                workQueue.asyncAfter(deadline: .now() + env.debounce, execute: search)
                return
            }
            // 线是从共用的根局面（新编号起点和读取的不同）校验的，展示层逐步推演也要从它推
            live.state = shown.root
            let result = RDContinuation.result(resumed.map { $0.line }, root: live.state)
            let analysis = RDHintBuilder.analyze(snapshot: snap, live: live, result: result,
                                                 cardName: env.cardName)
            let next = FollowBase(candidates: resumed.map { ($0.root, $0.line) }, turn: snap.turn, match: snap.match)
            deliver(analysis, next, true)
        }
    }

    private func commit(_ analysis: RDAnalysis, snapshot: RDGameSnapshot, base: FollowBase?) {
        inFlight = nil
        followBase = analysis.verdict == .lethal ? base : nil
        committedComputations += 1
        quizState = RDQuizState.next(quizState, snapshot: snapshot, verdict: analysis.verdict)
        var h = hint
        h.phase = .ready
        h.analysis = analysis
        h.isStale = false
        publish(composed(h))
    }

    /// 揭示档 / 答题判定随用户操作和偏好变，结论不变
    private func composed(_ base: RedDragonHint) -> RedDragonHint {
        var h = base
        let lethal = h.analysis?.isLethal ?? false
        let tier = h.analysis?.tier
        h.maxRevealLevel = RDRevealPolicy.cap(isLethal: lethal, tier: tier, preference: env.revealPreference())
        h.revealLevel = RDRevealPolicy.effective(requested: requestedReveal, preference: env.revealPreference(),
                                                 isLethal: lethal, tier: tier)
        h.quizMode = env.quizMode()
        h.quiz = h.quizMode ? quizState?.mark : nil
        return h
    }

    private func recompose() {
        guard hint.analysis != nil else { return }
        publish(composed(hint))
    }

    /// 热键：升一档（T2c 接）
    func raiseReveal() {
        guard let a = hint.analysis, hint.phase == .ready || hint.phase == .computing else { return }
        let top = RDRevealPolicy.cap(isLethal: a.isLethal, tier: a.tier, preference: env.revealPreference())
        requestedReveal = min(top, RDRevealLevel(rawValue: hint.revealLevel.rawValue + 1) ?? .order)
        recompose()
    }

    /// 热键：降一档
    func lowerReveal() {
        guard hint.analysis != nil else { return }
        requestedReveal = RDRevealLevel(rawValue: hint.revealLevel.rawValue - 1) ?? .verdict
        recompose()
    }

    /// 开关变了（`Settings.red_dragon_assist` 的通知，主线程）。打开：解析线程下一批（≤ 50 ms，没有新行也算）
    /// 拷一次；关掉：解析线程不再拷，作废在算的、清空结果
    func settingsDidChange() {
        let enabled = env.isEnabled()
        lock.lock()
        enabledCache = enabled
        forceCapture = enabled
        pendingCapture = false
        staleMarked = false
        lastFed = .inactive
        lock.unlock()
        if !enabled { clear() }
    }

    /// 关掉开关：作废在算的、清空结果。之后挂点不再拷，`submit` 也直接返回
    private func clear() {
        invalidate()
        lastSnapshot = nil
        resetTurn(nil)
        if hint != .inactive { publish(.inactive) }
    }

    private func invalidate() {
        generation += 1
        inFlight?.cancel()
        inFlight = nil
    }

    private func resetTurn(_ newTurn: Int?) {
        turn = newTurn
        requestedReveal = nil
        quizState = nil
        followBase = nil
        if newTurn == nil { lastSnapshot = nil }
    }

    private func publish(_ h: RedDragonHint) {
        guard h != hint else { return }
        hint = h
        onChange?(h)
        for s in subscribers {
            s.handler(h)
        }
    }

    // MARK: 多订阅（T2c overlay 用；`onChange` 留给测试和单个调用方）

    private struct Subscriber {
        let token: Int
        let handler: (RedDragonHint) -> Void
    }
    private var subscribers: [Subscriber] = []
    private var nextSubscriberToken = 0

    /// 主线程。返回的 token 交给 `unsubscribe` 退订；订阅方释放时要退订（handler 里应弱引用自己）
    func subscribe(_ handler: @escaping (RedDragonHint) -> Void) -> Int {
        nextSubscriberToken += 1
        subscribers.append(Subscriber(token: nextSubscriberToken, handler: handler))
        return nextSubscriberToken
    }

    func unsubscribe(_ token: Int) {
        subscribers.removeAll { $0.token == token }
    }

    var subscriberCount: Int { return subscribers.count }
}
