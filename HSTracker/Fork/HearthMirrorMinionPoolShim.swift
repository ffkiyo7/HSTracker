/*
 * This file is part of the HSTracker package.
 * Fork: temporary stand-in for the HearthMirror 1a6012b5 minion-pool API.
 *
 * Upstream 3.6.13 pins HearthMirror 1a6012b5 for getBattlegroundsMinionPool,
 * but libs.hearthsim.net served 404 for that build on 2026-09-29, so the fork
 * stays on the 3.6.12 build (912e88ea). These declarations let the 3.6.13
 * Swift compile against it; the pool is never available, so BattlegroundsDb
 * falls back to the assembled database exactly as upstream does when the read
 * fails. Delete this file (and its four project.pbxproj entries) and restore
 * HearthMirror-version.txt to 1a6012b545ba7af09afc14da3cd8286986c996f1 once
 * https://libs.hearthsim.net/hstracker/<sha>/HearthMirror.framework.zip
 * answers 200.
 */

import Foundation

final class MirrorBattlegroundsMinionPoolEntry: NSObject {
    var dbfId: Int = 0
    var tier: Int = 0
    var cardType: Int = 0
    var minionTypes: [NSNumber] = []
    var banned: Bool = false
}

final class MirrorBattlegroundsMinionPool: NSObject {
    var cards: [MirrorBattlegroundsMinionPoolEntry] = []
    var activeMinionTypes: [NSNumber] = []
}

extension HearthMirror {
    func getBattlegroundsMinionPool() -> MirrorBattlegroundsMinionPool? {
        return nil
    }
}
