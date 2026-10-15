//
//  ModHostTests.swift
//  ModHostTests
//
//  每次 `ModHost(...)` + `loadMods()` 相当于一次启动；没调 `markLaunchStable()` / `shutdown()` 就换下一个 = 上次启动很快崩了。
//

import Foundation
import ModHost
import ModKit
import XCTest

@MainActor
final class ModHostTests: XCTestCase {

    private func launch(_ box: Sandbox, _ loader: FakeLoader, _ configuration: ModHostConfiguration? = nil) -> ModHost {
        let host = ModHost(configuration: configuration ?? box.configuration(), loader: loader)
        host.loadMods()
        return host
    }

    private func statuses(_ host: ModHost) -> [String: String] {
        Dictionary(uniqueKeysWithValues: host.records.map { ($0.candidate.displayName, $0.status.summary) })
    }

    // MARK: - 版本与加载

    func testVersionCheck() throws {
        let box = try Sandbox()
        for name in ["ok.dylib", "older.dylib", "major.dylib", "newer.dylib", "symbol.dylib"] { try box.makeFile(name) }
        let loader = FakeLoader()
        loader.outcomes = [
            "ok.dylib": .mod(manifest("ok", 1, 2)),
            "older.dylib": .mod(manifest("older", 1, 0)),
            "major.dylib": .mod(manifest("major", 2, 0)),
            "newer.dylib": .mod(manifest("newer", 1, 3)),
            "symbol.dylib": .error(.openFailed(message: "Symbol not found", missingModKitSymbol: true))
        ]

        let host = launch(box, loader, box.configuration(hostVersion: ModKitVersion(major: 1, minor: 2)))

        let byName = Dictionary(uniqueKeysWithValues: host.records.map { ($0.candidate.displayName, $0) })
        guard case .loaded = byName["ok.dylib"]!.status, case .loaded = byName["older.dylib"]!.status else {
            return XCTFail("兼容的 mod 应该加载：\(statuses(host))")
        }
        guard case .incompatible(.majorMismatch) = byName["major.dylib"]!.status,
              case .incompatible(.hostTooOld) = byName["newer.dylib"]!.status,
              case .incompatible(.hostTooOld) = byName["symbol.dylib"]!.status else {
            return XCTFail("版本不对的 mod 不该加载：\(statuses(host))")
        }
        XCTAssertNil(byName["major.dylib"]!.mod, "版本不对不调 makeMod")
        XCTAssertNil(host.safeMode)
    }

    func testInvalidDuplicateAndMissingEntry() throws {
        let box = try Sandbox()
        for name in ["a.dylib", "b.dylib", "c.dylib", "d.dylib", "e.dylib"] { try box.makeFile(name) }
        let loader = FakeLoader()
        loader.outcomes = [
            "a.dylib": .mod(manifest("same")),
            "b.dylib": .mod(manifest("same")),
            "c.dylib": .mod(manifest("Bad ID")),
            "e.dylib": .error(.openFailed(message: "not a mach-o", missingModKitSymbol: false))
        ]

        let host = launch(box, loader)

        let s = host.records.map(\.status)
        guard case .loaded = s[0], case .duplicateID = s[1], case .invalidID = s[2],
              case .entryPointMissing = s[3], case .loadFailed("not a mach-o") = s[4] else {
            return XCTFail("\(statuses(host))")
        }
    }

    func testActivateAndShutdown() throws {
        let box = try Sandbox()
        try box.makeFile("good.dylib")
        try box.makeFile("bad.dylib")
        let loader = FakeLoader()
        loader.outcomes = ["good.dylib": .mod(manifest("good")), "bad.dylib": .mod(manifest("bad"), failsActivation: true)]
        FixtureMod.deactivations = 0

        let host = launch(box, loader)
        host.activateMods { FakeServices(manifest: $0) }

        XCTAssertEqual(host.activeContributions.map(\.manifest.id), ["good"])
        guard case .activationFailed = host.records[0].status else { return XCTFail("\(statuses(host))") }
        host.shutdown()
        host.shutdown()
        XCTAssertEqual(FixtureMod.deactivations, 1, "只 deactivate 启用成功的，重复 shutdown 无效")
    }

    func testDisabledModIsNotOpenedOnceKnown() throws {
        let box = try Sandbox()
        try box.makeFile("rd.dylib")
        let loader = FakeLoader()
        loader.outcomes = ["rd.dylib": .mod(manifest("red-dragon"))]
        let disabled = box.configuration(disabled: ["red-dragon"])

        // 第一次不知道 rd.dylib 是谁，只能 dlopen 看 id，但不 makeMod
        let first = launch(box, loader, disabled)
        guard case .disabledByUser = first.records[0].status else { return XCTFail("\(statuses(first))") }
        XCTAssertNil(first.records[0].mod)
        first.shutdown()

        // 之后认得出，直接跳过
        let second = launch(box, loader, disabled)
        guard case .disabledByUser = second.records[0].status else { return XCTFail("\(statuses(second))") }
        XCTAssertEqual(second.records[0].modID, "red-dragon")
        XCTAssertEqual(loader.opened, ["rd.dylib"])
    }

    // MARK: - 安全模式

