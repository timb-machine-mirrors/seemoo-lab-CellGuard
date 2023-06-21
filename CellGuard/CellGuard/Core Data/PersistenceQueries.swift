//
//  PersistenceQueries.swift
//  CellGuard
//
//  Created by Lukas Arnold on 03.02.23.
//

import CoreData

extension PersistenceController {
    // TODO: Import data from Wikipedia
    // MCC -> Country Name
    // MCC, MNC -> Network Operator Name
    
    /// Uses `NSBatchInsertRequest` (BIR) to import tweak cell properties into the Core Data store on a private queue.
    func importCollectedCells(from cells: [CCTCellProperties]) throws {
        let taskContext = newTaskContext()
        
        taskContext.name = "importContext"
        taskContext.transactionAuthor = "importTweakCells"
        
        var success = false
        
        taskContext.performAndWait {
            var index = 0
            let total = cells.count
            
            let importedDate = Date()
            
            let batchInsertRequest = NSBatchInsertRequest(entity: TweakCell.entity(), managedObjectHandler: { cell in
                guard index < total else { return true }
                
                
                if let cell = cell as? TweakCell {
                    cells[index].applyTo(tweakCell: cell)
                    cell.imported = importedDate
                    cell.status = CellStatus.imported.rawValue
                }
                    
                index += 1
                return false
            })
            
            if let fetchResult = try? taskContext.execute(batchInsertRequest),
               let batchInsertResult = fetchResult as? NSBatchInsertResult {
                success = batchInsertResult.result as? Bool ?? false
            }
        }
        
        if !success {
            logger.debug("Failed to execute batch import request for tweak cells.")
            throw PersistenceError.batchInsertError
        }
        
        try? assignLocationsToTweakCells()
        
        logger.debug("Successfully inserted \(cells.count) tweak cells.")
    }
    
    /// Uses `NSBatchInsertRequest` (BIR) to import ALS cell properties into the Core Data store on a private queue.
    func importALSCells(from cells: [ALSQueryCell], source: NSManagedObjectID) throws {
        // TODO: Add a constraint for technology,country,network,area,cell
        // Apparently this is not possible with parent entities. ):
        // See: https://developer.apple.com/forums/thread/36775
        
        let taskContext = newTaskContext()
        
        taskContext.name = "importContext"
        taskContext.transactionAuthor = "importALSCells"
        
        var success = false
        
        taskContext.performAndWait {
            let importedDate = Date()
            
            // We can't use a BatchInsertRequest because it doesn't support relationships
            // See: https://developer.apple.com/forums/thread/676651
            cells.forEach { queryCell in
                // Don't add the check if it already exists
                let existFetchRequets = NSFetchRequest<ALSCell>()
                existFetchRequets.entity = ALSCell.entity()
                existFetchRequets.predicate = sameCellPredicate(queryCell: queryCell)
                do {
                    // TODO: Update the date of existing cell
                    if try taskContext.count(for: existFetchRequets) > 0 {
                        return
                    }
                } catch {
                    self.logger.warning("Can't check if ALS cells (\(queryCell)) already exists: \(error)")
                    return
                }
                
                // The cell don't exists, so we can add it
                let cell = ALSCell(context: taskContext)
                cell.imported = importedDate
                queryCell.applyTo(alsCell: cell)
                
                if let queryLocation = queryCell.location {
                    let location = ALSLocation(context: taskContext)
                    queryLocation.applyTo(location: location)
                    cell.location = location
                }
            }
            
            // Get the tweak cell managed object from its ID
            guard let tweakCell = try? taskContext.existingObject(with: source) as? TweakCell else {
                self.logger.warning("Can't get tweak cell (\(source)) from its object ID")
                return
            }
            tweakCell.status = CellStatus.verified.rawValue

            // Fetch the verification cell for the tweak cell and assign it
            do {
                let verifyCell = try fetchALSCell(from: tweakCell, context: taskContext)
                if let verifyCell = verifyCell {
                    tweakCell.verification = verifyCell
                } else {
                    self.logger.warning("Can't assign a verification cell for tweak cell: \(tweakCell)")
                    return
                }
            } catch {
                self.logger.warning("Can't execute a fetch request for getting a verfication cell for tweak cell: \(tweakCell)")
                return
            }
            
            // Save the task context
            do {
                try taskContext.save()
                success = true
            } catch {
                self.logger.warning("Can't save tweak cell with successful verification: \(error)")
            }
        }
        
        if !success {
            throw PersistenceError.batchInsertError
        }
        
        logger.debug("Successfully inserted \(cells.count) ALS cells.")

    }
    
