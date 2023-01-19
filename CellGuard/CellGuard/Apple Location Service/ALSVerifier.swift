//
//  ALSVerifier.swift
//  CellGuard
//
//  Created by Lukas Arnold on 18.01.23.
//

import Foundation
import CoreData
import OSLog

enum ALSVerifierError: Error {
    case timeout(seconds: Int)
}

struct ALSVerifier {
    
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: ALSVerifier.self)
    )
    
    private let persistence = PersistenceController.shared
    private let client = ALSClient()
    
    func verify(n: Int, completion: (Error?) -> Void) {
        Self.logger.debug("Verifing at max \(n) tweak cell(s)...")
        
        let queryCells: [NSManagedObjectID : ALSQueryCell]
        do {
            queryCells = try persistence.fetchLatestUnverfiedTweakCells(count: n)
        } catch {
            completion(error)
            return
        }
        
        Self.logger.debug("Selected \(queryCells.count) tweak cell(s) for verification")
        
        // TODO: Search for query cells in database first before requesting?
        
        // We're using a dispatch group to provide a callback when all operations are finished
        let group = DispatchGroup()
        queryCells.forEach { objectID, queryCell in
            group.enter()
            client.requestCells(
                origin: queryCell,
                completion: { result in
                    processQueriedCells(result: result, source: objectID)
                    group.leave()
                }
            )
        }
        
        let timeResult = group.wait(wallTimeout: DispatchWallTime.now() + DispatchTimeInterval.seconds(n * 3))
        if timeResult == .timedOut {
            Self.logger.warning("Fetch operation for \(n) tweak timed out after \(n * 3)s")
            completion(ALSVerifierError.timeout(seconds: n * 3))
        } else {
            Self.logger.debug("Checked the verification status of \(n) tweak cells")
            completion(nil)
        }
    }

    private func processQueriedCells(result: Result<[ALSQueryCell], Error>, source: NSManagedObjectID) {
        switch (result) {
        case .failure(let error):
            Self.logger.warning("Can't fetch ALS cells for tweak cell: \(error)")
            
        case .success(let queryCells):
            Self.logger.debug("Received \(queryCells.count) cells from ALS")
            
            // Remove query cells with are only are rough approixmation
            let queryCells = queryCells.filter { $0.hasCellId() }
            
            // Check if the resuling ALS cell is valid
            if !(queryCells.first?.isValid() ?? false) {
                
                // If not, set the status of the origin cell to failed
                try? persistence.storeCellStatus(cellId: source, status: .failed)
                
                return
            }
            
            // If yes, import the cells
            do {
                try persistence.importALSCells(from: queryCells, source: source)
            } catch {
                Self.logger.warning("Can't import ALS cells \(queryCells): \(error)")
            }
        }
    }
        
}
