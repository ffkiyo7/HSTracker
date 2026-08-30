//
//  ReplayUploadTests.swift
//  HSTracker
//
//  Created by Istvan Fehervari on 09/05/2017.
//  Copyright © 2017 Benjamin Michotte. All rights reserved.
//

import XCTest

@testable import HSTracker

class ReplayUploadTests: HSTrackerTests {
	
	override func setUp() {
		super.setUp()
	}
	
	override func tearDown() {
		super.tearDown()
	}
	
	func testMetadataEncoding() throws {
		let player = UploadMetaData.Player()
		player.stars = 1
		player.wins = 20
		player.losses = 10
		player.deck = ["one", "two"]
		player.deck_id = 12345
		player.cardback = 3
		
		let data = try JSONEncoder().encode(player)
		let object = try JSONSerialization.jsonObject(with: data)
		let encodedPlayer = try XCTUnwrap(object as? [String: Any])
		
		XCTAssertEqual(encodedPlayer["cardback"] as? Int, player.cardback)
		XCTAssertEqual(encodedPlayer["deck"] as? [String], player.deck)
	}
}