    /// Calculates the distance between the location for the tweak cell and its verified counter part from Apple's database.
    /// If no verification or locations references cell exist, nil is returned.
    func calculateDistance(tweakCell tweakCellID: NSManagedObjectID) -> CellLocationDistance? {
        let taskContext = newTaskContext()
        
        var distance: CellLocationDistance? = nil
        taskContext.performAndWait {
            guard let tweakCell = taskContext.object(with: tweakCellID) as? TweakCell else {
                return
            }
            
            guard let alsCell = tweakCell.verification else {
                return
            }
            
            guard let userLocation = tweakCell.location else {
                return
            }
            
            guard let alsLocation = alsCell.location else {
                return
            }
            
            distance = CellLocationDistance.distance(userLocation: userLocation, alsLocation: alsLocation)
        }
        
        return distance
    }
    
    /// Uses `NSBatchInsertRequest` (BIR) to import locations into the Core Data store on a private queue.
    func importUserLocations(from locations: [TrackedUserLocation]) throws {
        let taskContext = newTaskContext()
        
        taskContext.name = "importContext"
        taskContext.transactionAuthor = "importLocations"
        
        var success = false
        
        // TODO: Only import if the location is different by a margin with the last location
        
        taskContext.performAndWait {
            var index = 0
            let total = locations.count
            
            let importedDate = Date()
            
            let batchInsertRequest = NSBatchInsertRequest(entity: UserLocation.entity(), managedObjectHandler: { location in
                guard index < total else { return true }
                
                if let location = location as? UserLocation {
                    locations[index].applyTo(location: location)
                    location.imported = importedDate
                }
                
                index += 1
                return false
            })
            if let fetchResult = try? taskContext.execute(batchInsertRequest),
               let batchInsertResult = fetchResult as? NSBatchInsertResult {
                success = batchInsertResult.result as? Bool ?? false
            }
        }
        
        if !success {
            logger.debug("Failed to execute batch import request for cells.")
            throw PersistenceError.batchInsertError
        }
        
        logger.debug("Successfully inserted \(locations.count) locations.")
    }
    
    /// Uses `NSBatchInsertRequest` (BIR) to import QMI packets into the Core Data store on a private queue.
    func importQMIPackets(from packets: [(CPTPacket, ParsedQMIPacket)]) throws {
        let taskContext = newTaskContext()
        
        taskContext.name = "importContext"
        taskContext.transactionAuthor = "importQMIPackets"
        
        var success = false
        
        taskContext.performAndWait {
            var index = 0
            let total = packets.count
            
            let importedDate = Date()
            
            let batchInsertRequest = NSBatchInsertRequest(entity: QMIPacket.entity(), managedObjectHandler: { dbPacket in
                guard index < total else { return true }
                
                if let dbPacket = dbPacket as? QMIPacket {
                    let (tweakPacket, parsedPacket) = packets[index]
                    dbPacket.data = tweakPacket.data
                    dbPacket.collected = tweakPacket.timestamp
                    dbPacket.direction = tweakPacket.direction.rawValue
                    dbPacket.proto = tweakPacket.proto.rawValue
                    
                    dbPacket.service = Int16(parsedPacket.qmuxHeader.serviceId)
                    dbPacket.message = Int32(parsedPacket.messageHeader.messageId)
                    dbPacket.indication = parsedPacket.transactionHeader.indication
                    
                    dbPacket.imported = importedDate
                }
                    
                index += 1
                return false
            })
            
            if let fetchResult = try? taskContext.execute(batchInsertRequest),
               let batchInsertResult = fetchResult as? NSBatchInsertResult {
                success = batchInsertResult.result as? Bool ?? false
            }
        }
        
        if !success {
            logger.debug("Failed to execute batch import request for QMI packets.")
            throw PersistenceError.batchInsertError
        }
        
        logger.debug("Successfully inserted \(packets.count) tweak QMI packets.")
    }
    
