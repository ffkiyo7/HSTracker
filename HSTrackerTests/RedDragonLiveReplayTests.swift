//
//  RedDragonLiveReplayTests.swift
//  HSTrackerTests
//
//  T2b 离线回放：真实对局的 Power.log（2026-10-01，致聋双闪避）喂进解析器，在我方每个回合的
//  MAIN_ACTION（抽完牌、还没出牌）跑「读取 → 搜索 → 展示模型」，对人工核过的回合下断言。
//  fixture 是 LogReaderManager 过滤后的原始行，截取命令见 T2b 任务书执行结果。
//  和线上一样只把 PowerTaskList 行交给解析器（LogReaderManager.processLine）。
//

import XCTest
@testable import HSTracker
@testable import RedDragonCore

class RedDragonLiveReplayTests: HSTrackerTests {

    /// 牌组代码 AAEBAYHmBwrc…（spike 六）解出来的 30 张 + E.T.C. 乐队
    static let deckList: [(String, Int)] = [
        ("CFM_630", 2), ("CORE_EX1_145", 2), ("EX1_144", 2), ("CORE_RLK_567", 1), ("TSC_916", 1),
        ("TOY_510", 2), ("JAM_022", 1), ("DED_004", 1), ("TLC_515", 2), ("CORE_DMF_511", 1),
        ("DEEP_014", 2), ("DMF_515", 2), ("REV_939", 2), ("LOOT_214", 2), ("CATA_111", 1),
        ("WC_016", 2), ("ETC_080", 1), ("BAR_552", 1), ("TRL_092", 1), ("OG_291", 1)
    ]
    static let band = ["ETC_079", "SCH_352", "LEG_CS3_031"]

    struct Checkpoint {
        var turn: Int
        var snapshot: RDGameSnapshot
        var live: RDLiveState
        var result: RedDragonResult
        var analysis: RDAnalysis
        /// 读取 + 搜索的线程 CPU 秒（Debug）
        var cpu: Double
        /// 这一回合结束时对方的有效血量（下一个对方回合的 MAIN_ACTION 读到的）；对局在这回合结束时为 nil
        var opponentAfter: Int?
    }

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
        // `blockStart` 经由 `AppDelegate.instance().coreManager`，宿主 app 启动完才有
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

    static func makeDeck() -> Deck {
        let deck = Deck()
        deck.name = "red dragon replay"
        deck.playerClass = .rogue
        for (id, count) in deckList {
            deck.cards.append(RealmCard(id: id, count: count))
        }
        let sideboard = RealmSideboard(ownerCardId: CardIds.Collectible.Neutral.ETCBandManager)
        for id in band { sideboard.cards.append(RealmCard(id: id, count: 1)) }
        deck.sideboards.append(sideboard)
        return deck
    }

    /// 喂完整局，在我方每个 MAIN_ACTION 停下来算一次
    func replay(_ fixture: String, playerId: Int,
                config: RedDragonConfig = RedDragonConfig()) -> [Checkpoint] {
        guard let url = Bundle(for: RedDragonLiveReplayTests.self).url(forResource: fixture, withExtension: "log"),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            XCTFail("fixture \(fixture) 不在测试包里")
            return []
        }
        let game = Game(hearthstoneRunState: HearthstoneRunState(isRunning: false, isActive: false))
        let parser = PowerGameStateParser(with: game)
        game.player.id = playerId
        game.opponent.id = playerId == 1 ? 2 : 1
        game.set(activeDeck: Self.makeDeck(), autoDetected: false)
        let deadline = Date().addingTimeInterval(5)
        while game.currentDeck == nil && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        XCTAssertNotNil(game.currentDeck)
        if let deck = game.currentDeck { XCTAssertTrue(RDDeckGate.isRedDragonDeck(deck)) }

