import SwiftUI
import Combine

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

@MainActor
class PortfolioViewModel: ObservableObject {
    @Published var positions: [Position] = [] { didSet { updateDividendsViewData(); saveData() } }
    @Published var availableCash: Double = 0.0 { didSet { updateDividendsViewData(); saveData() } }
    @Published var manuallyInvested: Double = 0.0 { didSet { saveData() } }
    
    // GOAL COMPOSITION
    @Published var currentGoalType: GoalType = .totalValue { didSet { saveData() } }
    @Published var currentGoalTarget: Double = 10000.0 { didSet { saveData() } }
    
    // GOAL DIVIDENDES (SÉPARÉ !)
    @Published var dividendGoalType: DividendGoalType = .dividendsAnnual { didSet { saveData() } }
    @Published var dividendGoalTarget: Double = 1000.0 { didSet { saveData() } }
    
    @Published var dividendYears: [DividendYear] = [] { didSet { saveData() } }
    @Published var dividendStartYear: Int = 2022 { didSet { setupDividendYears(); setupGrowthYears(); saveData() } }
    @Published var isLoading = false
    @Published var sortOrder = [KeyPathComparator(\Position.ticker)] { didSet { positions.sort(using: sortOrder) } }
    
    @Published var expectedMonthlyDividendSeries: [ExpectedMonthlyDividendSeries] = []
    @Published var stockYieldsData: [StockYieldDataItem] = []
    
    // ==================
    // GOAL GROWTH (NOUVEAU)
    // ==================
    @Published var growthGoalType: GrowthGoalType = .targetReturnPercent { didSet { saveData() } }
    @Published var growthGoalTarget: Double = 10.0 { didSet { saveData() } }

    @Published var growthYears: [GrowthYear] = [] { didSet { saveData() } }
    
    private let yahooService = YahooFinanceService()
    
    var positionsInvestedSum: Double { positions.reduce(0) { $0 + $1.investedAmountEUR } }
    var totalValue: Double { positions.reduce(0) { $0 + $1.currentValueEUR } }
    var currentTotalCapital: Double { totalValue + availableCash }
    var totalROIValue: Double { totalValue - positionsInvestedSum }
    var totalROIPercent: Double { positionsInvestedSum > 0 ? totalROIValue / positionsInvestedSum : 0 }
    var positionCount: Int { positions.count }
    var totalDividends: Double { positions.reduce(0) { $0 + $1.totalDividendEUR } }
    var portfolioYield: Double { currentTotalCapital > 0 ? totalDividends / currentTotalCapital : 0 }
    
    func color(for ticker: String) -> Color {
        let sortedTickers = Array(Set(positions.map { $0.ticker })).sorted()
        if let idx = sortedTickers.firstIndex(of: ticker) { return positionColors[idx % positionColors.count] }
        return .gray
    }
    
    var currentGoalValue: Double {
        switch currentGoalType {
        case .totalValue: return currentTotalCapital
        case .invested: return manuallyInvested
        }
    }
    
