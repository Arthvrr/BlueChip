import SwiftUI
import SwiftData
import CoreSpotlight

@main
struct BlueChipApp: App {
    
    // 1. CRÉATION DU CONTENEUR PARTAGÉ (L'UNIQUE CERVEAU 🧠)
    @StateObject private var sharedViewModel = PortfolioViewModel()
    
    static let sharedModelContainer: ModelContainer = {
        let schema = Schema([
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
            WatchlistItem.self,
            InvestmentJournal.self,
            JournalEntry.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    
    // SUPPRIMÉ : Le menuViewModel séparé qui causait la désynchronisation
    
    var body: some Scene {
        WindowGroup {
            // On passe notre unique cerveau à la vue principale
            ContentView(viewModel: sharedViewModel)
                .onAppear {
                    NotificationManager.shared.requestAuthorization()
                }
                // GESTION DU CLIC SPOTLIGHT
                .onContinueUserActivity(CSSearchableItemActionType) { userActivity in
                    if let uniqueIdentifier = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String {
                        
                        NSApp.activate(ignoringOtherApps: true)
                        if NSApp.windows.isEmpty {
                            NSApp.sendAction(Selector(("showWindow:")), to: nil, from: nil)
                        }
                        
                        if uniqueIdentifier == "action_add_transaction" {
                            NotificationCenter.default.post(name: NSNotification.Name("OpenAddTransaction"), object: nil)
                        } else if uniqueIdentifier == "action_add_position" {
                            NotificationCenter.default.post(name: NSNotification.Name("OpenAddPosition"), object: nil)
                        } else if uniqueIdentifier == "action_add_event" {
                            NotificationCenter.default.post(name: NSNotification.Name("OpenAddEvent"), object: nil)
                        }
                        else if uniqueIdentifier.starts(with: "page_") {
                            NotificationCenter.default.post(name: NSNotification.Name("NavigateToSpotlightPage"), object: uniqueIdentifier)
                        }
                        else if uniqueIdentifier.starts(with: "position_") {
                            let idString = uniqueIdentifier.replacingOccurrences(of: "position_", with: "")
                            NotificationCenter.default.post(name: NSNotification.Name("OpenPositionFromSpotlight"), object: idString)
                        }
                        else if uniqueIdentifier.starts(with: "watchlist_") {
                            NotificationCenter.default.post(name: NSNotification.Name("NavigateToSpotlightPage"), object: "page_watchlist")
                        }
                        else if uniqueIdentifier.starts(with: "event_") {
                            NotificationCenter.default.post(name: NSNotification.Name("NavigateToSpotlightPage"), object: "page_calendar")
                        }
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .modelContainer(BlueChipApp.sharedModelContainer)
        
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About BlueChip") {
                    NotificationCenter.default.post(name: NSNotification.Name("OpenAbout"), object: nil)
                }
            }
            
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
            
            CommandGroup(replacing: .newItem) {
                Button("Add Position...") {
                    NotificationCenter.default.post(name: NSNotification.Name("OpenAddPosition"), object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
                
                Button("Add Transaction...") {
                    NotificationCenter.default.post(name: NSNotification.Name("OpenAddTransaction"), object: nil)
                }
                .keyboardShortcut("t", modifiers: .command)
                
                Button("Add Calendar Event...") {
                    NotificationCenter.default.post(name: NSNotification.Name("OpenAddEvent"), object: nil)
                }
                .keyboardShortcut("e", modifiers: .command)
                
                Button("Add Thesis Log...") {
                    NotificationCenter.default.post(name: NSNotification.Name("OpenAddThesisLog"), object: nil)
                }
                .keyboardShortcut("b", modifiers: .command)
            }
            
            CommandMenu("Tools") {
                Button("Global Search") {
                    NotificationCenter.default.post(name: NSNotification.Name("GlobalSearch"), object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)
                
                Button("AI Copilot Insights") {
                    NotificationCenter.default.post(name: NSNotification.Name("OpenAICopilot"), object: nil)
                }
                .keyboardShortcut("i", modifiers: .command)
                
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
                .keyboardShortcut("f", modifiers: [.command, .control])
            }
            
            CommandGroup(replacing: .help) {
                Button("Page Tutorial") {
                    NotificationCenter.default.post(name: NSNotification.Name("OpenTutorial"), object: nil)
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                
                Button("Keyboard Shortcuts") {
                    NotificationCenter.default.post(name: NSNotification.Name("OpenCheatSheet"), object: nil)
                }
                .keyboardShortcut("/", modifiers: .command)
            }
        }
        
        // 4. BARRE DES MENUS
        MenuBarExtra("BlueChip", image: "MenuBarIcon") {
            // On passe EXACTEMENT le même cerveau à la barre des menus
            MenuBarDashboardView(viewModel: sharedViewModel)
                .onAppear {
                    // Si l'app est lancée en tâche de fond (fenêtre fermée), on s'assure
                    // que les données sont bien récupérées par l'unique ViewModel
                    let context = BlueChipApp.sharedModelContainer.mainContext
                    sharedViewModel.fetchData(context: context)
                }
        }
        .menuBarExtraStyle(.window)
    }
}
