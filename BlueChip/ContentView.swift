import SwiftUI
import Combine
import Charts

// MARK: - 1. LE MODÈLE (DATA)
struct Position: Identifiable, Codable {
    var id = UUID()
    let ticker: String
    var quantity: Double
    var averageCost: Double
    var currentPrice: Double
    var currency: String = "EUR"
    var usdToEurRate: Double = 1.0
    var annualDividendNet: Double = 0.0
    var purchaseDate: Date = Date()
    
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

enum GoalType: String, Codable, CaseIterable {
    case totalCapital = "Capital Total (€)"
    case totalDividends = "Dividendes Totaux (€)"
    case yield = "Rendement (%)"
}

struct ChartAllocationItem: Identifiable {
    let id = UUID()
    let name: String
    let value: Double
}

struct ChartPerformanceItem: Identifiable {
    let id = UUID()
    let ticker: String
    let category: String
    let value: Double
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
            print("Erreur Yahoo: \(error)")
        }
        return nil
    }
    
    func fetchUSDEURRate() async -> Double {
        if let data = await fetchStockData(for: "EUR=X") { return data.price }
        return 1.0
    }
}

// MARK: - 3. LE VIEW MODEL (LOGIQUE)
@MainActor
class PortfolioViewModel: ObservableObject {
    @Published var positions: [Position] = []
    @Published var availableCash: Double = 0.0 { didSet { saveData() } }
    @Published var isLoading = false
    
    @Published var currentGoalType: GoalType = .totalCapital { didSet { saveData() } }
    @Published var currentGoalTarget: Double = 10000.0 { didSet { saveData() } }
    
    // Gestion du tri
    @Published var sortOrder = [KeyPathComparator(\Position.ticker)] {
        didSet { positions.sort(using: sortOrder) }
    }
    
    private let yahooService = YahooFinanceService()
    
    var totalInvested: Double { positions.reduce(0) { $0 + $1.investedAmountEUR } }
    var totalValue: Double { positions.reduce(0) { $0 + $1.currentValueEUR } }
    var totalROIValue: Double { totalValue - totalInvested }
    var totalROIPercent: Double { totalInvested > 0 ? totalROIValue / totalInvested : 0 }
    var positionCount: Int { positions.count }
    var totalCapital: Double { totalInvested + availableCash }
    var totalDividends: Double { positions.reduce(0) { $0 + $1.totalDividendEUR } }
    var portfolioYield: Double { totalInvested > 0 ? totalDividends / totalInvested : 0 }
    
    var currentGoalValue: Double {
        switch currentGoalType {
        case .totalCapital: return totalCapital
        case .totalDividends: return totalDividends
        case .yield: return portfolioYield * 100
        }
    }
    
    var allocationData: [ChartAllocationItem] {
        var items = positions.map { ChartAllocationItem(name: $0.ticker, value: $0.currentValueEUR) }
        if availableCash > 0 { items.append(ChartAllocationItem(name: "Cash", value: availableCash)) }
        return items
    }
    
    var performanceData: [ChartPerformanceItem] {
        var items: [ChartPerformanceItem] = []
        for pos in positions {
            items.append(ChartPerformanceItem(ticker: pos.ticker, category: "Investi", value: pos.investedAmountEUR))
            items.append(ChartPerformanceItem(ticker: pos.ticker, category: "Actuel", value: pos.currentValueEUR))
        }
        return items
    }
    
    init() {
        loadData()
        Task { await refreshPrices() }
    }
    
    func refreshPrices() async {
        isLoading = true
        let currentUsdToEurRate = await yahooService.fetchUSDEURRate()
        
        var updatedPositions = positions
        for index in updatedPositions.indices {
            let ticker = updatedPositions[index].ticker
            if let data = await yahooService.fetchStockData(for: ticker) {
                updatedPositions[index].currentPrice = data.price
                updatedPositions[index].currency = data.currency
                updatedPositions[index].usdToEurRate = currentUsdToEurRate
            }
        }
        self.positions = updatedPositions.sorted(using: sortOrder)
        saveData()
        isLoading = false
    }
    
    func addPosition(ticker: String, quantity: Double, pru: Double) {
        let newPos = Position(ticker: ticker.uppercased(), quantity: quantity, averageCost: pru, currentPrice: 0, currency: "EUR", usdToEurRate: 1.0, annualDividendNet: 0.0, purchaseDate: Date())
        positions.append(newPos)
        positions.sort(using: sortOrder)
        saveData()
        Task { await refreshPrices() }
    }
    
