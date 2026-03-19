import SwiftUI
import Combine
import Charts

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
    var country: String
    var dividendMonths: Set<Int>
    var purchaseDate: Date
    
    init(id: UUID = UUID(), ticker: String, quantity: Double, averageCost: Double, currentPrice: Double, currency: String = "EUR", usdToEurRate: Double = 1.0, annualDividendNet: Double = 0.0, country: String = "", dividendMonths: Set<Int> = [], purchaseDate: Date = Date()) {
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
        self.purchaseDate = purchaseDate
    }
    
    enum CodingKeys: String, CodingKey {
        case id, ticker, quantity, averageCost, currentPrice, currency, usdToEurRate, annualDividendNet, country, dividendMonths, purchaseDate
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
        country = try container.decodeIfPresent(String.self, forKey: .country) ?? ""
        dividendMonths = try container.decodeIfPresent(Set<Int>.self, forKey: .dividendMonths) ?? []
        purchaseDate = try container.decodeIfPresent(Date.self, forKey: .purchaseDate) ?? Date()
    }
    
    var investedAmountEUR: Double { quantity * averageCost * (currency == "USD" ? usdToEurRate : 1.0) }
    var currentValueEUR: Double { quantity * currentPrice * (currency == "USD" ? usdToEurRate : 1.0) }
    var totalDividendEUR: Double { quantity * annualDividendNet * (currency == "USD" ? usdToEurRate : 1.0) }
    var roiValue: Double { currentValueEUR - investedAmountEUR }
    var roiPercent: Double { investedAmountEUR > 0 ? roiValue / investedAmountEUR : 0 }
}

struct PortfolioSaveData: Codable {
    var positions: [Position]
    var availableCash: Double
    var manuallyInvested: Double
}

struct ChartDataItem: Identifiable { let id = UUID(); let name: String; let value: Double }
struct PriceCompareItem: Identifiable { let id = UUID(); let ticker: String; let category: String; let value: Double }

// MARK: - 2. LE SERVICE YAHOO (RÉSEAU)
class YahooFinanceService {
    func fetchStockData(for ticker: String) async -> (price: Double, currency: String)? {
        let cleanTicker = ticker.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(cleanTicker)?interval=1d") else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
            if let chart = json?["chart"] as? [String: Any], let result = chart["result"] as? [[String: Any]],
               let meta = result.first?["meta"] as? [String: Any], let price = meta["regularMarketPrice"] as? Double {
                return (price, meta["currency"] as? String ?? "EUR")
            }
        } catch { print("Erreur Yahoo: \(error.localizedDescription)") }
        return nil
    }
    func fetchUSDEURRate() async -> Double { return await fetchStockData(for: "EUR=X")?.price ?? 1.0 }
}

// MARK: - 3. LE VIEW MODEL
@MainActor
class PortfolioViewModel: ObservableObject {
    @Published var positions: [Position] = [] { didSet { saveData() } }
    @Published var availableCash: Double = 0.0 { didSet { saveData() } }
    @Published var manuallyInvested: Double = 0.0 { didSet { saveData() } }
    @Published var isLoading = false
    @Published var sortOrder = [KeyPathComparator(\Position.ticker)] { didSet { positions.sort(using: sortOrder) } }
    
    private let yahooService = YahooFinanceService()
    
    var positionsInvestedSum: Double { positions.reduce(0) { $0 + $1.investedAmountEUR } }
    var totalValue: Double { positions.reduce(0) { $0 + $1.currentValueEUR } }
    var currentTotalCapital: Double { totalValue + availableCash }
    var totalROIValue: Double { totalValue - positionsInvestedSum }
    var totalROIPercent: Double { positionsInvestedSum > 0 ? totalROIValue / positionsInvestedSum : 0 }
    var positionCount: Int { positions.count }
    var totalDividends: Double { positions.reduce(0) { $0 + $1.totalDividendEUR } }
    
    // NOUVEAU CALCUL : Rendement sur le Total (Valeur Actions + Cash)
    var portfolioYield: Double { currentTotalCapital > 0 ? totalDividends / currentTotalCapital : 0 }
    
    var allocationByPosition: [ChartDataItem] {
        var items = positions.map { ChartDataItem(name: $0.ticker, value: $0.currentValueEUR) }
        if availableCash > 0 { items.append(ChartDataItem(name: "Cash", value: availableCash)) }
        return items.sorted { $0.value > $1.value }
    }
    
