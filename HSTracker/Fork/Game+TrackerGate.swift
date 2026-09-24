//
//  Game+TrackerGate.swift
//  HSTracker
//
//  Fork only (dev c5e125c2 / 381a9c80, Bug T4 / T5): the deck trackers, the
//  max resources widgets and the counters used to stay up on the menu after a
//  game, because upstream only hides them when hide_all_trackers_when_not_in_game
//  is on - and turning that on would also take the queue's deck list away.
//

import Foundation

extension Game {
    /// The one scene gate the trackers, the resources widgets and the counters
    /// share. `gameEnded` flips in gameEnd(), which requests the refresh itself,
    /// so all of them go at the moment a game ends rather than on the menu.
    var isTrackerGameActive: Bool {
        return !gameEnded && !isInMenu
    }

    /// The player's deck while queuing for a constructed-style mode. Player
    /// tracker only. `isInMenu` comes first because QueueWatcher.stop() never
    /// reports leaving the queue: a stale `isInQueue` must not reach a game.
    var isDeckTrackerQueue: Bool {
        guard isInMenu, queueEvents.isInQueue, currentDeck != nil, let currentMode else { return false }
        return QueueEvents.modes.contains(currentMode) && currentMode != .bacon
    }
}
