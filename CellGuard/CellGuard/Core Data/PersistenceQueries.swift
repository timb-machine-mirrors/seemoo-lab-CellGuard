//
//  PersistenceQueries.swift
//  CellGuard
//
//  Created by Lukas Arnold on 03.02.23.
//

import CoreData

extension PersistenceController {
    
    /// Uses `NSBatchInsertRequest` (BIR) to import tweak cell properties into the Core Data store on a private queue.
    func importCollectedCells(from cells: [CCTCellProperties]) throws {
        let taskContext = newTaskContext()
        
        taskContext.name = "importContext"
        taskContext.transactionAuthor = "importCellsTweak"
        taskContext.mergePolicy = NSMergePolicy.rollback
        
        var success = false
        
        taskContext.performAndWait {
            var index = 0
            let total = cells.count
            
            let importedDate = Date()
            
            let batchInsertRequest = NSBatchInsertRequest(entity: CellTweak.entity(), managedObjectHandler: { cell in
                guard index < total else { return true }
                
                
                if let cell = cell as? CellTweak {
                    cells[index].applyTo(tweakCell: cell)
                    cell.imported = importedDate
                    cell.status = CellStatus.imported.rawValue
                    cell.score = 0
                    cell.nextVerification = Date()
                    cell.notificationSent = false
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
        
        logger.debug("Successfully inserted \(cells.count) tweak cells.")
    }
    
    /// Uses `NSBatchInsertRequest` (BIR) to import ALS cell properties into the Core Data store on a private queue.
    func importALSCells(from cells: [ALSQueryCell], source: NSManagedObjectID?) throws {
        let taskContext = newTaskContext()
        
        taskContext.name = "importContext"
        taskContext.transactionAuthor = "importALSCells"
        taskContext.mergePolicy = NSMergePolicy.rollback
        
        var success = false
        
        taskContext.performAndWait {
            let importedDate = Date()
            
            // We can't use a BatchInsertRequest because it doesn't support relationships
            // See: https://developer.apple.com/forums/thread/676651
            cells.forEach { queryCell in
                // Don't add the check if it already exists
                let existFetchRequest = NSFetchRequest<CellALS>()
                existFetchRequest.fetchLimit = 1
                existFetchRequest.entity = CellALS.entity()
                existFetchRequest.predicate = sameCellPredicate(queryCell: queryCell, mergeUMTS: true)
                do {
                    // If the cell exists, we update its attributes but not its location.
                    // This is crucial for adding the PCI & EARFCN to an existing LTE cell.
                    if let existingCell = try taskContext.fetch(existFetchRequest).first{
                        existingCell.imported = importedDate
                        queryCell.applyTo(alsCell: existingCell)
                        return
                    }
                } catch {
                    self.logger.warning("Can't check if ALS cells (\(queryCell)) already exists: \(error)")
                    return
                }
                
                // The cell does not exists in our app's database, so we can add it
                let cell = CellALS(context: taskContext)
                cell.imported = importedDate
                queryCell.applyTo(alsCell: cell)
                
                if let queryLocation = queryCell.location {
                    let location = LocationALS(context: taskContext)
                    queryLocation.applyTo(location: location)
                    cell.location = location
                } else {
                    self.logger.warning("Imported an ALS cell without a location: \(queryCell)")
                }
            }
            
            if let source = source {
                // Get the tweak cell managed object from its ID
                guard let tweakCell = try? taskContext.existingObject(with: source) as? CellTweak else {
                    self.logger.warning("Can't get tweak cell (\(source)) from its object ID")
                    return
                }
                
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
                    self.logger.warning("Can't execute a fetch request for getting a verification cell for tweak cell: \(tweakCell)")
                    return
                }
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
    
    func determineDataRiskStatus() -> RiskLevel {
        return (try? performAndWait(name: "fetchContext", author: "determineDataRiskStatus") { context in
            let calendar = Calendar.current
            let thirtyMinutesAgo = Date() - 30 * 60
            let ftDaysAgo = calendar.date(byAdding: .day, value: -14, to: calendar.startOfDay(for: Date()))!
            
            // Consider all cells if the analysis mode is active, otherwise only those of the last 14 days
            let ftDayPredicate: NSPredicate
            if UserDefaults.standard.dataCollectionMode() == .none {
                // This predicate always evaluates to true
                ftDayPredicate = NSPredicate(value: true)
            } else {
                ftDayPredicate = NSPredicate(format: "collected >= %@", ftDaysAgo as NSDate)
            }
            
            let tweakCelSortDescriptor = [NSSortDescriptor(keyPath: \CellTweak.collected, ascending: false)]
            let dataCollectionMode = UserDefaults.standard.dataCollectionMode()
            
            // Unverified Measurements
            
            let unknownFetchRequest: NSFetchRequest<CellTweak> = CellTweak.fetchRequest()
            unknownFetchRequest.sortDescriptors = tweakCelSortDescriptor
            unknownFetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                ftDayPredicate,
                NSPredicate(format: "status != %@", CellStatus.verified.rawValue),
            ])
            unknownFetchRequest.fetchLimit = 1
            let unknowns = try context.fetch(unknownFetchRequest)
            
            // We show the unknown status if there's work left and were in the analysis mode
            if unknowns.count > 0 && dataCollectionMode == .none {
                return .Unknown
            }
            
            // Failed Measurements
            
            let failedFetchRequest: NSFetchRequest<CellTweak> = CellTweak.fetchRequest()
            failedFetchRequest.sortDescriptors = tweakCelSortDescriptor
            failedFetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                ftDayPredicate,
                NSPredicate(format: "status == %@", CellStatus.verified.rawValue),
                NSPredicate(format: "score < %@", CellVerifier.pointsUntrustedThreshold as NSNumber)
            ])
            let failed = try context.fetch(failedFetchRequest)
            if failed.count > 0 {
                let cellCount = Dictionary(grouping: failed) { Self.queryCell(from: $0) }.count
                return .High(cellCount: cellCount)
            }
            
            // Suspicious Measurements
            
            let suspiciousFetchRequest: NSFetchRequest<CellTweak> = CellTweak.fetchRequest()
            suspiciousFetchRequest.sortDescriptors = tweakCelSortDescriptor
            suspiciousFetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                ftDayPredicate,
                NSPredicate(format: "status == %@", CellStatus.verified.rawValue),
                NSPredicate(format: "score < %@", CellVerifier.pointsSuspiciousThreshold as NSNumber)
            ])
            let suspicious = try context.fetch(suspiciousFetchRequest)
            if suspicious.count > 0 {
                let cellCount = Dictionary(grouping: suspicious) { Self.queryCell(from: $0) }.count
                return .Medium(cause: .Cells(cellCount: cellCount))
            }
            
            #if JAILBREAK
            // Only check data received from tweaks if the device is jailbroken
            if dataCollectionMode == .automatic {
                
                // Latest Measurement
                
                let allFetchRequest: NSFetchRequest<CellTweak> = CellTweak.fetchRequest()
                allFetchRequest.fetchLimit = 1
                allFetchRequest.sortDescriptors = tweakCelSortDescriptor
                let all = try context.fetch(allFetchRequest)
                
                // We've received no cells for 30 minutes from the tweak, so we warn the user
                guard let latestTweakCell = all.first else {
                    return CCTClient.lastConnectionReady > thirtyMinutesAgo ? .Unknown : .Medium(cause: .TweakCells)
                }
                if latestTweakCell.collected ?? Date.distantPast < thirtyMinutesAgo {
                    return CCTClient.lastConnectionReady > thirtyMinutesAgo ? .Unknown : .Medium(cause: .TweakCells)
                }
                
                // Latest Packet
                
                let allQMIPacketsFetchRequest: NSFetchRequest<PacketQMI> = PacketQMI.fetchRequest()
                allQMIPacketsFetchRequest.fetchLimit = 1
                allQMIPacketsFetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \PacketQMI.collected, ascending: false)]
                let qmiPackets = try context.fetch(allQMIPacketsFetchRequest)
                
                let allARIPacketsFetchRequest: NSFetchRequest<PacketARI> = PacketARI.fetchRequest()
                allARIPacketsFetchRequest.fetchLimit = 1
                allARIPacketsFetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \PacketARI.collected, ascending: false)]
                let ariPackets = try context.fetch(allARIPacketsFetchRequest)
                