    var allocationByCountry: [ChartDataItem] {
        var dict: [String: Double] = [:]
        for pos in positions { dict[pos.country.isEmpty ? "Inconnu" : pos.country.uppercased(), default: 0] += pos.currentValueEUR }
        if availableCash > 0 { dict["Cash", default: 0] += availableCash }
        return dict.map { ChartDataItem(name: $0.key, value: $0.value) }.sorted { $0.value > $1.value }
    }
    
    var priceComparisonData: [PriceCompareItem] {
        var items: [PriceCompareItem] = []
        for pos in positions {
            items.append(PriceCompareItem(ticker: pos.ticker, category: "PRU", value: pos.averageCost))
            items.append(PriceCompareItem(ticker: pos.ticker, category: "Actuel", value: pos.currentPrice))
        }
        return items
    }
    
    init() { loadData(); Task { await refreshPrices() } }
    
    func refreshPrices() async {
        isLoading = true; let rate = await yahooService.fetchUSDEURRate(); let tickers = Array(Set(positions.map { $0.ticker }))
        for ticker in tickers {
            if let data = await yahooService.fetchStockData(for: ticker) {
                for i in 0..<positions.count where positions[i].ticker == ticker {
                    positions[i].currentPrice = data.price; positions[i].currency = data.currency; positions[i].usdToEurRate = rate
                }
            }
        }
        positions.sort(using: sortOrder); saveData(); isLoading = false
    }
    
    func addPosition(ticker: String, quantity: Double, pru: Double, dividend: Double, country: String, purchaseDate: Date) {
        positions.append(Position(ticker: ticker.uppercased(), quantity: quantity, averageCost: pru, currentPrice: pru, annualDividendNet: dividend, country: country, purchaseDate: purchaseDate))
        positions.sort(using: sortOrder); Task { await refreshPrices() }
    }
    
    func updatePosition(id: UUID, quantity: Double, pru: Double, dividend: Double, country: String, dividendMonths: Set<Int>, purchaseDate: Date) {
        if let idx = positions.firstIndex(where: { $0.id == id }) {
            positions[idx].quantity = quantity; positions[idx].averageCost = pru; positions[idx].annualDividendNet = dividend
            positions[idx].country = country; positions[idx].dividendMonths = dividendMonths; positions[idx].purchaseDate = purchaseDate
            positions.sort(using: sortOrder)
        }
    }
    
    func deletePosition(id: UUID) { positions.removeAll { $0.id == id } }
    
    private var saveFileURL: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("BlueChip_Data.json") }
    func saveData() { do { try JSONEncoder().encode(PortfolioSaveData(positions: positions, availableCash: availableCash, manuallyInvested: manuallyInvested)).write(to: saveFileURL, options: [.atomic]) } catch {} }
    func loadData() { do { let d = try JSONDecoder().decode(PortfolioSaveData.self, from: try Data(contentsOf: saveFileURL)); positions = d.positions.sorted(using: sortOrder); availableCash = d.availableCash; manuallyInvested = d.manuallyInvested } catch {} }
}

// MARK: - 4. NAVIGATION & ONGLETS
enum AppTab: String, CaseIterable {
    case composition = "Composition", fondamentaux = "Fondamentaux", croissance = "Croissance", dividendes = "Dividendes"
    case valorisation = "Valorisation", projection = "Projection", simulation = "Simulation", watchlist = "Watchlist"
    case exposition = "Exposition", transactions = "Transactions", benchmark = "Benchmark"
}

struct CustomTabBar: View {
    @Binding var selectedTab: AppTab
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 24) {
                ForEach(AppTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).font(.system(size: 14, weight: selectedTab == tab ? .bold : .medium)).foregroundColor(selectedTab == tab ? .primary : .secondary)
                        .padding(.vertical, 8).overlay(Rectangle().frame(height: 3).foregroundColor(selectedTab == tab ? .blue : .clear).offset(y: 4), alignment: .bottom)
                        .contentShape(Rectangle()).onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { selectedTab = tab } }
                }
            }.padding(.horizontal, 20)
        }.padding(.vertical, 6).background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - 5. COMPOSANTS UI & GRAPHIQUES AVANCÉS
enum ChartZoomType: Identifiable { case positions, countries, priceCompare, roiCombo; var id: Int { self.hashValue } }