    var allocationByPosition: [ChartDataItem] {
        var items = positions.map { ChartDataItem(name: $0.ticker, value: $0.currentValueEUR) }
        if availableCash > 0 { items.append(ChartDataItem(name: "Cash", value: availableCash)) }
        return items.sorted { $0.value > $1.value }
    }
    var allocationByCountry: [ChartDataItem] {
        var dict: [String: Double] = [:]; for pos in positions { dict[pos.country.isEmpty ? "Unknown" : pos.country.uppercased(), default: 0] += pos.currentValueEUR }
        if availableCash > 0 { dict["Cash", default: 0] += availableCash }
        return dict.map { ChartDataItem(name: $0.key, value: $0.value) }.sorted { $0.value > $1.value }
    }
    var allocationBySector: [ChartDataItem] {
        var dict: [String: Double] = [:]; for pos in positions { dict[pos.sector.isEmpty ? "Unknown" : pos.sector.capitalized, default: 0] += pos.currentValueEUR }
        if availableCash > 0 { dict["Cash", default: 0] += availableCash }
        return dict.map { ChartDataItem(name: $0.key, value: $0.value) }.sorted { $0.value > $1.value }
    }
    var allocationByMarketCap: [ChartDataItem] {
        var dict: [String: Double] = [:]; for pos in positions { dict[pos.marketCap.isEmpty ? "Unknown" : pos.marketCap.capitalized, default: 0] += pos.currentValueEUR }
        if availableCash > 0 { dict["Cash", default: 0] += availableCash }
        return dict.map { ChartDataItem(name: $0.key, value: $0.value) }.sorted { $0.value > $1.value }
    }
    var priceComparisonData: [PriceCompareItem] {
        var items: [PriceCompareItem] = []; for pos in positions { items.append(PriceCompareItem(ticker: pos.ticker, category: "Avg Cost", value: pos.averageCost)); items.append(PriceCompareItem(ticker: pos.ticker, category: "Current", value: pos.currentPrice)) }
        return items
    }
    var scatterData: [ScatterItem] {
        let total = totalValue; guard total > 0 else { return [] }; return positions.map { ScatterItem(ticker: $0.ticker, weight: $0.currentValueEUR / total, roi: $0.roiPercent) }
    }
    var valueSourceDonutData: [ValueSourceItem] {
        let invested = positionsInvestedSum; let pvLatente = totalROIValue; var items: [ValueSourceItem] = []; items.append(ValueSourceItem(category: "Total Invested", value: invested))
        if pvLatente > 0 { items.append(ValueSourceItem(category: "Unrealized P/L", value: pvLatente)) }; return items
    }
    
    init() {
        loadData()
        setupDividendYears()
        setupGrowthYears()
        Task { await refreshPrices() }
        updateDividendsViewData()
        }
    
    func setupDividendYears() {
        let currentYear = Calendar.current.component(.year, from: Date())
        let endYear = currentYear + 30
        var newYears: [DividendYear] = []
        for y in dividendStartYear...endYear {
            if let existing = dividendYears.first(where: { $0.year == y }) { newYears.append(existing) } else { newYears.append(DividendYear(year: y)) }
        }
        if newYears.count != dividendYears.count || newYears.first?.year != dividendYears.first?.year { dividendYears = newYears }
    }
    
    func setupGrowthYears() {
        let currentYear = Calendar.current.component(.year, from: Date())
        let endYear = currentYear + 30
        var newYears: [GrowthYear] = []
        for y in dividendStartYear...endYear {
            if let existing = growthYears.first(where: { $0.year == y }) {
                newYears.append(existing)
            } else {
                newYears.append(GrowthYear(year: y, startWallet: 0, invested: 0, endWallet: 0, totalInvest: 0))
            }
        }
        if newYears.count != growthYears.count || newYears.first?.year != growthYears.first?.year {
            growthYears = newYears
        }
    }
    
    func refreshPrices() async {
        isLoading = true; let rate = await yahooService.fetchUSDEURRate(); let tickers = Array(Set(positions.map { $0.ticker }))
        for ticker in tickers {
            if let data = await yahooService.fetchStockData(for: ticker) {
                for i in 0..<positions.count where positions[i].ticker == ticker { positions[i].currentPrice = data.price; positions[i].currency = data.currency; positions[i].usdToEurRate = rate }
            }
        }
        positions.sort(using: sortOrder); updateDividendsViewData(); saveData(); isLoading = false
    }
    
