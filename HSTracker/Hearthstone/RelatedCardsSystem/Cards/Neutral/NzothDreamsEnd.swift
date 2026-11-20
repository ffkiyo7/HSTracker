//
//  NzothDreamsEnd.swift
//  HSTracker
//
//  Created by Francisco Moraes on 10/13/26.
//  Copyright © 2026 Benjamin Michotte. All rights reserved.
//

import Foundation

// "Old God Cost (1) less for each Deathrattle minion you've summoned this game."
// Shows the candidates of its Army of N'Zoth ability: "Resurrect 4 different Deathrattle minions."
// "Different" means each resurrected minion is distinct, so the grid is de-duplicated.
class NzothDreamsEnd: ResurrectionCard {
    required init() {}

    override func getCardId() -> String {
        return CardIds.Collectible.Neutral.NzothDreamsEnd
    }

    override func filterCard(card: Card) -> Bool {
        return card.type == .minion && card.hasDeathrattle()
    }

    override func resurrectsMultipleCards() -> Bool {
        return false
    }
}
