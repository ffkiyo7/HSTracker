//
//  PlayerCardZones.swift
//  HSTracker
//
//  Fork only: the zone split behind the tracker's deck / hand / played
//  sections, and the single-evaluation refresh entry point (Perf P1).
//  Kept out of `Player.swift` so what the fork adds to an upstream file stays
//  down to a few access levels.
//

import Foundation

/// The tracker's main list split by zone: what is still in the deck, what is in
/// hand, and what left the deck without being in hand.
struct CardZoneGroups {
    let deck: [Card]
    let hand: [Card]
    let played: [Card]

    /// The split is built so that, for every card id,
    /// `deck + hand + |played| == the copies known to exist`. That is the
    /// invariant that keeps a card from vanishing or being counted twice as it
    /// moves between zones; the flat list cannot state it, because it forces
    /// every card that left the deck to `count = 0`.
    ///
    /// Everything is counted from the zone the entities are actually in, not
    /// from `EntityInfo.created`: the game reveals a card while it is still in
    /// the deck, so most ordinary draws end up flagged created (bug T6) and any
    /// split keyed on that flag drifts away from the board within two turns.
    ///
    /// - Parameter deckList: the deck list, i.e. how many copies exist.
    /// - Parameter knownInDeck: cards with a known id sitting in the deck right
    ///   now — revealed deck cards, and whatever was shuffled in.
    /// - Parameter cardsInHand: hand entities already grouped by card id.
    /// - Parameter leftDeck: copies that came out of the deck list and are not
    ///   in the deck anymore, in hand or not.
    /// - Parameter shuffledIntoDeck: of the cards in the deck, how many per card
    ///   id are copies the deck list does not own.
    /// - Parameter shuffledLeftDeck: of `leftDeck`, how many per card id were
    ///   such copies. They still belong to the played / hand sections, but they
    ///   may not be charged to the deck list: it never owned them.
    /// - Parameter inHandFromDeck: of those, how many are in hand per card id.
    static func make(deckList: [Card],
                     knownInDeck: [Card],
                     predictedInDeck: [Card],
                     cardsInHand: [Card],
                     leftDeck: [Card],
                     shuffledIntoDeck: [String: Int] = [:],
                     shuffledLeftDeck: [String: Int] = [:],
                     inHandFromDeck: [String: Int]) -> CardZoneGroups {
        func counts(_ cards: [Card]) -> [String: Int] {
            var result = [String: Int]()
            for card in cards {
                result[card.id] = (result[card.id] ?? 0) + abs(card.count)
            }
            return result
        }
        let listed = counts(deckList)
        let known = counts(knownInDeck)
        let left = counts(leftDeck)
        let heldIds = Set(cardsInHand.map { $0.id })

        var templates = [String: Card]()
        for card in deckList + leftDeck + knownInDeck {
            templates[card.id] = card
        }

        var seen = Set<String>()
        var deck = [Card]()
        for card in deckList + knownInDeck where seen.insert(card.id).inserted {
            // What the deck list still owes, plus the copies that were shuffled
            // in on top of it. Counting them separately is what keeps a copy
            // shuffled in from being swallowed by the list's own unrevealed
            // copies; `known` is only a floor, for when the list is incomplete.
            // Only the list's own copies come off the list, which is why a
            // shuffled in copy being drawn no longer costs the list a card.
            let leftFromList = (left[card.id] ?? 0) - (shuffledLeftDeck[card.id] ?? 0)
            let fromList = max((listed[card.id] ?? 0) - leftFromList, 0)
            let copies = max(fromList + (shuffledIntoDeck[card.id] ?? 0), known[card.id] ?? 0)
            guard copies > 0, let row = templates[card.id]?.copy() else { continue }
            row.count = copies
            row.highlightInHand = heldIds.contains(card.id)
            deck.append(row)
        }

        var played = [Card]()
        var seenPlayed = Set<String>()
        for card in leftDeck where seenPlayed.insert(card.id).inserted {
            let copies = (left[card.id] ?? 0) - (inHandFromDeck[card.id] ?? 0)
            guard copies > 0, let row = templates[card.id]?.copy() else { continue }
            // Negative count: a row with count <= 0 is drawn darkened with abs()
            // in the count box, so the bar still looks like a played card while
            // carrying how many copies it stands for.
            row.count = -copies
            played.append(row)
        }

        return CardZoneGroups(deck: deck + predictedInDeck.filter { card in
                                  deck.all { $0.id != card.id }
                              },
                              hand: cardsInHand,
                              played: played)
    }
}

