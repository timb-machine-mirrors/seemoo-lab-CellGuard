//
//  ScanProgressSheet.swift
//  CellGuard
//
//  Created by Lukas Arnold on 01.02.23.
//

import SwiftUI

struct VerificationProgressView: View {
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \TweakCell.collected, ascending: false)],
        predicate: NSPredicate(format: "status == %@", CellStatus.imported.rawValue)
    )
    private var unverifiedCells: FetchedResults<TweakCell>
    
    var body: some View {
        ProgressView {
            Text("Verifying \(unverifiedCells.count) \(unverifiedCells.count == 1 ? "cell" : "cells")")
        }
    }
}

struct VerificationProgressView_Previews: PreviewProvider {
    static var previews: some View {
        VerificationProgressView()
    }
}