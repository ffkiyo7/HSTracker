//
//  CardSize.swift
//  HSTracker
//
//  Created by Benjamin Michotte on 15/10/16.
//  Copyright © 2016 Benjamin Michotte. All rights reserved.
//

import Foundation

// The constants below size the legacy `CardBar` path only: they are the point
// dimensions its 217x34 theme PNGs were cut for. On the SwiftUI path the five
// presets are multipliers over a window-proportional base instead — see
// `TrackerMetrics` in UIs/Trackers/SwiftUI/TrackerBarStyle.swift (PLAN 2.8).
let kFrameWidth = 217.0
let kFrameHeight = 700.0
let kRowHeight = 34.0

let kHighRowHeight = 52.0
let kHighRowFrameWidth = (kFrameWidth / kRowHeight * kHighRowHeight)

let kMediumRowHeight = 29.0
let kMediumFrameWidth = (kFrameWidth / kRowHeight * kMediumRowHeight)

let kSmallRowHeight = 23.0
let kSmallFrameWidth = (kFrameWidth / kRowHeight * kSmallRowHeight)

let kTinyRowHeight = 17.0
let kTinyFrameWidth = (kFrameWidth / kRowHeight * kTinyRowHeight)

enum CardSize: Int {
    case tiny = -1,
    small = 0,
    medium = 1,
    big = 2,
    huge = 3
}
