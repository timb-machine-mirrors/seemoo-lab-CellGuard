//
//  TweakCellMeasurementView.swift
//  CellGuard
//
//  Created by Lukas Arnold on 21.07.23.
//

import SwiftUI
import CoreData

struct VerificationStateView: View {
    
    var verificationState: VerificationState
    
    var body: some View {
        List {
            if let measurement = verificationState.cell,
               let verificationPipeline = activeVerificationPipelines.first(where: { $0.id == verificationState.pipeline }) {
                VerificationStateInternalView(verificationPipeline: verificationPipeline, verificationState: verificationState, measurement: measurement)
            } else {
                Text("No cell has been assigned to this verification state or the selected verification pipeline is missing.")
            }
        }
        .navigationTitle("Verification State")
        .navigationBarTitleDisplayMode(.inline)
        .listStyle(.insetGrouped)
    }
    
}

private struct VerificationStateInternalView: View {
    
    let verificationPipeline: VerificationPipeline
    @ObservedObject var verificationState: VerificationState
    @ObservedObject var measurement: CellTweak
    
    var body: some View {
        let techFormatter = CellTechnologyFormatter.from(technology: measurement.technology)
        
        var currentStage: VerificationStage? = nil
        if !verificationState.finished && verificationState.stage < verificationPipeline.stages.count {
            currentStage = verificationPipeline.stages[Int(verificationState.stage)]
        }
        
        let logs = verificationState.logs?
            .compactMap { $0 as? VerificationLog }
            .sorted { $0.stageNumber < $1.stageNumber }
        ?? []
        
        return Group {
            Section(header: Text("Date & Time")) {
                if let collectedDate = measurement.collected {
                    CellDetailsRow("Collected", fullMediumDateTimeFormatter.string(from: collectedDate))
                }
                if let importedDate = measurement.imported {
                    CellDetailsRow("Imported", fullMediumDateTimeFormatter.string(from: importedDate))
                }
            }
            
            Section(header: Text("Cell Properties")) {
                if let rat = measurement.technology {
                    CellDetailsRow("Generation", rat)
                }
                CellDetailsRow(techFormatter.frequency(), measurement.frequency)
                CellDetailsRow("Band", measurement.band)
                CellDetailsRow("Bandwidth", measurement.bandwidth)
                CellDetailsRow("Physical Cell ID", measurement.physicalCell)
                if let neighborTechnology = measurement.neighborTechnology {
                    CellDetailsRow("Neighbor", neighborTechnology)
                }
            }
            
            // TODO: Should we show the cell's identification (MNC, MCC, ...) which is shown two pages up?
            
            if let json = measurement.json, let jsonPretty = try? self.formatJSON(json: json) {
                Section(header: Text("iOS-Internal Data")) {
                    Text(jsonPretty)
                        .font(Font(UIFont.monospacedSystemFont(ofSize: UIFont.smallSystemFontSize, weight: .regular)))
                }
            }
            
            Section(header: Text("Verification")) {
                CellDetailsRow("Status", verificationState.finished ? "Finished" : "In Progress")
                CellDetailsRow("Pipeline", verificationPipeline.name)
                CellDetailsRow("Stages", verificationPipeline.stages.count)
                CellDetailsRow("Points", "\(verificationState.score) / \(verificationPipeline.pointsMax)")
                if verificationState.finished {
                    if verificationState.score >= primaryVerificationPipeline.pointsSuspicious {
                        CellDetailsRow("Verdict", "Trusted", icon: "lock.shield")
                    } else if verificationState.score >= primaryVerificationPipeline.pointsUntrusted {
                        CellDetailsRow("Verdict", "Anomalous", icon: "shield")
                    } else {
                        CellDetailsRow("Verdict", "Suspicious", icon: "exclamationmark.shield")
                    }
                    Button {
                        let measurementId = measurement.objectID
                        Task(priority: .background) {
                            try? PersistenceController.shared.clearVerificationData(tweakCellID: measurementId)
                        }
                    } label: {
                        KeyValueListRow(key: "Clear Verification Data") {
                            Image(systemName: "trash")
                        }
                    }
                }
            }
            
            ForEach(logs, id: \.id) { logEntry in
                VerificationStateLogEntryView(logEntry: logEntry, description: stageDescription(logEntry: logEntry))
            }
                        
            if let currentStage = currentStage {
                Section(header: Text("Stage: \(currentStage.name) (\(verificationState.stage))"), footer: Text(currentStage.description)) {
                    KeyValueListRow(key: "Status") {
                        ProgressView()
                    }
                    CellDetailsRow("Points", "\(currentStage.points)")
                    CellDetailsRow("Requires Packets", currentStage.waitForPackets ? "Yes" : "No")
                }
            }
        }
    }
    
