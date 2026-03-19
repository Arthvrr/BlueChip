import SwiftUI
import Combine

// MARK: - 1. LE MODÈLE (DATA)
struct Position: Identifiable, Codable {
    var id = UUID()
    let ticker: String
    var quantity: Double
    var averageCost: Double // PRU
    var currentPrice: Double
    var currency: String = "EUR"
    var usdToEurRate: Double = 1.0
    var annualDividendNet: Double = 0.0
    
    // Calculs
    var investedAmountEUR: Double {
        let rate = currency == "USD" ? usdToEurRate : 1.0
        return quantity * averageCost * rate
    }
    
    var currentValueEUR: Double {
        let rate = currency == "USD" ? usdToEurRate : 1.0
        return quantity * currentPrice * rate
    }
    
    var totalDividendEUR: Double {
        let rate = currency == "USD" ? usdToEurRate : 1.0
        return quantity * annualDividendNet * rate
    }
    
    var roiValue: Double { currentValueEUR - investedAmountEUR }
    var roiPercent: Double {
        guard investedAmountEUR > 0 else { return 0 }
        return roiValue / investedAmountEUR
    }
}

// Structure pour sauvegarder tout le portefeuille d'un coup
struct PortfolioSaveData: Codable {
    var positions: [Position]
    var availableCash: Double
    var manuallyInvested: Double
}

// MARK: - 2. LE SERVICE YAHOO (RÉSEAU)
class YahooFinanceService {
    func fetchStockData(for ticker: String) async -> (price: Double, currency: String)? {
        let cleanTicker = ticker.trimmingCharacters(in: .whitespacesAndNewlines)
        let urlString = "https://query1.finance.yahoo.com/v8/finance/chart/\(cleanTicker)?interval=1d"
        guard let url = URL(string: urlString) else { return nil }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
            if let chart = json?["chart"] as? [String: Any],
               let result = chart["result"] as? [[String: Any]],
               let meta = result.first?["meta"] as? [String: Any],
               let price = meta["regularMarketPrice"] as? Double {
                let currency = meta["currency"] as? String ?? "EUR"
                return (price, currency)
            }
        } catch {
            print("Erreur Yahoo pour \(ticker): \(error.localizedDescription)")
        }
        return nil
    }
    
    func fetchUSDEURRate() async -> Double {
        if let data = await fetchStockData(for: "EUR=X") { return data.price }
        return 1.0
    }
}

// MARK: - 3. LE VIEW MODEL (LOGIQUE & SAUVEGARDE)
@MainActor
class PortfolioViewModel: ObservableObject {
    @Published var positions: [Position] = [] { didSet { saveData() } }
    @Published var availableCash: Double = 0.0 { didSet { saveData() } }
    @Published var manuallyInvested: Double = 0.0 { didSet { saveData() } }
    @Published var isLoading = false
    
    @Published var sortOrder = [KeyPathComparator(\Position.ticker)] {
        didSet { positions.sort(using: sortOrder) }
    }
    
    private let yahooService = YahooFinanceService()
    
    // Agrégations pour le Dashboard
    var positionsInvestedSum: Double { positions.reduce(0) { $0 + $1.investedAmountEUR } }
    var totalValue: Double { positions.reduce(0) { $0 + $1.currentValueEUR } }
    var manuallyInvestedPlusCash: Double { manuallyInvested + availableCash }
    var totalROIValue: Double { totalValue - positionsInvestedSum }
    var totalROIPercent: Double { positionsInvestedSum > 0 ? totalROIValue / positionsInvestedSum : 0 }
    var positionCount: Int { positions.count }
    var totalDividends: Double { positions.reduce(0) { $0 + $1.totalDividendEUR } }
    var portfolioYield: Double { positionsInvestedSum > 0 ? totalDividends / positionsInvestedSum : 0 }
    
    init() {
        loadData()
        Task { await refreshPrices() }
    }
    
    func refreshPrices() async {
        isLoading = true
        let currentUsdToEurRate = await yahooService.fetchUSDEURRate()
        let tickersToFetch = Array(Set(positions.map { $0.ticker }))
        
        for ticker in tickersToFetch {
            if let data = await yahooService.fetchStockData(for: ticker) {
                for i in 0..<self.positions.count {
                    if self.positions[i].ticker == ticker {
                        self.positions[i].currentPrice = data.price
                        self.positions[i].currency = data.currency
                        self.positions[i].usdToEurRate = currentUsdToEurRate
                    }
                }
            }
        }
        
        self.positions.sort(using: sortOrder)
        saveData()
        isLoading = false
    }
    
