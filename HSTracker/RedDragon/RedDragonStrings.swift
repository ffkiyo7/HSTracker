//
//  RedDragonStrings.swift
//  HSTracker
//
//  红龙辅助自有的界面文案，全部集中在这里。AGENTS.md 不许给 .xcstrings 增 key，所以直接写中文字面量；
//  卡名不在这里，跟随应用语言从卡库取（`Cards.any(byId:)`）。
//

import Foundation
@testable import RedDragonCore

enum RDText {
    // MARK: overlay 角标

    static let assistantName = "红龙辅助"
    static let lethal = "可斩杀"
    static let lethalIfDraw = "需抽到才斩杀"
    static let notFound = "未搜到斩杀"
    static let provenNotLethal = "不能斩杀"
    static let computing = "正在算…"
    static let truncated = "被截断"
    static let opponentSecrets = "⚠ 对方有奥秘"
    static let quizChip = "答题"
    static let quizOnLine = "✓ 仍在斩杀线上"
    static let quizOffLine = "✗ 已不可能斩杀"

    static func margin(_ m: Int) -> String {
        return m >= 0 ? "+\(m)" : "差 \(-m)"
    }

    static func tier(_ t: RDDifficulty.Tier) -> String {
        switch t {
        case .basic: return "基础"
        case .advanced: return "进阶"
        case .hard: return "困难"
        }
    }

    static func level(_ l: RDRevealLevel) -> String {
        switch l {
        case .verdict: return "判定"
        case .order: return "顺序"
        }
    }

    // MARK: overlay 文字行

    static func nextStep(_ text: String, total: Int, shown: Int) -> String {
        let tail = total > shown ? "（共 \(total) 步）" : ""
        return "下一步：" + text + tail
    }

    static let myHero = "英雄"
    static let enemyHero = "对方英雄"
    static let attackVerb = " 攻击 "
    static let targetArrow = " → "

    /// 一步的文字，overlay 自己按结构化的 `RDStep` 拼（不用 T2b 的 `nextStepText`：那里的 ⚔ 在 AR LisuGB 里没有字形）。
    /// 打牌 = 卡名［→ 目标］［（选 X / 抽到 X）］；攻击 = 攻击方 攻击 目标；英雄技能 = 技能名
    static func step(_ step: RDStep, cardName: (String) -> String) -> String {
        func target(_ t: RDStepTarget) -> String {
            switch t {
            case .friendlyMinion(_, let id), .enemyMinion(_, let id): return cardName(id)
            case .enemyHero: return enemyHero
            case .ownHero: return myHero
            }
        }
        switch step.kind {
        case .attack:
            return (step.attacker.map(target) ?? myHero) + attackVerb + (step.target.map(target) ?? enemyHero)
        case .heroPower:
            return cardName(RDCards.heroPowerId)
        case .playFromHand, .playGenerated:
            var s = step.cardId.map(cardName) ?? ""
            if let t = step.target { s += targetArrow + target(t) }
            let discovered = step.picks.filter { !$0.isDraw }.map { cardName($0.cardId) }
            let drawn = step.picks.filter { $0.isDraw }.map { cardName($0.cardId) }
            if !discovered.isEmpty { s += "（选 " + discovered.joined(separator: " / ") + "）" }
            if !drawn.isEmpty { s += "（抽到 " + drawn.joined(separator: " / ") + "）" }
            return s
        }
    }

    static func branch(_ names: [String], damage: Int) -> String {
        return "抽到 " + names.joined(separator: " + ") + " → \(damage)"
    }

    static func missing(_ names: [String], incomplete: Bool) -> String {
        return "缺：" + names.joined(separator: " 或 ") + (incomplete ? " 等" : "")
    }

    /// 面板放不下、收起了几行（角标末尾的小字）
    static func droppedLines(_ n: Int) -> String {
        return "收起 \(n) 条"
    }

    // MARK: 准备线 / 公式（T4）

    static let heal16Title = "奶 16"
    static let preLaunchTitle = "预启动"
    static let doomed = "等死"
    static let doomedNote = "凑不出奶 16"
    static let deviated = "已偏离，重算中"
    static let lethalLabel = "斩杀"
    static let healLabel = "奶16"
    static let preLaunchLabel = "预启动"
    static let leftoverPrefix = "回合末："
    static let leftBoard = "场 "
    static let leftHand = "手 "
    static let recheckAfter = "看结果后重算"

    static func nextTurnPotential(_ n: Int) -> String {
        return "下回合约 \(n)"
    }

    static func drawsContinue(_ cards: [RDCard]) -> String {
        return "抽到" + cards.map(abbr).joined(separator: "/") + "才继续"
    }

