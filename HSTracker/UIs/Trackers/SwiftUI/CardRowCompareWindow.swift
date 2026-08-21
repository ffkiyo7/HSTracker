//
//  CardRowCompareWindow.swift
//  HSTracker
//
//  Side-by-side AppKit CardBar vs SwiftUI CardRowView. Opened when
//  HSTRACKER_CARD_ROW_COMPARE=1 is set (same pattern as LatencyProbe), so it
//  works in Release without a .xib menu item.
//

import AppKit
import Combine
import SwiftUI

final class CardRowCompareWindowController: NSWindowController {
    static let enabled = ProcessInfo.processInfo.environment["HSTRACKER_CARD_ROW_COMPARE"] == "1"

    private static var retained: CardRowCompareWindowController?

    static func openIfRequested() {
        guard enabled else { return }
        if retained == nil {
            retained = CardRowCompareWindowController()
        }
        retained?.showWindow(nil)
        retained?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Card row compare"
        window.backgroundColor = NSColor(white: 0.12, alpha: 1)
        window.center()
        window.contentView = NSHostingView(rootView: CardRowCompareView())
        self.init(window: window)
        window.isReleasedWhenClosed = false
    }
}

private struct CompareFixture: Identifiable {
    let id: String
    let card: Card
    let label: String
}

private final class CardRowCompareModel: ObservableObject {
    @Published var theme: String
    @Published var cardSize: CardSize
    @Published var showRarityColors: Bool
    let fixtures: [CompareFixture]
    private var observers: [NSObjectProtocol] = []

    init() {
        theme = Settings.theme
        cardSize = Settings.cardSize
        showRarityColors = Settings.showRarityColors
        fixtures = Self.buildFixtures()

        let keys = [Settings.theme_token, Settings.card_size, Settings.rarity_colors]
        for key in keys {
            let observer = NotificationCenter.default.addObserver(
                forName: Notification.Name(rawValue: key),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                self.theme = Settings.theme
                self.cardSize = Settings.cardSize
                self.showRarityColors = Settings.showRarityColors
            }
            observers.append(observer)
        }
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    var themeBinding: Binding<String> {
        Binding(
            get: { self.theme },
            set: {
                self.theme = $0
                Settings.theme = $0
            }
        )
    }

    var cardSizeBinding: Binding<CardSize> {
        Binding(
            get: { self.cardSize },
            set: {
                self.cardSize = $0
                Settings.cardSize = $0
            }
        )
    }

    var rarityBinding: Binding<Bool> {
        Binding(
            get: { self.showRarityColors },
            set: {
                self.showRarityColors = $0
                Settings.showRarityColors = $0
            }
        )
    }

    private static func buildFixtures() -> [CompareFixture] {
        [
            fixture("fireball-1", CardIds.Collectible.Mage.Fireball,
                    count: 1, label: "Fireball ×1"),
            fixture("fireball-2", CardIds.Collectible.Mage.Fireball,
                    count: 2, label: "Fireball ×2"),
            fixture("fireball-0", CardIds.Collectible.Mage.Fireball,
                    count: 0, label: "Fireball ×0 (darken)"),
            fixture("fireball-created", CardIds.Collectible.Mage.Fireball,
                    count: 1, created: true, label: "Fireball created ×1"),
            fixture("fireball-created-2", CardIds.Collectible.Mage.Fireball,
                    count: 2, created: true, label: "Fireball created ×2"),
            fixture("ysera-1", CardIds.Collectible.Neutral.Ysera,
                    count: 1, label: "Ysera ×1 (legendary)"),
            fixture("ysera-2", CardIds.Collectible.Neutral.Ysera,
                    count: 2, label: "Ysera ×2"),
            fixture("ysera-jousted", CardIds.Collectible.Neutral.Ysera,
                    count: 1, jousted: true, label: "Ysera jousted"),
            fixture("spellbreaker", CardIds.Collectible.Neutral.Spellbreaker,
                    count: 1, label: "Spellbreaker (rare)"),
            fixture("auctioneer", CardIds.Collectible.Neutral.GadgetzanAuctioneer,
                    count: 2, label: "Auctioneer ×2 (epic)")
        ]
    }

    private static func fixture(_ id: String,
                                _ cardId: String,
                                count: Int,
                                created: Bool = false,
                                jousted: Bool = false,
                                label: String) -> CompareFixture {
        let card = Cards.by(cardId: cardId) ?? Card()
        if card.id.isEmpty {
            card.id = cardId
            card.name = label
            card.cost = 4
        }
        card.count = count
        card.isCreated = created
        card.jousted = jousted
        return CompareFixture(id: id, card: card, label: label)
    }
}

private struct CardRowCompareView: View {
    @StateObject private var model = CardRowCompareModel()

    var body: some View {
        let rowSize = CardRowView.pixelSize(cardSize: model.cardSize)
        VStack(alignment: .leading, spacing: 12) {
            controls
            HStack {
                columnHeader("AppKit CardBar", width: rowSize.width)
                columnHeader("SwiftUI CardRowView", width: rowSize.width)
                Spacer()
            }
            .padding(.horizontal, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.fixtures) { fixture in
                        HStack(alignment: .center, spacing: 16) {
                            CardBarPreview(card: fixture.card, size: rowSize)
                                .id("\(model.theme)-\(fixture.id)")
                                .frame(width: rowSize.width, height: rowSize.height)
                            CardRowView(card: fixture.card,
                                        theme: model.theme,
                                        cardSize: model.cardSize,
                                        showRarityColors: model.showRarityColors)
                                .frame(width: rowSize.width, height: rowSize.height)
                            Text(fixture.label)
                                .foregroundColor(.white)
                                .font(.system(size: 12))
                                .frame(minWidth: 180, alignment: .leading)
                        }
                    }
                }
                .padding(8)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.12))
    }

    private var controls: some View {
        HStack(spacing: 16) {
            Picker("Theme", selection: model.themeBinding) {
                Text("classic").tag("classic")
                Text("frost").tag("frost")
                Text("dark").tag("dark")
                Text("minimal").tag("minimal")
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 360)

            Picker("Size", selection: model.cardSizeBinding) {
                Text("tiny").tag(CardSize.tiny)
                Text("small").tag(CardSize.small)
                Text("medium").tag(CardSize.medium)
                Text("big").tag(CardSize.big)
                Text("huge").tag(CardSize.huge)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 420)

            Toggle("Rarity colors", isOn: model.rarityBinding)
                .toggleStyle(.checkbox)
                .foregroundColor(.white)
            Spacer()
        }
    }

    private func columnHeader(_ title: String, width: CGFloat) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(Color.white.opacity(0.7))
            .frame(width: width, alignment: .leading)
    }
}

private struct CardBarPreview: NSViewRepresentable {
    let card: Card
    let size: CGSize

    func makeNSView(context: Context) -> CardBar {
        let bar = CardBar.factory()
        bar.playerType = .player
        bar.card = card.copy()
        bar.setFrameSize(NSSize(width: size.width, height: size.height))
        return bar
    }

    func updateNSView(_ bar: CardBar, context: Context) {
        bar.setFrameSize(NSSize(width: size.width, height: size.height))
        // CardBar.draw() returns without painting when the new card compares
        // equal to oldCard, so clear first to force a real redraw.
        bar.card = nil
        bar.card = card.copy()
        bar.needsDisplay = true
    }
}
