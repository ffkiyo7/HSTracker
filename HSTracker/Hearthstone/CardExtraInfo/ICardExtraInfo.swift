//
//  ICardExtraInfo.swift
//  HSTracker
//
//  Created by Francisco Moraes on 12/16/24.
//  Copyright © 2024 Benjamin Michotte. All rights reserved.
//

import Foundation

protocol ICardExtraInfo: NSCopying, Equatable {
    var cardNameSuffix: String? { get }
}

extension ICardExtraInfo {
    /// `any ICardExtraInfo` values cannot use `==` directly; equal only when both have the same type and value.
    func isEqual(to other: any ICardExtraInfo) -> Bool {
        guard let other = other as? Self else {
            return false
        }
        return self == other
    }
}