        var out: [Checkpoint] = []
        for raw in content.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(raw)
            // 线上玩家名来自 HearthMirror（MatchInfo），回放用 DebugPrintGame 的 PlayerName 行代替，
            // 否则 `Entity=名字` 的 TAG_CHANGE（CURRENT_PLAYER 等）认不到玩家实体
            if let r = line.range(of: "GameState.DebugPrintGame() - PlayerID=") {
                let rest = line[r.upperBound...]
                let parts = rest.components(separatedBy: ", PlayerName=")
                if parts.count == 2, let pid = Int(parts[0]) {
                    let name = parts[1].trimmingCharacters(in: .whitespaces)
                    if pid == playerId { game.player.name = name } else { game.opponent.name = name }
                }
                continue
            }
            guard line.contains("PowerTaskList.DebugPrintPower") else { continue }
            parser.handle(logLine: LogLine(namespace: .power, line: line))
            guard line.contains("tag=STEP value=MAIN_ACTION") else { continue }
            // CREATE_GAME 会把玩家 id 清掉（线上靠 GameAccountId / 名字认回来，回放没有这条路）
            if game.player.id != playerId {
                game.player.id = playerId
                game.opponent.id = playerId == 1 ? 2 : 1
            }
            guard let snap = RDGameSnapshot.capture(game: game) else {
                XCTFail("T\(game.turnNumber()) 拷不出快照")
                continue
            }
            if !snap.isPlayerTurn {
                if !out.isEmpty && out[out.count - 1].opponentAfter == nil {
                    out[out.count - 1].opponentAfter = snap.opponentHeroHealth + snap.opponentHeroArmor
                }
                continue
            }
            let t0 = RedDragonSearch.threadCPUTime()
            let live = RDStateReader.read(snap)
            let result = RedDragonSearch.solve(live.state, config: config)
            let cpu = RedDragonSearch.threadCPUTime() - t0
            let analysis = RDHintBuilder.analyze(snapshot: snap, live: live, result: result,
                                                 cardName: { Cards.any(byId: $0)?.name ?? $0 })
            out.append(Checkpoint(turn: snap.turn, snapshot: snap, live: live, result: result,
                                  analysis: analysis, cpu: cpu, opponentAfter: nil))
        }
        return out
    }

    /// 一致边界（和线上挂点同一个判据：一个顶层 BLOCK 刚结束、解析器没有未闭合的 BLOCK）上拷的快照
    struct Boundary {
        /// fixture 里的行号（从 1 起）
        var line: Int
        /// 刚结束的那个顶层 BLOCK_START 行
        var block: String
        var snapshot: RDGameSnapshot
    }

    /// 喂完整局，在我方回合每个顶层 BLOCK 结束时拷一次快照（不搜索）。`assistant` 非 nil 时，
    /// 同时按线上的方式每行调一次它的 `parserBatchDidEnd`（一行一批）
    func boundaries(_ fixture: String, playerId: Int, assistant: RedDragonAssistant? = nil,
                    deck: Deck = RedDragonLiveReplayTests.makeDeck()) -> [Boundary] {
        guard let url = Bundle(for: RedDragonLiveReplayTests.self).url(forResource: fixture, withExtension: "log"),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            XCTFail("fixture \(fixture) 不在测试包里")
            return []
        }
        let game = Game(hearthstoneRunState: HearthstoneRunState(isRunning: false, isActive: false))
        let parser = PowerGameStateParser(with: game)
        game.player.id = playerId
        game.opponent.id = playerId == 1 ? 2 : 1
        game.set(activeDeck: deck, autoDetected: false)
        let deadline = Date().addingTimeInterval(5)
        while game.currentDeck == nil && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        var out: [Boundary] = []
        var topBlock = ""
        for (i, raw) in content.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = String(raw)
            if let r = line.range(of: "GameState.DebugPrintGame() - PlayerID=") {
                let parts = line[r.upperBound...].components(separatedBy: ", PlayerName=")
                if parts.count == 2, let pid = Int(parts[0]) {
                    let name = parts[1].trimmingCharacters(in: .whitespaces)
                    if pid == playerId { game.player.name = name } else { game.opponent.name = name }
                }
                continue
            }
            guard line.contains("PowerTaskList.DebugPrintPower") else { continue }
            let wasIdle = parser.currentBlock == nil
            if line.contains("CREATE_GAME") {
                // 线上由 LoadingScreen 的 Gameplay 场景调 `gameStart`（还会去读 HearthMirror），回放只置这两个标志
                game.isInMenu = false
                game.gameEnded = false
            }
            parser.handle(logLine: LogLine(namespace: .power, line: line))
            if game.player.id != playerId && line.contains("tag=STEP value=") {
                game.player.id = playerId
                game.opponent.id = playerId == 1 ? 2 : 1
            }
            if wasIdle && line.contains("BLOCK_START") { topBlock = line }
            let idle = parser.currentBlock == nil
            assistant?.parserBatchDidEnd(game, linesProcessed: true, idle: idle)
            guard idle, line.contains("BLOCK_END"), game.playerEntity?.isCurrentPlayer == true,
                  let snap = RDGameSnapshot.capture(game: game) else { continue }
            out.append(Boundary(line: i + 1, block: topBlock, snapshot: snap))
        }
        return out
    }

    /// 每一行都当一批（线上最细的批），解析器空闲、在我方回合、行号落在 `ranges` 里时拷快照，和上一份不同才记
    func idleSnapshots(_ fixture: String, playerId: Int, ranges: [ClosedRange<Int>],
                       deck: Deck = RedDragonLiveReplayTests.makeDeck()) -> [(line: Int, snapshot: RDGameSnapshot)] {
        guard let url = Bundle(for: RedDragonLiveReplayTests.self).url(forResource: fixture, withExtension: "log"),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            XCTFail("fixture \(fixture) 不在测试包里")
            return []
        }
        let game = Game(hearthstoneRunState: HearthstoneRunState(isRunning: false, isActive: false))
        let parser = PowerGameStateParser(with: game)
        game.player.id = playerId
        game.opponent.id = playerId == 1 ? 2 : 1
        game.set(activeDeck: deck, autoDetected: false)
        let deadline = Date().addingTimeInterval(5)
        while game.currentDeck == nil && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        var out: [(line: Int, snapshot: RDGameSnapshot)] = []
        for (i, raw) in content.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = String(raw)
            if let r = line.range(of: "GameState.DebugPrintGame() - PlayerID=") {
                let parts = line[r.upperBound...].components(separatedBy: ", PlayerName=")
                if parts.count == 2, let pid = Int(parts[0]) {
                    let name = parts[1].trimmingCharacters(in: .whitespaces)
                    if pid == playerId { game.player.name = name } else { game.opponent.name = name }
                }
                continue
            }
            guard line.contains("PowerTaskList.DebugPrintPower") else { continue }
            if line.contains("CREATE_GAME") {
                game.isInMenu = false
                game.gameEnded = false
            }
            parser.handle(logLine: LogLine(namespace: .power, line: line))
            if game.player.id != playerId && line.contains("tag=STEP value=") {
                game.player.id = playerId
                game.opponent.id = playerId == 1 ? 2 : 1
            }
            let n = i + 1
            guard ranges.contains(where: { $0.contains(n) }), parser.currentBlock == nil,
                  game.playerEntity?.isCurrentPlayer == true,
                  let snap = RDGameSnapshot.capture(game: game), snap != out.last?.snapshot else { continue }
            out.append((n, snap))
        }
        return out
    }

    static func describe(_ c: Checkpoint) -> String {
        let s = c.live.state
        let hand = c.snapshot.hand.map { "\(short($0.cardId))\($0.cost)" }.joined(separator: " ")
        let board = c.snapshot.board.map { "\(short($0.cardId))\($0.attack)/\($0.health)\($0.exhausted ? "z" : "")" }
            .joined(separator: " ")
        let enemy = c.snapshot.opponentBoard.map { "\($0.attack)/\($0.health)\($0.taunt ? "T" : "")" }
            .joined(separator: " ")
        let a = c.analysis
        let deck = s.deck.remaining(filter: .any).map { "\($0)" }.joined(separator: ",")
        let missing = a.missingPieces.map(short).joined(separator: ",")
        let line = (a.isLethal ? c.result.lethalLines.first : c.result.chosenLine)
            .map { RedDragonLiveReplayTests.lineText($0.actions, root: s) } ?? "-"
        return "T\(c.turn) 水晶\(s.maxMana) 法力\(s.availableMana) 敌\(s.opponent.effectiveHealth)"
            + "(\(c.snapshot.opponentHeroHealth)+\(c.snapshot.opponentHeroArmor)) 敌场[\(enemy)]"
            + " 手[\(hand)] 场[\(board)] 层\(s.layers.count) 边牌\(s.sideboard.count) 牌库\(s.deck.total)"
            + " → \(a.isLethal ? "可斩杀" : "不斩杀") 最大\(a.maxDamage)/\(a.effectiveEnemyHealth)"
            + " 档\(a.tier.map { "\($0)" } ?? "-") \(a.completeness) 缺[\(missing)]"
            + " 态\(c.result.statesExpanded) cpu\(String(format: "%.2f", c.cpu))s"
            + " 回合后敌\(c.opponentAfter.map(String.init) ?? "终局")"
            + " 我\(c.snapshot.heroHealth)+\(c.snapshot.heroArmor) 危\(a.boardDanger) 单回合不够\(a.singleTurnInsufficient)"
            + " 靠抽\(a.lethalDependsOnDraw) 步\(a.totalSteps)"
            + " 必[\(marks(c, .required))] 可[\(marks(c, .optional))]"
            + " 抽牌分支\(a.drawBranches.count) 推断底费\(c.live.inferredBaseCostEntities.count)"
            + " 下一步[\(a.nextStepText)]"
            + " 线: \(line)"
            + " 牌库剩: \(deck)"
    }

    /// 根局面的 Swift 字面量：给 scratchpad 里 `swiftc -O` 的基准程序用（那边只编引擎，没有 Game / Entity）
    static func literal(_ s: RDState) -> String {
        func b(_ v: Bool) -> String { return v ? "true" : "false" }
        func cards(_ cs: [RDCard]) -> String { return "[" + cs.map { ".\($0)" }.joined(separator: ", ") + "]" }
        func enchants(_ es: [RDEnchant]) -> String {
            return "[" + es.map { e -> String in
                switch e {
                case .set(let v): return ".set(\(v))"
                case .delta(let v): return ".delta(\(v))"
                }
            }.joined(separator: ", ") + "]"
        }
        let enemy = s.opponent.board.map {
            "RDEnemyMinion(entityId: \($0.entityId), attack: \($0.attack), health: \($0.health), taunt: \(b($0.taunt)), "
                + "divineShield: \(b($0.divineShield)), immune: \(b($0.immune)), stealth: \(b($0.stealth)), damaged: \(b($0.damaged)))"
        }.joined(separator: ", ")
        var out = "{ var s = RDState(maxMana: \(s.maxMana), mana: \(s.mana), opponent: RDOpponent(health: \(s.opponent.health), "
            + "armor: \(s.opponent.armor), immune: \(b(s.opponent.immune)), board: [\(enemy)], secretCount: \(s.opponent.secretCount)))"
        out += "; s.tempMana = \(s.tempMana); s.cardsPlayedThisTurn = \(s.cardsPlayedThisTurn); s.spellDamage = \(s.spellDamage)"
        out += "; s.heroAttackedThisTurn = \(b(s.heroAttackedThisTurn)); s.heroPowerUsed = \(b(s.heroPowerUsed))"
        if let w = s.weapon {
            out += "; s.weapon = RDWeapon(attack: \(w.attack), durability: \(w.durability), drawOnHeroAttack: \(b(w.drawOnHeroAttack)))"
        }
        out += "; s.hand = [" + s.hand.map { h -> String in
            var t = "RDHandCard(entityId: \(h.entityId), card: .\(h.card), enchants: \(enchants(h.enchants))"
            if let o = h.statsOverride { t += ", statsOverride: RDStats(attack: \(o.attack), health: \(o.health))" }
            if h.isShadowOfDemise { t += ", isShadowOfDemise: true" }
            if let u = h.unmodeledCardId { t += ", unmodeledCardId: \"\(u)\"" }
            return t + ")"
        }.joined(separator: ", ") + "]"
        out += "; s.board = [" + s.board.map { m in
            "RDBoardMinion(entityId: \(m.entityId), card: .\(m.card), attack: \(m.attack), health: \(m.health), "
                + "maxHealth: \(m.maxHealth), statsSetTo1x1: \(b(m.statsSetTo1x1)), silenced: \(b(m.silenced)), "
                + "summoningSick: \(b(m.summoningSick)), attacksThisTurn: \(m.attacksThisTurn), enchants: \(enchants(m.enchants)), "
                + "playOrder: \(m.playOrder))"
        }.joined(separator: ", ") + "]"
        out += "; s.nextPlayOrder = \(s.nextPlayOrder); s.heroFrozen = \(b(s.heroFrozen))"
        let deck = RDCard.allCases.filter { s.deck.count($0) > 0 }.map { "(.\($0), \(s.deck.count($0)))" }
        out += "; s.deck = RDDeck([" + deck.joined(separator: ", ") + "])"
        out += "; s.sideboard = \(cards(s.sideboard)); s.secretsInPlay = \(cards(s.secretsInPlay))"
        out += "; s.layers = [" + s.layers.map { "RDDiscountLayer(amount: \($0.amount), slots: \($0.slots), filter: .\($0.filter))" }
            .joined(separator: ", ") + "]"
        out += "; s.luckyCometCharges = \(s.luckyCometCharges); s.nextEntityId = \(s.nextEntityId); return s }()"
        return out
    }

    static func marks(_ c: Checkpoint, _ role: RDHandMark.Role) -> String {
        return c.analysis.handMarks.filter { $0.role == role }.map { m in
            c.snapshot.hand.first { $0.entityId == m.entityId }.map { short($0.cardId) } ?? "?"
        }.joined(separator: ",")
    }

    static func short(_ id: String) -> String {
        guard let c = RDCards.card(forId: id) else { return Cards.any(byId: id)?.name ?? id }
        return "\(c)"
    }

    static func lineText(_ actions: [RDAction], root: RDState) -> String {
        var s = root
        var out: [String] = []
        for a in actions {
            switch a {
            case .play(_, let identity, let target, let choices, _):
                var t = "\(identity)"
                switch target {
                case .enemyHero: t += "→脸"
                case .friendlyMinion(let id): t += "→" + (s.board.first { $0.entityId == id }.map { "\($0.card)" } ?? "?")
                case .enemyMinion: t += "→敌随"
                default: break
                }
                let picks = choices.compactMap { c -> String? in
                    if case .pick(let card) = c { return "\(card)" }
                    return nil
                }
                if !picks.isEmpty { t += "[" + picks.joined(separator: ",") + "]" }
                out.append(t)
            case .heroPower: out.append("技能")
            case .attack(let attacker, let defender, let choices):
                let who: String
                if case .friendlyMinion(let id) = attacker {
                    who = s.board.first { $0.entityId == id }.map { "\($0.card)" } ?? "?"
                } else { who = "英雄" }
                let picks = choices.compactMap { c -> String? in
                    if case .pick(let card) = c { return "\(card)" }
                    return nil
                }
                out.append("\(who)⚔\(defender == .enemyHero ? "脸" : "敌随")"
                           + (picks.isEmpty ? "" : "[" + picks.joined(separator: ",") + "]"))
            }
            if let next = try? RDEngine.apply(a, to: s) {
                out[out.count - 1] += "\(next.availableMana)"
                s = next
            }
        }
        return out.joined(separator: " ")
    }

    // MARK: - 断言
    //
    // 断言用「去掉 CPU 兜底、只留 40 万状态闸门」的配置跑：结论不随机器快慢变。线上配置（3 s CPU 兜底）
    // 在 Debug 下的结论和耗时见 testLiveConfigTiming —— 两者不一致的回合就是 Debug 慢导致的截断。

    static let games: [(fixture: String, playerId: Int)] = [
        ("2026-10-01-g4-second", 2), ("2026-10-01-g5-first", 1), ("2026-10-01-g3-lost", 1)
    ]

    static var deterministic: RedDragonConfig {
        var c = RedDragonConfig()
        c.cpuBudget = 1e9
        return c
    }

    private func checkpoints(_ fixture: String, playerId: Int) -> [Int: Checkpoint] {
        let cps = replay(fixture, playerId: playerId, config: Self.deterministic)
        print("=== \(fixture)：\(cps.count) 个我方回合")
        for c in cps { print(Self.describe(c)) }
        var byTurn: [Int: Checkpoint] = [:]
        for c in cps { byTurn[c.turn] = c }
        return byTurn
    }

    /// 读取层的通用检查：快照与根局面一致
    private func checkReader(_ c: Checkpoint, file: StaticString = #filePath, line: UInt = #line) {
        let s = c.live.state
        XCTAssertEqual(s.hand.count, c.snapshot.hand.count, "T\(c.turn) 手牌张数", file: file, line: line)
        XCTAssertEqual(s.hand.map { $0.entityId }, c.snapshot.hand.map { $0.entityId },
                       "T\(c.turn) 手牌按 ZONE_POSITION 排", file: file, line: line)
        XCTAssertEqual(s.opponent.effectiveHealth, c.snapshot.opponentHeroHealth + c.snapshot.opponentHeroArmor,
                       file: file, line: line)
        XCTAssertEqual(s.maxMana, c.snapshot.resources, file: file, line: line)
        XCTAssertEqual(s.sideboard.count, c.snapshot.sideboard?.count, file: file, line: line)
        // 卡表没建模的牌只占格，不应出现在这副牌的手里（套牌 30 张 + 乐队 + 币全在卡表）
        XCTAssertTrue(s.hand.allSatisfy { $0.unmodeledCardId == nil },
                      "T\(c.turn) 手里有没建模的牌：\(s.hand.compactMap { $0.unmodeledCardId })", file: file, line: line)
    }

    /// 后手、赢。T8 可斩杀（困难线）但没打出来，T10 打出了基础线
    func testReplayG4Second() throws {
        let t = checkpoints("2026-10-01-g4-second", playerId: 2)
        XCTAssertEqual(t.keys.sorted(), [2, 4, 6, 8, 10])
        for c in t.values { checkReader(c) }

        // T2：1 费，手里有对局给的幸运币 → 最多英雄技能 1 点
        let t2 = t[2]!
        XCTAssertEqual(t2.live.state.availableMana, 1)
        XCTAssertTrue(t2.snapshot.hand.contains { $0.isCoin })
        XCTAssertFalse(t2.analysis.isLethal)
        XCTAssertEqual(t2.analysis.maxDamage, 1)
        // 没找到 ≠ 证明不够：这一回合的搜索没穷举（有损裁剪发生过），所以不出「单回合不够」
        XCTAssertEqual(t2.analysis.verdict, .notFound)
        XCTAssertFalse(t2.analysis.singleTurnInsufficient)
        XCTAssertTrue(t2.analysis.handMarks.isEmpty)

        // T6：没鱼没刀，4 张以上发动件不齐
        XCTAssertFalse(t[6]!.analysis.isLethal)
        XCTAssertEqual(t[6]!.analysis.maxDamage, 1)

        // T8：4 费 32/30，但只有靠抽牌的线（行骗抽到暗影步）；这回合结束对方还是 30 血。
        // 不是「确定能斩没斩」，是「有概率斩」
        let t8 = t[8]!
        XCTAssertTrue(t8.analysis.isLethal)
        XCTAssertTrue(t8.analysis.lethalDependsOnDraw)
        XCTAssertEqual(t8.analysis.maxDamage, 32)
        XCTAssertEqual(t8.analysis.effectiveEnemyHealth, 30)
        XCTAssertEqual(t8.analysis.margin, 2)
        XCTAssertEqual(t8.analysis.tier, .hard)
        XCTAssertEqual(t8.opponentAfter, 30)
        let lethalBranches = t8.analysis.drawBranches.filter { $0.isLethal }
        print("G4 T8 抽牌分支 \(t8.analysis.drawBranches.count) 个，斩杀 \(lethalBranches.count) 个："
              + Set(lethalBranches.map { $0.drawn.map(Self.short).joined(separator: "+") }).sorted().joined(separator: " / "))
        XCTAssertFalse(lethalBranches.isEmpty)
        XCTAssertEqual(t8.analysis.steps.count, 3)
        XCTAssertFalse(t8.analysis.nextStepText.isEmpty)

        // T10：5 费基础线斩杀，对局在这回合结束
        let t10 = t[10]!
        XCTAssertTrue(t10.analysis.isLethal)
        XCTAssertEqual(t10.analysis.maxDamage, 32)
        XCTAssertEqual(t10.analysis.tier, .basic)
        XCTAssertNil(t10.opponentAfter)
        // 幸运币和鲨鱼可换先后；验证完整合法斩杀与首步映射，不把某一种同分顺序写死。
        let chosen = try XCTUnwrap(t10.result.chosenLine)
        XCTAssertNotNil(RDReplay.validate(chosen.actions, from: t10.live.state, expectedDamage: 32))
        let first = try XCTUnwrap(t10.analysis.steps.first)
        let firstCard = try XCTUnwrap(t10.live.state.hand.first { $0.entityId == first.handEntityId })
        let displayedCardId = try XCTUnwrap(first.cardId)
        XCTAssertEqual(RDCards.card(forId: displayedCardId), firstCard.card, "按牌的身份比较，允许幸运币的不同卡牌编号")
        XCTAssertEqual(t10.analysis.steps.first?.kind, .playFromHand)
    }

    /// 先手、赢。T11 打出斩杀（实际打法确定性、无抽牌）
    func testReplayG5First() {
        let t = checkpoints("2026-10-01-g5-first", playerId: 1)
        XCTAssertEqual(t.keys.sorted(), [1, 3, 5, 7, 9, 11])
        for c in t.values { checkReader(c) }

        XCTAssertFalse(t[1]!.analysis.isLethal)
        XCTAssertEqual(t[1]!.analysis.maxDamage, 0)

        // T5：黑水弯刀 1 费装上打 2
        XCTAssertFalse(t[5]!.analysis.isLethal)
        XCTAssertEqual(t[5]!.analysis.maxDamage, 2)

        // T9：5 费手握鱼狐刀暗牛巢母但只有 5 费、无币 → 不斩杀
        XCTAssertFalse(t[9]!.analysis.isLethal)
        XCTAssertEqual(t[9]!.analysis.completeness, .complete)

        // T11：6 费 + 伪造的币，32/30 斩杀，对局在这回合结束
        let t11 = t[11]!
        XCTAssertTrue(t11.analysis.isLethal)
        XCTAssertEqual(t11.analysis.maxDamage, 32)
        XCTAssertFalse(t11.analysis.lethalDependsOnDraw)
        XCTAssertNil(t11.opponentAfter)
        XCTAssertEqual(t11.analysis.tier, .advanced)
        XCTAssertEqual(t11.analysis.steps.first?.cardId, "TRL_092")
    }

    /// 先手、输（投降）。T9 引擎找到一条基础线（第一轮报的是「最多 16」，见下）；其余回合不斩杀
    func testReplayG3Lost() {
        let t = checkpoints("2026-10-01-g3-lost", playerId: 1)
        XCTAssertEqual(t.keys.sorted(), [1, 3, 5, 7, 9, 11, 13])
        for c in t.values { checkReader(c) }
        for c in t.values where c.turn != 9 { XCTAssertFalse(c.analysis.isLethal, "T\(c.turn)") }

        XCTAssertEqual(t[1]!.analysis.maxDamage, 2)
        // T9：对方 28 血。第一轮搜到「最多 16」并标了 complete —— 那是束搜索漏线（这条线不爆手，
        // 舞动按场位还是按上场先后结果一样，旧引擎同样合法）。T2b 第二轮哈希把「场位 ≠ 上场先后」的局面
        // 分开后束里保留的局面变了，搜到 32/28 的基础线：鲨→狐→刀油→暗影施法者复制刀油→牛（发现舞动 + 阿莱）
        // →币×3→刀油复制品→舞动→鲨→刀油→刀油→阿莱打脸→刀油→施法者复制阿莱→阿莱打脸。实际对局这回合没打出来
        let t9 = t[9]!
        XCTAssertTrue(t9.analysis.isLethal)
        XCTAssertEqual(t9.analysis.verdict, .lethal)
        XCTAssertEqual(t9.analysis.maxDamage, 32)
        XCTAssertEqual(t9.analysis.effectiveEnemyHealth, 28)
        XCTAssertEqual(t9.opponentAfter, 27)
        // T11：殒命暗影已变成致聋术，可沉默 #41 的嘲讽，再转刀打脸 1 点。
        XCTAssertEqual(t[11]!.analysis.maxDamage, 1)
        var t11 = t[11]!.live.state
        let deafen = t11.hand.first { $0.isShadowOfDemise && $0.card == .deafen }
        XCTAssertNotNil(deafen)
        if let deafen {
            do {
                t11 = try RDEngine.apply(.play(entityId: deafen.entityId, identity: .deafen,
                                               target: .enemyMinion(41), choices: []), to: t11)
                XCTAssertFalse(t11.opponent.board.contains { $0.taunt })
                t11 = try RDEngine.apply(.heroPower, to: t11)
                t11 = try RDEngine.apply(.attack(attacker: .friendlyHero, defender: .enemyHero, choices: []), to: t11)
                XCTAssertEqual(t11.damageDealt, 1)
            } catch {
                XCTFail("T11 的 1 点伤害重放失败：\(error)")
            }
        }
        XCTAssertEqual(t[11]!.analysis.effectiveEnemyHealth, 27)
        // T13：对方铺了 6 个随从
        XCTAssertEqual(t[13]!.snapshot.opponentBoard.count, 6)
        // 搜索到了状态上限（capped）→ 只能说「没找到」，不出「单回合不够」
        XCTAssertEqual(t[13]!.analysis.verdict, .notFound)
        XCTAssertFalse(t[13]!.analysis.singleTurnInsufficient)
    }

    /// 线上配置（3 s CPU 兜底）在 Debug 下的读取 + 搜索耗时；只打印、对单回合上限做个宽松的检查
    func testLiveConfigTiming() {
        var all: [Double] = []
        for g in Self.games {
            let cps = replay(g.fixture, playerId: g.playerId)
            for c in cps {
                all.append(c.cpu)
                print("[live] \(g.fixture) T\(c.turn) cpu \(String(format: "%.2f", c.cpu))s "
                      + "\(c.analysis.isLethal ? "可斩杀" : "不斩杀") 最大\(c.analysis.maxDamage) \(c.analysis.completeness)")
                print("[bench] (\"\(g.fixture) T\(c.turn)\", \(Self.literal(c.live.state))),")
            }
        }
        XCTAssertFalse(all.isEmpty)
        let avg = all.reduce(0, +) / Double(max(all.count, 1))
        print("[live] \(all.count) 个回合，平均 \(String(format: "%.2f", avg))s，最差 \(String(format: "%.2f", all.max() ?? 0))s")
        // 三遍搜索各自受 3 s 兜底，单回合不应超过 ~3 遍之和
        XCTAssertLessThan(all.max() ?? 0, 10)
    }

    // MARK: - 连招中途的一致边界（第二轮）

    /// 每个边界上：读取层反推的底费 + 引擎重新叠层算出的费用 = 日志里这张牌的 COST（推断底费的除外）
    private func checkCosts(_ b: Boundary, file: StaticString = #filePath, line: UInt = #line) {
        let live = RDStateReader.read(b.snapshot)
        XCTAssertEqual(live.state.hand.map { $0.entityId }, b.snapshot.hand.map { $0.entityId }, file: file, line: line)
        for (c, h) in zip(b.snapshot.hand, live.state.hand)
        where h.unmodeledCardId == nil && !live.inferredBaseCostEntities.contains(h.entityId) {
            XCTAssertEqual(live.state.cost(of: h, as: h.card), c.cost,
                           "行 \(b.line) \(c.cardId)#\(c.entityId) 的费用", file: file, line: line)
        }
    }

    /// g2 T12（01:08，日志原文件第 75004 行起的舞动）：刀油两层各用掉 1 槽的中途、舞动爆手、牌库剩余。
    /// 期望值都是对着 fixture 人工核的：
    /// - 舞动前场上 7 个随从，上场先后 鲨鱼 7 → 刀油 14 → 牛 30 → 巢母 19 → 狐 31 → 刀油复制 182 → 牛复制 185
    ///   （场位 4 5 6 7 3 2 1）；手里 7 张：暗影施法者 5、弯刀 8、TSC_916 17、阿莱 166、鲨鱼 179、巢母 188、舞动 216；
    /// - fixture 第 16822 / 16827 行：两层「烹油下锅」（199 / 207）TAG_SCRIPT_DATA_NUM_1 = 1；
    /// - 舞动结算（第 17654 行起）：7 14 30 19 进手，31 182 185 进坟场；
    /// - 牌库 12 张（按 ZONE 逐行数：scratchpad 的 deckcount.py，舞动前第 17653 行为止）
    func testMidComboBoundariesG2BounceOverflow() throws {
        let bs = boundaries("2026-10-01-g2-bounce-overflow", playerId: 1)
        XCTAssertGreaterThan(bs.count, 20)
        for b in bs { checkCosts(b) }

        let i = try XCTUnwrap(bs.firstIndex { $0.block.contains("BlockType=PLAY") && $0.block.contains("cardId=ETC_079") })
        let before = bs[i - 1], after = bs[i]
        XCTAssertLessThan(before.line, 17654)
        let live = RDStateReader.read(before.snapshot)
        let s = live.state
        XCTAssertEqual(s.hand.map { $0.entityId }.sorted(), [5, 8, 17, 166, 179, 188, 216])
        XCTAssertEqual(s.board.map { $0.entityId }, [185, 182, 31, 7, 14, 30, 19], "场位从左到右")
        XCTAssertEqual(s.boardIndicesByPlayOrder().map { s.board[$0].entityId }, [7, 14, 30, 19, 31, 182, 185],
                       "上场先后")
        // 刀油层消耗中途
        XCTAssertEqual(before.snapshot.playerEnchantments.filter { $0.cardId == "BAR_552o" }.map { $0.scriptData1 },
                       [1, 1])
        XCTAssertEqual(s.layers.filter { $0.amount == 2 && $0.filter == .any && $0.slots == 1 }.count, 2,
                       "两层刀油各剩 1 槽")
        // 牌库剩余（独立数出来的 12）
        XCTAssertEqual(before.snapshot.deck.values.reduce(0, +), 12)
        XCTAssertEqual(s.deck.total, 12)

        // 引擎预测的舞动结果 = 日志结果
        let predicted = try RDEngine.apply(.play(entityId: 216, identity: .bounceAround, target: .none, choices: []),
                                           to: s)
        let logged = RDStateReader.read(after.snapshot).state
        func cards(_ t: RDState) -> [String] {
            return t.hand.map { "\($0.card)\($0.statsOverride == nil ? "" : "(1/1)")" }.sorted()
        }
        XCTAssertEqual(after.snapshot.hand.map { $0.entityId }.sorted(), [5, 7, 8, 14, 17, 19, 30, 166, 179, 188])
        XCTAssertEqual(cards(predicted), cards(logged))
        XCTAssertTrue(predicted.board.isEmpty && logged.board.isEmpty)
        XCTAssertFalse(predicted.hand.contains { $0.card == .foxyFraud }, "按场位收回会收到狐，按上场先后不会")
    }

    /// g4 T10：伪造的幸运币 + 两枚幸运币之后（TEMP_RESOURCES = 3，fixture 第 11712 行）可用 5 + 3 = 8；
    /// 下鲨鱼（4 费）后临时法力先用完（第 11790 行 TEMP 0、USED 1）→ 可用 4。期望值对着 fixture 人工核过
    func testMidComboBoundariesG4TempMana() throws {
        let bs = boundaries("2026-10-01-g4-second", playerId: 2)
        for b in bs { checkCosts(b) }
        let coin = try XCTUnwrap(bs.last { $0.block.contains("BlockType=PLAY") && $0.block.contains("id=35 ")
            && $0.block.contains("TTN_COIN2") })
        XCTAssertEqual(coin.snapshot.tempResources, 3)
        XCTAssertEqual(RDStateReader.read(coin.snapshot).state.availableMana, 8)
        let shark = try XCTUnwrap(bs.first { $0.line > coin.line && $0.block.contains("BlockType=PLAY")
            && $0.block.contains("id=48 ") })
        XCTAssertEqual(shark.snapshot.tempResources, 0)
        XCTAssertEqual(RDStateReader.read(shark.snapshot).state.availableMana, 4)
    }

    /// 线上挂点在回放里的表现：每行一批、只在没有未闭合 BLOCK 时拷。投递的快照都是一致边界上的；
    /// 非本牌组时一次都不投递
    func testHookOnReplayFeedsOnlyAtConsistentPoints() {
        let env = RedDragonAssistant.Environment(
            isEnabled: { true }, revealPreference: { .verdict }, quizMode: { false },
            debounce: 1000, config: RedDragonConfig(), cardName: { $0 })
        let assistant = RedDragonAssistant(environment: env, recordsFeeds: true)
        let bs = boundaries("2026-10-01-g4-second", playerId: 2, assistant: assistant)
        let fed = assistant.fedInputs.compactMap { input -> RDGameSnapshot? in
            if case .snapshot(let s) = input { return s }
            return nil
        }
        XCTAssertFalse(fed.isEmpty)
        // 每个顶层 BLOCK 结束时的局面都投递过（只差操作数的算同一个）。起手调度和对局结束那回合不比
        let lastTurn = bs.map { $0.snapshot.turn }.max() ?? 0
        for b in bs where b.snapshot.turn > 1 && b.snapshot.turn < lastTurn {
            XCTAssertTrue(fed.contains { f in
                RedDragonAssistant.onlyOptionCountChanged(.snapshot(f), .snapshot(b.snapshot)) || f == b.snapshot
            }, "行 \(b.line) 的边界局面没投递")
        }
        XCTAssertTrue(assistant.fedInputs.contains(.opponentTurn))
        print("g4 回放：边界 \(bs.count) 个，投递 \(assistant.fedInputs.count) 次（快照 \(fed.count)）")

        // 非本牌组：一次都不投递
        let other = RedDragonAssistant(environment: env, recordsFeeds: true)
        let deck = Deck()
        deck.name = "not red dragon"
        deck.playerClass = .rogue
        deck.cards.append(RealmCard(id: "CFM_630", count: 2))
        _ = boundaries("2026-10-01-g4-second", playerId: 2, assistant: other, deck: deck)
        XCTAssertTrue(other.fedInputs.isEmpty, "非本牌组不投 main.async")
    }

    /// T2b 第四轮 P1：g2 两次英雄攻击，`NUM_OPTIONS_PLAYED_THIS_TURN` 都在攻击（以及矿锄抽牌、死亡结算）
    /// 之后才在顶层 +1（第 4078 行到 2、第 5824 行到 1）。一行一批时，先拷到「新场面 + 旧计数」，
    /// 再拷到只差计数的那份。判卷要：前一份不当完成、不覆盖操作之前的结论；后一份才算这一步完成，
    /// 用操作之前那次的结论判
    func testAttackOptionCountArrivesLateG2() {
        let windows: [(range: ClosedRange<Int>, countLine: Int, count: Int)] = [
            (3727...4090, 4078, 2), (5501...5830, 5824, 1)
        ]
        let all = idleSnapshots("2026-10-01-g2-bounce-overflow", playerId: 1, ranges: windows.map { $0.range })
        for w in windows {
            let seq = all.filter { w.range.contains($0.line) }
            guard let i = seq.firstIndex(where: { $0.line == w.countLine }), i > 0 else {
                return XCTFail("第 \(w.countLine) 行没有拷到快照；窗口里拷到的："
                               + seq.map { "\($0.line)/c\($0.snapshot.optionsPlayedThisTurn)" }.joined(separator: " "))
            }
            XCTAssertEqual(seq[i].snapshot.optionsPlayedThisTurn, w.count)
            XCTAssertTrue(RDQuizState.sameIgnoringOptionCount(seq[i].snapshot, seq[i - 1].snapshot),
                          "第 \(w.countLine) 行那份只差计数")
            XCTAssertEqual(seq[i - 1].snapshot.optionsPlayedThisTurn, w.count - 1, "攻击已结算、计数还没涨")
            XCTAssertGreaterThan(seq[i - 1].snapshot.heroAttacksThisTurn, seq[0].snapshot.heroAttacksThisTurn)

            var q: RDQuizState?
            var verdicts: [RDLethalVerdict] = []
            var lastSettledVerdict: RDLethalVerdict?
            for (k, item) in seq.enumerated() where k <= i {
                let live = RDStateReader.read(item.snapshot)
                let result = RedDragonSearch.solve(live.state, config: RedDragonConfig())
                let v = RDHintBuilder.analyze(snapshot: item.snapshot, live: live, result: result,
                                              cardName: { $0 }).verdict
                verdicts.append(v)
                if q?.pending != true { lastSettledVerdict = q?.baseline }
                q = RDQuizState.next(q, snapshot: item.snapshot, verdict: v)
                print("[quiz] g2 行 \(item.line) 计数 \(item.snapshot.optionsPlayedThisTurn) 英雄攻击 "
                      + "\(item.snapshot.heroAttacksThisTurn) 结论 \(v) pending \(q!.pending) "
                      + "已判 \(q!.lastActions) 标记 \(String(describing: q!.mark))")
                if k == i - 1 {
                    XCTAssertTrue(q!.pending, "第 \(item.line) 行：攻击进行中")
                    XCTAssertEqual(q!.lastActions, w.count - 1, "第 \(item.line) 行：还没判这一步")
                }
            }
            guard let done = q, let before = lastSettledVerdict else { return XCTFail() }
            XCTAssertFalse(done.pending)
            XCTAssertEqual(done.lastActions, w.count, "第 \(w.countLine) 行：这一步完成、判卷")
            XCTAssertEqual(done.lastOp?.before, before, "用攻击之前那次的结论判")
            XCTAssertEqual(done.mark, RDQuizState.judge(before: before, markBefore: nil, after: verdicts[i]))

            // 这两次攻击前后的真实结论都不是「能斩」，判不出颜色。用同一串真实局面、换上 Codex 复现的结论：
            // 上一步判了绿、攻击之前能斩，攻击结算后证明不能斩。第三轮的做法在这里一直是绿（结论被覆盖、
            // 只差计数的那份被丢）；现在第 countLine 行判红
            guard let firstPending = seq.firstIndex(where: { $0.snapshot.heroAttacksThisTurn > seq[0].snapshot.heroAttacksThisTurn })
            else { return XCTFail() }
            var g = RDQuizState(turn: seq[0].snapshot.turn, lastActions: w.count - 1, settled: seq[0].snapshot,
                                baseline: .lethal, lastOp: RDQuizOp(before: .lethal, markBefore: nil),
                                pendingOp: nil, mark: .onLine)
            for k in 1...i {
                g = RDQuizState.next(g, snapshot: seq[k].snapshot, verdict: k < firstPending ? .lethal : .provenNotLethal)
                if k >= firstPending && k < i {
                    XCTAssertTrue(g.pending)
                    XCTAssertEqual(g.baseline, .lethal, "第 \(seq[k].line) 行：攻击之前的「能斩」没被覆盖")
                }
            }
            XCTAssertEqual(g.lastActions, w.count)
            XCTAssertEqual(g.mark, .offLine, "第 \(w.countLine) 行：攻击打错，判红")
        }
    }

    /// T2b 第三轮：解析线程上「拍快照 + 和上次比较」本身的耗时（挂点里 `feed(input(from:))` 那一段，
    /// 不含搜索）。四局本牌组回放、一行一批，凡是在一致边界上拷了的批都计一次。只打印、不设阈值
    /// （Debug 构建，app 侧 -Onone）；开关关着时挂点在第一个判断就 return，不计
    func testSnapshotCaptureCostOnLogThread() {
        let env = RedDragonAssistant.Environment(
            isEnabled: { true }, revealPreference: { .verdict }, quizMode: { false },
            debounce: 1000, config: RedDragonConfig(), cardName: { $0 })
        var all: [Double] = []
        for (fixture, pid) in [("2026-10-01-g2-bounce-overflow", 1), ("2026-10-01-g3-lost", 1),
                               ("2026-10-01-g4-second", 2), ("2026-10-01-g5-first", 1)] {
            let assistant = RedDragonAssistant(environment: env, recordsFeeds: true)
            _ = boundaries(fixture, playerId: pid, assistant: assistant)
            let t = assistant.captureTimings
            XCTAssertFalse(t.isEmpty, fixture)
            all += t
            let avg = t.reduce(0, +) / Double(max(1, t.count))
            print(String(format: "[capture] %@：%d 批拷了快照，平均 %.1f µs，最大 %.1f µs，投递 %d 次", fixture,
                         t.count, avg * 1e6, (t.max() ?? 0) * 1e6, assistant.fedInputs.count))
        }
        let sorted = all.sorted()
        let avg = all.reduce(0, +) / Double(max(1, all.count))
        print(String(format: "[capture] 合计 %d 批，平均 %.1f µs，中位 %.1f µs，p99 %.1f µs，最大 %.1f µs",
                     all.count, avg * 1e6, sorted[sorted.count / 2] * 1e6,
                     sorted[min(sorted.count - 1, sorted.count * 99 / 100)] * 1e6, (sorted.last ?? 0) * 1e6))

        // 开关关着：挂点不拷、不计
        let off = RedDragonAssistant(environment: RedDragonAssistant.Environment(
            isEnabled: { false }, revealPreference: { .verdict }, quizMode: { false },
            debounce: 1000, config: RedDragonConfig(), cardName: { $0 }), recordsFeeds: true)
        _ = boundaries("2026-10-01-g4-second", playerId: 2, assistant: off)
        XCTAssertTrue(off.captureTimings.isEmpty)
        XCTAssertTrue(off.fedInputs.isEmpty)
    }
}
