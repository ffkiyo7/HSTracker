//
//  Settings+Tracker.swift
//  HSTracker
//
//  Fork only: the tracker panel's own keys, kept out of `Settings.swift`.
//  Defaults are dev's (docs/PLAN.md「与上游的默认值差异」).
//

import Foundation

extension Settings {
    static let group_cards_by_zone = "group_cards_by_zone"
    static let tracker_perf_flatten_rows = "tracker_perf_flatten_rows"
    static let tracker_perf_no_text_shadow = "tracker_perf_no_text_shadow"
    static let tracker_perf_no_card_art = "tracker_perf_no_card_art"
    static let tracker_perf_force_opaque = "tracker_perf_force_opaque"
    static let tracker_motion = "tracker_motion"
    static let overlay_perf_mode = "overlay_perf_mode"

    /// Splits the main list into deck / hand / played (PLAN Phase 2) and draws
    /// the fork's panel inside the upstream shell. Off falls back to the
    /// upstream panel as it ships.
    @UserDefault(key: Settings.group_cards_by_zone, defaultValue: true)
    static var groupCardsByZone: Bool
    // Perf P2 diagnostics (docs/tasks/perf-p2-vector-rows-compositing-cost.md).
    // Deliberately not in the preferences UI: they exist so a session that
    // drops frames can be bisected with `defaults write`, not as features.
    /// Off falls the rows back to the unflattened V1 / V2 drawing.
    @UserDefault(key: Settings.tracker_perf_flatten_rows, defaultValue: true)
    static var trackerFlattenRows: Bool
    @UserDefault(key: Settings.tracker_perf_no_text_shadow, defaultValue: false)
    static var trackerNoTextShadow: Bool
    @UserDefault(key: Settings.tracker_perf_no_card_art, defaultValue: false)
    static var trackerNoCardArt: Bool
    @UserDefault(key: Settings.tracker_perf_force_opaque, defaultValue: false)
    static var trackerForceOpaquePanel: Bool
    /// Phase 1 / T8, same contract: off makes the panel jump in one frame the
    /// way it did before the motion slice, which is both the A/B control for 🎮
    /// and the first bisection step if frames go missing.
    @UserDefault(key: Settings.tracker_motion, defaultValue: true)
    static var trackerMotion: Bool
    /// Overlay GPU cost A/B (docs/tasks/perf-p4-overlay-mask.md), same
    /// contract as the keys above but read live: RootOverlayWindow polls it
    /// once a second, so `defaults write` switches it in the middle of a game.
    /// 0 normal; 1 overlay window hidden; 2 window shown with nothing drawn in
    /// it; 3 drawn without the cut-out mask (cut-outs stop working).
    @UserDefault(key: Settings.overlay_perf_mode, defaultValue: 0)
    static var overlayPerfMode: Int
}
