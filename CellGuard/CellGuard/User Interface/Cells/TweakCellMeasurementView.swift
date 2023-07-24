//
//  TweakCellMeasurementView.swift
//  CellGuard
//
//  Created by Lukas Arnold on 21.07.23.
//

import SwiftUI

struct TweakCellMeasurementView: View {
    
    let measurement: TweakCell
    
    var body: some View {
        List {
            if let statusString = measurement.status, let status = CellStatus(rawValue: statusString) {
                TweakCellMeasurementStatusView(measurement: measurement, status: status)
            } else {
                Text("Invalid cell status \(measurement.status ?? "Empty")")
            }
        }
        .navigationTitle("Measurement")
        .navigationBarTitleDisplayMode(.inline)
        .listStyle(.insetGrouped)
    }
    
}

private struct TweakCellMeasurementStatusView: View {
    
    let measurement: TweakCell
    let status: CellStatus
    private let numberFormatter: NumberFormatter = {
        let numberFormatter = NumberFormatter()
        numberFormatter.maximumFractionDigits = 2
        return numberFormatter
    }()
    
    @State var distanceUserAndALS: CellLocationDistance?
    
    var body: some View {
        let techFormatter = CellTechnologyFormatter.from(technology: measurement.technology)
        
        return Group {
            Section(header: Text("Verification Progress")) {
                CellDetailsRow("State", status.humanDescription())
            }
            
            if status >= .processedCell {
                Section(header: Text("ALS Verification")) {
                    if let alsCell = measurement.verification {
                        CellDetailsRow("ALS Counterpart", "Present")
                        if let importedDate = alsCell.imported {
                            CellDetailsRow("Fetched at", mediumDateTimeFormatter.string(from: importedDate))
                        }
                        if let alsLocation = alsCell.location {
                            let (latitude, longitude) = coordinateToDMS(latitude: alsLocation.latitude, longitude: alsLocation.longitude)
                            CellDetailsRow("Latitude", latitude)
                            CellDetailsRow("Longitude", longitude)
                            CellDetailsRow("Accuracy", "± \(string(alsLocation.horizontalAccuracy)) m")
                            
                            CellDetailsRow("Reach", "\(alsLocation.reach) m")
                            CellDetailsRow("ALS Score", alsLocation.score)
                        }
                        CellDetailsRow("Score", "40 / 40")
                    } else {
                        CellDetailsRow("ALS Counterpart", "Not Present")
                        CellDetailsRow("Score", "0 / 40")
                    }
                }
            }
            
            if status >= .processedLocation {
                if let userLocation = measurement.location {
                    Section(header: Text("User Location")) {
                        let (userLatitudeStr, userLongitudeStr) = coordinateToDMS(latitude: userLocation.latitude, longitude: userLocation.longitude)
                        CellDetailsRow("Latitude", userLatitudeStr)
                        CellDetailsRow("Longitude", userLongitudeStr)
                        CellDetailsRow("Horizontal Accuracy", "± \(string(userLocation.horizontalAccuracy)) m")
                        CellDetailsRow("Altitude", "\(string(userLocation.altitude)) m")
                        CellDetailsRow("Vertical Accuracy", "± \(string(userLocation.verticalAccuracy)) m")
                        CellDetailsRow("Speed", "\(string(userLocation.speed)) m/s")
                        CellDetailsRow("Speed Accuracy", "± \(string(userLocation.speedAccuracy)) m/s")
                        CellDetailsRow("Recorded in Background?", "\(userLocation.background)")
                    }
                    .onAppear {
                        let objectId = measurement.objectID
                        DispatchQueue.global(qos: .userInitiated).async {
                            let distance = PersistenceController.basedOnEnvironment().calculateDistance(tweakCell: objectId)
                            DispatchQueue.main.async {
                                distanceUserAndALS = distance
                            }
                        }
                    }
                    
                    Section(header: Text("Distance Verification")) {
                        CellDetailsRow("User Location", "Present")
                        if let distance = distanceUserAndALS {
                            CellDetailsRow("Raw Distance", "\(string(distance.distance)) m")
                            CellDetailsRow("Corrected Distance", "\(string(distance.correctedDistance() / 1000.0)) km")
                            CellDetailsRow("Genuine Percentage", "\(string((1 - distance.score()) * 100.0)) %")
                            CellDetailsRow("Score", "\(Int(1-distance.score()) * 20) / 20")
                        } else if measurement.verification == nil {
                            CellDetailsRow("Score", "0 / 20")
                            CellDetailsRow("Reason", "ALS Location Missing")
                        } else {
                            CellDetailsRow("Score", "Calculating")
                        }
                    }
                } else {
                    Section(header: Text("Distance Verification")) {
                        CellDetailsRow("User Location", "Not Recorded")
                        CellDetailsRow("Score", "20 / 20")
                    }
                }
            }
            
            if status >= .verified {
                Section(header: Text("Packet Verification")) {
                    if let packet = measurement.rejectPacket {
                        CellDetailsRow("Network Reject Packet", "Present")
                        if let packetProto = packet.proto {
                            CellDetailsRow("Protocol", packetProto)
                        }
                        if let packetDirection = packet.direction {
                            CellDetailsRow("Direction", packetDirection)
                        }
                        if let packetCollected = packet.collected {
                            CellDetailsRow("Timestamp", fullMediumDateTimeFormatter.string(from: packetCollected))
                        }
                        if let qmiPacket = packet as? QMIPacket {
                            let (serviceName, messageName) = annotateQMIPacket(packet: qmiPacket)
                            if let serviceName = serviceName {
                                CellDetailsRow("QMI Service", serviceName)
                            }
                            PacketDetailsRow("QMI Service ID", hex: UInt8(qmiPacket.service))
                            if qmiPacket.indication {
                                if let messageName = messageName {
                                    CellDetailsRow("QMI Indication", messageName)
                                }
                                PacketDetailsRow("QMI Indication ID", hex: UInt16(qmiPacket.message))
                            } else {
                                if let messageName = messageName {
                                    CellDetailsRow("QMI Message", messageName)
                                }
                                PacketDetailsRow("QMI Message ID", hex: UInt16(qmiPacket.message))
                            }
                        } else if let ariPacket = packet as? ARIPacket {
                            let (groupName, typeName) = annotateARIPacket(packet: ariPacket)
                            if let groupName = groupName {
                                CellDetailsRow("ARI Group", groupName)
                            }
                            PacketDetailsRow("QMI Group ID", hex: UInt8(ariPacket.group))
                            if let typeName = typeName {
                                CellDetailsRow("ARI Type", typeName)
                            }
                            PacketDetailsRow("QMI Type ID", hex: UInt16(ariPacket.group))
                        }
                        CellDetailsRow("Score", "0 / 40")
                    } else {
                        CellDetailsRow("Network Reject Packet", "Absent")
                        CellDetailsRow("Score", "40 / 40")
                    }
                }
                
                Section(header: Text("Verification Result")) {
                    CellDetailsRow("Score", "\(measurement.score) / 100")
                    if measurement.score >= CellVerifier.pointsSuspiciousThreshold {
                        CellDetailsRow("Verdict", "Trusted", icon: "lock.shield")
                    } else if measurement.score >= CellVerifier.pointsUntrustedThreshold {
                        CellDetailsRow("Verdict", "Suspicious", icon: "shield")
                    } else {
                        CellDetailsRow("Verdict", "Untrusted", icon: "exclamationmark.shield")
                    }
                }
            }
            
            Section(header: Text("Timestamps")) {
                if let collectedDate = measurement.collected {
                    CellDetailsRow("Collected", fullMediumDateTimeFormatter.string(from: collectedDate))
                }
                if let importedDate = measurement.imported {
                    CellDetailsRow("Imported", fullMediumDateTimeFormatter.string(from: importedDate))
                }
            }
            
            Section(header: Text("Radio Access Technology")) {
                if let rat = measurement.technology {
                    CellDetailsRow("Generation", rat)
                }
                CellDetailsRow(techFormatter.frequency(), measurement.frequency)
                if let neighborTechnology = measurement.neighborTechnology {
                    CellDetailsRow("Neighbor", neighborTechnology)
                }
            }
            
            if let json = measurement.json, let jsonPretty = try? self.formatJSON(json: json) {
                Section(header: Text("iOS-Internal Data")) {
                    Text(jsonPretty)
                        .font(Font(UIFont.monospacedSystemFont(ofSize: UIFont.smallSystemFontSize, weight: .regular)))
                }
            }
        }
    }
    
