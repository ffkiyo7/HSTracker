//
//  TrackerCardListViewModel.swift
//  HSTracker
//
//  ObservableObject list state for the SwiftUI main tracker table.
//  Same pattern as PlayerResourcesViewModel / RootOverlayViewModel.
//

import AppKit
import Foundation
import SwiftUI

struct TrackerCardRowID: Hashable {
    let cardId: String
    let jousted: Bool
    let isCreated: Bool
    let wasDiscarded: Bool
    let deckListIndex: Int
    let hasIncindius: Bool
    let incindiusTurn: Int
    let incindiusCounter: Int
    /// 2.7: copies of one card in the played section are split by where they
    /// ended up, so the status is part of which row this is.
    var zoneStatus: CardZoneStatus = .none
    // A created copy in hand and one in the deck can produce two identical
    // keys; ForEach needs distinct ids, so repeats are numbered.
    var occurrence: Int = 0

    static func matchingAnimatedCardList(_ card: Card) -> TrackerCardRowID {
        let incindius = card.extraInfo as? IncindiusCounter
        return TrackerCardRowID(
            cardId: card.id,
            jousted: card.jousted,
            isCreated: card.isCreated,
            wasDiscarded: Settings.highlightDiscarded ? card.wasDiscarded : false,
            deckListIndex: card.deckListIndex,
            hasIncindius: incindius != nil,
            incindiusTurn: incindius?.turnPlayed ?? 0,
            incindiusCounter: incindius?.counter ?? 0,
            zoneStatus: card.zoneStatus
        )
    }
}

struct TrackerCardRow: Identifiable, Equatable {
    let id: TrackerCardRowID
    let card: Card
    var highlight: HighlightColor

    static func == (lhs: TrackerCardRow, rhs: TrackerCardRow) -> Bool {
        lhs.id == rhs.id
            && highlightsEqual(lhs.highlight, rhs.highlight)
            && lhs.card.count == rhs.card.count
            && lhs.card.cost == rhs.card.cost
            && lhs.card.name == rhs.card.name
            && lhs.card.highlightDraw == rhs.card.highlightDraw
            && lhs.card.highlightInHand == rhs.card.highlightInHand
            && lhs.card.extraInfo?.cardNameSuffix == rhs.card.extraInfo?.cardNameSuffix
    }

    private static func highlightsEqual(_ a: HighlightColor, _ b: HighlightColor) -> Bool {
        switch (a, b) {
        case (.none, .none), (.teal, .teal), (.orange, .orange), (.green, .green):
            return true
        default:
            return false
        }
    }
}

final class TrackerCardListViewModel: ObservableObject {
    @Published private(set) var rows: [TrackerCardRow] = []
    @Published var rowHeight: CGFloat = TrackerMetrics.rowHeight
    @Published var barWidth: CGFloat = TrackerMetrics.panelWidth
    @Published var showRarityColors: Bool = Settings.showRarityColors
    @Published var playerType: PlayerType = .player
    @Published var sectionHeaderHeight: CGFloat = 40
    /// The panel base's alpha. It reaches the rows through the view model so a
    /// change to `tracker_opacity` alone still repaints them: `updateLayout`
    /// runs `syncAppearance()` on every refresh, and a published change is the
    /// only thing that makes SwiftUI re-evaluate a list whose rows did not move.
    @Published var baseOpacity: CGFloat = TrackerDiagnostics.panelOpacity(
        setting: Settings.trackerOpacity)
    /// Perf P2 diagnostics, carried the same way so that flipping one with
    /// `defaults write` takes effect on the next refresh instead of a restart.
    @Published var flattensRows: Bool = TrackerDiagnostics.flattensRows
    @Published var drawsArt: Bool = TrackerDiagnostics.drawsArt
    @Published var drawsTextShadow: Bool = TrackerDiagnostics.drawsTextShadow

    /// T8: the rows that are flashing right now, each with the generation that
    /// lit it. The generation is the view's identity, so a row that flashes
    /// again while it is still lit restarts the curve instead of staying put.
    @Published private(set) var flashing: [TrackerCardRowID: Int] = [:]
    /// T8: bumped once per refresh that is allowed to move, and read by the
    /// view as `.animation(_:value:)`. The rows themselves are always assigned
    /// plainly — whether that assignment animates is decided *after* it, at
    /// `commitMotion`, because the row grid is only known once
    /// `TrackerViewModel.updateLayout` has run (review 1).
    @Published private(set) var motionGeneration = 0

    /// Which hover the rows report to `RootOverlayWindow`'s sweep
    /// (`TrackerRowHoverKey`). `.none` reports nothing.
    var hoverKind: TrackerRowHoverKind = .none

    var count: Int { rows.count }