    func updatePosition(id: UUID, quantity: Double, pru: Double, dividend: Double, date: Date) {
        if let index = positions.firstIndex(where: { $0.id == id }) {
            positions[index].quantity = quantity
            positions[index].averageCost = pru
            positions[index].annualDividendNet = dividend
            positions[index].purchaseDate = date
            positions.sort(using: sortOrder)
            saveData()
        }
    }
    
    func deletePosition(id: UUID) {
        positions.removeAll { $0.id == id }
        saveData()
    }
    
    private func saveData() {
        if let encoded = try? JSONEncoder().encode(positions) { UserDefaults.standard.set(encoded, forKey: "SavedPositions") }
        UserDefaults.standard.set(availableCash, forKey: "SavedCash")
        UserDefaults.standard.set(currentGoalType.rawValue, forKey: "SavedGoalType")
        UserDefaults.standard.set(currentGoalTarget, forKey: "SavedGoalTarget")
    }
    
    private func loadData() {
        self.availableCash = UserDefaults.standard.double(forKey: "SavedCash")
        
        if let savedGoalStr = UserDefaults.standard.string(forKey: "SavedGoalType"),
           let goal = GoalType(rawValue: savedGoalStr) {
            self.currentGoalType = goal
        }
        
        let savedTarget = UserDefaults.standard.double(forKey: "SavedGoalTarget")
        if savedTarget > 0 { self.currentGoalTarget = savedTarget }
        
        if let savedData = UserDefaults.standard.data(forKey: "SavedPositions"),
           let decoded = try? JSONDecoder().decode([Position].self, from: savedData) {
            self.positions = decoded.sorted(using: sortOrder)
        }
    }
}

// MARK: - 4. VUES FORMULAIRES ET COMPOSANTS
struct AddPositionView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: PortfolioViewModel
    @State private var ticker: String = ""
    @State private var quantity: Double = 0
    @State private var pru: Double = 0
    
    var body: some View {
        Form {
            Section(header: Text("Nouvelle Position")) {
                TextField("Ticker (ex: AAPL, MC.PA)", text: $ticker)
                TextField("Quantité", value: $quantity, format: .number)
                TextField("PRU (Dans la devise d'origine)", value: $pru, format: .number)
            }.padding()
            HStack {
                Button("Annuler") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Ajouter") {
                    if !ticker.isEmpty && quantity > 0 {
                        viewModel.addPosition(ticker: ticker, quantity: quantity, pru: pru)
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
    var position: Position
    @State private var quantity: Double
    @State private var pru: Double
    @State private var dividend: Double
    @State private var purchaseDate: Date
    
    init(viewModel: PortfolioViewModel, position: Position) {
        self.viewModel = viewModel
        self.position = position
        _quantity = State(initialValue: position.quantity)
        _pru = State(initialValue: position.averageCost)
        _dividend = State(initialValue: position.annualDividendNet)
        _purchaseDate = State(initialValue: position.purchaseDate)
    }
    
    var body: some View {
        Form {
            Section(header: Text("Modifier \(position.ticker)")) {
                TextField("Quantité", value: $quantity, format: .number)
                TextField("PRU (\(position.currency))", value: $pru, format: .number)
                TextField("Dividende par action", value: $dividend, format: .number)
                DatePicker("Détenu depuis", selection: $purchaseDate, displayedComponents: .date)
            }.padding()
            HStack {
                Button(role: .destructive, action: { viewModel.deletePosition(id: position.id); dismiss() }) { Text("Supprimer") }
                Spacer()
                Button("Annuler") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Sauvegarder") {
                    viewModel.updatePosition(id: position.id, quantity: quantity, pru: pru, dividend: dividend, date: purchaseDate)
                    dismiss()
                }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }.padding()
        }.frame(width: 380).padding()
    }
}

struct EditCashView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: PortfolioViewModel
    @State private var cashInput: Double = 0
    
    var body: some View {
        Form {
            Section(header: Text("Modifier les liquidités")) {
                TextField("Montant en €", value: $cashInput, format: .number)
            }.padding()
            HStack {
                Button("Annuler") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Enregistrer") { viewModel.availableCash = cashInput; dismiss() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }.padding()
        }.frame(width: 300).padding().onAppear { cashInput = viewModel.availableCash }
    }
}

struct EditGoalView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: PortfolioViewModel
    @State private var selectedGoal: GoalType
    @State private var targetInput: Double
    
    init(viewModel: PortfolioViewModel) {
        self.viewModel = viewModel
        _selectedGoal = State(initialValue: viewModel.currentGoalType)
        _targetInput = State(initialValue: viewModel.currentGoalTarget)
    }
    
    var body: some View {
        Form {
            Section(header: Text("Définir un objectif")) {
                Picker("Type d'objectif", selection: $selectedGoal) {
                    ForEach(GoalType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                TextField(selectedGoal == .yield ? "Cible (%)" : "Cible (€)", value: $targetInput, format: .number)
            }.padding()
            HStack {
                Button("Annuler") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Enregistrer") {
                    viewModel.currentGoalType = selectedGoal
                    viewModel.currentGoalTarget = targetInput
                    dismiss()
                }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }.padding()
        }.frame(width: 350).padding()
    }
}

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
        .padding().frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor)).cornerRadius(10)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

