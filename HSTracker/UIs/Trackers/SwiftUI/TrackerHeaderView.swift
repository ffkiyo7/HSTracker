//
//  TrackerHeaderView.swift
//  HSTracker
//
//  SwiftUI replacement for Tracker's card count, draw chance, record and
//  graveyard panels. Three-row table over the hero art (docs/tasks/phase1-t5-tracker-header.md, D2).
//

import AppKit
import SwiftUI

final class TrackerHeaderViewModel: ObservableObject {
    /// Settings.showDeckNameInTracker. V2a put the deck name back on the first
    /// line next to the class icon, so the flag gates both again.
    @Published var showDeckName = false
    @Published var deckName = ""
    @Published var playerClass: CardClass?
    @Published var handCount = 0
    @Published var deckCount = 0
    @Published var showCardCount = false
    @Published var overallRecord: StatsDeckRecord?
    @Published var matchupClass: CardClass?
    @Published var matchupRecord: StatsDeckRecord?
    /// One header line, i.e. one card row (V2a); `TrackerMetrics.rowHeight` is
    /// the reference value the sheet's numbers are expressed in.
    @Published var lineHeight: CGFloat = TrackerMetrics.rowHeight
    /// The panel's drawing width for this frame. The two fixed columns are a
    /// fraction of it, so a compressed panel narrows them instead of eating the
    /// deck-name column (V1 left this as a known defect).
    @Published var barWidth: CGFloat = TrackerMetrics.panelWidth
    @Published var heroArt: NSImage?

    private var heroCardId = ""

    var showFirstLine: Bool {
        showCardCount || showDeckName
    }

    var lineCount: Int {
        guard showFirstLine || overallRecord != nil else {
            return 0
        }
        return (showFirstLine ? 1 : 0) + (overallRecord == nil ? 0 : 1) + (matchupRecord == nil ? 0 : 1)
    }

    var height: CGFloat {
        CGFloat(lineCount) * lineHeight
    }

    func update(showDeckName: Bool,
                playerClass: CardClass?,
                heroCardId: String,
                handCount: Int,
                deckCount: Int,
                showCardCount: Bool,
                overallRecord: StatsDeckRecord?,
                matchupClass: CardClass?,
                matchupRecord: StatsDeckRecord?,
                lineHeight: CGFloat) {
        if self.showDeckName != showDeckName {
            self.showDeckName = showDeckName
        }
        // The deck name is read here rather than passed in: `Tracker.swift` is
        // only open to the header / section *heights* in this change, and this
        // is the same source its `playerName` comes from (Game.swift).
        let name = showDeckName
            ? (AppDelegate.instance().coreManager.game.currentDeck?.name ?? "")
            : ""
        if deckName != name {
            deckName = name
        }
        if self.playerClass != playerClass {
            self.playerClass = playerClass
        }
        if self.handCount != handCount {
            self.handCount = handCount
        }
        if self.deckCount != deckCount {
            self.deckCount = deckCount
        }
        if self.showCardCount != showCardCount {
            self.showCardCount = showCardCount
        }
        if !recordsEqual(self.overallRecord, overallRecord) {
            self.overallRecord = overallRecord
        }
        if self.matchupClass != matchupClass {
            self.matchupClass = matchupClass
        }
        if !recordsEqual(self.matchupRecord, matchupRecord) {
            self.matchupRecord = matchupRecord
        }
        if self.lineHeight != lineHeight {
            self.lineHeight = lineHeight
        }
        loadHeroArt(cardId: heroCardId)
    }

    // The art is only fetched when the hero changes; a stale completion for a
    // previous hero is dropped.
    private func loadHeroArt(cardId: String) {
        guard cardId != heroCardId else {
            return
        }
        heroCardId = cardId
        guard !cardId.isEmpty else {
            heroArt = nil
            return
        }
        if let cached = ImageUtils.cachedArt(cardId: cardId) {
            heroArt = cached
            return
        }
        heroArt = nil
        ImageUtils.art(for: cardId) { [weak self] image in
            guard let self, self.heroCardId == cardId else {
                return
            }
            self.heroArt = image
        }
    }

    private func recordsEqual(_ lhs: StatsDeckRecord?, _ rhs: StatsDeckRecord?) -> Bool {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            return lhs.wins == rhs.wins && lhs.losses == rhs.losses && lhs.draws == rhs.draws
        case (nil, nil):
            return true
        default:
            return false
        }
    }
}

private extension StatsDeckRecord {
    var trackerWinRate: String {
        let winRate = StatsHelper.getDeckWinRate(record: self)
        guard winRate >= 0 else {
            return "--"
        }
        return String(format: "%.1f%%", winRate * 100)
    }
}

