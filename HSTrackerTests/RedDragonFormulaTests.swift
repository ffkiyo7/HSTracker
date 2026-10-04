//
//  RedDragonFormulaTests.swift
//  HSTrackerTests
//
//  红龙 T2a：公式表（formulas.json）逐案例由引擎下结论 + 从声明的起手搜索 + 齐件 / 缺件分组。
//
//  案例 = 行 × 展开变体（expandedLines 各一条）× 起手缺法（startDeckVariants 各一种），各自独立重放、搜索、统计。
//
//  起手（`declaredStart`）只按截图声明来搭，不看哪条线成功：
//  - 随从：组名 / 行标签写的缺件（无狐、无晦、缺暗…）之外的主牌库随从各一张；「狐视作杂牌」的组狐在手、计入杂牌数；
//  - 特殊杂牌（骨 / 步 / 伺 / 殒 / 帷幕，spike 第八节「要求杂牌里有哪种」）计入杂牌数，「提前彗」各组的步、伺不计（组注）；
//    张数取该案例公式里出现的次数（截图不写张数，公式文字就是声明），列里写死却没出现的也放一张；
//  - 「腾格」「杂」实例化成本牌组的真牌，计入杂牌数，由真实规则约束费用和目标，逐个组合试，取第一个成立的：
//    腾格 = 步 / 骨刺 / 致聋术，再加另一版牌组的背刺 / 袋底藏沙 / 脱水（卡表 `verificationOnly`，用到的记前提
//    「需要另一版牌组的 X」，先试本牌组的组合）；「骨/步之外腾格」去掉步和骨刺，「≤N费」按印刷费过滤；
//    杂 = 黑水弯刀 / 闪避 / 潜伏帷幕；
//  - 杂牌数余下的张数 = 不可打的杂牌。截图没给杂牌数（null）的不继承别行，结论「待用户确认」。
//  - 手牌上限 10。起手超过 10 张 / 场面超过 7 个 = 起手非法，直接判「公式不成立」，不重放。
//
//  严格重放（`strictReplay`）：按搜索口径（`.search`，发现 / 复制 / 抽牌 / 随从落位都要给出确定的选择）逐 token 做 DFS，
//  在合法动作里找身份、目标、剩余法力都与表对得上的那个，最后伤害要等于表值。DFS 走出来的就是一条显式的动作序列。
//
//  结论：① 原样重放通过；② 前提下重放通过：带 premise 通过、不带失败，或只有用上另一版牌组的腾格牌才通过；
//  ③ 原表有误：原样失败、tableErrata 改正后通过；
//  ④ 清杂分支可行：截图只用文字允许、没印数字的分支（`printed: false` 的展开线，括号清杂的每种取舍各一条），
//    从插入的杂起不校验法力，卡牌顺序和印出来的那部分法力严格重放走得通、伤害达标。算通过，统计里分开数。
//  其余都**不算通过**、单独计数：公式不成立 / 规则未建模（每个候选都卡在「腾格」那一步）/ 待用户确认 / 非单回合公式。
//  公式不成立再由引擎分类（`failureKind`）：印刷数字对不上 / 爆手 / 其他，写在签名最前面。
//  每条没通过的案例在 rdExpectedFailures 里逐字记结论和失败签名。有多条分支的行另打印整行结论。
//

import XCTest
@testable import HSTracker

// MARK: - 公式表缩写

private let rdAbbreviations: [String: RDCard] = [
    "鱼": .spiritOfTheShark,
    "狐": .foxyFraud,
    "刀": .scabbsCutterbutter,
    "暗": .shadowcaster,
    "牛": .etcBandManager,
    "晦": .darkscaleBroodmother,
    "龙": .alexstrasza,
    "舞": .bounceAround,
    "幻": .potionOfIllusion,
    "步": .shadowstep,
    "骨": .serratedBoneSpike,
    "伺": .preparation,
    "殒": .shadowOfDemise,
    "币": .coin,
    "帷幕": .shroudOfConcealment
]

/// 「腾格」= 能把自己场上一个随从弄走的 ≤2 费牌（spike 第八节）。本牌组里是步 / 骨刺 / 致聋术；
/// 公式表是给带持枪要挟的另一版牌组写的，spike 还列了背刺、袋底藏沙，以及持枪要挟能发现的脱水。
/// 后三张按官方文本进了卡表（`verificationOnly`），实例化成它们的案例记前提「需要另一版牌组的 X」。
private let rdTenggeDeckCards: [RDCard] = [.shadowstep, .serratedBoneSpike, .deafen]
private let rdTenggeOtherDeckCards: [RDCard] = [.backstab, .pocketSand, .dehydrate]
private let rdTenggeCards: [RDCard] = rdTenggeDeckCards + rdTenggeOtherDeckCards
/// 「杂」= 可清的杂牌。取本牌组里不影响法力与场面的 1 / 2 / 3 费各一张
private let rdClearableJunkCards: [RDCard] = [.blackwaterCutlass, .evasion, .shroudOfConcealment]

/// 「提前彗」各组（组注：步和伺等同清杂，不算在杂牌数里）
private let rdCometGroups: Set<String> = ["狐起手", "刀起手", "无晦（狐视作杂牌）",
                                          "打/回16（狐视作杂牌）", "预启动（狐视作杂牌）"]

/// 没通过的案例：结论 + 失败形态签名 + 说明。签名由引擎生成（`failureSignature`）：
/// 每个实例化组合在决定性那次重放里卡住的「第几步 / 哪个 token」或起手非法，去重排序后拼起来。
/// 测试逐字比对结论和签名 —— 失败形态一变（卡在别的步、别的原因、或者通过了）就红。
/// 这些案例都**不算通过**，在结论统计里单独计数。
private struct RDExpectedFailure {
    let verdict: RDVerdict
    let signature: String
    let reason: String
}

private let rdExpectedFailures: [String: RDExpectedFailure] = [
    "t1-pre-03-n1": RDExpectedFailure(
        verdict: .pendingUser, signature: "杂牌数未声明",
        reason: "截图只写「下回合不卡格能4费48」，没给下回合杂牌数；原 fixture 的 4 是从 t1-pre-03 继承的，已改 null。"
            + "参考：杂牌 0–3 张时前提下重放通过，4 张时起手 11 张非法"),
    "t2-wuhu-03#1": RDExpectedFailure(
        verdict: .invalid, signature: "爆手｜第15步「暗2」",
        reason: "「不清」这一支（表里印的数字属于它）：一阶段打完场上 7 个随从，舞动时手里还有 4 杂 + 骨 + 龙，只剩 4 格；"
            + "二阶段要 鱼晦刀刀暗 5 张随从，按场上从左到右收回、放不下的烧掉（用户 09-11 定的规则），落位怎么排都要烧掉一张。"
            + "手牌上限放开就能打满（引擎判「爆手」）。整行靠三条清杂分支成立"),
    "t2-wudao-01": RDExpectedFailure(
        verdict: .notAFormula, signature: "无费用无步骤",
        reason: "截图这一格是「无刀做无限」的说明文字，没有费用、杂牌数和步骤"),
    "t2-huqs-03-n1": RDExpectedFailure(
        verdict: .invalid, signature: "起手11张",
        reason: "声明的起手 = 6 随从 + 杂牌 4（含骨）+ 步（「提前彗」组注：步不计入杂牌数）= 11 张，超过手牌上限 10，"
            + "真实对局里不存在。若组注不适用于这条备注公式（步计入 4 张杂牌），起手是 10 张，需用户确认"),
    "t2-daoqs-02#1": RDExpectedFailure(
        verdict: .invalid, signature: "爆手｜第15步「暗2」",
        reason: "同 t2-wuhu-03#1（「不清」这一支，带前提、改正后）：舞动时手里只剩 4 格，二阶段要的 5 张随从落位怎么排"
            + "都要烧掉一张。整行靠三条清杂分支成立")
]

// MARK: - fixture 数据

private struct RDToken {
    var card: String
    var target: String?
    var manaAfter: Int?
    /// 表里带括号的可选步（如 t1-pre-03 的「(晦4)」）：打或不打都行
    var optional = false
    /// 这一步实例化的牌印刷费上限（如「杂≤1费」）
    var maxCost: Int?
}

private struct RDPremise {
    var luckyComet = 0
    var cardsPlayedThisTurn = 0
    var enemyBoard: [(attack: Int, health: Int)] = []
    var startHand: [(card: String, copy: Bool)]?
    var sideboard: [String]?

