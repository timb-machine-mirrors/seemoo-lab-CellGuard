//
//  CellDetailsRows.swift
//  CellGuard
//
//  Created by Lukas Arnold on 21.07.23.
//

import SwiftUI

struct CellDetailsRow: View {
    
    let description: String
    let icon: String?
    let value: String
    
    init(_ description: String, _ value: Int) {
        self.init(description, value as NSNumber)
    }
    
    init(_ description: String, _ value: Int32) {
        self.init(description, value as NSNumber)
    }
    
    init(_ description: String, _ value: Int64) {
        self.init(description, value as NSNumber)
    }
    
    init(_ description: String, _ value: NSNumber) {
        self.init(description, plainNumberFormatter.string(from: value) ?? "-")
    }
    
    init(_ description: String, _ value: String, icon: String? = nil) {
        self.description = description
        self.value = value
        self.icon = icon
    }
    
    var body: some View {
        KeyValueListRow(key: description) {
            HStack {
                Text(value)
                if let icon = self.icon {
                    Image(systemName: icon)
                }
            }
        }
    }
    
}
