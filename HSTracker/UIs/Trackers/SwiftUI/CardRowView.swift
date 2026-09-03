//
//  CardRowView.swift
//  HSTracker
//
//  SwiftUI stand-in for CardBar + the four theme subclasses, covering the
//  constructed-play path only. Battlegrounds tags, editDeck/hero, highlight
//  flash and mulligan winrate are intentionally not drawn.
//

import AppKit
import SwiftUI

struct CardRowView: View {
    let card: Card
    var playerType: PlayerType = .player
    var theme: String = Settings.theme
    var cardSize: CardSize = Settings.cardSize
    var showRarityColors: Bool = Settings.showRarityColors
    var rowHeight: CGFloat?
    var backgroundImage: NSImage?
    var highlightColor: HighlightColor = .none

    @SwiftUI.State private var tile: NSImage?

    var body: some View {
        let layout = ThemeBarLayout.forTheme(theme)
        let size = Self.pixelSize(cardSize: cardSize, rowHeight: rowHeight)
        let ratios = Self.ratios(cardSize: cardSize, boundsHeight: size.height)

        ZStack(alignment: .topLeading) {
            if ThemeImageCache.hasRequired(theme: layout.dir) {
                layers(layout: layout, size: size, rw: ratios.width, rh: ratios.height)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .onAppear {
            ThemeImageCache.prepare(theme: layout.dir)
            loadTile()
        }
        .onChange(of: card.id) { _, _ in
            tile = nil
            loadTile()
        }
        .onChange(of: theme) { _, _ in
            ThemeImageCache.prepare(theme: ThemeBarLayout.forTheme(theme).dir)
        }
        .transaction { $0.animation = nil }
    }

    static func pixelSize(cardSize: CardSize, rowHeight: CGFloat? = nil) -> CGSize {
        let width: CGFloat
        let height: CGFloat
        switch cardSize {
        case .tiny:
            width = CGFloat(kTinyFrameWidth)
            height = CGFloat(kTinyRowHeight)
        case .small:
            width = CGFloat(kSmallFrameWidth)
            height = CGFloat(kSmallRowHeight)
        case .medium:
            width = CGFloat(kMediumFrameWidth)
            height = CGFloat(kMediumRowHeight)
        case .huge:
            width = CGFloat(kHighRowFrameWidth)
            height = CGFloat(kHighRowHeight)
        case .big:
            width = CGFloat(kFrameWidth)
            height = CGFloat(kRowHeight)
        }
        if let rowHeight {
            return CGSize(width: width, height: rowHeight)
        }
        return CGSize(width: width, height: height)
    }

    static func ratios(cardSize: CardSize, boundsHeight: CGFloat) -> (width: CGFloat, height: CGFloat) {
        let ratioWidth: CGFloat
        switch cardSize {
        case .tiny: ratioWidth = CGFloat(kRowHeight / kTinyRowHeight)
        case .small: ratioWidth = CGFloat(kRowHeight / kSmallRowHeight)
        case .medium: ratioWidth = CGFloat(kRowHeight / kMediumRowHeight)
        case .huge: ratioWidth = CGFloat(kRowHeight / kHighRowHeight)
        case .big: ratioWidth = 1.0
        }

        let baseHeight: CGFloat
        switch cardSize {
        case .tiny: baseHeight = CGFloat(kTinyRowHeight)
        case .small: baseHeight = CGFloat(kSmallRowHeight)
        case .medium: baseHeight = CGFloat(kMediumRowHeight)
        case .huge: baseHeight = CGFloat(kHighRowFrameWidth)
        case .big: baseHeight = CGFloat(kRowHeight)
        }

        let ratioHeight: CGFloat
        if baseHeight > boundsHeight && boundsHeight > 0 {
            ratioHeight = CGFloat(kRowHeight) / boundsHeight
        } else {
            ratioHeight = ratioWidth
        }
        return (ratioWidth, ratioHeight)
    }

    static func ratio(_ rect: NSRect, rw: CGFloat, rh: CGFloat) -> NSRect {
        NSRect(x: round(rect.origin.x / rw),
               y: round(rect.origin.y / rh),
               width: round(rect.size.width / rw),
               height: round(rect.size.height / rh))
    }

    @ViewBuilder
    private func layers(layout: ThemeBarLayout,
                        size: CGSize,
                        rw: CGFloat,
                        rh: CGFloat) -> some View {
        let rarity = effectiveRarity
        let absCount = abs(card.count)
        let showCountBox = absCount > 1 || rarity == .legendary
        // CardBar.addCardImage: `offset && count>1 || legendary` (no parens).
        let offsetImage = (layout.offsetImageByCountBox && absCount > 1)
            || rarity == .legendary
        let offsetFade = layout.offsetFadeByCountBox && (absCount > 1 || rarity == .legendary)

        if let backgroundImage {
            imageLayer(backgroundImage,
                       rect: layout.imageRect,
                       size: size, rw: rw, rh: rh)
        }

        cardArt(layout: layout, offset: offsetImage, size: size, rw: rw, rh: rh)

        themeLayer(file: "fade.png",
                   rect: offsetFade
                        ? layout.fadeRect.offsetBy(dx: layout.fadeOffset, dy: 0)
                        : layout.fadeRect,
                   size: size, rw: rw, rh: rh)

        if showCountBox && layout.usesCountBox {
            themeLayer(file: countBoxFile(rarity: rarity, layout: layout),
                       rect: layout.boxRect,
                       size: size, rw: rw, rh: rh)
        }
        if absCount > 1 {
            strokedText("\(absCount)",
                        fontName: "ChunkFive",
                        fontSize: layout.countFontSize / rh,
                        color: countTextColor(layout: layout),
                        stroke: -2.0,
                        centered: true,
                        rect: layout.countTextRect,
                        size: size, rw: rw, rh: rh)
        }

        if card.isCreated {
            let createdRect = (absCount > 1 || rarity == .legendary)
                ? layout.boxRect.offsetBy(dx: layout.createdIconOffset, dy: 0)
                : layout.boxRect
            themeLayer(file: "icon_created.png",
                       rect: createdRect,
                       size: size, rw: rw, rh: rh)
        }
        if absCount <= 1 && rarity == .legendary {
            themeLayer(file: "icon_legendary.png",
                       rect: layout.legendaryIconRect,
                       size: size, rw: rw, rh: rh)
        }

        themeLayer(file: frameFile(rarity: rarity, layout: layout),
                   rect: layout.frameRect,
                   size: size, rw: rw, rh: rh)

        if showsGemAndCost {
            themeLayer(file: gemFile(rarity: rarity, layout: layout),
                       rect: layout.gemRect,
                       size: size, rw: rw, rh: rh)
            strokedText("\(card.cost)",
                        fontName: "ChunkFive",
                        fontSize: layout.costFontSize / rh,
                        color: costColor,
                        stroke: -1.0,
                        centered: true,
                        rect: layout.costTextRect,
                        size: size, rw: rw, rh: rh)
        }

        if let highlightFile = highlightFile {
            themeLayer(file: highlightFile,
                       rect: layout.frameRect,
                       size: size, rw: rw, rh: rh)
        }

        let nameRect = cardNameRect(layout: layout, rarity: rarity, absCount: absCount)
        strokedText(cardName,
                    fontName: layout.textFontName,
                    fontSize: layout.nameFontSize / rh,
                    color: nameColor,
                    stroke: -2.0,
                    centered: false,
                    rect: nameRect,
                    size: size, rw: rw, rh: rh)

        if (card.count <= 0 || card.jousted)
            && playerType != .cardList && playerType != .editDeck {
            themeLayer(file: "dark.png",
                       rect: layout.frameRect,
                       size: size, rw: rw, rh: rh)
        }
    }

    private var effectiveRarity: Rarity {
        card.rarity == .invalid && card.mechanics.contains("ELITE")
            ? .legendary
            : card.rarity
    }

    private var highlightFile: String? {
        switch highlightColor {
        case .green: return "highlight_green.png"
        case .teal: return "highlight_teal.png"
        case .orange: return "highlight_orange.png"
        default: return nil
        }
    }

    private var showsGemAndCost: Bool {
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

    private var nameColor: NSColor {
        if playerType == .cardList || playerType == .editDeck {
            return .white
        }
        return card.textColor()
    }

    private var costColor: NSColor {
        if playerType == .cardList || playerType == .editDeck {
            return .white
        }
        return card.textColor()
    }

    private func countTextColor(layout: ThemeBarLayout) -> NSColor {
        guard layout.rarityTintedCountText else {
            return NSColor(red: 0.9221, green: 0.7215, blue: 0.2226, alpha: 1.0)
        }
        // MinimalBar.countTextColor switches on the raw rarity, not the one
        // that folds ELITE into legendary.
        switch card.rarity {
        case .rare:
            return NSColor(red: 0.1922, green: 0.5255, blue: 0.8706, alpha: 1.0)
        case .epic:
            return NSColor(red: 0.6784, green: 0.4431, blue: 0.9686, alpha: 1.0)
        case .legendary:
            return NSColor(red: 1.0, green: 0.6039, blue: 0.0627, alpha: 1.0)
        default:
            return .white
        }
    }

    private func frameFile(rarity: Rarity, layout: ThemeBarLayout) -> String {
        guard showRarityColors && ThemeImageCache.hasOptionalFrames(theme: layout.dir) else {
            return "frame.png"
        }
        switch rarity {
        case .rare: return "frame_rare.png"
        case .epic: return "frame_epic.png"
        case .legendary: return "frame_legendary.png"
        default: return "frame_common.png"
        }
    }

    private func gemFile(rarity: Rarity, layout: ThemeBarLayout) -> String {
        guard showRarityColors && ThemeImageCache.hasOptionalGems(theme: layout.dir) else {
            return "gem.png"
        }
        switch rarity {
        case .rare: return "gem_rare.png"
        case .epic: return "gem_epic.png"
        case .legendary: return "gem_legendary.png"
        default: return "gem_common.png"
        }
    }

    private func countBoxFile(rarity: Rarity, layout: ThemeBarLayout) -> String {
        guard showRarityColors && ThemeImageCache.hasOptionalCountBoxes(theme: layout.dir) else {
            return "countbox.png"
        }
        switch rarity {
        case .rare: return "countbox_rare.png"
        case .epic: return "countbox_epic.png"
        case .legendary: return "countbox_legendary.png"
        default: return "countbox_common.png"
        }
    }

    private func cardNameRect(layout: ThemeBarLayout, rarity: Rarity, absCount: Int) -> NSRect {
        if layout.nameAlwaysReserveCountBox {
            return NSRect(x: layout.nameX,
                          y: layout.nameY,
                          width: layout.frameRect.width - layout.boxRect.width - layout.nameX,
                          height: layout.nameHeight)
        }
        var width = layout.frameRect.width - layout.nameX
        if absCount > 0 || rarity == .legendary {
            width -= layout.boxRect.width
        }
        if card.isCreated {
            width -= abs(layout.createdIconOffset)
        }
        return NSRect(x: layout.nameX, y: layout.nameY, width: width, height: layout.nameHeight)
    }

    @ViewBuilder
    private func cardArt(layout: ThemeBarLayout,
                         offset: Bool,
                         size: CGSize,
                         rw: CGFloat,
                         rh: CGFloat) -> some View {
        if layout.usesBlurredFullBleedArt {
            if let small = ThemeImageCache.smallCard(id: card.id) {
                imageLayer(small, rect: layout.frameRect, size: size, rw: rw, rh: rh)
                    .blur(radius: 1.5)
            }
        } else if let tile {
            let rect = offset
                ? layout.imageRect.offsetBy(dx: layout.imageOffset, dy: 0)
                : layout.imageRect
            imageLayer(tile, rect: rect, size: size, rw: rw, rh: rh)
        }
    }

    @ViewBuilder
    private func themeLayer(file: String,
                            rect: NSRect,
                            size: CGSize,
                            rw: CGFloat,
                            rh: CGFloat) -> some View {
        let layout = ThemeBarLayout.forTheme(theme)
        if let image = ThemeImageCache.image(theme: layout.dir, file: file) {
            imageLayer(image, rect: rect, size: size, rw: rw, rh: rh)
        }
    }

    private func imageLayer(_ image: NSImage,
                            rect: NSRect,
                            size: CGSize,
                            rw: CGFloat,
                            rh: CGFloat) -> some View {
        let r = Self.ratio(rect, rw: rw, rh: rh)
        return Image(nsImage: image)
            .renderingMode(.original)
            .resizable()
            .frame(width: r.width, height: r.height)
            .offset(x: r.origin.x, y: size.height - r.origin.y - r.height)
    }

    private func strokedText(_ text: String,
                             fontName: String,
                             fontSize: CGFloat,
                             color: NSColor,
                             stroke: CGFloat,
                             centered: Bool,
                             rect: NSRect,
                             size: CGSize,
                             rw: CGFloat,
                             rh: CGFloat) -> some View {
        let r = Self.ratio(rect, rw: rw, rh: rh)
        return CardRowStrokedText(text: text,
                                  fontName: fontName,
                                  fontSize: fontSize,
                                  color: color,
                                  stroke: stroke,
                                  centered: centered)
            .frame(width: r.width, height: r.height)
            .offset(x: r.origin.x, y: size.height - r.origin.y - r.height)
            .allowsHitTesting(false)
    }

    private func loadTile() {
        if ThemeBarLayout.forTheme(theme).usesBlurredFullBleedArt {
            return
        }
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

/// The card-name font the current theme and language resolve to, for views
/// outside this file that must match the card rows (the tracker header).
enum TrackerTextFont {
    static var name: String {
        ThemeBarLayout.forTheme(Settings.theme).textFontName
    }
}

private struct ThemeBarLayout {
    let dir: String
    let frameRect = NSRect(x: 0, y: 0, width: 217, height: 34)
    let gemRect = NSRect(x: 0, y: 0, width: 34, height: 34)
    let boxRect = NSRect(x: 183, y: 0, width: 34, height: 34)
    let fadeRect: NSRect
    let imageRect: NSRect
    let offsetImageByCountBox: Bool
    let offsetFadeByCountBox: Bool
    let imageOffset: CGFloat
    let fadeOffset: CGFloat
    let createdIconOffset: CGFloat
    let countTextRect: NSRect
    let costTextRect: NSRect
    let legendaryIconRect: NSRect
    let nameX: CGFloat
    let nameY: CGFloat
    let nameHeight: CGFloat
    let nameAlwaysReserveCountBox: Bool
    let usesCountBox: Bool
    let usesBlurredFullBleedArt: Bool
    let rarityTintedCountText: Bool
    let countFontSize: CGFloat
    let costFontSize: CGFloat
    let nameFontSize: CGFloat

    var textFontName: String {
        if Settings.isSimplifiedChinese {
            return "AR LisuGB Medium"
        } else if Settings.isAsianLanguage {
            return "NanumGothic"
        } else if Settings.isCyrillicLanguage {
            return dir == "classic" ? "Benguiat Rus" : "BenguiatBold"
        } else if dir == "classic" {
            return "Belwe Bd BT"
        } else {
            return "ChunkFive"
        }
    }

    static func forTheme(_ theme: String) -> ThemeBarLayout {
        switch theme {
        case "frost": return frost
        case "dark": return dark
        case "minimal": return minimal
        default: return classic
        }
    }

    static let classic = ThemeBarLayout(
        dir: "classic",
        fadeRect: NSRect(x: 28, y: 0, width: 189, height: 34),
        imageRect: NSRect(x: 108, y: 4, width: 108, height: 27),
        offsetImageByCountBox: true,
        offsetFadeByCountBox: true,
        imageOffset: -19,
        fadeOffset: -19,
        createdIconOffset: -19,
        countTextRect: NSRect(x: 196, y: 9, width: 14, height: 34),
        costTextRect: NSRect(x: 1, y: 9, width: 34, height: 34),
        legendaryIconRect: NSRect(x: 183, y: 0, width: 34, height: 34),
        nameX: 38,
        nameY: 10,
        nameHeight: 30,
        nameAlwaysReserveCountBox: true,
        usesCountBox: true,
        usesBlurredFullBleedArt: false,
        rarityTintedCountText: false,
        countFontSize: 17,
        costFontSize: 20,
        nameFontSize: 15
    )

    static let dark = ThemeBarLayout(
        dir: "dark",
        fadeRect: NSRect(x: 34, y: 0, width: 183, height: 34),
        imageRect: NSRect(x: 83, y: 0, width: 134, height: 34),
        offsetImageByCountBox: true,
        offsetFadeByCountBox: true,
        imageOffset: -23,
        fadeOffset: -23,
        createdIconOffset: -23,
        countTextRect: NSRect(x: 198, y: 9, width: 14, height: 34),
        costTextRect: NSRect(x: 0, y: 9, width: 34, height: 34),
        legendaryIconRect: NSRect(x: 183, y: 0, width: 34, height: 34),
        nameX: 38,
        nameY: 10,
        nameHeight: 30,
        nameAlwaysReserveCountBox: false,
        usesCountBox: true,
        usesBlurredFullBleedArt: false,
        rarityTintedCountText: false,
        countFontSize: 17,
        costFontSize: 20,
        nameFontSize: 15
    )

    static let frost = ThemeBarLayout(
        dir: "frost",
        fadeRect: NSRect(x: 0, y: 0, width: 217, height: 34),
        imageRect: NSRect(x: 82, y: 0, width: 134, height: 34),
        offsetImageByCountBox: false,
        offsetFadeByCountBox: false,
        imageOffset: -23,
        fadeOffset: -23,
        createdIconOffset: -23,
        countTextRect: NSRect(x: 197, y: 9, width: 14, height: 34),
        costTextRect: NSRect(x: 0, y: 9, width: 34, height: 34),
        legendaryIconRect: NSRect(x: 182, y: 0, width: 34, height: 34),
        nameX: 38,
        nameY: 10,
        nameHeight: 30,
        nameAlwaysReserveCountBox: false,
        usesCountBox: true,
        usesBlurredFullBleedArt: false,
        rarityTintedCountText: false,
        countFontSize: 17,
        costFontSize: 20,
        nameFontSize: 15
    )

    static let minimal = ThemeBarLayout(
        dir: "minimal",
        fadeRect: NSRect(x: 0, y: 0, width: 217, height: 34),
        imageRect: NSRect(x: 83, y: 0, width: 134, height: 34),
        offsetImageByCountBox: false,
        offsetFadeByCountBox: false,
        imageOffset: -23,
        fadeOffset: -23,
        createdIconOffset: -15,
        countTextRect: NSRect(x: 196, y: 9, width: 14, height: 34),
        costTextRect: NSRect(x: 0, y: 9, width: 34, height: 34),
        legendaryIconRect: NSRect(x: 183, y: 0, width: 34, height: 34),
        nameX: 38,
        nameY: 10,
        nameHeight: 30,
        nameAlwaysReserveCountBox: false,
        usesCountBox: false,
        usesBlurredFullBleedArt: true,
        rarityTintedCountText: true,
        countFontSize: 17,
        costFontSize: 20,
        nameFontSize: 15
    )
}

/// Same NSString stroke path as CardBar.add(text:), but the rect itself
/// shrinks the text via NSStringDrawingContext.minimumScaleFactor instead of
/// CardBar.fitFontForSize's binary-search layout loop.
private struct CardRowStrokedText: NSViewRepresentable {
    let text: String
    let fontName: String
    let fontSize: CGFloat
    let color: NSColor
    let stroke: CGFloat
    let centered: Bool

    func makeNSView(context: Context) -> Inner {
        let view = Inner()
        view.apply(self)
        return view
    }

    func updateNSView(_ view: Inner, context: Context) {
        view.apply(self)
        view.needsDisplay = true
    }

    final class Inner: NSView {
        var text = ""
        var fontName = ""
        var fontSize: CGFloat = 15
        var color = NSColor.white
        var stroke: CGFloat = -2
        var centered = false

        override var isFlipped: Bool { false }
        override var isOpaque: Bool { false }

        func apply(_ spec: CardRowStrokedText) {
            text = spec.text
            fontName = spec.fontName
            fontSize = spec.fontSize
            color = spec.color
            stroke = spec.stroke
            centered = spec.centered
        }

        override func draw(_ dirtyRect: NSRect) {
            guard let font = NSFont(name: fontName, size: fontSize) else { return }
            var attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color,
                .strokeWidth: stroke,
                .strokeColor: NSColor.black
            ]
            if centered {
                let paragraph = NSMutableParagraphStyle()
                paragraph.alignment = .center
                attrs[.paragraphStyle] = paragraph
            }
            let context = NSStringDrawingContext()
            context.minimumScaleFactor = 0.001
            (text as NSString).draw(with: bounds,
                                    options: [.usesFontLeading],
                                    attributes: attrs,
                                    context: context)
        }
    }
}