    /// Uses `NSBatchInsertRequest` (BIR) to import ARI packets into the Core Data store on a private queue.
    func importARIPackets(from packets: [(CPTPacket, ParsedARIPacket)]) throws {
        let taskContext = newTaskContext()
        
        taskContext.name = "importContext"
        taskContext.transactionAuthor = "importARIPackets"
        
        var success = false
        
        taskContext.performAndWait {
            var index = 0
            let total = packets.count
            
            let importedDate = Date()
            
            let batchInsertRequest = NSBatchInsertRequest(entity: ARIPacket.entity(), managedObjectHandler: { dbPacket in
                guard index < total else { return true }
                
                if let dbPacket = dbPacket as? ARIPacket {
                    let (tweakPacket, parsedPacket) = packets[index]
                    dbPacket.data = tweakPacket.data
                    dbPacket.collected = tweakPacket.timestamp
                    dbPacket.direction = tweakPacket.direction.rawValue
                    dbPacket.proto = tweakPacket.proto.rawValue
                    
                    dbPacket.group = Int16(parsedPacket.header.group)
                    dbPacket.type = Int32(parsedPacket.header.type)
                    
                    dbPacket.imported = importedDate
                }
                    
                index += 1
                return false
            })
            
            if let fetchResult = try? taskContext.execute(batchInsertRequest),
               let batchInsertResult = fetchResult as? NSBatchInsertResult {
                success = batchInsertResult.result as? Bool ?? false
            }
        }
        
        if !success {
            logger.debug("Failed to execute batch import request for ARI packets.")
            throw PersistenceError.batchInsertError
        }
        
        logger.debug("Successfully inserted \(packets.count) tweak ARI packets.")
    }
    
    func fetchLatestUnverifiedTweakCells(count: Int) throws -> [NSManagedObjectID : ALSQueryCell]  {
        var queryCells: [NSManagedObjectID : ALSQueryCell] = [:]
        var fetchError: Error? = nil
        newTaskContext().performAndWait {
            let request = NSFetchRequest<TweakCell>()
            request.entity = TweakCell.entity()
            request.fetchLimit = count
            request.predicate = NSPredicate(format: "status == %@", CellStatus.imported.rawValue)
            request.sortDescriptors = [NSSortDescriptor(keyPath: \TweakCell.collected, ascending: false)]
            request.returnsObjectsAsFaults = false
            do {
                let tweakCells = try request.execute()
                queryCells = Dictionary(uniqueKeysWithValues: tweakCells.map { ($0.objectID, queryCell(from: $0)) })
            } catch {
                fetchError = error
            }
        }
        
        if let fetchError = fetchError {
            logger.warning("Can't to fetch the latest \(count) unverified cells: \(fetchError)")
            throw fetchError
        }
        
        return queryCells
    }
    
    func assignExistingALSIfPossible(to tweakCellID: NSManagedObjectID) throws -> Bool {
        let taskContext = newTaskContext()
        
        taskContext.name = "updateContext"
        taskContext.transactionAuthor = "assignExistingALSIfPossible"
        
        var fetchError: Error?
        var found = false
        
        taskContext.performAndWait {
            do {
                guard let tweakCell = taskContext.object(with: tweakCellID) as? TweakCell else {
                    return
                }
                
                guard let alsCell = try fetchALSCell(from: tweakCell, context: taskContext) else {
                    return
                }
                
                found = true
                
                tweakCell.status = CellStatus.verified.rawValue
                tweakCell.verification = alsCell
                
                try taskContext.save()
            } catch {
                fetchError = error
            }
        }
        
        if let fetchError = fetchError {
            logger.warning(
                "Can't fetch or save for assinging an existing ALS cell to a tweak cell (\(tweakCellID) if possible: \(fetchError)")
            throw fetchError
        }
        
        return found
    }
    
    private func fetchALSCell(from tweakCell: TweakCell, context: NSManagedObjectContext) throws -> ALSCell? {
        let fetchRequest = NSFetchRequest<ALSCell>()
        fetchRequest.entity = ALSCell.entity()
        fetchRequest.fetchLimit = 1
        fetchRequest.predicate = sameCellPredicate(cell: tweakCell)
        
        do {
            let result = try fetchRequest.execute()
            return result.first
        } catch {
            self.logger.warning("Can't fetch ALS cell for tweak cell (\(tweakCell)): \(error)")
            throw error
        }
    }
    
    private func queryCell(from cell: TweakCell) -> ALSQueryCell {
        return ALSQueryCell(
            technology: ALSTechnology(rawValue: cell.technology ?? "") ?? .LTE,
            country: cell.country,
            network: cell.network,
            area: cell.area,
            cell: cell.cell
        )
    }
    
