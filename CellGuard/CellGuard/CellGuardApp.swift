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
    
    let persistenceController = PersistenceController.shared
    let locationManager = LocationDataManager(extact: true)
    let networkAuthorization = LocalNetworkAuthorization(
        checkNow: UserDefaults.standard.bool(forKey: UserDefaultsKeys.introductionShown.rawValue)
    )
    let notificationManager = CGNotificationManager.shared

    var body: some Scene {
        WindowGroup {
            CGTabView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(locationManager)
                .environmentObject(networkAuthorization)
                .environmentObject(notificationManager)
        }
    }
}