    private var highlightFn: ((Card, [Card]) -> HighlightColor)?
    private var flashGeneration = 0
    /// One work item for the whole list, replaced on every flash: the set can
    /// only ever be emptied, never half-emptied, so no row can be left with a
    /// stale overlay.
    private var flashClear: DispatchWorkItem?
    /// What the last `update(cards:)` asked for, waiting for the geometry half
    /// of the answer. `TrackerViewModel.updateLayout` runs later in the same
    /// main-thread block (`update(...groups:)` then `relayoutZonePanel()`).
    private var pendingFlashes: Set<TrackerCardRowID>?

    deinit {
        flashClear?.cancel()
    }

    func syncAppearance() {
        let nextRarity = Settings.showRarityColors
        if showRarityColors != nextRarity {
            showRarityColors = nextRarity
        }
        let nextOpacity = TrackerDiagnostics.panelOpacity(setting: Settings.trackerOpacity)
        if baseOpacity != nextOpacity {
            baseOpacity = nextOpacity
        }
        if flattensRows != TrackerDiagnostics.flattensRows {
            flattensRows = TrackerDiagnostics.flattensRows
        }
        if drawsArt != TrackerDiagnostics.drawsArt {
            drawsArt = TrackerDiagnostics.drawsArt
        }
        if drawsTextShadow != TrackerDiagnostics.drawsTextShadow {
            drawsTextShadow = TrackerDiagnostics.drawsTextShadow
        }
    }

    func update(cards: [Card]) {
        syncAppearance()
        let next = rows(from: cards)
        guard next != rows else { return }

        // Always a plain assignment. Nothing here knows yet whether the row
        // grid is about to move under these rows: in the compressed state
        // `cardHeight` is `(availableHeight - offset) / totalCards`, so losing
        // a row makes every row taller. Deciding here and letting the geometry
        // veto later is exactly the "one flies while the other jumps" split
        // this file used to have.
        switch motionPlan(for: next) {
        case .instant:
            pendingFlashes = nil
            rows = next
        case .animated(let flashes):
            pendingFlashes = flashes
            rows = next
        }
    }

    /// The single commit point, and the *only* thing that can start a motion:
    /// a list nobody commits for simply never animates, which is the safe
    /// direction. `animates` is the coordinator's verdict for the whole panel;
    /// a list that did not ask to move is unaffected either way.
    func commitMotion(animates: Bool) {
        guard let flashes = pendingFlashes else { return }
        pendingFlashes = nil
        guard animates else { return }
        motionGeneration &+= 1
        light(flashes)
    }

    /// Whether this list asked to move on the refresh that has not committed
    /// yet. A plain read: the verdict clears it, not this.
    var wantsMotion: Bool { pendingFlashes != nil }

    /// A disabled switch has to behave as it did before T8, so it lands on
    /// `.instant` here as well as at the view.
    private func motionPlan(for next: [TrackerCardRow]) -> TrackerMotion.Plan {
        guard TrackerMotion.isEnabled else { return .instant }
        return TrackerMotion.plan(from: rows.map(TrackerCardListViewModel.motionRow),
                                  to: next.map(TrackerCardListViewModel.motionRow))
    }

    private static func motionRow(_ row: TrackerCardRow) -> TrackerMotion.Row {
        TrackerMotion.Row(id: row.id, count: row.card.count)
    }

    /// Not inside the row animation's transaction: the overlay owns its own
    /// curve, and an implicit fade on top of it would double the timing.
    private func light(_ flashes: Set<TrackerCardRowID>) {
        guard !flashes.isEmpty else { return }
        flashGeneration += 1
        for id in flashes {
            flashing[id] = flashGeneration
        }
        flashClear?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.flashing = [:]
        }
        flashClear = work
        DispatchQueue.main.asyncAfter(deadline: .now() + TrackerMotion.flashDuration, execute: work)
    }

    func setHighlight(_ fn: ((Card, [Card]) -> HighlightColor)?) {
        highlightFn = fn
        let next = rows(from: rows.map(\.card))
        if next != rows {
            rows = next
        }
    }

    private func rows(from cards: [Card]) -> [TrackerCardRow] {
        let live = cards.filter { $0.count > 0 }
        var seen: [TrackerCardRowID: Int] = [:]
        return cards.map { card in
            let highlight: HighlightColor
            if card.count <= 0 || card.jousted {
                highlight = .none
            } else {
                highlight = highlightFn?(card, live) ?? .none
            }
            var id = TrackerCardRowID.matchingAnimatedCardList(card)
            let repeats = seen[id, default: 0]
            seen[id] = repeats + 1
            id.occurrence = repeats
            return TrackerCardRow(id: id, card: card, highlight: highlight)
        }
    }
}