extension Player {
    /// Everything the player tracker needs out of one refresh. `getDeckState()`
    /// walks every revealed entity, so the flat list, the zone groups and the
    /// sideboards all have to be served from a single evaluation of it.
    struct PlayerTrackerSnapshot {
        let cards: [Card]
        let groups: CardZoneGroups?
        let sideboards: [Sideboard]
    }

    func playerTrackerSnapshot(useZoneGroups: Bool) -> PlayerTrackerSnapshot {
        guard game.currentDeck != nil else {
            // No deck: no deck state, no sideboards, and nothing to group.
            return PlayerTrackerSnapshot(cards: playerCardListWithoutDeck(), groups: nil, sideboards: [])
        }
        let deckState = getDeckState()
        let sideboards = getPlayerSideboards(Settings.removeCardsFromDeck, deckState: deckState)
        if useZoneGroups, let groups = playerCardGroups(sideboards: sideboards) {
            return PlayerTrackerSnapshot(cards: [Card](), groups: groups, sideboards: sideboards)
        }
        return PlayerTrackerSnapshot(cards: playerCardList(deckState: deckState, sideboards: sideboards),
                                     groups: nil,
                                     sideboards: sideboards)
    }

    /// Upstream's `playerCardList` without a current deck.
    func playerCardListWithoutDeck() -> [Card] {
        let createdInHand = Settings.showPlayerGet ? createdCardsInHand : [Card]()
        return (revealedCards + createdInHand
            + knownCardsInDeck + getPredictedCardsInDeck(hidden: true)).sortCardList()
    }

    /// Upstream's `playerCardList` with a current deck, fed an already computed
    /// deck state and sideboards: the upstream accessor recomputes both, once
    /// per `annotateCards` call. Keep in step with `Player.playerCardList`.
    func playerCardList(deckState: DeckState, sideboards: [Sideboard]) -> [Card] {
        let createdInHand = Settings.showPlayerGet ? createdCardsInHand : [Card]()
        let sorting = game.isMulliganDone() ? CardListSorting.cost : CardListSorting.mulliganWr
        let inDeck = deckState.remainingInDeck
        let notInDeck = deckState.removedFromDeck.filter({ x in inDeck.all({ x.id != $0.id }) })
        let predictedInDeck = getPredictedCardsInDeck(hidden: false).filter({ x in inDeck.all { c in x.id != c.id } })
        if !Settings.removeCardsFromDeck {
            return annotateCards(cards: (inDeck + predictedInDeck + notInDeck + createdInHand),
                                 sideboards: sideboards).sortCardList(sorting)
        }
        if Settings.highlightCardsInHand {
            return annotateCards(cards: (inDeck + predictedInDeck + getHighlightedCardsInHand(cardsInDeck: inDeck)
                + createdInHand), sideboards: sideboards).sortCardList(sorting)
        }
        return annotateCards(cards: (inDeck + predictedInDeck + createdInHand),
                             sideboards: sideboards).sortCardList(sorting)
    }

    /// Hand entities grouped by card id. Every card in hand belongs to the hand
    /// section, gifts included: `Settings.showPlayerGet` ("show the cards I was
    /// given") is about a flat list that cannot say where a card is, and it is
    /// not usable as a filter anyway, because the game reveals a card while it
    /// is still in the deck and `info.created` ends up set on ordinary draws
    /// too (bug T6). Created and drawn copies stay separate rows so the gift
    /// icon keeps its meaning.
    private var cardsInHandByCardId: [Card] {
        return hand.filter({ $0.hasCardId })
            .map({ (e: Entity) -> (DynamicEntity) in
                DynamicEntity(cardId: self.zoneCardId(e),
                              created: e.info.created || e.info.stolen,
                              extraInfo: e.info.extraInfo)
            })
            .group { (d: DynamicEntity) in d }
            .compactMap { g -> Card? in
                if let card = Cards.by(cardId: g.key.cardId) {
                    card.count = g.value.count
                    card.isCreated = g.key.created
                    card.highlightInHand = true
                    card.extraInfo = g.key.extraInfo?.copy() as? (any ICardExtraInfo)
                    return card
                } else {
                    return nil
                }
            }
    }

