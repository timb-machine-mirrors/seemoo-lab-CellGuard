//
//  SysdiagInstructionsDetailedView.swift
//  CellGuard
//
//  Created by jiska on 20.05.24.
//

import SwiftUI

struct DebugProfileDetailedView: View {
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                CenteredTitleIconTextView(
                    icon: "cellularbars",
                    title: "Baseband Debug Profile",
                    description: """
A baseband debug profile adds more data about cellular network connections to your system logs. This includes all baseband management packets exchanged between iOS and the baseband chip.

Please install the baseband debug profile provided and signed by Apple. If you are in Lockdown Mode, we recommend disconnecting your iPhone from the Internet, temporarily disabling Lockdown Mode, and then installing the baseband debug profile. After the installation, you can enable Lockdown Mode.

The debug profile expires after 21 days. Please reinstall after expiry.
""",
                    size: 120
                )
            
            }
            
            Link("Debug Profile Download Link", destination: URL(string: "https://developer.apple.com/bug-reporting/profiles-and-logs/?platform=ios&name=baseband")!)
                .frame(alignment: .leading)
            
            Spacer(minLength: 10)
        }
    }
}



#Preview {
    DebugProfileDetailedView()
}