/// Internal, not private: the session recap window reuses this as its spec.
enum HeaderStyle {
    static let digitFontName = "Belwe Bd BT"
    /// Session recap only. The tracker header went to the gold rules of the D3
    /// sheet (`TrackerBarStyle.line`) in V2a.
    static let divider = Color.white.opacity(0.18)
    static let border = Color(red: 0x14 / 255, green: 0x16 / 255, blue: 0x17 / 255)
    static let win = Color(red: 0x62 / 255, green: 0xD9 / 255, blue: 0x7A / 255)
    static let loss = Color(red: 0xFF / 255, green: 0x6B / 255, blue: 0x5E / 255)
    static let shade = Color(red: 12 / 255, green: 11 / 255, blue: 9 / 255)
    /// Session recap only. The tracker header no longer lays `TrackerFade` over
    /// its hero art: the D3 sheet's `.hdr .shade` is the plain 0.95 / 0.9 / 0.4
    /// gradient, which is what `panelShade` draws.
    static let fadeOpacity: CGFloat = 0.8
    /// Hero art is drawn this much wider than the header and clipped, so the
    /// tile's own edge columns never reach the visible area.
    static let artOverscan: CGFloat = 1.08

    /// Absolute point sizes: the session recap window is a normal window, not a
    /// panel on the card-row grid, so it passes `scale` 1.
    static func text(_ scale: CGFloat, size: CGFloat = 14) -> Font {
        Font.custom(TrackerTextFont.name, size: size * scale)
    }

    static func digits(_ scale: CGFloat, size: CGFloat = 15) -> Font {
        Font.custom(digitFontName, size: size * scale)
    }
}

struct TrackerHeaderView: View {
    @ObservedObject var viewModel: TrackerHeaderViewModel

    /// One reference pixel of the 171 x 21 sheet. A header line *is* a card row
    /// since V2a, so the whole panel reads off one grid.
    private var u: CGFloat { viewModel.lineHeight / TrackerMetrics.rowHeight }
    /// The two fixed columns follow the panel width rather than the line height:
    /// under compression the bars narrow while `lineHeight` stays at the base
    /// value, and a 40 + 46 pair frozen to the base would eat the deck-name
    /// column (V1 reported this as a known defect).
    private var columnUnit: CGFloat {
        viewModel.barWidth > 0 ? viewModel.barWidth / TrackerMetrics.panelWidth : u
    }
    private var rule: CGFloat { max(TrackerBarStyle.hairline * u, 0.5) }

