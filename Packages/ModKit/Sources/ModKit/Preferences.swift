//
//  Preferences.swift
//  ModKit
//
//  口子 4：设置页，和 mod 自己的设置存取。
//
//  - 设置页：mod 给标题、图标、搜索词和 SwiftUI 视图，宿主包成设置窗里的一页（宽度由设置窗定）。
//  - 设置存取：`ModSettings`（`ModHostServices.settings`）。键只写 mod 自己的短名，宿主自动加 mod 前缀
//    （按 `ModManifest.id` 分命名空间），mod 之间、mod 和宿主之间不会撞键。
//    读写走它而不是 @AppStorage / UserDefaults：它会通知观察者，热切换靠这个。
//

import AppKit
import SwiftUI

/// 设置窗里 mod 的那一页
public struct ModPreferencePane {
    public var title: String
    public var icon: NSImage
    /// 设置窗搜索框能搜到这一页的词（页里各项的标题、说明）
    public var searchTerms: [String]
    /// 主线程，打开这一页时调
    public var makeView: @MainActor () -> AnyView

    public init(title: String, icon: NSImage, searchTerms: [String] = [],
                makeView: @escaping @MainActor () -> AnyView) {
        self.title = title
        self.icon = icon
        self.searchTerms = searchTerms
        self.makeView = makeView
    }
}

/// 一个设置值
public enum ModSettingValue: Hashable, Sendable {
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
}

/// mod 的设置存取（键已按 mod 分好命名空间）。读写任何线程都可以；观察回调在主线程
public protocol ModSettings: AnyObject {
    /// 没存过时为 nil
    func value(forKey key: String) -> ModSettingValue?
    /// nil = 删掉，回到默认值。值变了才通知观察者
    func setValue(_ value: ModSettingValue?, forKey key: String)
    /// 这个键变了（不管是谁改的）时在主线程调 `handler`。拿着返回值才一直有效，释放或 `cancel()` 后停止
    func observe(_ key: String, handler: @escaping @MainActor () -> Void) -> ModObservation
}

extension ModSettings {
    public func bool(_ key: String, default fallback: Bool) -> Bool {
        if case .bool(let v)? = value(forKey: key) { return v }
        return fallback
    }

    public func int(_ key: String, default fallback: Int) -> Int {
        if case .int(let v)? = value(forKey: key) { return v }
        return fallback
    }

    public func double(_ key: String, default fallback: Double) -> Double {
        switch value(forKey: key) {
        case .double(let v)?: return v
        case .int(let v)?: return Double(v)
        default: return fallback
        }
    }

    public func string(_ key: String, default fallback: String) -> String {
        if case .string(let v)? = value(forKey: key) { return v }
        return fallback
    }

    public func set(_ value: Bool, forKey key: String) { setValue(.bool(value), forKey: key) }
    public func set(_ value: Int, forKey key: String) { setValue(.int(value), forKey: key) }
    public func set(_ value: Double, forKey key: String) { setValue(.double(value), forKey: key) }
    public func set(_ value: String, forKey key: String) { setValue(.string(value), forKey: key) }
}

/// 一次观察。释放时自动取消
public final class ModObservation {
    private let lock = NSLock()
    private var onCancel: (() -> Void)?

    public init(onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
    }

    public func cancel() {
        lock.lock()
        let action = onCancel
        onCancel = nil
        lock.unlock()
        action?()
    }

    deinit {
        cancel()
    }
}