    /// A customised Zilliax is in the deck list under its base id while the
    /// entity that comes out of the deck carries the cosmetic module's id, so
    /// the two never cancel out and the base card stays in the deck section for
    /// the whole game. The zone sections key everything on the base id;
    /// `annotateCards` puts the customised card back for display, the same way
    /// the flat list does (`Helper.resolveZilliax3000`).
    private func zoneCardId(_ entity: Entity) -> String {
        if Cards.by(cardId: entity.cardId)?.zilliaxCustomizableCosmeticModule == true {
            return CardIds.Collectible.Neutral.ZilliaxDeluxe3000
        }
        return entity.cardId
    }

    /// Cards with a known id sitting in the deck right now: revealed deck cards
    /// and whatever was shuffled in.
    private var knownCardsInDeckZone: [Card] {
        // A hidden card on the opponent's side is one we are not supposed to
        // know about; our own deck is ours to read.
        return deck.filter({ $0.hasCardId && (isLocalPlayer || !$0.info.hidden) })
            .map({ (e: Entity) -> (DynamicEntity) in
                DynamicEntity(cardId: self.zoneCardId(e),
                              created: e.info.created || e.info.stolen,
                              discarded: e.info.discarded,
                              extraInfo: e.info.extraInfo)
            })
            .group { (d: DynamicEntity) in d }
            .compactMap { g -> Card? in
                if let card = Cards.by(cardId: g.key.cardId) {
                    card.count = g.value.count
                    card.isCreated = g.key.created
                    card.extraInfo = g.key.extraInfo?.copy() as? (any ICardExtraInfo)
                    return card
                } else {
                    return nil
                }
            }
    }

    /// Entities that started in the deck and are not in it anymore. Zone based
    /// on purpose: `getDeckState()` keys the same question on `info.created`,
    /// which is set on most ordinary draws, so its `remainingInDeck` keeps
    /// listing cards that have long been drawn or played (bug T6).
    ///
    /// Ownership is the *original* controller, not the current one: a card of
    /// ours the opponent took has left our deck all the same, and a minion we
    /// took from them was never in it, so neither may be filtered by who holds
    /// it now.
    ///
    /// The sideboard is not part of the deck either: E.T.C.'s cards and Zilliax's
    /// modules are created set aside while the board is being built and the setup
    /// branch of `zoneChange` calls that `originalZone = .deck`, so they used to
    /// show up here — and in the played section — from turn zero (bug T9). The
    /// flag is latched while parsing (`TagChangeActions.markSetAsideAtSetup`).
    private var entitiesThatLeftTheDeck: [Entity] {
        return revealedEntities.filter { entity in
            guard !entity.wasSetAsideAtSetup else { return false }
            guard entity.info.originalZone == .deck, !entity.isInDeck else { return false }
            let owner = entity.info.originalController
            return owner == self.id || (owner == 0 && entity.isControlled(by: self.id))
        }
    }

    /// Copies sitting in the deck that the deck list does not own, i.e. shuffled
    /// in by a card. The flag is latched while parsing
    /// (`TagChangeActions.markShuffledIntoDeck`); reading it back here instead of
    /// re-deriving it is what makes the answer survive the copy being drawn.
    private var shuffledIntoDeckByCardId: [String: Int] {
        var result = [String: Int]()
        for entity in deck where entity.hasCardId && (isLocalPlayer || !entity.info.hidden) {
            guard entity.wasShuffledIntoDeck else { continue }
            let cardId = zoneCardId(entity)
            result[cardId] = (result[cardId] ?? 0) + 1
        }
        return result
    }

