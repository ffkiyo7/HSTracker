//
//  ModKitVersion.swift
//  ModKit
//
//  「主.次」版本号。规则：
//  - 次版本：只加不改（加类型、加带默认实现的协议要求、加枚举 case）。按 1.0 编的 mod 在 1.3 的 HSTracker 上照常加载。
//  - 主版本：改了或删了已有接口才升。主版本不同的 mod 拒绝加载，设置页提示要按新版重编。
//
//  两个版本号别弄混：
//  - `compileTime`：编进调用方的常量（`@_alwaysEmitIntoClient`），mod 读到的是它编译时那份 ModKit 的版本。
//    `ModManifest` 的便利构造器就是拿它填 `modKitVersion`。
//  - `runtime`：从已加载的 ModKit 动态库里读，HSTracker（加载器）拿它和 mod 声明的版本比。
//  升版本时两处字面量一起改（测试核对它们相等）。
//

/// ModKit 的「主.次」版本
@frozen
public struct ModKitVersion: Hashable, Comparable, CustomStringConvertible, Sendable {
    public let major: Int
    public let minor: Int

    @inlinable
    public init(major: Int, minor: Int) {
        self.major = major
        self.minor = minor
    }

    /// 调用方编译时那份 ModKit 的版本（编进调用方，不随运行时的 ModKit 变）
    @_alwaysEmitIntoClient
    public static var compileTime: ModKitVersion { ModKitVersion(major: 1, minor: 0) }

    /// 进程里实际加载的 ModKit 的版本
    public static var runtime: ModKitVersion { ModKitVersion(major: 1, minor: 0) }

    public var description: String { "\(major).\(minor)" }

    public static func < (lhs: ModKitVersion, rhs: ModKitVersion) -> Bool {
        (lhs.major, lhs.minor) < (rhs.major, rhs.minor)
    }

    /// 宿主（`self` 是宿主运行时的 ModKit 版本）能不能加载按 `modVersion` 编的 mod
    public func compatibility(withModBuiltAgainst modVersion: ModKitVersion) -> ModCompatibility {
        if modVersion.major != major { return .majorMismatch }
        if modVersion.minor > minor { return .hostTooOld }
        return .compatible
    }
}

/// 加载前的版本判定结果
public enum ModCompatibility: Hashable, Sendable {
    case compatible
    /// 主版本不同：接口改过，mod 要按宿主的 ModKit 重编
    case majorMismatch
    /// mod 按更新的次版本编，可能用到宿主没有的接口：要更新 HSTracker
    case hostTooOld
}