                let latestPacket = [qmiPackets.first as (any Packet)?, ariPackets.first as (any Packet)?]
                    .compactMap { $0 }
                    .sorted { return $0.collected ?? Date.distantPast < $1.collected ?? Date.distantPast }
                    .last
                guard let latestPacket = latestPacket else {
                    return CPTClient.lastConnectionReady > thirtyMinutesAgo ? .Unknown : .Medium(cause: .TweakPackets)
                }
                if latestPacket.collected ?? Date.distantPast < thirtyMinutesAgo {
                    return CPTClient.lastConnectionReady > thirtyMinutesAgo ? .Unknown : .Medium(cause: .TweakPackets)
                }
            }
            #endif
            
            // Only check locations if the analysis mode is not active
            if dataCollectionMode != .none {
                
                // Latest Location
                
                let locationFetchRequest: NSFetchRequest<LocationUser> = LocationUser.fetchRequest()
                locationFetchRequest.fetchLimit = 1
                locationFetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \LocationUser.collected, ascending: false)]
                let location = try context.fetch(locationFetchRequest)
                
                // We've received no location for 30 minutes from iOS, so we warn the user
                guard let latestLocation = location.first else {
                    return .Medium(cause: .Location)
                }
                if latestLocation.collected ?? Date.distantPast < thirtyMinutesAgo {
                    return .Medium(cause: .Location)
                }
            }
            
            
            // Permissions
            
            if (LocationDataManager.shared.authorizationStatus ?? .authorizedAlways) != .authorizedAlways ||
                (CGNotificationManager.shared.authorizationStatus ?? .authorized) != .authorized {
                return .Medium(cause: .Permissions)
            }
            
            // We keep the unknown status until all cells are verified (except the current cell which we are monitoring)
            // If the analysis mode is not active, we the unknown mode has a lower priority
            if unknowns.count == 1, let unknownCell = unknowns.first, unknownCell.status == CellStatus.processedBandwidth.rawValue {
                return .LowMonitor
            } else if unknowns.count > 0 {
                return .Unknown
            }
            
            return .Low
            
        }) ?? RiskLevel.Medium(cause: .CantCompute)
    }
    
    /// Calculates the distance between the location for the tweak cell and its verified counter part from Apple's database.
    /// If no verification or locations references cell exist, nil is returned.
    func calculateDistance(tweakCell tweakCellID: NSManagedObjectID) -> CellLocationDistance? {
        return try? performAndWait(name: "fetchContext", author: "calculateDistance") { (context) -> CellLocationDistance? in
            guard let tweakCell = context.object(with: tweakCellID) as? CellTweak else {
                logger.warning("Can't calculate distance for cell \(tweakCellID): Cell missing from task context")
                return nil
            }
            
            guard let alsCell = tweakCell.verification else {
                logger.warning("Can't calculate distance for cell \(tweakCellID): No verification ALS cell")
                return nil
            }
            
            guard let userLocation = tweakCell.location else {
                logger.warning("Can't calculate distance for cell \(tweakCellID): Missing user location from cell")
                return nil
            }
            
            guard let alsLocation = alsCell.location else {
                // TODO: Sometimes this does not work ): -> imported = nil, other properties are there
                logger.warning("Can't calculate distance for cell \(tweakCellID): Missing location from ALS cell")
                return nil
            }
            
            return CellLocationDistance.distance(userLocation: userLocation, alsLocation: alsLocation)
        }
    }
    
    /// Uses `NSBatchInsertRequest` (BIR) to import locations into the Core Data store on a private queue.
    func importUserLocations(from locations: [TrackedUserLocation]) throws {
        // TODO: Only import if the location is different by a margin with the last location
        
        try performAndWait(name: "importContext", author: "importLocations") { context in
            var index = 0
            let total = locations.count
            
            let importedDate = Date()
            
            let batchInsertRequest = NSBatchInsertRequest(entity: LocationUser.entity(), managedObjectHandler: { location in
                guard index < total else { return true }
                
                if let location = location as? LocationUser {
                    locations[index].applyTo(location: location)
                    location.imported = importedDate
                }
                
                index += 1
                return false
            })
            
            let fetchResult = try context.execute(batchInsertRequest)
            
            if let batchInsertResult = fetchResult as? NSBatchInsertResult,
                !((batchInsertResult.result as? Bool) ?? false) {
                logger.debug("Failed to execute batch import request for user locations.")
                throw PersistenceError.batchInsertError
            }
        }
        
        logger.debug("Successfully inserted \(locations.count) locations.")    }
    
    /// Uses `NSBatchInsertRequest` (BIR) to import QMI packets into the Core Data store on a private queue.
    func importQMIPackets(from packets: [(CPTPacket, ParsedQMIPacket)]) throws {
        if packets.isEmpty {
            return
        }
        
        let objectIds: [NSManagedObjectID] = try performAndWait(name: "importContext", author: "importQMIPackets") { context in
            var index = 0
            let total = packets.count
            
            let importedDate = Date()
            
            let batchInsertRequest = NSBatchInsertRequest(entity: PacketQMI.entity(), managedObjectHandler: { dbPacket in
                guard index < total else { return true }
                
                if let dbPacket = dbPacket as? PacketQMI {
                    let (tweakPacket, parsedPacket) = packets[index]
                    dbPacket.data = tweakPacket.data
                    dbPacket.collected = tweakPacket.timestamp
                    dbPacket.direction = tweakPacket.direction.rawValue
                    // dbPacket.proto = tweakPacket.proto.rawValue
                    
                    dbPacket.service = Int16(parsedPacket.qmuxHeader.serviceId)
                    dbPacket.message = Int32(parsedPacket.messageHeader.messageId)
                    dbPacket.indication = parsedPacket.transactionHeader.indication
                    
                    dbPacket.imported = importedDate
                }
                
                index += 1
                return false
            })
            
            batchInsertRequest.resultType = .objectIDs
            
            guard let fetchResult = try? context.execute(batchInsertRequest),
                  let batchInsertResult = fetchResult as? NSBatchInsertResult else {
                return []
            }
            
            return batchInsertResult.result as? [NSManagedObjectID]
        } ?? []
        
        try performAndWait(name: "importContext", author: "importQMIPackets") { context in
            var added = false
            
            for id in objectIds {
                guard let qmiPacket = context.object(with: id) as? PacketQMI else {
                    continue
                }
                
                if qmiPacket.indication == PacketConstants.qmiRejectIndication
                    && qmiPacket.service == PacketConstants.qmiRejectService
                    && qmiPacket.direction == PacketConstants.qmiRejectDirection.rawValue {
                    
                    if qmiPacket.message == PacketConstants.qmiRejectMessage {
                        let index = PacketIndexQMI(context: context)
                        index.collected = qmiPacket.collected
                        index.reject = true
                        qmiPacket.index = index
                        added = true
                    } else if qmiPacket.message == PacketConstants.qmiSignalMessage {
                        let index = PacketIndexQMI(context: context)
                        index.collected = qmiPacket.collected
                        index.signal = true
                        qmiPacket.index = index
                        added = true
                    }
                }
            }
            
            if added {
                try context.save()
            }
        }
        
        // It can be the case the newly imported data is already in the database
        /* if objectIds.isEmpty {
            logger.debug("Failed to execute batch import request for QMI packets.")
            throw PersistenceError.batchInsertError
        } */
        
        logger.debug("Successfully inserted \(packets.count) tweak QMI packets.")
    }
    
    /// Uses `NSBatchInsertRequest` (BIR) to import ARI packets into the Core Data store on a private queue.
    func importARIPackets(from packets: [(CPTPacket, ParsedARIPacket)]) throws {
        if packets.isEmpty {
            return
        }
        
        let objectIds: [NSManagedObjectID] = try performAndWait(name: "importContext", author: "importARIPackets") { context in
            var index = 0
            let total = packets.count
            
            let importedDate = Date()
            
            let batchInsertRequest = NSBatchInsertRequest(entity: PacketARI.entity(), managedObjectHandler: { dbPacket in
                guard index < total else { return true }
                
                if let dbPacket = dbPacket as? PacketARI {
                    let (tweakPacket, parsedPacket) = packets[index]
                    dbPacket.data = tweakPacket.data
                    dbPacket.collected = tweakPacket.timestamp
                    dbPacket.direction = tweakPacket.direction.rawValue
                    // dbPacket.proto = tweakPacket.proto.rawValue
                    
                    dbPacket.group = Int16(parsedPacket.header.group)
                    dbPacket.type = Int32(parsedPacket.header.type)
                    
                    dbPacket.imported = importedDate
                }
                
                index += 1
                return false
            })
            
            batchInsertRequest.resultType = .objectIDs
            
            guard let fetchResult = try? context.execute(batchInsertRequest),
                  let batchInsertResult = fetchResult as? NSBatchInsertResult else {
                return []
            }
            
            return batchInsertResult.result as? [NSManagedObjectID]
        } ?? []
        
        try performAndWait(name: "importContext", author: "importARIPackets") { context in
            var added = false
            
            for id in objectIds {
                guard let ariPacket = context.object(with: id) as? PacketARI else {
                    continue
                }
                
                if ariPacket.direction == PacketConstants.ariRejectDirection.rawValue {
                    if ariPacket.group == PacketConstants.ariRejectGroup && ariPacket.type == PacketConstants.ariRejectType {
                        let index = PacketIndexARI(context: context)
                        index.reject = true
                        index.collected = ariPacket.collected
                        ariPacket.index = index
                        added = true
                    } else if ariPacket.group == PacketConstants.ariSignalGroup && ariPacket.type == PacketConstants.ariSignalType {
                        let index = PacketIndexARI(context: context)
                        index.signal = true
                        index.collected = ariPacket.collected
                        ariPacket.index = index
                        added = true
                    }
                }
            }
            
            if added {
                try context.save()
            }
        }
        
        /* if objectIds.isEmpty {
            logger.debug("Failed to execute batch import request for ARI packets.")
            throw PersistenceError.batchInsertError
        } */
        
        logger.debug("Successfully inserted \(packets.count) tweak ARI packets.")
    }
    
    func fetchLatestUnverifiedTweakCells(count: Int) throws -> (NSManagedObjectID, ALSQueryCell, CellStatus?, Int16)?  {
        var cell: (NSManagedObjectID, ALSQueryCell, CellStatus?, Int16)? = nil
        var fetchError: Error? = nil
        newTaskContext().performAndWait {
            let request = NSFetchRequest<CellTweak>()
            request.entity = CellTweak.entity()
            request.fetchLimit = count
            request.predicate = NSPredicate(format: "status != %@ and nextVerification <= %@", CellStatus.verified.rawValue, Date() as NSDate)
            request.sortDescriptors = [NSSortDescriptor(keyPath: \CellTweak.collected, ascending: false)]
            request.returnsObjectsAsFaults = false
            do {
                let tweakCells = try request.execute()
                if let first = tweakCells.first {
                    cell = (first.objectID, Self.queryCell(from: first), CellStatus(rawValue: first.status ?? ""), first.score)
                }
            } catch {
                fetchError = error
            }
        }
        
        if let fetchError = fetchError {
            logger.warning("Can't to fetch the latest \(count) unverified cells: \(fetchError)")
            throw fetchError
        }
        
        return cell
    }
    
    func fetchCellLifespan(of tweakCellID: NSManagedObjectID) throws -> (start: Date, end: Date, after: NSManagedObjectID)? {
        let taskContext = newTaskContext()
        
        var cellTuple: (start: Date, end: Date, after: NSManagedObjectID)? = nil
        var fetchError: Error? = nil
        taskContext.performAndWait {
            guard let tweakCell = taskContext.object(with: tweakCellID) as? CellTweak else {
                logger.warning("Can't convert NSManagedObjectID \(tweakCellID) to CellTweak")
                return
            }
            
            guard let startTimestamp = tweakCell.collected else {
                logger.warning("CellTweak \(tweakCell) has not collected timestamp")
                return
            }
            
            let request = NSFetchRequest<CellTweak>()
            request.entity = CellTweak.entity()
            request.fetchLimit = 1
            request.predicate = NSPredicate(format: "collected > %@", startTimestamp as NSDate)
            request.sortDescriptors = [NSSortDescriptor(keyPath: \CellTweak.collected, ascending: true)]
            request.returnsObjectsAsFaults = false
            do {
                let tweakCells = try request.execute()
                if let tweakCell = tweakCells.first {
                    if let endTimestamp = tweakCell.collected {
                        cellTuple = (start: startTimestamp, end: endTimestamp, after: tweakCell.objectID)
                    } else {
                        logger.warning("CellTweak \(tweakCell) has not collected timestamp")
                    }
                }
            } catch {
                fetchError = error
            }
        }
        
        if let fetchError = fetchError {
            logger.warning("Can' fetch the first cell after the cell \(tweakCellID): \(fetchError)")
            throw fetchError
        }
        
        return cellTuple
    }
    
    /// Fetches QMI packets with the specified properties from Core Data.
    /// Remember to update the fetch index `byQMIPacketPropertiesIndex` when fetching new types of packets, otherwise the query slows down significantly.
    func fetchQMIPackets(direction: CPTDirection, service: Int16, message: Int32, indication: Bool, start: Date, end: Date) throws -> [NSManagedObjectID: ParsedQMIPacket] {
        var packets: [NSManagedObjectID: ParsedQMIPacket] = [:]
        
        var fetchError: Error? = nil
        newTaskContext().performAndWait {
            let request = NSFetchRequest<PacketQMI>()
            request.entity = PacketQMI.entity()
            request.predicate = NSPredicate(
                format: "indication = %@ and service = %@ and message = %@ and %@ <= collected and collected <= %@ and direction = %@",
                NSNumber(booleanLiteral: indication), service as NSNumber, message as NSNumber, start as NSDate, end as NSDate, direction.rawValue as NSString
            )
            request.sortDescriptors = [NSSortDescriptor(keyPath: \PacketQMI.collected, ascending: false)]
            // See: https://stackoverflow.com/a/11165883
            request.propertiesToFetch = ["data"]
            do {
                let qmiPackets = try request.execute()
                for qmiPacket in qmiPackets {
                    guard let data = qmiPacket.data else {
                        logger.warning("Skipping packet \(qmiPacket) as it provides no binary data")
                        continue
                    }
                    packets[qmiPacket.objectID] = try ParsedQMIPacket(nsData: data)
                }
            } catch {
                fetchError = error
            }
        }
        
        if let fetchError = fetchError {
            logger.warning("Can't fetch QMI packets (service=\(service), message=\(message), indication=\(indication)) from \(start) to \(end): \(fetchError)")
            throw fetchError
        }
        
        return packets
    }
    
    func fetchIndexedQMIPackets(start: Date, end: Date, reject: Bool = false, signal: Bool = false) throws -> [NSManagedObjectID: ParsedQMIPacket] {
        return try performAndWait(name: "fetch") { context in
            let request = PacketIndexQMI.fetchRequest()
            
            request.predicate = NSPredicate(
                format: "reject = %@ and signal = %@ and %@ <= collected and collected <= %@",
                NSNumber(booleanLiteral: reject), NSNumber(booleanLiteral: signal), start as NSDate, end as NSDate
            )
            request.sortDescriptors = [NSSortDescriptor(keyPath: \PacketIndexQMI.collected, ascending: false)]
            request.includesSubentities = true
        
            var packets: [NSManagedObjectID: ParsedQMIPacket] = [:]
            for indexedQMIPacket in try request.execute() {
                guard let packet = indexedQMIPacket.packet else {
                    logger.warning("No QMI packet for indexed packet \(indexedQMIPacket)")
                    continue
                }
                guard let data = packet.data else {
                    logger.warning("Skipping packet \(packet) as it provides no binary data")
                    continue
                }
                
                packets[packet.objectID] = try ParsedQMIPacket(nsData: data)
            }

            return packets
        } ?? [:]
    }
    
    func fetchIndexedARIPackets(start: Date, end: Date, reject: Bool = false, signal: Bool = false) throws -> [NSManagedObjectID: ParsedARIPacket] {
        return try performAndWait { context in
            let request = PacketIndexARI.fetchRequest()
            
            request.predicate = NSPredicate(
                format: "reject = %@ and signal = %@ and %@ <= collected and collected <= %@",
                NSNumber(booleanLiteral: reject), NSNumber(booleanLiteral: signal), start as NSDate, end as NSDate
            )
            request.sortDescriptors = [NSSortDescriptor(keyPath: \PacketIndexARI.collected, ascending: false)]
            request.includesSubentities = true
        
            var packets: [NSManagedObjectID: ParsedARIPacket] = [:]
            for indexedARIPacket in try request.execute() {
                guard let packet = indexedARIPacket.packet else {
                    logger.warning("No ARI packet for indexed packet \(indexedARIPacket)")
                    continue
                }
                guard let data = packet.data else {
                    logger.warning("Skipping packet \(packet) as it provides no binary data")
                    continue
                }
                packets[packet.objectID] = try ParsedARIPacket(data: data)
            }

            return packets
        } ?? [:]
    }
    
    /// Fetches ARI packets with the specified properties from Core Data.
    /// Remember to update the fetch index `byARIPacketPropertiesIndex` when fetching new types of packets, otherwise the query slows down significantly.
    func fetchARIPackets(direction: CPTDirection, group: Int16, type: Int32, start: Date, end: Date) throws -> [NSManagedObjectID: ParsedARIPacket] {
        var packets: [NSManagedObjectID: ParsedARIPacket] = [:]
        
        var fetchError: Error? = nil
        newTaskContext().performAndWait {
            let request = NSFetchRequest<PacketARI>()
            request.entity = PacketARI.entity()
            request.predicate = NSPredicate(
                format: "group = %@ and type = %@ and %@ <= collected and collected <= %@ and direction = %@",
                group as NSNumber, type as NSNumber, start as NSDate, end as NSDate, direction.rawValue as NSString
            )
            request.sortDescriptors = [NSSortDescriptor(keyPath: \PacketARI.collected, ascending: false)]
            request.returnsObjectsAsFaults = false
            do {
                let ariPackets = try request.execute()
                for ariPacket in ariPackets {
                    guard let data = ariPacket.data else {
                        logger.warning("Skipping packet \(ariPacket) as it provides no binary data")
                        continue
                    }
                    packets[ariPacket.objectID] = try ParsedARIPacket(data: data)
                }
            } catch {
                fetchError = error
            }
        }
        
        if let fetchError = fetchError {
            logger.warning("Can't fetch ARI packets (group=\(group), type=\(type)) from \(start) to \(end): \(fetchError)")
            throw fetchError
        }
        
        return packets
    }
    
    func fetchCellAttribute<T>(cell: NSManagedObjectID, extract: (CellTweak) throws -> T?) -> T? {
        let context = newTaskContext()
        
        var fetchError: Error? = nil
        var attribute: T? = nil
        context.performAndWait {
            do {
                if let tweakCell = context.object(with: cell) as? CellTweak {
                    attribute = try extract(tweakCell)
                }
            } catch {
                fetchError = error
            }
        }
        
        if fetchError != nil {
            logger.warning("Can't fetch attribute from CellTweak: \(fetchError)")
            return nil
        }
        
        return attribute
    }
    
    func assignExistingALSIfPossible(to tweakCellID: NSManagedObjectID) throws -> Bool {
        let taskContext = newTaskContext()
        
        taskContext.name = "updateContext"
        taskContext.transactionAuthor = "assignExistingALSIfPossible"
        
        var fetchError: Error?
        var found = false
        
        taskContext.performAndWait {
            do {
                guard let tweakCell = taskContext.object(with: tweakCellID) as? CellTweak else {
                    return
                }
                
                guard let alsCell = try fetchALSCell(from: tweakCell, context: taskContext) else {
                    return
                }
                
                found = true
                
                tweakCell.verification = alsCell
                
                try taskContext.save()
            } catch {
                fetchError = error
            }
        }
        
        if let fetchError = fetchError {
            logger.warning(
                "Can't fetch or save for assigning an existing ALS cell to a tweak cell (\(tweakCellID) if possible: \(fetchError)")
            throw fetchError
        }
        
        return found
    }
    
    private func fetchALSCell(from tweakCell: CellTweak, context: NSManagedObjectContext) throws -> CellALS? {
        let fetchRequest = NSFetchRequest<CellALS>()
        fetchRequest.entity = CellALS.entity()
        fetchRequest.fetchLimit = 1
        fetchRequest.predicate = sameCellPredicate(cell: tweakCell, mergeUMTS: true)
        
        do {
            let result = try fetchRequest.execute()
            return result.first
        } catch {
            self.logger.warning("Can't fetch ALS cell for tweak cell (\(tweakCell)): \(error)")
            throw error
        }
    }
    
    static func queryCell(from cell: CellTweak) -> ALSQueryCell {
        return ALSQueryCell(
            technology: ALSTechnology(rawValue: cell.technology ?? "") ?? .LTE,
            country: cell.country,
            network: cell.network,
            area: cell.area,
            cell: cell.cell
        )
    }
    
    func sameCellPredicate(cell: Cell, mergeUMTS: Bool) -> NSPredicate {
        let technology = mergeUMTS && cell.technology == ALSTechnology.UMTS.rawValue ? ALSTechnology.GSM.rawValue : cell.technology
        
        return NSPredicate(
            format: "technology = %@ and country = %@ and network = %@ and area = %@ and cell = %@",
            technology ?? "", cell.country as NSNumber, cell.network as NSNumber,
            cell.area as NSNumber, cell.cell as NSNumber
        )
    }
    
    func sameCellPredicate(queryCell cell: ALSQueryCell, mergeUMTS: Bool) -> NSPredicate {
        let technology = mergeUMTS && cell.technology == ALSTechnology.UMTS ? ALSTechnology.GSM.rawValue : cell.technology.rawValue
        
        return NSPredicate(
            format: "technology = %@ and country = %@ and network = %@ and area = %@ and cell = %@",
            technology, cell.country as NSNumber, cell.network as NSNumber,
            cell.area as NSNumber, cell.cell as NSNumber
        )
    }
    
    func storeCellStatus(cellId: NSManagedObjectID, status: CellStatus, score: Int16) throws {
        let taskContext = newTaskContext()
        
        taskContext.name = "updateContext"
        taskContext.transactionAuthor = "storeCellStatus"
        
        var saveError: Error? = nil
        taskContext.performAndWait {
            if let tweakCell = taskContext.object(with: cellId) as? CellTweak {
                tweakCell.status = status.rawValue
                tweakCell.score = score
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
    
    func storeVerificationDelay(cellId: NSManagedObjectID, seconds: Int) throws {
        let taskContext = newTaskContext()
        
        var saveError: Error? = nil
        taskContext.performAndWait {
            if let tweakCell = taskContext.object(with: cellId) as? CellTweak {
                tweakCell.nextVerification = Date().addingTimeInterval(Double(seconds))
                do {
                    try taskContext.save()
                } catch {
                    self.logger.warning("Can't save tweak cell (\(tweakCell)) with verification delay of \(seconds)s: \(error)")
                    saveError = error
                }
            } else {
                self.logger.warning("Can't add verification delay of \(seconds)s to the tweak cell with object ID: \(cellId)")
                saveError = PersistenceError.objectIdNotFoundError
            }
        }
        if let saveError = saveError {
            throw saveError
        }
    }
    
    func storeRejectPacket(cellId: NSManagedObjectID, packetId: NSManagedObjectID) throws {
        let taskContext = newTaskContext()
        
        // Currently we are not storing the reject packet.
        // This will be part of the score overhaul.
        // TODO: Re-implement
        
        /* var saveError: Error? = nil
        taskContext.performAndWait {
            if let tweakCell = taskContext.object(with: cellId) as? CellTweak, let packet = taskContext.object(with: packetId) as? (any Packet) {
                tweakCell.rejectPacket = packet
                do {
                    try taskContext.save()
                } catch {
                    self.logger.warning("Can't save tweak cell (\(tweakCell)) with reject packet \(packet): \(error)")
                    saveError = error
                }
            } else {
                self.logger.warning("Can't add reject packet \(packetId) to the tweak cell with object ID: \(cellId)")
                saveError = PersistenceError.objectIdNotFoundError
            }
        }
        if let saveError = saveError {
            throw saveError
        } */
    }
    
    func assignLocation(to tweakCellID: NSManagedObjectID) throws -> (Bool, Date?) {
        let taskContext = newTaskContext()
        
        var saveError: Error? = nil
        var foundLocation: Bool = false
        var cellCollected: Date? = nil
        
        taskContext.performAndWait {
            guard let tweakCell = taskContext.object(with: tweakCellID) as? CellTweak else {
                self.logger.warning("Can't assign location to the tweak cell with object ID: \(tweakCellID)")
                saveError = PersistenceError.objectIdNotFoundError
                return
            }
            
            cellCollected = tweakCell.collected
            
            // Find the most precise user location within a four minute window
            let fetchLocationRequest = NSFetchRequest<LocationUser>()
            fetchLocationRequest.entity = LocationUser.entity()
            // We don't set a fetch limit as it interferes the following predicate
            if let cellCollected = cellCollected {
                let before = cellCollected.addingTimeInterval(-120)
                let after = cellCollected.addingTimeInterval(120)
                
                fetchLocationRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                    NSPredicate(format: "collected != nil"),
                    NSPredicate(format: "collected > %@", before as NSDate),
                    NSPredicate(format: "collected < %@", after as NSDate),
                ])
            } else {
                // No location without a date boundary as we would just pick a random location
                return
            }
            fetchLocationRequest.sortDescriptors = [
                NSSortDescriptor(keyPath: \LocationUser.horizontalAccuracy, ascending: true)
            ]
            
            // Execute the fetch request
            let locations: [LocationUser]
            do {
                locations = try fetchLocationRequest.execute()
            } catch {
                self.logger.warning("Can't query location for tweak cell \(tweakCell): \(error)")
                saveError = error
                return
            }
            
            // Return with foundLocation = false if we've found no location matching the criteria
            guard let location = locations.first else {
                return
            }
            
            // We've found a location, assign it to the cell, and save the cell
            foundLocation = true
            tweakCell.location = location
            
            do {
                try taskContext.save()
            } catch {
                self.logger.warning("Can't save tweak cell (\(tweakCell)) with an assigned location: \(error)")
                saveError = error
                return
            }
        }
        if let saveError = saveError {
            throw saveError
        }
        
        return (foundLocation, cellCollected)
    }
    
    func countPacketsByType(completion: @escaping (Result<(Int, Int), Error>) -> Void) {
        let backgroundContext = newTaskContext()
        backgroundContext.perform {
            let qmiRequest = NSFetchRequest<PacketQMI>()
            qmiRequest.entity = PacketQMI.entity()
            
            let ariRequest = NSFetchRequest<PacketARI>()
            ariRequest.entity = PacketARI.entity()
            
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
    
    func countEntitiesOf<T>(_ request: NSFetchRequest<T>) -> Int? {
        let taskContext = newTaskContext()
        
        // We can skip loading all the sub-entities
        // See: https://stackoverflow.com/a/1134353
        request.includesSubentities = false
        
        var count: Int? = nil
        taskContext.performAndWait {
            do {
                count = try taskContext.count(for: request)
            } catch {
                logger.warning("Can't count the number of entities in the database for \(request)")
            }
        }
        
        return count
    }
    
    func fetchNotificationCellCounts() -> (suspicious: Int, untrusted: Int)? {
        let taskContext = newTaskContext()
        
        var count: (Int, Int)? = nil
        taskContext.performAndWait {
            let request: NSFetchRequest<CellTweak> = CellTweak.fetchRequest()
            request.predicate = NSPredicate(
                format: "notificationSent == NO and status == %@ and score < %@",
                CellStatus.verified.rawValue as NSString, CellVerifier.pointsSuspiciousThreshold as NSNumber
            )
            
            do {
                let measurements = try taskContext.fetch(request)
                
                // Choose the measurement with the lowest score for each cell
                let cells = Dictionary(grouping: try taskContext.fetch(request)) { Self.queryCell(from: $0) }
                    .compactMap { $0.value.min { $0.score < $1.score } }
                
                // Count the number suspicious and untrusted cells
                count = (
                    cells.filter {$0.score >= CellVerifier.pointsUntrustedThreshold}.count,
                    cells.filter {$0.score < CellVerifier.pointsUntrustedThreshold}.count
                )
                
                // Update all cells, so no multiple notification are sent
                measurements.forEach { $0.notificationSent = true }
                try taskContext.save()
            } catch {
                logger.warning("Can't count and update the measurements for notifications")
            }
        }
        
        return count
    }
    
    func clearVerificationData(tweakCellID: NSManagedObjectID) throws {
        try performAndWait { taskContext in
            guard let tweakCell = taskContext.object(with: tweakCellID) as? CellTweak else {
                self.logger.warning("Can't clear verification data of the tweak cell with object ID: \(tweakCellID)")
                throw PersistenceError.objectIdNotFoundError
            }
            
            tweakCell.score = 0
            tweakCell.status = CellStatus.imported.rawValue
            tweakCell.notificationSent = false
            
            tweakCell.verification = nil
            // tweakCell.rejectPacket = nil
            tweakCell.location = nil
            
            do {
                try taskContext.save()
            } catch {
                self.logger.warning("Can't save tweak cell (\(tweakCell)) with cleared verification properties: \(error)")
                throw error
            }
            
            self.logger.debug("Cleared verification data of \(tweakCell)")
        }
    }
    
    func deletePacketsOlderThan(days: Int) {
        let taskContext = newTaskContext()
        logger.debug("Start deleting packets older than \(days) day(s) from the store...")
        
        taskContext.performAndWait {
            do {
                let startOfDay = Calendar.current.startOfDay(for: Date())
                guard let daysAgo = Calendar.current.date(byAdding: .day, value: -days, to: startOfDay) else {
                    logger.debug("Can't calculate the date for packet deletion")
                    return
                }
                logger.debug("Deleting packets older than \(startOfDay)")
                // Only delete packets not referenced by cells
                let predicate = NSPredicate(format: "collected < %@ and index = nil", daysAgo as NSDate)
                
                let qmiCount = try deleteData(entity: PacketQMI.entity(), predicate: predicate, context: taskContext)
                let ariCount = try deleteData(entity: PacketARI.entity(), predicate: predicate, context: taskContext)
                logger.debug("Successfully deleted \(qmiCount + ariCount) old packets")
            } catch {
                self.logger.warning("Failed to delete old packets: \(error)")
            }
        }
        
    }
    
    func deleteLocationsOlderThan(days: Int) {
        let taskContext = newTaskContext()
        logger.debug("Start deleting locations older than \(days) day(s) from the store...")
        
        taskContext.performAndWait {
            do {
                let startOfDay = Calendar.current.startOfDay(for: Date())
                guard let daysAgo = Calendar.current.date(byAdding: .day, value: -days, to: startOfDay) else {
                    logger.debug("Can't calculate the date for location deletion")
                    return
                }
                logger.debug("Deleting locations older than \(startOfDay)")
                // Only delete old locations not referenced by any cells
                let predicate = NSPredicate(format: "collected < %@ and cells.@count == 0", daysAgo as NSDate)
                
                let count = try deleteData(entity: LocationUser.entity(), predicate: predicate, context: taskContext)
                logger.debug("Successfully deleted \(count) old locations")
            } catch {
                self.logger.warning("Failed to delete old locations: \(error)")
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
        let taskContext = newTaskContext()
        logger.debug("Start deleting data of \(categories) from the store...")
        
        // If the ALS cell cache or older locations are deleted but no connected cells, we do not reset their verification status to trigger a re-verification.
        let categoryEntityMapping: [PersistenceCategory: [NSEntityDescription]] = [
            .connectedCells: [CellTweak.entity()],
            .alsCells: [CellALS.entity(), LocationALS.entity()],
            .locations: [LocationUser.entity()],
            .packets: [PacketARI.entity(), PacketQMI.entity()]
        ]
        
        var deleteError: Error? = nil
        taskContext.performAndWait {
            do {
                try categoryEntityMapping
                    .filter { categories.contains($0.key) }
                    .flatMap { $0.value }
                    .forEach { entity in
                        _ = try deleteData(entity: entity, predicate: nil, context: taskContext)
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
    private func deleteData(entity: NSEntityDescription, predicate: NSPredicate?, context: NSManagedObjectContext) throws -> Int {
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>()
        fetchRequest.entity = entity
        if let predicate = predicate {
            fetchRequest.predicate = predicate
        }
        
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        deleteRequest.resultType = .resultTypeCount
        let result = try context.execute(deleteRequest)
        return ((result as? NSBatchDeleteResult)?.result as? Int) ?? 0
    }
    
}