struct InteractiveLegendView: View {
    let items: [String]
    let colorMap: (String) -> Color
    @Binding var hiddenItems: Set<String>
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(items, id: \.self) { item in
                    Button(action: { withAnimation { if hiddenItems.contains(item) { hiddenItems.remove(item) } else { hiddenItems.insert(item) } } }) {
                        HStack(spacing: 6) {
                            Circle().fill(colorMap(item)).frame(width: 10, height: 10)
                            Text(item).font(.caption).foregroundColor(hiddenItems.contains(item) ? .secondary : .primary)
                        }
                    }
                    .buttonStyle(.plain)
                    .opacity(hiddenItems.contains(item) ? 0.4 : 1.0)
                }
            }.padding(.horizontal, 4)
        }
    }
}

let chartColors: [Color] = [.blue, .green, .orange, .purple, .red, .teal, .yellow, .pink, .indigo, .mint, .cyan, .brown]

struct ModernDonutChart: View {
    let data: [ChartDataItem]; let title: String; let zoomType: ChartZoomType; var isExpanded: Bool = false
    @Binding var expandedChart: ChartZoomType?
    @State private var selectedAngleValue: Double? = nil; @State private var hiddenItems: Set<String> = []
    
    func color(for name: String) -> Color { if let idx = data.firstIndex(where: { $0.name == name }) { return chartColors[idx % chartColors.count] }; return .gray }
    var filteredData: [ChartDataItem] { data.filter { !hiddenItems.contains($0.name) } }
    
    var body: some View {
        VStack {
            HStack {
                Text(title).font(.headline).foregroundColor(.secondary); Spacer()
                if !isExpanded { Button(action: { expandedChart = zoomType }) { Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary) }.buttonStyle(.plain) }
            }.padding(.bottom, 4)
            InteractiveLegendView(items: data.map { $0.name }, colorMap: color, hiddenItems: $hiddenItems).padding(.bottom, 8)
            if filteredData.isEmpty { Spacer(); Text("Aucune donnée").foregroundColor(.secondary); Spacer() } else {
                Chart(filteredData) { item in
                    SectorMark(angle: .value("Valeur", item.value), innerRadius: .ratio(0.65), angularInset: 1.5).foregroundStyle(color(for: item.name)).cornerRadius(4)
                }.chartLegend(.hidden).chartAngleSelection(value: $selectedAngleValue).chartBackground { proxy in
                    GeometryReader { geometry in
                        if let value = selectedAngleValue {
                            let item = findItem(for: value)
                            VStack { Text(item.name).font(.headline); Text(item.value.formatted(.currency(code: "EUR"))).font(.subheadline).foregroundColor(.secondary) }.position(x: geometry.frame(in: .local).midX, y: geometry.frame(in: .local).midY)
                        }
                    }
                }.animation(.easeInOut(duration: 0.2), value: selectedAngleValue)
            }
        }.padding().frame(minHeight: 360, maxHeight: isExpanded ? .infinity : 360).background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    func findItem(for value: Double) -> ChartDataItem { var cum = 0.0; for item in filteredData { cum += item.value; if value <= cum { return item } }; return filteredData.last! }
}

struct PRUPriceChart: View {
    let data: [PriceCompareItem]; var isExpanded: Bool = false; @Binding var expandedChart: ChartZoomType?
    @State private var hiddenCategories: Set<String> = []; @State private var hiddenTickers: Set<String> = []; @State private var hoveredTicker: String? = nil
    
    let categories = ["PRU", "Actuel"]
    var uniqueTickers: [String] { Array(Set(data.map { $0.ticker })).sorted() }
    var filteredData: [PriceCompareItem] { data.filter { !hiddenCategories.contains($0.category) && !hiddenTickers.contains($0.ticker) } }
    
