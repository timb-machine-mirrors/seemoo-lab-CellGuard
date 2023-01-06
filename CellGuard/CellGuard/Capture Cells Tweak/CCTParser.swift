//
//  CCTParser.swift
//  CellGuard
//
//  Created by Lukas Arnold on 01.01.23.
//

import Foundation
import CoreData

enum CCTParserError: Error {
    case emptySample(CellSample)
    case noCells(CellSample)
    case noServingCell(CellSample)
    case invalidTimestamp(CellInfo)
    case missingRAT(CellInfo)
    case unknownRAT(String)
    case notImplementedRAT(String)
    case missingCellType(CellInfo)
    case unknownCellType(String)
}

enum CCTCellType: String {
    case Serving = "CellTypeServing"
    case Neighbour = "CellTypeNeighbor"
    case Monitor = "CellTypeMonitor"
    case Detected = "CellTypeDetected"
}

struct CCTParser {
    
    let context: NSManagedObjectContext
    
    init(context: NSManagedObjectContext) {
        self.context = context
    }
    
    func parse(_ sample: CellSample) throws -> Cell {
        if sample.isEmpty {
            throw CCTParserError.emptySample(sample)
        }
        
        guard let doubleTimestamp = sample.last?["timestamp"] as? Double else {
            throw CCTParserError.invalidTimestamp(sample.last!)
        }
        let timestamp = Date(timeIntervalSince1970: doubleTimestamp)
        let cells = try sample.dropLast(1).map() { try parseCell($0) }
        
        if cells.isEmpty {
            throw CCTParserError.noCells(sample)
        }
        
        let servingCell = cells.first(where: { $0.type == CCTCellType.Serving})?.cell
        let neighborCell = cells.first(where: { $0.type == CCTCellType.Neighbour})?.cell
        
        guard let servingCell = servingCell else {
            throw CCTParserError.noServingCell(sample)
        }
        
        if let neighborCell = neighborCell {
            servingCell.neighbourRadio = neighborCell.radio
        }
        
        // We're using JSONSerilization because the JSONDecoder requires specific type information that we can't provide
        servingCell.json = String(data: try JSONSerialization.data(withJSONObject: sample), encoding: .utf8)
        servingCell.timestamp = timestamp
        
        return servingCell
    }
    
    private func parseCell(_ info: CellInfo) throws -> (cell: Cell, type: CCTCellType) {
        // Location for symbols:
        // - Own sample collection using the tweak
        // - IPSW: /System/Library/Frameworks/CoreTelephony.framework/CoreTelephony (dyld_cache)
        // - https://github.com/nahum365/CellularInfo/blob/master/CellInfoView.m#L32
        
        let rat = info["CellRadioAccessTechnology"]
        guard let rat = rat as? String else {
            throw CCTParserError.missingRAT(info)
        }
        
        let cell: Cell
        switch (rat) {
        case "RadioAccessTechnologyGSM":
            cell = try parseGSM(info)
        case "RadioAccessTechnologyUMTS":
            cell = try parseUTMS(info)
        case "RadioAccessTechnologyUTRAN":
            // UMTS Terrestrial Radio Access Network
            // https://en.wikipedia.org/wiki/UMTS_Terrestrial_Radio_Access_Network
            cell = try parseUTMS(info)
        case "RadioAccessTechnologyCDMA1x":
            // https://en.wikipedia.org/wiki/CDMA2000
            cell = try parseCDMA(info)
        case "RadioAccessTechnologyCDMAEVDO":
            // CDMA2000 1x Evolution-Data Optimized
            cell = try parseCDMA(info)
        case "RadioAccessTechnologyCDMAHybrid":
            cell = try parseCDMA(info)
        case "RadioAccessTechnologyLTE":
            cell = try parseLTE(info)
        case "RadioAccessTechnologyTDSCDMA":
            // Special version of UMTS WCDMA in China
            // https://www.electronics-notes.com/articles/connectivity/3g-umts/td-scdma.php
            cell = try parseUTMS(info)
        case "RadioAccessTechnologyNR":
            cell = try parseNR(info)
        default:
            throw CCTParserError.unknownRAT(rat)
        }
        
        let cellType = info["CellType"]
        guard let cellType = cellType as? String else {
            throw CCTParserError.missingCellType(info)
        }
        guard let cellType = CCTCellType(rawValue: cellType) else {
            throw CCTParserError.unknownCellType(cellType)
        }
         
        cell.radio = rat
        
        return (cell, cellType)
    }
    