    var key: String {
        let board = enemyBoard.map { "\($0.attack)/\($0.health)" }.joined(separator: ",")
        let hand = startHand.map { list in list.map { $0.card + ($0.copy ? "c" : "") }.joined() } ?? "-"
        return "comet\(luckyComet) played\(cardsPlayedThisTurn) enemy[\(board)] hand[\(hand)]"
            + " side[\((sideboard ?? []).joined())]"
    }

    var summary: String {
        var parts: [String] = []
        if luckyComet > 0 { parts.append("幸运彗星 ×\(luckyComet)") }
        if cardsPlayedThisTurn > 0 { parts.append("已出牌 \(cardsPlayedThisTurn)") }
        if !enemyBoard.isEmpty {
            parts.append("敌方随从 " + enemyBoard.map { "\($0.attack)/\($0.health)" }.joined(separator: ","))
        }
        if let h = startHand {
            parts.append("起手 " + h.map { $0.card + ($0.copy ? "(1费复制)" : "") }.joined())
        }
        if let s = sideboard { parts.append("边牌只剩 " + s.joined()) }
        return parts.joined(separator: "、")
    }
}

private struct RDErrata {
    var crystals: Int?
    var steps: [[RDToken]?]?
    var expandedLines: [[RDToken]]?
    var cells: [String]
}

private struct RDRow {
    var id: String
    var group: String
    var rowLabel: String
    var crystals: Int?
    var cost: Int?
    var damage: Int?
    /// nil = 截图没给杂牌数（不准从别的行继承），该案例结论是「待用户确认」
    var junk: Int?
    var specialJunkRaw: String
    var phases: [[RDToken]?]
    var expandedLines: [[RDToken]]
    /// 每条展开线的标签和「截图印了这一支的数字」。没印的分支（清杂分支）从插入的那一步起不校验法力，
    /// 后面阶段的法力也不校验（表里的数字属于印出来的那一支）
    var expandedLabels: [String]
    var expandedPrinted: [Bool]
    var premise: RDPremise?
    var errata: RDErrata?
    var startDeckVariants: [[String]]
    var fromNote: Bool
}

private func parseTokens(_ any: Any?) -> [RDToken]? {
    guard let list = any as? [[String: Any]] else { return nil }
    return list.map {
        RDToken(card: ($0["card"] as? String) ?? "", target: $0["target"] as? String,
                manaAfter: $0["manaAfter"] as? Int, optional: ($0["optional"] as? Bool) ?? false,
                maxCost: $0["maxCost"] as? Int)
    }
}

private func parsePhases(_ any: Any?) -> [[RDToken]?] {
    guard let steps = any as? [Any] else { return [] }
    return steps.map { parseTokens($0) }
}

private func parseExpanded(_ any: Any?) -> [[RDToken]] {
    guard let lines = any as? [[String: Any]] else { return [] }
    return lines.compactMap { parseTokens($0["steps"]) }
}

private func parsePremise(_ any: Any?) -> RDPremise? {
    guard let dict = any as? [String: Any] else { return nil }
    var p = RDPremise()
    p.luckyComet = dict["luckyComet"] as? Int ?? 0
    p.cardsPlayedThisTurn = dict["cardsPlayedThisTurn"] as? Int ?? 0
    if let board = dict["enemyBoard"] as? [[String: Any]] {
        p.enemyBoard = board.map { (attack: $0["attack"] as? Int ?? 0, health: $0["health"] as? Int ?? 1) }
    }
    if let hand = dict["startHand"] as? [[String: Any]] {
        p.startHand = hand.map { (card: $0["card"] as? String ?? "", copy: $0["copy"] as? Bool ?? false) }
    }
    p.sideboard = dict["sideboard"] as? [String]
    return p
}

private func parseErrata(_ any: Any?) -> RDErrata? {
    guard let dict = any as? [String: Any] else { return nil }
    var cells: [String] = []
    if let list = dict["cells"] as? [[String: Any]] {
        for c in list {
            cells.append("\(c["at"] ?? "?")：表 \(c["table"] ?? "?") → \(c["corrected"] ?? "?")")
        }
    }
    return RDErrata(crystals: dict["crystals"] as? Int,
                    steps: dict["steps"] == nil ? nil : parsePhases(dict["steps"]),
                    expandedLines: dict["expandedLines"] == nil ? nil : parseExpanded(dict["expandedLines"]),
                    cells: cells)
}

private func loadRows() -> [RDRow] {
    guard let url = Bundle(for: RedDragonFormulaTests.self).url(forResource: "formulas",
                                                                withExtension: "json"),
          let data = try? Data(contentsOf: url),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let raw = json["rows"] as? [[String: Any]] else {
        return []
    }
    return raw.map { dict in
        var special = (dict["specialJunkRaw"] as? String) ?? ""
        if special.isEmpty {
            if let s = dict["specialJunk"] as? String {
                special = s
            } else if let a = dict["specialJunk"] as? [String] {
                special = a.joined(separator: "+")
            }
        }
        return RDRow(id: (dict["id"] as? String) ?? "?",
                     group: (dict["group"] as? String) ?? "",
                     rowLabel: (dict["rowLabel"] as? String) ?? "",
                     crystals: dict["crystals"] as? Int,
                     cost: dict["cost"] as? Int,
                     damage: dict["damage"] as? Int,
                     junk: dict["junk"] as? Int,
                     specialJunkRaw: special,
                     phases: parsePhases(dict["steps"]),
                     expandedLines: parseExpanded(dict["expandedLines"]),
                     expandedLabels: ((dict["expandedLines"] as? [[String: Any]]) ?? [])
                        .map { ($0["label"] as? String) ?? "" },
                     expandedPrinted: ((dict["expandedLines"] as? [[String: Any]]) ?? [])
                        .map { ($0["printed"] as? Bool) ?? true },
                     premise: parsePremise(dict["premise"]),
                     errata: parseErrata(dict["tableErrata"]),
                     startDeckVariants: dict["startDeckVariants"] as? [[String]] ?? [],
                     fromNote: dict["fromNote"] != nil)
    }
}

// MARK: - 案例

private struct RDCase {
    var id: String
    var row: RDRow
    var tokens: [RDToken]
    /// tableErrata 改正后的 token；没有改正时为 nil
    var corrected: [RDToken]?
    var crystals: Int?
    var correctedCrystals: Int?
    /// 阶段写到一半（null 阶段且没有展开）：不校验总伤害
    var truncated: Bool
    var deckOut: [String]
    /// 行标签声明缺的随从（「缺暗(晦)」= 缺暗或缺晦，二者各成一个案例）
    var labelMissing: [String]
    /// 展开线的标签（有多条展开线时）
    var branchLabel: String? = nil
    /// 截图印了这一支的数字。false = 清杂分支，通过时结论记「清杂分支可行」
    var branchPrinted = true
}

/// 行标签里的缺件声明，每个元素是一种替代情况
private func labelMissingAlternatives(_ row: RDRow) -> [[String]] {
    switch row.rowLabel {
    case "无晦清杂预启动": return [["晦"]]
    case "缺暗(晦)预启动": return [["暗"], ["晦"]]
    default: return [[]]
    }
}

/// 每一阶段：非 null 用 steps，null 用 expandedLines 的第 variant 条，没有就截断。
/// `printed` = false（截图没印这一支的数字）：展开线之后各阶段的法力不校验
private func script(_ phases: [[RDToken]?], _ expanded: [[RDToken]], variant: Int,
                    printed: Bool = true) -> (tokens: [RDToken], truncated: Bool) {
    var out: [RDToken] = []
    var afterBranch = false
    for phase in phases {
        if let phase = phase {
            out.append(contentsOf: afterBranch && !printed
                       ? phase.map { t -> RDToken in var u = t; u.manaAfter = nil; return u }
                       : phase)
        } else if !expanded.isEmpty {
            out.append(contentsOf: expanded[min(variant, expanded.count - 1)])
            afterBranch = true
        } else {
            return (out, true)
        }
    }
    return (out, false)
}

