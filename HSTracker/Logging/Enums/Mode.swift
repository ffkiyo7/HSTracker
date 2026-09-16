//
//  Mode.swift
//  HSTracker
//
//  Created by Benjamin Michotte on 27/02/16.
//  Copyright © 2016 Benjamin Michotte. All rights reserved.
//

import Foundation

enum Mode: String, CaseIterable {
    case invalid,
    startup,
    login,
    hub,
    gameplay,
    collectionmanager,
    packopening,
    tournament,
    friendly,
    fatal_error,
    draft,
    credits,
    reset,
    adventure,
    tavern_brawl,
    bacon,
    game_mode,
    pvp_dungeon_run,
    bacon_collection,
    lettuce_village,
    lettuce_bounty_board,
    lettuce_map,
    lettuce_play,
    lettuce_collection,
    lettuce_coop,
    lettuce_friendly,
    lettuce_bounty_team_select,
    lettuce_pack_opening,
    lucky_draw,
    /// Added by the 2026-09-16 client patch (`LoadingScreen.log` shows
    /// `nextMode=BLACK_MARKET`); neither HDT nor upstream HSTracker lists it
    /// yet, so the ordinal 29 is inferred from the append pattern.
    black_market

    /// The scene manager's `SceneMgr.Mode` ordinal as HearthMirror reads it.
    /// A client patch can add modes this enum does not know yet (2026-09-16:
    /// the mirror reported an index past `lucky_draw` and `allCases[i]`
    /// trapped in SceneWatcher), so unknown ordinals map to `.invalid`.
    static func fromMirror(_ index: Int) -> Mode {
        guard index >= 0, index < allCases.count else { return .invalid }
        return allCases[index]
    }
}
