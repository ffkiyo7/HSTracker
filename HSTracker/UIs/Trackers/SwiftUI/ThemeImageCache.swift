//
//  ThemeImageCache.swift
//  HSTracker
//
//  Process-wide decoded theme PNGs. CardBar.add(themeElement:) re-reads
//  from disk on every draw; this is the replacement.
//

import AppKit
import Foundation

enum ThemeImageCache {
    private static let lock = UnfairLock()
    private static var images: [String: NSImage] = [:]
    private static var prepared = Set<String>()
    private static var requiredOK: [String: Bool] = [:]
    private static var optionalFramesOK: [String: Bool] = [:]
    private static var optionalGemsOK: [String: Bool] = [:]
    private static var optionalCountBoxesOK: [String: Bool] = [:]
    private static var smallCards: [String: NSImage] = [:]
    private static var smallCardsMissing = Set<String>()

    private static let requiredFiles = [
        "frame.png", "gem.png", "countbox.png", "dark.png", "fade.png",
        "icon_created.png", "icon_bad_multiple.png", "icon_legendary.png",
        "frame_mask.png", "keeprate_box.png", "keeprate_active_box.png",
        "highlight_teal.png", "highlight_orange.png", "highlight_green.png"
    ]
    private static let optionalFrameFiles = [
        "frame_common.png", "frame_rare.png", "frame_epic.png", "frame_legendary.png"
    ]
    private static let optionalGemFiles = [
        "gem_common.png", "gem_rare.png", "gem_epic.png", "gem_legendary.png"
    ]
    private static let optionalCountBoxFiles = [
        "countbox_common.png", "countbox_rare.png", "countbox_epic.png",
        "countbox_legendary.png"
    ]

    /// Bundle theme PNGs never change at runtime, so nothing is evicted.
    /// Switching theme just addresses a different `themeDir` key; the previous
    /// theme stays resident.
    static func prepare(theme: String) {
        lock.around {
            prepareLocked(theme: theme)
        }
    }

    static func image(theme: String, file: String) -> NSImage? {
        lock.around {
            prepareLocked(theme: theme)
            return images[key(theme, file)]
        }
    }

    static func hasRequired(theme: String) -> Bool {
        lock.around {
            prepareLocked(theme: theme)
            return requiredOK[theme] ?? false
        }
    }

    static func hasOptionalFrames(theme: String) -> Bool {
        lock.around {
            prepareLocked(theme: theme)
            return optionalFramesOK[theme] ?? false
        }
    }

    static func hasOptionalGems(theme: String) -> Bool {
        lock.around {
            prepareLocked(theme: theme)
            return optionalGemsOK[theme] ?? false
        }
    }

    static func hasOptionalCountBoxes(theme: String) -> Bool {
        lock.around {
            prepareLocked(theme: theme)
            return optionalCountBoxesOK[theme] ?? false
        }
    }

    static func smallCard(id: String) -> NSImage? {
        lock.around {
            if let cached = smallCards[id] {
                return cached
            }
            if smallCardsMissing.contains(id) {
                return nil
            }
            guard let rp = Bundle.main.resourcePath else {
                smallCardsMissing.insert(id)
                return nil
            }
            let path = "\(rp)/Resources/Small/\(id).png"
            if let image = NSImage(contentsOfFile: path) {
                smallCards[id] = image
                return image
            }
            smallCardsMissing.insert(id)
            return nil
        }
    }

    private static func prepareLocked(theme: String) {
        if prepared.contains(theme) {
            return
        }
        prepared.insert(theme)

        guard let rp = Bundle.main.resourcePath else {
            requiredOK[theme] = false
            optionalFramesOK[theme] = false
            optionalGemsOK[theme] = false
            optionalCountBoxesOK[theme] = false
            return
        }
        let dir = "\(rp)/Resources/Themes/Bars/\(theme)"
        let manager = FileManager.default

        if let files = try? manager.contentsOfDirectory(atPath: dir) {
            for name in files where name.lowercased().hasSuffix(".png") {
                let path = "\(dir)/\(name)"
                if let image = NSImage(contentsOfFile: path) {
                    images[key(theme, name)] = image
                }
            }
        }

        func allExist(_ names: [String]) -> Bool {
            names.allSatisfy { manager.fileExists(atPath: "\(dir)/\($0)") }
        }
        requiredOK[theme] = allExist(requiredFiles)
        optionalFramesOK[theme] = allExist(optionalFrameFiles)
        optionalGemsOK[theme] = allExist(optionalGemFiles)
        optionalCountBoxesOK[theme] = allExist(optionalCountBoxFiles)
    }

    private static func key(_ theme: String, _ file: String) -> String {
        "\(theme)/\(file)"
    }
}
