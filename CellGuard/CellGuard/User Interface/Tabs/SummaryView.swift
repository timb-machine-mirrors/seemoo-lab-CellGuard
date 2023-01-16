//
//  SummaryView.swift
//  CellGuard
//
//  Created by Lukas Arnold on 07.01.23.
//

import SwiftUI

struct SummaryView: View {
    
    let showSettings: () -> ()
    
    var body: some View {
        NavigationView {
            
            // TODO: Detection status
            // TODO: Permission status
            // TODO: Currenctly connected to ...
            
            Text("Hello, World!")
                .navigationTitle("Summary")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            self.showSettings()
                        } label: {
                            // person.crop.circle
                            // gear
                            // ellipsis.circle
                            Label("Settings", systemImage: "ellipsis.circle")
                        }
                    }
                }
        }
    }
}

struct SummaryView_Previews: PreviewProvider {
    static var previews: some View {
        SummaryView {
            // doing nothing
        }
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environmentObject(LocationDataManager(extact: true))
        .environmentObject(LocalNetworkAuthorization(checkNow: true))
    }
}
