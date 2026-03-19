import SwiftUI
import Combine

// MARK: - 1. LE MODÈLE (DATA)
struct Position: Identifiable, Codable {
    var id: UUID
    let ticker: String
    var quantity: Double
    var averageCost: Double // PRU
    var currentPrice: Double
    var currency: String
    var usdToEurRate: Double
    var annualDividendNet: Double
    
    // Nouveaux champs
    var country: String
    var dividendMonths: Set<Int>
    
    // Initialiseur standard
    init(id: UUID = UUID(), ticker: String, quantity: Double, averageCost: Double, currentPrice: Double, currency: String = "EUR", usdToEurRate: Double = 1.0, annualDividendNet: Double = 0.0, country: String = "", dividendMonths: Set<Int> = []) {
        self.id = id
        self.ticker = ticker
        self.quantity = quantity
        self.averageCost = averageCost
        self.currentPrice = currentPrice
        self.currency = currency
        self.usdToEurRate = usdToEurRate
        self.annualDividendNet = annualDividendNet
        self.country = country
        self.dividendMonths = dividendMonths
    }
    
    // Décodeur sécurisé : Permet de charger un vieux JSON qui n'aurait pas les champs "country" ou "dividendMonths"
    enum CodingKeys: String, CodingKey {
        case id, ticker, quantity, averageCost, currentPrice, currency, usdToEurRate, annualDividendNet, country, dividendMonths
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        ticker = try container.decode(String.self, forKey: .ticker)
        quantity = try container.decode(Double.self, forKey: .quantity)
        averageCost = try container.decode(Double.self, forKey: .averageCost)
        currentPrice = try container.decode(Double.self, forKey: .currentPrice)
        currency = try container.decodeIfPresent(String.self, forKey: .currency) ?? "EUR"
        usdToEurRate = try container.decodeIfPresent(Double.self, forKey: .usdToEurRate) ?? 1.0
        annualDividendNet = try container.decodeIfPresent(Double.self, forKey: .annualDividendNet) ?? 0.0
        
        // Valeurs par défaut si le JSON est ancien
        country = try container.decodeIfPresent(String.self, forKey: .country) ?? ""
        dividendMonths = try container.decodeIfPresent(Set<Int>.self, forKey: .dividendMonths) ?? []
    }
    
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
    
    func addPosition(ticker: String, quantity: Double, pru: Double, dividend: Double, country: String) {
        let newPos = Position(ticker: ticker.uppercased(), quantity: quantity, averageCost: pru, currentPrice: pru, annualDividendNet: dividend, country: country)
        positions.append(newPos)
        positions.sort(using: sortOrder)
        Task { await refreshPrices() }
    }
    
    func updatePosition(id: UUID, quantity: Double, pru: Double, dividend: Double, country: String, dividendMonths: Set<Int>) {
        if let index = positions.firstIndex(where: { $0.id == id }) {
            positions[index].quantity = quantity
            positions[index].averageCost = pru
            positions[index].annualDividendNet = dividend
            positions[index].country = country
            positions[index].dividendMonths = dividendMonths
            positions.sort(using: sortOrder)
            // saveData() est automatiquement appelé grâce au didSet
        }
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
        let dataToSave = PortfolioSaveData(positions: positions, availableCash: availableCash, manuallyInvested: manuallyInvested)
        do {
            let encoded = try JSONEncoder().encode(dataToSave)
            try encoded.write(to: saveFileURL, options: [.atomic])
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
        } catch {
            print("ℹ️ Fichier JSON introuvable ou erreur de lecture (Normal au premier lancement).")
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
    @State private var country: String = ""
    
    var body: some View {
        Form {
            Section(header: Text("Nouvelle Position").font(.headline)) {
                TextField("Ticker (ex: AAPL, MC.PA)", text: $ticker)
                TextField("Quantité", value: $quantity, format: .number)
                TextField("PRU (Devise d'origine)", value: $pru, format: .number)
                TextField("Dividende net par action", value: $dividend, format: .number)
                TextField("Pays de cotation (ex: US, FR)", text: $country)
            }.padding()
            HStack {
                Button("Annuler") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Ajouter") {
                    if !ticker.isEmpty && quantity > 0 {
                        viewModel.addPosition(ticker: ticker, quantity: quantity, pru: pru, dividend: dividend, country: country)
                        dismiss()
                    }
                }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }.padding()
        }.frame(width: 350).padding()
    }
}

struct EditPositionView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: PortfolioViewModel
    let position: Position
    
