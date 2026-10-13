import SwiftUI
import SwiftData
import Combine
import LocalAuthentication // <-- REQUIS POUR TOUCH ID / MOT DE PASSE

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @StateObject private var viewModel = PortfolioViewModel()
    
    @State private var selectedTab: AppTab = .composition
    @State private var showAddSheet = false
    
    // Variables persistantes
    @AppStorage("privacyMode") private var privacyMode = false
    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    @AppStorage("forcePrivacyOnStartup") private var forcePrivacyOnStartup: Bool = false
    @AppStorage("requireAuthOnStartup") private var requireAuthOnStartup: Bool = false
    
    // État de verrouillage (True = l'utilisateur peut voir l'app)
    @State private var isUnlocked: Bool = false

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
            // Si le mode confidentialité forcé est activé, on floute au lancement
            if forcePrivacyOnStartup {
                privacyMode = true
            }
            viewModel.initializeData(context: context)
        }
    }
    
    // ==========================================
    // LOGIQUE D'AUTHENTIFICATION (TOUCH ID)
    // ==========================================
    func authenticate() {
        let context = LAContext()
        var error: NSError?

        // Vérifie si le Mac supporte la biométrie ou le mot de passe
        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock BlueChip to access your financial data.") { success, authenticationError in
                // Le résultat est renvoyé sur un thread secondaire, on repasse sur le Main
                DispatchQueue.main.async {
                    if success {
                        // Déverrouillé avec succès !
                        self.isUnlocked = true
                    } else {
                        // Échec (l'utilisateur a annulé ou s'est trompé)
                        // L'écran de verrouillage reste affiché avec le bouton "Unlock Portfolio"
                    }
                }
            }
        } else {
            // Si le Mac n'a ni mot de passe ni Touch ID configuré, on laisse passer
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
                
                Button(action: { withAnimation { privacyMode.toggle() } }) {
                    Image(systemName: privacyMode ? "eye.slash" : "eye").font(.body)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
                
                Button(action: { viewModel.showSettings = true }) {
                    Image(systemName: "gearshape.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }.buttonStyle(.plain)
                
                Button(action: {
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
                }) {
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
        .sheet(isPresented: $showAddSheet) { EditPositionView(viewModel: viewModel, position: nil) }
        .sheet(isPresented: $viewModel.showSettings) { SettingsView(viewModel: viewModel) }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenSettings"))) { _ in
            viewModel.showSettings = true
        }
    }
}