private func makeCases(_ rows: [RDRow]) -> [RDCase] {
    var out: [RDCase] = []
    for row in rows {
        let hasNull = row.phases.contains { $0 == nil }
        let variants = hasNull && !row.expandedLines.isEmpty ? row.expandedLines.count : 1
        let decks = row.startDeckVariants.isEmpty ? [[String]()] : row.startDeckVariants
        for v in 0..<variants {
            let printed = v < row.expandedPrinted.count ? row.expandedPrinted[v] : true
            let orig = script(row.phases, row.expandedLines, variant: v, printed: printed)
            var corrected: [RDToken]?
            if let e = row.errata, e.steps != nil || e.expandedLines != nil {
                corrected = script(e.steps ?? row.phases, e.expandedLines ?? row.expandedLines, variant: v,
                                   printed: printed).tokens
            }
            let labels = labelMissingAlternatives(row)
            for deckOut in decks {
                for label in labels {
                    var id = row.id
                    if variants > 1 { id += "#\(v + 1)" }
                    if !deckOut.isEmpty { id += "/缺" + deckOut.joined() }
                    if labels.count > 1 { id += "/缺" + label.joined() }
                    out.append(RDCase(id: id, row: row, tokens: orig.tokens, corrected: corrected,
                                      crystals: row.crystals,
                                      correctedCrystals: row.errata?.crystals ?? row.crystals,
                                      truncated: orig.truncated, deckOut: deckOut,
                                      labelMissing: label,
                                      branchLabel: variants > 1 && v < row.expandedLabels.count
                                        ? row.expandedLabels[v] : nil,
                                      branchPrinted: printed))
                }
            }
        }
    }
    return out
}

// MARK: - 声明的起手

private struct RDStart {
    var state: RDState
    var text: String
    var findings: [String]
    /// 起手本身不合法（超过手牌上限等）：不重放，直接判失败
    var illegal: String?
}

/// 起手合法性：真实对局里手牌不会超过上限、场面不会超过 7 格
private func startIllegality(_ s: RDState) -> String? {
    if s.hand.count > s.handLimit { return "起手 \(s.hand.count) 张，超过手牌上限 \(s.handLimit)" }
    if s.board.count > s.boardLimit { return "场面 \(s.board.count) 个随从，超过 \(s.boardLimit) 格" }
    return nil
}

/// 组名声明缺的随从（行标签的缺件见 `labelMissingAlternatives`，按案例给）
private func declaredMissing(_ c: RDCase) -> [String] {
    var out: [String] = []
    switch c.row.group {
    case "无狐": out = ["狐"]
    case "无晦", "无晦（狐视作杂牌）": out = ["晦"]
    case "无暗+无晦": out = ["暗", "晦"]
    case "无刀做无限": out = ["刀"]
    default: break
    }
    return out + c.labelMissing
}

private func foxCountsAsJunk(_ row: RDRow) -> Bool {
    return row.group.contains("狐视作杂牌") || row.group == "刀起手"
}

private func count(_ tokens: [RDToken], _ card: String) -> Int {
    return tokens.filter { $0.card == card }.count
}

private let rdSpecialNames = ["帷幕", "步", "骨", "伺", "殒", "币"]

/// 特殊杂牌列里「腾格」能实例化成哪些牌：「骨/步之外腾格」去掉步和骨刺；「（≤N费）」按印刷费过滤
/// （起手里的牌不是本回合进手，脱水的快枪 1 费用不上，按印刷 3 费算）
private func tenggePool(_ raw: String) -> [RDCard] {
    var pool = raw.contains("骨/步之外")
        ? rdTenggeCards.filter { $0 != .shadowstep && $0 != .serratedBoneSpike }
        : rdTenggeCards
    if let r = raw.range(of: "≤[0-9]+费", options: .regularExpression) {
        let digits = raw[r].filter { $0.isNumber }
        if let limit = Int(digits) { pool = pool.filter { RDCards.def($0).printedCost <= limit } }
    }
    return pool
}

/// 起手里特殊牌的张数：公式里出现几次就几张；特殊杂牌列里写死的（不是「骨/步」二选一、不在括号里）
/// 没出现也放一张，「双步」放两张
private func specialCounts(_ row: RDRow, tokens: [[RDToken]]) -> (counts: [String: Int], findings: [String]) {
    var counts: [String: Int] = [:]
    var findings: [String] = []
    let raw = row.specialJunkRaw
    let listed = Set(rdSpecialNames.filter { raw.contains($0) })
    var required = raw.replacingOccurrences(of: "（[^）]*）", with: "", options: .regularExpression)
    required = required.replacingOccurrences(of: "骨/步之外", with: "")
    required = required.replacingOccurrences(of: "[^+/]+/[^+/]+", with: "", options: .regularExpression)
    if required.contains("双步") { counts["步"] = 2 }
    for name in rdSpecialNames where required.contains(name) {
        counts[name] = max(counts[name] ?? 0, 1)
    }
    for name in rdSpecialNames {
        let n = tokens.map { count($0, name) }.max() ?? 0
        if n > 0 {
            counts[name] = max(counts[name] ?? 0, n)
            if !listed.contains(name) { findings.append("公式用了特殊杂牌列没写的「\(name)」") }
        }
    }
    return (counts, findings)
}

private func declaredStart(_ c: RDCase, premise: Bool, crystals: Int?, tengge: [RDCard],
                           clearable: [RDCard], junk: Int) -> RDStart {
    let row = c.row
    var state = RDState(maxMana: crystals ?? 10, mana: row.cost ?? 99,
                        opponent: RDOpponent(health: 400))
    state.handLimit = 10
    var findings: [String] = []
    var parts: [String] = []

    func add(_ card: RDCard, copy: Bool = false) {
        let id = state.takeEntityId()
        state.hand.append(RDHandCard(entityId: id, card: card,
                                     enchants: copy ? [.set(1)] : [],
                                     statsOverride: copy ? RDStats(attack: 1, health: 1) : nil,
                                     isShadowOfDemise: card == .shadowOfDemise))
    }

    var junkUsed = 0
    if premise, let p = row.premise {
        state.luckyCometCharges = p.luckyComet
        state.cardsPlayedThisTurn = p.cardsPlayedThisTurn
        for e in p.enemyBoard {
            let id = state.takeEntityId()
            state.opponent.board.append(RDEnemyMinion(entityId: id, attack: e.attack, health: e.health,
                                                      taunt: false, divineShield: false,
                                                      immune: false, stealth: false))
        }
        if let side = p.sideboard { state.sideboard = side.compactMap { rdAbbreviations[$0] } }
    }
    if premise, let hand = row.premise?.startHand {
        for h in hand {
            guard let card = rdAbbreviations[h.card] else { continue }
            add(card, copy: h.copy)
        }
        parts.append(hand.map { $0.card + ($0.copy ? "c" : "") }.joined())
    } else {
        let missing = Set(declaredMissing(c) + c.deckOut)
        let minions = ["鱼", "狐", "刀", "暗", "牛", "晦"].filter { !missing.contains($0) }
        for m in minions { add(rdAbbreviations[m]!) }
        parts.append(minions.joined())
        if foxCountsAsJunk(row) && minions.contains("狐") { junkUsed += 1 }

        let tokenLists = [c.tokens] + (c.corrected.map { [$0] } ?? [])
        let specials = specialCounts(row, tokens: tokenLists)
        findings += specials.findings
        for name in rdSpecialNames {
            let n = specials.counts[name] ?? 0
            guard n > 0 else { continue }
            for _ in 0..<n { add(rdAbbreviations[name]!) }
            parts.append(name + (n > 1 ? "×\(n)" : ""))
            // 特殊杂牌 =「要求杂牌里有哪种」，计入杂牌数；「提前彗」各组注明步和伺不计
            if !(rdCometGroups.contains(row.group) && (name == "步" || name == "伺")) { junkUsed += n }
        }
        for card in tengge {
            add(card)
            parts.append("腾格=\(rdShort(card))")
            junkUsed += 1
        }
        for card in clearable {
            add(card)
            parts.append("杂=\(rdShort(card))")
            junkUsed += 1
        }
    }
    let rest = junk - junkUsed
    if rest < 0 {
        findings.append("特殊杂牌 / 可清杂 \(junkUsed) 张，多于杂牌数 \(junk)")
    }
    for _ in 0..<max(0, rest) {
        state.hand.append(RDHandCard.unmodeled(entityId: state.takeEntityId(), cardId: nil))
    }
    if rest > 0 { parts.append("杂×\(rest)") }
    if !c.deckOut.isEmpty {
        state.deck = RDDeck(c.deckOut.compactMap { rdAbbreviations[$0] }.map { ($0, 1) })
        parts.append("牌库 " + c.deckOut.joined())
    }
    return RDStart(state: state, text: parts.joined(separator: " + "), findings: findings,
                   illegal: startIllegality(state))
}

