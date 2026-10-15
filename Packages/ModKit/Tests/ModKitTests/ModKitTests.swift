//
//  ModKitTests.swift
//  ModKitTests
//

import ModKit
import XCTest

final class ModKitTests: XCTestCase {

    func testCompileTimeVersionMatchesRuntime() {
        // 升版本时两处字面量要一起改
        XCTAssertEqual(ModKitVersion.compileTime, ModKitVersion.runtime)
    }

    func testCompatibility() {
        let host = ModKitVersion(major: 1, minor: 2)
        XCTAssertEqual(host.compatibility(withModBuiltAgainst: ModKitVersion(major: 1, minor: 0)), .compatible)
        XCTAssertEqual(host.compatibility(withModBuiltAgainst: ModKitVersion(major: 1, minor: 2)), .compatible)
        XCTAssertEqual(host.compatibility(withModBuiltAgainst: ModKitVersion(major: 1, minor: 3)), .hostTooOld)
        XCTAssertEqual(host.compatibility(withModBuiltAgainst: ModKitVersion(major: 2, minor: 0)), .majorMismatch)
        XCTAssertEqual(host.compatibility(withModBuiltAgainst: ModKitVersion(major: 0, minor: 9)), .majorMismatch)
    }

    func testManifestTakesCompileTimeVersion() {
        let manifest = ModManifest(id: "red-dragon", name: "红龙辅助", version: "1.0")
        XCTAssertEqual(manifest.modKitVersion, .compileTime)
    }

    func testManifestID() {
        XCTAssertTrue(ModManifest.isValidID("red-dragon"))
        XCTAssertTrue(ModManifest.isValidID("a.b-2"))
        XCTAssertFalse(ModManifest.isValidID(""))
        XCTAssertFalse(ModManifest.isValidID("2fast"))
        XCTAssertFalse(ModManifest.isValidID("Red"))
        XCTAssertFalse(ModManifest.isValidID("red dragon"))
        XCTAssertFalse(ModManifest.isValidID("红龙"))
    }

    final class Dummy: HSTrackerMod {
        func activate(_ host: any ModHostServices) throws -> ModContributions { ModContributions() }
    }

    func testRegistrationRoundTrip() {
        let pointer = ModRegistration(manifest: ModManifest(id: "dummy", name: "Dummy", version: "0.1")) {
            Dummy()
        }.retainedPointer()
        let registration = ModRegistration.take(pointer)
        XCTAssertEqual(registration.manifest.id, "dummy")
        XCTAssertTrue(registration.makeMod() is Dummy)
    }

    func testSettingsConveniences() {
        final class Memory: ModSettings {
            var store: [String: ModSettingValue] = [:]
            func value(forKey key: String) -> ModSettingValue? { store[key] }
            func setValue(_ value: ModSettingValue?, forKey key: String) { store[key] = value }
            func observe(_ key: String, handler: @escaping @MainActor () -> Void) -> ModObservation {
                ModObservation {}
            }
        }
        let s = Memory()
        XCTAssertTrue(s.bool("on", default: true))
        s.set(false, forKey: "on")
        XCTAssertFalse(s.bool("on", default: true))
        s.set(3, forKey: "level")
        XCTAssertEqual(s.int("level", default: 0), 3)
        XCTAssertEqual(s.double("level", default: 0), 3)
        s.setValue(nil, forKey: "level")
        XCTAssertEqual(s.int("level", default: 1), 1)
    }

    func testObservationCancelsOnce() {
        var cancels = 0
        var observation: ModObservation? = ModObservation { cancels += 1 }
        observation?.cancel()
        observation = nil
        XCTAssertEqual(cancels, 1)
    }
}
