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

/// Where a copy in the played section ended up (Phase 2 / 2.7), drawn as the
/// row's trailing status icon. `.none` is a copy that is still out there: a
/// minion on the board, an equipped weapon, a secret that has not fired.
enum CardZoneStatus: Int {
    case none = 0
    /// Played, and in the graveyard now.
    case graveyard
    /// Left without being played: discarded, burned by a full hand, destroyed
    /// or torn out of the deck, or taken by the other side.
    case burned
}

/// What sets two rows of the same card apart: a gift (a copy the deck list
/// never owned) and a status never share a row with copies that differ.
struct CardZoneRowState: Hashable {
    let gift: Bool
    let status: CardZoneStatus

    static let plain = CardZoneRowState(gift: false, status: .none)

    fileprivate var order: Int { (gift ? 10 : 0) + status.rawValue }
}

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
    /// - Parameter playedStates: of the copies that left the deck and are not
    ///   in hand, how many there are per row state. A card id missing here is
    ///   one plain row, as before 2.7.
    /// - Parameter giftsPlayed: copies from outside the deck list that went
    ///   through our hand and left it (played, discarded, taken), grouped by
    ///   card id and status. They are on top of everything above.
    /// - Parameter giftsInDeck: of the known cards in the deck, how many per
    ///   card id are gifts, latched or not. `nil` means the latched ones only
    ///   (`shuffledIntoDeck`).
    static func make(deckList: [Card],
                     knownInDeck: [Card],
                     predictedInDeck: [Card],
                     cardsInHand: [Card],
                     leftDeck: [Card],
                     shuffledIntoDeck: [String: Int] = [:],
                     shuffledLeftDeck: [String: Int] = [:],
                     inHandFromDeck: [String: Int],
                     playedStates: [String: [CardZoneRowState: Int]] = [:],
                     giftsPlayed: [Card] = [],
                     giftsInDeck: [String: Int]? = nil) -> CardZoneGroups {
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
            // Gifts are known copies by definition, so they are added on top and
            // only the rest of `known` is a floor under the list's share. With
            // `gifts == shuffledIntoDeck` this is the T8 total exactly.
            let gifts = giftsInDeck.map { $0[card.id] ?? 0 } ?? (shuffledIntoDeck[card.id] ?? 0)
            let own = max(fromList, (known[card.id] ?? 0) - gifts)
            guard own + gifts > 0, let template = templates[card.id] else { continue }
            for (gift, count) in [(false, own), (true, gifts)] where count > 0 {
                let row = template.copy()
                row.count = count
                row.isCreated = gift
                row.zoneStatus = .none
                row.highlightInHand = heldIds.contains(card.id)
                deck.append(row)
            }
        }

        var played = [Card]()
        var playedRows = [String: [CardZoneRowState: Card]]()
        func addPlayed(_ template: Card, state: CardZoneRowState, copies: Int) {
            if let row = playedRows[template.id]?[state] {
                row.count -= copies
                return
            }
            let row = template.copy()
            // Negative count: a row with count <= 0 is drawn darkened with abs()
            // in the count box, so the bar still looks like a played card while
            // carrying how many copies it stands for.
            row.count = -copies
            row.isCreated = state.gift
            row.zoneStatus = state.status
            row.wasDiscarded = state.status == .burned
            playedRows[template.id, default: [:]][state] = row
            played.append(row)
        }

        var seenPlayed = Set<String>()
        for card in leftDeck where seenPlayed.insert(card.id).inserted {
            let copies = (left[card.id] ?? 0) - (inHandFromDeck[card.id] ?? 0)
            guard copies > 0, let template = templates[card.id] else { continue }
            // The breakdown can only split the copies, never add to them or
            // drop any: whatever it does not cover stays a plain row.
            var remaining = copies
            let states = (playedStates[card.id] ?? [:]).sorted { $0.key.order < $1.key.order }
            for (state, count) in states where remaining > 0 && count > 0 {
                let taken = min(count, remaining)
                addPlayed(template, state: state, copies: taken)
                remaining -= taken
            }
            if remaining > 0 {
                addPlayed(template, state: .plain, copies: remaining)
            }
        }
        for card in giftsPlayed where abs(card.count) > 0 {
            addPlayed(card, state: CardZoneRowState(gift: true, status: card.zoneStatus),
                      copies: abs(card.count))
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
    /// too (bug T6). Gifts and deck list copies stay separate rows so the gift
    /// icon keeps its meaning — told apart by `isFromOutsideTheDeck`, not by
    /// that flag.
    private func cardsInHandByCardId(_ hand: [Entity]) -> [Card] {
        return hand
            .map({ (e: Entity) -> (DynamicEntity) in
                DynamicEntity(cardId: self.zoneCardId(e),
                              created: self.isFromOutsideTheDeck(e),
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
    private func knownCardsInDeckZone(_ deck: [Entity]) -> [Card] {
        return deck
            .map({ (e: Entity) -> (DynamicEntity) in
                DynamicEntity(cardId: self.zoneCardId(e),
                              created: self.isFromOutsideTheDeck(e),
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
    private func entitiesThatLeftTheDeck(_ revealed: [Entity]) -> [Entity] {
        return revealed.filter { entity in
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
    private func shuffledIntoDeckByCardId(_ deck: [Entity]) -> [String: Int] {
        return countByCardId(deck.filter { $0.wasShuffledIntoDeck })
    }

    /// 2.7 review #5: every gift sitting in the deck, latched or not — the Coin
    /// or a discovered card that went back in has no creator to latch on, but
    /// it is no more the list's than a copy shuffled in.
    private func giftsInDeckByCardId(_ deck: [Entity]) -> [String: Int] {
        return countByCardId(deck.filter { isFromOutsideTheDeck($0) })
    }

    /// Of the copies that left the deck, the ones the deck list never owned.
    /// Without this the deck list pays for a shuffled in copy being drawn and
    /// the deck section comes up one short (bug T8).
    private func shuffledCopiesThatLeftTheDeck(_ leftDeck: [Entity]) -> [String: Int] {
        return countByCardId(leftDeck.filter { $0.wasShuffledIntoDeck })
    }

    private func countByCardId(_ entities: [Entity]) -> [String: Int] {
        var result = [String: Int]()
        for entity in entities {
            result[zoneCardId(entity), default: 0] += 1
        }
        return result
    }

    private func cardsThatLeftTheDeck(_ leftDeck: [Entity]) -> [Card] {
        return leftDeck
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

    private func cardsInHandFromDeck(_ leftDeck: [Entity]) -> [String: Int] {
        // Our own hand only: a card of ours the opponent is now holding left the
        // deck, but it is not in the hand section, so it belongs to "played".
        return countByCardId(leftDeck.filter { $0.isInHand && $0.isControlled(by: self.id) })
    }

    // MARK: - Phase 2 / 2.7: gifts and where a played copy ended up

    /// A copy the deck list never owned: shuffled in by a card (T8's latch),
    /// a sideboard card (T9's latch), anything whose first zone was not the
    /// deck (discovered, generated, the Coin), or a card that came from the
    /// other side's deck. Deliberately not `info.created`: the game reveals a
    /// card while it is still in the deck, so ordinary draws carry that flag
    /// too (bug T6). `originalZone` alone cannot tell a shuffled in copy from
    /// the list's own (bug T7), which is what the first latch is for.
    private func isFromOutsideTheDeck(_ entity: Entity) -> Bool {
        if entity.wasShuffledIntoDeck || entity.wasSetAsideAtSetup {
            return true
        }
        guard entity.info.originalZone == .deck else { return true }
        let owner = entity.info.originalController
        return owner != 0 && owner != id
    }

    /// Entities this player played out of their hand: `play` records minions,
    /// spells, weapons and locations; secrets, quests, sigils and objectives
    /// only reach `spellsPlayedCards`. Ids, because a reconnect re-dump may
    /// leave the lists holding an older object for the same entity.
    private var idsPlayedFromHand: Set<Int> {
        return Set(cardsPlayedThisMatch.map { $0.id }).union(spellsPlayedCards.map { $0.id })
    }

    /// Of a copy in the played section: thrown away, or taken off us without
    /// being played, is burned; otherwise the graveyard is a skull and anything
    /// still out there has no status. `info.discarded` is what upstream sets on
    /// a hand discard and on every way out of the deck that is not a draw or a
    /// summon (full hand, mill, a card destroyed or torn out of the deck). It
    /// outranks having been played (review #3): the flag a discover out of the
    /// deck sets is cleared again on the way back, whether into the hand
    /// (`TagChangeActions.zoneChangeFromOther`) or into the deck
    /// (`Player.createInDeck`), so a set flag is the last thing that happened.
    ///
    /// Round 3 of the review: the flag is not the last thing that happened for
    /// a card made in hand, since the clearing only covers deck cards. Hand →
    /// SETASIDE → hand → played sets it on the way out and nothing clears it
    /// on the way back, so a played copy only counts as thrown away when it
    /// came back to a hand or deck after that (`info.returned`, set by
    /// `boardToHand` / `handToDeck` / `boardToDeck`) — played, bounced, then
    /// discarded is burned; set aside, handed back, played is not.
    ///
    /// A copy left in SETASIDE without being played is one a transformation
    /// replaced in hand (恶魔计划; T11 fixture line 7564: HAND → SETASIDE for
    /// good). Upstream books that exit as a discard too, but nothing was thrown
    /// away, so it gets no status. A card destroyed out of the hand passes
    /// through SETASIDE and ends in the graveyard (16605 → 16610), so by the
    /// time it is at rest it is burned as before.
    private func zoneStatus(of entity: Entity, playedFromHand: Set<Int>) -> CardZoneStatus {
        let played = playedFromHand.contains(entity.id)
        if !entity.isControlled(by: id) && !played {
            return .burned
        }
        if entity.isInSetAside && !played {
            return .none
        }
        if entity.info.discarded && (!played || entity.info.returned) {
            return .burned
        }
        return entity.isInGraveyard ? .graveyard : .none
    }

    /// The breakdown of the played section's deck side by row state: the same
    /// entities `cardsThatLeftTheDeck` minus `cardsInHandFromDeck` count.
    private func playedStates(leftDeck: [Entity],
                              playedFromHand: Set<Int>) -> [String: [CardZoneRowState: Int]] {
        var result = [String: [CardZoneRowState: Int]]()
        for entity in leftDeck where !(entity.isInHand && entity.isControlled(by: id)) {
            let state = CardZoneRowState(gift: isFromOutsideTheDeck(entity),
                                         status: zoneStatus(of: entity, playedFromHand: playedFromHand))
            result[zoneCardId(entity), default: [:]][state, default: 0] += 1
        }
        return result
    }

    /// Whether a gift has been in this player's hand. The main criterion is
    /// where the game made it: `originalZone == .hand` under this player's
    /// control is set once, when the entity first lands in a zone, and nothing
    /// that happens to it afterwards — played, pulled onto the board, cast by
    /// a trigger, played face down, shuffled back and destroyed in the deck —
    /// can change it (review #1 / #2 / #4). A token bounced back to hand is
    /// marked by `info.returned` (round 3 #4). A card taken from the other
    /// side's hand has no mark at all, so for it the hand's own records still
    /// stand in.
    private func hasBeenInHand(_ entity: Entity, playedFromHand: Set<Int>,
                               discardedFromHand: Set<Int>) -> Bool {
        if entity.info.originalZone == .hand && entity.info.originalController == id {
            return true
        }
        return entity.info.returned
            || playedFromHand.contains(entity.id) || discardedFromHand.contains(entity.id)
    }

    /// Gifts that have been in this player's hand and are not in it any more
    /// nor back in the deck, where the deck section owns them. A token summoned
    /// straight onto the board never was in the hand and is not here, and a
    /// gift a transformation replaced in hand (left in SETASIDE unplayed, see
    /// `zoneStatus`) is gone rather than played. The hero, hero powers and
    /// enchantments are never cards of the list, so they are left out whatever
    /// the records say. Sideboard cards set aside at setup (bug T9) never were
    /// in hand; E.T.C.'s pick is a card made in hand and counts like any gift.
    private func giftsThatLeftTheHand(revealed: [Entity], leftDeck: [Entity],
                                      playedFromHand: Set<Int>) -> [Card] {
        let fromDeck = Set(leftDeck.map { $0.id })
        let discardedFromHand = Set(entitiesDiscardedFromHand.map { $0.id })
        let gifts = revealed.filter { entity in
            guard !fromDeck.contains(entity.id), isFromOutsideTheDeck(entity) else { return false }
            guard !entity.isInDeck, !(entity.isInHand && entity.isControlled(by: id)) else { return false }
            guard !(entity.isInSetAside && !playedFromHand.contains(entity.id)) else { return false }
            guard !(entity.isHero && !entity.isPlayableHero), !entity.isHeroPower,
                  !entity.isEnchantment, !entity.wasSetAsideAtSetup else { return false }
            return hasBeenInHand(entity, playedFromHand: playedFromHand,
                                 discardedFromHand: discardedFromHand)
        }
        var counts = [String: [CardZoneStatus: Int]]()
        var order = [String]()
        for entity in gifts {
            let cardId = zoneCardId(entity)
            if counts[cardId] == nil {
                order.append(cardId)
            }
            counts[cardId, default: [:]][zoneStatus(of: entity, playedFromHand: playedFromHand), default: 0] += 1
        }
        return order.flatMap { cardId -> [Card] in
            (counts[cardId] ?? [:]).sorted { $0.key.rawValue < $1.key.rawValue }.compactMap { status, count in
                guard let card = Cards.by(cardId: cardId) else { return nil }
                card.count = count
                card.isCreated = true
                card.zoneStatus = status
                return card
            }
        }
    }

    /// Review #6: `revealedEntities` is the one walk over `game.entities` a
    /// refresh makes here; the hand, the known deck and what left the deck are
    /// all cut from it and handed down instead of being walked for again.
    func zoneGroups(deckList: [Card]) -> CardZoneGroups {
        let revealed = revealedEntities
        let hand = revealed.filter { $0.isInHand && $0.isControlled(by: id) }
        // A hidden card on the opponent's side is one we are not supposed to
        // know about; our own deck is ours to read.
        let deck = revealed.filter {
            $0.isInDeck && $0.isControlled(by: id) && (isLocalPlayer || !$0.info.hidden)
        }
        let leftDeck = entitiesThatLeftTheDeck(revealed)
        let playedFromHand = idsPlayedFromHand

        let knownInDeck = knownCardsInDeckZone(deck)
        let predictedInDeck = getPredictedCardsInDeck(hidden: false)
            .filter({ x in knownInDeck.all { c in x.id != c.id } })
        return CardZoneGroups.make(deckList: deckList,
                                   knownInDeck: knownInDeck,
                                   predictedInDeck: predictedInDeck,
                                   cardsInHand: cardsInHandByCardId(hand),
                                   leftDeck: cardsThatLeftTheDeck(leftDeck),
                                   shuffledIntoDeck: shuffledIntoDeckByCardId(deck),
                                   shuffledLeftDeck: shuffledCopiesThatLeftTheDeck(leftDeck),
                                   inHandFromDeck: cardsInHandFromDeck(leftDeck),
                                   playedStates: playedStates(leftDeck: leftDeck,
                                                              playedFromHand: playedFromHand),
                                   giftsPlayed: giftsThatLeftTheHand(revealed: revealed,
                                                                     leftDeck: leftDeck,
                                                                     playedFromHand: playedFromHand),
                                   giftsInDeck: giftsInDeckByCardId(deck))
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
