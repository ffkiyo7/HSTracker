//
//  EnumTests.swift
//  HSTracker
//
//  Created by Benjamin Michotte on 5/05/17.
//  Copyright © 2017 Benjamin Michotte. All rights reserved.
//

import XCTest
@testable import HSTracker

class EnumTests: HSTrackerTests {

    override func setUp() {
        super.setUp()
    }
    
    override func tearDown() {
        super.tearDown()
    }

    func testLanguages() {
        let locales: [Language.Hearthstone] = [.deDE, .enUS, .esES, .esMX,
                                               .frFR, .itIT, .koKR, .plPL,
                                               .ptBR, .ruRU, .zhCN, .zhTW,
                                               .jaJP, .thTH].sorted(by: {
            $0.rawValue.localizedCaseInsensitiveCompare($1.rawValue) == ComparisonResult.orderedAscending
        })

        let languages: [Language.Hearthstone] = Array(Language.Hearthstone.allCases).sorted(by: {
            $0.rawValue.localizedCaseInsensitiveCompare($1.rawValue) == ComparisonResult.orderedAscending
        })
        XCTAssertEqual(languages.count, 14, "There are 14 locales")
        XCTAssertEqual(languages, locales, "Sorting locale is not the same")
    }

    /// A Hearthstone patch can add scene modes before this enum learns them;
    /// the mirror's ordinal must never trap (2026-09-16 crash in SceneWatcher).
    func testModeFromMirrorToleratesUnknownOrdinals() {
        XCTAssertEqual(Mode.fromMirror(0), .invalid)
        XCTAssertEqual(Mode.fromMirror(3), .hub)
        XCTAssertEqual(Mode.fromMirror(28), .lucky_draw)
        XCTAssertEqual(Mode.fromMirror(29), .black_market)
        XCTAssertEqual(Mode.fromMirror(Mode.allCases.count - 1), .black_market)
        XCTAssertEqual(Mode.fromMirror(Mode.allCases.count), .invalid)
        XCTAssertEqual(Mode.fromMirror(99), .invalid)
        XCTAssertEqual(Mode.fromMirror(-1), .invalid)
    }
}