    private func stageDescription(logEntry: VerificationLog) -> String? {
        // Since this verification log entry was recorded its respective verification pipeline could have been modified.
        // We try to find the current's states description in the most effective manner.
        
        // Check if the stage resides in the same position of the pipeline
        if let stage = verificationPipeline.stages[safe: Int(logEntry.stageNumber)],
            stage.id == logEntry.stageId {
            return stage.description
        }
        
        // Check if the stages resides anywhere in the pipeline
        if let stage = verificationPipeline.stages.first(where: { $0.id == logEntry.stageId }) {
            return stage.description
        }
        
        // The stage is missing from the pipeline
        return nil
    }
    
    private func formatJSON(json inputJSON: String?) throws -> String? {
        guard let inputJSON = inputJSON else {
            return nil
        }
        
        guard let inputData = inputJSON.data(using: .utf8) else {
            return nil
        }
        
        let parsedData = try JSONSerialization.jsonObject(with: inputData)
        let outputJSON = try JSONSerialization.data(withJSONObject: parsedData, options: .prettyPrinted)
        
        return String(data: outputJSON, encoding: .utf8)
    }
}

private func doubleString(_ value: Double, maxDigits: Int = 2) -> String {
    return String(format: "%.\(maxDigits)f", value)
}

// See: https://stackoverflow.com/a/35120978
private func coordinateToDMS(latitude: Double, longitude: Double) -> (latitude: String, longitude: String) {
    let latDegrees = abs(Int(latitude))
    let latMinutes = abs(Int((latitude * 3600).truncatingRemainder(dividingBy: 3600) / 60))
    let latSeconds = Double(abs((latitude * 3600).truncatingRemainder(dividingBy: 3600).truncatingRemainder(dividingBy: 60)))
    
    let lonDegrees = abs(Int(longitude))
    let lonMinutes = abs(Int((longitude * 3600).truncatingRemainder(dividingBy: 3600) / 60))
    let lonSeconds = Double(abs((longitude * 3600).truncatingRemainder(dividingBy: 3600).truncatingRemainder(dividingBy: 60) ))
    
    return (String(format:"%d° %d' %.4f\" %@", latDegrees, latMinutes, latSeconds, latitude >= 0 ? "N" : "S"),
            String(format:"%d° %d' %.4f\" %@", lonDegrees, lonMinutes, lonSeconds, longitude >= 0 ? "E" : "W"))
}

private struct VerificationStateLogEntryView: View {
    
    @ObservedObject var logEntry: VerificationLog
    let description: String?
    
    var body: some View {
        Group {
            Section(header: Text("Stage: \(logEntry.stageName ?? "Missing Name") (\(logEntry.stageNumber))"), footer: Text(description ?? "")) {
                CellDetailsRow("Status", "Completed")
                CellDetailsRow("Points", "\(logEntry.pointsAwarded) / \(logEntry.pointsMax)")
                CellDetailsRow("Duration", "\(doubleString(logEntry.duration, maxDigits: 4))s")
                if let relatedALSCell = logEntry.relatedCellALS {
                    NavigationLink {
                        VerificationStateLogRelatedALSCellView(alsCell: relatedALSCell)
                    } label: {
                        Text("Related ALS Cell")
                    }
                }
                if let relatedUserLocation = logEntry.relatedLocationUser {
                    NavigationLink {
                        VerificationStateLogRelatedUserLocationView(userLocation: relatedUserLocation)
                    } label: {
                        Text("Related User Location")
                    }
                }
                
                if let relatedALSCell = logEntry.relatedCellALS, let relatedUserLocation = logEntry.relatedLocationUser {
                    NavigationLink {
                        VerificationStageLogRelatedDistanceView(alsCell: relatedALSCell, userLocation: relatedUserLocation)
                    } label: {
                        Text("Related Distance")
                    }
                }
                
                if let relatedARIPackets = logEntry.relatedPacketARI?.compactMap({$0 as? PacketARI}), relatedARIPackets.count > 0 {
                    NavigationLink {
                        VerificationStageLogRelatedPacketsView(packets: relatedARIPackets)
                    } label: {
                        Text("Related ARI Packets")
                    }
                }
                if let relatedQMIPackets = logEntry.relatedPacketQMI?.compactMap({$0 as? PacketQMI}), relatedQMIPackets.count > 0 {
                    NavigationLink {
                        VerificationStageLogRelatedPacketsView(packets: relatedQMIPackets)
                    } label: {
                        Text("Related QMI Packets")
                    }
                }
            }
        }
    }
}

