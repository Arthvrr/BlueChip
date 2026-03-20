import SwiftUI
import Combine
import Charts

// MARK: - 1. MODEL (DATA)
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
    var sector: String
    var marketCap: String
    var dividendMonths: Set<Int>
    var purchaseDate: Date
    
    init(id: UUID = UUID(), ticker: String, quantity: Double, averageCost: Double, currentPrice: Double, currency: String = "EUR", usdToEurRate: Double = 1.0, annualDividendNet: Double = 0.0, country: String = "", sector: String = "", marketCap: String = "", dividendMonths: Set<Int> = [], purchaseDate: Date = Date()) {
        self.id = id
        self.ticker = ticker
        self.quantity = quantity
        self.averageCost = averageCost
        self.currentPrice = currentPrice
        self.currency = currency
        self.usdToEurRate = usdToEurRate
        self.annualDividendNet = annualDividendNet
        self.country = country
        self.sector = sector
        self.marketCap = marketCap
        self.dividendMonths = dividendMonths
        self.purchaseDate = purchaseDate
    }
    
    enum CodingKeys: String, CodingKey {
        case id, ticker, quantity, averageCost, currentPrice, currency, usdToEurRate, annualDividendNet, country, sector, marketCap, dividendMonths, purchaseDate
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
        sector = try container.decodeIfPresent(String.self, forKey: .sector) ?? ""
        marketCap = try container.decodeIfPresent(String.self, forKey: .marketCap) ?? ""
        dividendMonths = try container.decodeIfPresent(Set<Int>.self, forKey: .dividendMonths) ?? []
        purchaseDate = try container.decodeIfPresent(Date.self, forKey: .purchaseDate) ?? Date()
    }
    
    var investedAmountEUR: Double { quantity * averageCost * (currency == "USD" ? usdToEurRate : 1.0) }
    var currentValueEUR: Double { quantity * currentPrice * (currency == "USD" ? usdToEurRate : 1.0) }
    var totalDividendEUR: Double { quantity * annualDividendNet * (currency == "USD" ? usdToEurRate : 1.0) }
    var roiValue: Double { currentValueEUR - investedAmountEUR }
    var roiPercent: Double { investedAmountEUR > 0 ? roiValue / investedAmountEUR : 0 }
    
    var daysHeld: Int { max(1, Calendar.current.dateComponents([.day], from: purchaseDate, to: Date()).day ?? 1) }
    var dailyROIValue: Double { roiValue / Double(daysHeld) }
}

enum GoalType: String, Codable, CaseIterable {
    case totalValue = "Total Value (€)"
    case dividends = "Annual Dividends (€)"
    case invested = "Initial Investment (€)"
}

struct PortfolioSaveData: Codable {
    var positions: [Position]
    var availableCash: Double
    var manuallyInvested: Double
    var goalType: GoalType?
    var goalTarget: Double?
}

struct ChartDataItem: Identifiable { let id = UUID(); let name: String; let value: Double }
struct PriceCompareItem: Identifiable { let id = UUID(); let ticker: String; let category: String; let value: Double }
struct ScatterItem: Identifiable { let id = UUID(); let ticker: String; let weight: Double; let roi: Double }
struct ValueSourceItem: Identifiable { let id = UUID(); let category: String; let value: Double }
struct TreemapNode: Identifiable { let id = UUID(); let position: Position; let rect: CGRect }

// MARK: - 2. YAHOO SERVICE (NETWORK)
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
        } catch { print("Yahoo Error: \(error.localizedDescription)") }
        return nil
    }
    func fetchUSDEURRate() async -> Double { return await fetchStockData(for: "EUR=X")?.price ?? 1.0 }
}

// MARK: - 3. VIEW MODEL
@MainActor
class PortfolioViewModel: ObservableObject {
    @Published var positions: [Position] = [] { didSet { saveData() } }
    @Published var availableCash: Double = 0.0 { didSet { saveData() } }
    @Published var manuallyInvested: Double = 0.0 { didSet { saveData() } }
    @Published var currentGoalType: GoalType = .totalValue { didSet { saveData() } }
    @Published var currentGoalTarget: Double = 10000.0 { didSet { saveData() } }
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
    var portfolioYield: Double { currentTotalCapital > 0 ? totalDividends / currentTotalCapital : 0 }
    
    var currentGoalValue: Double {
        switch currentGoalType {
        case .totalValue: return currentTotalCapital
        case .dividends: return totalDividends
        case .invested: return manuallyInvested
        }
    }
    
    var allocationByPosition: [ChartDataItem] {
        var items = positions.map { ChartDataItem(name: $0.ticker, value: $0.currentValueEUR) }
        if availableCash > 0 { items.append(ChartDataItem(name: "Cash", value: availableCash)) }
        return items.sorted { $0.value > $1.value }
    }
    
    var allocationByCountry: [ChartDataItem] {
        var dict: [String: Double] = [:]
        for pos in positions { dict[pos.country.isEmpty ? "Unknown" : pos.country.uppercased(), default: 0] += pos.currentValueEUR }
        if availableCash > 0 { dict["Cash", default: 0] += availableCash }
        return dict.map { ChartDataItem(name: $0.key, value: $0.value) }.sorted { $0.value > $1.value }
    }
    
    var allocationBySector: [ChartDataItem] {
        var dict: [String: Double] = [:]
        for pos in positions { dict[pos.sector.isEmpty ? "Unknown" : pos.sector.capitalized, default: 0] += pos.currentValueEUR }
        if availableCash > 0 { dict["Cash", default: 0] += availableCash }
        return dict.map { ChartDataItem(name: $0.key, value: $0.value) }.sorted { $0.value > $1.value }
    }
    
