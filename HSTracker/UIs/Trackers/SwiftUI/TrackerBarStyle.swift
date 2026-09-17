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
    static let starSize: CGFloat = 10
    /// D3-b (`.D` / `.D.fe75` in the sheet): the art runs from the cost cell's
    /// trailing edge to the end of the bar — 149 of the 171 reference pixels —
    /// and the panel base lies over it, solid for the first tenth and gone by
    /// three quarters. Both fractions are of the *art strip*, not of the bar.
    static let artSolidFraction: CGFloat = 0.10
    static let artClearFraction: CGFloat = 0.75
    /// `.D .row .name`: the name's back half can sit on lit art now.
    static let nameShadowNear: CGFloat = 2
    static let nameShadowFar: CGFloat = 4
    /// `.dim` in the D2 sheet: count <= 0 / jousted rows.
    static let dimContent: CGFloat = 0.45
    static let dimCost: CGFloat = 0.55

    // MARK: - three-row header and section header (`.hdr` / `.sec` in the D3 sheet)

    /// A header line is exactly one card row; a section header is one notch
    /// taller. Everything else here is in the same reference pixels.
    static let sectionRowHeight: CGFloat = 22
    static let headerPadding: CGFloat = 6
    static let headerMiddleColumn: CGFloat = 40
    static let headerTrailingColumn: CGFloat = 46
    static let headerLabelFontSize: CGFloat = 9.5
    static let headerDigitFontSize: CGFloat = 10
    static let headerIcon: CGFloat = 11
    static let headerIconGap: CGFloat = 4
    static let headerRecordGap: CGFloat = 3
    static let sectionFontSize: CGFloat = 10
    /// `letter-spacing: .04em` on `.sec`.
    static let sectionTracking: CGFloat = 0.04
    static let sectionCountGap: CGFloat = 3
    static let sectionSideColumn: CGFloat = 22
    static let chevron: CGFloat = 6
    static let chevronStroke: CGFloat = 1.5
    static let chevronOpacity: CGFloat = 0.8

    /// Belwe for every numeral, as in the D2 sheet's `--num`.
    static let digitFontName = "Belwe Bd BT"

    /// Labels and section names: the theme face (AR LisuGB in Chinese).
    static func label(_ u: CGFloat, size: CGFloat) -> Font {
        Font.custom(TrackerTextFont.name, size: size * u)
    }

    /// Every numeral on the panel.
    static func digits(_ u: CGFloat, size: CGFloat) -> Font {
        Font.custom(digitFontName, size: size * u)
    }
}

/// The count box's legendary marker. It used to be `Text("★")` in the system
/// font — the one face the panel is not allowed to show — so the star is drawn.
struct TrackerStar: Shape {
    func path(in rect: CGRect) -> Path {
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        // 0.382 = 1 / phi^2, the inner radius of a regular pentagram.
        let inner = outer * 0.382
        var path = Path()
        for step in 0..<10 {
            let radius = step.isMultiple(of: 2) ? outer : inner
            let angle = -CGFloat.pi / 2 + CGFloat(step) * .pi / 5
            let point = CGPoint(x: centre.x + radius * cos(angle),
                                y: centre.y + radius * sin(angle))
            if step == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}

/// `.sec .chev`: the trailing and bottom edges of a square, stroked and turned
/// 45 degrees, which is the sheet's collapse arrow.
struct TrackerChevron: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        return path
    }
}

/// True inside the hand section. D2 dropped the in-hand green there (it only
/// says something in the deck section), and the row view has to know which
/// section it is in — `TrackerCardListView` between the two is not part of
/// this change, so the flag travels by environment.
private struct TrackerHandSectionKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var trackerHandSection: Bool {
        get { self[TrackerHandSectionKey.self] }
        set { self[TrackerHandSectionKey.self] = newValue }
    }
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

    /// Alpha of the panel base for the `tracker_opacity` setting (0...100).
    /// The setting's default is 0: on the theme-PNG path that meant "no extra
    /// black tint under the opaque bars", so 0 must not erase the D2 base —
    /// it is treated as "unset" and paints the base in full. Any explicit value
    /// above 0 is applied as-is.
    static func baseOpacity(setting: Double) -> CGFloat {
        guard setting > 0 else { return 1 }
        return CGFloat(min(setting, 100) / 100)
    }

    /// V2a put the whole panel on one row grid: a three-row header line *is* a
    /// card row, and a section header is the 22 : 21 notch of the D3 sheet's
    /// `.sec`. Nothing keeps the old 40 : 34 ratio to a card row any more.
    static func sectionHeaderHeight(rowHeight: CGFloat) -> CGFloat {
        max(rowHeight * TrackerBarStyle.sectionRowHeight / Self.rowHeight, 1)
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

/// The session recap window's row shade, as a drawn gradient rather than the
/// retired `fade.png`. Kept as an `NSImage` because that window scales it in two
/// pieces. **Card rows no longer use it** — D3-b gave them their own full-bleed
/// geometry (`TrackerBarStyle.artSolidFraction` / `artClearFraction`), so the two
/// numbers below are the recap's own and are not derived from the bar any more.
enum TrackerFade {
    /// Where the shaded strip starts, as a fraction of the row width.
    static let startFraction: CGFloat = 1 - 100.0 / 171.0
    /// Fraction of the gradient whose alpha is still flat.
    static let opaqueFraction: CGFloat = 0.35

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
