//
//  TrackerBarStyle.swift
//  HSTracker
//
//  The D2 visual spec (docs/tasks/phase2-v-visual-redesign.md) and the
//  window-proportional sizing of PLAN 2.8, in one place: every number the
//  vector card rows, the section headers and the panel background use.
//

import AppKit
import SwiftUI

/// D2 palette. All sizes elsewhere are expressed in `u`, one logical pixel of
/// the reference 1920x1080 layout, so the whole panel scales by one factor.
enum TrackerBarStyle {
    /// Panel base. Multiplied by `Settings.trackerOpacity` where it is painted.
    static let base = Color(red: 0x1B / 255, green: 0x14 / 255, blue: 0x10 / 255)
    static let baseNS = NSColor(red: 0x1B / 255, green: 0x14 / 255, blue: 0x10 / 255, alpha: 1)
    /// Structural gold: 28% for element borders, 10% for the row hairline.
    static let gold = Color(red: 0xD6 / 255, green: 0xB2 / 255, blue: 0x6E / 255)
    static let line = gold.opacity(0.28)
    static let rowLine = gold.opacity(0.10)
    static let text = Color(red: 0xF4 / 255, green: 0xEA / 255, blue: 0xD4 / 255)
    static let countBox = Color.black.opacity(0.5)
    static let star = Color(red: 0xFF / 255, green: 0xB6 / 255, blue: 0x41 / 255)

    /// Cost cell, tinted by rarity (D2 chose these for colour-blind separation).
    static func cost(_ rarity: Rarity) -> Color {
        switch rarity {
        case .rare: return Color(red: 0x3B / 255, green: 0x6B / 255, blue: 0x8F / 255)
        case .epic: return Color(red: 0x9A / 255, green: 0x5F / 255, blue: 0x8C / 255)
        case .legendary: return Color(red: 0xA8 / 255, green: 0x76 / 255, blue: 0x2C / 255)
        default: return Color(red: 0x5A / 255, green: 0x56 / 255, blue: 0x50 / 255)
        }
    }

    static func highlight(_ color: HighlightColor) -> Color? {
        switch color {
        case .teal: return Color(red: 0x3F / 255, green: 0xC7 / 255, blue: 0xC0 / 255)
        case .orange: return Color(red: 0xFF / 255, green: 0x9A / 255, blue: 0x3C / 255)
        case .green: return Color(red: 0x5D / 255, green: 0xD1 / 255, blue: 0x62 / 255)
        case .none: return nil
        }
    }

    // MARK: - row geometry, in reference pixels (row height 21, bar width 171)

    static let costWidth: CGFloat = 22
    static let namePadLeading: CGFloat = 6
    static let namePadTrailing: CGFloat = 8
    static let namePadBoxed: CGFloat = 24
    static let boxWidth: CGFloat = 20
    static let hairline: CGFloat = 1
    static let nameFontSize: CGFloat = 10
    static let costFontSize: CGFloat = 12
    static let countFontSize: CGFloat = 11
    static let createdMark: CGFloat = 6
    /// Art strip as a fraction of the bar width (100 / 171 in the D2 sheet), and
    /// the part of it the base colour still covers fully.
    static let artFraction: CGFloat = 100.0 / 171.0
    static let artFadeFraction: CGFloat = 0.35
    /// `.dim` in the D2 sheet: count <= 0 / jousted rows.
    static let dimContent: CGFloat = 0.45
    static let dimCost: CGFloat = 0.55

    /// Belwe for every numeral, as in the D2 sheet's `--num`.
    static let digitFontName = "Belwe Bd BT"
}

/// Panel and row size, derived from the Hearthstone window instead of the
/// absolute point values of `CardSize` (PLAN 2.8).
enum TrackerMetrics {
    /// Firestone's measured 171 x 21 (docs/research/firestone-overlay.md 7.1).
    static let panelWidth: CGFloat = 171
    static let rowHeight: CGFloat = 21
    static let aspect: CGFloat = panelWidth / rowHeight

    /// Firestone sits at 8.9% of window width and 1.94% of window height; on
    /// 16:9 the two agree, so the smaller one is taken and the other derived.
    /// That keeps the bar aspect exact on every window shape and stops an
    /// ultra-wide window from producing an absurdly wide panel.
    static let widthFraction: CGFloat = 0.089
    static let heightFraction: CGFloat = 0.0194

    /// `.big` is `Settings.cardSize`'s default, so it carries the Firestone
    /// size; the other four are notches around it.
    static func multiplier(_ size: CardSize) -> CGFloat {
        switch size {
        case .tiny: return 0.70
        case .small: return 0.85
        case .medium: return 0.92
        case .big: return 1.00
        case .huge: return 1.25
        }
    }

    /// Panel width for a Hearthstone window of this size, at the given preset.
    static func panelWidth(windowWidth: CGFloat,
                           windowHeight: CGFloat,
                           cardSize: CardSize) -> CGFloat {
        let byWidth = windowWidth * widthFraction
        let byHeight = windowHeight * heightFraction * aspect
        let width = min(byWidth, byHeight) * multiplier(cardSize)
        return max(width, rowHeight * aspect * 0.5)
    }

    /// The tracker window's own width *is* the panel width, so the row height
    /// follows from it and the aspect is locked by construction.
    static func rowHeight(panelWidth: CGFloat) -> CGFloat {
        max(panelWidth / aspect, 1)
    }

    /// The three-row header and the section headers keep the 40 : 34 ratio to a
    /// card row they had on the theme-PNG path; squeezing them onto the 21-px
    /// grid is V2.
    static func headerLineHeight(rowHeight: CGFloat) -> CGFloat {
        max(round(rowHeight * 40 / 34), 1)
    }
}

/// The card-name font. Language only — the four bar themes are retired, so
/// there is no per-theme face any more.
enum TrackerTextFont {
    static var name: String {
        if Settings.isSimplifiedChinese {
            return "AR LisuGB Medium"
        } else if Settings.isAsianLanguage {
            return "NanumGothic"
        } else if Settings.isCyrillicLanguage {
            return "Benguiat Rus"
        }
        return TrackerBarStyle.digitFontName
    }
}

/// The shade a card row lays over its art, as a drawn gradient rather than the
/// retired `fade.png`. Kept as an `NSImage` because the session recap window
/// scales it in two pieces the way the tracker header does.
enum TrackerFade {
    /// Where the art strip starts, as a fraction of the bar width.
    static var startFraction: CGFloat { 1 - TrackerBarStyle.artFraction }
    /// Fraction of the gradient whose alpha is still flat.
    static let opaqueFraction: CGFloat = TrackerBarStyle.artFadeFraction

    private static var cached: NSImage?

    static var image: NSImage? {
        if let cached {
            return cached
        }
        let size = NSSize(width: 128, height: 1)
        let image = NSImage(size: size)
        image.lockFocus()
        let gradient = NSGradient(colors: [TrackerBarStyle.baseNS,
                                           TrackerBarStyle.baseNS,
                                           TrackerBarStyle.baseNS.withAlphaComponent(0)],
                                  atLocations: [0, opaqueFraction, 1],
                                  colorSpace: .deviceRGB)
        gradient?.draw(in: NSRect(origin: .zero, size: size), angle: 0)
        image.unlockFocus()
        image.resizingMode = .stretch
        cached = image
        return image
    }
}
