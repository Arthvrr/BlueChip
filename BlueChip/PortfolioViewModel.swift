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
    @Published var positions: [Position] = [] { didSet { saveData() } }
    @Published var availableCash: Double = 0.0 { didSet { saveData() } }
    @Published var manuallyInvested: Double = 0.0 { didSet { saveData() } }
    @Published var currentGoalType: GoalType = .totalValue { didSet { saveData() } }
    @Published var currentGoalTarget: Double = 10000.0 { didSet { saveData() } }
    @Published var dividendYears: [DividendYear] = [] { didSet { saveData() } }
    @Published var dividendStartYear: Int = 2022 { didSet { setupDividendYears(); saveData() } }
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
    
    func color(for ticker: String) -> Color {
        let sortedTickers = Array(Set(positions.map { $0.ticker })).sorted()
        if let idx = sortedTickers.firstIndex(of: ticker) { return positionColors[idx % positionColors.count] }
        return .gray
    }
    
    var currentGoalValue: Double {
        switch currentGoalType {
        case .totalValue: return currentTotalCapital; case .dividends: return totalDividends; case .invested: return manuallyInvested
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
    
    init() { loadData(); setupDividendYears(); Task { await refreshPrices() } }
    
    func setupDividendYears() {
        let currentYear = Calendar.current.component(.year, from: Date())
        let endYear = currentYear + 30
        var newYears: [DividendYear] = []
        for y in dividendStartYear...endYear {
            if let existing = dividendYears.first(where: { $0.year == y }) { newYears.append(existing) } else { newYears.append(DividendYear(year: y)) }
        }
        if newYears.count != dividendYears.count || newYears.first?.year != dividendYears.first?.year { dividendYears = newYears }
    }
    
    func refreshPrices() async {
        isLoading = true; let rate = await yahooService.fetchUSDEURRate(); let tickers = Array(Set(positions.map { $0.ticker }))
        for ticker in tickers {
            if let data = await yahooService.fetchStockData(for: ticker) {
                for i in 0..<positions.count where positions[i].ticker == ticker { positions[i].currentPrice = data.price; positions[i].currency = data.currency; positions[i].usdToEurRate = rate }
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
            positions[idx].quantity = quantity; positions[idx].averageCost = pru; positions[idx].annualDividendNet = dividend; positions[idx].country = country; positions[idx].sector = sector; positions[idx].marketCap = marketCap; positions[idx].dividendMonths = dividendMonths; positions[idx].purchaseDate = purchaseDate; positions.sort(using: sortOrder)
        }
    }
    func deletePosition(id: UUID) { positions.removeAll { $0.id == id } }
    
    private var saveFileURL: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("BlueChip_Data.json") }
    func saveData() {
        let dataToSave = PortfolioSaveData(positions: positions, availableCash: availableCash, manuallyInvested: manuallyInvested, goalType: currentGoalType, goalTarget: currentGoalTarget, dividendYears: dividendYears, dividendStartYear: dividendStartYear)
        do { try JSONEncoder().encode(dataToSave).write(to: saveFileURL, options: [.atomic]) } catch {}
    }
    func loadData() {
        do {
            let data = try Data(contentsOf: saveFileURL)
            let decoded = try JSONDecoder().decode(PortfolioSaveData.self, from: data)
            positions = decoded.positions.sorted(using: sortOrder); availableCash = decoded.availableCash; manuallyInvested = decoded.manuallyInvested
            if let savedGoalType = decoded.goalType { currentGoalType = savedGoalType }
            if let savedGoalTarget = decoded.goalTarget { currentGoalTarget = savedGoalTarget }
            if let savedDivYears = decoded.dividendYears { dividendYears = savedDivYears }
            if let savedStartYear = decoded.dividendStartYear { dividendStartYear = savedStartYear }
        } catch { print("ℹ️ JSON File not found or read error.") }
    }
}
