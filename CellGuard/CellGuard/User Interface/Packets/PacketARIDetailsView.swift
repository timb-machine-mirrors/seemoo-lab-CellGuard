//
//  PacketARIDetailsView.swift
//  CellGuard
//
//  Created by Lukas Arnold on 09.06.23.
//

import SwiftUI

struct PacketARIDetailsView: View {
    let packet: ARIPacket
    
    var body: some View {
        List {
            if let data = packet.data {
                if let parsed = try? ParsedARIPacket(data: data) {
                    PacketARIDetailsList(packet: packet, data: data, parsed: parsed)
                } else {
                    Text("Failed to parse the packet's binary data")
                }
            } else {
                Text("Failed to get the packet's binary data.")
            }
            
        }
        .listStyle(.insetGrouped)
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("ARI Packet")
    }
}

private struct PacketARIDetailsList: View {
    
    let packet: ARIPacket
    let data: Data
    let parsed: ParsedARIPacket
    
    var body: some View {
        let definitions = ARIDefinitions.shared
        let groupDef = definitions.groups[parsed.header.group]
        let typeDef = groupDef?.types[parsed.header.type]
        
        return Group {
            Section(header: Text("Packet")) {
                PacketDetailsRow("Protocol", packet.proto ?? "???")
                PacketDetailsRow("Direction", packet.direction ?? "???")
                PacketDetailsRow("Timestamp", date: packet.collected)
                PacketDetailsRow("Size", bytes: data.count)
                PacketDetailsDataRow("Data", data: data)
            }
            Section(header: Text("ARI Header")) {
                PacketDetailsRow("Group ID", hex: parsed.header.group)
                PacketDetailsRow("Group Name", groupDef?.name ?? "???")
                PacketDetailsRow("Sequence Number", hex: parsed.header.sequenceNumber)
                PacketDetailsRow("Length", hex: parsed.header.length)
                PacketDetailsRow("Type ID", hex: parsed.header.type)
                PacketDetailsRow("Type Name", typeDef?.name ?? "???")
                PacketDetailsRow("Transaction", hex: parsed.header.transaction)
                PacketDetailsRow("Acknowledgement", bool: parsed.header.acknowledgement)
            }
            ForEach(parsed.tlvs, id: \.type) { tlv in
                Section(header: Text("TLV")) {
                    PacketDetailsRow("TLV ID", hex: tlv.type)
                    PacketDetailsRow("Version", hex: tlv.version)
                    PacketDetailsRow("Length", bytes: Int(tlv.length))
                    PacketDetailsDataRow("Data", data: tlv.data)
                }
            }
        }
    }
    
}

struct PacketARIDetailsView_Previews: PreviewProvider {
    static var previews: some View {
        let context = PersistenceController.preview.container.viewContext
        let packets = PersistencePreview.packets(context: context)
        
        NavigationView {
            PacketARIDetailsView(packet: packets[3] as! ARIPacket)
        }
        .environment(\.managedObjectContext, context)
    }
}