// MARK: - 严格重放（搜索口径 DFS）

private struct RDRun {
    var ok: Bool
    var failure: String?
    var actions: [RDAction] = []
    var damage = 0
    var sideboardTaken = 0
    /// 失败形态的短签名（卡在第几步的哪个 token / 伤害不等 / 起手非法），供 rdExpectedFailures 逐字比对
    var signature = ""
}

private func tokenIdentities(_ token: RDToken) -> [RDCard] {
    switch token.card {
    case "腾格": return rdTenggeCards
    case "杂": return rdClearableJunkCards
    default: return rdAbbreviations[token.card].map { [$0] } ?? []
    }
}

private func targetMatches(_ token: RDToken, identity: RDCard, target: RDTarget, state: RDState) -> Bool {
    // 伤害按打脸计（表中伤害 = 对英雄）
    if identity == .alexstrasza { return target == .enemyHero }
    guard let t = token.target, token.card != "殒" else { return true }
    switch target {
    case .enemyMinion:
        return t == "敌随"
    case .friendlyMinion(let id):
        guard let m = state.board.first(where: { $0.entityId == id }) else { return false }
        switch t {
        case "某随": return true
        case "鱼之外某随": return m.card != .spiritOfTheShark
        default: return rdAbbreviations[t] == m.card
        }
    default:
        return false
    }
}

/// 逐 token 在搜索口径的合法动作里找身份 / 目标 / 剩余法力都对得上的那个，DFS 回溯。
/// 失败的 (局面, 步数) 记下来不再走，保证不会指数爆炸。
///
/// 随从落位：不在下随从时逐格展开（那样每步分支 ×2.7，见 `testPlacementBranchingDiagnostics`），
/// 而是用 `RDBoardOrder` 在爆手的全场弹回 / 复制那一步展开所有「收回哪几张」的排法（**不设上限**，
/// 和逐格展开的结果集合相同）；走通后把排法翻译成每次下随从的落位，再用引擎带落位原样重放确认。
private func strictReplay(_ tokens: [RDToken], from start: RDState, expectedDamage: Int?) -> RDRun {
    guard !tokens.isEmpty else { return RDRun(ok: false, failure: "没有可重放的序列") }
    var dead = Set<UInt64>()
    var deepest = 0
    var path: [RDAction] = []
    var orders: [RDOrderDecision?] = []
    var finalState: RDState?
    var nodes = 0
    var listOptions = RDOptions.search
    listOptions.expandPlacements = false

    var deepestState = start
    func dfs(_ s: RDState, _ free: RDBoardConstraints, _ i: Int) -> Bool {
        nodes += 1
        if nodes > 2_000_000 { return false }
        if i > deepest {
            deepest = i
            deepestState = s
        }
        if i == tokens.count {
            if let d = expectedDamage, s.damageDealt != d { return false }
            finalState = s
            return true
        }
        let key = (s.canonicalHash() ^ (free.positionMask(s.board) &* 0x9e37_79b9_7f4a_7c15))
            &* 1_000_003 &+ UInt64(i)
        if dead.contains(key) { return false }
        let token = tokens[i]
        let wanted = tokenIdentities(token)
        // 可选步：先试不打
        if token.optional && dfs(s, free, i + 1) { return true }
        for action in RDEngine.legalActions(s, options: listOptions) {
            guard case .play(let eid, let identity, let target, _, _) = action,
                  let card = s.hand.first(where: { $0.entityId == eid }) else { continue }
            if token.card == "殒" {
                guard card.isShadowOfDemise else { continue }
                if let t = token.target, rdAbbreviations[t] != identity { continue }
            } else {
                guard wanted.contains(identity), !card.isShadowOfDemise else { continue }
            }
            if let cap = token.maxCost, RDCards.def(identity).printedCost > cap { continue }
            guard targetMatches(token, identity: identity, target: target, state: s),
                  let first = try? RDEngine.apply(action, to: s, options: .search) else { continue }
            for o in RDBoardOrder.outcomes(of: action, from: s, constraints: free, first: first,
                                           options: .search) {
                let next = o.state
                if let m = token.manaAfter, next.availableMana != m { continue }
                path.append(action)
                orders.append(o.decision)
                if dfs(next, o.constraints, i + 1) { return true }
                path.removeLast()
                orders.removeLast()
            }
        }
        dead.insert(key)
        return false
    }

    if let bad = startIllegality(start) {
        return RDRun(ok: false, failure: bad, signature: "起手\(start.hand.count)张")
    }
    if dfs(start, RDBoardConstraints.root(start), 0), let end = finalState {
        guard let placed = RDBoardOrder.assignPositions(path, decisions: orders, root: start, options: .search),
              let check = try? RDReplay.run(placed, from: start),
              check.damage == end.damageDealt, check.finalState.canonicalHash() == end.canonicalHash() else {
            return RDRun(ok: false, failure: "排法翻译成落位后重放结果不同", signature: "落位翻译失败")
        }
        return RDRun(ok: true, failure: nil, actions: placed, damage: end.damageDealt,
                     sideboardTaken: start.sideboard.count - end.sideboard.count)
    }
    if nodes > 2_000_000 {
        return RDRun(ok: false, failure: "DFS 超过 200 万节点", signature: "DFS上限")
    }
    if deepest == tokens.count {
        return RDRun(ok: false, failure: "序列走完但伤害 ≠ 表 \(expectedDamage ?? -1)",
                     signature: "伤害≠\(expectedDamage ?? -1)")
    }
    let t = tokens[deepest]
    let s = deepestState
    let hand = s.hand.map { c -> String in
        RDCards.def(c.card).isPlaceholder ? "杂" : rdShort(c.card) + "\(s.cost(of: c, as: c.card))"
    }.joined()
    let tokenText = "\(t.card)\(t.target.map { "-" + $0 } ?? "")\(t.manaAfter.map(String.init) ?? "")"
    return RDRun(ok: false, failure: "第 \(deepest + 1) 步「\(tokenText)」没有对得上的合法动作"
                 + "（此时法力 \(s.availableMana)，手 \(hand)，场 \(s.board.map { rdShort($0.card) }.joined())）",
                 signature: "第\(deepest + 1)步「\(tokenText)」")
}

// MARK: - 逐案例结论

private enum RDVerdict: String {
    case asIs = "原样重放通过"
    case premise = "前提下重放通过"
    case tableError = "原表有误·改正后通过"
    /// 截图只用文字允许、没印数字的清杂分支：卡牌顺序 + 印出来的那部分法力严格重放走得通、伤害达标。
    /// 算通过，但统计里和上面三种分开数
    case branchPass = "清杂分支可行（截图没印这一支的数字）"
    /// 以下四种都**不算通过**，统计里单独计数
    case invalid = "公式不成立"
    case notModeled = "规则未建模"
    case pendingUser = "待用户确认"
    case notAFormula = "非单回合公式"

    var passed: Bool {
        return self == .asIs || self == .premise || self == .tableError || self == .branchPass
    }
}

private struct RDCaseResult {
    var c: RDCase
    var verdict: RDVerdict = .invalid
    var problems: [String] = []
    /// 失败形态签名（通过的案例为空）
    var signature = ""
    var run: RDRun?
    var start: RDStart?
    var instantiation = ""
    /// 腾格实例化里用到的另一版牌组的牌（前提「需要另一版牌组的 X」）
    var otherDeck: [RDCard] = []
    var missing: [RDCard] = []
    var difficulty: RDDifficulty.Components?
    var crystals: Int?
}

/// 多重组合（可重复）：腾格 / 杂各几张，从候选里挑。用到另一版牌组的牌越少越先试
private func multisets(_ pool: [RDCard], size: Int) -> [[RDCard]] {
    guard size > 0 else { return [[]] }
    var out: [[RDCard]] = []
    func rec(_ from: Int, _ acc: [RDCard]) {
        if acc.count == size { out.append(acc); return }
        for i in from..<pool.count { rec(i, acc + [pool[i]]) }
    }
    rec(0, [])
    func other(_ m: [RDCard]) -> Int { return m.filter { rdTenggeOtherDeckCards.contains($0) }.count }
    return out.enumerated().sorted { (other($0.element), $0.offset) < (other($1.element), $1.offset) }
        .map { $0.element }
}

