//
//  PersistenceImporter.swift
//  CellGuard
//
//  Created by Lukas Arnold on 24.01.23.
//

import Foundation
import OSLog

enum PersistenceImportError: Error {
    case readFailed(Error)
    case deserilizationFailed(Error)
    case invalidStructure
    case locationImportFailed(Error)
    case cellImportFailed(Error)
}

// https://stackoverflow.com/a/49154838
// https://developer.apple.com/documentation/uniformtypeidentifiers/defining_file_and_data_types_for_your_app
// https://developer.apple.com/documentation/uniformtypeidentifiers/uttype/3551524-json
// https://stackoverflow.com/questions/69499921/adding-file-icon-to-custom-file-type-in-xcode
// https://developer.apple.com/documentation/uikit/view_controllers/adding_a_document_browser_to_your_app/setting_up_a_document_browser_app

struct PersistenceImporter {
    
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: PersistenceImporter.self)
    )
    
    static func importInBackground(url: URL, completion: @escaping (Result<Int, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result.init {
                try PersistenceImporter().importData(from: url)
            }
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }
    
    private init() {
        
    }
    
    private func importData(from url: URL) throws -> Int {
        let data = try read(url: url)
        return try store(json: data)
    }
    
    private func read(url: URL) throws -> [String: Any] {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw PersistenceImportError.readFailed(error)
        }
        
        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw PersistenceImportError.deserilizationFailed(error)
        }
        
        
        guard let jsonDict = json as? [String: Any] else {
            throw PersistenceImportError.invalidStructure
        }
        
        return jsonDict
    }
    
    private func store(json: [String : Any]) throws -> Int {
        let parser = CCTParser()
        
        let cellsJson: [Any] = (json[CellFileKeys.cells] as? [Any]) ?? []
        let locationsJson: [Any] = (json[CellFileKeys.locations] as? [Any]) ?? []
        
        let cells = cellsJson
            .compactMap { $0 as? CellSample }
            .compactMap { (sample: CellSample) in
                do {
                    return try parser.parse(sample)
                } catch {
                    Self.logger.warning("Skipped cell sample \(sample) for import: \(error)")
                    return nil
                }
            }
        
        let locations = locationsJson
            .compactMap { $0 as? [String: Any] }
            .map { TrackedUserLocation(from: $0) }
        
        try PersistenceController.shared.importUserLocations(from: locations)
        try PersistenceController.shared.importCollectedCells(from: cells)
        
        Self.logger.debug("Imported \(locations.count) locations and \(cells.count) cells")
        
        return cells.count + locations.count
    }
    
}