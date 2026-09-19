//
//  CardRowView.swift
//  HSTracker
//
//  The vector card row of the D2 redesign (Phase 2 / V1). No theme PNG is
//  read any more: cost cell, name, art fade and count box are all drawn, so
//  the row scales to any height without stretching a 217x34 bitmap.
//
//  Perf P2 split the file in two: `CardRowContentView` is that drawing, byte
//  for byte, and `CardRowView` is the wrapper that owns the tile, reads the
//  environment and hands the render server one flat bitmap per row instead of
//  the content's layer tree (see TrackerRowRaster.swift).
//

import AppKit
import SwiftUI

struct CardRowView: View {
    let card: Card
    var playerType: PlayerType = .player
    var showRarityColors: Bool = Settings.showRarityColors
    var rowHeight: CGFloat = TrackerMetrics.rowHeight
    var barWidth: CGFloat = TrackerMetrics.panelWidth
    var highlightColor: HighlightColor = .none
    /// The art's shade is the panel base, so it has to carry the panel's own
    /// alpha — otherwise a translucent panel would show a fully opaque strip
    /// under every card name. V2b read it straight from `Settings` here; Perf
    /// P2 feeds it from `TrackerCardListViewModel` instead, so a change to
    /// `tracker_opacity` alone publishes and the rows really do repaint. The
    /// default is only for previews and tests.
    var baseOpacity: CGFloat = TrackerDiagnostics.panelOpacity(setting: Settings.trackerOpacity)
    /// Perf P2 diagnostics, stored rather than read inside `body` so that a
    /// flipped switch yields a row value SwiftUI cannot skip, and a raster key
    /// that cannot collide with the other setting's bitmap.
    var flattensToBitmap: Bool = TrackerDiagnostics.flattensRows
    var drawsArt: Bool = TrackerDiagnostics.drawsArt
    var drawsTextShadow: Bool = TrackerDiagnostics.drawsTextShadow

    @SwiftUI.State private var tile: NSImage?
    @Environment(\.trackerHandSection) private var isHandSection
    @Environment(\.displayScale) private var displayScale

    var content: CardRowContentView {
        CardRowContentView(card: card,
                           playerType: playerType,
                           showRarityColors: showRarityColors,
                           rowHeight: rowHeight,
                           barWidth: barWidth,
                           highlightColor: highlightColor,
                           baseOpacity: baseOpacity,
                           isHandSection: isHandSection,
                           drawsArt: drawsArt,
                           drawsTextShadow: drawsTextShadow,
                           tile: tile)
    }

    /// The whole row as one bitmap, drawn once per distinct appearance. `nil`
    /// means the renderer could not produce one, and the vector row is drawn.
    private var raster: NSImage? {
        let content = self.content
        return TrackerRowRaster.image(for: content.rasterKey(scale: rasterScale)) { content }
    }

    /// `displayScale` is 0 outside a window (previews, the metric tests); the
    /// main screen's factor is the closest thing to what the panel will land on.
    private var rasterScale: CGFloat {
        displayScale >= 1 ? displayScale : (NSScreen.main?.backingScaleFactor ?? 2)
    }

    var body: some View {
        Group {
            if flattensToBitmap, let raster {
                Image(nsImage: raster)
                    .resizable()
                    .frame(width: barWidth, height: rowHeight)
            } else {
                content
            }
        }
        .onAppear(perform: loadTile)
        .onChange(of: card.id) { _, _ in
            tile = nil
            loadTile()
        }
        .transaction { $0.animation = nil }
    }

    private func loadTile() {
        if let cached = ImageUtils.cachedTile(cardId: card.id) {
            tile = cached
            return
        }
        let cardId = card.id
        ImageUtils.tile(for: cardId) { image in
            DispatchQueue.main.async {
                if cardId == card.id {
                    tile = image
                }
            }
        }
    }
}

/// The drawing itself. Pure — no `@State`, no environment — because Perf P2
/// hands it to `ImageRenderer`, which starts from an empty environment and
/// never runs `onAppear`.
struct CardRowContentView: View {
    let card: Card
    var playerType: PlayerType = .player
    var showRarityColors: Bool = Settings.showRarityColors
    var rowHeight: CGFloat = TrackerMetrics.rowHeight
    var barWidth: CGFloat = TrackerMetrics.panelWidth
    var highlightColor: HighlightColor = .none
    var baseOpacity: CGFloat = TrackerDiagnostics.panelOpacity(setting: Settings.trackerOpacity)
    var isHandSection: Bool = false
    var drawsArt: Bool = TrackerDiagnostics.drawsArt
    var drawsTextShadow: Bool = TrackerDiagnostics.drawsTextShadow
    var tile: NSImage?