    var allocationByMarketCap: [ChartDataItem] {
        var dict: [String: Double] = [:]
        for pos in positions { dict[pos.marketCap.isEmpty ? "Unknown" : pos.marketCap.capitalized, default: 0] += pos.currentValueEUR }
        if availableCash > 0 { dict["Cash", default: 0] += availableCash }
        return dict.map { ChartDataItem(name: $0.key, value: $0.value) }.sorted { $0.value > $1.value }
    }
    
    var priceComparisonData: [PriceCompareItem] {
        var items: [PriceCompareItem] = []
        for pos in positions {
            items.append(PriceCompareItem(ticker: pos.ticker, category: "Avg Cost", value: pos.averageCost))
            items.append(PriceCompareItem(ticker: pos.ticker, category: "Current", value: pos.currentPrice))
        }
        return items
    }
    
    var scatterData: [ScatterItem] {
        let total = totalValue
        guard total > 0 else { return [] }
        return positions.map { pos in
            ScatterItem(ticker: pos.ticker, weight: pos.currentValueEUR / total, roi: pos.roiPercent)
        }
    }
    
    var valueSourceDonutData: [ValueSourceItem] {
        let invested = positionsInvestedSum
        let pvLatente = totalROIValue
        var items: [ValueSourceItem] = []
        items.append(ValueSourceItem(category: "Total Invested", value: invested))
        if pvLatente > 0 { items.append(ValueSourceItem(category: "Unrealized P/L", value: pvLatente)) }
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
    
    func addPosition(ticker: String, quantity: Double, pru: Double, dividend: Double, country: String, sector: String, marketCap: String, purchaseDate: Date) {
        positions.append(Position(ticker: ticker.uppercased(), quantity: quantity, averageCost: pru, currentPrice: pru, annualDividendNet: dividend, country: country, sector: sector, marketCap: marketCap, purchaseDate: purchaseDate))
        positions.sort(using: sortOrder); Task { await refreshPrices() }
    }
    
    func updatePosition(id: UUID, quantity: Double, pru: Double, dividend: Double, country: String, sector: String, marketCap: String, dividendMonths: Set<Int>, purchaseDate: Date) {
        if let idx = positions.firstIndex(where: { $0.id == id }) {
            positions[idx].quantity = quantity; positions[idx].averageCost = pru; positions[idx].annualDividendNet = dividend
            positions[idx].country = country; positions[idx].sector = sector; positions[idx].marketCap = marketCap
            positions[idx].dividendMonths = dividendMonths; positions[idx].purchaseDate = purchaseDate
            positions.sort(using: sortOrder)
        }
    }
    
    func deletePosition(id: UUID) { positions.removeAll { $0.id == id } }
    
    private var saveFileURL: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("BlueChip_Data.json") }
    func saveData() {
        let dataToSave = PortfolioSaveData(positions: positions, availableCash: availableCash, manuallyInvested: manuallyInvested, goalType: currentGoalType, goalTarget: currentGoalTarget)
        do { try JSONEncoder().encode(dataToSave).write(to: saveFileURL, options: [.atomic]) } catch {}
    }
    func loadData() {
        do {
            let data = try Data(contentsOf: saveFileURL)
            let decoded = try JSONDecoder().decode(PortfolioSaveData.self, from: data)
            positions = decoded.positions.sorted(using: sortOrder)
            availableCash = decoded.availableCash; manuallyInvested = decoded.manuallyInvested
            if let savedGoalType = decoded.goalType { currentGoalType = savedGoalType }
            if let savedGoalTarget = decoded.goalTarget { currentGoalTarget = savedGoalTarget }
        } catch { print("ℹ️ JSON File not found or read error.") }
    }
}

// MARK: - 4. NAVIGATION & TABS
enum AppTab: String, CaseIterable {
    case composition = "Composition", fundamentals = "Fundamentals", growth = "Growth", dividends = "Dividends"
    case valuation = "Valuation", projection = "Projection", simulation = "Simulation", watchlist = "Watchlist"
    case exposure = "Exposure", transactions = "Transactions", benchmark = "Benchmark"
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

// MARK: - 5. UI COMPONENTS & CHARTS
enum ChartZoomType: Identifiable { case positions, countries, sectors, marketCaps, priceCompare, roiCombo, scatter, valueSource, heatmap, dailyRoi; var id: Int { self.hashValue } }

struct BlueChipWatermark: View {
    var body: some View {
        HStack {
            Spacer()
            Text("Powered by BlueChip")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(.secondary.opacity(0.3))
        }
        .padding(.top, 2)
    }
}

struct InteractiveLegendView: View {
    let items: [String]; let colorMap: (String) -> Color; @Binding var hiddenItems: Set<String>
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(items, id: \.self) { item in
                    Button(action: { withAnimation { if hiddenItems.contains(item) { hiddenItems.remove(item) } else { hiddenItems.insert(item) } } }) {
                        HStack(spacing: 6) { Circle().fill(colorMap(item)).frame(width: 10, height: 10); Text(item).font(.caption).foregroundColor(hiddenItems.contains(item) ? .secondary : .primary) }
                    }.buttonStyle(.plain).opacity(hiddenItems.contains(item) ? 0.4 : 1.0)
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
            HStack { Text(title).font(.headline).foregroundColor(.secondary); Spacer(); if !isExpanded { Button(action: { expandedChart = zoomType }) { Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary) }.buttonStyle(.plain) } }.padding(.bottom, 4)
            InteractiveLegendView(items: data.map { $0.name }, colorMap: color, hiddenItems: $hiddenItems).padding(.bottom, 8)
            if filteredData.isEmpty { Spacer(); Text("No data").foregroundColor(.secondary); Spacer() } else {
                Chart(filteredData) { item in
                    SectorMark(angle: .value("Value", item.value), innerRadius: .ratio(0.65), angularInset: 1.5).foregroundStyle(color(for: item.name)).cornerRadius(4)
                }.chartLegend(.hidden).chartAngleSelection(value: $selectedAngleValue).chartBackground { proxy in
                    GeometryReader { geometry in
                        if let value = selectedAngleValue {
                            let item = findItem(for: value)
                            VStack { Text(item.name).font(.headline); Text(item.value.formatted(.currency(code: "EUR"))).font(.subheadline).foregroundColor(.secondary) }.position(x: geometry.frame(in: .local).midX, y: geometry.frame(in: .local).midY)
                        }
                    }
                }.animation(.easeInOut(duration: 0.2), value: selectedAngleValue)
            }
            BlueChipWatermark()
        }.padding().frame(minHeight: 360, maxHeight: isExpanded ? .infinity : 360).background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    func findItem(for value: Double) -> ChartDataItem { var cum = 0.0; for item in filteredData { cum += item.value; if value <= cum { return item } }; return filteredData.last! }
}