private struct VerificationStateLogRelatedALSCellView: View {
    
    let alsCell: CellALS
    
    var body: some View {
        let techFormatter = CellTechnologyFormatter.from(technology: alsCell.technology)
        
        List {
            Section(header: Text("Identification")) {
                CellDetailsRow("Technology", alsCell.technology ?? "Unknown")
                CellDetailsRow(techFormatter.country(), alsCell.country)
                CellDetailsRow(techFormatter.network(), alsCell.network)
                CellDetailsRow(techFormatter.area(), alsCell.area)
                CellDetailsRow(techFormatter.cell(), alsCell.cell)
            }
            
            if let importedDate = alsCell.imported {
                Section(header: Text("Date & Time")) {
                    CellDetailsRow("Queried at", mediumDateTimeFormatter.string(from: importedDate))
                }
            }
            if let alsLocation = alsCell.location {
                Section(header: Text("Location")) {
                    let (latitude, longitude) = coordinateToDMS(latitude: alsLocation.latitude, longitude: alsLocation.longitude)
                    CellDetailsRow("Latitude", latitude)
                    CellDetailsRow("Longitude", longitude)
                    CellDetailsRow("Accuracy", "± \(alsLocation.horizontalAccuracy)m")
                    CellDetailsRow("Reach", "\(alsLocation.reach)m")
                    CellDetailsRow("Score", alsLocation.score)
                }
            }
            
            Section(header: Text("Cell Properties")) {
                CellDetailsRow("\(techFormatter.frequency())", alsCell.frequency)
                CellDetailsRow("Physical Cell ID", alsCell.physicalCell)
            }
        }
        .navigationTitle("Related ALS Cell")
    }
    
}

private struct VerificationStateLogRelatedUserLocationView: View {
    
    let userLocation: LocationUser
    
    var body: some View {
        let (userLatitudeStr, userLongitudeStr) = coordinateToDMS(latitude: userLocation.latitude, longitude: userLocation.longitude)
        
        List {
            Section(header: Text("3D Position")) {
                CellDetailsRow("Latitude", userLatitudeStr)
                CellDetailsRow("Longitude", userLongitudeStr)
                CellDetailsRow("Horizontal Accuracy", "± \(doubleString(userLocation.horizontalAccuracy)) m")
                CellDetailsRow("Altitude", "\(doubleString(userLocation.altitude)) m")
                CellDetailsRow("Vertical Accuracy", "± \(doubleString(userLocation.verticalAccuracy)) m")
            }
            
            Section(header: Text("Speed")) {
                CellDetailsRow("Speed", "\(doubleString(userLocation.speed)) m/s")
                CellDetailsRow("Speed Accuracy", "± \(doubleString(userLocation.speedAccuracy)) m/s")
            }
            
            Section(header: Text("Metadata")) {
                CellDetailsRow("App in Background?", "\(userLocation.background)")
                if let collected = userLocation.collected {
                    CellDetailsRow("Recorded at", mediumDateTimeFormatter.string(from: collected))
                }
            }
        }
        .navigationTitle("Related User Location")
    }
    
}

private struct VerificationStageLogRelatedDistanceView: View {
    
    let alsCell: CellALS
    let userLocation: LocationUser
    @State var distance: CellLocationDistance? = nil
    
    // TODO: Compute distance async
    
    var body: some View {
        List {
            if let distance = distance {
                CellDetailsRow("Distance", "\(doubleString(distance.distance / 1000.0)) km")
                CellDetailsRow("Corrected Distance", "\(doubleString(distance.correctedDistance() / 1000.0)) km")
                CellDetailsRow("Percentage of Trust", "\(doubleString((1 - distance.score()) * 100.0)) %")
            } else {
                Text("Calculating Distance")
            }
        }
        .navigationTitle("Related Distance")
        .onAppear {
            if let alsLocation = alsCell.location {
                distance = CellLocationDistance.distance(userLocation: userLocation, alsLocation: alsLocation)
            }
        }
    }
    
}

private struct VerificationStageLogRelatedPacketsView: View {
    
    let packets: [any Packet]
    
