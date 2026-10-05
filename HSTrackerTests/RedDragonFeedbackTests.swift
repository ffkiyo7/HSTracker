//
//  RedDragonFeedbackTests.swift
//  HSTrackerTests
//
//  T3（10-05 实测反馈）：rewind 重读后浮窗恢复、舞动前后的局面、斩杀线中途的跟手。
//  fixture 是 10-05 那份 Power.log 按 T2b 的做法截取 + 脱敏（截取命令见 T3 任务书执行结果）。
//

import XCTest
import SwiftUI
@testable import HSTracker
@testable import RedDragonCore

class RedDragonFeedbackTests: HSTrackerTests {

    override class func setUp() {
        super.setUp()
        if Cards.by(cardId: CardIds.Collectible.Rogue.Shadowstep) == nil {
            Database().loadDatabase(splashscreen: nil, withLanguages: [.enUS])
        }
    }

    private var savedActiveDeck: String?

    override func setUp() {
        super.setUp()
        savedActiveDeck = Settings.activeDeck
        let launched = Date().addingTimeInterval(30)
        while AppDelegate.instance().coreManager == nil && Date() < launched {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        XCTAssertNotNil(AppDelegate.instance().coreManager)
    }

    override func tearDown() {
        Settings.activeDeck = savedActiveDeck
        super.tearDown()
    }

    static func lines(_ fixture: String) -> [String] {
        guard let url = Bundle(for: RedDragonFeedbackTests.self).url(forResource: fixture, withExtension: "log"),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            XCTFail("fixture \(fixture) 不在测试包里")
            return []
        }
        return content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    static func makeGame(playerId: Int, deck: Deck = RedDragonLiveReplayTests.makeDeck()) -> Game {
        let game = Game(hearthstoneRunState: HearthstoneRunState(isRunning: false, isActive: false))
        game.player.id = playerId
        game.opponent.id = playerId == 1 ? 2 : 1
        game.set(activeDeck: deck, autoDetected: false)
        let deadline = Date().addingTimeInterval(5)
        while game.currentDeck == nil && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        return game
    }

    static func environment(debounce: TimeInterval, followsLine: Bool = true,
                            reveal: RDRevealLevel = .verdict) -> RedDragonAssistant.Environment {
        var env = RedDragonAssistant.Environment(
            isEnabled: { true }, revealPreference: { reveal }, quizMode: { false },
            debounce: debounce, config: RedDragonConfig(), cardName: { $0 })
        env.followsLine = followsLine
        return env
    }

    /// 线上读日志的替身：和 `LogReaderManager.processLine` 一样只把 PowerTaskList 行交给解析器，每行当一批调
    /// 挂点。碰到半稳定传送门的「回溯时间线」就照 `CoreManager.handleRewind` → `resetAndReprocess` 做：
    /// 这一批剩下的行丢掉（`requestStop`）、`game.reset(updateUI: false)`、换新的解析器，从对局开头重读，
    /// 跳过被回溯的时间段（`ignoredTimeRanges`）。`onLine` 在每行处理完、挂点调完之后回调（行号从 1 起，
    /// 第几遍读）
    struct Reread {
        var rewinds: [(line: Int, range: ClosedRange<LogDate>)] = []
    }

    @discardableResult
    static func replayWithRewinds(_ lines: [String], game: Game, playerId: Int,
                                  assistant: RedDragonAssistant?,
                                  onLine: (Int, Int, PowerGameStateParser) -> Void = { _, _, _ in }) -> Reread {
        var ignored: [ClosedRange<LogDate>] = []
        var result = Reread()
        var pass = 0
        var start = 0
        while true {
            pass += 1
            let parser = PowerGameStateParser(with: game)
            var entered = Set<LogDate>()
            var rewound = false
            for i in start..<lines.count {
                let line = lines[i]
                if let r = line.range(of: "GameState.DebugPrintGame() - PlayerID=") {
                    let parts = line[r.upperBound...].components(separatedBy: ", PlayerName=")
                    if parts.count == 2, let pid = Int(parts[0]) {
                        let name = parts[1].trimmingCharacters(in: .whitespaces)
                        if pid == playerId { game.player.name = name } else { game.opponent.name = name }
                    }
                    continue
                }
                guard line.contains("PowerTaskList.DebugPrintPower") else { continue }
                let logLine = LogLine(namespace: .power, line: line)
                if LogReaderManager.isRewound(logLine, ranges: ignored, entered: &entered) { continue }
                if line.contains("CREATE_GAME") {
                    game.isInMenu = false
                    game.gameEnded = false
                }
                // 解析器在这一行调 `coreManager.handleRewind`（宿主 app 的那个）：测试里自己接，先把触发条件拿掉
                var rewind: ClosedRange<LogDate>?
                if line.contains("BLOCK_START"), line.contains("cardId=TIME_000tb"),
                   let play = game.lastPlayBlockTime, logLine.time >= play {
                    rewind = play ... logLine.time
                    game.lastPlayBlockTime = nil
                }
                parser.handle(logLine: logLine)
                if game.player.id != playerId && line.contains("tag=STEP value=") {
                    game.player.id = playerId
                    game.opponent.id = playerId == 1 ? 2 : 1
                }
                assistant?.parserBatchDidEnd(game, linesProcessed: true, idle: parser.currentBlock == nil)
                onLine(i + 1, pass, parser)
                if let rewind {
                    ignored.append(rewind)
                    result.rewinds.append((i + 1, rewind))
                    rewound = true
                    break
                }
            }
            guard rewound else { break }
            game.reset(updateUI: false)
            game.player.id = playerId
            game.opponent.id = playerId == 1 ? 2 : 1
            start = 0
        }
        return result
    }

    /// 10-05 的五局（有连招或舞动的）：fixture、我方 PlayerID
    static let games: [(fixture: String, playerId: Int)] = [
        ("2026-10-05-g1-first", 1), ("2026-10-05-g2-dance-lost", 2), ("2026-10-05-g4-dance-won", 2),
        ("2026-10-05-g6-first", 1), ("2026-10-05-g7-rewind", 2)
    ]

    /// 我方回合里的一致边界（一个顶层 BLOCK 刚结束、解析器空闲），和线上挂点同一判据。只留最后一遍读的
    struct Boundary {
        var line: Int
        /// 刚结束的顶层 BLOCK_START 行（不是 BLOCK 结束的边界为空）
        var block: String
        var snapshot: RDGameSnapshot
    }

    static func walk(_ fixture: String, playerId: Int) -> [Boundary] {
        let lines = Self.lines(fixture)
        let game = makeGame(playerId: playerId)
        var byPass: [Int: [Boundary]] = [:]
        var topBlock = ""
        var wasIdle = true
        replayWithRewinds(lines, game: game, playerId: playerId, assistant: nil) { n, pass, parser in
            let line = lines[n - 1]
            if wasIdle && line.contains("BLOCK_START") { topBlock = line }
            let idle = parser.currentBlock == nil
            defer { wasIdle = idle }
            guard idle, line.contains("BLOCK_END") || line.contains("tag=STEP value=MAIN_ACTION"),
                  RDGameSnapshot.playerEntity(game: game)?.isCurrentPlayer == true,
                  let snap = RDGameSnapshot.capture(game: game) else { return }
            if let last = byPass[pass]?.last, last.snapshot == snap { return }
            byPass[pass, default: []].append(Boundary(
                line: n, block: line.contains("BLOCK_END") ? topBlock : "", snapshot: snap))
        }
        return byPass[byPass.keys.max() ?? 0] ?? []
    }

    static func blockCard(_ block: String) -> String {
        guard let type = block.range(of: "BlockType=")?.upperBound else { return "-" }
        let t = block[type...].prefix { $0 != " " }
        let card = block.range(of: "cardId=").map { block[$0.upperBound...].prefix { $0 != " " } } ?? ""
        return "\(t):\(card)"
    }

    /// 一个边界上线上会给的结论（确定性配置，结论和墙钟无关）
    static func analyze(_ b: Boundary) -> (live: RDLiveState, result: RedDragonResult, analysis: RDAnalysis) {
        let live = RDStateReader.read(b.snapshot)
        let result = RedDragonSearch.solve(live.state, config: RedDragonLiveReplayTests.deterministic)
        let a = RDHintBuilder.analyze(snapshot: b.snapshot, live: live, result: result, cardName: { $0 })
        return (live, result, a)
    }

    static func boundary(_ bs: [Boundary], line: Int, file: StaticString = #filePath,
                         lineNo: UInt = #line) -> Boundary? {
        guard let b = bs.first(where: { $0.line == line }) else {
            XCTFail("没有第 \(line) 行的边界；有：\(bs.map { $0.line })", file: file, line: lineNo)
            return nil
        }
        return b
    }

    // MARK: - 问题 2：rewind 重读后浮窗恢复

    /// 第 7 局两次「回溯时间线」，每次都从对局开头重读。修前第二次重读把被回溯的 PLAY 之前、同一时间戳的两个
    /// BLOCK_END 也跳了，解析器一直在没闭合的 BLOCK 里，之后再没有一致边界（T11 / T13 一个局面都没投递）；
    /// 重读时 GAME_RESET 的「FULL_ENTITY - Updating 玩家名」又造了一个编号 0、带 PLAYER_ID 的实体，
    /// 上游 `Game.playerEntity` 会挑中它，局面拍不出来
    ///
    /// 走的是 `replayWithRewinds` 这个替身，不是真的 `CoreManager.handleRewind` → `resetAndReprocess`：那条路径
    /// 停掉并重建测试宿主自己的 `LogReaderManager`，从磁盘上炉石日志目录的 Power.log 重读、写宿主的
    /// `coreManager.game`，测试里没法换成 fixture（要改上游加注入点）。替身照它的步骤做（丢掉这一批剩下的行、
    /// `game.reset`、新解析器、从头重读、跳过 `ignoredTimeRanges`），跳过判断用的就是生产的 `LogReaderManager.isRewound`
    func testRewindRereadKeepsFeeding() {
        let lines = Self.lines("2026-10-05-g7-rewind")
        let game = Self.makeGame(playerId: 2)
        let assistant = RedDragonAssistant(environment: Self.environment(debounce: 0.12), recordsFeeds: true)
        // 上屏的结论：(局面的回合, 结论)。只记已提交、不过时的
        var committed: [(turn: Int, verdict: RDLethalVerdict?)] = []
        let token = assistant.subscribe { h in
            guard h.phase == .ready, !h.isStale, case .snapshot(let s)? = assistant.fedInputs.last else { return }
            committed.append((s.turn, h.analysis?.verdict))
        }
        defer { assistant.unsubscribe(token) }
        var rewindsSeen = 0
        let r = Self.replayWithRewinds(lines, game: game, playerId: 2, assistant: assistant) { n, _, parser in
            if lines[n - 1].contains("cardId=TIME_000tb") && lines[n - 1].contains("BLOCK_START") { rewindsSeen += 1 }
            // 第二次重读之后、我方 T11 / T13 的一致边界上等结论上来
            guard rewindsSeen == 2, parser.currentBlock == nil,
                  [11, 13].contains(game.gameEntity?[.turn] ?? 0) else { return }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.002))
            let deadline = Date().addingTimeInterval(10)
            while Date() < deadline && (assistant.hint.phase == .computing || assistant.hint.isStale) {
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.002))
            }
        }
        XCTAssertEqual(r.rewinds.count, 2)
        XCTAssertNotEqual(RDGameSnapshot.playerEntity(game: game)?.id ?? 0, 0, "不能挑中重置时造的编号 0 实体")
        // 两回合都判过可斩杀（第 7 局 T11 / T13 都是斩杀回合，见问题 3 的结论表）
        for turn in [11, 13] {
            XCTAssertTrue(committed.contains { $0.turn == turn && $0.verdict == .lethal },
                          "T\(turn) 要有「可斩杀」的结论上屏，实际：\(committed.filter { $0.turn == turn }.map { "\(String(describing: $0.verdict))" })")
        }
    }

    /// 被回溯的时间段从那个 PLAY 的 BLOCK_START 开始；同一时间戳、写在它前面的 PowerTaskList 行照常读
    func testRewoundRangeStartsAtThePlayBlock() throws {
        let lines = Self.lines("2026-10-05-g7-rewind")
        let r = Self.replayWithRewinds(lines, game: Self.makeGame(playerId: 2), playerId: 2, assistant: nil)
        XCTAssertEqual(r.rewinds.count, 2)
        for rewind in r.rewinds {
            var entered = Set<LogDate>()
            var kept: [String] = []
            var firstSkipped: String?
            for line in lines where line.contains("PowerTaskList.DebugPrintPower") {
                let l = LogLine(namespace: .power, line: line)
                guard l.time == rewind.range.lowerBound else { continue }
                if LogReaderManager.isRewound(l, ranges: [rewind.range], entered: &entered) {
                    if firstSkipped == nil { firstSkipped = line }
                } else {
                    XCTAssertNil(firstSkipped, "跳过开始之后同一时间戳的行也要跳：\(line)")
                    kept.append(line)
                }
            }
            let skipped = try XCTUnwrap(firstSkipped)
            XCTAssertTrue(skipped.contains("BLOCK_START BlockType=PLAY"), skipped)
            if rewind.line == r.rewinds[1].line {
                XCTAssertEqual(kept.filter { $0.contains("BLOCK_END") }.count, 2, "第二次回溯：PLAY 之前的两个 BLOCK_END 要读")
            }
        }
        // 时间段里其余的行照旧跳过
        var entered = Set<LogDate>()
        let inside = try XCTUnwrap(lines.first { line in
            guard line.contains("PowerTaskList.DebugPrintPower") else { return false }
            let t = LogLine(namespace: .power, line: line).time
            return r.rewinds[0].range.contains(t) && t > r.rewinds[0].range.lowerBound
        })
        XCTAssertTrue(LogReaderManager.isRewound(LogLine(namespace: .power, line: inside),
                                                 ranges: r.rewinds.map { $0.range }, entered: &entered))
    }

    // MARK: - 问题 3：舞动前后

    /// 殒命暗影变身（CHANGE_ENTITY）后按变成的牌读：第 4 局 T11 手里的殒命暗影先变致聋术、再变舞动全场，
    /// 修前按 cardId 还读成殒命暗影，少了第二张舞动，可斩杀 → 未搜到斩杀
    func testShadowOfDemiseIsReadAsTheSpellItBecame() throws {
        let bs = Self.walk("2026-10-05-g4-dance-won", playerId: 2)
        let b = try XCTUnwrap(Self.boundary(bs, line: 16181))
        let r = Self.analyze(b)
        XCTAssertTrue(r.live.state.hand.contains { $0.isShadowOfDemise && $0.card == .bounceAround },
                      "殒命暗影此刻是舞动全场")
        XCTAssertEqual(r.analysis.verdict, .lethal)
    }

    func testFourthGameSecondDanceKeepsLethal() throws {
        let bs = Self.walk("2026-10-05-g4-dance-won", playerId: 2)
        let index = try XCTUnwrap(bs.firstIndex {
            $0.snapshot.turn == 13 && $0.block.contains("BlockType=PLAY")
                && $0.block.contains("cardId=ETC_079 ")
        })
        XCTAssertGreaterThan(index, 0)
        guard index > 0 else { return }
        for b in [bs[index - 1], bs[index]] {
            XCTAssertEqual(Self.analyze(b).analysis.verdict, .lethal, "第4局 T13 舞动前后，行\(b.line)")
        }
    }

    /// 第 2 局 T13：用户打出暗影步后殒命暗影变成了暗影步，修前读错 → 未搜到斩杀；修后到用户把阿莱指向
    /// 自己英雄之前一直可斩杀
    func testSecondGameStaysLethalUntilTheUserDeviates() throws {
        let bs = Self.walk("2026-10-05-g2-dance-lost", playerId: 2)
        for line in [14085, 14989, 15813] {
            let b = try XCTUnwrap(Self.boundary(bs, line: line))
            XCTAssertEqual(Self.analyze(b).analysis.verdict, .lethal, "第 \(line) 行")
        }
    }

    /// 第 7 局 T13：施法者复制的 1/1 阿莱被暗影步弹回是 7 费，不是 1 费。修前给的线「暗影步 → 1/1 阿莱复制体，
    /// 再打 1 费阿莱」打不出来；修后线弹的是场上 8/8 那张，用户偏离后判不能斩杀
    func testSeventhGameCopyBounceLine() throws {
        let bs = Self.walk("2026-10-05-g7-rewind", playerId: 2)
        let before = try XCTUnwrap(Self.boundary(bs, line: 30183))
        let r = Self.analyze(before)
        XCTAssertEqual(r.analysis.verdict, .lethal)
        let line = try XCTUnwrap(r.result.lethalLines.first)
        let outcome = try RDReplay.run(line.actions, from: r.live.state)
        XCTAssertLessThanOrEqual(outcome.finalState.opponent.health, 0)
        let copies = Set(r.live.state.board.filter { $0.statsSetTo1x1 }.map { $0.entityId })
        for action in line.actions {
            guard case let .play(_, identity, target, _, _) = action, identity == .shadowstep,
                  case let .friendlyMinion(id) = target else { continue }
            XCTAssertFalse(copies.contains(id), "不再拿 1/1 复制体当暗影步的目标")
        }
        let after = try XCTUnwrap(Self.boundary(bs, line: 30418))
        XCTAssertNotEqual(Self.analyze(after).analysis.verdict, .lethal)
    }

    // MARK: - 问题 1：跟手（接着用屏上的线）

    /// 和线上一样：每个判「可斩杀」的边界留下所有不靠抽牌的斩杀线，下一个边界先试着接着用（屏上那条优先）。
    /// 接上的每一个局面独立搜索也要判可斩杀，接着用的线在真实局面上重放能打死
    func testContinuationFollowsLethalLines() {
        var followed = 0
        var optionalMarks = 0
        for g in Self.games {
            var base: (candidates: [(root: RDState, line: RedDragonLine)], turn: Int)?
            for b in Self.walk(g.fixture, playerId: g.playerId) {
                let live = RDStateReader.read(b.snapshot)
                if let bb = base, bb.turn == b.snapshot.turn {
                    let resumed = RDContinuation.resumeAll(bb.candidates, onto: live.state)
                    if let shown = resumed.first {
                        followed += 1
                        for r in resumed {
                            XCTAssertEqual(r.root.nextEntityId, shown.root.nextEntityId, "接上的线共用一个根局面")
                            let outcome = try? RDReplay.run(r.line.actions, from: shown.root)
                            XCTAssertLessThanOrEqual(outcome?.finalState.opponent.health ?? 1, 0, "\(g.fixture) 行\(b.line)")
                        }
                        // 必打 / 可选按全部接上的线算：只在部分线里打的手牌是可选
                        var l = live
                        l.state = shown.root
                        let a = RDHintBuilder.analyze(snapshot: b.snapshot, live: l,
                                                      result: RDContinuation.result(resumed.map { $0.line }, root: l.state),
                                                      cardName: { $0 })
                        let used = resumed.map { Set(RDLineWalker.handEntitiesPlayed($0.line.actions, root: shown.root)) }
                        let every = used.dropFirst().reduce(used[0]) { $0.intersection($1) }
                        for m in a.handMarks {
                            XCTAssertEqual(m.role, every.contains(m.entityId) ? .required : .optional,
                                           "\(g.fixture) 行\(b.line) #\(m.entityId)")
                        }
                        optionalMarks += a.handMarks.filter { $0.role == .optional }.count
                        XCTAssertEqual(Self.analyze(b).analysis.verdict, .lethal, "\(g.fixture) 行\(b.line)：接着用的局面搜索也要认")
                        base = (resumed.map { ($0.root, $0.line) }, b.snapshot.turn)
                        continue
                    }
                }
                let a = Self.analyze(b)
                let det = a.result.lethalLines.filter { !RDLineWalker.dependsOnDraw($0.actions, root: a.live.state) }
                base = a.analysis.verdict == .lethal && !det.isEmpty
                    ? (det.map { (a.live.state, $0) }, b.snapshot.turn) : nil
            }
        }
        XCTAssertGreaterThan(followed, 20, "10-05 五局里斩杀线中途照线打的局面")
        XCTAssertGreaterThan(optionalMarks, 0, "接上多条线时要有可选牌（只交第一条线时全是必打）")
    }

    /// 真实局面和线推出来的任何一步都对不上（这里：敌方血量不同）就不接
    func testContinuationRejectsADeviatedState() throws {
        let bs = Self.walk("2026-10-05-g2-dance-lost", playerId: 2)
        let a = Self.analyze(try XCTUnwrap(Self.boundary(bs, line: 14085)))
        let line = try XCTUnwrap(a.result.lethalLines.first)
        let next = try RDEngine.apply(line.actions[0], to: a.live.state)
        XCTAssertEqual(RDContinuation.resume(line, from: a.live.state, onto: next)?.stepsTaken, 1)
        var off = next
        off.opponent.health += 1
        XCTAssertNil(RDContinuation.resume(line, from: a.live.state, onto: off))
    }

    /// 线上流程：照线打的局面不等去抖、不搜索就提交。去抖设成 3 秒，每次提交量「挂点 → 提交」的墙钟：
    /// 接着用的都在 1 秒内；搜索的都不早于去抖（证明接着用那几次没走去抖 + 搜索）
    func testAssistantCommitsFollowedLinesWithoutSearching() {
        let debounce: TimeInterval = 3
        let lines = Self.lines("2026-10-05-g2-dance-lost")
        let game = Self.makeGame(playerId: 2)
        let assistant = RedDragonAssistant(environment: Self.environment(debounce: debounce), recordsFeeds: true)
        var scheduledAt: Date?
        var scheduled = 0, followed = 0
        var followedLatencies: [TimeInterval] = [], searchedLatencies: [TimeInterval] = []
        // 在提交的那个主线程 block 里回调；schedule 每次都作废前一次，提交的一定是最近一次调度的
        let token = assistant.subscribe { h in
            guard h.phase == .ready, !h.isStale, let at = scheduledAt else { return }
            let elapsed = Date().timeIntervalSince(at)
            if assistant.followedComputations > followed {
                followedLatencies.append(elapsed)
            } else {
                searchedLatencies.append(elapsed)
            }
            followed = assistant.followedComputations
            scheduledAt = nil
        }
        defer { assistant.unsubscribe(token) }
        Self.replayWithRewinds(lines, game: game, playerId: 2, assistant: assistant) { _, _, parser in
            guard parser.currentBlock == nil, (game.gameEntity?[.turn] ?? 0) == 13 else { return }
            // 挂点刚调完；调度在投递那一跳 main.async 里，跑一下 runloop 之后才看得到。从挂点算起（不早于调度）
            let hooked = Date()
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.002))
            if assistant.scheduledComputations > scheduled {
                scheduled = assistant.scheduledComputations
                scheduledAt = hooked
            }
            let deadline = Date().addingTimeInterval(15)
            while Date() < deadline && (assistant.hint.phase == .computing || assistant.hint.isStale) {
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.002))
            }
        }
        XCTAssertFalse(searchedLatencies.isEmpty, "T13 第一个「可斩杀」要搜出来")
        XCTAssertGreaterThan(followedLatencies.count, 0)
        XCTAssertLessThan(followedLatencies.max() ?? 0, 1, "接着用不等去抖（\(debounce) 秒）")
        XCTAssertGreaterThanOrEqual(searchedLatencies.min() ?? debounce, debounce, "搜索的要先等满去抖")
    }

    // MARK: - 问题 1：跟手延迟实测（按需开）

    /// 要量的回合：判过「可斩杀」的我方回合（五局里一共 6 个；第 6 局没有）
    static let followTurns: [(fixture: String, playerId: Int, turns: Set<Int>)] = [
        ("2026-10-05-g1-first", 1, [13]), ("2026-10-05-g2-dance-lost", 2, [13]),
        ("2026-10-05-g4-dance-won", 2, [11, 13]), ("2026-10-05-g7-rewind", 2, [11, 13])
    ]

    struct StepLatency {
        var fixture: String
        var turn: Int
        var line: Int
        var block: String
        /// 墙钟：这一步最后一个一致边界投递 → 它的结论上屏（view model 提交 + layout + display 完）。
        /// nil = 用户下一次点击之前没上屏（结论被下一步的局面作废了）
        var delay: Double?
        /// assistant 提交 → view model 提交并完成离屏 layout/display。
        var commitToDisplay: Double?
        /// 日志时间：这一步在 PowerTaskList 里写完 → 用户下一次点击（`SendOption`）
        var userGap: Double?
        /// 日志时间：GameState 里这一步的顶层 BLOCK_END → PowerTaskList 里这一步写完（炉石自己的动画排队）
        var hsLag: Double?
        /// 日志时间：点击 → GameState 顶层 BLOCK_END（服务器往返）
        var serverLag: Double?
        /// 点这一步的那一刻（墙钟），屏上已提交、且对应当时最新局面的结论是「可斩杀」
        var lethalBefore: Bool
        /// 这一步的结论走的是「接着用」
        var followed: Bool
        /// 这一步的结论在用户下一次点击（墙钟）之前上屏了。nil = 后面没有点击
        var shownBeforeNextClick: Bool?
    }

    static func absolute(_ d: LogDate) -> Double {
        return d.date.timeIntervalSince1970 + Double(d.subseconds) / 1e7
    }

    /// 实时回放一局里要量的回合：真的 assistant（线上去抖 / 配置）+ 真的 view model + NSHostingView 画面。
    /// PowerTaskList 行按日志时间间隔喂（同一时间戳的行一批，批尾调挂点）；流水线空闲（屏上已是最新结论、
    /// 没有在算的）时跳过等待，不改变结果、省掉用户思考的时间。只在要量的回合里调挂点
    func measureFollow(_ fixture: String, playerId: Int, turns: Set<Int>, followsLine: Bool) -> [StepLatency] {
        let lines = Self.lines(fixture)
        let ignored = Self.replayWithRewinds(lines, game: Self.makeGame(playerId: playerId), playerId: playerId,
                                             assistant: nil).rewinds.map { $0.range }
        let game = Self.makeGame(playerId: playerId)
        let assistant = RedDragonAssistant(environment: Self.environment(debounce: 0.12, followsLine: followsLine,
                                                                         reveal: .order),
                                           recordsFeeds: true)
        let vm = RedDragonOverlayViewModel(assistant: assistant, cardName: { $0 })
        let size = CGSize(width: 1920, height: 1080)
        let hosting = NSHostingView(rootView: RedDragonOverlayView(viewModel: vm, canvasSize: size))
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        func now() -> Double { return CFAbsoluteTimeGetCurrent() }

        struct Commit { var wall: Double; var shown: Double; var fed: Int; var verdict: RDLethalVerdict?; var followed: Bool }
        var commits: [Commit] = []
        var followedSoFar = 0
        let token = assistant.subscribe { h in
            guard h.phase == .ready, !h.isStale else { return }
            let wall = now()
            let fed = assistant.fedInputs.count
            let followed = assistant.followedComputations > followedSoFar
            followedSoFar = assistant.followedComputations
            let verdict = h.analysis?.verdict
            // view model 先订阅，它的 main.async 提交排在这一块前面：这里画的就是新结论
            DispatchQueue.main.async {
                hosting.layoutSubtreeIfNeeded()
                hosting.display()
                commits.append(Commit(wall: wall, shown: now(), fed: fed, verdict: verdict, followed: followed))
            }
        }
        defer {
            assistant.unsubscribe(token)
            window.contentView = nil
        }
        func busy() -> Bool {
            let h = assistant.hint
            return h.phase == .computing || h.isStale || vm.model != RDOverlayModel.make(h, cardName: { $0 })
        }
        func pump(until: Double) {
            repeat {
                RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.001))
            } while now() < until && busy()
        }

        // 每行之后下一条 PowerTaskList 行的时间戳（判断一批在哪结束）
        var nextStamp = [Substring](repeating: "", count: lines.count + 1)
        for i in stride(from: lines.count - 1, through: 0, by: -1) {
            nextStamp[i] = lines[i].contains("PowerTaskList.DebugPrintPower") ? lines[i].prefix(18) : nextStamp[i + 1]
        }

        struct Feed { var wall: Double; var line: Int; var log: Double; var fed: Int; var turn: Int }
        var feeds: [Feed] = []
        // 点击：行号、日志时间、回放到这一行时的墙钟（PowerTaskList 行按日志间隔实时喂，GameState 行按文件顺序夹在
        // 中间，读到它的那一刻就是它在回放里的时刻）
        var sends: [(line: Int, log: Double, wall: Double, turn: Int)] = []
        var gsEnds: [(line: Int, log: Double)] = []
        var gsDepth = 0
        var anchor: (log: Double, wall: Double)?
        var measuring = false
        let parser = PowerGameStateParser(with: game)
        var entered = Set<LogDate>()
        for i in 0..<lines.count {
            let line = lines[i]
            if let r = line.range(of: "GameState.DebugPrintGame() - PlayerID=") {
                let parts = line[r.upperBound...].components(separatedBy: ", PlayerName=")
                if parts.count == 2, let pid = Int(parts[0]) {
                    let name = parts[1].trimmingCharacters(in: .whitespaces)
                    if pid == playerId { game.player.name = name } else { game.opponent.name = name }
                }
                continue
            }
            if line.contains(" GameState.") {
                guard measuring else { continue }
                let t = Self.absolute(LogLine(namespace: .power, line: line).time)
                if line.contains("GameState.SendOption()") {
                    // 这一刻之前该到的 PowerTaskList 行已经按节奏喂了；按日志时间等到点击时刻再记
                    if let a = anchor { pump(until: a.wall + (t - a.log)) }
                    sends.append((i + 1, t, now(), game.gameEntity?[.turn] ?? 0))
                } else if line.contains("GameState.DebugPrintPower() -") {
                    if line.contains("BLOCK_START") {
                        gsDepth += 1
                    } else if line.contains("BLOCK_END") {
                        gsDepth = max(0, gsDepth - 1)
                        if gsDepth == 0 { gsEnds.append((i + 1, t)) }
                    }
                }
                continue
            }
            guard line.contains("PowerTaskList.DebugPrintPower") else { continue }
            let logLine = LogLine(namespace: .power, line: line)
            if LogReaderManager.isRewound(logLine, ranges: ignored, entered: &entered) { continue }
            if line.contains("CREATE_GAME") {
                game.isInMenu = false
                game.gameEnded = false
            }
            if line.contains("BLOCK_START"), line.contains("cardId=TIME_000tb") { game.lastPlayBlockTime = nil }
            let t = Self.absolute(logLine.time)
            if measuring {
                if let a = anchor { pump(until: a.wall + (t - a.log)) }
                anchor = (t, now())
            }
            parser.handle(logLine: logLine)
            if game.player.id != playerId && line.contains("tag=STEP value=") {
                game.player.id = playerId
                game.opponent.id = playerId == 1 ? 2 : 1
            }
            let turn = game.gameEntity?[.turn] ?? 0
            let inTurn = turns.contains(turn)
            if measuring && !inTurn {
                pump(until: now() + 10)
                anchor = nil
                gsDepth = 0
            }
            // 量完就停：读到对局结束会走 `Game.gameEnd` → HearthMirror 取对局信息，测试进程里会崩
            if turn > turns.max() ?? 0 { break }
            measuring = inTurn
            guard measuring, nextStamp[i + 1] != line.prefix(18) else { continue }
            let before = assistant.fedInputs.count
            let wall = now()
            assistant.parserBatchDidEnd(game, linesProcessed: true, idle: parser.currentBlock == nil)
            let fed = assistant.fedInputs
            if fed.count > before, case .snapshot(let s)? = fed.last {
                feeds.append(Feed(wall: wall, line: i + 1, log: t, fed: fed.count, turn: s.turn))
            }
            RunLoop.current.run(mode: .default, before: Date())
        }
        pump(until: now() + 10)

        var out: [StepLatency] = []
        for (k, s) in sends.enumerated() {
            let nextLine = k + 1 < sends.count ? sends[k + 1].line : Int.max
            let mine = feeds.filter { $0.line > s.line && $0.line < nextLine && $0.turn == s.turn }
            guard let last = mine.last else { continue }
            let c = commits.first { $0.fed == last.fed }
            let gsEnd = gsEnds.last { $0.line > s.line && $0.line < last.line }
            // 点击那一刻（墙钟）屏上是什么：那之前最后一次上屏的结论，且它对应的是那之前最后一次投递的局面
            let shownAtClick = commits.last { $0.shown <= s.wall }
            let fedAtClick = feeds.last { $0.wall <= s.wall }?.fed
            let before = shownAtClick?.fed == fedAtClick ? shownAtClick : nil
            let nextClick = k + 1 < sends.count && sends[k + 1].turn == s.turn ? sends[k + 1] : nil
            let nextClickWall = nextClick?.wall
            let block = lines[s.line..<last.line].first {
                $0.contains("PowerTaskList.DebugPrintPower() - BLOCK_START")
            } ?? ""
            out.append(StepLatency(
                fixture: fixture, turn: last.turn, line: last.line, block: Self.blockCard(block),
                delay: c.map { $0.shown - last.wall },
                commitToDisplay: c.map { $0.shown - $0.wall },
                userGap: nextClick.map { $0.log - last.log },
                hsLag: gsEnd.map { last.log - $0.log }, serverLag: gsEnd.map { $0.log - s.log },
                lethalBefore: before?.verdict == .lethal, followed: c?.followed ?? false,
                shownBeforeNextClick: nextClickWall.map { w in c.map { $0.shown <= w } ?? false }))
        }
        return out
    }

    static func quantiles(_ xs: [Double]) -> String {
        guard !xs.isEmpty else { return "无样本" }
        let s = xs.sorted()
        func q(_ p: Double) -> Double { return s[min(s.count - 1, Int(Double(s.count - 1) * p + 0.5))] }
        return String(format: "n=%d 中位 %.0f ms / p90 %.0f ms / 最慢 %.0f ms", s.count, q(0.5) * 1000, q(0.9) * 1000, s.last! * 1000)
    }

    /// 问题 1 的实测（改前 = 关掉「接着用」，改后 = 打开；其余同一套代码、同一口径）。
    /// 实时回放，跑一遍十几分钟，平时跳过：`TEST_RUNNER_HSTRACKER_RDR_LATENCY=1` 加在构建命令前开
    func testFollowLatency() throws {
        guard ProcessInfo.processInfo.environment["HSTRACKER_RDR_LATENCY"] != nil else {
            throw XCTSkip("实时回放，按需开：TEST_RUNNER_HSTRACKER_RDR_LATENCY=1")
        }
        var comparisons: [[StepLatency]] = []
        for follows in [false, true] {
            var all: [StepLatency] = []
            for g in Self.followTurns {
                all += measureFollow(g.fixture, playerId: g.playerId, turns: g.turns, followsLine: follows)
            }
            let tag = follows ? "改后" : "改前"
            comparisons.append(all)
            for s in all {
                print(String(format: "[lat] %@ %@ T%d 行%d %@ 斩杀线中%@ 上屏 %@ 接着用%@ 下一次点击 %@ 炉石动画 %@ 服务器 %@",
                             tag, s.fixture, s.turn, s.line, s.block, s.lethalBefore ? "是" : "否",
                             s.delay.map { String(format: "%.0fms", $0 * 1000) } ?? "-", s.followed ? "是" : "否",
                             s.userGap.map { String(format: "%.2fs", $0) } ?? "-",
                             s.hsLag.map { String(format: "%.2fs", $0) } ?? "-",
                             s.serverLag.map { String(format: "%.2fs", $0) } ?? "-"))
            }
            let online = all.filter { $0.lethalBefore }
            let delays = online.compactMap { $0.delay }
            let late = online.filter { $0.shownBeforeNextClick == false }.count
            print("[lat] \(tag) 斩杀线中途的步：\(Self.quantiles(delays))；没在下一次点击前上屏 \(late) / \(online.count) 步；"
                  + "接着用 \(online.filter { $0.followed }.count) 步")
            print("[lat] \(tag) 炉石动画（GameState 写完 → PowerTaskList 写完）：\(Self.quantiles(online.compactMap { $0.hsLag }))")
            print("[lat] \(tag) 服务器（点击 → GameState 写完）：\(Self.quantiles(online.compactMap { $0.serverLag }))")
            print("[lat] \(tag) 用户节奏（这一步写完 → 下一次点击）：\(Self.quantiles(online.compactMap { $0.userGap }))")
            print("[lat] \(tag) 提交到绘制：\(Self.quantiles(online.compactMap { $0.commitToDisplay }))")
        }
        // 同一批步骤比较：两次回放点击当时都已显示斩杀，避免优化改变样本集合而造成假改善。
        func key(_ s: StepLatency) -> String { "\(s.fixture):\(s.line)" }
        let common = Set(comparisons[0].filter { $0.lethalBefore }.map(key))
            .intersection(comparisons[1].filter { $0.lethalBefore }.map(key))
        XCTAssertFalse(common.isEmpty)
        for (i, rows) in comparisons.enumerated() {
            let same = rows.filter { common.contains(key($0)) }
            print("[lat] 同步骤 \(i == 0 ? "改前" : "改后")：\(Self.quantiles(same.compactMap { $0.delay }))；"
                  + "下一次点击前未上屏 \(same.filter { $0.shownBeforeNextClick == false }.count)/\(same.count)")
            let endToEnd = same.compactMap { s -> Double? in
                guard let lag = s.hsLag, let delay = s.delay else { return nil }
                return lag + delay
            }
            print("[lat] 同步骤 GameState 完成到绘制：\(Self.quantiles(endToEnd))")
        }
    }
}