struct PRUPriceChart: View {
    let data: [PriceCompareItem]; var isExpanded: Bool = false; @Binding var expandedChart: ChartZoomType?
    @State private var hiddenCategories: Set<String> = []; @State private var hiddenTickers: Set<String> = []; @State private var hoveredTicker: String? = nil
    
    let categories = ["Avg Cost", "Current"]
    var uniqueTickers: [String] { Array(Set(data.map { $0.ticker })).sorted() }
    var filteredData: [PriceCompareItem] { data.filter { !hiddenCategories.contains($0.category) && !hiddenTickers.contains($0.ticker) } }
    
    var body: some View {
        VStack {
            HStack { Text("Avg Cost vs Current Price").font(.headline).foregroundColor(.secondary); Spacer(); if !isExpanded { Button(action: { expandedChart = .priceCompare }) { Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary) }.buttonStyle(.plain) } }.padding(.bottom, 4)
            VStack(spacing: 4) {
                InteractiveLegendView(items: categories, colorMap: { $0 == "Avg Cost" ? .gray.opacity(0.6) : .blue }, hiddenItems: $hiddenCategories)
                InteractiveLegendView(items: uniqueTickers, colorMap: { _ in .primary.opacity(0.3) }, hiddenItems: $hiddenTickers)
            }.padding(.bottom, 8)
            if filteredData.isEmpty { Spacer(); Text("No data").foregroundColor(.secondary); Spacer() } else {
                Chart(filteredData) { item in
                    BarMark(x: .value("Ticker", item.ticker), y: .value("Price", item.value)).foregroundStyle(item.category == "Avg Cost" ? Color.gray.opacity(0.6) : Color.blue).position(by: .value("Category", item.category)).cornerRadius(4)
                        .annotation(position: .top) { if hoveredTicker == item.ticker { Text(item.value.formatted(.currency(code: "EUR"))).font(.system(size: 9, weight: .bold)).foregroundColor(.secondary) } }
                }.chartLegend(.hidden).chartXSelection(value: $hoveredTicker)
            }
            BlueChipWatermark()
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
            HStack { Text("Return on Investment (P/L)").font(.headline).foregroundColor(.secondary); Spacer(); if !isExpanded { Button(action: { expandedChart = .roiCombo }) { Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary) }.buttonStyle(.plain) } }.padding(.bottom, 4)
            VStack(spacing: 4) {
                InteractiveLegendView(items: metrics, colorMap: { $0 == "P/L (€)" ? .green : .purple }, hiddenItems: $hiddenMetrics)
                InteractiveLegendView(items: uniqueTickers, colorMap: { _ in .primary.opacity(0.3) }, hiddenItems: $hiddenTickers)
            }.padding(.bottom, 8)
            if filteredPositions.isEmpty { Spacer(); Text("No data").foregroundColor(.secondary); Spacer() } else {
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
            BlueChipWatermark()
        }.padding().frame(minHeight: 360, maxHeight: isExpanded ? .infinity : 360).background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

struct ModernScatterPlotChart: View {
    let data: [ScatterItem]; var isExpanded: Bool = false; @Binding var expandedChart: ChartZoomType?
    @State private var hiddenTickers: Set<String> = []; @State private var hoveredWeight: Double? = nil
    
    var uniqueTickers: [String] { data.map { $0.ticker }.sorted() }
    func color(for name: String) -> Color { if let idx = uniqueTickers.firstIndex(of: name) { return chartColors[idx % chartColors.count] }; return .gray }
    var filteredData: [ScatterItem] { data.filter { !hiddenTickers.contains($0.ticker) } }
    var hoveredItem: ScatterItem? { guard let w = hoveredWeight else { return nil }; return filteredData.min(by: { abs($0.weight - w) < abs($1.weight - w) }) }
    
    var xDomain: [Double] { guard let maxW = filteredData.map({$0.weight}).max() else { return [0, 0.1] }; return [0, maxW * 1.1] }
    var yDomain: [Double] { guard let maxR = filteredData.map({$0.roi}).max() else { return [0, 0.1] }; return [0, maxR * 1.1] }
    
