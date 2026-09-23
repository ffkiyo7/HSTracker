//
//  TrackerMotion.swift
//  HSTracker
//
//  Phase 1 / T8. Everything the SwiftUI panel needs in order to move: the
//  durations, the one animation the rows and the panel geometry share, the
//  pure rule that decides whether a given refresh moves at all, and the two
//  animatable modifiers that draw the movement.
//
//  The shapes are deliberately unshaped: a leaving row's height factor *is*
//  the transition's progress, and `TrackerViewModel` animates the section
//  heights with the very same `animation`. Same delta, same curve, same start
//  frame, so the row's own collapse and the frame that contains it cannot
//  drift apart — no eyeballed offsets, and nothing to re-tune in pairs.
//

import AppKit
import SwiftUI

enum TrackerMotion {
    // MARK: - the dials (🎮 will move these)

    /// Row insert / remove, and every panel height that follows from them.
    /// `hdt-overlay.md` measured HDT at 0.7 s and recommends roughly half.
    static let duration: Double = 0.28
    /// The draw flash. HDT flashes for 1.0 s *before* it touches the numbers;
    /// the recommendation is half that with the numbers updating immediately,
    /// which is what happens here — the flash is an overlay, the row under it
    /// already reads the new count.
    static let flashDuration: Double = 0.4
    /// Peak alpha of that overlay.
    static let flashPeak: CGFloat = 0.38
    static let flashColor = Color.white

    /// The one animation. Rows and geometry must share it (see the file note).
    static var animation: Animation { .easeOut(duration: duration) }
    /// Linear, because `flashOpacity` already carries the shape.
    static var flashAnimation: Animation { .linear(duration: flashDuration) }

