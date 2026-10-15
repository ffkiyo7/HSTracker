//
//  DynamicLoadingTests.swift
//  ModHostTests
//
//  真 dlopen：拿测试 bundle 自己的可执行文件当 mod（它导出了 `hstracker_mod_entry`，见 Fixtures.swift）。
//

import Foundation
import ModHost
import ModKit
import XCTest

@MainActor
final class DynamicLoadingTests: XCTestCase {

    private var testBinary: URL {
        get throws {
            try XCTUnwrap(Bundle(for: DynamicLoadingTests.self).executableURL)
        }
    }

    func testLoadsRealEntryPoint() throws {
        let registration = try DynamicLibraryLoader().loadRegistration(from: testBinary)
        XCTAssertEqual(registration.manifest.id, "fixture")
        XCTAssertEqual(registration.manifest.modKitVersion, .compileTime)
        XCTAssertTrue(registration.makeMod() is FixtureMod)
    }

    func testLibraryWithoutEntryPoint() {
        XCTAssertThrowsError(try DynamicLibraryLoader().loadRegistration(from: URL(fileURLWithPath: "/usr/lib/libz.1.dylib"))) {
            XCTAssertEqual($0 as? ModLibraryLoadError, .entryPointMissing)
        }
    }

    func testNotALibrary() throws {
        let box = try Sandbox()
        let junk = try box.makeFile("junk.dylib", contents: "not a mach-o")
        XCTAssertThrowsError(try DynamicLibraryLoader().loadRegistration(from: junk)) {
            guard case .openFailed(_, missingModKitSymbol: false)? = $0 as? ModLibraryLoadError else {
                return XCTFail("\($0)")
            }
        }
    }

    func testEndToEndWithDevPath() throws {
        let box = try Sandbox()
        let host = ModHost(configuration: box.configuration(hostVersion: .runtime, additional: [try testBinary]))
        host.loadMods()
        host.activateMods { FakeServices(manifest: $0) }

        XCTAssertNil(host.safeMode)
        XCTAssertEqual(host.activeContributions.map(\.manifest.id), ["fixture"])
        host.shutdown()
    }
}