    /// One reference pixel of the 171 x 21 sheet, in points.
    private var u: CGFloat { rowHeight / TrackerMetrics.rowHeight }
    private var costWidth: CGFloat { TrackerBarStyle.costWidth * u }
    /// D3-b: from the cost cell's trailing edge to the end of the bar.
    private var artWidth: CGFloat { max(barWidth - costWidth, 0) }
    private var boxWidth: CGFloat { TrackerBarStyle.boxWidth * u }

    private var absCount: Int { abs(card.count) }
    private var showsCountBox: Bool { absCount > 1 || effectiveRarity == .legendary }
    private var isDimmed: Bool {
        (card.count <= 0 || card.jousted) && playerType != .cardList && playerType != .editDeck
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            art
            costCell
            name
            if showsCountBox {
                countBox
            }
            if card.isCreated {
                createdMark
            }
        }
        .frame(width: barWidth, height: rowHeight, alignment: .topLeading)
        .clipped()
        .overlay(alignment: .top) {
            Rectangle()
                .fill(TrackerBarStyle.rowLine)
                .frame(height: max(TrackerBarStyle.hairline * u, 0.5))
        }
        .overlay { highlightOverlay }
        .transaction { $0.animation = nil }
    }

    // MARK: - layers

    /// D3-b: the art fills everything right of the cost cell, under a shade that
    /// is solid panel base for the leading tenth and gone by three quarters, so
    /// the name still sits on flat colour and the back third of the art is lit.
    /// `.fill` is cover: 149 : 21 is flatter than the 256 x 59 tile, so the tile
    /// is scaled to the width and cropped vertically, never blown up.
    @ViewBuilder
    private var art: some View {
        ZStack(alignment: .topLeading) {
            if let tile, drawsArt {
                Image(nsImage: tile)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: artWidth, height: rowHeight)
                    .clipped()
                    .opacity(isDimmed ? TrackerBarStyle.dimContent : 1)
            }
            LinearGradient(
                stops: [
                    .init(color: shade, location: 0),
                    .init(color: shade, location: TrackerBarStyle.artSolidFraction),
                    .init(color: shade.opacity(0), location: TrackerBarStyle.artClearFraction),
                    .init(color: shade.opacity(0), location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: artWidth, height: rowHeight)
        }
        .frame(width: barWidth, height: rowHeight, alignment: .trailing)
    }

    /// The panel base at the panel's own alpha (see `baseOpacity`).
    private var shade: Color {
        TrackerBarStyle.base.opacity(baseOpacity)
    }

    /// The whole cell carries the rarity colour (D2 dropped the round gem).
    private var costCell: some View {
        ZStack {
            TrackerBarStyle.cost(showRarityColors ? effectiveRarity : .common)
            if showsCost {
                Text("\(card.cost)")
                    .font(.custom(TrackerBarStyle.digitFontName,
                                  size: TrackerBarStyle.costFontSize * u))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(drawsTextShadow ? 0.7 : 0), radius: u, y: u)
            }
        }
        .frame(width: costWidth, height: rowHeight)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.black.opacity(0.35))
                .frame(width: max(TrackerBarStyle.hairline * u, 0.5))
        }
        .opacity(isDimmed ? TrackerBarStyle.dimCost : 1)
    }

    private var name: some View {
        Text(cardName)
            .font(.custom(TrackerTextFont.name, size: TrackerBarStyle.nameFontSize * u))
            .foregroundColor(nameColor)
            .lineLimit(1)
            .truncationMode(.tail)
            .shadow(color: .black.opacity(drawsTextShadow ? 0.95 : 0),
                    radius: TrackerBarStyle.nameShadowNear * u, y: u)
            .shadow(color: .black.opacity(drawsTextShadow ? 0.8 : 0),
                    radius: TrackerBarStyle.nameShadowFar * u)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.leading, costWidth + TrackerBarStyle.namePadLeading * u)
            .padding(.trailing, (showsCountBox ? TrackerBarStyle.namePadBoxed
                                               : TrackerBarStyle.namePadTrailing) * u)
            .frame(width: barWidth, height: rowHeight)
            .opacity(isDimmed ? TrackerBarStyle.dimContent : 1)
    }

    /// Copies > 1 print the number; a single legendary prints a star, as on the
    /// theme path where `icon_legendary.png` stood in for a count.
    private var countBox: some View {
        ZStack {
            TrackerBarStyle.countBox
            if absCount > 1 {
                Text("\(absCount)")
                    .font(.custom(TrackerBarStyle.digitFontName,
                                  size: TrackerBarStyle.countFontSize * u))
                    .foregroundColor(.white)
            } else {
                TrackerStar()
                    .fill(TrackerBarStyle.star)
                    .frame(width: TrackerBarStyle.starSize * u,
                           height: TrackerBarStyle.starSize * u)
            }
        }
        .frame(width: boxWidth, height: rowHeight)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(TrackerBarStyle.line)
                .frame(width: max(TrackerBarStyle.hairline * u, 0.5))
        }
        .frame(width: barWidth, height: rowHeight, alignment: .trailing)
        .opacity(isDimmed ? TrackerBarStyle.dimContent : 1)
    }

    /// `icon_created.png`'s replacement: a gold notch in the cost cell's
    /// leading corner. It sits outside the name box, so a gift never costs the
    /// card name any width.
    private var createdMark: some View {
        Path { path in
            let side = TrackerBarStyle.createdMark * u
            path.move(to: .zero)
            path.addLine(to: CGPoint(x: side, y: 0))
            path.addLine(to: CGPoint(x: 0, y: side))
            path.closeSubpath()
        }
        .fill(TrackerBarStyle.gold)
        .frame(width: barWidth, height: rowHeight, alignment: .topLeading)
    }

    /// Related-card highlight (teal / orange / green). The theme path laid a
    /// full-bar glow PNG over the frame; a tinted inset border reads the same
    /// without hiding the rarity colour or the art.
    @ViewBuilder
    private var highlightOverlay: some View {
        if let color = TrackerBarStyle.highlight(highlightColor) {
            Rectangle()
                .fill(color.opacity(0.14))
                .overlay {
                    Rectangle()
                        .strokeBorder(color.opacity(0.85), lineWidth: max(1.5 * u, 1))
                }
                .allowsHitTesting(false)
        }
    }

    // MARK: - card facts

    private var effectiveRarity: Rarity {
        card.rarity == .invalid && card.mechanics.contains("ELITE")
            ? .legendary
            : card.rarity
    }

    private var showsCost: Bool {
        if Cards.isHero(cardId: card.id) && !Cards.isPlayableHero(cardId: card.id) {
            return false
        }
        if card.cost < 0 {
            return false
        }
        if card.type == .battleground_spell {
            return false
        }
        return true
    }

    private var cardName: String {
        if let suffix = card.extraInfo?.cardNameSuffix {
            return "\(card.name) \(suffix)"
        }
        return card.name
    }

    /// `Card.textColor()` still owns the draw / in-hand / discarded precedence
    /// and the four settings that gate them; only its plain-white default is
    /// swapped for the D2 parchment.
    ///
    /// The hand section is the exception: D2 took the in-hand green off it (it
    /// only says something in the deck section) and the sheet paints those names
    /// flat — `.inhand .name { color: var(--hand) }`, which is this very colour.
    /// The just-drawn orange outranks the green in `Card.textColor()` and is kept
    /// here too: every card in that section is in hand, so dropping the green
    /// leaves orange as the only signal the section can carry (review 09-17).
    /// `Card.textColor()` itself is untouched; the old bar path shares it.
    private var nameColor: Color {
        if playerType == .cardList || playerType == .editDeck {
            return TrackerBarStyle.text
        }
        if isHandSection && !(card.highlightDraw && Settings.highlightLastDrawn) {
            return TrackerBarStyle.text
        }
        let color = card.textColor()
        return color.isEqual(NSColor.white) ? TrackerBarStyle.text : Color(nsColor: color)
    }

    // MARK: - Perf P2

    /// Everything above that can change the picture, so a cached bitmap is only
    /// reused for a row that really looks the same.
    func rasterKey(scale: CGFloat) -> CardRowRasterKey {
        CardRowRasterKey(cardId: card.id,
                         name: cardName,
                         cost: card.cost,
                         showsCost: showsCost,
                         count: card.count,
                         rarity: effectiveRarity,
                         showRarityColors: showRarityColors,
                         dimmed: isDimmed,
                         created: card.isCreated,
                         countBox: showsCountBox,
                         nameColor: Self.packed(nameColor),
                         highlight: highlightColor.rasterToken,
                         hasTile: drawsArt && tile != nil,
                         rowHeight: rowHeight,
                         barWidth: barWidth,
                         baseOpacity: baseOpacity,
                         scale: scale,
                         drawsArt: drawsArt,
                         drawsTextShadow: drawsTextShadow)
    }

    /// The resolved colour rather than the settings behind it: `textColor()`
    /// reads four flags plus `Settings.playerInHandColor`, and a key built from
    /// those would go stale the moment one more input is added.
    private static func packed(_ color: Color) -> UInt32 {
        guard let srgb = NSColor(color).usingColorSpace(.sRGB) else {
            return 0
        }
        let channel = { (value: CGFloat) in UInt32((max(0, min(1, value)) * 255).rounded()) }
        return channel(srgb.redComponent) << 24
            | channel(srgb.greenComponent) << 16
            | channel(srgb.blueComponent) << 8
            | channel(srgb.alphaComponent)
    }
}

private extension HighlightColor {
    var rasterToken: Int {
        switch self {
        case .none: return 0
        case .teal: return 1
        case .orange: return 2
        case .green: return 3
        }
    }
}