    func addPosition(ticker: String, quantity: Double, pru: Double, dividend: Double) {
        let newPos = Position(ticker: ticker.uppercased(), quantity: quantity, averageCost: pru, currentPrice: pru, annualDividendNet: dividend)
        positions.append(newPos)
        positions.sort(using: sortOrder)
        Task { await refreshPrices() }
    }
    
    func deletePosition(id: UUID) {
        positions.removeAll { $0.id == id }
    }
    
    // MARK: - Persistance des données (FICHIER JSON PHYSIQUE)
    private func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0]
    }
    
    private var saveFileURL: URL {
        getDocumentsDirectory().appendingPathComponent("BlueChip_Data.json")
    }
    
    func saveData() {
        let dataToSave = PortfolioSaveData(
            positions: positions,
            availableCash: availableCash,
            manuallyInvested: manuallyInvested
        )
        
        do {
            let encoded = try JSONEncoder().encode(dataToSave)
            try encoded.write(to: saveFileURL, options: [.atomic])
            print("✅ JSON SAUVEGARDÉ ICI : \(saveFileURL.path)")
        } catch {
            print("❌ ERREUR D'ÉCRITURE JSON : \(error.localizedDescription)")
        }
    }
    
    func loadData() {
        do {
            let data = try Data(contentsOf: saveFileURL)
            let decoded = try JSONDecoder().decode(PortfolioSaveData.self, from: data)
            
            self.positions = decoded.positions.sorted(using: sortOrder)
            self.availableCash = decoded.availableCash
            self.manuallyInvested = decoded.manuallyInvested
            
            print("✅ JSON CHARGÉ DEPUIS : \(saveFileURL.path)")
        } catch {
            print("ℹ️ Fichier JSON introuvable (C'est normal si c'est le premier lancement).")
        }
    }
}

// MARK: - 4. COMPOSANTS UI
struct DashboardCard: View {
    let title: String
    let value: String
    var titleIcon: String? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.subheadline).foregroundColor(.secondary).lineLimit(1).minimumScaleFactor(0.8)
                if let icon = titleIcon { Image(systemName: icon).foregroundColor(.secondary).font(.caption) }
            }
            Text(value).font(.title2).fontWeight(.bold).lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

struct AddPositionView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: PortfolioViewModel
    @State private var ticker: String = ""
    @State private var quantity: Double = 0
    @State private var pru: Double = 0
    @State private var dividend: Double = 0
    
    var body: some View {
        Form {
            Section(header: Text("Nouvelle Position").font(.headline)) {
                TextField("Ticker (ex: AAPL, MC.PA)", text: $ticker)
                TextField("Quantité", value: $quantity, format: .number)
                TextField("PRU (Devise d'origine)", value: $pru, format: .number)
                TextField("Dividende net par action", value: $dividend, format: .number)
            }.padding()
            HStack {
                Button("Annuler") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Ajouter") {
                    if !ticker.isEmpty && quantity > 0 {
                        viewModel.addPosition(ticker: ticker, quantity: quantity, pru: pru, dividend: dividend)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }.padding()
        }.frame(width: 350).padding()
    }
}

struct SimpleNumberEditView: View {
    @Environment(\.dismiss) var dismiss
    let title: String
    @Binding var value: Double
    @State private var input: Double = 0
    
    var body: some View {
        Form {
            Section(header: Text(title).font(.headline)) { TextField("Montant (€)", value: $input, format: .number) }.padding()
            HStack {
                Button("Annuler") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Enregistrer") { value = input; dismiss() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }.padding()
        }
        .frame(width: 300).padding()
        .onAppear { input = value }
    }
}

// MARK: - 5. VUE PRINCIPALE
struct ContentView: View {
    @StateObject private var viewModel = PortfolioViewModel()
    @State private var selection: Set<Position.ID> = []
    
