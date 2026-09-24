//
//  AppDelegate+MainMenu.swift
//  HSTracker
//
//  Fork only (dev 35fea72a): upstream finds its main menu items again with
//  item(withTitle: String.localizedString(...)), which misses whenever the
//  MainMenu catalog and Localizable translate a title differently - the case
//  for zh-Hans. The Dock deck menu also gave no sign of which deck was picked.
//

import AppKit

extension AppDelegate {
    enum MainMenuTag {
        static let decks = 10_001
        static let replays = 10_002
        static let lastReplays = 10_003
        static let window = 10_004
        static let lockWindows = 10_005
    }

    /// Once at launch, before buildMenu() looks anything up. Positions are
    /// MainMenu.xib's; the tags are set here rather than in the upstream xib.
    func configureMainMenuTags() {
        guard let mainMenu = NSApplication.shared.mainMenu,
              mainMenu.items.count >= 5 else {
            logger.error("Main menu does not have its expected layout")
            return
        }
        let deckMenu = mainMenu.items[2]
        let replayMenu = mainMenu.items[3]
        let windowMenu = mainMenu.items[4]
        guard let lastReplays = replayMenu.submenu?.items.first,
              let lockWindows = windowMenu.submenu?.items.first else {
            logger.error("Main menu is missing required items")
            return
        }
        deckMenu.tag = MainMenuTag.decks
        replayMenu.tag = MainMenuTag.replays
        lastReplays.tag = MainMenuTag.lastReplays
        windowMenu.tag = MainMenuTag.window
        lockWindows.tag = MainMenuTag.lockWindows
    }

    /// Ticks `deckId` in both the main and the Dock deck menus and clears the
    /// rest. Deck items carry their deck id as `representedObject`.
    func markActiveDeck(_ deckId: String?) {
        let menus = [NSApplication.shared.mainMenu?.item(withTag: MainMenuTag.decks)?.submenu,
                     dockMenu.item(withTag: 1)?.submenu]
        for menu in menus.compactMap({ $0 }) {
            for classItem in menu.items {
                classItem.submenu?.items.forEach { item in
                    let isActive = deckId != nil && item.representedObject as? String == deckId
                    item.state = isActive ? .on : .off
                }
            }
        }
    }
}
