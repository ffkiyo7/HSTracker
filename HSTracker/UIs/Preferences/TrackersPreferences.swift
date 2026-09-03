//
//  TrackersPreferences.swift
//  HSTracker
//

import AppKit
import Preferences
import SwiftUI

class TrackersPreferences: PreferencePaneController, PreferencePane {
    var preferencePaneIdentifier = Preferences.PaneIdentifier.trackers

    var preferencePaneTitle = String.localizedString("Trackers", comment: "")

    var toolbarItemIcon = NSImage(named: "settings-trackers")!

    private var hostingController: NSHostingController<TrackersPreferencesView>?

    override func loadView() {
        let controller = NSHostingController(rootView: TrackersPreferencesView())
        hostingController = controller
        view = controller.view
    }
}

private struct TrackersPreferencesView: View {
    @StateObject private var state = TrackersPreferencesState()
    private let themes = ["classic", "frost", "dark", "minimal"]

    var body: some View {
        let _ = state.revision
        Form {
            Section {
                Picker(label("tracker_theme"), selection: state.setting(Settings.theme, set: { Settings.theme = $0 })) {
                    ForEach(themes, id: \.self) { theme in
                        Text(label("tracker_theme_\(theme)"))
                            .tag(theme)
                    }
                }
                Picker(label("tracker_card_size"), selection: cardSize) {
                    Text(label("tracker_card_size_tiny")).tag(CardSize.tiny)
                    Text(label("tracker_card_size_small")).tag(CardSize.small)
                    Text(label("tracker_card_size_medium")).tag(CardSize.medium)
                    Text(label("tracker_card_size_big")).tag(CardSize.big)
                    Text(label("tracker_card_size_huge")).tag(CardSize.huge)
                }
                HStack {
                    Text(label("tracker_opacity"))
                    Slider(value: opacity, in: 0...100, step: 1)
                    Text("\(Int(Settings.trackerOpacity))%")
                        .monospacedDigit()
                        .frame(width: 36, alignment: .trailing)
                }
                Toggle(label("tracker_highlight_cards_in_hand"), isOn: state.setting(Settings.highlightCardsInHand, set: { Settings.highlightCardsInHand = $0 }))
                Toggle(label("tracker_highlight_last_drawn"), isOn: state.setting(Settings.highlightLastDrawn, set: { Settings.highlightLastDrawn = $0 }))
                Toggle(label("tracker_highlight_discarded"), isOn: state.setting(Settings.highlightDiscarded, set: { Settings.highlightDiscarded = $0 }))
                Toggle(label("tracker_remove_zero_count_cards"), isOn: state.setting(Settings.removeCardsFromDeck, set: { Settings.removeCardsFromDeck = $0 }))
            } header: {
                Text(label("trackers_appearance"))
            } footer: {
                Text(label("trackers_appearance_footer"))
            }

            Section {
                Toggle(label("tracker_auto_position"), isOn: autoPosition)
                Toggle(label("tracker_allow_fullscreen"), isOn: state.setting(Settings.canJoinFullscreen, set: { Settings.canJoinFullscreen = $0 }))
                Toggle(label("tracker_hide_in_background"), isOn: state.setting(Settings.hideAllWhenGameInBackground, set: { Settings.hideAllWhenGameInBackground = $0 }))
                Toggle(label("tracker_disable_spectator"), isOn: state.setting(Settings.dontTrackWhileSpectating, set: { Settings.dontTrackWhileSpectating = $0 }))
                Toggle(label("tracker_show_timer"), isOn: state.setting(Settings.showTimer, set: { Settings.showTimer = $0 }))
                Toggle(label("tracker_secret_helper"), isOn: state.setting(Settings.showSecretHelper, set: { Settings.showSecretHelper = $0 }))
                Toggle(label("tracker_rarity_colors"), isOn: state.setting(Settings.showRarityColors, set: { Settings.showRarityColors = $0 }))
                Toggle(label("tracker_hover_card"), isOn: state.setting(Settings.showFloatingCard, set: { Settings.showFloatingCard = $0 }))
                Toggle(label("tracker_experience_counter"), isOn: experienceCounter)
                Toggle(label("tracker_show_flavor_text"), isOn: state.setting(Settings.showFlavorText, set: { Settings.showFlavorText = $0 }))
            } header: {
                Text(label("trackers_overlays"))
            } footer: {
                Text(label("trackers_overlays_footer"))
            }

            Section {
                Toggle(label("tracker_mulligan_toast"), isOn: state.setting(Settings.showMulliganToast, set: { Settings.showMulliganToast = $0 }))
                Toggle(label("tracker_enable_mulligan_guide"), isOn: mulliganGuide)
                Toggle(label("tracker_enable_mulligan_v2"), isOn: mulliganGuideV2)
                Toggle(label("tracker_mulligan_pre_lobby"), isOn: mulliganPreLobby)
                Toggle(label("tracker_mulligan_auto_show"), isOn: state.setting(Settings.autoShowMulliganGuide, set: { Settings.autoShowMulliganGuide = $0 }))
            } header: {
                Text(label("trackers_mulligan"))
            } footer: {
                Text(label("trackers_mulligan_footer"))
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var cardSize: Binding<CardSize> {
        state.setting(Settings.cardSize, set: { Settings.cardSize = $0 })
    }

    private var opacity: Binding<Double> {
        state.setting(Settings.trackerOpacity, set: { Settings.trackerOpacity = $0 })
    }

    private var autoPosition: Binding<Bool> {
        state.setting(Settings.autoPositionTrackers) { enabled in
            Settings.autoPositionTrackers = enabled
            if enabled {
                Settings.windowsLocked = true
            }
        }
    }

    private var experienceCounter: Binding<Bool> {
        state.setting(Settings.showExperienceCounter) { enabled in
            Settings.showExperienceCounter = enabled
            let game = AppDelegate.instance().coreManager.game
            if enabled {
                if let mode = game.currentMode, mode == .hub {
                    game.windowManager.experiencePanel.visible = true
                }
            } else {
                game.windowManager.experiencePanel.visible = false
            }
        }
    }

    private var mulliganGuide: Binding<Bool> {
        state.setting(Settings.enableMulliganGuide) { enabled in
            Settings.enableMulliganGuide = enabled
            let game = AppDelegate.instance().coreManager.game
            if enabled {
                game.hideMulliganGuideStats()
                game.player.mulliganCardStats = nil
            }
            game.updateMulliganGuidePreLobby()
        }
    }

    private var mulliganGuideV2: Binding<Bool> {
        state.setting(Settings.enableMulliganGV2) { enabled in
            Settings.enableMulliganGV2 = enabled
            if #available(macOS 10.15, *) {
                let game = AppDelegate.instance().coreManager.game
                game.stopMulliganLivePolling()
                game.windowManager.rootOverlay?.viewModel.mulliganGuideV2.reset()
            }
        }
    }

    private var mulliganPreLobby: Binding<Bool> {
        state.setting(Settings.showMulliganGuidePreLobby) { enabled in
            Settings.showMulliganGuidePreLobby = enabled
            AppDelegate.instance().coreManager.game.updateMulliganGuidePreLobby()
        }
    }

    private func label(_ key: String) -> String {
        String.localizedString(key, comment: "")
    }

}

private final class TrackersPreferencesState: ObservableObject {
    @Published private(set) var revision = 0

    func setting<Value>(_ value: @autoclosure @escaping () -> Value,
                        set: @escaping (Value) -> Void) -> Binding<Value> {
        Binding(get: { [self] in
            _ = revision
            return value()
        }, set: { [self] newValue in
            set(newValue)
            revision &+= 1
        })
    }
}

// MARK: - Preferences
extension Preferences.PaneIdentifier {
    static let trackers = Self("trackers")
}
