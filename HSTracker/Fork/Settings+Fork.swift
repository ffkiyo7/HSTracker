//
//  Settings+Fork.swift
//  HSTracker
//
//  Fork only: keys that are not the tracker panel's (see Settings+Tracker.swift).
//  Defaults are dev's (docs/PLAN.md「与上游的默认值差异」).
//

import Foundation

extension Settings {
    static let keep_power_log = "keep_power_log"

    /// Upstream truncates `Power.log` to 0 bytes once Hearthstone quits and
    /// deletes it on the next start. Keep it so past games can be replayed
    /// offline (red dragon fixtures). Other logs are still cleaned up.
    @UserDefault(key: Settings.keep_power_log, defaultValue: true)
    static var keepPowerLog: Bool

    static let show_constructed_session_recap = "show_constructed_session_recap"

    /// Our constructed session recap. Not to be confused with upstream's
    /// `showSessionRecap`, which is the battlegrounds one.
    @UserDefault(key: Settings.show_constructed_session_recap, defaultValue: true)
    static var showConstructedSessionRecap: Bool

    static let perf_log = "perf_log"

    #if DEBUG
    static let perfLogDefault = false
    #else
    static let perfLogDefault = true
    #endif

    /// Per-game performance log (Utility/PerfLog.swift). On in Release, where
    /// the numbers mean something; read once per game start.
    @UserDefault(key: Settings.perf_log, defaultValue: Settings.perfLogDefault)
    static var perfLog: Bool

    static let red_dragon_assist = "red_dragon_assist"
    static let red_dragon_reveal_level = "red_dragon_reveal_level"
    static let red_dragon_quiz_mode = "red_dragon_quiz_mode"

    /// 红龙辅助总开关。关着时刷新链上的挂点直接返回，不调度任何计算（RedDragonAssistant）
    @UserDefault(key: Settings.red_dragon_assist, defaultValue: false)
    static var redDragonAssist: Bool

    /// 进回合时默认揭示到哪一档：0 判定 / 1 参与牌 / 2 顺序（`RDRevealLevel`）
    @UserDefault(key: Settings.red_dragon_reveal_level, defaultValue: 0)
    static var redDragonRevealLevel: Int

    /// 答题模式：不给序号，每出一张牌判对错
    @UserDefault(key: Settings.red_dragon_quiz_mode, defaultValue: false)
    static var redDragonQuizMode: Bool
}
