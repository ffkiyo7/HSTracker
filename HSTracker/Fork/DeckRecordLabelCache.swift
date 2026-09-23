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
/// dropped on `reload_decks`, whenever `gameEnded` flips, and on
/// `statisticsChanged()`. The zone header's records (`TrackerHeaderStats`) key
/// their own cache on `generation(gameEnded:)`, so both drop at the same moments.
final class DeckRecordLabelCache {
    static let shared = DeckRecordLabelCache()

    private var cached: (deckId: String, label: String)?
    private var gameEnded = false
    private var generation = 0
    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: NSNotification.Name(rawValue: Events.reload_decks),
            object: nil, queue: OperationQueue.main) { [weak self] _ in
                self?.invalidate()
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func invalidate() {
        cached = nil
        generation &+= 1
    }

    /// A deck's statistics were written or deleted. Neither posts
    /// `reload_decks`, and nothing else is sure to refresh the trackers after
    /// either, so this asks for one.
    func statisticsChanged() {
        invalidate()
        AppDelegate.instance().coreManager.game.updateTrackers()
    }

    /// Bumped on every invalidation, a `gameEnded` flip included.
    func generation(gameEnded: Bool) -> Int {
        if self.gameEnded != gameEnded {
            self.gameEnded = gameEnded
            invalidate()
        }
        return generation
    }

    func label(for deckId: String, gameEnded: Bool) -> String? {
        _ = generation(gameEnded: gameEnded)
        if let cached, cached.deckId == deckId {
            return cached.label
        }
        guard let deck = RealmHelper.getDeck(with: deckId) else { return nil }
        let label = StatsHelper.getDeckManagerRecordLabel(deck: deck, mode: .all)
        cached = (deckId, label)
        return label
    }
}
