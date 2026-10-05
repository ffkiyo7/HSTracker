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
    static let stale = "已过时"
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
        case .cards: return "参与牌"
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

    static let singleTurnInsufficient = "单回合不够，考虑预启动"
    static let boardDanger = "场面危险，必须下怪"
    static let heroTarget = "英雄"

    // MARK: 设置页

    static let prefsTitle = "红龙辅助"
    static let prefsEnable = "启用红龙辅助"
    static let prefsEnableNote = "只在红龙贼套牌（E.T.C. 乐队带阿莱克丝塔萨）的对局里出现，其它套牌不做任何计算。开关立即生效，不用重启。"
    static let prefsReveal = "进回合默认揭示到："
    static let prefsRevealNote = "判定只给能不能斩；参与牌高亮要打的手牌（实线必打、虚线可选）；顺序标出前 3 步和场面目标。"
        + "选「顺序」时斩杀线一律给顺序，中途变简单也不降档；选其他档时，最简单的线是「基础」档则最多到参与牌。"
        + "只有「困难」线时默认直接给顺序。"
    static let prefsQuiz = "答题模式"
    static let prefsQuizNote = "不显示参与牌和序号；每做一步判卷：绿 = 仍在斩杀线上，红 = 已不可能斩杀（只在证明了不能斩时才判红）。"
    static let prefsHotkeys = "热键（只在炉石在前台时响应，不需要辅助功能权限）"

    static func hotkeyLine(_ keys: String, _ action: String) -> String {
        return keys + "　" + action
    }

    static let hotkeyRaise = "升一档揭示"
    static let hotkeyLower = "降一档揭示"
    static let hotkeyQuiz = "开 / 关答题模式"
}