    var body: some View {
        Group {
            if viewModel.lineCount > 0 {
                ZStack {
                    heroBackground
                    rows
                }
                .clipped()
                .overlay(Rectangle().strokeBorder(TrackerBarStyle.line, lineWidth: rule))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.clear)
        .transaction { $0.animation = nil }
    }

    private var heroBackground: some View {
        GeometryReader { proxy in
            ZStack {
                if let art = viewModel.heroArt {
                    // Slightly over-scan the art: the 256x tiles carry a light
                    // border column/row from the source crop, which showed as a
                    // grey strip on the left through the shade.
                    Image(nsImage: art)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width * HeaderStyle.artOverscan,
                               height: proxy.size.height, alignment: .top)
                        .offset(y: -proxy.size.height * 0.12)
                }
                // Drawn with or without art: the sheet's `.hdr .shade` is this
                // gradient, and it never drops to fully transparent, so the
                // deck-count column never sits straight on the game screen
                // (the opponent tracker has no hero art at all).
                panelShade
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
    }

    /// `.hdr .shade` of the D3 sheet, kept from T5: 0.95 / 0.9 / 0.4 at
    /// 0 / 0.48 / 1.
    private var panelShade: some View {
        LinearGradient(
            stops: [
                .init(color: HeaderStyle.shade.opacity(0.95), location: 0),
                .init(color: HeaderStyle.shade.opacity(0.9), location: 0.48),
                .init(color: HeaderStyle.shade.opacity(0.4), location: 1)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var rows: some View {
        let labelFont = TrackerBarStyle.label(u, size: TrackerBarStyle.headerLabelFontSize)
        let digitFont = TrackerBarStyle.digits(u, size: TrackerBarStyle.headerDigitFontSize)
        let icon = TrackerBarStyle.headerIcon * u
        return VStack(spacing: 0) {
            if viewModel.showFirstLine {
                row(isFirst: true) {
                    // D3 sheet's first line is "<class dot> <deck name> | 6 | 13":
                    // the two SF Symbols that labelled the counts are gone, the
                    // column itself says which count it is.
                    HStack(spacing: TrackerBarStyle.headerIconGap * u) {
                        if viewModel.showDeckName,
                           let image = viewModel.playerClass.flatMap(classIcon) {
                            Image(nsImage: image)
                                .resizable()
                                .frame(width: icon, height: icon)
                        }
                        if viewModel.showDeckName && !viewModel.deckName.isEmpty {
                            Text(viewModel.deckName)
                                .font(labelFont)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                } middle: {
                    if viewModel.showCardCount {
                        Text("\(viewModel.handCount)").font(digitFont)
                    }
                } trailing: {
                    if viewModel.showCardCount {
                        Text("\(viewModel.deckCount)").font(digitFont)
                    }
                }
            }
            if let record = viewModel.overallRecord {
                row(isFirst: !viewModel.showFirstLine) {
                    Text(String.localizedString("Deck win rate", comment: ""))
                        .font(labelFont)
                        .lineLimit(1)
                        .truncationMode(.tail)
                } middle: {
                    Text(record.trackerWinRate).font(digitFont)
                } trailing: {
                    TrackerHeaderRecord(record: record, u: u, font: digitFont)
                }
            }
            if let matchupClass = viewModel.matchupClass,
               let record = viewModel.matchupRecord {
                row(isFirst: false) {
                    HStack(spacing: TrackerBarStyle.headerIconGap * u) {
                        Text(String.localizedString("vs", comment: ""))
                            .font(labelFont)
                        if let image = classIcon(matchupClass) {
                            Image(nsImage: image)
                                .resizable()
                                .frame(width: icon, height: icon)
                        }
                    }
                } middle: {
                    Text(record.trackerWinRate).font(digitFont)
                } trailing: {
                    TrackerHeaderRecord(record: record, u: u, font: digitFont)
                }
            }
        }
        .foregroundColor(TrackerBarStyle.text)
        .shadow(color: .black, radius: 0, x: 1, y: 1)
    }

    private func row<Leading: View, Middle: View, Trailing: View>(
        isFirst: Bool,
        @ViewBuilder leading: @escaping () -> Leading,
        @ViewBuilder middle: @escaping () -> Middle,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) -> some View {
        TrackerHeaderRow(u: u,
                         height: viewModel.lineHeight,
                         middleWidth: TrackerBarStyle.headerMiddleColumn * columnUnit,
                         trailingWidth: TrackerBarStyle.headerTrailingColumn * columnUnit,
                         isFirst: isFirst,
                         leading: leading,
                         middle: middle,
                         trailing: trailing)
    }

    private func classIcon(_ cardClass: CardClass) -> NSImage? {
        NSImage(named: cardClass.rawValue.lowercased())
    }
}

/// One `.hdr` line: a flexible label column and the two fixed count columns,
/// separated by the gold rules of the D3 sheet.
private struct TrackerHeaderRow<Leading: View, Middle: View, Trailing: View>: View {
    let u: CGFloat
    let height: CGFloat
    let middleWidth: CGFloat
    let trailingWidth: CGFloat
    let isFirst: Bool
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let middle: () -> Middle
    @ViewBuilder let trailing: () -> Trailing

    private var rule: CGFloat { max(TrackerBarStyle.hairline * u, 0.5) }

    var body: some View {
        HStack(spacing: 0) {
            leading()
                .padding(.horizontal, TrackerBarStyle.headerPadding * u)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            middle()
                .frame(width: middleWidth)
                .frame(maxHeight: .infinity)
                .overlay(alignment: .leading) {
                    Rectangle().fill(TrackerBarStyle.line).frame(width: rule)
                }
            trailing()
                .frame(width: trailingWidth)
                .frame(maxHeight: .infinity)
                .overlay(alignment: .leading) {
                    Rectangle().fill(TrackerBarStyle.line).frame(width: rule)
                }
        }
        .frame(height: height)
        .overlay(alignment: .top) {
            if !isFirst {
                Rectangle().fill(TrackerBarStyle.line).frame(height: rule)
            }
        }
    }
}

private struct TrackerHeaderRecord: View {
    let record: StatsDeckRecord
    let u: CGFloat
    let font: Font

    var body: some View {
        HStack(spacing: TrackerBarStyle.headerRecordGap * u) {
            Text("\(record.wins)")
                .foregroundColor(HeaderStyle.win)
            Text("/")
                .foregroundColor(TrackerBarStyle.text.opacity(0.8))
            Text("\(record.losses)")
                .foregroundColor(HeaderStyle.loss)
        }
        .font(font)
    }
}
