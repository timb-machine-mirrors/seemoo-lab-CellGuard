//
//  CellListFilterView.swift
//  CellGuard
//
//  Created by Lukas Arnold on 23.07.23.
//

import CoreData
import SwiftUI

struct CellListFilterSettings {
    
    var status: CellListFilterStatus = .all
    var study: CellListFilterStudyOptions = .all
    
    var timeFrame: CellListFilterTimeFrame = .live
    var date: Date = Calendar.current.startOfDay(for: Date())
    
    var technology: ALSTechnology?
    var country: Int?
    var network: Int?
    var area: Int?
    var cell: Int?
    
    func predicates(startDate: Date?, endDate: Date?) -> [NSPredicate] {
        var predicateList: [NSPredicate] = [
            NSPredicate(format: "cell != nil"),
            NSPredicate(format: "pipeline == %@", Int(primaryVerificationPipeline.id) as NSNumber)
        ]
        
        if let technology = technology {
            predicateList.append(NSPredicate(format: "cell.technology == %@", technology.rawValue))
        }
        
        if let country = country {
            predicateList.append(NSPredicate(format: "cell.country == %@", country as NSNumber))
        }
        
        if let network = network {
            predicateList.append(NSPredicate(format: "cell.network == %@", network as NSNumber))
        }
        
        if let area = area {
            predicateList.append(NSPredicate(format: "cell.area == %@", area as NSNumber))
        }
        
        if let cell = cell {
            predicateList.append(NSPredicate(format: "cell.cell == %@", cell as NSNumber))
        }
        
        if let start = startDate {
            predicateList.append(NSPredicate(format: "%@ <= cell.collected", start as NSDate))
        }
        if let end = endDate {
            predicateList.append(NSPredicate(format: "cell.collected <= %@", end as NSDate))
        }
        
        let thresholdSuspicious = primaryVerificationPipeline.pointsSuspicious as NSNumber
        let thresholdUntrusted = primaryVerificationPipeline.pointsUntrusted as NSNumber
        
        switch (status) {
        case .all:
            break
        case .processing:
            predicateList.append(NSPredicate(format: "finished == NO"))
        case .trusted:
            predicateList.append(NSPredicate(format: "finished == YES"))
            predicateList.append(NSPredicate(format: "score >= %@", thresholdSuspicious))
        case .anomalous:
            predicateList.append(NSPredicate(format: "finished == YES"))
            predicateList.append(NSPredicate(format: "score >= %@ and score < %@", thresholdUntrusted, thresholdSuspicious))
        case .suspicious:
            predicateList.append(NSPredicate(format: "finished == YES"))
            predicateList.append(NSPredicate(format: "score < %@", thresholdUntrusted))
        }
        
        switch (study) {
        case .all:
            break
        case .submitted:
            predicateList.append(NSPredicate(format: "cell.study != nil and cell.study.uploaded != nil"))
        }

        return predicateList
    }
    
    func applyTo(request: NSFetchRequest<VerificationState>) {
        var beginDate: Date
        var endDate: Date
        let calendar = Calendar.current
        
        switch (timeFrame) {
        case .live:
            beginDate = calendar.startOfDay(for: Date())
            endDate = calendar.date(byAdding: .day, value: 1, to: beginDate)!
        case .pastDay:
            beginDate = calendar.startOfDay(for: date)
            endDate = calendar.date(byAdding: .day, value: 1, to: beginDate)!
        case .pastDays:
            beginDate = calendar.startOfDay(for: date)
            endDate = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date()))!
        }

        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates(startDate: beginDate, endDate: endDate))
        request.relationshipKeyPathsForPrefetching = ["cell"]
    }
    
}

enum CellListFilterTimeFrame: String, CaseIterable, Identifiable {
    case live, pastDay, pastDays
    
    var id: Self { self }
}

enum CellListFilterStatus: String, CaseIterable, Identifiable {
    case all, processing, trusted, anomalous, suspicious
    
    var id: Self { self }
}

enum CellListFilterCustomOptions: String, CaseIterable, Identifiable {
    case all, custom
    
    var id: Self { self }
}

enum CellListFilterPredefinedOptions: String, CaseIterable, Identifiable {
    case all, predefined, custom
    
    var id: Self { self }
}

