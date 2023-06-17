//
//  SummaryView.swift
//  CellGuard
//
//  Created by Lukas Arnold on 07.01.23.
//

import CoreData
import SwiftUI

// Do not attempt to use a SwiftUI Menu within a NavigationView ToolbarItem!
// This is utterly broken in SwiftUI on iOS 14 as the menu always closes if a view gets any kind of update.
// See:
// - https://developer.apple.com/forums/thread/664906
// - https://stackoverflow.com/questions/68373893/toolbar-menu-is-closed-when-updates-are-made-to-ui-in-swiftui
// - https://www.hackingwithswift.com/forums/swiftui/navigationbar-toolbar-button-not-working-properly/3376
// - https://stackoverflow.com/questions/63540602/navigationbar-toolbar-button-not-working-reliable-when-state-variable-refres
// - https://stackoverflow.com/questions/65095562/observableobject-is-updating-all-views-and-causing-menus-to-close-in-swiftui
//
// We've got a workaround for a related problem with NavigationLinks in ToolbarItems in PacketTabView.swift.
//
// And we've fixed the primary issue with 'Self._printChanges()' (Only works on iOS 15 and above)
// See: WelcomeSheet.swift
// See: https://www.hackingwithswift.com/quick-start/swiftui/how-to-find-which-data-change-is-causing-a-swiftui-view-to-update


struct SummaryTabView: View {
    
    @State private var showingCellList = false
    @State private var showingHelp = false
    @State private var showingSettings = false
    
    var body: some View {
        NavigationView {
            VStack {
                NavigationLink(isActive: $showingCellList) {
                    CellsListView()
                } label: {
                    EmptyView()
                }
                NavigationLink(isActive: $showingHelp) {
                    Text("TODO")
                } label: {
                    EmptyView()
                }
                NavigationLink(isActive: $showingSettings) {
                    SettingsView()
                } label: {
                    EmptyView()
                }
                CombinedRiskCellView()
            }
            .navigationTitle("Summary")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            showingCellList = true
                        } label: {
                            Label("View all Cells", systemImage: "list.bullet")
                        }
                        Button {
                            showingHelp = true
                        } label: {
                            Label("Learn more", systemImage: "questionmark.circle")
                        }
                        Button {
                            showingSettings = true
                        } label: {
                            Label("Settings", systemImage: "gear")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .imageScale(.large)
                    }
                }
            }
        }
        .background(Color.gray)
    }
}

private struct CombinedRiskCellView: View {
    
    @EnvironmentObject var locationManager: LocationDataManager
    @EnvironmentObject var networkAuthorization: LocalNetworkAuthorization
    @EnvironmentObject var notificationManager: CGNotificationManager
    
    @FetchRequest private var tweakCells: FetchedResults<TweakCell>
    @FetchRequest private var failedCells: FetchedResults<TweakCell>
    @FetchRequest private var unknownCells: FetchedResults<TweakCell>
    
    init() {
        let latestTweakCellRequest = NSFetchRequest<TweakCell>()
        latestTweakCellRequest.entity = TweakCell.entity()
        latestTweakCellRequest.fetchLimit = 1
        latestTweakCellRequest.sortDescriptors = [NSSortDescriptor(keyPath: \TweakCell.collected, ascending: false)]
        
        _tweakCells = FetchRequest(fetchRequest: latestTweakCellRequest)
        
        let calendar = Calendar.current
        let ftDaysAgo = calendar.date(byAdding: .day, value: -14, to: calendar.startOfDay(for: Date()))!
        
        let ftPredicate = NSPredicate(format: "collected >= %@", ftDaysAgo as NSDate)
        let failedPredicate = NSPredicate(format: "status == %@", CellStatus.failed.rawValue)
        let unknownPredicate = NSPredicate(format: "status == %@", CellStatus.imported.rawValue)
        
        _failedCells = FetchRequest(
            sortDescriptors: [],
            predicate: NSCompoundPredicate(andPredicateWithSubpredicates: [ftPredicate, failedPredicate])
        )
        _unknownCells = FetchRequest(
            sortDescriptors: [],
            predicate: NSCompoundPredicate(andPredicateWithSubpredicates: [ftPredicate, unknownPredicate])
        )
    }
    
    var body: some View {
        ScrollView {
            RiskIndicatorCard(risk: riskLevel)
            
            if !tweakCells.isEmpty {
                CellInformationCard(cell: tweakCells[0])
            }
        }
    }
    
    var riskLevel: RiskLevel {
        // We keep the unknown status until all cells are verified because we're sending notifications during verification
        if unknownCells.count > 0 {
            return .Unknown
        }
        
        if failedCells.count > 0 {
            return .High(count: failedCells.count)
        }
        
        // We've received no cells for 30 minutes from the tweak, so we warn the user
        let ftMinutesAgo = Date() - 30 * 60
        if tweakCells.isEmpty || tweakCells.first!.collected! < ftMinutesAgo {
            return .Medium(cause: .Tweak)
        }
        
        // TODO: A condition is false at the first start of the app, figure out which
        if (locationManager.authorizationStatus ?? .authorizedAlways) != .authorizedAlways ||
            !(networkAuthorization.lastResult ?? true) ||
            (notificationManager.authorizationStatus ?? .authorized) != .authorized {
            return .Medium(cause: .Permissions)
        }
        
        return .Low
    }
    
}

struct SummaryView_Previews: PreviewProvider {
    static var previews: some View {
        SummaryTabView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environmentObject(LocationDataManager.shared)
        .environmentObject(LocalNetworkAuthorization(checkNow: true))
        .environmentObject(CGNotificationManager.shared)
    }
}