/*
* This file is part of the HSTracker package.
* (c) Benjamin Michotte <bmichotte@gmail.com>
*
* For the full copyright and license information, please view the LICENSE
* file that was distributed with this source code.
*
* Created on 15/02/16.
*/

import Cocoa
import RealmSwift

class Tracker: OverWindowController, CardCellHover {

    // UI elements
    @IBOutlet private var cardsView: AnimatedCardList!
    @IBOutlet private var cardCounter: CardCounter!
    @IBOutlet private var playerDrawChance: PlayerDrawChance!
    @IBOutlet private var opponentDrawChance: OpponentDrawChance!
    @IBOutlet private var playerClass: NSView!
    @IBOutlet private var recordTracker: StringTracker!
    @IBOutlet private var graveyardCounter: GraveyardCounter!
    @IBOutlet private var playerBottom: DeckLens!
    @IBOutlet private var playerTop: DeckLens!
    @IBOutlet private var playerSideboards: DeckSideboards!
    @IBOutlet private var opponentRelatedCards: DeckLens!

    private var hero: CardBar?
    private var heroCard: Card?
    private var swiftUICards: TrackerCardListHost?
    private var swiftUIListActive = false
    private var swiftUIPlayerTop: TrackerSectionHost?
    private var swiftUIPlayerBottom: TrackerSectionHost?
    private var swiftUIOpponentRelatedCards: TrackerSectionHost?
    private var swiftUISectionsActive = false
    private var playerSideboardsData: [Sideboard] = []
    
    var bottomY = CGFloat(0.0)

    var hasValidFrame = false
    
    var playerType: PlayerType?
    var showGraveyard: Bool = false
    var proxy: Entity?
    var graveyard: [Entity]?
    
    var playerClassId: String?
    var playerName: String?
    var currentGameMode: GameMode = .none
    var currentFormat: Format = .unknown
    var matchInfo: MatchInfo?
    var recordTrackerMessage: String = ""
    var observer: NSObjectProtocol?
    
    private func getTrackingArea() -> NSTrackingArea {
        let frame = window?.frame ?? NSRect.zero
        return NSTrackingArea(rect: NSRect(x: frame.minX, y: bottomY, width: frame.width, height: frame.maxY - bottomY),
                              options: [.activeAlways, .mouseEnteredAndExited],
                              owner: self,
                              userInfo: nil)
    }

    override func windowDidLoad() {
        super.windowDidLoad()

        self.observer = NotificationCenter.default.addObserver(forName: NSNotification.Name(rawValue: Settings.tracker_opacity), object: nil, queue: OperationQueue.main) { _ in
            self.setOpacity()
        }
        if let playerType = playerType {
            graveyardCounter.playerType = playerType
            cardsView.playerType = playerType
            playerBottom.setPlayerType(playerType: playerType)
            playerTop.setPlayerType(playerType: playerType)
            playerSideboards.setPlayerType(playerType: playerType)
            opponentRelatedCards.setPlayerType(playerType: playerType)
        }
        cardsView.delegate = self
        playerBottom.setDelegate(delegate: self)
        playerTop.setDelegate(delegate: self)
        playerTop.setLabel(label: String.localizedString("On Top", comment: ""))
        playerBottom.setLabel(label: String.localizedString("On Bottom", comment: ""))
        playerSideboards.setDelegate(delegate: self)
        playerSideboards.isHidden = true
        opponentRelatedCards.setDelegate(delegate: self)
        opponentRelatedCards.setLabel(label: String.localizedString("Related_Cards", comment: ""))
        setOpacity()
        
        if playerType == .opponent {
            window?.contentView?.addTrackingArea(getTrackingArea())
        }
    }
    
