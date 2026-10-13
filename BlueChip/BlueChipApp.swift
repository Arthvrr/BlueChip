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
        .commands {
            // 1. Menu Préférences (BlueChip > Preferences)
            CommandGroup(replacing: .appSettings) {
                Button("Preferences...") {
                    NotificationCenter.default.post(name: NSNotification.Name("OpenSettings"), object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            
            // 2. Menu Fichier (File > Add Position)
            CommandGroup(replacing: .newItem) {
                Button("Add Position...") {
                    NotificationCenter.default.post(name: NSNotification.Name("OpenAddPosition"), object: nil)
                }
                .keyboardShortcut("n", modifiers: .command) // Cmd + N classique pour un nouvel élément
            }
            
            // 3. Menu Affichage (View > Refresh, Privacy, Next Tab)
            CommandMenu("View Options") {
                Button("Refresh Prices & FX") {
                    NotificationCenter.default.post(name: NSNotification.Name("RefreshPrices"), object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
                
                Button("Toggle Privacy Mode") {
                    NotificationCenter.default.post(name: NSNotification.Name("TogglePrivacy"), object: nil)
                }
                .keyboardShortcut("f", modifiers: .command) // Tu avais demandé Cmd + F
                
                Divider()
                
                Button("Next Tab") {
                    NotificationCenter.default.post(name: NSNotification.Name("NextTab"), object: nil)
                }
                .keyboardShortcut(.tab, modifiers: .control) // Control + Tab
            }
        }
    }
}
