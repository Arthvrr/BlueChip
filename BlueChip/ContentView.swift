import SwiftUI
import SwiftData
import Combine
import LocalAuthentication

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @StateObject private var viewModel = PortfolioViewModel()
    
    @State private var selectedTab: AppTab = .composition
    @State private var showAddSheet = false
    
    // NOUVEAU : État temporaire pour la recherche globale (Cmd + K)
    @State private var showGlobalSearch = false
    
    // Variables persistantes
    @AppStorage("privacyMode") private var privacyMode = false
    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    @AppStorage("forcePrivacyOnStartup") private var forcePrivacyOnStartup: Bool = false
    @AppStorage("requireAuthOnStartup") private var requireAuthOnStartup: Bool = false
    
    // État de verrouillage (True = l'utilisateur peut voir l'app)
    @State private var isUnlocked: Bool = false
    
    @State private var showAddTransaction = false
    @State private var showAddEvent = false
    @State private var showCheatSheet = false
    @State private var showAbout = false
    @State private var showTutorial = false
    
    @State private var showSearch = false
    @State private var showAICopilot = false
    
    @State private var resumeAIChat = false


    var body: some View {
        Group {
            // SI L'APP EST VERROUILLÉE
            if requireAuthOnStartup && !isUnlocked {
                VStack(spacing: 24) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.blue)
                    
                    Text("BlueChip is Locked")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Authentication is required to view your portfolio.")
                        .foregroundColor(.secondary)
                    
                    Button("Unlock Portfolio") {
                        authenticate()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.top, 10)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.windowBackgroundColor))
                .onAppear { authenticate() }
            }
            // SI L'APP EST DÉVERROUILLÉE (OU SI PAS DE SÉCURITÉ)
            else {
                mainAppView
            }
        }
        .preferredColorScheme(appTheme.colorScheme)
        .onAppear {
            if forcePrivacyOnStartup { privacyMode = true }
            viewModel.initializeData(context: context)
        }
    }
    
    // ==========================================
    // LOGIQUE D'AUTHENTIFICATION (TOUCH ID)
    // ==========================================
    func authenticate() {
        let context = LAContext()
        var error: NSError?

        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock BlueChip to access your financial data.") { success, _ in
                DispatchQueue.main.async {
                    if success { self.isUnlocked = true }
                }
            }
        } else {
            self.isUnlocked = true
        }
    }
    
    // ==========================================
    // LE CORPS DE L'APPLICATION (VUE PRINCIPALE)
    // ==========================================
    var mainAppView: some View {
        VStack(spacing: 0) {
            HStack {
                Text("BlueChip - Stocks Portfolio Manager")
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundColor(.primary)
                Spacer()
                                
                // BOUTON RECHERCHE GLOBALE (Cmd + F)
                Button(action: { NotificationCenter.default.post(name: NSNotification.Name("OpenSearch"), object: nil) }) {
                    Image(systemName: "magnifyingglass")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }.buttonStyle(.plain)
                .padding(.trailing, 8)
                
                // BOUTON IA COPILOT (Cmd + I)
                Button(action: { NotificationCenter.default.post(name: NSNotification.Name("OpenAICopilot"), object: nil) }) {
                    Image(systemName: "sparkles")
                        .font(.title2)
                        .foregroundColor(.secondary) // En bleu pour bien le démarquer !
                }.buttonStyle(.plain)
                .padding(.trailing, 8)
                

                // NOUVEAU BOUTON TUTORIEL
                Button(action: {
                    // Remplace par le nom exact de la notification ou de la variable d'état de ton tutoriel
                    NotificationCenter.default.post(name: NSNotification.Name("OpenTutorial"), object: nil)
                }) {
                    Image(systemName: "questionmark.circle")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)

                Button(action: { withAnimation { privacyMode.toggle() } }) {
                    Image(systemName: privacyMode ? "eye.slash" : "eye").font(.body)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)

                Button(action: { viewModel.showSettings = true }) {
                    Image(systemName: "gearshape.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8) // Ajout d'un padding ici pour équilibrer l'espacement avant le bouton Refresh

                Button(action: { performRefresh() }) {
                    if viewModel.isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(viewModel.isLoading)
                .buttonStyle(.bordered)
                .padding(.trailing, 8)

                Button(action: { showAddSheet = true }) {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)

            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 10)
            
            HStack {
                CustomTabBar(selectedTab: $selectedTab)
                Spacer()
            }
            Divider()
            
            Group {
                switch selectedTab {
                case .composition: CompositionTabView(viewModel: viewModel, privacyMode: $privacyMode)
                case .growth: GrowthView(viewModel: viewModel, privacyMode: $privacyMode)
                case .dividends: DividendsView(viewModel: viewModel, privacyMode: $privacyMode)
                case .benchmark: BenchmarkView(viewModel: viewModel, privacyMode: $privacyMode)
                case .transactions: TransactionsView(viewModel: viewModel, privacyMode: $privacyMode)
                case .projection: ProjectionView(viewModel: viewModel, privacyMode: $privacyMode)
                case .watchlist: WatchListView(viewModel: viewModel, privacyMode: $privacyMode)
                case .calendar: CalendarView(viewModel: viewModel, privacyMode: $privacyMode)
                case .simulation: SimulationView(viewModel: viewModel, privacyMode: $privacyMode)
                case .exposure: ExposureView(viewModel: viewModel, privacyMode: $privacyMode)
                case .fundamentals: FundamentalsView(viewModel: viewModel, privacyMode: $privacyMode)
                case .wealth: WealthView(viewModel: viewModel, privacyMode: $privacyMode)
                case .valuation: ValuationView(viewModel: viewModel, privacyMode: $privacyMode)
                
                default:
                    VStack(spacing: 20) {
                        Image(systemName: "hammer.fill").font(.system(size: 50)).foregroundColor(.secondary)
                        Text("\(selectedTab.rawValue) view is under construction.").font(.title).foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .navigationTitle("")
        
        // --- TOUTES LES MODALES (SHEETS) ---
        .sheet(isPresented: $showAddSheet) { EditPositionView(viewModel: viewModel, position: nil) }
        .sheet(isPresented: $viewModel.showSettings) { SettingsView(viewModel: viewModel) }
        
        // La modale temporaire pour la recherche globale
        .sheet(isPresented: $showGlobalSearch) {
            VStack(spacing: 16) {
                Image(systemName: "magnifyingglass").font(.system(size: 50)).foregroundColor(.blue)
                Text("Global Search").font(.title).fontWeight(.bold)
                Text("Appuyez sur Cmd + F depuis n'importe où.\nMoteur de recherche en construction !").multilineTextAlignment(.center).foregroundColor(.secondary)
                Button("Close") { showGlobalSearch = false }.keyboardShortcut(.cancelAction)
            }
            .padding(40)
            .frame(width: 400, height: 300)
        }
        
        // --- NOUVELLES MODALES (SHEETS) ---
        .sheet(isPresented: $showAddTransaction) {
            AddEditTransactionView(viewModel: viewModel, transaction: nil)
        }
        .sheet(isPresented: $showAddEvent) {
            AddEditEventSheet(viewModel: viewModel, event: nil, initialDate: Date())
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenAddTransaction"))) { _ in
            showAddTransaction = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenAddEvent"))) { _ in
            showAddEvent = true
        }

        .sheet(isPresented: $showCheatSheet) { CheatSheetView() }
        .sheet(isPresented: $showAbout) { AboutBlueChipView() }
        .sheet(isPresented: $showTutorial) { TutorialView(currentTab: selectedTab) }
        
        .sheet(isPresented: $showAICopilot) {
            AICopilotView(viewModel: viewModel, currentTab: selectedTab, resumeChat: resumeAIChat)
        }


        
        // --- NOUVEAUX ÉCOUTEURS ---
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenAddTransaction"))) { _ in showAddTransaction = true }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenAddEvent"))) { _ in showAddEvent = true }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenCheatSheet"))) { _ in showCheatSheet = true }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenAbout"))) { _ in showAbout = true }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenTutorial"))) { _ in showTutorial = true }

        
        // --- ÉCOUTEURS DE NOTIFICATIONS POUR LES RACCOURCIS CLAVIER ---
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenSettings"))) { _ in viewModel.showSettings = true }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenAddPosition"))) { _ in showAddSheet = true }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TogglePrivacy"))) { _ in withAnimation { privacyMode.toggle() } }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RefreshPrices"))) { _ in performRefresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NextTab"))) { _ in cycleToNextTab() }
        
        // Nouveaux écouteurs
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("PrevTab"))) { _ in cycleToPreviousTab() }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("GlobalSearch"))) { _ in showGlobalSearch = true }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("LockApp"))) { _ in lockApp() }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ToggleFullScreen"))) { _ in
            if let window = NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first { window.toggleFullScreen(nil)}}
        
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenSearch"))) { _ in showSearch = true}
        //.onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenAICopilot"))) { _ in showAICopilot = true}
        
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenAICopilot"))) { _ in
            // L'application vérifie silencieusement s'il y a une sauvegarde pour la page actuelle
            // Si oui, ça reprend. Si non, ça lance une nouvelle analyse !
            resumeAIChat = ChatHistoryManager.shared.hasHistory(for: selectedTab.rawValue)
            showAICopilot = true
        }
    }
    
    // ==========================================
    // MÉTHODES UTILITAIRES POUR LES RACCOURCIS
    // ==========================================
    
    private func performRefresh() {
        Task {
            await viewModel.refreshPrices()
            let service = YahooFinanceService()
            if let fxData = await service.fetchStockData(for: "EUR=X") {
                await MainActor.run {
                    for pos in viewModel.positions {
                        if pos.currency.uppercased() == "USD" { pos.usdToEurRate = fxData.price }
                        else if pos.currency.uppercased() == "EUR" { pos.usdToEurRate = 1.0 }
                    }
                    viewModel.objectWillChange.send()
                }
            }
        }
    }
    
    private func lockApp() {
        // Force l'activation de la sécurité et verrouille immédiatement
        requireAuthOnStartup = true
        isUnlocked = false
    }
    
    private func cycleToNextTab() {
        let allTabs = AppTab.allCases
        if let currentIndex = allTabs.firstIndex(of: selectedTab) {
            let nextIndex = (currentIndex + 1) % allTabs.count
            withAnimation { selectedTab = allTabs[nextIndex] }
        }
    }
    
    private func cycleToPreviousTab() {
        let allTabs = AppTab.allCases
        if let currentIndex = allTabs.firstIndex(of: selectedTab) {
            // L'astuce mathématique pour reculer dans un tableau sans faire d'erreur "Index Out Of Bounds"
            let prevIndex = (currentIndex - 1 + allTabs.count) % allTabs.count
            withAnimation { selectedTab = allTabs[prevIndex] }
        }
    }
}