struct CustomProgressBar: View {
    let title: String
    let currentValue: Double
    let targetValue: Double
    let isPercentage: Bool
    
    var progress: Double { min(max(currentValue / targetValue, 0), 1) }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Objectif : \(title)").font(.headline)
                Spacer()
                Text(isPercentage ? "\(currentValue, specifier: "%.2f")% / \(targetValue, specifier: "%.2f")%" : "\(currentValue.formatted(.currency(code: "EUR"))) / \(targetValue.formatted(.currency(code: "EUR")))")
                    .font(.subheadline).fontWeight(.bold).foregroundColor(progress >= 1 ? .green : .primary)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.windowBackgroundColor)).frame(height: 14)
                    RoundedRectangle(cornerRadius: 8)
                        .fill(LinearGradient(gradient: Gradient(colors: [.blue, .purple]), startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(0, geometry.size.width * CGFloat(progress)), height: 14)
                        .animation(.spring(), value: progress)
                }
            }.frame(height: 14)
        }
        .padding().background(Color(NSColor.controlBackgroundColor)).cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        .help("Double-cliquez pour modifier votre objectif")
    }
}

// MARK: - 5. VUES DES GRAPHIQUES (INTERACTIFS)
struct DonutChartView: View {
    @ObservedObject var viewModel: PortfolioViewModel
    @State private var hoveredSector: String? = nil
    
    var body: some View {
        Chart(viewModel.allocationData) { item in
            SectorMark(
                angle: .value("Valeur", item.value),
                innerRadius: .ratio(0.55),
                angularInset: 1.5
            )
            .foregroundStyle(by: .value("Actif", item.name))
            .cornerRadius(4)
            .opacity(hoveredSector == nil || hoveredSector == item.name ? 1.0 : 0.3)
        }
        .chartAngleSelection(value: $hoveredSector)
        .animation(.easeInOut(duration: 0.2), value: hoveredSector)
    }
}

struct BarChartView: View {
    @ObservedObject var viewModel: PortfolioViewModel
    @State private var hoveredTicker: String? = nil
    
    var body: some View {
        Chart(viewModel.performanceData) { item in
            BarMark(
                x: .value("Ticker", item.ticker),
                y: .value("Valeur en €", item.value)
            )
            .foregroundStyle(by: .value("Catégorie", item.category))
            .position(by: .value("Catégorie", item.category))
            .opacity(hoveredTicker == nil || hoveredTicker == item.ticker ? 1.0 : 0.4)
        }
        .chartForegroundStyleScale(["Investi": Color.gray.opacity(0.4), "Actuel": Color.blue])
        .chartXSelection(value: $hoveredTicker)
        .animation(.easeInOut(duration: 0.2), value: hoveredTicker)
    }
}

enum ActiveChart: String, Identifiable {
    case allocation, performance
    var id: String { self.rawValue }
}