    deinit {
        if let observer = self.observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    override func mouseEntered(with event: NSEvent) {
        if window?.mouseLocationOutsideOfEventStream.y ?? 0 >= bottomY {
            AppDelegate.instance().coreManager.game.windowManager.linkOpponentDeckPanel.showByOpponentStack()
        }
    }

    override func mouseExited(with event: NSEvent) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: {
            AppDelegate.instance().coreManager.game.windowManager.linkOpponentDeckPanel.hideByOpponentStack()
        })
    }

    func isLoaded() -> Bool {
        return self.isWindowLoaded
    }

    // MARK: - Notifications

    func setOpacity() {
        let alpha = CGFloat(Settings.trackerOpacity / 100.0)
        self.window!.backgroundColor = NSColor(red: 0,
                                               green: 0,
                                               blue: 0,
                                               alpha: alpha)
    }

    // MARK: - Game
    func update(cards: [Card], top: [Card], bottom: [Card], sideboards: [Sideboard], relatedCards: [Card], reset: Bool = false) {
        if Settings.useSwiftUITracker {
            let host = ensureSwiftUICards()
            if let playerType {
                host.viewModel.playerType = playerType
            }
            host.viewModel.update(cards: cards)
            host.isHidden = false
            cardsView.isHidden = true
            swiftUIListActive = true
        } else {
            if swiftUIListActive {
                cardsView.update(cards: cards, reset: true)
                swiftUIListActive = false
            } else {
                cardsView.update(cards: cards, reset: reset)
            }
            if swiftUICards != nil {
                cardsView.isHidden = false
                swiftUICards?.isHidden = true
            }
        }
        if Settings.useSwiftUITracker {
            let sections = ensureSwiftUISections()
            if let playerType {
                sections.top.viewModel.playerType = playerType
                sections.bottom.viewModel.playerType = playerType
                sections.related.viewModel.playerType = playerType
            }
            sections.top.viewModel.update(cards: top)
            sections.bottom.viewModel.update(cards: bottom)
            playerSideboardsData = sideboards
            sections.related.viewModel.update(cards: relatedCards)
            sections.top.isHidden = false
            sections.bottom.isHidden = false
            sections.related.isHidden = false
            playerTop.isHidden = true
            playerBottom.isHidden = true
            opponentRelatedCards.isHidden = true
            swiftUISectionsActive = true
        } else {
            let sectionReset = swiftUISectionsActive
            swiftUISectionsActive = false
            playerBottom.update(cards: bottom, reset: reset || sectionReset)
            playerTop.update(cards: top, reset: reset || sectionReset)
            playerSideboardsData = sideboards
            opponentRelatedCards.update(cards: relatedCards, reset: reset || sectionReset)
            if let swiftUIPlayerTop {
                swiftUIPlayerTop.isHidden = true
            }
            if let swiftUIPlayerBottom {
                swiftUIPlayerBottom.isHidden = true
            }
            if let swiftUIOpponentRelatedCards {
                swiftUIOpponentRelatedCards.isHidden = true
            }
        }
    }

    private func ensureSwiftUICards() -> TrackerCardListHost {
        if let swiftUICards {
            return swiftUICards
        }
        let host = TrackerCardListHost(frame: .zero)
        host.onHover = { [weak self] card, view in
            guard let self else { return }
            let component: HoveredComponent = self.playerType == .player ? .playerCardView : .opponentCardView
            self.hover(card: card, frameView: view, component: component)
        }
        host.onExit = { [weak self] card in
            self?.out(card: card)
        }
        if let playerType {
            host.viewModel.playerType = playerType
        }
        window?.contentView?.addSubview(host)
        swiftUICards = host
        return host
    }

    private func ensureSwiftUISections() -> (top: TrackerSectionHost,
                                             bottom: TrackerSectionHost,
                                             related: TrackerSectionHost) {
        if swiftUIPlayerTop == nil {
            let host = TrackerSectionHost(
                frame: .zero,
                title: String.localizedString("On Top", comment: "")
            )
            host.onHover = { [weak self] card, view in
                self?.hover(card: card, frameView: view, component: .playerTop)
            }
            host.onExit = { [weak self] card in
                self?.out(card: card)
            }
            if let playerType {
                host.viewModel.playerType = playerType
            }
            window?.contentView?.addSubview(host)
            swiftUIPlayerTop = host
        }
        if swiftUIPlayerBottom == nil {
            let host = TrackerSectionHost(
                frame: .zero,
                title: String.localizedString("On Bottom", comment: "")
            )
            host.onHover = { [weak self] card, view in
                self?.hover(card: card, frameView: view, component: .playerBottom)
            }
            host.onExit = { [weak self] card in
                self?.out(card: card)
            }
            if let playerType {
                host.viewModel.playerType = playerType
            }
            window?.contentView?.addSubview(host)
            swiftUIPlayerBottom = host
        }
        if swiftUIOpponentRelatedCards == nil {
            let host = TrackerSectionHost(
                frame: .zero,
                title: String.localizedString("Related_Cards", comment: "")
            )
            host.onHover = { [weak self] card, view in
                self?.hover(card: card, frameView: view, component: .opponentRelatedCards)
            }
            host.onExit = { [weak self] card in
                self?.out(card: card)
            }
            if let playerType {
                host.viewModel.playerType = playerType
            }
            window?.contentView?.addSubview(host)
            swiftUIOpponentRelatedCards = host
        }
        return (swiftUIPlayerTop!, swiftUIPlayerBottom!, swiftUIOpponentRelatedCards!)
    }

    private var mainListCount: Int {
        if Settings.useSwiftUITracker {
            return swiftUICards?.count ?? 0
        }
        return cardsView.count
    }

    private var playerTopCount: Int {
        if Settings.useSwiftUITracker {
            return swiftUIPlayerTop?.count ?? 0
        }
        return playerTop.count
    }

    private var playerBottomCount: Int {
        if Settings.useSwiftUITracker {
            return swiftUIPlayerBottom?.count ?? 0
        }
        return playerBottom.count
    }

    private var opponentRelatedCardsCount: Int {
        if Settings.useSwiftUITracker {
            return swiftUIOpponentRelatedCards?.count ?? 0
        }
        return opponentRelatedCards.count
    }
    
    override func updateFrames() {
        super.updateFrames()
        guard let windowFrame = self.window?.contentView?.frame else { return }
        
        let windowWidth = windowFrame.width
        let windowHeight = windowFrame.height
        
        let ratio: CGFloat
        switch Settings.cardSize {
        case .tiny: ratio = CGFloat(kRowHeight / kTinyRowHeight)
        case .small: ratio = CGFloat(kRowHeight / kSmallRowHeight)
        case .medium: ratio = CGFloat(kRowHeight / kMediumRowHeight)
        case .huge: ratio = CGFloat(kRowHeight / kHighRowHeight)
        case .big: ratio = 1.0
        }
        
        if playerType == .opponent {
            cardCounter.isHidden = !Settings.showOpponentCardCount
            opponentDrawChance.isHidden = !Settings.showOpponentDrawChance
            playerDrawChance.isHidden = true
            playerClass.isHidden = !Settings.showOpponentClassInTracker
            recordTracker.isHidden = true
        } else {
            cardCounter.isHidden = !Settings.showPlayerCardCount
            opponentDrawChance.isHidden = true
            playerDrawChance.isHidden = !Settings.showPlayerDrawChance
            playerClass.isHidden = !Settings.showDeckNameInTracker
            recordTracker.isHidden = !Settings.showWinLossRatio
        }
        
        graveyardCounter.isHidden = !showGraveyard
        
        if !recordTracker.isHidden {
            recordTracker.needsDisplay = true
        }
        
        recordTracker.message = recordTrackerMessage
                
        // map entitiy to card [count]
        var minionmap: [Card: Int] = [:]
        var minions: Int = 0
        var murlocks: Int = 0
        if let graveyard = self.graveyard {
            for e: Entity in graveyard where e.isMinion {
                if let value = minionmap[e.card] {
                    minionmap[e.card] = value + 1
                } else {
                    minionmap[e.card] = 1
                }
                minions += 1
                if e.card.race == .murloc {
                    murlocks += 1
                }
            }
        }
        var graveyardminions: [Card] = []
        for (card, count) in minionmap {
            card.count = count
            graveyardminions.append(card)
        }
        graveyardCounter.graveyard = graveyardminions.sortCardList()
        graveyardCounter.minions = minions
        graveyardCounter.murlocks = murlocks
        
        let bigFrameHeight = round(71 / ratio)
        let smallFrameHeight = round(40 / ratio)
        
        var offsetFrames: CGFloat = 0
        var startHeight: CGFloat = 0
        
        if !playerClass.isHidden && playerType == .opponent {
            if let playerClassId = self.playerClassId {
                offsetFrames += smallFrameHeight
                
                playerClass.frame = NSRect(x: 0,
                                           y: windowHeight - smallFrameHeight,
                                           width: windowHeight,
                                           height: smallFrameHeight)
                startHeight += smallFrameHeight
                
                if hero == nil {
                    hero = CardBar.factory()
                    if let hero = hero {
                        playerClass.addSubview(hero)
                    }
                }
                
                hero?.playerType = .hero
                hero?.card = Cards.hero(byId: playerClassId)
                hero?.card?.count = 1
                hero?.card?.cost = -1
                hero?.playerName = playerName
                hero?.frame = NSRect(x: 0, y: 0,
                                     width: windowWidth,
                                     height: smallFrameHeight)
                hero?.update(highlight: false)
                hero?.needsDisplay = true
            }
        } else if !playerClass.isHidden && playerType == .player {
            
            offsetFrames += smallFrameHeight
            
            playerClass.frame = NSRect(x: 0,
                                       y: windowHeight - smallFrameHeight,
                                       width: windowHeight,
                                       height: smallFrameHeight)
            startHeight += smallFrameHeight
            if hero == nil {
                
                hero = CardBar.factory()
                if let hero = hero {
                    playerClass.addSubview(hero)
                }
            }
            hero?.playerType = .hero
            hero?.card = Cards.hero(byId: self.playerClassId ?? "")

            hero?.card?.count = 1
            hero?.playerName = playerName
            
            hero?.frame = NSRect(x: 0, y: 0,
                                 width: windowWidth,
                                 height: smallFrameHeight)
            hero?.update(highlight: false)
            hero?.needsDisplay = true
            
        }
        
        if !opponentDrawChance.isHidden {
            offsetFrames += bigFrameHeight
        }
        if !playerDrawChance.isHidden {
            offsetFrames += smallFrameHeight
        }
        if !cardCounter.isHidden {
            offsetFrames += smallFrameHeight
        }
        if showGraveyard {
            offsetFrames += smallFrameHeight
        }
        if !recordTracker.isHidden {
            offsetFrames += smallFrameHeight
        }

        var totalCards = mainListCount

        if playerBottomCount > 0 && Settings.showPlayerCardsBottom {
            offsetFrames += smallFrameHeight
            totalCards += playerBottomCount
        }
        if playerTopCount > 0 && Settings.showPlayerCardsTop {
            offsetFrames += smallFrameHeight
            totalCards += playerTopCount
        }
        if opponentRelatedCardsCount > 0 && Settings.showOpponentRelatedCards {
            offsetFrames += smallFrameHeight
            totalCards += opponentRelatedCardsCount
        }

        var cardHeight: CGFloat
        switch Settings.cardSize {
        case .tiny: cardHeight = CGFloat(kTinyRowHeight)
        case .small: cardHeight = CGFloat(kSmallRowHeight)
        case .medium: cardHeight = CGFloat(kMediumRowHeight)
        case .huge: cardHeight = CGFloat(kHighRowHeight)
        case .big: cardHeight = CGFloat(kRowHeight)
        }
        if totalCards > 0 {
            cardHeight = min(cardHeight, (windowHeight - offsetFrames) / CGFloat(totalCards))
        }
        
        let cardViewHeight = CGFloat(mainListCount) * cardHeight
        var y: CGFloat = windowHeight - startHeight

        if playerTopCount > 0 && Settings.showPlayerCardsTop {
            let playerTopHeight = CGFloat(playerTopCount) * cardHeight + smallFrameHeight + 5
            y -= playerTopHeight
            if Settings.useSwiftUITracker {
                let host = ensureSwiftUISections().top
                host.cardHeight = cardHeight
                host.headerHeight = smallFrameHeight
                host.viewModel.syncAppearance()
                host.frame = NSRect(x: 0, y: y, width: windowWidth, height: playerTopHeight)
                host.isHidden = false
                playerTop.frame = .zero
                playerTop.isHidden = true
            } else {
                playerTop.frame = NSRect(x: 0, y: y, width: windowWidth, height: playerTopHeight)
                playerTop.updateFrames(frameHeight: smallFrameHeight)
                playerTop.isHidden = false
                if let host = swiftUIPlayerTop {
                    host.frame = .zero
                    host.isHidden = true
                }
            }
        } else {
            playerTop.frame = NSRect.zero
            playerTop.isHidden = true
            if Settings.useSwiftUITracker {
                let host = ensureSwiftUISections().top
                host.frame = .zero
                host.isHidden = true
            } else {
                playerTop.updateFrames(frameHeight: smallFrameHeight)
                if let host = swiftUIPlayerTop {
                    host.frame = .zero
                    host.isHidden = true
                }
            }
        }

        y -= cardViewHeight
        if Settings.useSwiftUITracker {
            let host = ensureSwiftUICards()
            host.cardHeight = cardHeight
            host.viewModel.syncAppearance()
            host.frame = NSRect(x: 0,
                                y: y,
                                width: windowWidth,
                                height: cardViewHeight)
            host.isHidden = false
            cardsView.frame = .zero
            cardsView.isHidden = true
        } else {
            cardsView.cardHeight = cardHeight
            cardsView.frame = NSRect(x: 0,
                                     y: y,
                                     width: windowWidth,
                                     height: cardViewHeight)
            cardsView.updateFrames()
            if let host = swiftUICards {
                cardsView.isHidden = false
                host.frame = .zero
                host.isHidden = true
            }
        }
                
        if playerBottomCount > 0 && Settings.showPlayerCardsBottom {
            let playerBottomHeight = CGFloat(playerBottomCount) * cardHeight + smallFrameHeight + 5
            y -= playerBottomHeight
            if Settings.useSwiftUITracker {
                let host = ensureSwiftUISections().bottom
                host.cardHeight = cardHeight
                host.headerHeight = smallFrameHeight
                host.viewModel.syncAppearance()
                host.frame = NSRect(x: 0, y: y, width: windowWidth, height: playerBottomHeight)
                host.isHidden = false
                playerBottom.frame = .zero
                playerBottom.isHidden = true
            } else {
                playerBottom.frame = NSRect(x: 0, y: y, width: windowWidth, height: playerBottomHeight)
                playerBottom.updateFrames(frameHeight: smallFrameHeight)
                playerBottom.isHidden = false
                if let host = swiftUIPlayerBottom {
                    host.frame = .zero
                    host.isHidden = true
                }
            }
        } else {
            playerBottom.frame = NSRect.zero
            playerBottom.isHidden = true
            if Settings.useSwiftUITracker {
                let host = ensureSwiftUISections().bottom
                host.frame = .zero
                host.isHidden = true
            } else {
                playerBottom.updateFrames(frameHeight: smallFrameHeight)
                if let host = swiftUIPlayerBottom {
                    host.frame = .zero
                    host.isHidden = true
                }
            }
        }
        playerSideboards.frame = NSRect.zero
        playerSideboards.updateFrames(frameHeight: smallFrameHeight, cardHeight: cardHeight)
        playerSideboards.isHidden = true
        if !cardCounter.isHidden {
            y -= smallFrameHeight
            cardCounter.frame = NSRect(x: 0, y: y, width: windowWidth, height: smallFrameHeight)
        }
        if !opponentDrawChance.isHidden {
            y -= bigFrameHeight
            opponentDrawChance.frame = NSRect(x: 0,
                                              y: y,
                                              width: windowWidth,
                                              height: bigFrameHeight)
        }
        if !playerDrawChance.isHidden {
            y -= smallFrameHeight
            playerDrawChance.frame = NSRect(x: 0,
                                            y: y,
                                            width: windowWidth,
                                            height: smallFrameHeight)
        }
        if opponentRelatedCardsCount > 0 && Settings.showOpponentRelatedCards {
            let opponentRelatedCardsHeight = CGFloat(opponentRelatedCardsCount) * cardHeight + smallFrameHeight + 5
            y -= opponentRelatedCardsHeight
            if Settings.useSwiftUITracker {
                let host = ensureSwiftUISections().related
                host.cardHeight = cardHeight
                host.headerHeight = smallFrameHeight
                host.viewModel.syncAppearance()
                host.frame = NSRect(x: 0, y: y, width: windowWidth, height: opponentRelatedCardsHeight)
                host.isHidden = false
                opponentRelatedCards.frame = .zero
                opponentRelatedCards.isHidden = true
            } else {
                opponentRelatedCards.frame = NSRect(x: 0, y: y, width: windowWidth, height: opponentRelatedCardsHeight)
                opponentRelatedCards.updateFrames(frameHeight: smallFrameHeight)
                opponentRelatedCards.isHidden = false
                if let host = swiftUIOpponentRelatedCards {
                    host.frame = .zero
                    host.isHidden = true
                }
            }
        } else {
            opponentRelatedCards.frame = NSRect.zero
            opponentRelatedCards.isHidden = true
            if Settings.useSwiftUITracker {
                let host = ensureSwiftUISections().related
                host.frame = .zero
                host.isHidden = true
            } else {
                opponentRelatedCards.updateFrames(frameHeight: smallFrameHeight)
                if let host = swiftUIOpponentRelatedCards {
                    host.frame = .zero
                    host.isHidden = true
                }
            }
        }
        if !graveyardCounter.isHidden {
            y -= smallFrameHeight
            graveyardCounter?.frame = NSRect(x: 0,
                                             y: y,
                                             width: windowWidth,
                                             height: smallFrameHeight)
            if playerType == .opponent {
                graveyardCounter?.displayDetails = Settings.showOpponentGraveyardDetails
            } else {
                graveyardCounter?.displayDetails = Settings.showPlayerGraveyardDetails
            }
            graveyardCounter?.cardHeight = cardHeight
            graveyardCounter?.needsDisplay = true
        }
        if !recordTracker.isHidden {
            y -= smallFrameHeight
            recordTracker.frame = NSRect(x: 0,
                                         y: y,
                                         width: windowWidth,
                                         height: smallFrameHeight)
        }
        
        bottomY = y
        if playerType == .opponent, let cv = window?.contentView {
            for ta in cv.trackingAreas {
                cv.removeTrackingArea(ta)
            }
            cv.addTrackingArea(getTrackingArea())
        }
    }

    func updateCardCounter(deckCount: Int, handCount: Int, hasCoin: Bool, gameStarted: Bool) {
        
        cardCounter?.deckCount = deckCount
        cardCounter?.handCount = handCount
        cardCounter?.needsDisplay = true
        
        if playerType == .opponent {
            var draw1 = 0.0, draw2 = 0.0, hand1 = 0.0, hand2 = 0.0
            if deckCount > 0 {
                draw1 = (1 * 100.0) / Double(deckCount)
                draw2 = (2 * 100.0) / Double(deckCount)
            }
            if gameStarted {
                // opponent's chances of having a particular card (of which they have either one
                // or two in the deck) after the next draw, i.e. at the start of their next turn
                if deckCount <= 1 {
                    // opponent will have drawn all his cards
                    hand1 = 100
                    hand2 = 100
                } else {
                    let maxDeckSize = max(30, deckCount)

                    // Deck size after the opponent draws
                    let nextDeckSize = deckCount - 1

                    // probability a given card has been drawn if there is one copy in the deck
                    hand1 = Double(maxDeckSize - nextDeckSize) / Double(maxDeckSize)

                    // probability a given card has been drawn if there are two copies in the deck
                    let prob2 = Double((maxDeckSize - 1) - nextDeckSize) / Double(maxDeckSize - 1)
                    hand2 = 2 * hand1 - (hand1 * prob2)

                    hand1 *= 100
                    hand2 *= 100
                }
            }
            opponentDrawChance?.drawChance1 = draw1
            opponentDrawChance?.drawChance2 = draw2
            opponentDrawChance?.handChance1 = hand1
            opponentDrawChance?.handChance2 = hand2
            opponentDrawChance?.needsDisplay = true
        } else {
            var draw1 = 0.0, draw2 = 0.0
            if deckCount > 0 {
                draw1 = (1 * 100.0) / Double(deckCount)
                draw2 = (2 * 100.0) / Double(deckCount)
            }

            playerDrawChance?.drawChance1 = draw1
            playerDrawChance?.drawChance2 = draw2
            playerDrawChance?.needsDisplay = true
        }
    }
    
    private var delayedTooltip: DelayedTooltip?
    
    // MARK: - CardCellHover
    enum HoveredComponent {
        case playerTop,
             playerBottom,
             playerSideboards,
             playerCardView,
             opponentRelatedCards,
             opponentCardView,
             other
    }
    
    private func getHoverComponent(_ cell: CardBar) -> HoveredComponent {
        var view: NSView? = cell
        while view != nil {
            if view == playerTop {
                return .playerTop
            } else if view == playerBottom {
                return .playerBottom
            } else if view == playerSideboards {
                return .playerSideboards
            } else if view == opponentRelatedCards {
                return .opponentRelatedCards
            } else if view == cardsView {
                if playerType == .player {
                    return .playerCardView
                } else {
                    return .opponentCardView
                }
            }
            view = view?.superview
        }
        return .other
    }
    
    func setRelatedCardsTooltip(_ player: Player, _ cardId: String, _ rect: NSRect) {
        guard #available(macOS 10.15, *) else { return }
        let game = AppDelegate.instance().coreManager.game
        let relatedCards = game.getRelatedCards(player: player, cardId: cardId)

        let hearthstoneRect = SizeHelper.hearthstoneWindow.frame
        let tooltipGridCards = game.windowManager.tooltipGridCards
        if relatedCards.count > 0 {
            let nonNullableRelatedCards = relatedCards.compactMap { $0 }

            tooltipGridCards.setCardIdsFromCards(nonNullableRelatedCards)
            tooltipGridCards.setTitle(String.localizedString("Related_Cards", comment: ""))
            // Passing player (like Game.swift's hover paths already do) so dynamic
            // evolve/devolve pools resolve their live-state summary here too, instead of
            // silently falling through to no summary on a deck-list hover.
            let (statistics, summary, hasLargePool) = game.relatedCardsManager.getPoolStatistics(cardId: cardId, relatedCards: relatedCards, player: player)
            tooltipGridCards.setPoolStatistics(statistics, relatedCardsSummary: summary, hasLargePool: hasLargePool)
            let screen = NSScreen.screens.first { s in s.frame.contains(rect) } ?? NSScreen.main
            var y = rect.minY
            if rect.minY + CGFloat(tooltipGridCards.gridHeight) > screen?.frame.height ?? hearthstoneRect.height {
                y = hearthstoneRect.maxY - CGFloat(tooltipGridCards.gridHeight)
            }

            var x: CGFloat = 0.0
            if rect.minX < hearthstoneRect.width / 2 {
                x = rect.maxX
            } else {
                x = rect.minX - CGFloat(tooltipGridCards.gridWidth)
            }

            let tooltipFrame = NSRect(x: x, y: y, width: CGFloat(tooltipGridCards.gridWidth), height: CGFloat(tooltipGridCards.gridHeight))
            tooltipGridCards.show(frame: tooltipFrame)
            RelatedCardsRightClickMonitor.shared.setHoveredLargePool(
                card: hasLargePool ? Cards.by(cardId: cardId) : nil,
                pool: hasLargePool ? nonNullableRelatedCards : [],
                anchorFrame: tooltipFrame)
        } else {
            tooltipGridCards.hide()
            RelatedCardsRightClickMonitor.shared.clearHoveredLargePool()
        }
    }

    private func sideboardCards(for card: Card) -> [Card]? {
        guard playerType == .player, !Settings.hidePlayerSideboards else {
            return nil
        }
        // Zilliax is shown as a copy of its cosmetic module, so its own id never
        // matches an owner id. deckbuildingCard maps that copy back.
        let ownerId = card.deckbuildingCard.id
        guard let sideboard = playerSideboardsData.first(where: { $0.ownerCardId == ownerId }),
              !sideboard.cards.isEmpty else {
            return nil
        }
        return sideboard.cards
    }

    private func showTooltipGridCards(cards: [Card], title: String, rect: NSRect) {
        let game = AppDelegate.instance().coreManager.game
        let hearthstoneRect = SizeHelper.hearthstoneWindow.frame
        let tooltipGridCards = game.windowManager.tooltipGridCards
        if !cards.isEmpty {
            tooltipGridCards.setCardIdsFromCards(cards)
            tooltipGridCards.setTitle(title)
            tooltipGridCards.setPoolStatistics(nil, relatedCardsSummary: nil, hasLargePool: false)
            let screen = NSScreen.screens.first { $0.frame.contains(rect) } ?? NSScreen.main
            var y = rect.minY
            if rect.minY + CGFloat(tooltipGridCards.gridHeight) > screen?.frame.height ?? hearthstoneRect.height {
                y = hearthstoneRect.maxY - CGFloat(tooltipGridCards.gridHeight)
            }

            let x = rect.minX < hearthstoneRect.width / 2
                ? rect.maxX
                : rect.minX - CGFloat(tooltipGridCards.gridWidth)
            let tooltipFrame = NSRect(x: x, y: y, width: CGFloat(tooltipGridCards.gridWidth), height: CGFloat(tooltipGridCards.gridHeight))
            tooltipGridCards.show(frame: tooltipFrame)
            RelatedCardsRightClickMonitor.shared.clearHoveredLargePool()
        } else {
            tooltipGridCards.hide()
            RelatedCardsRightClickMonitor.shared.clearHoveredLargePool()
        }
    }
    
    func highlightPlayerDeckCards(highlightSourceCardId: String?) {
        guard let highlightSourceCardId, !highlightSourceCardId.isEmpty, Settings.showPlayerHighlightSynergies else {
            cardsView?.shouldHighlightCard = nil
            swiftUICards?.viewModel.setHighlight(nil)
            return
        }
        
        let game = AppDelegate.instance().coreManager.game
        let highlightSourceCard = game.relatedCardsManager.getCardWithHighlight(highlightSourceCardId)
        let fn = highlightSourceCard?.shouldHighlight
        if Settings.useSwiftUITracker {
            swiftUICards?.viewModel.setHighlight(fn)
            cardsView?.shouldHighlightCard = nil
        } else {
            cardsView?.shouldHighlightCard = fn
            swiftUICards?.viewModel.setHighlight(nil)
        }
    }
        
    func hover(cell: CardBar, card: Card) {
        hover(card: card, frameView: cell, component: getHoverComponent(cell))
    }

    private func hover(card: Card, frameView: NSView, component: HoveredComponent) {
        if playerType == .player {
            highlightPlayerDeckCards(highlightSourceCardId: card.id)
        }
        delayedTooltip?.cancel()
        delayedTooltip = DelayedTooltip(handler: tooltipDisplay, 0.400,
                                        HoverTooltipPayload(cell: frameView, card: card, component: component))
    }

    private final class HoverTooltipPayload {
        let cell: NSView
        let card: Card
        let component: HoveredComponent
        init(cell: NSView, card: Card, component: HoveredComponent) {
            self.cell = cell
            self.card = card
            self.component = component
        }
    }
    
    private func tooltipDisplay(_ userInfo: Any?) {
        if let window, let payload = userInfo as? HoverTooltipPayload {
            let cell = payload.cell
            let card = payload.card
            let windowRect = window.frame
            
            let hoverFrame = NSRect(x: 0, y: 0, width: 256, height: 388)
            
            var x: CGFloat
            // decide if the popup window should on the left or right side of the tracker
            if windowRect.origin.x < hoverFrame.size.width {
                x = windowRect.origin.x + windowRect.size.width
            } else {
                x = windowRect.origin.x - hoverFrame.size.width
            }
            
            let cellFrameRelativeToWindow = cell.convert(cell.bounds, to: nil)
            guard let cellFrameRelativeToScreen = cell.window?.convertToScreen(cellFrameRelativeToWindow) else {
                delayedTooltip = nil
                return
            }
            
            let y: CGFloat = cellFrameRelativeToScreen.origin.y - hoverFrame.height / 2.0
            
            let frame = [x, y, hoverFrame.width, hoverFrame.height]
            
            let userinfo = [
                "card": card,
                "frame": frame,
                "useFrame": true
            ] as [String: Any]
            
            NotificationCenter.default
                .post(name: Notification.Name(rawValue: Events.show_floating_card),
                      object: nil,
                      userInfo: userinfo)
            
            let tooltipRect = NSRect(x: frame[0], y: frame[1], width: frame[2], height: frame[3])
            switch payload.component {
            case .opponentRelatedCards, .opponentCardView:
                if Settings.showOpponentRelatedCards {
                    setRelatedCardsTooltip(AppDelegate.instance().coreManager.game.opponent, card.id, tooltipRect)
                }
            case .playerTop, .playerBottom, .playerSideboards, .playerCardView:
                if let cards = sideboardCards(for: card) {
                    showTooltipGridCards(cards: cards, title: card.name, rect: tooltipRect)
                } else if Settings.showPlayerRelatedCards {
                    setRelatedCardsTooltip(AppDelegate.instance().coreManager.game.player, card.id, tooltipRect)
                }
            default:
                break
            }
        }
        delayedTooltip = nil
    }

    func out(card: Card) {
        if playerType == .player {
            highlightPlayerDeckCards(highlightSourceCardId: nil)
        }
        delayedTooltip?.cancel()
        delayedTooltip = nil
        let userinfo = [
            "card": card
            ] as [String: Any]
        NotificationCenter.default.post(name: Notification.Name(rawValue: Events.hide_floating_card),
                                        object: nil,
                                        userInfo: userinfo)
        
        if #available(macOS 10.15, *) {
            AppDelegate.instance().coreManager.game.windowManager.tooltipGridCards.hide()
        }
    }
}
