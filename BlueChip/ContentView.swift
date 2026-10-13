import SwiftUI
import SwiftData
import Combine

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @StateObject private var viewModel = PortfolioViewModel()
    
    @State private var selectedTab: AppTab = .composition
    @State private var showAddSheet = false
    @AppStorage("privacyMode") private var privacyMode = false
    @AppStorage("appTheme") private var appTheme: AppTheme = .system

    var body: some View {
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
                
                // MODIFIÉ : Utilisation de viewModel.showSettings
                Button(action: { viewModel.showSettings = true }) {
                    Image(systemName: "gearshape.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }.buttonStyle(.plain)
                .keyboardShortcut(",", modifiers: .command)
                
                Button(action: {
                    Task {
                        // 1. Mise à jour des prix des actions
                        await viewModel.refreshPrices()
                        
                        // 2. Récupération du taux de change en direct (USD -> EUR)
                        let service = YahooFinanceService()
                        if let fxData = await service.fetchStockData(for: "EUR=X") {
                            await MainActor.run {
                                // On met à jour toutes les positions concernées
                                for pos in viewModel.positions {
                                    if pos.currency.uppercased() == "USD" {
                                        pos.usdToEurRate = fxData.price
                                    } else if pos.currency.uppercased() == "EUR" {
                                        pos.usdToEurRate = 1.0
                                    }
                                }
                                // On signale à l'interface de se redessiner
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
        
        // MODIFIÉ : La modale écoute maintenant viewModel.showSettings
        // ... fin de ton ContentView ...
        .sheet(isPresented: $viewModel.showSettings) {
            SettingsView(viewModel: viewModel)
        }
        .onAppear {
            viewModel.initializeData(context: context)
        }
        .preferredColorScheme(appTheme.colorScheme)
        
        // NOUVEAU : Écoute le clic du menu système et ouvre la modale
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenSettings"))) { _ in
            viewModel.showSettings = true
        }
    }
}

