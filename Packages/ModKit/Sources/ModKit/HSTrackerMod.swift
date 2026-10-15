//
//  HSTrackerMod.swift
//  ModKit
//
//  mod 的入口和它交给 HSTracker 的东西。
//
//  一个 mod 是一个依赖 ModKit 的 Swift 包，编出来是一个动态库，导出一个 C 符号（`ModEntryPoint.symbolName`）：
//
//      @_cdecl("hstracker_mod_entry")
//      public func hstrackerModEntry() -> UnsafeMutableRawPointer {
//          ModRegistration(manifest: ModManifest(id: "red-dragon", name: "红龙辅助", version: "1.0")) {
//              RedDragonMod()
//          }.retainedPointer()
//      }
//
//  加载器（HSTracker）：dlopen → dlsym 这个符号 → `ModRegistration.take(_:)` → 先比 `manifest.modKitVersion`
//  （`ModKitVersion.runtime.compatibility(withModBuiltAgainst:)`），对得上才调 `makeMod()`，
//  再在主线程调 `activate(_:)`，拿回 `ModContributions` 接到 5 个口子上。
//  mod 按更新的次版本编、用了宿主 ModKit 没有的符号时，dlopen 本身就会失败，加载器按「宿主太旧」处理。
//
//  含 Swift 代码的库加载后卸不掉：设置里关掉某个 mod 下次启动才生效，换 mod 版本要重启 HSTracker。
//

import Foundation

/// mod 动态库导出的入口
public enum ModEntryPoint {
    /// 入口符号名（`@_cdecl` 用的就是它）
    public static let symbolName = "hstracker_mod_entry"
    /// 入口函数的类型：返回 `ModRegistration.retainedPointer()`
    public typealias Function = @convention(c) () -> UnsafeMutableRawPointer
}

/// mod 的身份。`id` 决定设置键的命名空间和数据目录，定了就别改
public struct ModManifest: Hashable, Sendable {
    /// 小写字母、数字、`-`、`.`，以字母开头，如 `red-dragon`（`isValidID`）
    public var id: String
    /// 设置窗 mod 列表里显示的名字
    public var name: String
    /// mod 自己的版本，只用于显示和日志
    public var version: String
    /// mod 编译时的 ModKit 版本，加载器拿它判兼容
    public var modKitVersion: ModKitVersion

    public init(id: String, name: String, version: String, modKitVersion: ModKitVersion) {
        self.id = id
        self.name = name
        self.version = version
        self.modKitVersion = modKitVersion
    }

    /// mod 用这个：`modKitVersion` 取 mod 编译时的 ModKit 版本（编进 mod，不随宿主变）
    @_alwaysEmitIntoClient
    public init(id: String, name: String, version: String) {
        self.init(id: id, name: name, version: version, modKitVersion: .compileTime)
    }

    public static func isValidID(_ id: String) -> Bool {
        guard let first = id.unicodeScalars.first, ("a"..."z").contains(first), id.count <= 64 else { return false }
        return id.unicodeScalars.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-" || $0 == "." }
    }
}

/// 入口函数交回来的登记：身份 + 造 mod 的工厂。加载器先看身份、判完版本再造
public final class ModRegistration {
    public let manifest: ModManifest
    private let factory: () -> any HSTrackerMod

    public init(manifest: ModManifest, makeMod: @escaping () -> any HSTrackerMod) {
        self.manifest = manifest
        self.factory = makeMod
    }

    public func makeMod() -> any HSTrackerMod {
        return factory()
    }

    /// mod 的入口函数返回它（+1 引用，交给加载器）
    public func retainedPointer() -> UnsafeMutableRawPointer {
        return Unmanaged.passRetained(self).toOpaque()
    }

    /// 加载器用：接过入口函数返回的指针（消耗那 +1 引用，每个指针只能调一次）
    public static func take(_ pointer: UnsafeMutableRawPointer) -> ModRegistration {
        return Unmanaged<ModRegistration>.fromOpaque(pointer).takeRetainedValue()
    }
}

/// mod 本体
public protocol HSTrackerMod: AnyObject {
    /// 主线程，启动时加载后调一次。返回要接的口子；抛错 = 这个 mod 本次不启用（错误记日志、设置页提示）
    @MainActor
    func activate(_ host: any ModHostServices) throws -> ModContributions

    /// 主线程，HSTracker 退出前调。停掉自己的定时器、热键之类（库卸不掉，不必清内存）
    @MainActor
    func deactivate()
}

extension HSTrackerMod {
    @MainActor
    public func deactivate() {}
}

/// mod 交给 HSTracker 的东西，对应 5 个口子里的 3 个（读对局状态跟着对局事件给，宿主服务在 `activate` 时给）。
/// 不接的口子留 nil
public struct ModContributions {
    /// 口子 1、2：对局事件，回调里读对局状态
    public var gameEvents: (any ModGameEventHandler)?
    /// 口子 3：overlay 图层
    public var overlay: (any ModOverlayProvider)?
    /// 口子 4：设置页
    public var preferencePane: ModPreferencePane?

    public init(gameEvents: (any ModGameEventHandler)? = nil,
                overlay: (any ModOverlayProvider)? = nil,
                preferencePane: ModPreferencePane? = nil) {
        self.gameEvents = gameEvents
        self.overlay = overlay
        self.preferencePane = preferencePane
    }
}
