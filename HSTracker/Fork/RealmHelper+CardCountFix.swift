//
//  RealmHelper+CardCountFix.swift
//  HSTracker
//
//  Fork only (Perf P1): `getDeck` runs on every tracker refresh and used to
//  open a Realm write transaction whether or not a count needed repairing.
//

import Foundation

extension RealmHelper {
    /// A count above 30 is the corruption `validateCardCounts` repairs; every
    /// other deck must not pay for a Realm handle and an (empty) write
    /// transaction.
    static func needsCardCountFix(_ deck: Deck) -> Bool {
        return deck.cards.contains { $0.count > 30 }
    }
}