    var body: some View {
        VStack {
            HStack { Text("Portfolio Weight vs Unrealized Performance").font(.headline).foregroundColor(.secondary); Spacer(); if !isExpanded { Button(action: { expandedChart = .scatter }) { Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary) }.buttonStyle(.plain) } }.padding(.bottom, 4)
            InteractiveLegendView(items: uniqueTickers, colorMap: color(for:), hiddenItems: $hiddenTickers).padding(.bottom, 8)
            
            if filteredData.isEmpty { Spacer(); Text("No data").foregroundColor(.secondary); Spacer() } else {
                Chart(filteredData) { item in
                    PointMark(x: .value("Weight", item.weight), y: .value("ROI", item.roi)).foregroundStyle(color(for: item.ticker)).symbolSize(100)
                        .annotation(position: .top, alignment: .center) {
                            if hoveredItem?.id == item.id {
                                VStack {
                                    Text(item.ticker).font(.system(size: 10, weight: .bold))
                                    Text("\(item.weight.formatted(.percent.precision(.fractionLength(1)))) | \(item.roi.formatted(.percent.precision(.fractionLength(1))))").font(.system(size: 9))
                                }.padding(4).background(Color(NSColor.windowBackgroundColor).opacity(0.9)).cornerRadius(4)
                            }
                        }
                }.chartLegend(.hidden).chartXScale(domain: xDomain).chartYScale(domain: yDomain)
                 .chartXAxis { AxisMarks { value in AxisGridLine(); AxisTick(); if let v = value.as(Double.self) { AxisValueLabel(v.formatted(.percent.precision(.fractionLength(0)))) } } }
                 .chartYAxis { AxisMarks { value in AxisGridLine(); AxisTick(); if let v = value.as(Double.self) { AxisValueLabel(v.formatted(.percent.precision(.fractionLength(0)))) } } }
                 .chartXSelection(value: $hoveredWeight)
            }
            BlueChipWatermark()
        }.padding().frame(minHeight: 360, maxHeight: isExpanded ? .infinity : 360).background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

struct ModernValueSourceChart: View {
    let data: [ValueSourceItem]; var isExpanded: Bool = false; @Binding var expandedChart: ChartZoomType?
    @State private var selectedAngleValue: Double? = nil; @State private var hiddenItems: Set<String> = []
    
    func color(for name: String) -> Color { name == "Total Invested" ? .blue : .green }
    var filteredData: [ValueSourceItem] { data.filter { !hiddenItems.contains($0.category) } }
    
    var body: some View {
        VStack {
            HStack { Text("Source of Total Stock Value").font(.headline).foregroundColor(.secondary); Spacer(); if !isExpanded { Button(action: { expandedChart = .valueSource }) { Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary) }.buttonStyle(.plain) } }.padding(.bottom, 4)
            InteractiveLegendView(items: data.map { $0.category }, colorMap: color, hiddenItems: $hiddenItems).padding(.bottom, 8)
            
            if filteredData.isEmpty { Spacer(); Text("No data").foregroundColor(.secondary); Spacer() } else {
                Chart(filteredData) { item in
                    SectorMark(angle: .value("Value", item.value), innerRadius: .ratio(0.65), angularInset: 1.5).foregroundStyle(color(for: item.category)).cornerRadius(4)
                }.chartLegend(.hidden).chartAngleSelection(value: $selectedAngleValue).chartBackground { proxy in
                    GeometryReader { geometry in
                        if let value = selectedAngleValue {
                            let item = findItem(for: value)
                            VStack { Text(item.category).font(.headline).foregroundColor(.secondary).lineLimit(1).minimumScaleFactor(0.5); Text(item.value.formatted(.currency(code: "EUR").precision(.fractionLength(0)))).font(.title3).fontWeight(.bold) }.position(x: geometry.frame(in: .local).midX, y: geometry.frame(in: .local).midY)
                        } else {
                            let total = filteredData.reduce(0) { $0 + $1.value }
                            VStack { Text("Stock Value").font(.subheadline).foregroundColor(.secondary); Text(total.formatted(.currency(code: "EUR").precision(.fractionLength(0)))).font(.title2).fontWeight(.bold) }.position(x: geometry.frame(in: .local).midX, y: geometry.frame(in: .local).midY)
                        }
                    }
                }.animation(.easeInOut(duration: 0.2), value: selectedAngleValue)
            }
            BlueChipWatermark()
        }.padding().frame(minHeight: 360, maxHeight: isExpanded ? .infinity : 360).background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    func findItem(for value: Double) -> ValueSourceItem { var cum = 0.0; for item in filteredData { cum += item.value; if value <= cum { return item } }; return filteredData.last! }
}

struct HeatmapNodeView: View {
    let node: TreemapNode
    @Binding var hoveredTicker: String?
    
    func color(for roi: Double) -> Color {
        if roi == 0 { return Color.gray.opacity(0.4) }
        let intensity = min(max(abs(roi) / 0.5, 0.3), 1.0)
        return roi > 0 ? Color.green.opacity(intensity) : Color.red.opacity(intensity)
    }
    var isHovered: Bool { hoveredTicker == node.position.ticker }
    
