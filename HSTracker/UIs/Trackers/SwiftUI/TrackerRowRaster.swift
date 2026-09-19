//
//  TrackerRowRaster.swift
//  HSTracker
//
//  Perf P2: a vector card row compiles into a dozen CALayers (two text
//  shadows, a gradient, several group opacities, two clips), and the render
//  server has to composite that tree over a 165 Hz game every time one row
//  changes. The drawing is unchanged; it is rasterised once per distinct
//  appearance inside the process and the row becomes a single flat bitmap.
//

import AppKit
import SwiftUI

/// Perf P2 runtime diagnostics. They exist so a stuck session can be bisected
/// in place — `defaults write net.hearthsim.hstracker <key> -bool true`, restart
/// HSTracker — without a rebuild and without a preferences UI. Read straight
/// from `UserDefaults` on every row so a value that changes mid-session takes
/// effect on the next refresh; they also reach the rows as stored properties,
/// so a changed flag yields a different row value and a different raster key.
enum TrackerDiagnostics {
    /// ① `tracker_perf_flatten_rows` (default **true**): off falls back to the
    /// V1 / V2 drawing, one CALayer subtree per row.
    static var flattensRows: Bool { Settings.trackerFlattenRows }
    /// ② `tracker_perf_no_text_shadow` (default false).
    static var drawsTextShadow: Bool { !Settings.trackerNoTextShadow }
    /// ③ `tracker_perf_no_card_art` (default false).
    static var drawsArt: Bool { !Settings.trackerNoCardArt }
    /// ④ `tracker_perf_force_opaque` (default false).
    static var forcesOpaquePanel: Bool { Settings.trackerForceOpaquePanel }

    /// The panel base's alpha with switch ④ folded in.
    static func panelOpacity(setting: Double) -> CGFloat {
        forcesOpaquePanel ? 1 : TrackerMetrics.baseOpacity(setting: setting)
    }
}

/// Everything that decides what a card row looks like. Equal keys are the same
/// picture, so one bitmap serves every row that matches and nothing is redrawn
/// until one of these changes.
struct CardRowRasterKey: Hashable {
    var cardId: String
    var name: String
    var cost: Int
    var showsCost: Bool
    var count: Int
    var rarity: Rarity
    var showRarityColors: Bool
    var dimmed: Bool
    var created: Bool
    var countBox: Bool
    /// The resolved name colour, packed, rather than the settings behind it:
    /// `Card.textColor()` reads four of them plus a user-chosen colour.
    var nameColor: UInt32
    var highlight: Int
    var hasTile: Bool
    var rowHeight: CGFloat
    var barWidth: CGFloat
    var baseOpacity: CGFloat
    var scale: CGFloat
    var drawsArt: Bool
    var drawsTextShadow: Bool
}

/// The row bitmaps. Main-thread only: it is read and filled from `body`.
@MainActor
enum TrackerRowRaster {
    private final class Box: NSObject {
        let key: CardRowRasterKey

        init(_ key: CardRowRasterKey) {
            self.key = key
        }

        override var hash: Int { key.hashValue }

        override func isEqual(_ object: Any?) -> Bool {
            (object as? Box)?.key == key
        }
    }

    /// A `.big` row on a 4K window is about 230 KB at 2x, so the live set of
    /// two panels is roughly 16 MB. `NSCache` evicts by cost and under memory
    /// pressure; a miss only costs one re-render.
    private static let cache: NSCache<Box, NSImage> = {
        let cache = NSCache<Box, NSImage>()
        cache.totalCostLimit = 32 * 1024 * 1024
        return cache
    }()

    /// Test probes: how many rasters were drawn versus asked for.
    private(set) static var renders = 0
    private(set) static var lookups = 0

    static func image<Content: View>(for key: CardRowRasterKey,
                                     content: () -> Content) -> NSImage? {
        lookups += 1
        let box = Box(key)
        if let hit = cache.object(forKey: box) {
            return hit
        }
        guard key.barWidth >= 1, key.rowHeight >= 1, key.scale >= 1 else {
            return nil
        }
        let renderer = ImageRenderer(content: content())
        renderer.scale = key.scale
        guard let cgImage = renderer.cgImage else {
            return nil
        }
        // The point size is pinned to the row's own frame so the bitmap lays
        // out exactly where the vector row did, whatever ImageRenderer made of
        // the content's ideal size.
        let image = NSImage(cgImage: cgImage,
                            size: NSSize(width: key.barWidth, height: key.rowHeight))
        renders += 1
        cache.setObject(image, forKey: box, cost: cgImage.bytesPerRow * cgImage.height)
        return image
    }

    static func reset() {
        cache.removeAllObjects()
        renders = 0
        lookups = 0
    }
}
