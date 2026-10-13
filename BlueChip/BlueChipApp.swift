import SwiftUI
import SwiftData

@main
struct BlueChipApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar) // Enlève la barre de titre moche de macOS
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
            // 1. Menu Préférences & Sécurité (BlueChip)
            CommandGroup(replacing: .appSettings) {
                Button("Preferences...") {
                    NotificationCenter.default.post(name: NSNotification.Name("OpenSettings"), object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
                
                Divider()
                
                Button("Lock Application") {
                    NotificationCenter.default.post(name: NSNotification.Name("LockApp"), object: nil)
                }
                .keyboardShortcut("l", modifiers: .command)
            }
            
            // 2. Menu Fichier (File > Add Position)
            CommandGroup(replacing: .newItem) {
                Button("Add Position...") {
                    NotificationCenter.default.post(name: NSNotification.Name("OpenAddPosition"), object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            
            // 3. Menu Navigation & Actions
            CommandMenu("Actions & Navigation") {
                Button("Global Search") {
                    NotificationCenter.default.post(name: NSNotification.Name("GlobalSearch"), object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)
                
                Divider()
                
                Button("Refresh Prices & FX") {
                    NotificationCenter.default.post(name: NSNotification.Name("RefreshPrices"), object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
                
                Button("Toggle Privacy Mode") {
                    NotificationCenter.default.post(name: NSNotification.Name("TogglePrivacy"), object: nil)
                }
                .keyboardShortcut("k", modifiers: .command)
                
                Divider()
                
                Button("Next Tab") {
                    NotificationCenter.default.post(name: NSNotification.Name("NextTab"), object: nil)
                }
                .keyboardShortcut(.tab, modifiers: .control)
                
                Button("Previous Tab") {
                    NotificationCenter.default.post(name: NSNotification.Name("PrevTab"), object: nil)
                }
                .keyboardShortcut(.tab, modifiers: [.control, .shift])
                
                Button("Toggle Full Screen") {
                    NotificationCenter.default.post(name: NSNotification.Name("ToggleFullScreen"), object: nil)
                }
                .keyboardShortcut("f", modifiers: [.command, .control]) // Cmd + Control + F

            }
        }
    }
}

