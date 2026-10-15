//
//  RedDragonMod.swift
//  HSTracker
//
//  红龙辅助作为 HSTracker mod 的入口：只通过 ModKit 的口子和 HSTracker 打交道（对局事件、读对局状态、overlay 图层、
//  设置页、宿主服务），不碰宿主类型。
//

import Foundation
import ModKit
import RedDragonCore

final class RedDragonMod: HSTrackerMod {

    static let manifest = ModManifest(id: "red-dragon", name: RDText.assistantName, version: "1.0")

    static func registration() -> ModRegistration {
        ModRegistration(manifest: manifest) { RedDragonMod() }
    }

    private var assistant: RedDragonAssistant?
    private var hotkeys: RedDragonHotkeys?
    private var overlay: RedDragonOverlay?

    @MainActor
    func activate(_ host: any ModHostServices) throws -> ModContributions {
        RDStyle.tracker = host.trackerStyle
        let assistant = RedDragonAssistant(environment: .live(host), settings: host.settings)
        let hotkeys = RedDragonHotkeys(assistant: assistant, settings: host.settings,
                                       log: { [weak host] in host?.warning($0) })
        hotkeys.start()
        let overlay = RedDragonOverlay(viewModel: RedDragonOverlayViewModel(assistant: assistant,
                                                                            cardName: { host.cardName($0) ?? $0 }))
        self.assistant = assistant
        self.hotkeys = hotkeys
        self.overlay = overlay
        return ModContributions(gameEvents: assistant, overlay: overlay,
                                preferencePane: RedDragonPreferences.pane(settings: host.settings))
    }

    @MainActor
    func deactivate() {
        hotkeys?.stop()
    }
}