    var body: some View {
        VStack {
            HStack {
                Text("PRU vs Prix Actuel").font(.headline).foregroundColor(.secondary); Spacer()
                if !isExpanded { Button(action: { expandedChart = .priceCompare }) { Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary) }.buttonStyle(.plain) }
            }.padding(.bottom, 4)
            VStack(spacing: 4) {
                InteractiveLegendView(items: categories, colorMap: { $0 == "PRU" ? .gray.opacity(0.6) : .blue }, hiddenItems: $hiddenCategories)
                InteractiveLegendView(items: uniqueTickers, colorMap: { _ in .primary.opacity(0.3) }, hiddenItems: $hiddenTickers)
            }.padding(.bottom, 8)
            if filteredData.isEmpty { Spacer(); Text("Aucune donnée").foregroundColor(.secondary); Spacer() } else {
                Chart(filteredData) { item in
                    BarMark(x: .value("Ticker", item.ticker), y: .value("Prix", item.value)).foregroundStyle(item.category == "PRU" ? Color.gray.opacity(0.6) : Color.blue).position(by: .value("Catégorie", item.category)).cornerRadius(4)
                        .annotation(position: .top) { if hoveredTicker == item.ticker { Text(item.value.formatted(.currency(code: "EUR"))).font(.system(size: 9, weight: .bold)).foregroundColor(.secondary) } }
                }.chartLegend(.hidden).chartXSelection(value: $hoveredTicker)
            }
        }.padding().frame(minHeight: 360, maxHeight: isExpanded ? .infinity : 360).background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

struct ROIComboChart: View {
    let positions: [Position]; var isExpanded: Bool = false; @Binding var expandedChart: ChartZoomType?
    @State private var hiddenMetrics: Set<String> = []; @State private var hiddenTickers: Set<String> = []; @State private var hoveredTicker: String? = nil
    
    let metrics = ["P/L (€)", "P/L (%)"]
    var uniqueTickers: [String] { positions.map { $0.ticker }.sorted() }
    var filteredPositions: [Position] { positions.filter { !hiddenTickers.contains($0.ticker) } }
    