    @State private var showAddSheet = false
    @State private var showCashSheet = false
    @State private var showInvestedSheet = false

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 24) {
                
                // --- LES 8 CASES DU DASHBOARD ---
                VStack(spacing: 16) {
                    HStack(spacing: 16) {
                        Button(action: { showCashSheet = true }) {
                            DashboardCard(title: "Cash", value: viewModel.availableCash.formatted(.currency(code: "EUR")), titleIcon: "pencil")
                        }.buttonStyle(.plain)
                        
                        Button(action: { showInvestedSheet = true }) {
                            DashboardCard(title: "Investi", value: viewModel.manuallyInvested.formatted(.currency(code: "EUR")), titleIcon: "pencil")
                        }.buttonStyle(.plain)
                        
                        DashboardCard(title: "Total (Investi+Cash)", value: viewModel.manuallyInvestedPlusCash.formatted(.currency(code: "EUR")))
                        DashboardCard(title: "Actuel (Actions)", value: viewModel.totalValue.formatted(.currency(code: "EUR")))
                    }
                    
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("P/L Total").font(.subheadline).foregroundColor(.secondary).lineLimit(1)
                            Text(viewModel.totalROIValue.formatted(.currency(code: "EUR").sign(strategy: .always())))
                                .font(.title2).fontWeight(.bold).foregroundColor(getColor(for: viewModel.totalROIValue))
                            Text(viewModel.totalROIPercent.formatted(.percent.precision(.fractionLength(2)).sign(strategy: .always())))
                                .font(.caption).padding(.horizontal, 6).padding(.vertical, 2)
                                .background(getColor(for: viewModel.totalROIValue).opacity(0.1))
                                .foregroundColor(getColor(for: viewModel.totalROIValue)).cornerRadius(4)
                        }
                        .padding().frame(maxWidth: .infinity, alignment: .leading).background(Color(NSColor.controlBackgroundColor)).cornerRadius(10)
                        
                        DashboardCard(title: "Positions", value: "\(viewModel.positionCount)")
                        DashboardCard(title: "Dividendes Totaux", value: viewModel.totalDividends.formatted(.currency(code: "EUR")))
                        DashboardCard(title: "Rendement", value: viewModel.portfolioYield.formatted(.percent.precision(.fractionLength(2))))
                    }
                }
                
                // --- LE TABLEAU DES POSITIONS ---
                Table(viewModel.positions, selection: $selection, sortOrder: $viewModel.sortOrder) {
                    TableColumn("Ticker", value: \.ticker) { position in
                        HStack {
                            Circle().fill(Color.gray.opacity(0.2)).frame(width: 24, height: 24)
                                .overlay(Text(position.ticker.prefix(1)).font(.caption).fontWeight(.bold).foregroundColor(.primary))
                            Text(position.ticker).font(.system(.body, design: .monospaced)).fontWeight(.bold)
                        }
                        .contextMenu { Button(role: .destructive) { viewModel.deletePosition(id: position.id) } label: { Label("Supprimer", systemImage: "trash") } }
                    }
                    
                    TableColumn("Qté", value: \.quantity) { position in
                        Text("\(position.quantity, specifier: "%.2f")")
                    }
                    
                    TableColumn("Prix", value: \.currentPrice) { position in
                        Text(position.currentPrice, format: .currency(code: position.currency))
                    }
                    
                    TableColumn("PRU", value: \.averageCost) { position in
                        Text(position.averageCost, format: .currency(code: position.currency)).foregroundColor(.secondary)
                    }
                    
                    TableColumn("P/L €", value: \.roiValue) { position in
                        Text(position.roiValue, format: .currency(code: "EUR").sign(strategy: .always()))
                            .foregroundColor(getColor(for: position.roiValue)).fontWeight(.medium)
                    }
                    
                    TableColumn("P/L %", value: \.roiPercent) { position in
                        Text(position.roiPercent, format: .percent.precision(.fractionLength(2)).sign(strategy: .always()))
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(getColor(for: position.roiValue).opacity(0.1))
                            .foregroundColor(getColor(for: position.roiValue)).cornerRadius(4)
                    }
                }
                .tableStyle(.inset)
                .frame(minHeight: 300)
            }
            .padding()
        }
        .background(Color(NSColor.windowBackgroundColor))
        .toolbar {
            //ToolbarItem(placement: .navigation) { Text("BlueChip").font(.headline).foregroundColor(.secondary) }
            ToolbarItem(placement: .primaryAction) { Button(action: { showAddSheet = true }) { Label("Ajouter", systemImage: "plus") } }
            ToolbarItem(placement: .automatic) {
                Button(action: { Task { await viewModel.refreshPrices() } }) {
                    if viewModel.isLoading { ProgressView().controlSize(.small) } else { Label("Actualiser", systemImage: "arrow.clockwise") }
                }.disabled(viewModel.isLoading)
            }
        }
        .sheet(isPresented: $showAddSheet) { AddPositionView(viewModel: viewModel) }
        .sheet(isPresented: $showCashSheet) { SimpleNumberEditView(title: "Modifier Cash", value: $viewModel.availableCash) }
        .sheet(isPresented: $showInvestedSheet) { SimpleNumberEditView(title: "Modifier Investi", value: $viewModel.manuallyInvested) }
        
        // INTERCEPTEUR DE FERMETURE D'APP (Cmd + Q)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            print("🔴 Fermeture de l'app détectée (Cmd+Q) : Sauvegarde forcée en cours...")
            viewModel.saveData()
        }
    }
    
    func getColor(for value: Double) -> Color { value >= 0 ? .green : .red }
}