    /// Diagnostic switch ⑤, same contract as the Perf P2 keys: no preferences
    /// UI, `defaults write net.hearthsim.hstracker tracker_motion -bool false`,
    /// and with it off the panel behaves frame for frame as it did before T8.
    /// The system's "Reduce motion" is honoured the same way.
    static var isEnabled: Bool {
        Settings.trackerMotion
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    // MARK: - "does this refresh move?"

    /// A row reduced to what the decision is allowed to look at.
    struct Row: Equatable {
        let id: TrackerCardRowID
        let count: Int
    }

    enum Plan: Equatable {
        /// One frame, exactly as before T8.
        case instant
        /// Animate, and flash these rows (the ones that stayed and changed
        /// count, plus the ones that arrived).
        case animated(flashes: Set<TrackerCardRowID>)
    }

    /// The whole rule, as a pure function of the two row lists.
    ///
    /// It says yes to exactly one thing: a single card moving in or out of
    /// this one list. Everything else — the opening deal, a deck swap, the end
    /// of a game, `groupCardsByZone` flipping, a section emptying — shows up
    /// here as "more than one row changed" or "an end of the list was empty",
    /// and goes one frame. Row height, bar width and opacity are not inputs:
    /// they never reach this list as a row change (see `TrackerViewModel`,
    /// which refuses to animate a layout whose grid moved).
    static func plan(from before: [Row], to after: [Row]) -> Plan {
        // An empty end is a deal-in or a clear-out, never one card.
        guard !before.isEmpty, !after.isEmpty else { return .instant }

        var beforeCounts = [TrackerCardRowID: Int](minimumCapacity: before.count)
        for row in before {
            guard beforeCounts.updateValue(row.count, forKey: row.id) == nil else {
                // Duplicate ids are a bug elsewhere (`occurrence` numbers them
                // apart); refuse to reason about them rather than guess.
                return .instant
            }
        }
        var afterCounts = [TrackerCardRowID: Int](minimumCapacity: after.count)
        for row in after {
            guard afterCounts.updateValue(row.count, forKey: row.id) == nil else {
                return .instant
            }
        }

        var inserted = Set<TrackerCardRowID>()
        var changed = Set<TrackerCardRowID>()
        for row in after {
            guard let was = beforeCounts[row.id] else {
                inserted.insert(row.id)
                continue
            }
            if was != row.count {
                changed.insert(row.id)
            }
        }
        let removed = before.reduce(0) { afterCounts[$1.id] == nil ? $0 + 1 : $0 }

        guard removed + inserted.count + changed.count == 1 else { return .instant }

        // One card, so exactly one copy crossed the boundary. The played
        // section counts down from zero, hence the absolute values.
        let copiesBefore = before.reduce(0) { $0 + abs($1.count) }
        let copiesAfter = after.reduce(0) { $0 + abs($1.count) }
        guard abs(copiesAfter - copiesBefore) == 1 else { return .instant }

        return .animated(flashes: inserted.union(changed))
    }

    /// The geometry half of the same question. The panel may glide only when
    /// the grid itself held still — a `card_size` change, a window resize, a
    /// compression step or an opacity change moves every row at once and is
    /// exactly what "不许三十行一起飞" forbids.
    static func layoutCanAnimate(from old: TrackerLayout,
                                 to new: TrackerLayout,
                                 sectionChrome: CGFloat) -> Bool {
        guard old.cardHeight == new.cardHeight,
              old.barWidth == new.barWidth,
              old.opacity == new.opacity,
              old.headerHeight == new.headerHeight else {
            return false
        }
        // One row, or one row plus the header and padding of a section that
        // just appeared or emptied.
        let budget = new.cardHeight + sectionChrome + 0.5
        let pairs = [
            (old.topHeight, new.topHeight), (old.listHeight, new.listHeight),
            (old.deckHeight, new.deckHeight), (old.handHeight, new.handHeight),
            (old.playedHeight, new.playedHeight), (old.bottomHeight, new.bottomHeight),
            (old.relatedHeight, new.relatedHeight)
        ]
        return pairs.allSatisfy { abs($1 - $0) <= budget }
    }

    // MARK: - curves

    /// Triangle: dark at both ends, `flashPeak` in the middle. Written as a
    /// function of one progress so a single linear animation drives the whole
    /// flash — an interrupted one cannot be left lit, because the view that
    /// carries it is gone and every value it could have held is bounded by
    /// this curve.
    static func flashOpacity(_ progress: CGFloat) -> CGFloat {
        let p = max(0, min(1, progress))
        return flashPeak * (1 - abs(2 * p - 1))
    }

    static func rowTransition(rowHeight: CGFloat) -> AnyTransition {
        .modifier(active: RowCollapse(progress: 0, rowHeight: rowHeight),
                  identity: RowCollapse(progress: 1, rowHeight: rowHeight))
    }
}

/// HDT's `LayoutTransform` + `ScaleY`, which is the part that makes the rows
/// below move continuously: the *layout* height shrinks, so the stack re-lays
/// out every frame. The row's own bitmap is only scaled and faded — its raster
/// key never sees `progress`, so nothing is redrawn while it plays.
struct RowCollapse: ViewModifier, Animatable {
    var progress: CGFloat
    let rowHeight: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let p = max(0, min(1, progress))
        return content
            .scaleEffect(x: 1, y: p, anchor: .top)
            .frame(height: rowHeight * p, alignment: .top)
            .opacity(Double(p))
            .clipped()
            // The hover sensor reads this back and shrinks with the row, so a
            // row on its way out stops being the view under the mouse.
            .environment(\.trackerRowMotion, p)
    }
}

/// The draw flash: one rectangle over the row, its alpha shaped by
/// `TrackerMotion.flashOpacity`. It is a sibling of the row bitmap, never part
/// of it, so it cannot enter `CardRowRasterKey`; and it is a view rather than a
/// `CALayer` handed to `addSublayer`, so flashing twice cannot leave two of
/// them behind the way `CardBar` does.
struct TrackerRowFlash: View {
    let width: CGFloat
    let height: CGFloat

    @SwiftUI.State private var progress: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(TrackerMotion.flashColor)
            .frame(width: width, height: height)
            .modifier(FlashCurve(progress: progress))
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(TrackerMotion.flashAnimation) {
                    progress = 1
                }
            }
    }
}

struct FlashCurve: ViewModifier, Animatable {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content.opacity(Double(TrackerMotion.flashOpacity(progress)))
    }
}

/// 1 while a row sits still, the collapse / expand progress while it moves.
private struct TrackerRowMotionKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    var trackerRowMotion: CGFloat {
        get { self[TrackerRowMotionKey.self] }
        set { self[TrackerRowMotionKey.self] = newValue }
    }
}
