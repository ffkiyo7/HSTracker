//
//  DeckRecordLabelCache.swift
//  HSTracker
//
//  Fork only (Perf P1, dev 143db6f3): the player tracker's win / loss label
//  used to cost a Realm fetch plus a walk over the deck's statistics on every
//  refresh, and refreshes now come up to once a frame.
//

import Foundation

/// Main thread only, like the refresh that reads it. The label only moves when
/// a game is saved or the decks are reloaded, so it is cached per deck id and
/// dropped on `reload_decks`, whenever `gameEnded` flips, and by `invalidate()`
/// after a game's statistics are written.
final class DeckRecordLabelCache {
    static let shared = DeckRecordLabelCache()

    private var cached: (deckId: String, label: String)?
    private var gameEnded = false
    private var observer: NSObjectProtocol?

    private init() {
        observer = NotificationCenter.default.addObserver(
            forName: NSNotification.Name(rawValue: Events.reload_decks),
            object: nil, queue: OperationQueue.main) { [weak self] _ in
                self?.invalidate()
        }
    }

    func invalidate() {
        cached = nil
    }

    func label(for deckId: String, gameEnded: Bool) -> String? {
        if self.gameEnded != gameEnded {
            self.gameEnded = gameEnded
            cached = nil
        }
        if let cached, cached.deckId == deckId {
            return cached.label
        }
        guard let deck = RealmHelper.getDeck(with: deckId) else { return nil }
        let label = StatsHelper.getDeckManagerRecordLabel(deck: deck, mode: .all)
        cached = (deckId, label)
        return label
    }
}
