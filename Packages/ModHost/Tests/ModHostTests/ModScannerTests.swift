//
//  ModScannerTests.swift
//  ModHostTests
//

import Foundation
@testable import ModHost
import XCTest

final class ModScannerTests: XCTestCase {

    func testFindsThreeShapesSortedAndSkipsOthers() throws {
        let box = try Sandbox()
        try box.makeFile("b.dylib")
        try box.makeFile("Flat.framework/Flat")
        try box.makeFile("Deep.framework/Versions/A/Deep")
        try FileManager.default.createSymbolicLink(atPath: box.mods.appendingPathComponent("Deep.framework/Versions/Current").path,
                                                   withDestinationPath: "A")
        try box.makeFile("Plug.bundle/Contents/MacOS/PlugBin")
        let plist: [String: Any] = ["CFBundleExecutable": "PlugBin", "CFBundleIdentifier": "test.plug"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: box.mods.appendingPathComponent("Plug.bundle/Contents/Info.plist"))
        try box.makeFile(".hidden.dylib")
        try box.makeFile("readme.txt")

        let result = ModScanner.scan(directory: box.mods)

        XCTAssertEqual(result.candidates.map(\.displayName), ["Deep.framework", "Flat.framework", "Plug.bundle", "b.dylib"])
        XCTAssertEqual(result.candidates.map { $0.binaryURL.lastPathComponent }, ["Deep", "Flat", "PlugBin", "b.dylib"])
        XCTAssertTrue(result.issues.isEmpty)
    }

    func testBrokenBundlesBecomeIssues() throws {
        let box = try Sandbox()
        try FileManager.default.createDirectory(at: box.mods.appendingPathComponent("Empty.framework"),
                                                withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: box.mods.appendingPathComponent("NoPlist.bundle"),
                                                withIntermediateDirectories: true)

        let result = ModScanner.scan(directory: box.mods)

        XCTAssertTrue(result.candidates.isEmpty)
        XCTAssertEqual(Set(result.issues.map { $0.url.lastPathComponent }), ["Empty.framework", "NoPlist.bundle"])
    }

    func testMissingDirectoryIsEmpty() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("no-such-\(UUID().uuidString)")
        let result = ModScanner.scan(directory: missing)
        XCTAssertTrue(result.candidates.isEmpty)
        XCTAssertTrue(result.issues.isEmpty)
    }

    func testAdditionalURLsComeLastAndSameBinaryOnlyOnce() throws {
        let box = try Sandbox()
        let outside = try box.makeFile("build/Dev.dylib", in: box.root)
        let bareBinary = try box.makeFile("build/DevBinary", in: box.root)
        // Mods 目录里放一个指向构建输出的链接，开发路径又指了同一个文件
        try FileManager.default.createSymbolicLink(at: box.mods.appendingPathComponent("Dev.dylib"),
                                                   withDestinationURL: outside)
        try box.makeFile("a.dylib")

        let result = ModScanner.scan(directory: box.mods, additionalURLs: [outside, bareBinary])

        XCTAssertEqual(result.candidates.map(\.displayName), ["Dev.dylib", "a.dylib", "DevBinary"])
        XCTAssertEqual(result.issues.map(\.url), [outside])
    }

    func testMissingModKitSymbolHeuristic() {
        let missing = """
        dlopen(/x/Foo.dylib, 0x0002): Symbol not found: _$s6ModKit3NewV
          Referenced from: <UUID> /x/Foo.dylib
          Expected in:     <UUID> /app/Contents/Frameworks/ModKit.framework/Versions/A/ModKit
        """
        XCTAssertTrue(DynamicLibraryLoader.isMissingModKitSymbol(missing))
        let otherLib = """
        dlopen(/x/Foo.dylib, 0x0002): Symbol not found: _foo
          Referenced from: <UUID> /x/Foo.dylib
          Expected in:     <UUID> /usr/lib/libz.1.dylib
        """
        XCTAssertFalse(DynamicLibraryLoader.isMissingModKitSymbol(otherLib))
        XCTAssertFalse(DynamicLibraryLoader.isMissingModKitSymbol("dlopen(/x/Foo.dylib): file not found"))
    }
}