    var body: some View {
        ZStack {
            Rectangle().fill(color(for: node.position.roiPercent)).border(Color(NSColor.windowBackgroundColor), width: 1.5)
            VStack(spacing: 4) {
                Text(node.position.ticker).font(.system(size: node.rect.width > 45 && node.rect.height > 35 ? 14 : 8, weight: .bold)).foregroundColor(.white).lineLimit(1)
                if node.rect.width > 60 && node.rect.height > 50 { Text(node.position.roiPercent.formatted(.percent.precision(.fractionLength(1)))).font(.caption).foregroundColor(.white.opacity(0.9)).lineLimit(1) }
            }
            if isHovered {
                VStack {
                    Text(node.position.ticker).font(.caption.bold())
                    Text(node.position.currentValueEUR.formatted(.currency(code: "EUR"))).font(.caption2)
                    Text("Daily: \(node.position.dailyROIValue.formatted(.currency(code: "EUR").sign(strategy: .always())))").font(.caption2)
                }.padding(6).background(Color(NSColor.windowBackgroundColor).opacity(0.95)).cornerRadius(6).shadow(radius: 4).zIndex(10)
            }
        }.frame(width: node.rect.width, height: node.rect.height).offset(x: node.rect.minX, y: node.rect.minY).scaleEffect(isHovered ? 1.02 : 1.0).zIndex(isHovered ? 1 : 0).onContinuousHover { phase in
            switch phase { case .active(_): hoveredTicker = node.position.ticker; case .ended: hoveredTicker = nil }
        }
    }
}

struct PerformanceHeatmap: View {
    let positions: [Position]; var isExpanded: Bool = false; @Binding var expandedChart: ChartZoomType?
    @State private var hoveredTicker: String? = nil
    
    var totalValue: Double { positions.reduce(0) { $0 + $1.currentValueEUR } }
    var sortedPositions: [Position] { positions.sorted { $0.currentValueEUR > $1.currentValueEUR } }
    
    func layoutNodes(in rect: CGRect) -> [TreemapNode] {
        var nodes: [TreemapNode] = []; var currentRect = rect; var remainingWeight = totalValue
        for item in sortedPositions {
            guard remainingWeight > 0 else { continue }
            let fraction = item.currentValueEUR / remainingWeight
            if currentRect.width > currentRect.height {
                let w = currentRect.width * CGFloat(fraction)
                nodes.append(TreemapNode(position: item, rect: CGRect(x: currentRect.minX, y: currentRect.minY, width: w, height: currentRect.height)))
                currentRect = CGRect(x: currentRect.minX + w, y: currentRect.minY, width: currentRect.width - w, height: currentRect.height)
            } else {
                let h = currentRect.height * CGFloat(fraction)
                nodes.append(TreemapNode(position: item, rect: CGRect(x: currentRect.minX, y: currentRect.minY, width: currentRect.width, height: h)))
                currentRect = CGRect(x: currentRect.minX, y: currentRect.minY + h, width: currentRect.width, height: currentRect.height - h)
            }
            remainingWeight -= item.currentValueEUR
        }
        return nodes
    }
    
    var body: some View {
        VStack {
            HStack { Text("Performance Heatmap").font(.headline).foregroundColor(.secondary); Spacer(); if !isExpanded { Button(action: { expandedChart = .heatmap }) { Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary) }.buttonStyle(.plain) } }.padding(.bottom, 8)
            if positions.isEmpty { Spacer(); Text("No data").foregroundColor(.secondary); Spacer() } else {
                GeometryReader { geo in ZStack(alignment: .topLeading) { ForEach(layoutNodes(in: CGRect(origin: .zero, size: geo.size))) { node in HeatmapNodeView(node: node, hoveredTicker: $hoveredTicker) } } }
            }
            BlueChipWatermark()
        }.padding().frame(minHeight: 360, maxHeight: isExpanded ? .infinity : 360).background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

struct DailyROIChart: View {
    let positions: [Position]; var isExpanded: Bool = false; @Binding var expandedChart: ChartZoomType?
    @State private var hiddenTickers: Set<String> = []; @State private var hoveredTicker: String? = nil
    
    var uniqueTickers: [String] { positions.map { $0.ticker }.sorted() }
    func color(for name: String) -> Color { if let idx = uniqueTickers.firstIndex(of: name) { return chartColors[idx % chartColors.count] }; return .gray }
    var filteredPositions: [Position] { positions.filter { !hiddenTickers.contains($0.ticker) } }
    