    var body: some View {
        List(packets, id: \.id) { packet in
            NavigationLink {
                if let qmiPacket = packet as? PacketQMI {
                    PacketQMIDetailsView(packet: qmiPacket)
                } else if let ariPacket = packet as? PacketARI {
                    PacketARIDetailsView(packet: ariPacket)
                }
            } label: {
                PacketCell(packet: packet, customInfo: customInfo(packet))
            }
        }
        .navigationTitle("Related Packets")
    }
    
    // TODO: Compute the custom info async
    
    func customInfo(_ packet: any Packet) -> Text? {
        if let qmiPacket = packet as? PacketQMI {
            if PacketConstants.qmiSignalIndication == qmiPacket.indication
                && PacketConstants.qmiSignalDirection.rawValue == qmiPacket.direction
                && PacketConstants.qmiSignalService == qmiPacket.service
                && PacketConstants.qmiSignalMessage == qmiPacket.message,
               let data = qmiPacket.data,
               let parsedPacket = try? ParsedQMIPacket(nsData: data),
               let parsedSignalInfo = try? ParsedQMISignalInfoIndication(qmiPacket: parsedPacket) {
                
                // So far we have seen no packet that contains NR & LTE signal strengths at the same time,
                // but we've encountered multiple NR packets that do not contain any signal info.
                var texts: [String] = []
                
                if let nr = parsedSignalInfo.nr {
                    texts.append("NR: rsrp = \(formatSignalStrength(nr.rsrp, unit: "dBm")), rsrq = \(formatSignalStrength(nr.rsrq, unit: "dB")), snr = \(formatSignalStrength(nr.snr, unit: "dB"))")
                } else if let lte = parsedSignalInfo.lte {
                    texts.append("LTE: rssi = \(formatSignalStrength(lte.rssi, unit: "dBm")), rsrp = \(formatSignalStrength(lte.rsrp, unit: "dBm")), rsrq = \(formatSignalStrength(lte.rsrq, unit: "dB")), snr = \(formatSignalStrength(lte.snr, unit: "dB"))")
                } else if let gsmRssi = parsedSignalInfo.gsm {
                    texts.append("GSM: rssi = \(formatSignalStrength(gsmRssi, unit: "dBm"))")
                }
                
                if texts.count > 0 {
                    return Text(texts.joined(separator: "\n"))
                        .font(.system(size: 14))
                }
            }
        } else if let ariPacket = packet as? PacketARI {
            if PacketConstants.ariSignalDirection.rawValue == ariPacket.direction
                && PacketConstants.ariSignalGroup == ariPacket.group
                && PacketConstants.ariSignalType == ariPacket.type,
               let data = ariPacket.data,
            let parsedPacket = try? ParsedARIPacket(data: data),
            let parsedSignalInfo = try? ParsedARIRadioSignalIndication(ariPacket: parsedPacket) {
                let ssr = (Double(parsedSignalInfo.signalStrength) / Double(parsedSignalInfo.signalStrengthMax)) * 100
                let sqr = (Double(parsedSignalInfo.signalQuality) / Double(parsedSignalInfo.signalQualityMax)) * 100
                return Text("ssr = \(doubleString(ssr))%, sqr = \(doubleString(sqr))%")
                    .font(.system(size: 14))
            }
        }
        
        return nil
    }
    
    func formatSignalStrength(_ number: (any FixedWidthInteger)?, unit: String) -> String {
        if let number = number {
            // Casting number to String to remove the thousand dot
            // See: https://stackoverflow.com/a/64492495
            return "\(String(number))\(unit)"
        } else {
            return "N/A"
        }
    }
    
}

struct VerificationStateView_Previews: PreviewProvider {
    
    static var previews: some View {
        /*let viewContext = PersistenceController.preview.container.viewContext
        let cell = PersistencePreview.alsCell(context: viewContext)
        let tweakCell = PersistencePreview.tweakCell(context: viewContext, from: cell)
        tweakCell.appleDatabase = cell
        // TODO: JSON for tests
        tweakCell.json = """
[{"RSRP":0,"CellId":12941845,"BandInfo":1,"TAC":45711,"CellType":"CellTypeServing","SectorLat":0,"CellRadioAccessTechnology":"RadioAccessTechnologyLTE","SectorLong":0,"MCC":262,"PID":461,"MNC":2,"DeploymentType":1,"RSRQ":0,"Bandwidth":100,"UARFCN":100},{"timestamp":1672513186.351948}]
"""
        
        do {
            try viewContext.save()
        } catch {
            
        }
        
        PersistenceController.preview.fetchPersistentHistory()
        
        return VerificationStateView(verificationState: tweakCell)
            .environment(\.managedObjectContext, viewContext) */
        Text("TODO")
    }
}