private func evaluate(_ c: RDCase) -> RDCaseResult {
    guard c.row.cost != nil else {
        var r = RDCaseResult(c: c)
        r.verdict = .notAFormula
        r.signature = "无费用无步骤"
        r.problems = ["截图这一格是说明文字，没有费用、杂牌数和可重放的步骤"]
        return r
    }
    guard let junk = c.row.junk else {
        var r = RDCaseResult(c: c)
        r.verdict = .pendingUser
        r.signature = "杂牌数未声明"
        r.problems = ["截图没有给这一回合的杂牌数，不从别的行继承；以下只是参考："]
        for j in 0...4 {
            let probe = evaluate(c, junk: j)
            r.problems.append("假设杂牌 \(j) 张 → "
                              + (probe.verdict.passed ? probe.verdict.rawValue : "\(probe.verdict.rawValue)（\(probe.signature)）"))
        }
        r.start = declaredStart(c, premise: c.row.premise != nil, crystals: c.crystals,
                                tengge: [], clearable: [], junk: 0)
        return r
    }
    return evaluate(c, junk: junk)
}

private func evaluate(_ c: RDCase, junk: Int) -> RDCaseResult {
    var best: RDCaseResult?
    var allProblems: [String] = []
    var signatures = Set<String>()
    /// 每个失败组合里决定结论的那次重放（用来判失败属于哪一类）
    var decisive: [(tokens: [RDToken], state: RDState)] = []
    let lists = [c.tokens] + (c.corrected.map { [$0] } ?? [])
    let kT = lists.map { count($0, "腾格") }.max() ?? 0
    let kZ = lists.map { count($0, "杂") }.max() ?? 0
    let damage = c.truncated ? nil : c.row.damage
    let pool = tenggePool(c.row.specialJunkRaw)
    for tengge in multisets(pool, size: kT) {
        for clearable in multisets(rdClearableJunkCards, size: kZ) {
            var r = RDCaseResult(c: c)
            var sig: String?
            func start(_ premise: Bool, _ corrected: Bool) -> RDStart {
                return declaredStart(c, premise: premise,
                                     crystals: corrected ? c.correctedCrystals : c.crystals,
                                     tengge: tengge, clearable: clearable, junk: junk)
            }
            func replay(_ premise: Bool, _ corrected: Bool) -> (RDRun, RDStart) {
                let s = start(premise, corrected)
                let tokens = corrected ? (c.corrected ?? c.tokens) : c.tokens
                return (strictReplay(tokens, from: s.state, expectedDamage: damage), s)
            }
            func fail(_ text: String, _ run: RDRun) {
                r.problems.append(text + (run.failure ?? "?"))
                sig = sig ?? run.signature
            }
            func extra(_ text: String, _ signature: String) {
                r.problems.append(text)
                sig = sig ?? signature
            }
            let hasErrata = c.corrected != nil || c.row.errata?.crystals != nil
            let plain = replay(false, false)
            var pass: (RDRun, RDStart)?
            switch (c.row.premise != nil, hasErrata) {
            case (false, false):
                r.verdict = .asIs
                if plain.0.ok { pass = plain } else { fail("原样重放失败：", plain.0) }
            case (true, false):
                r.verdict = .premise
                let p = replay(true, false)
                if p.0.ok { pass = p } else { fail("带前提仍失败：", p.0) }
                if plain.0.ok { extra("不带前提就能过，premise 多余", "premise多余") }
            case (false, true):
                r.verdict = .tableError
                let fixed = replay(false, true)
                if fixed.0.ok { pass = fixed } else { fail("改正后仍失败：", fixed.0) }
                if plain.0.ok { extra("原样就能过，tableErrata 不成立", "errata多余") }
            case (true, true):
                r.verdict = .tableError
                let orig = replay(true, false)
                let fixedNoPremise = replay(false, true)
                let fixed = replay(true, true)
                if fixed.0.ok { pass = fixed } else { fail("带前提改正后仍失败：", fixed.0) }
                if orig.0.ok { extra("带前提原样就能过，tableErrata 不成立", "errata多余") }
                if fixedNoPremise.0.ok { extra("改正后不带前提就能过，premise 多余", "premise多余") }
            }
            r.instantiation = (tengge.map { "腾格=" + rdShort($0) } + clearable.map { "杂=" + rdShort($0) })
                .joined(separator: "、")
            r.otherDeck = tengge.filter { rdTenggeOtherDeckCards.contains($0) }
            if let p = pass, r.problems.isEmpty {
                // 组合按「另一版牌组的牌用得少」先试，走到这里说明只用本牌组的组合全都失败：
                // 「需要另一版牌组的 X」是这条线成立的前提
                if !r.otherDeck.isEmpty && r.verdict == .asIs { r.verdict = .premise }
                if !c.branchPrinted { r.verdict = .branchPass }
                r.run = p.0
                r.start = p.1
                r.crystals = r.verdict == .tableError ? c.correctedCrystals : c.crystals
                r.missing = RDComponents.missing(in: p.1.state)
                r.difficulty = RDDifficulty.components(for: p.0.actions, sideboardCardsTaken: p.0.sideboardTaken)
                return r
            }
            let tag = r.instantiation.isEmpty ? "" : "[\(r.instantiation)] "
            allProblems += r.problems.map { tag + $0 }
            let decisiveStart = start(c.row.premise != nil, hasErrata)
            decisive.append((hasErrata ? (c.corrected ?? c.tokens) : c.tokens, decisiveStart.state))
            signatures.insert(sig ?? "?")
            if best == nil {
                r.start = start(c.row.premise != nil, false)
                r.missing = RDComponents.missing(in: r.start!.state)
                best = r
            }
        }
    }
    guard var r = best else {
        var r = RDCaseResult(c: c)
        r.verdict = .notModeled
        r.signature = "腾格无候选"
        r.problems = ["特殊杂牌列「\(c.row.specialJunkRaw)」的腾格在卡表里没有可实例化的真实牌"]
        return r
    }
    // 每个候选组合都卡在「腾格」那一步：找到的真实腾格牌都给不出表里要的效果 → 规则未建模；
    // 卡在别处（爆牌烧掉、法力对不上、起手非法…）→ 公式不成立
    let tenggeOnly = kT > 0 && signatures.allSatisfy { $0.contains("「腾格") }
    r.verdict = tenggeOnly ? .notModeled : .invalid
    r.signature = signatures.sorted().joined(separator: "；")
    r.problems = allProblems
    if r.verdict == .invalid, let kind = failureKind(decisive, damage: damage) {
        r.signature = kind + "｜" + r.signature
        r.problems.insert("失败类别：\(kind)", at: 0)
    }
    r.otherDeck = []
    return r
}

/// 公式不成立属于哪一类，由引擎判：
/// - 「印刷数字对不上」：去掉表里印的剩余法力、只按卡牌顺序重放，能打到表中伤害；
/// - 「爆手」：只按卡牌顺序也不行，但把手牌上限放到 30（没有牌会被烧掉）就行 —— 是舞动 / 复制时手牌放不下；
/// - 「其他」：两样都不行。
/// 起手就非法的组合不参与（它们的签名已经是「起手N张」）。全部组合都起手非法时返回 nil
private func failureKind(_ runs: [(tokens: [RDToken], state: RDState)], damage: Int?) -> String? {
    let legal = runs.filter { startIllegality($0.state) == nil }
    guard !legal.isEmpty else { return nil }
    func bare(_ t: [RDToken]) -> [RDToken] { return t.map { var u = $0; u.manaAfter = nil; return u } }
    if legal.contains(where: { strictReplay(bare($0.tokens), from: $0.state, expectedDamage: damage).ok }) {
        return "印刷数字对不上"
    }
    if legal.contains(where: { run in
        var roomy = run.state
        roomy.handLimit = 30
        return strictReplay(bare(run.tokens), from: roomy, expectedDamage: damage).ok
    }) {
        return "爆手"
    }
    return "其他"
}

// MARK: - 起手比较（缺件补齐后的参照）

private func handKeys(_ s: RDState) -> [String: Int] {
    var m: [String: Int] = [:]
    for c in s.hand where !RDCards.def(c.card).isPlaceholder {
        let k = "\(c.card.rawValue)/\(c.statsOverride != nil)/\(c.isShadowOfDemise)/\(c.enchants.count)"
        m[k, default: 0] += 1
    }
    return m
}