    var body: some View {
        VStack {
            HStack { Text("Daily P/L by Holding Period").font(.headline).foregroundColor(.secondary); Spacer(); if !isExpanded { Button(action: { expandedChart = .dailyRoi }) { Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary) }.buttonStyle(.plain) } }.padding(.bottom, 4)
            InteractiveLegendView(items: uniqueTickers, colorMap: color(for:), hiddenItems: $hiddenTickers).padding(.bottom, 8)
            
            if filteredPositions.isEmpty { Spacer(); Text("No data").foregroundColor(.secondary); Spacer() } else {
                Chart(filteredPositions) { pos in
                    BarMark(x: .value("Ticker", pos.ticker), y: .value("Daily P/L", pos.dailyROIValue)).foregroundStyle(pos.dailyROIValue >= 0 ? Color.green.opacity(0.7) : Color.red.opacity(0.7)).cornerRadius(4)
                        .annotation(position: pos.dailyROIValue >= 0 ? .top : .bottom) {
                            if hoveredTicker == pos.ticker { Text(pos.dailyROIValue.formatted(.currency(code: "EUR").sign(strategy: .always()))).font(.system(size: 9, weight: .bold)).padding(2).background(Color(NSColor.windowBackgroundColor).opacity(0.8)).cornerRadius(2) }
                        }
                }.chartLegend(.hidden).chartXSelection(value: $hoveredTicker)
            }
            BlueChipWatermark()
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
            case .sectors: ModernDonutChart(data: viewModel.allocationBySector, title: "", zoomType: zoomType, isExpanded: true, expandedChart: .constant(nil))
            case .marketCaps: ModernDonutChart(data: viewModel.allocationByMarketCap, title: "", zoomType: zoomType, isExpanded: true, expandedChart: .constant(nil))
            case .priceCompare: PRUPriceChart(data: viewModel.priceComparisonData, isExpanded: true, expandedChart: .constant(nil))
            case .roiCombo: ROIComboChart(positions: viewModel.positions, isExpanded: true, expandedChart: .constant(nil))
            case .scatter: ModernScatterPlotChart(data: viewModel.scatterData, isExpanded: true, expandedChart: .constant(nil))
            case .valueSource: ModernValueSourceChart(data: viewModel.valueSourceDonutData, isExpanded: true, expandedChart: .constant(nil))
            case .heatmap: PerformanceHeatmap(positions: viewModel.positions, isExpanded: true, expandedChart: .constant(nil))
            case .dailyRoi: DailyROIChart(positions: viewModel.positions, isExpanded: true, expandedChart: .constant(nil))
            }
        }.padding(30).frame(minWidth: 900, minHeight: 700)
    }
    var titleForZoom: String {
        switch zoomType {
        case .positions: return "Weight by Position"; case .countries: return "Geographic Exposure"; case .sectors: return "Sector Allocation"; case .marketCaps: return "Market Cap Allocation"
        case .priceCompare: return "Avg Cost vs Current Price"; case .roiCombo: return "Return on Investment (P/L)"; case .scatter: return "Portfolio Weight vs Unrealized Performance"
        case .valueSource: return "Source of Total Stock Value"; case .heatmap: return "Performance Heatmap"; case .dailyRoi: return "Daily P/L by Holding Period"
        }
    }
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

struct GoalProgressBar: View {
    let title: String; let currentValue: Double; let targetValue: Double
    var progress: Double { guard targetValue > 0 else { return 0 }; return min(max(currentValue / targetValue, 0), 1) }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Text("Goal : \(title)").font(.headline); Spacer(); Text("\(currentValue.formatted(.currency(code: "EUR"))) / \(targetValue.formatted(.currency(code: "EUR")))").font(.subheadline).fontWeight(.bold).foregroundColor(progress >= 1 ? .green : .primary) }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.windowBackgroundColor)).frame(height: 14)
                    RoundedRectangle(cornerRadius: 8).fill(LinearGradient(gradient: Gradient(colors: [.blue, .purple]), startPoint: .leading, endPoint: .trailing)).frame(width: max(0, geometry.size.width * CGFloat(progress)), height: 14).animation(.spring(), value: progress)
                }
            }.frame(height: 14)
        }.padding().background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1).help("Double-click to edit your goal")
    }
}

// MARK: - 6. FORMS
struct AddPositionView: View {
    @Environment(\.dismiss) var dismiss; @ObservedObject var viewModel: PortfolioViewModel
    @State private var ticker = ""; @State private var quantity: Double = 0; @State private var pru: Double = 0
    @State private var dividend: Double = 0; @State private var country = ""; @State private var purchaseDate = Date()
    @State private var sector = ""; @State private var marketCap = ""
    var body: some View {
        Form {
            Section(header: Text("New Position").font(.headline)) {
                TextField("Ticker (e.g., AAPL)", text: $ticker); TextField("Quantity", value: $quantity, format: .number)
                TextField("Avg Cost (Original Currency)", value: $pru, format: .number); TextField("Net Dividend/Share", value: $dividend, format: .number)
                TextField("Country (e.g., US, FR)", text: $country); TextField("Sector", text: $sector); TextField("Market Cap", text: $marketCap)
                DatePicker("Purchase Date", selection: $purchaseDate, displayedComponents: .date)
            }.padding()
            HStack { Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button("Add") { if !ticker.isEmpty && quantity > 0 { viewModel.addPosition(ticker: ticker, quantity: quantity, pru: pru, dividend: dividend, country: country, sector: sector, marketCap: marketCap, purchaseDate: purchaseDate); dismiss() } }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent) }.padding()
        }.frame(width: 400).padding()
    }
}

struct EditPositionView: View {
    @Environment(\.dismiss) var dismiss; @ObservedObject var viewModel: PortfolioViewModel; let position: Position
    @State private var quantity: Double; @State private var pru: Double; @State private var dividend: Double
    @State private var country: String; @State private var sector: String; @State private var marketCap: String
    @State private var purchaseDate: Date; @State private var dividendMonths: Set<Int>
    let monthsNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    init(viewModel: PortfolioViewModel, position: Position) { self.viewModel = viewModel; self.position = position; _quantity = State(initialValue: position.quantity); _pru = State(initialValue: position.averageCost); _dividend = State(initialValue: position.annualDividendNet); _country = State(initialValue: position.country); _sector = State(initialValue: position.sector); _marketCap = State(initialValue: position.marketCap); _purchaseDate = State(initialValue: position.purchaseDate); _dividendMonths = State(initialValue: position.dividendMonths) }
    var body: some View {
        Form {
            Section(header: Text("Edit \(position.ticker)").font(.headline)) {
                TextField("Quantity", value: $quantity, format: .number); TextField("Avg Cost", value: $pru, format: .number)
                TextField("Net Dividend/Share", value: $dividend, format: .number); TextField("Country", text: $country)
                TextField("Sector", text: $sector); TextField("Market Cap", text: $marketCap)
                DatePicker("Purchase Date", selection: $purchaseDate, displayedComponents: .date)
            }.padding(.bottom, 8)
            Section(header: Text("Dividend Months").font(.subheadline).foregroundColor(.secondary)) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 8) { ForEach(0..<12, id: \.self) { index in let m = index + 1; Toggle(monthsNames[index], isOn: Binding(get: { dividendMonths.contains(m) }, set: { isSet in if isSet { dividendMonths.insert(m) } else { dividendMonths.remove(m) } })).toggleStyle(.button).font(.caption) } }
            }.padding(.bottom, 16)
            HStack { Button(role: .destructive) { viewModel.deletePosition(id: position.id); dismiss() } label: { Text("Delete") }; Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction); Button("Save") { viewModel.updatePosition(id: position.id, quantity: quantity, pru: pru, dividend: dividend, country: country, sector: sector, marketCap: marketCap, dividendMonths: dividendMonths, purchaseDate: purchaseDate); dismiss() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent) }
        }.frame(width: 450).padding()
    }
}