    private func string(_ value: Double, maxDigits: Int = 2) -> String {
        return String(format: "%.2f", value)
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
    
    private func annotateQMIPacket(packet: QMIPacket) -> (String?, String?) {
        let serviceId = UInt8(packet.service)
        let messageId = UInt16(packet.message)
        
        let definitions = QMIDefinitions.shared
        let serviceDef = definitions.services[serviceId]
        let messageDef = packet.indication ? serviceDef?.indications[messageId] : serviceDef?.messages[messageId]
        
        return (serviceDef?.longName, messageDef?.name)
    }
    
    private func annotateARIPacket(packet: ARIPacket) -> (String?, String?) {
        let groupId = UInt8(packet.group)
        let typeId = UInt16(packet.type)
        
        let definitions = ARIDefinitions.shared
        let groupDef = definitions.groups[groupId]
        let typeDef = groupDef?.types[typeId]
        
        return (groupDef?.name, typeDef?.name)
    }
}

struct TweakCellMeasurementView_Previews: PreviewProvider {
    
    static var previews: some View {
        let viewContext = PersistenceController.preview.container.viewContext
        let cell = PersistencePreview.alsCell(context: viewContext)
        let tweakCell = PersistencePreview.tweakCell(context: viewContext, from: cell)
        tweakCell.score = 0
        tweakCell.status = CellStatus.verified.rawValue
        tweakCell.verification = cell
        // TODO: JSON for tests
        tweakCell.json = """
[{"RSRP":0,"CellId":12941845,"BandInfo":1,"TAC":45711,"CellType":"CellTypeServing","SectorLat":0,"CellRadioAccessTechnology":"RadioAccessTechnologyLTE","SectorLong":0,"MCC":262,"PID":461,"MNC":2,"DeploymentType":1,"RSRQ":0,"Bandwidth":100,"UARFCN":100},{"timestamp":1672513186.351948}]
"""
        
        do {
            try viewContext.save()
        } catch {
            
        }
        
        PersistenceController.preview.fetchPersistentHistory()
        
        return TweakCellMeasurementView(measurement: tweakCell)
            .environment(\.managedObjectContext, viewContext)
    }
}