private func deckKey(_ s: RDState) -> String {
    return RDCard.allCases.map { String(s.deck.count($0)) }.joined(separator: ",")
        + "|" + s.sideboard.map { String($0.rawValue) }.joined(separator: ",")
}

private func isSubset(_ a: [String: Int], _ b: [String: Int]) -> Bool {
    return a.allSatisfy { b[$0.key, default: 0] >= $0.value }
}

private func rdShort(_ card: RDCard) -> String {
    switch card {
    case .deafen: return "致聋"
    case .blackwaterCutlass: return "弯刀"
    case .evasion: return "闪避"
    case .backstab: return "背刺"
    case .pocketSand: return "袋底藏沙"
    case .dehydrate: return "脱水"
    default:
        return rdAbbreviations.first { $0.value == card }?.key ?? "\(card)"
    }
}

private func describe(_ actions: [RDAction], from start: RDState) -> String {
    var s = start
    var out: [String] = []
    for a in actions {
        if case .play(_, let identity, let target, let choices, let position) = a {
            var t = rdShort(identity)
            // 落位：nil = 放最右；否则「(第N格)」从左数 1 起
            if let p = position { t += "(第\(p + 1)格)" }
            switch target {
            case .friendlyMinion(let id):
                if let m = s.board.first(where: { $0.entityId == id }) { t += "-" + rdShort(m.card) }
            case .enemyMinion: t += "-敌随"
            default: break
            }
            let picks = choices.map { c -> String in
                if case .pick(let card) = c { return rdShort(card) }
                return "?"
            }
            if !picks.isEmpty { t += "[" + picks.joined() + "]" }
            out.append(t)
        }
        s = (try? RDEngine.apply(a, to: s)) ?? s
        out[out.count - 1] += "\(s.availableMana)"
    }
    return out.joined(separator: " ")
}

// MARK: -

class RedDragonFormulaTests: HSTrackerTests {

    private static var rows: [RDRow] = []
    private static var cases: [RDCase] = []
    private static var results: [RDCaseResult] = []

    override class func setUp() {
        super.setUp()
        rows = loadRows()
        cases = makeCases(rows)
        results = cases.map { evaluate($0) }
    }

    /// 状态闸门、补搜份额、束宽都用生产默认；只放大 CPU 兜底 —— Debug（-Onone）比 -O 慢约 12 倍，
    /// 不放大的话先撞上的是 CPU，结果随机器负载变
    private func searchConfig() -> RedDragonConfig {
        var config = RedDragonConfig()
        config.cpuBudget = 900
        config.missingPieceBudget = 900
        return config
    }

    /// 测试配置下从某个起手搜一遍；同一标签只算一次（采样补搜那条测试和逐案例搜索共用结果）
    private static var searchCache: [String: RedDragonResult] = [:]
    private func defaultSearch(_ root0: RDState, target: Int, _ label: String) -> RedDragonResult {
        if let cached = RedDragonFormulaTests.searchCache[label] { return cached }
        var root = root0
        root.opponent.health = target
        root.opponent.armor = 0
        let result = RedDragonSearch.solve(root, config: searchConfig())
        RedDragonFormulaTests.searchCache[label] = result
        return result
    }

    /// 两遍共用一份总状态预算：总展开数不超过上限 + 一个节点的子动作数（上限在节点之间检查）
    private func assertSharedStateBudget(_ result: RedDragonResult, config: RedDragonConfig, _ label: String) {
        guard let cap = config.maxStatesExpanded else { return }
        let slack = config.maxActionsPerNode ?? 64
        let mainCap = Int(Double(cap) * (1 - config.samplingShare))
        XCTAssertLessThanOrEqual(result.statesExpanded, cap + slack,
                                 "\(label) 主搜索 + 补搜共展开 \(result.statesExpanded) 态，超过总预算 \(cap)")
        if config.samplingPassWidth != nil {
            XCTAssertLessThanOrEqual(result.mainStatesExpanded, mainCap + slack,
                                     "\(label) 主搜索展开 \(result.mainStatesExpanded) 态，侵占了补搜份额")
        }
        if result.termination == .budgetExceeded {
            XCTAssertLessThan(result.cpuTime, config.cpuBudget, "\(label) 撞上的是 CPU 兜底而不是状态闸门")
        }
    }

    // MARK: 1. 转录无漏

    /// 80 = 75（T1 转录）+ 5 条备注 / 组注里的公式（T2a 补，id 带 -n1）；案例 = 行 × 展开变体 × 起手缺法 × 行标签缺件
    func testFixtureCoversEveryFormulaInScreenshots() {
        let rows = RedDragonFormulaTests.rows
        XCTAssertEqual(rows.count, 80, "fixture 应有 80 行")
        XCTAssertEqual(rows.filter { $0.fromNote }.count, 5, "备注里的公式 5 条")
        XCTAssertEqual(Set(rows.map { $0.id }).count, rows.count, "id 不能重复")
        XCTAssertEqual(RedDragonFormulaTests.cases.count, 90,
                       "80 行 + t1-48-08 多 1 条展开 + t2-wuhu-03 / t2-daoqs-02 各 4 条清杂分支（各多 3 条）"
                       + " + t2-chou-01 多 2 种缺法 + t1-pre-03 缺暗 / 缺晦两种")
    }

    // MARK: 2. 每个案例都有引擎结论

    func testEveryCaseHasEngineVerdict() {
        var counts: [String: Int] = [:]
        var passed = 0, failed = 0
        var lines: [String] = []
        for r in RedDragonFormulaTests.results {
            counts[r.verdict.rawValue, default: 0] += 1
            if r.verdict.passed {
                passed += 1
                XCTAssertNotNil(r.run)
                XCTAssertTrue(r.signature.isEmpty)
                if rdExpectedFailures[r.c.id] != nil {
                    XCTFail("\(r.c.id) 现在通过了（\(r.verdict.rawValue)），从 rdExpectedFailures 里删掉")
                }
            } else {
                failed += 1
                XCTAssertNil(r.run)
                let expected = rdExpectedFailures[r.c.id]
                lines.append("   \(r.verdict.rawValue) \(r.c.id)：\(expected?.reason ?? "?")\n      签名：\(r.signature)"
                             + "\n      引擎：" + r.problems.prefix(6).joined(separator: "；"))
                if let e = expected {
                    XCTAssertEqual(r.verdict, e.verdict, "\(r.c.id) 结论变了")
                    XCTAssertEqual(r.signature, e.signature, "\(r.c.id) 失败形态变了")
                } else {
                    XCTFail("\(r.c.id) 没通过且不在 rdExpectedFailures：\(r.verdict.rawValue)「\(r.signature)」")
                }
            }
            for f in r.start?.findings ?? [] { lines.append("   发现 \(r.c.id)：\(f)") }
        }
        for id in rdExpectedFailures.keys where !RedDragonFormulaTests.results.contains(where: { $0.c.id == id }) {
            XCTFail("rdExpectedFailures 里的 \(id) 不是现有案例")
        }
        print((["== 公式表结论：通过 \(passed)（不含未验证）/ 未验证 \(failed)；"
                + counts.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: " / ")]
               + lines).joined(separator: "\n"))

