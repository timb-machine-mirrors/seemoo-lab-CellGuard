//
//  CellGuardApp.swift
//  CellGuard
//
//  Created by Lukas Arnold on 01.01.23.
//

import SwiftUI

@main
struct CellGuardApp: App {
    @UIApplicationDelegateAdaptor(CellGuardAppDelegate.self) var appDelegate
    @Environment(\.scenePhase) var scenePhase
    
    let persistenceController = PersistenceController.shared
    let locationManager = LocationDataManager.shared
    let notificationManager = CGNotificationManager.shared
    let backgroundState = BackgroundState.shared

    var body: some Scene {
        WindowGroup {
            CompositeTabView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(locationManager)
                .environmentObject(notificationManager)
                .onChange(of: scenePhase) { backgroundState.update(from: $0) }
                .onAppear { backgroundState.update(from: scenePhase) }
        }
    }
}