    var body: some View {
        VStack {
            HStack {
                Text("Retour sur Investissement (P/L)").font(.headline).foregroundColor(.secondary); Spacer()
                if !isExpanded { Button(action: { expandedChart = .roiCombo }) { Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary) }.buttonStyle(.plain) }
            }.padding(.bottom, 4)
            VStack(spacing: 4) {
                InteractiveLegendView(items: metrics, colorMap: { $0 == "P/L (€)" ? .green : .purple }, hiddenItems: $hiddenMetrics)
                InteractiveLegendView(items: uniqueTickers, colorMap: { _ in .primary.opacity(0.3) }, hiddenItems: $hiddenTickers)
            }.padding(.bottom, 8)
            if filteredPositions.isEmpty { Spacer(); Text("Aucune donnée").foregroundColor(.secondary); Spacer() } else {
                Chart {
                    ForEach(filteredPositions) { pos in
                        if !hiddenMetrics.contains("P/L (€)") {
                            BarMark(x: .value("Ticker", pos.ticker), y: .value("P/L (€)", pos.roiValue)).foregroundStyle(pos.roiValue >= 0 ? Color.green.opacity(0.6) : Color.red.opacity(0.6)).cornerRadius(4)
                                .annotation(position: pos.roiValue >= 0 ? .top : .bottom) { if hoveredTicker == pos.ticker { Text(pos.roiValue.formatted(.currency(code: "EUR"))).font(.system(size: 9, weight: .bold)).padding(2).background(Color(NSColor.windowBackgroundColor).opacity(0.8)).cornerRadius(2) } }
                        }
                        if !hiddenMetrics.contains("P/L (%)") {
                            LineMark(x: .value("Ticker", pos.ticker), y: .value("P/L (%)", pos.roiValue)).foregroundStyle(Color.primary).interpolationMethod(.monotone)
                            PointMark(x: .value("Ticker", pos.ticker), y: .value("P/L (%)", pos.roiValue)).foregroundStyle(Color.primary)
                                .annotation(position: pos.roiValue >= 0 ? .top : .bottom) { if hoveredTicker == pos.ticker { Text(pos.roiPercent.formatted(.percent.precision(.fractionLength(1)))).font(.system(size: 9, weight: .bold)).padding(2).background(Color(NSColor.windowBackgroundColor).opacity(0.8)).cornerRadius(2).offset(y: pos.roiValue >= 0 ? -15 : 15) } }
                        }
                    }
                }.chartLegend(.hidden).chartXSelection(value: $hoveredTicker)
            }
        }.padding().frame(minHeight: 360, maxHeight: isExpanded ? .infinity : 360).background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

struct FullScreenChartView: View {
    @Environment(\.dismiss) var dismiss; let zoomType: ChartZoomType; @ObservedObject var viewModel: PortfolioViewModel
    var body: some View {
        VStack(spacing: 20) {
            HStack { Text(titleForZoom).font(.title).fontWeight(.bold); Spacer(); Button(action: { dismiss() }) { Image(systemName: "xmark.circle.fill").font(.title).foregroundColor(.secondary) }.buttonStyle(.plain) }
            switch zoomType {
            case .positions: ModernDonutChart(data: viewModel.allocationByPosition, title: "", zoomType: zoomType, isExpanded: true, expandedChart: .constant(nil))
            case .countries: ModernDonutChart(data: viewModel.allocationByCountry, title: "", zoomType: zoomType, isExpanded: true, expandedChart: .constant(nil))
            case .priceCompare: PRUPriceChart(data: viewModel.priceComparisonData, isExpanded: true, expandedChart: .constant(nil))
            case .roiCombo: ROIComboChart(positions: viewModel.positions, isExpanded: true, expandedChart: .constant(nil))
            }
        }.padding(30).frame(minWidth: 900, minHeight: 700)
    }
    var titleForZoom: String { switch zoomType { case .positions: return "Allocation par Position"; case .countries: return "Allocation par Pays"; case .priceCompare: return "Comparaison PRU vs Prix Actuel"; case .roiCombo: return "Retour sur Investissement Détaillé" } }
}

struct DashboardCard: View {
    let title: String; let value: String; var titleIcon: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Text(title).font(.subheadline).foregroundColor(.secondary).lineLimit(1).minimumScaleFactor(0.8); if let icon = titleIcon { Image(systemName: icon).foregroundColor(.secondary).font(.caption) } }
            Text(value).font(.title2).fontWeight(.bold).lineLimit(1).minimumScaleFactor(0.8)
        }.padding().frame(maxWidth: .infinity, alignment: .leading).background(Color(NSColor.controlBackgroundColor)).cornerRadius(10).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// MARK: - 6. FORMULAIRES
struct AddPositionView: View {
    @Environment(\.dismiss) var dismiss; @ObservedObject var viewModel: PortfolioViewModel
    @State private var ticker = ""; @State private var quantity: Double = 0; @State private var pru: Double = 0
    @State private var dividend: Double = 0; @State private var country = ""; @State private var purchaseDate = Date()
    var body: some View {
        Form {
            Section(header: Text("Nouvelle Position").font(.headline)) {
                TextField("Ticker (ex: AAPL)", text: $ticker); TextField("Quantité", value: $quantity, format: .number)
                TextField("PRU", value: $pru, format: .number); TextField("Dividende net/action", value: $dividend, format: .number)
                TextField("Pays (ex: US, FR)", text: $country); DatePicker("Date d'achat", selection: $purchaseDate, displayedComponents: .date)
            }.padding()
            HStack { Button("Annuler") { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button("Ajouter") { if !ticker.isEmpty && quantity > 0 { viewModel.addPosition(ticker: ticker, quantity: quantity, pru: pru, dividend: dividend, country: country, purchaseDate: purchaseDate); dismiss() } }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent) }.padding()
        }.frame(width: 380).padding()
    }
}

struct EditPositionView: View {
    @Environment(\.dismiss) var dismiss; @ObservedObject var viewModel: PortfolioViewModel; let position: Position
    @State private var quantity: Double; @State private var pru: Double; @State private var dividend: Double
    @State private var country: String; @State private var purchaseDate: Date; @State private var dividendMonths: Set<Int>
    let monthsNames = ["Jan", "Fév", "Mar", "Avr", "Mai", "Jun", "Jul", "Aoû", "Sep", "Oct", "Nov", "Déc"]
    init(viewModel: PortfolioViewModel, position: Position) { self.viewModel = viewModel; self.position = position; _quantity = State(initialValue: position.quantity); _pru = State(initialValue: position.averageCost); _dividend = State(initialValue: position.annualDividendNet); _country = State(initialValue: position.country); _purchaseDate = State(initialValue: position.purchaseDate); _dividendMonths = State(initialValue: position.dividendMonths) }
    var body: some View {
        Form {
            Section(header: Text("Modifier \(position.ticker)").font(.headline)) {
                TextField("Quantité", value: $quantity, format: .number); TextField("PRU", value: $pru, format: .number)
                TextField("Dividende net/action", value: $dividend, format: .number); TextField("Pays", text: $country); DatePicker("Date d'achat", selection: $purchaseDate, displayedComponents: .date)
            }.padding(.bottom, 8)
            Section(header: Text("Mois de versement").font(.subheadline).foregroundColor(.secondary)) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 8) { ForEach(0..<12, id: \.self) { index in let m = index + 1; Toggle(monthsNames[index], isOn: Binding(get: { dividendMonths.contains(m) }, set: { isSet in if isSet { dividendMonths.insert(m) } else { dividendMonths.remove(m) } })).toggleStyle(.button).font(.caption) } }
            }.padding(.bottom, 16)
            HStack { Button(role: .destructive) { viewModel.deletePosition(id: position.id); dismiss() } label: { Text("Supprimer") }; Spacer(); Button("Annuler") { dismiss() }.keyboardShortcut(.cancelAction); Button("Sauvegarder") { viewModel.updatePosition(id: position.id, quantity: quantity, pru: pru, dividend: dividend, country: country, dividendMonths: dividendMonths, purchaseDate: purchaseDate); dismiss() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent) }
        }.frame(width: 450).padding()
    }
}

