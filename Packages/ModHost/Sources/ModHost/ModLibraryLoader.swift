//
//  ModLibraryLoader.swift
//  ModHost
//
//  dlopen → dlsym 入口 → 调入口拿 `ModRegistration`。单独成协议，测试里换成假的。
//
//  dlopen 会跑 mod 的初始化代码，所以安全模式、被用户关掉的 mod 一律不走到这一步。
//  含 Swift 代码的库加载后卸不掉：版本不对的 mod 也已经在进程里了，只是不调 `makeMod()`。
//

import Darwin
import Foundation
import ModKit

public enum ModLibraryLoadError: Error, Hashable, Sendable {
    /// dlopen 失败。`missingModKitSymbol` 为真时是 mod 用了宿主 ModKit 没有的符号（按更新的次版本编的）
    case openFailed(message: String, missingModKitSymbol: Bool)
    /// 库里没有 `hstracker_mod_entry`
    case entryPointMissing
}

public protocol ModLibraryLoading {
    /// 打开 `binaryURL`，调入口，交回登记（已接过入口给的 +1 引用）
    func loadRegistration(from binaryURL: URL) throws -> ModRegistration
}

/// 真正的加载：dlopen / dlsym
public struct DynamicLibraryLoader: ModLibraryLoading {
    public init() {}

    public func loadRegistration(from binaryURL: URL) throws -> ModRegistration {
        _ = dlerror()
        // RTLD_LOCAL：mod 之间的符号互不可见；ModKit 是单独的动态库，类型照样只有一份
        guard let handle = dlopen(binaryURL.path, RTLD_NOW | RTLD_LOCAL) else {
            let message = dlerror().map { String(cString: $0) } ?? "dlopen 失败"
            throw ModLibraryLoadError.openFailed(message: message,
                                                 missingModKitSymbol: Self.isMissingModKitSymbol(message))
        }
        guard let symbol = dlsym(handle, ModEntryPoint.symbolName) else {
            // 不 dlclose：Swift 库卸不掉，关了也白关
            throw ModLibraryLoadError.entryPointMissing
        }
        let entry = unsafeBitCast(symbol, to: ModEntryPoint.Function.self)
        return ModRegistration.take(entry())
    }

    /// dyld 的报错形如 `Symbol not found: _$s6ModKit…  Referenced from: … Expected in: …/ModKit.framework/…/ModKit`
    static func isMissingModKitSymbol(_ message: String) -> Bool {
        guard message.contains("Symbol not found") else { return false }
        if let expected = message.range(of: "Expected in:") {
            return message[expected.upperBound...].contains("ModKit")
        }
        return message.contains("6ModKit")
    }
}
