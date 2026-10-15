//
//  RedDragonTestSupport.swift
//  HSTrackerTests
//
//  红龙辅助只通过 ModKit 读对局、拿几何（`ModGameState` / `ModEntity` / `ModOverlayCanvas`）。回放类测试手里是宿主的
//  `Game` / `Entity` 和画布尺寸：这里用 app 的适配层（HSTracker/Mods/）把它们接过去，测试照旧按原来的写法调。
//

import AppKit
import Foundation
import ModKit
@testable import HSTracker
@testable import RedDragonCore

extension RedDragonAssistant {
    func parserBatchDidEnd(_ game: Game, linesProcessed: Bool, idle: Bool) {
        parserBatchDidEnd(ModGameAdapter(game), linesProcessed: linesProcessed, idle: idle)
    }

    func parserTopBlockDidClose(_ game: Game) {
        parserTopBlockDidClose(ModGameAdapter(game))
    }
}

extension RDGameSnapshot {
    static func capture(game: Game) -> RDGameSnapshot? {
        return capture(state: ModGameAdapter(game))
    }

    static func playerEntity(game: Game) -> Entity? {
        return (playerEntity(state: ModGameAdapter(game)) as? ModEntityAdapter)?.entity
    }

    static func capture(entities all: [Entity], playerId: Int, opponentId: Int,
                        deck: [String: Int], band: [String]?,
                        opponentBoardDamage: Int = 0, deadToBoard: Bool = false,
                        match: Date? = nil) -> RDGameSnapshot {
        return capture(entities: all.map { ModEntityAdapter($0) as any ModEntity }, playerId: playerId,
                       opponentId: opponentId, deck: deck, band: band, opponentBoardDamage: opponentBoardDamage,
                       deadToBoard: deadToBoard, match: match)
    }
}

extension RDDeckGate {
    static func isRedDragonDeck(_ deck: PlayingDeck) -> Bool {
        return isRedDragonDeck(ModGameAdapter.modDeck(deck))
    }
}

/// 测试用的红龙设置：单独的 UserDefaults 域，不碰用户真实的设置
enum RDTestSettings {
    static let defaults = UserDefaults(suiteName: "net.hearthsim.hstracker.tests.red-dragon")!
    static let store = ModSettingsStore(modID: RedDragonMod.manifest.id, defaults: defaults)

    static var assist: Bool {
        get { RDSettings.isEnabled(store) }
        set { store.set(newValue, forKey: RDSettings.assist) }
    }
}

// MARK: - 几何：按画布尺寸取宿主的几何（app 的 `HostBoardGeometry`）

extension RDOverlayGeometry {
    typealias TrackerPlacement = ModReservedFrames.TrackerPlacement

    static func canvas(_ size: CGSize, trackers: [CGRect] = []) -> ModOverlayCanvas {
        return ModOverlayCanvas(size: size, reservedFrames: trackers, geometry: HostBoardGeometry(canvas: size))
    }

    static func handCardSize(_ size: CGSize) -> CGSize { handCardSize(canvas(size)) }

    static func handCard(index: Int, count: Int, canvas size: CGSize) -> (center: CGPoint, angle: Double) {
        handCard(index: index, count: count, canvas: canvas(size))
    }

    static func badgeSize(_ size: CGSize) -> CGFloat { badgeSize(canvas(size)) }

    static func minionRect(isEnemy: Bool, index: Int, count: Int, canvas size: CGSize) -> CGRect {
        minionRect(isEnemy: isEnemy, index: index, count: count, canvas: canvas(size))
    }

    static func handBox(_ size: CGSize) -> CGRect { handBox(canvas(size)) }

    static func fixedObstacles(_ size: CGSize, hand: CGRect? = nil) -> [CGRect] {
        fixedObstacles(canvas(size), hand: hand)
    }

    static func panelLayout(canvas size: CGSize, badge: RDOverlayModel.Badge, lines: [RDOverlayModel.Line],
                            trackers: [CGRect]) -> PanelLayout? {
        panelLayout(canvas: canvas(size, trackers: trackers), badge: badge, lines: lines)
    }

    static func trackerBox(_ p: TrackerPlacement, cardSize: CardSize, canvas: CGSize) -> CGRect? {
        ModReservedFrames.trackerBox(p, cardSize: cardSize, canvas: canvas)
    }
}

extension RedDragonOverlayView {
    init(viewModel: RedDragonOverlayViewModel, canvasSize: CGSize, trackers: [CGRect] = []) {
        self.init(viewModel: viewModel, canvas: RDOverlayGeometry.canvas(canvasSize, trackers: trackers))
    }
}

extension RootOverlayViewModel {
    /// 换上测试自己的红龙图层（不接 assistant，测试直接 `receive`）：app 启动时启用的那份红龙和真的 overlay 窗口共用，
    /// 测试改它会让真窗口也重算、改写 `RedDragonOverlayView` 的统计
    func installTestRedDragon(cardName: @escaping (String) -> String) {
        let vm = RedDragonOverlayViewModel(assistant: nil, cardName: cardName)
        mods = ModOverlayLayerModel(providers: [(id: RedDragonMod.manifest.id, provider: RedDragonOverlay(viewModel: vm))],
                                    trackers: [playerTracker, opponentTracker])
    }

    var redDragon: RedDragonOverlayViewModel {
        // swiftlint:disable:next force_cast
        return (mods.providers.first { $0.id == RedDragonMod.manifest.id }!.provider as! RedDragonOverlay).viewModel
    }
}
