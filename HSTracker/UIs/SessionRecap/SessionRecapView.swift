//
//  SessionRecapView.swift
//  HSTracker
//
//  D2: the tracker's three-row header, extended into a table. Fonts, colours,
//  grid lines and the 1fr / 62 / 76 columns all come from `HeaderStyle`
//  (TrackerHeaderView.swift); the two summary levels carry the theme's card
//  strip `fade.png` the same way a card row does.
//

import AppKit
import SwiftUI

enum SessionRecapStyle {
    static let background = Color(red: 0x23 / 255, green: 0x27 / 255, blue: 0x2A / 255)
    /// The header's row height at scale 1 — this window does not scale.
    static let rowHeight: CGFloat = 40
    static let gameRowHeight: CGFloat = 26
    static let footerHeight: CGFloat = 44
    static let middleWidth: CGFloat = 62
    static let trailingWidth: CGFloat = 76
    static let width: CGFloat = 420
}

struct SessionRecapView: View {
    let summary: SessionRecapSummary
    let onOpenStatistics: (String) -> Void
    let onClose: () -> Void

    static func preferredHeight(for summary: SessionRecapSummary) -> CGFloat {
        let rows = CGFloat(1 + summary.decks.count) * SessionRecapStyle.rowHeight
        let games = CGFloat(summary.decks.reduce(0) { $0 + $1.games.count }) * SessionRecapStyle.gameRowHeight
        return rows + games + SessionRecapStyle.footerHeight
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    totalRow
                    ForEach(summary.decks) { deck in
                        deckRow(deck)
                        ForEach(deck.games) { game in
                            gameRow(game)
                        }
                    }
                }
            }
            footer
        }
        .foregroundColor(.white)
        .frame(minWidth: SessionRecapStyle.width, maxWidth: .infinity, maxHeight: .infinity)
        .background(SessionRecapStyle.background)
        .overlay(Rectangle().strokeBorder(HeaderStyle.border, lineWidth: 1))
        // Fixed dark, like the tracker itself: the window must not follow the
        // system appearance.
        .environment(\.colorScheme, .dark)
    }

    private var totalRow: some View {
        SessionRecapRow(height: SessionRecapStyle.rowHeight, shaded: true, topDivider: false) {
            Text(String(format: String.localizedString("session_recap_total", comment: ""), summary.record.total))
                .font(HeaderStyle.text(1, size: 13))
                .lineLimit(1)
        } middle: {
            Text(winRate(summary.record))
                .font(HeaderStyle.digits(1))
        } trailing: {
            SessionRecapRecord(record: summary.record)
        }
    }

    private func deckRow(_ deck: SessionRecapDeck) -> some View {
        SessionRecapRow(height: SessionRecapStyle.rowHeight, shaded: true, topDivider: true) {
            HStack(spacing: 7) {
                if let icon = classIcon(deck.playerClass) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 22, height: 22)
                }
                Text(deck.name)
                    .font(HeaderStyle.text(1, size: 13))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                if let deckId = deck.deckId {
                    Button {
                        onOpenStatistics(deckId)
                    } label: {
                        Image(systemName: "chart.bar.doc.horizontal")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.white.opacity(0.75))
                    .help(String.localizedString("session_recap_open_stats", comment: ""))
                }
            }
        } middle: {
            Text(winRate(deck.record))
                .font(HeaderStyle.digits(1))
        } trailing: {
            SessionRecapRecord(record: deck.record)
        }
    }

    private func gameRow(_ game: SessionRecapGame) -> some View {
        SessionRecapRow(height: SessionRecapStyle.gameRowHeight, shaded: false, topDivider: true) {
            HStack(spacing: 6) {
                Text(String.localizedString("vs", comment: ""))
                    .font(HeaderStyle.text(1, size: 12))
                    .foregroundColor(.white.opacity(0.75))
                if let icon = classIcon(game.opponentClass) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 16, height: 16)
                }
                Text(String.localizedString(game.opponentClass.rawValue, comment: ""))
                    .font(HeaderStyle.text(1, size: 12))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(SessionRecapView.time.string(from: game.startTime))
                    .font(HeaderStyle.digits(1, size: 12))
                    .foregroundColor(.white.opacity(0.75))
            }
            .padding(.leading, 20)
        } middle: {
            if game.turns > 0 {
                Text(String(format: String.localizedString("session_recap_turns", comment: ""), game.turns))
                    .font(HeaderStyle.text(1, size: 12))
                    .foregroundColor(.white.opacity(0.75))
            }
        } trailing: {
            Text(resultText(game.result))
                .font(HeaderStyle.text(1, size: 12))
                .foregroundColor(resultColor(game.result))
        }
    }

    private var footer: some View {
        HStack(spacing: 0) {
            Text(durationText)
                .font(HeaderStyle.text(1, size: 12))
                .foregroundColor(.white.opacity(0.75))
            Spacer(minLength: 8)
            Button(String.localizedString("session_recap_close", comment: ""), action: onClose)
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 10)
        .frame(height: SessionRecapStyle.footerHeight)
        .overlay(alignment: .top) { Rectangle().fill(HeaderStyle.divider).frame(height: 1) }
    }

    private var durationText: String {
        let minutes = max(Int(summary.end.timeIntervalSince(summary.start)) / 60, 0)
        if minutes < 60 {
            return String(format: String.localizedString("session_recap_duration_minutes", comment: ""), minutes)
        }
        return String(format: String.localizedString("session_recap_duration_hours", comment: ""),
                      minutes / 60, minutes % 60)
    }

    private func winRate(_ record: StatsDeckRecord) -> String {
        let rate = StatsHelper.getDeckWinRate(record: record)
        guard rate >= 0 else {
            return "--"
        }
        return String(format: "%.1f%%", rate * 100)
    }

    private func resultText(_ result: GameResult) -> String {
        switch result {
        case .win: return String.localizedString("session_recap_win", comment: "")
        case .loss: return String.localizedString("session_recap_loss", comment: "")
        case .draw: return String.localizedString("session_recap_draw", comment: "")
        case .unknown: return "--"
        }
    }

    private func resultColor(_ result: GameResult) -> Color {
        switch result {
        case .win: return HeaderStyle.win
        case .loss: return HeaderStyle.loss
        default: return .white.opacity(0.75)
        }
    }

    private func classIcon(_ cardClass: CardClass) -> NSImage? {
        NSImage(named: cardClass.rawValue.lowercased())
    }

    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