enum CellListFilterStudyOptions: String, CaseIterable, Identifiable {
    case all, submitted
    
    var id: Self { self }
}

struct CellListFilterView: View {
    let close: () -> Void
    
    @Binding var settingsBound: CellListFilterSettings
    @State var settings: CellListFilterSettings = CellListFilterSettings()
    
    init(settingsBound: Binding<CellListFilterSettings>, close: @escaping () -> Void) {
        self.close = close
        self._settingsBound = settingsBound
        self._settings = State(wrappedValue: self._settingsBound.wrappedValue)
    }
    
    var body: some View {
        CellListFilterSettingsView(settings: $settings, save: {
            self.settingsBound = settings
            self.close()
        })
        .navigationTitle("Filter")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                // TOOD: Somehow taps on it result in the navigation stack disappearing on iOS 14
                if #available(iOS 15, *) {
                    Button {
                        self.settingsBound = settings
                        self.close()
                    } label: {
                        Text("Apply")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}


private struct CellListFilterSettingsView: View {
    
    @Binding var settings: CellListFilterSettings
    let save: () -> Void
    
    var body: some View {
        // TODO: Somehow the Pickers that open a navigation selection menu pose an issue for the navigation bar on iOS 14
        // If the "Apply" button is pressed afterwards, the "< Back" button vanishes from the navigation bar
        Form {
            Section(header: Text("Cells")) {
                // See: https://stackoverflow.com/a/59348094
                Picker("Technology", selection: $settings.technology) {
                    Text("All").tag(nil as ALSTechnology?)
                    ForEach(ALSTechnology.allCases) { Text($0.rawValue).tag($0 as ALSTechnology?) }
                }
                
                LabelNumberField("Country", "MCC", $settings.country)
                LabelNumberField("Network", "MNC", $settings.network)
                LabelNumberField("Area", "LAC or TAC", $settings.area)
                LabelNumberField("Cell", "Cell ID", $settings.cell)
            }
            Section(header: Text("Verification")) {
                Picker("Status", selection: $settings.status) {
                    ForEach(CellListFilterStatus.allCases) { Text($0.rawValue.capitalized) }
                }
            }
            Section(header: Text("Data")) {
                Picker("Display", selection: $settings.timeFrame) {
                    Text("Live").tag(CellListFilterTimeFrame.live)
                    Text("Recorded").tag(CellListFilterTimeFrame.pastDay)
                }
                if settings.timeFrame == .pastDay {
                    DatePicker("Day", selection: $settings.date, in: ...Date(), displayedComponents: [.date])
                }
            }
            
            Section(header: Text("Study")) {
                Picker("Status", selection: $settings.study) {
                    Text("All").tag(CellListFilterStudyOptions.all)
                    Text("Submitted").tag(CellListFilterStudyOptions.submitted)
                }
            }
            
            if #unavailable(iOS 15) {
                Button {
                    save()
                } label: {
                    HStack {
                        Image(systemName: "tray.and.arrow.down")
                        Text("Apply")
                        Spacer()
                    }
                }
            }
        }
    }
    
}

private struct LabelNumberField: View {
    
    let label: String
    let hint: String
    let numberBinding: Binding<Int?>
    
    init(_ label: String, _ hint: String, _ numberBinding: Binding<Int?>) {
        self.label = label
        self.hint = hint
        self.numberBinding = numberBinding
    }
    
    var body: some View {
        HStack {
            Text(label)
            TextField(hint, text: positiveNumberBinding(numberBinding))
                .multilineTextAlignment(.trailing)
        }
        .keyboardType(.numberPad)
        .disableAutocorrection(true)
    }
    
    private func positiveNumberBinding(_ property: Binding<Int?>) -> Binding<String> {
        // See: https://stackoverflow.com/a/65385643
        return Binding(
            get: {
                if let number = property.wrappedValue {
                    return String(number)
                } else {
                    return ""
                }
            },
            set: {
                if let number = Int($0), number >= 0 {
                    property.wrappedValue = number
                } else {
                    property.wrappedValue = nil
                }
            }
        )
    }

    
}

struct CellListFilterView_Previews: PreviewProvider {
    static var previews: some View {
        @State var settings = CellListFilterSettings()
        
        NavigationView {
            CellListFilterView(settingsBound: $settings) {
                // Doing nothing
            }
        }
    }
}