    func updateDividendsViewData() {
        let monthsShort = Calendar.current.shortMonthSymbols
        var newExpectedSeries: [ExpectedMonthlyDividendSeries] = []
        
        for pos in positions {
            guard pos.totalDividendEUR > 0, !pos.dividendMonths.isEmpty else { continue }
            let netPerMonthEUR = pos.totalDividendEUR / Double(pos.dividendMonths.count)
            let brutPerMonthEUR = netPerMonthEUR / 0.85
            
            for m in pos.dividendMonths {
                guard m >= 1 && m <= 12 else { continue }
                let monthName = monthsShort[m-1]
                newExpectedSeries.append(ExpectedMonthlyDividendSeries(month: m, monthName: monthName, type: "Net", ticker: pos.ticker, amount: netPerMonthEUR))
                newExpectedSeries.append(ExpectedMonthlyDividendSeries(month: m, monthName: monthName, type: "Gross", ticker: pos.ticker, amount: brutPerMonthEUR))
            }
        }
        self.expectedMonthlyDividendSeries = newExpectedSeries.sorted { $0.month < $1.month }
        
        self.stockYieldsData = positions.filter { $0.currentValueEUR > 0 }
            .map { StockYieldDataItem(ticker: $0.ticker, yield: $0.stockYieldEUR * 100.0) }
            .sorted { $0.ticker < $1.ticker }
    }
    
    func addPosition(ticker: String, quantity: Double, pru: Double, dividend: Double, country: String, sector: String, marketCap: String, purchaseDate: Date) {
        positions.append(Position(ticker: ticker.uppercased(), quantity: quantity, averageCost: pru, currentPrice: pru, annualDividendNet: dividend, country: country, sector: sector, marketCap: marketCap, purchaseDate: purchaseDate))
        positions.sort(using: sortOrder); Task { await refreshPrices() }
    }
    func updatePosition(id: UUID, quantity: Double, pru: Double, dividend: Double, country: String, sector: String, marketCap: String, dividendMonths: Set<Int>, purchaseDate: Date) {
        if let idx = positions.firstIndex(where: { $0.id == id }) {
            positions[idx].quantity = quantity; positions[idx].averageCost = pru; positions[idx].annualDividendNet = dividend; positions[idx].country = country; positions[idx].sector = sector; positions[idx].marketCap = marketCap; positions[idx].dividendMonths = dividendMonths; positions[idx].purchaseDate = purchaseDate; positions.sort(using: sortOrder)
        }
    }
    func deletePosition(id: UUID) { positions.removeAll { $0.id == id } }
    
    private var saveFileURL: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("BlueChip_Data.json") }
    
    func saveData() {
        let dataToSave = PortfolioSaveData(
            positions: positions,
            availableCash: availableCash,
            manuallyInvested: manuallyInvested,
            
            goalType: currentGoalType,
            goalTarget: currentGoalTarget,
            
            dividendGoalType: dividendGoalType,
            dividendGoalTarget: dividendGoalTarget,
            dividendYears: dividendYears,
            dividendStartYear: dividendStartYear,
            
            growthGoalType: growthGoalType,
            growthGoalTarget: growthGoalTarget,
            growthYears: growthYears,
        )
        do { try JSONEncoder().encode(dataToSave).write(to: saveFileURL, options: [.atomic]) } catch {}
    }
    func loadData() {
        do {
            let data = try Data(contentsOf: saveFileURL)
            let decoded = try JSONDecoder().decode(PortfolioSaveData.self, from: data)
            positions = decoded.positions.sorted(using: sortOrder); availableCash = decoded.availableCash; manuallyInvested = decoded.manuallyInvested
            if let savedGoalType = decoded.goalType { currentGoalType = savedGoalType }
            if let savedGoalTarget = decoded.goalTarget { currentGoalTarget = savedGoalTarget }
            
            //DIVIDENDS
            if let savedDivGoalType = decoded.dividendGoalType { dividendGoalType = savedDivGoalType }
            if let savedDivGoalTarget = decoded.dividendGoalTarget { dividendGoalTarget = savedDivGoalTarget }
            if let savedDivYears = decoded.dividendYears { dividendYears = savedDivYears }
            if let savedStartYear = decoded.dividendStartYear { dividendStartYear = savedStartYear }
            
            //GROWTH
            if let savedGrowthGoalType = decoded.growthGoalType { growthGoalType = savedGrowthGoalType }
            if let savedGrowthGoalTarget = decoded.growthGoalTarget { growthGoalTarget = savedGrowthGoalTarget }
            if let savedGrowthYears = decoded.growthYears { growthYears = savedGrowthYears }
        } catch { print("ℹ️ JSON File not found or read error.") }
    }
}
