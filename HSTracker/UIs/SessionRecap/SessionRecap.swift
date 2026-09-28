//
//  SessionRecap.swift
//  HSTracker
//
//  A session is one Hearthstone process lifetime (launch -> quit). This slices
//  the constructed games recorded in that window out of Realm for the recap
//  window (docs/tasks/phase7-t1-session-recap-window.md, D2).
//

import Foundation

struct SessionRecapGame: Identifiable {
    let id: String
    let opponentClass: CardClass
    let startTime: Date
    let turns: Int
    let result: GameResult
}

struct SessionRecapDeck: Identifiable {
    /// nil once the deck behind these games is gone; the group is then shown as
    /// "unknown deck" and offers no statistics entry.
    let deckId: String?
    let name: String
    let playerClass: CardClass
    let record: StatsDeckRecord
    let games: [SessionRecapGame]

    var id: String { deckId ?? "" }
}

struct SessionRecapSummary {
    let start: Date
    let end: Date
    let record: StatsDeckRecord
    let decks: [SessionRecapDeck]
}

enum SessionRecap {
    /// Start of the running session. Memory only by design: restarting HSTracker
    /// starts a new session even if Hearthstone keeps running.
    private(set) static var sessionStart: Date?

    /// Constructed play only. `ranked` covers standard / wild / classic / twist,
    /// which differ by `format`, not by mode. Battlegrounds, mercenaries, duels,
    /// practice, friendly and spectator games never reach the recap.
    private static let includedModes: Set<GameMode> = [.ranked, .casual, .arena, .brawl]

    /// Second guard on the raw game type: an adventure or a solo brawl can be
    /// recorded with a constructed-looking game mode.
    private static let excludedTypes: Set<GameType> = [
        .gt_vs_ai, .gt_tutorial, .gt_test,
        .gt_tb_1p_vs_ai, .gt_tb_2p_coop,
        .gt_fsg_brawl_1p_vs_ai, .gt_fsg_brawl_2p_coop,
        .gt_battlegrounds, .gt_battlegrounds_friendly,
        .gt_battlegrounds_ai_vs_ai, .gt_battlegrounds_player_vs_ai,
        .gt_battlegrounds_duo, .gt_battlegrounds_duo_vs_ai,
        .gt_battlegrounds_duo_friendly, .gt_battlegrounds_duo_ai_vs_ai,
        .gt_mercenaries_pvp, .gt_mercenaries_pve, .gt_mercenaries_pve_coop,
        .gt_mercenaries_ai_vs_ai, .gt_mercenaries_friendly
    ]

    static func beginSession(at date: Date = Date()) {
        sessionStart = date
    }

    /// Closes the running session and returns its recap, or nil when there was
    /// no session or it holds no constructed game (0 games must not pop a
    /// window). Consumes the start, so a second call returns nil.
    static func endSession(at end: Date = Date()) -> SessionRecapSummary? {
        guard let start = sessionStart else {
            return nil
        }
        sessionStart = nil
        guard let rows = RealmHelper.getStatistics(since: start) else {
            return nil
        }

        var order = [String]()
        var names = [String: (name: String, playerClass: CardClass)]()
        var games = [String: [SessionRecapGame]]()

        for (deck, stats) in rows where include(stats) {
            let known = !deck.isInvalidated && !deck.name.isEmpty
            let key = known ? deck.deckId : ""
            if names[key] == nil {
                order.append(key)
                names[key] = known
                    ? (deck.name, deck.playerClass)
                    : (String.localizedString("session_recap_unknown_deck", comment: ""), stats.playerHero)
            }
            games[key, default: []].append(SessionRecapGame(id: stats.statId,
                                                            opponentClass: stats.opponentHero,
                                                            startTime: stats.startTime,
                                                            turns: stats.turns,
                                                            result: stats.result))
        }

        let decks = order.compactMap { key -> SessionRecapDeck? in
            guard let meta = names[key], let games = games[key] else {
                return nil
            }
            return SessionRecapDeck(deckId: key.isEmpty ? nil : key,
                                    name: meta.name,
                                    playerClass: meta.playerClass,
                                    record: record(of: games),
                                    games: games)
        }
        guard !decks.isEmpty else {
            return nil
        }
        return SessionRecapSummary(start: start,
                                   end: end,
                                   record: record(of: decks.flatMap { $0.games }),
                                   decks: decks)
    }

    private static func include(_ stats: GameStats) -> Bool {
        includedModes.contains(stats.gameMode) && !excludedTypes.contains(stats.gameType)
    }

    /// `total` counts every game, `wins`/`losses` only decide the win rate —
    /// draws and unknown results stay out of its denominator but are still
    /// listed.
    private static func record(of games: [SessionRecapGame]) -> StatsDeckRecord {
        var record = StatsDeckRecord()
        for game in games {
            switch game.result {
            case .win: record.wins += 1
            case .loss: record.losses += 1
            case .draw: record.draws += 1
            case .unknown: break
            }
            record.total += 1
        }
        return record
    }
}
