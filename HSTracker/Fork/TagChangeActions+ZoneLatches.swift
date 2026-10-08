//
//  TagChangeActions+ZoneLatches.swift
//  HSTracker
//
//  Fork only: the two entity flags the zone sections (`PlayerCardZones.swift`)
//  need latched while parsing, because what they record can no longer be
//  derived once the entity has moved on.
//

import Foundation

extension TagChangeActions {
    /// Runs after upstream's `zoneChange` for every ZONE tag change.
    func updateZoneLatches(eventHandler: PowerEventHandler, id: Int, value: Int) {
        guard let entity = eventHandler.entities[id] else { return }
        // A card created set aside at setup that really is put into the deck
        // later is a copy in the deck like any other from here on.
        if value == Zone.deck.rawValue {
            entity.wasSetAsideAtSetup = false
        }
        // 2.9: what the entity is as it comes into play. A card can change in
        // hand or in the deck (infuse, corrupt, a card that shifts every turn)
        // and `info.latestCardId` cannot tell that from a transformation on
        // the board; only the second makes a minion die as another card.
        if value == Zone.play.rawValue {
            entity.cardIdOnEnteringPlay = entity.info.latestCardId
        }
        markShuffledIntoDeck(eventHandler: eventHandler, id: id)
    }

    /// Latches `Entity.wasShuffledIntoDeck`: this copy was made by a card and put
    /// into the deck, so it is not one of the deck list's copies (bug T8).
    ///
    /// `info.created` alone does not say that — it is set on ordinary draws and
    /// on anything that re-enters the deck, dredge included (bug T6) — so the
    /// entity also has to name a *card* as its creator, which is what the game
    /// writes when it makes a new card. Deck list cards get no creator, or the
    /// game entity as one.
    ///
    /// Either tag can be the last one in: a `FULL_ENTITY` straight into the deck
    /// queues its zone action (`TagChangeHandler.tagChange`, `isCreationTag`)
    /// while the `DISPLAYED_CREATOR` line right after it runs at once, so the
    /// check has to run on both tags.
    ///
    /// Far Sight names itself as the creator of the card it *drew* (upstream's
    /// `creatorChanged` skips it for the same reason); that card going back into
    /// the deck would otherwise be taken for a copy shuffled in.
    func markShuffledIntoDeck(eventHandler: PowerEventHandler, id: Int) {
        guard let entity = eventHandler.entities[id], !entity.wasShuffledIntoDeck else { return }
        guard entity.isInDeck, entity.info.created else { return }
        guard !Self.isFarSight(eventHandler.entities[entity[.creator]]),
              !Self.isFarSight(eventHandler.entities[entity[.displayed_creator]]) else { return }
        let creatorId = entity[.creator] > 0 ? entity[.creator] : entity[.displayed_creator]
        guard creatorId > 0, creatorId != entity.id,
              eventHandler.entities[creatorId]?.hasCardId == true else { return }
        entity.wasShuffledIntoDeck = true
    }

    /// A card the game creates straight into SETASIDE while the board is being
    /// built was never in the deck: E.T.C.'s sideboard and Zilliax's modules come
    /// in this way, with their card id already revealed on our own side.
    /// Upstream's setup branch of `zoneChange` still writes `originalZone = .deck`
    /// for them, so without this latch the zone sections count them as copies
    /// that left the deck and list the sideboard as played (bug T9).
    func markSetAsideAtSetup(entity: Entity, value: Int) {
        guard value == Zone.setaside.rawValue else { return }
        entity.wasSetAsideAtSetup = true
    }

    private static func isFarSight(_ entity: Entity?) -> Bool {
        guard let cardId = entity?.cardId else { return false }
        return cardId == CardIds.Collectible.Shaman.FarSight
            || cardId == CardIds.Collectible.Shaman.FarSightCore
            || cardId == CardIds.Collectible.Shaman.FarSightVanilla
    }
}
