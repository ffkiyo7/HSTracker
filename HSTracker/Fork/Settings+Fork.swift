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
}