    func testCrashShortlyAfterLaunchEntersSafeMode() throws {
        let box = try Sandbox()
        try box.makeFile("rd.dylib")
        let loader = FakeLoader()
        loader.outcomes = ["rd.dylib": .mod(manifest("red-dragon"))]

        _ = launch(box, loader)                       // 加载了 mod，没撑过窗口就「崩了」
        let safe = launch(box, loader)

        guard case .crashedShortlyAfterLaunch? = safe.safeMode?.reason else { return XCTFail("应进安全模式") }
        XCTAssertEqual(safe.safeMode?.suspectMods, ["rd.dylib"])
        guard case .skippedSafeMode = safe.records[0].status else { return XCTFail("\(statuses(safe))") }
        XCTAssertEqual(loader.opened, ["rd.dylib"], "安全模式下不 dlopen")

        // 安全模式这次也崩了（不怪 mod）、或正常退出：mod 没变就一直留在安全模式
        let again = launch(box, loader)
        again.shutdown()
        let stillSafe = launch(box, loader)
        XCTAssertEqual(stillSafe.safeMode?.suspectMods, ["rd.dylib"])
        XCTAssertEqual(stillSafe.records[0].modID, "red-dragon", "列表里认得出 id，用户可以按 id 关掉它")
        XCTAssertEqual(loader.opened, ["rd.dylib"])
    }

    func testStableOrCleanExitIsNotACrash() throws {
        let box = try Sandbox()
        try box.makeFile("rd.dylib")
        let loader = FakeLoader()
        loader.outcomes = ["rd.dylib": .mod(manifest("red-dragon"))]

        launch(box, loader).markLaunchStable()
        XCTAssertNil(launch(box, loader).safeMode, "撑过窗口后崩的不算")
        // 上一行那次没撑过窗口
        let safe = launch(box, loader)
        XCTAssertNotNil(safe.safeMode)
        safe.leaveSafeMode()

        let back = launch(box, loader)
        XCTAssertNil(back.safeMode, "用户退出安全模式后下次加载")
        back.shutdown()
        XCTAssertNil(launch(box, loader).safeMode, "正常退出不算崩溃")
        XCTAssertEqual(loader.opened.count, 4)
    }

    func testCrashWithoutModsIsNotTheModsFault() throws {
        let box = try Sandbox()
        let loader = FakeLoader()
        _ = launch(box, loader)                       // 没有 mod，崩了
        try box.makeFile("rd.dylib")
        loader.outcomes = ["rd.dylib": .mod(manifest("red-dragon"))]

        XCTAssertNil(launch(box, loader).safeMode)
    }

    func testChangedModFileLeavesSafeMode() throws {
        let box = try Sandbox()
        let file = try box.makeFile("rd.dylib")
        let loader = FakeLoader()
        loader.outcomes = ["rd.dylib": .mod(manifest("red-dragon"))]

        _ = launch(box, loader)
        XCTAssertNotNil(launch(box, loader).safeMode)

        try Data("rebuilt".utf8).write(to: file)      // 重编了 mod
        let retry = launch(box, loader)
        XCTAssertNil(retry.safeMode)
        guard case .loaded = retry.records[0].status else { return XCTFail("\(statuses(retry))") }
    }

    func testDisablingTheSuspectLeavesSafeMode() throws {
        let box = try Sandbox()
        try box.makeFile("a.dylib")
        try box.makeFile("rd.dylib")
        let loader = FakeLoader()
        loader.outcomes = ["a.dylib": .mod(manifest("other")), "rd.dylib": .mod(manifest("red-dragon"))]

        _ = launch(box, loader)
        XCTAssertEqual(launch(box, loader).safeMode?.suspectMods, ["a.dylib", "rd.dylib"])

        // 在安全模式的 mod 列表里关掉红龙：剩下的照常加载，红龙不 dlopen
        let host = launch(box, loader, box.configuration(disabled: ["red-dragon"]))
        XCTAssertNil(host.safeMode)
        guard case .loaded = host.records[0].status, case .disabledByUser = host.records[1].status else {
            return XCTFail("\(statuses(host))")
        }
        XCTAssertEqual(loader.opened, ["a.dylib", "rd.dylib", "a.dylib"])
    }

    func testForcedSafeModeIsNotPersisted() throws {
        let box = try Sandbox()
        try box.makeFile("rd.dylib")
        let loader = FakeLoader()
        loader.outcomes = ["rd.dylib": .mod(manifest("red-dragon"))]

        let forced = launch(box, loader, box.configuration(forceSafeMode: true))
        XCTAssertEqual(forced.safeMode?.reason, .forced)
        XCTAssertEqual(forced.safeMode?.suspectMods, [])
        XCTAssertTrue(loader.opened.isEmpty)

        // 强制安全模式那次崩了也不怪 mod
        XCTAssertNil(launch(box, loader).safeMode)
        XCTAssertEqual(loader.opened, ["rd.dylib"])
    }

    func testCorruptStateFileIsIgnored() throws {
        let box = try Sandbox()
        try box.makeFile("rd.dylib")
        try box.makeFile("state.json", contents: "{not json", in: box.state)
        let loader = FakeLoader()
        loader.outcomes = ["rd.dylib": .mod(manifest("red-dragon"))]

        let host = launch(box, loader)
        XCTAssertNil(host.safeMode)
        guard case .loaded = host.records[0].status else { return XCTFail("\(statuses(host))") }
    }
}