struct SimpleNumberEditView: View {
    @Environment(\.dismiss) var dismiss; let title: String; @Binding var value: Double; @State private var input: Double = 0
    var body: some View {
        Form { Section(header: Text(title).font(.headline)) { TextField("Amount (€)", value: $input, format: .number) }.padding(); HStack { Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button("Save") { value = input; dismiss() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent) }.padding() }.frame(width: 300).padding().onAppear { input = value }
    }
}

struct EditGoalView: View {
    @Environment(\.dismiss) var dismiss; @ObservedObject var viewModel: PortfolioViewModel
    @State private var selectedGoal: GoalType; @State private var targetInput: Double
    init(viewModel: PortfolioViewModel) { self.viewModel = viewModel; _selectedGoal = State(initialValue: viewModel.currentGoalType); _targetInput = State(initialValue: viewModel.currentGoalTarget) }
    var body: some View {
        Form {
            Section(header: Text("Set a Goal").font(.headline)) { Picker("Goal Type", selection: $selectedGoal) { ForEach(GoalType.allCases, id: \.self) { type in Text(type.rawValue).tag(type) } }; TextField("Target Amount (€)", value: $targetInput, format: .number) }.padding()
            HStack { Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button("Save") { viewModel.currentGoalType = selectedGoal; viewModel.currentGoalTarget = targetInput; dismiss() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent) }.padding()
        }.frame(width: 380).padding()
    }
}

// MARK: - 7. TAB VIEWS (PAGES)
struct CompositionTabView: View {
    @ObservedObject var viewModel: PortfolioViewModel
    @State private var selection: Set<Position.ID> = []
    @State private var showCashSheet = false; @State private var showInvestedSheet = false
    @State private var showGoalSheet = false; @State private var positionToEdit: Position? = nil; @State private var chartToZoom: ChartZoomType? = nil
    
