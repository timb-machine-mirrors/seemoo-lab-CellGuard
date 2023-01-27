//
//  RiskIndicator.swift
//  CellGuard
//
//  Created by Lukas Arnold on 16.01.23.
//

import UIKit
import SwiftUI

enum RiskMediumCause: String {
    case Permissions = "Ensure you've granted all required permissions"
    case Tweak = "Ensure the tweak is running on your device"
}

enum RiskLevel: Equatable {
    // TODO: Show number of cells to be verified
    case Unknown
    case Low
    case Medium(cause: RiskMediumCause)
    case High(count: Int)
    
    func header() -> String {
        switch (self) {
        case .Unknown: return "Unkown"
        case .Low: return "Low"
        case .Medium: return "Medium"
        case .High: return "High"
        }
    }
    
    func description() -> String {
        switch (self) {
        case .Unknown:
            return "Collecting and processing data"
        case .Low:
            return "Verified all cells of the last 14 days"
        case let .Medium(cause):
            return cause.rawValue
        case let .High(count):
            return "Detected \(count) potential malicious \(count == 1 ? "cell" : "cells") in the last 14 days"
        }
    }
    
    func color(dark: Bool) -> Color {
        // TODO: Less saturated colors for the dark mode
        switch (self) {
        case .Unknown: return dark ? Color(UIColor.systemGray6) : .gray
        case .Low: return .green
        case .Medium: return .orange
        case .High: return .red
        }
    }
}

struct RiskIndicatorCard: View {
    
    let risk: RiskLevel
    let onTap: (RiskLevel) -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack {
            HStack() {
                Text("\(risk.header()) Risk")
                    .font(.title2)
                    .bold()
                Spacer()
                if risk == .Unknown {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Image(systemName: "chevron.right.circle.fill")
                        .imageScale(.large)
                }
            }
            HStack {
                Text(risk.description())
                    .padding()
                Spacer()
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerSize: CGSize(width: 10, height: 10))
                .foregroundColor(risk.color(dark: colorScheme == .dark))
                .shadow(color: .black.opacity(0.2), radius: 8)
        )
        .foregroundColor(.white)
        .padding()
        .onTapGesture {
            onTap(risk)
        }
    }
}

struct RiskIndicator_Previews: PreviewProvider {
    static var previews: some View {
        RiskIndicatorCard(risk: .Unknown, onTap: { _ in })
            .previewDisplayName("Unknown")
        RiskIndicatorCard(risk: .Low, onTap: { _ in })
            .previewDisplayName("Low")
        RiskIndicatorCard(risk: .Medium(cause: .Permissions), onTap: { _ in })
            .previewDisplayName("Medium")
        RiskIndicatorCard(risk: .High(count: 3), onTap: { _ in })
            .previewDisplayName("High")
    }
}
