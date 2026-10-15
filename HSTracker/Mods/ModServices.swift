//
//  ModServices.swift
//  HSTracker
//
//  Fork：ModKit 口子 5（宿主服务）和口子 4 的设置存取在 app 里的实现。每个 mod 一份（`ModManager` 按 manifest 造）。
//

import AppKit
import Foundation
import ModKit
import SwiftUI

final class ModServices: ModHostServices {
    let manifest: ModManifest
    let settings: any ModSettings
    let dataDirectory: URL

    init(manifest: ModManifest, settings: (any ModSettings)? = nil) {
        self.manifest = manifest
        self.settings = settings ?? ModSettingsStore(modID: manifest.id)
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        dataDirectory = support.appendingPathComponent("HSTracker/ModData/\(manifest.id)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
    }

    var hostVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    func log(_ level: ModLogLevel, _ message: String) {
        let line = "[mod \(manifest.id)] \(message)"
        switch level {
        case .debug: logger.debug(line)
        case .info: logger.info(line)
        case .warning: logger.warning(line)
        case .error: logger.error(line)
        @unknown default: logger.info(line)
        }
    }

    func cardName(_ cardId: String) -> String? {
        Cards.any(byId: cardId)?.name
    }

    var trackerStyle: ModTrackerStyle { Self.trackerStyle }

    static let trackerStyle = ModTrackerStyle(
        base: TrackerBarStyle.base, gold: TrackerBarStyle.gold, line: TrackerBarStyle.line,
        rowLine: TrackerBarStyle.rowLine, text: TrackerBarStyle.text, star: TrackerBarStyle.star,
        skull: TrackerBarStyle.skull, flame: TrackerBarStyle.flame,
        dimContentOpacity: Double(TrackerBarStyle.dimContent), digitFontName: TrackerBarStyle.digitFontName,
        highlights: [.teal: TrackerBarStyle.highlight(.teal), .orange: TrackerBarStyle.highlight(.orange),
                     .green: TrackerBarStyle.highlight(.green)].compactMapValues { $0 })
}

/// mod 的设置：存在 UserDefaults 的 `mod.<mod id>.<键>` 下。值变了在主线程通知这个键的观察者
/// （在主线程改的当场通知，和 `Settings` 的通知一样同步；别的线程改的投 `main.async`）
final class ModSettingsStore: ModSettings {
    let modID: String
    private let defaults: UserDefaults
    private let lock = NSLock()
    private var observers: [String: [Int: @MainActor () -> Void]] = [:]
    private var nextToken = 0

    init(modID: String, defaults: UserDefaults = .standard) {
        self.modID = modID
        self.defaults = defaults
    }

    static func defaultsKey(modID: String, key: String) -> String { "mod.\(modID).\(key)" }

    private func fullKey(_ key: String) -> String { Self.defaultsKey(modID: modID, key: key) }

    func value(forKey key: String) -> ModSettingValue? {
        Self.decode(defaults.object(forKey: fullKey(key)))
    }

    func setValue(_ value: ModSettingValue?, forKey key: String) {
        guard self.value(forKey: key) != value else { return }
        if let value {
            defaults.set(Self.encode(value), forKey: fullKey(key))
        } else {
            defaults.removeObject(forKey: fullKey(key))
        }
        notify(key)
    }

    func observe(_ key: String, handler: @escaping @MainActor () -> Void) -> ModObservation {
        lock.lock()
        nextToken += 1
        let token = nextToken
        observers[key, default: [:]][token] = handler
        lock.unlock()
        return ModObservation { [weak self] in
            guard let self else { return }
            self.lock.lock()
            self.observers[key]?[token] = nil
            self.lock.unlock()
        }
    }

    private func notify(_ key: String) {
        let fire = { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let handlers = (self.observers[key] ?? [:]).sorted { $0.key < $1.key }.map { $0.value }
            self.lock.unlock()
            MainActor.assumeIsolated {
                for handler in handlers { handler() }
            }
        }
        if Thread.isMainThread {
            fire()
        } else {
            DispatchQueue.main.async(execute: fire)
        }
    }

    private static func encode(_ value: ModSettingValue) -> Any {
        switch value {
        case .bool(let v): return v
        case .int(let v): return v
        case .double(let v): return v
        case .string(let v): return v
        @unknown default: return String(describing: value)
        }
    }

    /// plist 里布尔存成 CFBoolean，整数和小数靠 NSNumber 的类型区分
    private static func decode(_ object: Any?) -> ModSettingValue? {
        switch object {
        case let s as String:
            return .string(s)
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return .bool(n.boolValue) }
            if CFNumberIsFloatType(n) { return .double(n.doubleValue) }
            return .int(n.intValue)
        default:
            return nil
        }
    }

    /// 把宿主老设置键的值抄到 mod 的命名空间（只在 mod 的键还没存过时抄；老键留着，旧版 HSTracker 照常读）
    func migrate(from legacyKey: String, to key: String) {
        guard defaults.object(forKey: fullKey(key)) == nil,
              let value = Self.decode(defaults.object(forKey: legacyKey)) else { return }
        defaults.set(Self.encode(value), forKey: fullKey(key))
    }
}