struct FullScreenChartView: View {
    @Environment(\.dismiss) var dismiss
    let chartType: ActiveChart
    @ObservedObject var viewModel: PortfolioViewModel
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text(chartType == .allocation ? "Répartition du Portefeuille" : "Performance par Position (Investi vs Actuel)").font(.title).fontWeight(.bold)
                Spacer()
                Button(action: { dismiss() }) { Image(systemName: "xmark.circle.fill").font(.title).foregroundColor(.secondary) }.buttonStyle(.plain)
            }
            if chartType == .allocation { DonutChartView(viewModel: viewModel) } else { BarChartView(viewModel: viewModel) }
        }.padding(30).frame(minWidth: 800, minHeight: 600)
    }
}

// MARK: - 6. LA VUE PRINCIPALE (CONTENT VIEW)
struct ContentView: View {
    @StateObject private var viewModel = PortfolioViewModel()
    @State private var selection: Set<Position.ID> = []
    
    @State private var showAddSheet = false
    @State private var showCashSheet = false
    @State private var showGoalSheet = false
    @State private var positionToEdit: Position? = nil
    @State private var fullScreenChart: ActiveChart? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            // --- LE DASHBOARD ---
            VStack(spacing: 16) {
                HStack(spacing: 16) {
                    Button(action: { showCashSheet = true }) { DashboardCard(title: "Cash", value: viewModel.availableCash.formatted(.currency(code: "EUR")), titleIcon: "pencil") }.buttonStyle(.plain).help("Cliquez pour modifier votre solde")
                    DashboardCard(title: "Investi", value: viewModel.totalInvested.formatted(.currency(code: "EUR")))
                    DashboardCard(title: "Total (Investi+Cash)", value: viewModel.totalCapital.formatted(.currency(code: "EUR")))
                    DashboardCard(title: "Actuel (Actions)", value: viewModel.totalValue.formatted(.currency(code: "EUR")))
                }
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("P/L Total").font(.subheadline).foregroundColor(.secondary).lineLimit(1)
                        Text(viewModel.totalROIValue.formatted(.currency(code: "EUR").sign(strategy: .always())))
                            .font(.title2).fontWeight(.bold).foregroundColor(getColor(for: viewModel.totalROIValue)).lineLimit(1).minimumScaleFactor(0.8)
                        Text(viewModel.totalROIPercent.formatted(.percent.precision(.fractionLength(2)).sign(strategy: .always())))
                            .font(.caption).padding(.horizontal, 6).padding(.vertical, 2).background(getColor(for: viewModel.totalROIValue).opacity(0.1)).foregroundColor(getColor(for: viewModel.totalROIValue)).cornerRadius(4)
                    }.padding().frame(maxWidth: .infinity, alignment: .leading).background(Color(NSColor.controlBackgroundColor)).cornerRadius(10).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                    
                    DashboardCard(title: "Positions", value: "\(viewModel.positionCount)")
                    DashboardCard(title: "Dividendes Totaux", value: viewModel.totalDividends.formatted(.currency(code: "EUR")))
                    DashboardCard(title: "Rendement", value: viewModel.portfolioYield.formatted(.percent.precision(.fractionLength(2))))
                }
                
                // Barre d'objectif
                CustomProgressBar(
                    title: viewModel.currentGoalType.rawValue,
                    currentValue: viewModel.currentGoalValue,
                    targetValue: viewModel.currentGoalTarget,
                    isPercentage: viewModel.currentGoalType == .yield
                )
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { showGoalSheet = true }
                
            }
            .padding().background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // --- LE TABLEAU (AVEC TRI INTÉGRÉ) ---
            Table(viewModel.positions, selection: $selection, sortOrder: $viewModel.sortOrder) {
                TableColumn("Ticker", value: \.ticker) { position in
                    Text(position.ticker).font(.system(.body, design: .monospaced)).fontWeight(.bold).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        .contentShape(Rectangle()).onTapGesture(count: 2) { positionToEdit = position }.contextMenu { deleteButton(for: position) }
                }.width(min: 60, ideal: 80)
                
                TableColumn("Qté", value: \.quantity) { position in
                    Text("\(position.quantity, specifier: "%.2f")").frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                        .contentShape(Rectangle()).onTapGesture(count: 2) { positionToEdit = position }.contextMenu { deleteButton(for: position) }
                }.width(50)
                
                TableColumn("Prix", value: \.currentPrice) { position in
                    Text(position.currentPrice, format: .currency(code: position.currency)).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                        .contentShape(Rectangle()).onTapGesture(count: 2) { positionToEdit = position }.contextMenu { deleteButton(for: position) }
                }
                
                TableColumn("PRU", value: \.averageCost) { position in
                    Text(position.averageCost, format: .currency(code: position.currency)).foregroundColor(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                        .contentShape(Rectangle()).onTapGesture(count: 2) { positionToEdit = position }.contextMenu { deleteButton(for: position) }
                }
                
                TableColumn("P/L €", value: \.roiValue) { position in
                    Text(position.roiValue, format: .currency(code: "EUR").sign(strategy: .always())).foregroundColor(getColor(for: position.roiValue)).fontWeight(.medium).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                        .contentShape(Rectangle()).onTapGesture(count: 2) { positionToEdit = position }.contextMenu { deleteButton(for: position) }
                }
                
                TableColumn("P/L %", value: \.roiPercent) { position in
                    Text(position.roiPercent, format: .percent.precision(.fractionLength(2)).sign(strategy: .always())).padding(.horizontal, 8).padding(.vertical, 2)
                        .background(getColor(for: position.roiValue).opacity(0.1)).foregroundColor(getColor(for: position.roiValue)).cornerRadius(4).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                        .contentShape(Rectangle()).onTapGesture(count: 2) { positionToEdit = position }.contextMenu { deleteButton(for: position) }
                }
            }
            .tableStyle(.inset)
            .frame(height: 320)
            
            Divider()
            
            // --- LA ZONE DES GRAPHIQUES ---
            HStack(spacing: 24) {
                VStack(alignment: .leading) {
                    HStack {
                        Text("Répartition").font(.headline).foregroundColor(.secondary)
                        Spacer()
                        Button(action: { fullScreenChart = .allocation }) { Image(systemName: "arrow.up.left.and.arrow.down.right").foregroundColor(.secondary) }.buttonStyle(.plain)
                    }.padding(.bottom, 8)
                    if viewModel.allocationData.isEmpty { Spacer(); Text("Aucune donnée").foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .center); Spacer() } else { DonutChartView(viewModel: viewModel) }
                }.frame(maxWidth: .infinity, maxHeight: .infinity).padding().background(Color(NSColor.controlBackgroundColor)).cornerRadius(12)
                
                VStack(alignment: .leading) {
                    HStack {
                        Text("Performance").font(.headline).foregroundColor(.secondary)
                        Spacer()
                        Button(action: { fullScreenChart = .performance }) { Image(systemName: "arrow.up.left.and.arrow.down.right").foregroundColor(.secondary) }.buttonStyle(.plain)
                    }.padding(.bottom, 8)
                    if viewModel.performanceData.isEmpty { Spacer(); Text("Aucune donnée").foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .center); Spacer() } else { BarChartView(viewModel: viewModel) }
                }.frame(maxWidth: .infinity, maxHeight: .infinity).padding().background(Color(NSColor.controlBackgroundColor)).cornerRadius(12)
            }
            .padding().frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(NSColor.windowBackgroundColor))
        }
        .navigationTitle("")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Text("BlueChip - Stocks Portfolio Manager").font(.subheadline).foregroundColor(.secondary).padding(.trailing, 8)
                Button(action: { showAddSheet = true }) { Label("Ajouter", systemImage: "plus") }
            }
            ToolbarItem(placement: .automatic) {
                Button(action: { Task { await viewModel.refreshPrices() } }) {
                    if viewModel.isLoading { ProgressView().controlSize(.small) } else { Label("Actualiser", systemImage: "arrow.clockwise") }
                }.disabled(viewModel.isLoading)
            }
        }
        .sheet(isPresented: $showAddSheet) { AddPositionView(viewModel: viewModel) }
        .sheet(isPresented: $showCashSheet) { EditCashView(viewModel: viewModel) }
        .sheet(isPresented: $showGoalSheet) { EditGoalView(viewModel: viewModel) }
        .sheet(item: $positionToEdit) { position in EditPositionView(viewModel: viewModel, position: position) }
        .sheet(item: $fullScreenChart) { chartType in FullScreenChartView(chartType: chartType, viewModel: viewModel) }
    }
    
    @ViewBuilder
    private func deleteButton(for position: Position) -> some View {
        Button(role: .destructive) { viewModel.deletePosition(id: position.id) } label: { Label("Supprimer \(position.ticker)", systemImage: "trash") }
    }
    
    func getColor(for value: Double) -> Color { value >= 0 ? .green : .red }
}