struct SimpleNumberEditView: View {
    @Environment(\.dismiss) var dismiss; let title: String; @Binding var value: Double; @State private var input: Double = 0
    var body: some View {
        Form { Section(header: Text(title).font(.headline)) { TextField("Montant (€)", value: $input, format: .number) }.padding(); HStack { Button("Annuler") { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button("Enregistrer") { value = input; dismiss() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent) }.padding() }.frame(width: 300).padding().onAppear { input = value }
    }
}

// MARK: - 7. VUES DES ONGLETS (PAGES)
struct CompositionTabView: View {
    @ObservedObject var viewModel: PortfolioViewModel
    @State private var selection: Set<Position.ID> = []
    @State private var showCashSheet = false; @State private var showInvestedSheet = false
    @State private var positionToEdit: Position? = nil; @State private var chartToZoom: ChartZoomType? = nil
    
    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 24) {
                // --- DASHBOARD ---
                VStack(spacing: 16) {
                    HStack(spacing: 16) {
                        Button(action: { showCashSheet = true }) { DashboardCard(title: "Cash", value: viewModel.availableCash.formatted(.currency(code: "EUR")), titleIcon: "pencil") }.buttonStyle(.plain)
                        Button(action: { showInvestedSheet = true }) { DashboardCard(title: "Apport Initial", value: viewModel.manuallyInvested.formatted(.currency(code: "EUR")), titleIcon: "pencil") }.buttonStyle(.plain)
                        DashboardCard(title: "Total (Actuel + Cash)", value: viewModel.currentTotalCapital.formatted(.currency(code: "EUR")))
                        DashboardCard(title: "Valeur Actions", value: viewModel.totalValue.formatted(.currency(code: "EUR")))
                    }
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("P/L Latent").font(.subheadline).foregroundColor(.secondary).lineLimit(1)
                            Text(viewModel.totalROIValue.formatted(.currency(code: "EUR").sign(strategy: .always()))).font(.title2).fontWeight(.bold).foregroundColor(getColor(for: viewModel.totalROIValue))
                            Text(viewModel.totalROIPercent.formatted(.percent.precision(.fractionLength(2)).sign(strategy: .always()))).font(.caption).padding(.horizontal, 6).padding(.vertical, 2).background(getColor(for: viewModel.totalROIValue).opacity(0.1)).foregroundColor(getColor(for: viewModel.totalROIValue)).cornerRadius(4)
                        }.padding().frame(maxWidth: .infinity, alignment: .leading).background(Color(NSColor.controlBackgroundColor)).cornerRadius(10)
                        DashboardCard(title: "Positions", value: "\(viewModel.positionCount)")
                        DashboardCard(title: "Dividendes Annuels", value: viewModel.totalDividends.formatted(.currency(code: "EUR")))
                        DashboardCard(title: "Rendement Total", value: viewModel.portfolioYield.formatted(.percent.precision(.fractionLength(2))))
                    }
                }
                
                // --- TABLEAU ---
                Table(viewModel.positions, selection: $selection, sortOrder: $viewModel.sortOrder) {
                    TableColumn("Ticker", value: \.ticker) { position in
                        HStack { Circle().fill(Color.gray.opacity(0.2)).frame(width: 24, height: 24).overlay(Text(position.ticker.prefix(1)).font(.caption).fontWeight(.bold).foregroundColor(.primary)); Text(position.ticker).font(.system(.body, design: .monospaced)).fontWeight(.bold) }
                        .contentShape(Rectangle()).onTapGesture(count: 2) { positionToEdit = position }.contextMenu { Button(role: .destructive) { viewModel.deletePosition(id: position.id) } label: { Label("Supprimer", systemImage: "trash") } }
                    }
                    TableColumn("Qté", value: \.quantity) { pos in Text("\(pos.quantity, specifier: "%.2f")").frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()).onTapGesture(count: 2) { positionToEdit = pos } }
                    TableColumn("Prix", value: \.currentPrice) { pos in Text(pos.currentPrice, format: .currency(code: pos.currency)).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()).onTapGesture(count: 2) { positionToEdit = pos } }
                    TableColumn("PRU", value: \.averageCost) { pos in Text(pos.averageCost, format: .currency(code: pos.currency)).foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()).onTapGesture(count: 2) { positionToEdit = pos } }
                    TableColumn("P/L €", value: \.roiValue) { pos in Text(pos.roiValue, format: .currency(code: "EUR").sign(strategy: .always())).foregroundColor(getColor(for: pos.roiValue)).fontWeight(.medium).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()).onTapGesture(count: 2) { positionToEdit = pos } }
                    TableColumn("P/L %", value: \.roiPercent) { pos in Text(pos.roiPercent, format: .percent.precision(.fractionLength(2)).sign(strategy: .always())).padding(.horizontal, 8).padding(.vertical, 2).background(getColor(for: pos.roiValue).opacity(0.1)).foregroundColor(getColor(for: pos.roiValue)).cornerRadius(4).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()).onTapGesture(count: 2) { positionToEdit = pos } }
                }.tableStyle(.inset).frame(minHeight: 300)
                
                // --- GRAPHIQUES ---
                VStack(spacing: 24) {
                    HStack(spacing: 24) { ModernDonutChart(data: viewModel.allocationByPosition, title: "Poids par Position", zoomType: .positions, expandedChart: $chartToZoom); ModernDonutChart(data: viewModel.allocationByCountry, title: "Exposition Géographique", zoomType: .countries, expandedChart: $chartToZoom) }
                    HStack(spacing: 24) { PRUPriceChart(data: viewModel.priceComparisonData, expandedChart: $chartToZoom); ROIComboChart(positions: viewModel.positions, expandedChart: $chartToZoom) }
                }
            }.padding()
        }
        .sheet(isPresented: $showCashSheet) { SimpleNumberEditView(title: "Modifier Cash", value: $viewModel.availableCash) }
        .sheet(isPresented: $showInvestedSheet) { SimpleNumberEditView(title: "Modifier Apport", value: $viewModel.manuallyInvested) }
        .sheet(item: $positionToEdit) { position in EditPositionView(viewModel: viewModel, position: position) }
        .sheet(item: $chartToZoom) { type in FullScreenChartView(zoomType: type, viewModel: viewModel) }
    }
    func getColor(for value: Double) -> Color { value >= 0 ? .green : .red }
}