/// Same three columns and grid lines as `TrackerHeaderRow`, plus an optional
/// `fade.png` backing for the two summary levels.
private struct SessionRecapRow<Leading: View, Middle: View, Trailing: View>: View {
    let height: CGFloat
    let shaded: Bool
    let topDivider: Bool
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let middle: () -> Middle
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 0) {
            leading()
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .overlay(alignment: .trailing) { Rectangle().fill(HeaderStyle.divider).frame(width: 1) }
            middle()
                .frame(width: SessionRecapStyle.middleWidth)
                .frame(maxHeight: .infinity)
                .overlay(alignment: .trailing) { Rectangle().fill(HeaderStyle.divider).frame(width: 1) }
            trailing()
                .frame(width: SessionRecapStyle.trailingWidth)
                .frame(maxHeight: .infinity)
        }
        .frame(height: height)
        // Before the background, or the fade layer would cast the shadow too and
        // leave a dark line on the row below.
        .shadow(color: .black, radius: 0, x: 1, y: 1)
        .background(shaded ? AnyView(SessionRecapFade()) : AnyView(Color.clear))
        .overlay(alignment: .top) {
            if topDivider {
                Rectangle().fill(HeaderStyle.divider).frame(height: 1)
            }
        }
    }
}

/// The theme's `fade.png`, laid out exactly like `TrackerHeaderView` does it:
/// the leading strip a card row hides behind its gem is filled by over-scaling
/// a second copy until only its flat, opaque part shows.
private struct SessionRecapFade: View {
    var body: some View {
        GeometryReader { proxy in
            if let fade = TrackerFade.image {
                let start = (proxy.size.width * TrackerFade.startFraction).rounded()
                HStack(spacing: 0) {
                    if start > 0 {
                        Image(nsImage: fade)
                            .resizable()
                            .frame(width: start / TrackerFade.opaqueFraction, height: proxy.size.height)
                            .frame(width: start, height: proxy.size.height, alignment: .leading)
                            .clipped()
                    }
                    Image(nsImage: fade)
                        .resizable()
                        .frame(width: max(proxy.size.width - start, 0), height: proxy.size.height)
                }
                .opacity(HeaderStyle.fadeOpacity)
            }
        }
    }
}

private struct SessionRecapRecord: View {
    let record: StatsDeckRecord

    var body: some View {
        HStack(spacing: 4) {
            Text("\(record.wins)")
                .foregroundColor(HeaderStyle.win)
            Text("/")
                .font(HeaderStyle.digits(1, size: 12))
                .foregroundColor(.white.opacity(0.8))
            Text("\(record.losses)")
                .foregroundColor(HeaderStyle.loss)
        }
        .font(HeaderStyle.digits(1))
    }
}
