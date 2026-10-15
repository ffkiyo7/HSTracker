//
//  Fixtures.swift
//  ModHostTests
//
//  测试用的假 mod、假加载器、假宿主服务。
//  测试 bundle 自己也导出 `hstracker_mod_entry`，真 dlopen 的测试直接加载测试 bundle 的可执行文件。
//

import Foundation
import ModHost
import ModKit
import SwiftUI
import XCTest

final class FixtureMod: HSTrackerMod {
    struct ActivationError: Error, CustomStringConvertible {
        var description: String { "故意失败" }
    }

    static var deactivations = 0
    let failsActivation: Bool

    init(failsActivation: Bool = false) {
        self.failsActivation = failsActivation
    }

    func activate(_ host: any ModHostServices) throws -> ModContributions {
        if failsActivation { throw ActivationError() }
        return ModContributions()
    }

    func deactivate() {
        FixtureMod.deactivations += 1
    }
}

/// 真 dlopen 测试用：测试 bundle 的入口
@_cdecl("hstracker_mod_entry")
public func hstrackerModEntry() -> UnsafeMutableRawPointer {
    ModRegistration(manifest: ModManifest(id: "fixture", name: "Fixture", version: "1.0")) {
        FixtureMod()
    }.retainedPointer()
}

/// 按文件名给登记或错误，记下 dlopen 了哪些文件
final class FakeLoader: ModLibraryLoading {
    enum Outcome {
        case mod(ModManifest, failsActivation: Bool = false)
        case error(ModLibraryLoadError)
    }

    var outcomes: [String: Outcome] = [:]
    private(set) var opened: [String] = []

    func loadRegistration(from binaryURL: URL) throws -> ModRegistration {
        let name = binaryURL.lastPathComponent
        opened.append(name)
        switch outcomes[name] {
        case .mod(let manifest, let failsActivation)?:
            return ModRegistration(manifest: manifest) { FixtureMod(failsActivation: failsActivation) }
        case .error(let error)?:
            throw error
        case nil:
            throw ModLibraryLoadError.entryPointMissing
        }
    }
}

final class MemorySettings: ModSettings {
    var store: [String: ModSettingValue] = [:]
    func value(forKey key: String) -> ModSettingValue? { store[key] }
    func setValue(_ value: ModSettingValue?, forKey key: String) { store[key] = value }
    func observe(_ key: String, handler: @escaping @MainActor () -> Void) -> ModObservation { ModObservation {} }
}

final class FakeServices: ModHostServices {
    let manifest: ModManifest
    let hostVersion = "test"
    let dataDirectory = FileManager.default.temporaryDirectory
    let settings: any ModSettings = MemorySettings()
    let trackerStyle = ModTrackerStyle(base: .black, gold: .yellow, line: .gray, rowLine: .gray, text: .white,
                                       star: .orange, skull: .white, flame: .red, dimContentOpacity: 0.5,
                                       digitFontName: "Helvetica", highlights: [:])

    init(manifest: ModManifest) { self.manifest = manifest }
    func log(_ level: ModLogLevel, _ message: String) {}
    func cardName(_ cardId: String) -> String? { nil }
}

/// 每个测试一个临时目录：Mods/ 和 ModHost/ 状态目录
final class Sandbox {
    let root: URL
    var mods: URL { root.appendingPathComponent("Mods", isDirectory: true) }
    var state: URL { root.appendingPathComponent("ModHost", isDirectory: true) }

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ModHostTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: mods, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    @discardableResult
    func makeFile(_ relativePath: String, contents: String = "x", in base: URL? = nil) throws -> URL {
        let url = (base ?? mods).appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url)
        return url
    }

    func configuration(disabled: Set<String> = [], forceSafeMode: Bool = false,
                       hostVersion: ModKitVersion = ModKitVersion(major: 1, minor: 0),
                       additional: [URL] = []) -> ModHostConfiguration {
        ModHostConfiguration(modsDirectory: mods, additionalModURLs: additional, stateDirectory: state,
                             disabledModIDs: disabled, schedulesStableMark: false,
                             forceSafeMode: forceSafeMode, hostModKitVersion: hostVersion)
    }
}

func manifest(_ id: String, _ major: Int = 1, _ minor: Int = 0) -> ModManifest {
    ModManifest(id: id, name: id, version: "1.0", modKitVersion: ModKitVersion(major: major, minor: minor))
}