// MARK: - 8. VUE PRINCIPALE (CONTAINER)
struct ContentView: View {
    @StateObject private var viewModel = PortfolioViewModel()
    @State private var selectedTab: AppTab = .composition
    @State private var showAddSheet = false

    var body: some View {
        VStack(spacing: 0) {
            
            // Le Header bien PRO
            HStack {
                Text("BlueChip - Stocks Portfolio Manager")
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 10)
            
            // Barre d'onglets
            HStack { CustomTabBar(selectedTab: $selectedTab); Spacer() }
            Divider()
            
            // Routage
            Group {
                switch selectedTab {
                case .composition: CompositionTabView(viewModel: viewModel)
                default: VStack(spacing: 20) { Image(systemName: "hammer.fill").font(.system(size: 50)).foregroundColor(.secondary); Text("La vue \(selectedTab.rawValue) est en construction.").font(.title).foregroundColor(.secondary) }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .navigationTitle("") // SÉCURITÉ : Cache le petit titre de la Toolbar si présent
        .toolbar {
            ToolbarItem(placement: .primaryAction) { Button(action: { showAddSheet = true }) { Label("Ajouter", systemImage: "plus") } }
            ToolbarItem(placement: .automatic) { Button(action: { Task { await viewModel.refreshPrices() } }) { if viewModel.isLoading { ProgressView().controlSize(.small) } else { Label("Actualiser", systemImage: "arrow.clockwise") } }.disabled(viewModel.isLoading) }
        }
        .sheet(isPresented: $showAddSheet) { AddPositionView(viewModel: viewModel) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in viewModel.saveData() }
    }
}
