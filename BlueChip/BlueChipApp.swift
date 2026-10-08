//
//  BlueChipApp.swift
//  BlueChip
//
//  Created by Arthur Louette on 09/01/2026.
//

import SwiftUI
import SwiftData

@main
struct BlueChipApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar) // Enlève la barre de titre moche de macOS
        // NOUVEAU : On initialise la base de données avec tous tes modèles
        .modelContainer(for: [
            AppSettings.self,
            Position.self,
            DividendYear.self,
            CalendarEvent.self,
            BenchmarkIndex.self,
            Transaction.self,
            GrowthYear.self,
            FundamentalCriterion.self,
            WealthAsset.self,
            WealthLiability.self,
            WatchlistItem.self
        ])
    }
}