    /// 公式表的牌名缩写（`HSTrackerTests/Fixtures/RedDragon/formulas.json` 的 `notation`）。
    /// 表里没有缩写的牌（不在公式里出现过的）取最常用的叫法
    static func abbr(_ card: RDCard) -> String {
        switch card {
        case .spiritOfTheShark: return "鱼"
        case .foxyFraud: return "狐"
        case .scabbsCutterbutter: return "刀"
        case .shadowcaster: return "暗"
        case .etcBandManager: return "牛"
        case .darkscaleBroodmother: return "晦"
        case .alexstrasza: return "龙"
        case .bounceAround: return "舞"
        case .potionOfIllusion: return "幻"
        case .shadowstep: return "步"
        case .serratedBoneSpike: return "骨"
        case .preparation: return "伺"
        case .shadowOfDemise: return "殒"
        case .coin: return "币"
        case .shroudOfConcealment: return "帷幕"
        case .goneFishin: return "探底"
        case .digForTreasure: return "挖宝"
        case .cultistMap: return "地图"
        case .blackwaterCutlass: return "黑刀"
        case .deafen: return "聋"
        case .quickPick: return "矿锄"
        case .swindle: return "骗"
        case .evasion: return "闪"
        case .backstab: return "背刺"
        case .pocketSand: return "沙"
        case .dehydrate: return "脱水"
        case .junkPlaceholder: return "杂"
        case .freeSlotPlaceholder: return "腾格"
        }
    }

    /// 一步的公式写法：缩写 + ［-目标］ + 打完剩余的费用，例如「鱼4」「骨-狐2」「龙-奶0」。
    /// 殒命暗影写它变成的那张牌的缩写 +「（殒）」，例如「步（殒）-晦4」；攻击写「攻击方攻目标」（不带费用）。对敌方英雄的龙不写目标（公式表的惯例）
    static func formulaToken(_ t: RDFormulaToken) -> String {
        func target(_ x: RDFormulaTarget) -> String {
            switch x {
            case .card(let c): return abbr(c)
            case .enemyMinion: return "怪"
            case .enemyHero: return "脸"
            case .ownHero: return "奶"
            }
        }
        switch t.kind {
        case .heroPower:
            return "技\(t.mana)"
        case .attack:
            return (t.card.map(abbr) ?? "英") + "攻" + (t.target.map(target) ?? "脸")
        case .play:
            var s = (t.card.map(abbr) ?? "") + (t.original ? "（殒）" : "") + (formulaPicks(t) ?? "")
            if let x = t.target, x != .enemyHero || t.card != .alexstrasza { s += "-" + target(x) }
            return s + "\(t.mana)"
        }
    }

    /// 乐队经理这步拿哪几张：「（龙舞）」，面板上换一个颜色。没有发现就 nil
    static func formulaPicks(_ t: RDFormulaToken) -> String? {
        return t.picks.isEmpty ? nil : "（" + t.picks.map(abbr).joined() + "）"
    }

    /// 一步后面跟的说明（抽到什么才继续 / 垂钓类看结果后重算），没有就 nil
    static func formulaNote(_ t: RDFormulaToken) -> String? {
        if !t.draws.isEmpty { return drawsContinue(t.draws) }
        if t.kind == .play, t.card == .goneFishin || t.card == .cultistMap { return recheckAfter }
        return nil
    }

    static let singleTurnInsufficient = "单回合不够，考虑预启动"
    static let boardDanger = "场面危险，必须下怪"
    static let heroTarget = "英雄"

    // MARK: 设置页

    static let prefsTitle = "红龙辅助"
    static let prefsEnable = "启用红龙辅助"
    static let prefsEnableNote = "只在红龙贼套牌（E.T.C. 乐队带阿莱克丝塔萨）的对局里出现，其它套牌不做任何计算。开关立即生效，不用重启。"
    static let prefsReveal = "进回合默认揭示到："
    static let prefsRevealNote = "判定只给能不能斩；顺序在浮窗里给出怎么打（手牌和场面上不画任何标记）。"
        + "选「顺序」时斩杀线一律给顺序，中途变简单也不降档；选「判定」时可用热键升到顺序，最简单的线是「基础」档则不给顺序。"
        + "只有「困难」线时默认直接给顺序。"
        + "选「顺序」且没开答题时，浮窗给出完整公式（牌名缩写 + 打完剩余的费用，按舞 / 幻分段换行）并锁定："
        + "每打一步只核对在不在线上，在线上就划掉这一步，打偏或对方介入导致走不通时旧公式置灰并标「已偏离，重算中」，算出新线再换。"
        + "斩不了且场面危险时给奶 16 的线（凑不出就提示「等死」），不受揭示档和答题影响。"
    static let prefsQuiz = "答题模式"
    static let prefsQuizNote = "不显示怎么打；每做一步判卷：绿 = 仍在斩杀线上，红 = 已不可能斩杀（只在证明了不能斩时才判红）。"
    static let prefsHotkeys = "热键（只在炉石在前台时响应，不需要辅助功能权限）"

    static func hotkeyLine(_ keys: String, _ action: String) -> String {
        return keys + "　" + action
    }

    static let hotkeyRaise = "升一档揭示"
    static let hotkeyLower = "降一档揭示"
    static let hotkeyQuiz = "开 / 关答题模式"
}