    private func parseGSM(_ info: CellInfo) throws -> Cell {
        let cell = Cell(context: self.context)
        
        cell.mcc = info["MCC"] as? Int32 ?? 0
        cell.network = info["MNC"] as? Int32 ?? 0
        cell.area = info["LAC"] as? Int32 ?? 0
        cell.cellId = info["CellId"] as? Int64 ?? 0
        
        // We're using ARFCN here as BandInfo is always 0
        cell.band = info["ARFCN"] as? Int32 ?? 0
        
        return cell
    }
    
    private func parseUTMS(_ info: CellInfo) throws -> Cell {
        let cell = Cell(context: self.context)
        
        // UMTS has been phased out in many countries
        // https://de.wikipedia.org/wiki/Universal_Mobile_Telecommunications_System
        
        // Therefore this is just a guess and not tested but it should be the similar to GSM
        // https://en.wikipedia.org/wiki/Mobility_management#Location_area
        
        cell.mcc = info["MCC"] as? Int32 ?? 0
        cell.network = info["MNC"] as? Int32 ?? 0
        cell.area = info["LAC"] as? Int32 ?? 0
        cell.cellId = info["CellId"] as? Int64 ?? 0
        
        cell.band = info["BandInfo"] as? Int32 ?? 0
        
        return cell
    }
    
    private func parseCDMA(_ info: CellInfo) throws -> Cell {
        // CDMA has been shutdown is most conutries:
        // - https://www.verizon.com/about/news/3g-cdma-network-shut-date-set-december-31-2022
        // - https://www.digi.com/blog/post/2g-3g-4g-lte-network-shutdown-updates
        // - https://en.wikipedia.org/wiki/List_of_CDMA2000_networks
        
        // Sources:
        // https://wiki.opencellid.org/wiki/Public:CDMA
        // https://en.wikipedia.org/wiki/CDMA_subscriber_identity_module
        // https://github.com/nahum365/CellularInfo/blob/master/CellInfoView.m#L47
        // https://github.com/CellMapper/Map-BETA/issues/13
        // https://www.howardforums.com/showthread.php/1578315-Verizon-cellId-and-channel-number-questions?highlight=SID%3ANID%3ABID
        
        // Just a guess, not tested

        let cell = Cell(context: self.context)
        
        cell.mcc = info["MCC"] as? Int32 ?? 0
        cell.network = info["SID"] as? Int32 ?? 0
        cell.area = info["PNOffset"] as? Int32 ?? 0
        cell.cellId = info["BaseStationId"] as? Int64 ?? 0
        
        cell.band = info["BandClass"] as? Int32 ?? 0
        
        return cell
    }
    
    
    private func parseLTE(_ info: CellInfo) throws -> Cell {
        let cell = Cell(context: self.context)
        
        cell.mcc = info["MCC"] as? Int32 ?? 0
        cell.network = info["MNC"] as? Int32 ?? 0
        cell.area = info["TAC"] as? Int32 ?? 0
        cell.cellId = info["CellId"] as? Int64 ?? 0
        
        cell.band = info["BandInfo"] as? Int32 ?? 0
        
        return cell
    }
    
    private func parseNR(_ info: CellInfo) throws -> Cell {
        let cell = Cell(context: self.context)
        
        // Just a guess
        
        cell.mcc = info["MCC"] as? Int32 ?? 0
        cell.network = info["MNC"] as? Int32 ?? 0
        cell.area = info["TAC"] as? Int32 ?? 0
        cell.cellId = info["CellId"] as? Int64 ?? 0
        
        cell.band = info["BandInfo"] as? Int32 ?? 0

        return cell
    }
    
}
