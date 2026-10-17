//
//  BoundSoul.swift
//  HSTracker
//

import Foundation

// "Discover a minion devoured by Souleater's Scythe."
// The Scythe itself needs no class: the minions it devoured are stored on it while parsing
// its Start of Game block, and the entity fallback in Game.getRelatedCards shows them.
// The Souls are created between those reveals, so they read the Scythe at hover time.
class BoundSoul: ICardWithRelatedCards {

    required init() {}

    func getCardId() -> String {
        return CardIds.NonCollectible.DemonHunter.SouleatersScythe_BoundSoulToken
    }

    func shouldShowForOpponent(opponent: Player) -> Bool {
        return false
    }

    func getRelatedCards(player: Player) -> [Card?] {
        guard let scythe = player.playerEntities.first(where: { e in
            e.cardId == CardIds.Collectible.DemonHunter.SouleatersScythe && !e.info.storedCardIds.isEmpty
        }) else {
            return []
        }
        return scythe.info.storedCardIds.map { id in Cards.by(cardId: id) }
    }
}