    func sameCellPredicate(cell: Cell) -> NSPredicate {
        return NSPredicate(
            format: "technology = %@ and country = %@ and network = %@ and area = %@ and cell = %@",
            cell.technology ?? "", cell.country as NSNumber, cell.network as NSNumber,
            cell.area as NSNumber, cell.cell as NSNumber
        )
    }
    
    func sameCellPredicate(queryCell cell: ALSQueryCell) -> NSPredicate {
        return NSPredicate(
            format: "technology = %@ and country = %@ and network = %@ and area = %@ and cell = %@",
            cell.technology.rawValue, cell.country as NSNumber, cell.network as NSNumber,
            cell.area as NSNumber, cell.cell as NSNumber
        )
    }
    
    func storeCellStatus(cellId: NSManagedObjectID, status: CellStatus) throws {
        let taskContext = newTaskContext()
        
        taskContext.name = "updateContext"
        taskContext.transactionAuthor = "storeCellStatus"
        
        var saveError: Error? = nil
        taskContext.performAndWait {
            if let tweakCell = taskContext.object(with: cellId) as? TweakCell {
                tweakCell.status = status.rawValue
                do {
                    try taskContext.save()
                } catch {
                    self.logger.warning("Can't save tweak cell (\(tweakCell)) with status == \(status.rawValue): \(error)")
                    saveError = error
                }
            } else {
                self.logger.warning("Can't apply status == \(status.rawValue) to tweak cell with object ID: \(cellId)")
                saveError = PersistenceError.objectIdNotFoundError
            }
        }
        
        if let saveError = saveError {
            throw saveError
        }
    }
    
    /// Uses `NSBatchUpdateRequest` (BIR) to assign locations stored in Core Data  to cells on a private queue.
    func assignLocationsToTweakCells() throws {
        let taskContext = newTaskContext()
        
        taskContext.name = "updateContext"
        taskContext.transactionAuthor = "assignLocationsToTweakCells"
        
        var successful: Int = 0
        var count: Int = 0
        var contextError: Error?
        
        taskContext.performAndWait {
            // Fetch all tweak cells without location
            let cellFetchRequest = NSFetchRequest<TweakCell>()
            cellFetchRequest.entity = TweakCell.entity()
            cellFetchRequest.predicate = NSPredicate(format: "location == nil and collected != nil")
            
            let cells: [TweakCell]
            do {
                cells = try cellFetchRequest.execute()
            } catch {
                self.logger.warning("Can't fetch tweak cells without any location: \(error)")
                contextError = error
                return
            }
            
            if cells.isEmpty {
                self.logger.debug("There are no tweak cells without location data")
                return
            }
            count = cells.count
            
            let calendar = Calendar.current
            
            // TODO: Check if this does work correctly
            let min = cells.min { $0.collected! < $1.collected! }?.collected
            let max = cells.max { $0.collected! < $1.collected! }?.collected
            
            let minDay = calendar.date(byAdding: .day, value: -1, to: min!)!
            let maxDay = calendar.date(byAdding: .day, value: 1, to: max!)!
            
            // Fetch locations in date range with a margin of one day
            let locationFetchRequest = NSFetchRequest<UserLocation>()
            locationFetchRequest.entity = UserLocation.entity()
            locationFetchRequest.predicate = NSPredicate(format: "collected > %@ and collected < %@ and collected != nil", minDay as NSDate, maxDay as NSDate)
            
            let locations: [UserLocation]
            do {
                locations = try locationFetchRequest.execute()
            } catch {
                self.logger.warning("Can't fetch user locations with in \(minDay) - \(maxDay): \(error)")
                contextError = error
                return
            }
            
            if locations.isEmpty {
                self.logger.debug("There no user locations which can be assigned to \(cells.count) tweak cells")
                return
            }
            
            // Assign each tweak cell location with min (tweakCell.collected - location.timestamp) which is greater or equal to zero
            var seenDates = Set<Date>()
            let uniqueLocationsKV = locations
                .filter { seenDates.insert( $0.collected!).inserted }
                .map { ($0.collected!, $0) }
            
            let collectedLocationMap: [Date : UserLocation] = Dictionary(uniqueKeysWithValues: uniqueLocationsKV)
            let collectedDates = collectedLocationMap.keys
            
            cells.forEach { cell in
                let lastLocationBefore = collectedDates
                    .filter { $0 > cell.collected! }
                    .max(by: { $0 < $1 })
                
                // If we've got no location (because it could be older than a day), we'll dont set it
                guard let lastLocationBefore = lastLocationBefore else {
                    return
                }
                
                // If the location is older than a day, we'll skip it
                if cell.collected!.timeIntervalSince(lastLocationBefore) > 60 * 60 * 24 {
                    // TODO: Somehow mark the cell not to scan it again?
                    return
                }
                
                // If not, we'll assign it
                cell.location = collectedLocationMap[lastLocationBefore]
                successful += 1
            }
            
            // Save everything
            do {
                try taskContext.save()
            } catch {
                contextError = error
                self.logger.debug("Can't save context with \(locations.count) locations assigned to \(cells.count) tweak cells: \(error)")
            }
        }
        
        if let contextError = contextError {
            throw contextError
        }
        
        self.logger.debug("Successfully assigned user locations to \(successful) tweak cells of out \(count) cells.")
    }
    
