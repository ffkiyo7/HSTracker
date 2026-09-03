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
    @Published var deckName = ""
    @Published var showDeckName = false
    @Published var playerClass: CardClass?
    @Published var handCount = 0
    @Published var deckCount = 0
    @Published var showCardCount = false
    @Published var overallRecord: StatsDeckRecord?
    @Published var matchupClass: CardClass?
    @Published var matchupRecord: StatsDeckRecord?
    @Published var lineHeight: CGFloat = 40
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

    func update(deckName: String,
                showDeckName: Bool,
                playerClass: CardClass?,
                heroCardId: String,
                handCount: Int,
                deckCount: Int,
                showCardCount: Bool,
                overallRecord: StatsDeckRecord?,
                matchupClass: CardClass?,
                matchupRecord: StatsDeckRecord?,
                lineHeight: CGFloat) {
        if self.deckName != deckName {
            self.deckName = deckName
        }
        if self.showDeckName != showDeckName {
            self.showDeckName = showDeckName
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

private enum HeaderStyle {
    static let digitFontName = "Belwe Bd BT"
    static let divider = Color.white.opacity(0.18)
    static let border = Color(red: 0x14 / 255, green: 0x16 / 255, blue: 0x17 / 255)
    static let innerBorder = Color.white.opacity(0.08)
    static let win = Color(red: 0x62 / 255, green: 0xD9 / 255, blue: 0x7A / 255)
    static let loss = Color(red: 0xFF / 255, green: 0x6B / 255, blue: 0x5E / 255)
    static let shade = Color(red: 12 / 255, green: 11 / 255, blue: 9 / 255)

    static func text(_ scale: CGFloat, size: CGFloat = 14) -> Font {
        Font.custom(TrackerTextFont.name, size: size * scale)
    }

    static func digits(_ scale: CGFloat, size: CGFloat = 15) -> Font {
        Font.custom(digitFontName, size: size * scale)
    }
}

struct TrackerHeaderView: View {
    @ObservedObject var viewModel: TrackerHeaderViewModel

    private var scale: CGFloat { viewModel.lineHeight / 40 }

    var body: some View {
        Group {
            if viewModel.lineCount > 0 {
                ZStack {
                    heroBackground
                    rows
                }
                .clipped()
                .overlay(Rectangle().strokeBorder(HeaderStyle.innerBorder, lineWidth: 1).padding(1))
                .overlay(Rectangle().strokeBorder(HeaderStyle.border, lineWidth: 1))
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
                    Image(nsImage: art)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                        .offset(y: -proxy.size.height * 0.12)
                }
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
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
    }

    private var rows: some View {
        VStack(spacing: 0) {
            if viewModel.showFirstLine {
                TrackerHeaderRow(scale: scale, height: viewModel.lineHeight,
                                 isLast: viewModel.overallRecord == nil) {
                    HStack(spacing: 7 * scale) {
                        if viewModel.showDeckName {
                            if let icon = viewModel.playerClass.flatMap(classIcon) {
                                Image(nsImage: icon)
                                    .resizable()
                                    .frame(width: 22 * scale, height: 22 * scale)
                            }
                            Text(viewModel.deckName)
                                .font(HeaderStyle.text(scale))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                } middle: {
                    if viewModel.showCardCount {
                        HStack(spacing: 5 * scale) {
                            Image(systemName: "hand.raised")
                                .font(.system(size: 13 * scale, weight: .semibold))
                            Text("\(viewModel.handCount)")
                                .font(HeaderStyle.digits(scale, size: 16))
                        }
                    }
                } trailing: {
                    if viewModel.showCardCount {
                        HStack(spacing: 5 * scale) {
                            Image(systemName: "rectangle.portrait.on.rectangle.portrait")
                                .font(.system(size: 13 * scale, weight: .semibold))
                            Text("\(viewModel.deckCount)")
                                .font(HeaderStyle.digits(scale, size: 16))
                        }
                    }
                }
            }
            if let record = viewModel.overallRecord {
                TrackerHeaderRow(scale: scale, height: viewModel.lineHeight,
                                 isLast: viewModel.matchupRecord == nil) {
                    Text(String.localizedString("Deck win rate", comment: ""))
                        .font(HeaderStyle.text(scale, size: 13))
                        .lineLimit(1)
                } middle: {
                    Text(record.trackerWinRate)
                        .font(HeaderStyle.digits(scale))
                } trailing: {
                    TrackerHeaderRecord(record: record, scale: scale)
                }
            }
            if let matchupClass = viewModel.matchupClass,
               let record = viewModel.matchupRecord {
                TrackerHeaderRow(scale: scale, height: viewModel.lineHeight, isLast: true) {
                    HStack(spacing: 7 * scale) {
                        Text(String.localizedString("vs", comment: ""))
                            .font(HeaderStyle.text(scale, size: 13))
                        if let icon = classIcon(matchupClass) {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 22 * scale, height: 22 * scale)
                        }
                        Text(String.localizedString(matchupClass.rawValue, comment: ""))
                            .font(HeaderStyle.text(scale, size: 13))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                } middle: {
                    Text(record.trackerWinRate)
                        .font(HeaderStyle.digits(scale))
                } trailing: {
                    TrackerHeaderRecord(record: record, scale: scale)
                }
            }
        }
        .foregroundColor(.white)
        .shadow(color: .black, radius: 0, x: 1, y: 1)
    }

    private func classIcon(_ cardClass: CardClass) -> NSImage? {
        NSImage(named: cardClass.rawValue.lowercased())
    }
}

private struct TrackerHeaderRow<Leading: View, Middle: View, Trailing: View>: View {
    let scale: CGFloat
    let height: CGFloat
    let isLast: Bool
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let middle: () -> Middle
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 0) {
            leading()
                .padding(.horizontal, 8 * scale)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .overlay(alignment: .trailing) { Rectangle().fill(HeaderStyle.divider).frame(width: 1) }
            middle()
                .frame(width: 62 * scale)
                .frame(maxHeight: .infinity)
                .overlay(alignment: .trailing) { Rectangle().fill(HeaderStyle.divider).frame(width: 1) }
            trailing()
                .frame(width: 76 * scale)
                .frame(maxHeight: .infinity)
        }
        .frame(height: height)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle().fill(HeaderStyle.divider).frame(height: 1)
            }
        }
    }
}

private struct TrackerHeaderRecord: View {
    let record: StatsDeckRecord
    let scale: CGFloat

    var body: some View {
        HStack(spacing: 4 * scale) {
            Text("\(record.wins)")
                .foregroundColor(HeaderStyle.win)
            Text("/")
                .font(HeaderStyle.digits(scale, size: 12))
                .foregroundColor(.white.opacity(0.8))
            Text("\(record.losses)")
                .foregroundColor(HeaderStyle.loss)
        }
        .font(HeaderStyle.digits(scale))
    }
}

final class TrackerHeaderHost: NSView {
    let viewModel = TrackerHeaderViewModel()
    private let hostingView: TrackerTransparentHostingView<TrackerHeaderView>

    var height: CGFloat {
        CGFloat(viewModel.lineCount) * viewModel.lineHeight
    }

    override var isOpaque: Bool { false }

    override init(frame: NSRect) {
        hostingView = TrackerTransparentHostingView(
            rootView: TrackerHeaderView(viewModel: viewModel)
        )
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.isOpaque = false
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