    @State private var quantity: Double
    @State private var pru: Double
    @State private var dividend: Double
    @State private var country: String
    @State private var dividendMonths: Set<Int>
    
    let monthsNames = ["Jan", "Fév", "Mar", "Avr", "Mai", "Jun", "Jul", "Aoû", "Sep", "Oct", "Nov", "Déc"]
    
    init(viewModel: PortfolioViewModel, position: Position) {
        self.viewModel = viewModel
        self.position = position
        _quantity = State(initialValue: position.quantity)
        _pru = State(initialValue: position.averageCost)
        _dividend = State(initialValue: position.annualDividendNet)
        _country = State(initialValue: position.country)
        _dividendMonths = State(initialValue: position.dividendMonths)
    }
    
    var body: some View {
        Form {
            Section(header: Text("Modifier \(position.ticker)").font(.headline)) {
                TextField("Quantité", value: $quantity, format: .number)
                TextField("PRU (\(position.currency))", value: $pru, format: .number)
                TextField("Dividende net par action", value: $dividend, format: .number)
                TextField("Pays (ex: US, FR)", text: $country)
            }.padding(.bottom, 8)
            
            Section(header: Text("Mois de versement des dividendes").font(.subheadline).foregroundColor(.secondary)) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 8) {
                    ForEach(0..<12, id: \.self) { index in
                        let monthNumber = index + 1
                        Toggle(monthsNames[index], isOn: Binding(
                            get: { dividendMonths.contains(monthNumber) },
                            set: { isSet in if isSet { dividendMonths.insert(monthNumber) } else { dividendMonths.remove(monthNumber) } }
                        ))
                        .toggleStyle(.button)
                        .font(.caption)
                    }
                }
            }.padding(.bottom, 16)
            
            HStack {
                Button(role: .destructive) {
                    viewModel.deletePosition(id: position.id)
                    dismiss()
                } label: {
                    Text("Supprimer la position")
                }
                
                Spacer()
                Button("Annuler") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Sauvegarder") {
                    viewModel.updatePosition(id: position.id, quantity: quantity, pru: pru, dividend: dividend, country: country, dividendMonths: dividendMonths)
                    dismiss()
                }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }.frame(width: 450).padding()
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
    @State private var positionToEdit: Position? = nil // Gère l'affichage de la fenêtre d'édition

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
                        
                        DashboardCard(title: "Total Portefeuille", value: viewModel.manuallyInvestedPlusCash.formatted(.currency(code: "EUR")))
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
                        .contentShape(Rectangle()) // Rend toute la cellule cliquable
                        .onTapGesture(count: 2) { positionToEdit = position }
                        .contextMenu { Button(role: .destructive) { viewModel.deletePosition(id: position.id) } label: { Label("Supprimer", systemImage: "trash") } }
                    }
                    
                    TableColumn("Qté", value: \.quantity) { position in
                        Text("\(position.quantity, specifier: "%.2f")")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) { positionToEdit = position }
                    }
                    
                    TableColumn("Prix", value: \.currentPrice) { position in
                        Text(position.currentPrice, format: .currency(code: position.currency))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) { positionToEdit = position }
                    }
                    
                    TableColumn("PRU", value: \.averageCost) { position in
                        Text(position.averageCost, format: .currency(code: position.currency)).foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) { positionToEdit = position }
                    }
                    
                    TableColumn("P/L €", value: \.roiValue) { position in
                        Text(position.roiValue, format: .currency(code: "EUR").sign(strategy: .always()))
                            .foregroundColor(getColor(for: position.roiValue)).fontWeight(.medium)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) { positionToEdit = position }
                    }
                    
                    TableColumn("P/L %", value: \.roiPercent) { position in
                        Text(position.roiPercent, format: .percent.precision(.fractionLength(2)).sign(strategy: .always()))
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(getColor(for: position.roiValue).opacity(0.1))
                            .foregroundColor(getColor(for: position.roiValue)).cornerRadius(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) { positionToEdit = position }
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
        
        // Nouvelle sheet d'édition déclenchée par le double-clic
        .sheet(item: $positionToEdit) { position in
            EditPositionView(viewModel: viewModel, position: position)
        }
        
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            viewModel.saveData()
        }
    }
    
    func getColor(for value: Double) -> Color { value >= 0 ? .green : .red }
}
