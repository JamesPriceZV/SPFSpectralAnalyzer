//
//  Item.swift
//  Shimadzu File Converter
//
//  Created by Zinco Verde, Inc. on 3/7/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date = Date()

    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