        // 有多条清杂分支的行：每支一个结论，整行结论 = 有一支通过就成立（并注明是哪支）
        var rowLines = ["== 多分支行的整行结论"]
        for row in RedDragonFormulaTests.rows where row.expandedPrinted.contains(false) {
            let branches = RedDragonFormulaTests.results.filter { $0.c.row.id == row.id }
            let ok = branches.filter { $0.verdict.passed }
            rowLines.append("   \(row.id)：" + (ok.isEmpty ? "整行不成立" : "整行成立（靠 "
                            + ok.map { $0.c.branchLabel ?? $0.c.id }.joined(separator: "、") + "）"))
            for b in branches {
                rowLines.append("      \(b.c.branchLabel ?? b.c.id)：\(b.verdict.rawValue)"
                                + (b.signature.isEmpty ? "" : "「\(b.signature)」"))
            }
            XCTAssertEqual(branches.count, row.expandedLines.count, "\(row.id) 每条分支都要有结论")
        }
        print(rowLines.joined(separator: "\n"))
        var explicit = ["== 严格重放的显式动作序列（(第N格) = 随从落位，从左数；不写 = 放最右）"]
        for r in RedDragonFormulaTests.results {
            guard let run = r.run, let s = r.start else { continue }
            let other = r.otherDeck.isEmpty ? "" : "〔需要另一版牌组的 \(r.otherDeck.map { rdShort($0) }.joined(separator: "、"))〕"
            explicit.append("   \(r.c.id)\(other)：" + describe(run.actions, from: s.state))
        }
        print(explicit.joined(separator: "\n"))
    }

    // MARK: 2b. 落位带来的分支数

    /// 严格重放路径上每一步：合法动作数（含落位） vs 去掉落位后的动作数。只打印，给落位的代价一个数
    func testPlacementBranchingDiagnostics() {
        var withPos = 0, withoutPos = 0, steps = 0, stepsWithAlt = 0
        for r in RedDragonFormulaTests.results {
            guard let run = r.run, var s = r.start?.state else { continue }
            for a in run.actions {
                let legal = RDEngine.legalActions(s, options: .search)
                let base = legal.filter {
                    if case .play(_, _, _, _, let p) = $0 { return p == nil }
                    return true
                }
                withPos += legal.count
                withoutPos += base.count
                steps += 1
                if legal.count > base.count { stepsWithAlt += 1 }
                s = (try? RDEngine.apply(a, to: s, options: .search)) ?? s
            }
        }
        print(String(format: "== 落位分支：严格重放路径 %d 步，其中 %d 步有可选落位；合法动作合计 %d（不含落位 %d，×%.2f）",
                     steps, stepsWithAlt, withPos, withoutPos, Double(withPos) / Double(max(1, withoutPos))))
    }

    // MARK: 3. 可反推 + 4. 齐件 / 缺件

    func testSearchFromDeclaredStartAndComponentGroups() {
        let config = searchConfig()
        let results = RedDragonFormulaTests.results.filter { $0.run != nil }
        var lines: [String] = []
        var searchDamage: [String: Int] = [:]
        var failures: [String] = []

        struct Stat {
            var cases = 0, searchOK = 0
            var damages: [Int: Int] = [:]
            var difficulties: [Double] = []
            var cpu = 0.0
            var states: [Int] = []
        }
        var stats: [Bool: Stat] = [true: Stat(), false: Stat()]

        var sampledNeeded: [String] = []
        func search(_ root0: RDState, target: Int, _ label: String) -> RedDragonResult {
            var root = root0
            root.opponent.health = target
            root.opponent.armor = 0
            let result = defaultSearch(root0, target: target, label)
            if result.samplingPassRan || result.boardOrderPassRan {
                let passes = (result.boardOrderPassRan ? ["排法补搜"] : []) + (result.samplingPassRan ? ["采样补搜"] : [])
                sampledNeeded.append("\(label)：主搜索 \(result.mainStatesExpanded) 态未斩杀，跑了"
                                     + passes.joined(separator: "、") + "，合计 "
                                     + "\(result.statesExpanded) 态，伤害 \(result.maxDamage)"
                                     + (result.isLethal ? "（斩杀）" : ""))
            }
            assertSharedStateBudget(result, config: config, label)
            XCTAssertEqual(result.placementTranslationFailures, 0, "\(label) 有线因落位翻译失败被丢掉")
            if let chosen = result.chosenLine {
                XCTAssertNotNil(RDReplay.validate(chosen.actions, from: root, expectedDamage: chosen.damage),
                                "\(label) chosenLine 重放失败")
            }
            for line in result.lethalLines {
                XCTAssertNotNil(RDReplay.validate(line.actions, from: root, expectedDamage: line.damage),
                                "\(label) lethalLine 重放失败")
            }
            return result
        }

        for r in results {
            guard let start = r.start, let run = r.run else { continue }
            let complete = r.missing.isEmpty
            // 预启动没有伤害列：血量给足让搜索跑满，达标线 = 重放伤害
            let target = r.c.row.damage ?? run.damage
            let result = search(start.state, target: r.c.row.damage ?? 400, r.c.id)
            searchDamage[r.c.id] = result.maxDamage
            var stat = stats[complete]!
            stat.cases += 1
            if result.maxDamage >= target { stat.searchOK += 1 } else {
                failures.append("\(r.c.id) 搜索 \(result.maxDamage) < 目标 \(target)"
                                + "（\(result.termination.rawValue)，\(result.statesExpanded) 态）")
            }
            if let d = r.c.row.damage { stat.damages[d, default: 0] += 1 }
            let score = r.difficulty?.score ?? 0
            stat.difficulties.append(score)
            stat.cpu += result.cpuTime
            stat.states.append(result.statesExpanded)
            stats[complete] = stat

            let group = complete ? "齐件" : "缺件（缺" + r.missing.map { rdShort($0) }.joined() + "）"
            var cond: [String] = []
            if r.verdict != .asIs, let p = r.c.row.premise { cond.append("前提：" + p.summary) }
            if r.verdict == .tableError || (r.verdict == .branchPass && r.c.corrected != nil),
               let e = r.c.row.errata { cond.append("改正：" + e.cells.joined(separator: "；")) }
            if let label = r.c.branchLabel { cond.append("分支：" + label) }
            if !r.otherDeck.isEmpty {
                cond.append("前提：需要另一版牌组的 " + r.otherDeck.map { rdShort($0) }.joined(separator: "、"))
            }
            if !r.instantiation.isEmpty { cond.append(r.instantiation) }
            for f in start.findings { cond.append("⚠️ " + f) }
            lines.append("| \(r.c.id) | \(group) | \(r.verdict.rawValue) | \(start.text)"
                         + " | \(cond.isEmpty ? "—" : cond.joined(separator: "；"))"
                         + " | \(r.c.row.damage.map { String($0) } ?? "—") | \(result.maxDamage)"
                         + String(format: " | %.0f | %d/%d | %.2fs |", score, result.mainStatesExpanded,
                                  result.statesExpanded, result.cpuTime))
        }
        for f in failures { XCTFail(f) }

        // 缺件：把缺的组件换掉一张不可打的杂牌（没有杂牌就加一张），搜索要到「起手被它包含的齐件案例」与本案例表伤的较大者
        var supplementLines: [String] = []
        let completes = results.filter { $0.missing.isEmpty && $0.c.row.damage != nil }
        for r in results where !r.missing.isEmpty {
            guard var supp = r.start?.state else { continue }
            for card in r.missing {
                if let i = supp.hand.firstIndex(where: { RDCards.def($0.card).isPlaceholder }) {
                    supp.hand.remove(at: i)
                }
                let id = supp.takeEntityId()
                supp.hand.append(RDHandCard(entityId: id, card: card))
            }
            let missingText0 = r.missing.map { rdShort($0) }.joined()
            // 追加手牌同样要过起手合法性：补完超过手牌上限的，这个「补齐」在真实对局里不存在
            if let bad = startIllegality(supp) {
                supplementLines.append("   \(r.c.id) 补\(missingText0)：\(bad)，补齐不成立，不搜")
                continue
            }
            let premiseKey = r.verdict == .asIs ? "" : (r.c.row.premise?.key ?? "")
            let suppKeys = handKeys(supp)
            let refs = completes.filter { ref in
                guard let refStart = ref.start?.state else { return false }
                let refKey = ref.verdict == .asIs ? "" : (ref.c.row.premise?.key ?? "")
                return refKey == premiseKey
                    && (ref.crystals ?? 10) <= (r.crystals ?? 10)
                    && refStart.mana <= supp.mana
                    && deckKey(refStart) == deckKey(supp)
                    && isSubset(handKeys(refStart), suppKeys)
            }
            let missingText = missingText0
            let best = refs.max { ($0.c.row.damage ?? 0) < ($1.c.row.damage ?? 0) }
            let goal = max(best?.c.row.damage ?? 0, r.c.row.damage ?? 0)
            guard goal > 0 else {
                supplementLines.append("   \(r.c.id) 补\(missingText)：没有可比的齐件案例，本案例也没有伤害列")
                continue
            }
            let damage = search(supp, target: goal, r.c.id + " 补齐").maxDamage
            // 本案例自己的线在补齐后的起手上是否仍成立（严格重放，同一份 token）
            var ownLine = ""
            if let d = r.c.row.damage, let tokens = r.verdict == .tableError ? (r.c.corrected ?? r.c.tokens) : Optional(r.c.tokens) {
                let ok = strictReplay(tokens, from: supp, expectedDamage: r.c.truncated ? nil : d).ok
                ownLine = ok ? "；本案例的线补齐后严格重放仍通过" : "；本案例的线补齐后严格重放不通过"
            }
            let refText = best.map { "参照 \($0.c.id) \($0.c.row.damage ?? 0)" } ?? "无可比齐件案例，目标取本案例表伤"
            supplementLines.append("   \(r.c.id) 补\(missingText) → 搜索 \(damage)，目标 \(goal)（\(refText)\(ownLine)）"
                                   + (damage >= goal ? "" : "  ⚠️"))
            XCTAssertGreaterThanOrEqual(damage, goal, "\(r.c.id) 补\(missingText) 后搜索 \(damage) < \(goal)")
        }

        var out = ["== 逐案例（案例 / 分组 / 结论 / 起手 / 前提·改正·实例化 / 表伤 / 搜伤 / 难度 / 主搜索·合计态 / Debug CPU）",
                   "| 案例 | 分组 | 结论 | 起手 | 前提 / 改正 / 实例化 | 表中伤害 | 搜索伤害 | 难度分 | 主搜索/合计态 | Debug CPU |",
                   "|---|---|---|---|---|---|---|---|---|---|"]
        out.append(contentsOf: lines)
        for complete in [true, false] {
            let s = stats[complete]!
            let d = s.difficulties.sorted()
            let dmg = s.damages.sorted { $0.key < $1.key }.map { "\($0.key)×\($0.value)" }.joined(separator: " ")
            var tiers: [String: Int] = [:]
            for x in d { tiers[RDDifficulty.tier(x).rawValue, default: 0] += 1 }
            out.append("== \(complete ? "齐件" : "缺件")：\(s.cases) 案例，搜索达标 \(s.searchOK)"
                       + "；表中伤害 \(dmg)"
                       + (d.isEmpty ? "" : String(format: "；难度 min %.0f / 中位 %.0f / max %.0f",
                                                   d.first!, d[d.count / 2], d.last!))
                       + "；分档 " + tiers.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }
                            .joined(separator: " ")
                       + String(format: "；搜索 CPU 合计 %.1fs，最多 %d 态", s.cpu, s.states.max() ?? 0))
        }
        out.append("== 缺件补齐")
        out.append(contentsOf: supplementLines)
        out.append("== 跑了采样补搜的（主搜索未斩杀）")
        out.append(contentsOf: sampledNeeded.map { "   " + $0 })
        print(out.joined(separator: "\n"))
    }

    // MARK: 5. 生产配置的代价（只在 Release 有意义）

    /// 默认配置（生产路径，一个字段都不改）从每个案例起手搜一遍，报平均 / 最慢 CPU 与达标数。
    /// Debug 下跳过（-Onone 的数字没有参考价值）；用 Debug 配置加 `SWIFT_OPTIMIZATION_LEVEL=-O` 跑
    /// （`-configuration Release` 的测试 target 编不过，见任务书执行结果）。
    func testProductionConfigCostRelease() throws {
        // 测试 target 不定义 DEBUG（只有 HSTTEST），`#if DEBUG` 在 Debug 下也不跳，所以按优化级别判断
        if _isDebugAssertConfiguration() {
            throw XCTSkip("只在 -O 下测生产配置的 CPU")
        }
        let config = RedDragonConfig()
        var times: [(String, Double, Bool, Int)] = []
        var sampledIds: [String] = []
        for r in RedDragonFormulaTests.results {
            guard var root = r.start?.state, let run = r.run else { continue }
            let target = r.c.row.damage ?? run.damage
            root.opponent.health = r.c.row.damage ?? 400
            let result = RedDragonSearch.solve(root, config: config)
            assertSharedStateBudget(result, config: config, r.c.id)
            if result.samplingPassRan { sampledIds.append(r.c.id) }
            if r.c.id == "t2-wuhui-03" {
                XCTAssertTrue(result.samplingPassRan, "默认配置下 t2-wuhui-03 应跑采样补搜")
                XCTAssertTrue(result.isLethal, "默认配置下 t2-wuhui-03 应由补搜救回")
            }
            times.append((r.c.id, result.cpuTime, result.maxDamage >= target, result.statesExpanded))
        }
        print("== -O 生产配置跑了采样补搜的：" + sampledIds.joined(separator: " "))
        let total = times.reduce(0.0) { $0 + $1.1 }
        let sorted = times.sorted { $0.1 > $1.1 }
        var out = [String(format: "== -O 生产配置：%d 案例，平均 %.3fs，最慢 %.3fs（%@），达标 %d",
                          times.count, total / Double(max(1, times.count)), sorted.first?.1 ?? 0,
                          sorted.first?.0 ?? "-", times.filter { $0.2 }.count)]
        for t in sorted.prefix(10) {
            out.append(String(format: "   %@ %.3fs %d 态 %@", t.0, t.1, t.3, t.2 ? "达标" : "⚠️ 未达标"))
        }
        print(out.joined(separator: "\n"))
        for t in times where !t.2 { XCTFail("\(t.0) 生产配置下未达标") }
    }

    // MARK: 5b. 采样补搜在默认状态预算下确实会跑

    /// t2-wuhui-03：默认的状态闸门和补搜份额（Debug 只放大 CPU 兜底）下，主搜索那一半预算找不到斩杀，
    /// 补搜用剩下的预算找到。同时核对两遍共用一份总预算
    func testSamplingPassRescuesWuhui03UnderDefaultBudget() {
        guard let r = RedDragonFormulaTests.results.first(where: { $0.c.id == "t2-wuhui-03" }),
              let root = r.start?.state, let damage = r.c.row.damage else {
            XCTFail("t2-wuhui-03 没有通过严格重放")
            return
        }
        let config = searchConfig()
        // 和逐案例搜索共用同一次结果（同起手、同配置）
        let full = defaultSearch(root, target: damage, r.c.id)
        // solve 只在主搜索没斩杀时才跑补搜，所以 samplingPassRan 本身就说明主搜索那一半预算没找到斩杀
        XCTAssertTrue(full.samplingPassRan, "主搜索没斩杀时应跑补搜")
        XCTAssertTrue(full.isLethal, "补搜应找到 \(damage) 斩杀，实际 \(full.maxDamage)")
        assertSharedStateBudget(full, config: config, "t2-wuhui-03")
        XCTAssertGreaterThan(full.statesExpanded, full.mainStatesExpanded, "补搜应展开了状态")
        print("== t2-wuhui-03：主搜索 \(full.mainStatesExpanded) 态未斩杀；补搜后合计 "
              + "\(full.statesExpanded) 态伤害 \(full.maxDamage)（总预算 \(config.maxStatesExpanded ?? 0)）")
    }

    // MARK: 6. 确定性

    func testDeterminism() {
        guard let r = RedDragonFormulaTests.results.first(where: { $0.c.id == "t1-32-01" }),
              var root = r.start?.state else {
            XCTFail("t1-32-01 缺失")
            return
        }
        root.opponent = RDOpponent(health: 32)
        // CPU 预算截断的位置取决于机器负载，确定性要靠可复现的闸门：这里用状态数上限，
        // 并把预算放得足够大，保证两次都是被同一个闸门在同一个位置截断。
        var config = RedDragonConfig()
        config.cpuBudget = 600
        config.maxStatesExpanded = 20_000
        let a = RedDragonSearch.solve(root, config: config)
        let b = RedDragonSearch.solve(root, config: config)
        XCTAssertEqual(a.statesExpanded, b.statesExpanded)
        XCTAssertEqual(a.depthReached, b.depthReached)
        XCTAssertEqual(a.maxDamage, b.maxDamage)
        XCTAssertEqual(a.isLethal, b.isLethal)
        XCTAssertEqual(a.termination, b.termination)
        XCTAssertEqual(a.lethalLines.count, b.lethalLines.count)
        for (x, y) in zip(a.lethalLines, b.lethalLines) {
            XCTAssertEqual(x.damage, y.damage)
            XCTAssertEqual(x.difficulty, y.difficulty)
            XCTAssertEqual(x.actions, y.actions)
        }
        XCTAssertEqual(a.chosenLine?.actions, b.chosenLine?.actions)
        XCTAssertEqual(a.missingPieces, b.missingPieces)
    }
}
