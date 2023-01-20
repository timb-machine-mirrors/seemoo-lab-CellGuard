//
//  CellGuardAppDelegate.swift
//  CellGuard
//
//  Created by Lukas Arnold on 02.01.23.
//

import BackgroundTasks
import Foundation
import OSLog
import UIKit

class CellGuardAppDelegate : NSObject, UIApplicationDelegate {
    
    // https://www.hackingwithswift.com/quick-start/swiftui/how-to-add-an-appdelegate-to-a-swiftui-app
    // https://www.fivestars.blog/articles/app-delegate-scene-delegate-swiftui/
    // https://holyswift.app/new-backgroundtask-in-swiftui-and-how-to-test-it/
    
    static let cellRefreshTaskIdentifier = "de.tu-darmstadt.seemoo.CellGuard.refresh.cells"
    static let verifyTaskIdentifier = "de.tu-darmstadt.seemoo.CellGuard.processing.verify"
    
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: CellGuardAppDelegate.self)
    )
    
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Assign our own scene delegate to every scene
        let scenceConfig = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        scenceConfig.delegateClass = CellGuardSceneDelegate.self
        return scenceConfig
    }
    
    func application(_ application: UIApplication, willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        trackLocationIfBackground(launchOptions)
        registerSchedulers()
        
        if !isTestRun {
            startTasks()
        }
        
        return true
    }
    
    private func trackLocationIfBackground(_ launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) {
        // Only initialize the location manager if the app was excliptly launched in the background to track locations.
        // Otherwise it was initialized in CellGuardApp as environment variable
        if let launchOptions = launchOptions {
            // https://developer.apple.com/documentation/corelocation/cllocationmanager/1423531-startmonitoringsignificantlocati
            if launchOptions[.location] != nil {
                // TODO: Is this even required?
                // -> I guess not
                // _ = LocationDataManager()
            }
        }
    }
    
    private func registerSchedulers() {
        // Register a background refresh task to poll the tweak continuously in the background
        // https://developer.apple.com/documentation/uikit/app_and_environment/scenes/preparing_your_ui_to_run_in_the_background/using_background_tasks_to_update_your_app
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.cellRefreshTaskIdentifier, using: nil) { task in
            // Use to cancel operations:
            // let queue = OperationQueue()
            // queue.maxConcurrentOperationCount = 1
            // https://medium.com/snowdog-labs/managing-background-tasks-with-new-task-scheduler-in-ios-13-aaabdac0d95b
            
            let collector = CCTCollector(client: CCTClient(queue: DispatchQueue.global()))
            
            // TODO: Should we allow to cancel the task somehow?
            // task.expirationHandler
            
            collector.collectAndStore { error in
                task.setTaskCompleted(success: error == nil)
            }
        }
        
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.verifyTaskIdentifier, using: nil) { task in
            ALSVerifier().verify(n: 100)
        }
    }
    
    private func startTasks() {
        let collector = CCTCollector(client: CCTClient(queue: .global(qos: .userInitiated)))
        
        // Schedule a timer to continously poll the latest cells while the app is active
        let collectTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { timer in
            collector.collectAndStore { error in
                if let error = error {
                    Self.logger.warning("Failed to collect & store cells in scheduled timer: \(error)")
                }
            }
        }
        // We allow the timer a high tolerance of 50% as our collector is not time critical
        collectTimer.tolerance = 30
        // We also start a task to instantly fetch te latest cells
        Task {
            collector.collectAndStore { error in
                if let error = error {
                    Self.logger.warning("Failed to collect & store cells in initialization request: \(error)")
                }
            }
        }
                
        let checkTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { timer in
            ALSVerifier().verify(n: 10)
        }
        // We allow only allow a lower tolerance for check timer as it is executed in short intervals
        checkTimer.tolerance = 1

        // TODO: Add task to reguarly delete old ALS cells (>= 90 days) to force a refresh
        // -> Then, also reset the status of the associated tweak cells
    }
    
}