    /// Of the copies that left the deck, the ones the deck list never owned.
    /// Without this the deck list pays for a shuffled in copy being drawn and
    /// the deck section comes up one short (bug T8).
    private var shuffledCopiesThatLeftTheDeck: [String: Int] {
        var result = [String: Int]()
        for entity in entitiesThatLeftTheDeck where entity.wasShuffledIntoDeck {
            let cardId = zoneCardId(entity)
            result[cardId] = (result[cardId] ?? 0) + 1
        }
        return result
    }

    private var cardsThatLeftTheDeck: [Card] {
        return entitiesThatLeftTheDeck
            .map({ (e: Entity) -> (DynamicEntity) in
                DynamicEntity(cardId: self.zoneCardId(e),
                              discarded: e.info.discarded && Settings.highlightDiscarded,
                              extraInfo: e.info.extraInfo)
            })
            .group { (d: DynamicEntity) in d }
            .compactMap { g -> Card? in
                if let card = Cards.by(cardId: g.key.cardId) {
                    card.count = g.value.count
                    card.wasDiscarded = g.key.discarded
                    card.extraInfo = g.key.extraInfo?.copy() as? (any ICardExtraInfo)
                    return card
                } else {
                    return nil
                }
            }
    }

    private var cardsInHandFromDeck: [String: Int] {
        var result = [String: Int]()
        // Our own hand only: a card of ours the opponent is now holding left the
        // deck, but it is not in the hand section, so it belongs to "played".
        for entity in entitiesThatLeftTheDeck where entity.isInHand && entity.isControlled(by: self.id) {
            let cardId = zoneCardId(entity)
            result[cardId] = (result[cardId] ?? 0) + 1
        }
        return result
    }

    func zoneGroups(deckList: [Card]) -> CardZoneGroups {
        let knownInDeck = knownCardsInDeckZone
        let predictedInDeck = getPredictedCardsInDeck(hidden: false)
            .filter({ x in knownInDeck.all { c in x.id != c.id } })
        return CardZoneGroups.make(deckList: deckList,
                                   knownInDeck: knownInDeck,
                                   predictedInDeck: predictedInDeck,
                                   cardsInHand: cardsInHandByCardId,
                                   leftDeck: cardsThatLeftTheDeck,
                                   shuffledIntoDeck: shuffledIntoDeckByCardId,
                                   shuffledLeftDeck: shuffledCopiesThatLeftTheDeck,
                                   inHandFromDeck: cardsInHandFromDeck)
    }

    func playerCardGroups(sideboards: [Sideboard]) -> CardZoneGroups? {
        guard let currentDeck = game.currentDeck else { return nil }
        let groups = zoneGroups(deckList: currentDeck.cards)
        let sorting = game.isMulliganDone() ? CardListSorting.cost : CardListSorting.mulliganWr
        return CardZoneGroups(deck: annotateCards(cards: groups.deck, sideboards: sideboards).sortCardList(sorting),
                              hand: annotateCards(cards: groups.hand, sideboards: sideboards).sortCardList(sorting),
                              played: annotateCards(cards: groups.played, sideboards: sideboards).sortCardList(sorting))
    }

    /// Zone split of the player's main list. `nil` means there is nothing to
    /// split (no deck known) and the caller has to keep the flat
    /// `playerCardList`.
    var playerCardGroups: CardZoneGroups? {
        return playerCardGroups(sideboards: playerSideboardsDict)
    }

    /// Zone split of the opponent's list. Only defined once the deck has been
    /// linked: without a known deck the list is made of revealed entities only,
    /// and a "in hand" section would state something we are not supposed to
    /// know.
    var opponentCardGroups: CardZoneGroups? {
        guard let knownDeck = Player.knownOpponentDeck else { return nil }
        let groups = zoneGroups(deckList: knownDeck)
        return CardZoneGroups(deck: groups.deck.sortCardList(),
                              hand: groups.hand.sortCardList(),
                              played: groups.played.sortCardList())
    }
}