    func countPacketsByType(completion: @escaping (Result<(Int, Int), Error>) -> Void) {
        let backgroundContext = newTaskContext()
        backgroundContext.perform {
            let qmiRequest = NSFetchRequest<QMIPacket>()
            qmiRequest.entity = QMIPacket.entity()
            
            let ariRequest = NSFetchRequest<ARIPacket>()
            ariRequest.entity = ARIPacket.entity()
            
            let result = Result {
                let qmiCount = try backgroundContext.count(for: qmiRequest)
                let ariCount = try backgroundContext.count(for: ariRequest)
                
                return (qmiCount, ariCount)
            }
            
            // Call the callback on the main queue
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }
    
    func deletePacketsOlderThan(days: Int) {
        let viewContext = container.viewContext
        logger.debug("Start deleting packets older than \(days) day(s) from the store...")
        
        viewContext.performAndWait {
            do {
                let startOfDay = Calendar.current.startOfDay(for: Date())
                guard let daysAgo = Calendar.current.date(byAdding: .day, value: -days, to: startOfDay) else {
                    logger.debug("Can't calculate the date for packet deletion")
                    return
                }
                logger.debug("Deleting packets older than \(startOfDay)")
                let predicate = NSPredicate(format: "collected < %@", daysAgo as NSDate)
                
                try deleteData(entity: QMIPacket.entity(), predicate: predicate, context: viewContext)
                try deleteData(entity: ARIPacket.entity(), predicate: predicate, context: viewContext)
                logger.debug("Successfully deleted old packets")
            } catch {
                self.logger.warning("Failed to delete old packets: \(error)")
            }
        }

    }
    
    func deleteDataInBackground(categories: [PersistenceCategory], completion: @escaping (Result<Void, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            // Perform the deletion
            let result = Result { try self.deleteData(categories: categories) }
            
            // Call the callback on the main queue
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }
    
    /// Synchronously deletes all records in the Core Data store.
    private func deleteData(categories: [PersistenceCategory]) throws {
        let viewContext = container.viewContext
        logger.debug("Start deleting data of \(categories) from the store...")
        
        // If the ALS cell cache or older locations are deleted but no connected cells, we do not reset their verification status to trigger a re-verification.
        let categoryEntityMapping: [PersistenceCategory: [NSEntityDescription]] = [
            .connectedCells: [TweakCell.entity()],
            .alsCells: [ALSCell.entity(), ALSLocation.entity()],
            .locations: [UserLocation.entity()],
            .packets: [ARIPacket.entity(), QMIPacket.entity()]
        ]
        
        var deleteError: Error? = nil
        viewContext.performAndWait {
            do {
                try categoryEntityMapping
                    .filter { categories.contains($0.key) }
                    .flatMap { $0.value }
                    .forEach { entity in
                        try deleteData(entity: entity, predicate: nil, context: viewContext)
                    }
            } catch {
                self.logger.warning("Failed to delete data: \(error)")
                deleteError = error
            }
            
            logger.debug("Successfully deleted data of \(categories).")
        }
        
        if let deleteError = deleteError {
            throw deleteError
        }
        
        cleanPersistentHistoryChanges()
    }
    
    /// Deletes all records belonging to a given entity
    private func deleteData(entity: NSEntityDescription, predicate: NSPredicate?, context: NSManagedObjectContext) throws {
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>()
        fetchRequest.entity = entity
        if let predicate = predicate {
            fetchRequest.predicate = predicate
        }
        
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        try context.persistentStoreCoordinator?.execute(deleteRequest, with: context)
    }

}
