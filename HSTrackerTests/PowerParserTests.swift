//
//  PowerParserTests.swift
//  HSTracker
//
//  Created by Istvan Fehervari on 28/03/2017.
//  Copyright © 2017 Benjamin Michotte. All rights reserved.
//

import XCTest
import Foundation

@testable import HSTracker

class PowerParserTests: HSTrackerTests {
    private var game: Game!
    private var parser: PowerGameStateParser!

    override func setUp() {
        super.setUp()
        game = Game(hearthstoneRunState: HearthstoneRunState(isRunning: false, isActive: false))
        parser = PowerGameStateParser(with: game)
    }

    private func feed(_ line: String) {
        parser.handle(logLine: LogLine(namespace: .power, line: line))
    }

    func testCreateGameEntity() {
        feed("D 00:00:00.0000000 GameState.DebugPrintPower() - CREATE_GAME")
        feed("D 00:00:00.0000000 GameState.DebugPrintPower() -     GameEntity EntityID=1")

        let entity = game.entities[1]
        XCTAssertNotNil(entity, "GameEntity not created")
        XCTAssertEqual(entity?.name, "GameEntity")
        XCTAssertEqual(entity?.id, 1)
    }

    func testPlayerEntity() {
        feed("D 00:00:00.0000000 GameState.DebugPrintPower() - CREATE_GAME")
        feed("D 00:00:00.0000000 GameState.DebugPrintPower() -     GameEntity EntityID=1")
        feed("D 00:00:00.0000000 GameState.DebugPrintPower() -     Player EntityID=2 PlayerID=1 GameAccountId=[hi=0 lo=0]")

        XCTAssertNotNil(game.entities[2], "Player entity not created")
        XCTAssertEqual(game.entities[2]?.id, 2)
    }
}