    // FIX 1 : Hauteur fixe pour exactement 10 lignes + en-tête. Satisfaction : <= 10 -> pas de scroll. > 10 -> scroll interne activé.
    let tableFrameHeight: CGFloat = 340
    
    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 24) {
                // --- DASHBOARD ---
                VStack(spacing: 16) {
                    HStack(spacing: 16) {
                        Button(action: { showCashSheet = true }) { DashboardCard(title: "Cash", value: viewModel.availableCash.formatted(.currency(code: "EUR")), titleIcon: "pencil") }.buttonStyle(.plain)
                        Button(action: { showInvestedSheet = true }) { DashboardCard(title: "Initial Investment", value: viewModel.manuallyInvested.formatted(.currency(code: "EUR")), titleIcon: "pencil") }.buttonStyle(.plain)
                        DashboardCard(title: "Total (Current + Cash)", value: viewModel.currentTotalCapital.formatted(.currency(code: "EUR")))
                        DashboardCard(title: "Stock Value", value: viewModel.totalValue.formatted(.currency(code: "EUR")))
                    }
                    HStack(spacing: 16) {
                        // FIX 2 : AJOUT DU SHADOW MANQUANT !
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Unrealized P/L").font(.subheadline).foregroundColor(.secondary).lineLimit(1)
                            Text(viewModel.totalROIValue.formatted(.currency(code: "EUR").sign(strategy: .always()))).font(.title2).fontWeight(.bold).foregroundColor(getColor(for: viewModel.totalROIValue))
                            Text(viewModel.totalROIPercent.formatted(.percent.precision(.fractionLength(2)).sign(strategy: .always()))).font(.caption).padding(.horizontal, 6).padding(.vertical, 2).background(getColor(for: viewModel.totalROIValue).opacity(0.1)).foregroundColor(getColor(for: viewModel.totalROIValue)).cornerRadius(4)
                        }.padding().frame(maxWidth: .infinity, alignment: .leading).background(Color(NSColor.controlBackgroundColor)).cornerRadius(10).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                        DashboardCard(title: "Positions", value: "\(viewModel.positionCount)")
                        DashboardCard(title: "Annual Dividends", value: viewModel.totalDividends.formatted(.currency(code: "EUR")))
                        DashboardCard(title: "Total Yield", value: viewModel.portfolioYield.formatted(.percent.precision(.fractionLength(2))))
                    }
                }
                
                GoalProgressBar(title: viewModel.currentGoalType.rawValue, currentValue: viewModel.currentGoalValue, targetValue: viewModel.currentGoalTarget).contentShape(Rectangle()).onTapGesture(count: 2) { showGoalSheet = true }
                
                // FIX 1 : Table dans un conteneur stylisé à hauteur fixe
                VStack(spacing: 0) {
                    Table(viewModel.positions, selection: $selection, sortOrder: $viewModel.sortOrder) {
                        TableColumn("Ticker", value: \.ticker) { position in
                            HStack { Circle().fill(Color.gray.opacity(0.2)).frame(width: 24, height: 24).overlay(Text(position.ticker.prefix(1)).font(.caption).fontWeight(.bold).foregroundColor(.primary)); Text(position.ticker).font(.system(.body, design: .monospaced)).fontWeight(.bold) }
                            .contentShape(Rectangle()).onTapGesture(count: 2) { positionToEdit = position }.contextMenu { Button(role: .destructive) { viewModel.deletePosition(id: position.id) } label: { Label("Delete", systemImage: "trash") } }
                        }
                        TableColumn("Qty", value: \.quantity) { pos in Text("\(pos.quantity, specifier: "%.2f")").frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()).onTapGesture(count: 2) { positionToEdit = pos } }
                        TableColumn("Price", value: \.currentPrice) { pos in Text(pos.currentPrice, format: .currency(code: pos.currency)).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()).onTapGesture(count: 2) { positionToEdit = pos } }
                        TableColumn("Avg Cost", value: \.averageCost) { pos in Text(pos.averageCost, format: .currency(code: pos.currency)).foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()).onTapGesture(count: 2) { positionToEdit = pos } }
                        TableColumn("Total Value", value: \.currentValueEUR) { pos in Text(pos.currentValueEUR, format: .currency(code: "EUR")).fontWeight(.medium).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()).onTapGesture(count: 2) { positionToEdit = pos } }
                        TableColumn("P/L €", value: \.roiValue) { pos in Text(pos.roiValue, format: .currency(code: "EUR").sign(strategy: .always())).foregroundColor(getColor(for: pos.roiValue)).fontWeight(.medium).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()).onTapGesture(count: 2) { positionToEdit = pos } }
                        TableColumn("P/L %", value: \.roiPercent) { pos in Text(pos.roiPercent, format: .percent.precision(.fractionLength(2)).sign(strategy: .always())).padding(.horizontal, 8).padding(.vertical, 2).background(getColor(for: pos.roiValue).opacity(0.1)).foregroundColor(getColor(for: pos.roiValue)).cornerRadius(4).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()).onTapGesture(count: 2) { positionToEdit = pos } }
                    }
                    .tableStyle(.inset)
                }
                .frame(height: tableFrameHeight)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                
                // --- CHARTS ---
                VStack(spacing: 24) {
                    HStack(spacing: 24) {
                        ModernDonutChart(data: viewModel.allocationByPosition, title: "Weight by Position", zoomType: .positions, expandedChart: $chartToZoom)
                        ModernDonutChart(data: viewModel.allocationByCountry, title: "Geographic Exposure", zoomType: .countries, expandedChart: $chartToZoom)
                    }
                    HStack(spacing: 24) {
                        ModernDonutChart(data: viewModel.allocationBySector, title: "Sector Allocation", zoomType: .sectors, expandedChart: $chartToZoom)
                        ModernDonutChart(data: viewModel.allocationByMarketCap, title: "Market Cap Allocation", zoomType: .marketCaps, expandedChart: $chartToZoom)
                    }
                    HStack(spacing: 24) {
                        PRUPriceChart(data: viewModel.priceComparisonData, expandedChart: $chartToZoom)
                        ROIComboChart(positions: viewModel.positions, expandedChart: $chartToZoom)
                    }
                    HStack(spacing: 24) {
                        PerformanceHeatmap(positions: viewModel.positions, expandedChart: $chartToZoom)
                        DailyROIChart(positions: viewModel.positions, expandedChart: $chartToZoom)
                    }
                }
            }.padding()
        }
        .sheet(isPresented: $showCashSheet) { SimpleNumberEditView(title: "Edit Cash", value: $viewModel.availableCash) }
        .sheet(isPresented: $showInvestedSheet) { SimpleNumberEditView(title: "Edit Initial Investment", value: $viewModel.manuallyInvested) }
        .sheet(isPresented: $showGoalSheet) { EditGoalView(viewModel: viewModel) }
        .sheet(item: $positionToEdit) { position in EditPositionView(viewModel: viewModel, position: position) }
        .sheet(item: $chartToZoom) { type in FullScreenChartView(zoomType: type, viewModel: viewModel) }
    }
    func getColor(for value: Double) -> Color { value >= 0 ? .green : .red }
}

// MARK: - 8. MAIN VIEW (CONTAINER)
struct ContentView: View {
    @StateObject private var viewModel = PortfolioViewModel()
    @State private var selectedTab: AppTab = .composition
    @State private var showAddSheet = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("BlueChip - Stocks Portfolio Manager").font(.system(size: 24, weight: .black, design: .rounded)).foregroundColor(.primary)
                Spacer()
                Button(action: { Task { await viewModel.refreshPrices() } }) { if viewModel.isLoading { ProgressView().controlSize(.small) } else { Label("Refresh", systemImage: "arrow.clockwise") } }.disabled(viewModel.isLoading).buttonStyle(.bordered).padding(.trailing, 8)
                Button(action: { showAddSheet = true }) { Label("Add", systemImage: "plus") }.buttonStyle(.borderedProminent)
            }.padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 10)
            
            HStack { CustomTabBar(selectedTab: $selectedTab); Spacer() }
            Divider()
            
            Group {
                switch selectedTab {
                case .composition: CompositionTabView(viewModel: viewModel)
                default: VStack(spacing: 20) { Image(systemName: "hammer.fill").font(.system(size: 50)).foregroundColor(.secondary); Text("\(selectedTab.rawValue) view is under construction.").font(.title).foregroundColor(.secondary) }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .navigationTitle("")
        .sheet(isPresented: $showAddSheet) { AddPositionView(viewModel: viewModel) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in viewModel.saveData() }
    }
}
