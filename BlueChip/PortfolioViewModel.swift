import SwiftUI
import Combine
import SwiftData

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
    
    var modelContext: ModelContext?
    @Published var settings: AppSettings?
    
    // ==========================================
    // VARIABLES PUBLIÉES (Synchronisées avec SwiftData)
    // ==========================================
    
    @Published var positions: [Position] = [] { didSet { updateDividendsViewData() } }
    
    @Published var availableCash: Double = 0.0 { didSet { settings?.availableCash = availableCash; updateDividendsViewData() } }
    @Published var manuallyInvested: Double = 0.0 { didSet { settings?.manuallyInvested = manuallyInvested } }
    
    @Published var currentGoalType: GoalType = .totalValue { didSet { settings?.goalType = currentGoalType } }
    @Published var currentGoalTarget: Double = 10000.0 { didSet { settings?.goalTarget = currentGoalTarget } }
    
    @Published var dividendGoalType: DividendGoalType = .dividendsAnnual { didSet { settings?.dividendGoalType = dividendGoalType } }
    @Published var dividendGoalTarget: Double = 1000.0 { didSet { settings?.dividendGoalTarget = dividendGoalTarget } }
    
    @Published var dividendYears: [DividendYear] = []
    @Published var dividendStartYear: Int = 2022 { didSet { settings?.dividendStartYear = dividendStartYear; setupDividendYears(); setupGrowthYears() } }
    
    @Published var growthGoalType: GrowthGoalType = .targetReturnPercent { didSet { settings?.growthGoalType = growthGoalType } }
    @Published var growthGoalTarget: Double = 10.0 { didSet { settings?.growthGoalTarget = growthGoalTarget } }
    @Published var growthYears: [GrowthYear] = []
    
    @Published var benchmarkIndices: [BenchmarkIndex] = []
    @Published var benchmarkGoalTarget: Double = 10.0 { didSet { settings?.benchmarkGoalTarget = benchmarkGoalTarget } }
    
    @Published var transactions: [Transaction] = []
    @Published var transactionCustomColumns: [String] = ["State Tax", "Broker Tax", "Other Taxes"] { didSet { settings?.transactionCustomColumns = transactionCustomColumns } }
    @Published var transactionGoalTarget: Double = 50 { didSet { settings?.transactionGoalTarget = transactionGoalTarget } }
    
    @Published var watchlistItems: [WatchlistItem] = []
    @Published var calendarEvents: [CalendarEvent] = []
    @Published var fundamentalCriteria: [FundamentalCriterion] = []
    
    @Published var wealthGoalTarget: Double = 50000.0 { didSet { settings?.wealthGoalTarget = wealthGoalTarget } }
    @Published var manualWealthAssets: [WealthAsset] = []
    @Published var manualWealthLiabilities: [WealthLiability] = []
    @Published var safeWithdrawalRate: Double = 4.0 { didSet { settings?.safeWithdrawalRate = safeWithdrawalRate } }
    
    @Published var isLoading = false
    @Published var sortOrder = [KeyPathComparator(\Position.ticker)] { didSet { positions.sort(using: sortOrder) } }
    @Published var expectedMonthlyDividendSeries: [ExpectedMonthlyDividendSeries] = []
    @Published var stockYieldsData: [StockYieldDataItem] = []
    
    @Published var newLiabilityName: String = ""
    @Published var newLiabilityAmount: Double? = nil
    
    private let yahooService = YahooFinanceService()
    
    // ==========================================
    // INITIALISATION SWIFTDATA
    // ==========================================
    
    init() {}
    
    func initializeData(context: ModelContext) {
        guard modelContext == nil else { return } // Évite la double initialisation
        self.modelContext = context
        
        // 1. CHARGEMENT DES SETTINGS
        let settingsFetch = FetchDescriptor<AppSettings>()
        if let existingSettings = try? context.fetch(settingsFetch).first {
            self.settings = existingSettings
        } else {
            let newSettings = AppSettings()
            context.insert(newSettings)
            self.settings = newSettings
        }
        
        // 2. SYNCHRONISATION DES VARIABLES SIMPLES
        self.availableCash = settings!.availableCash
        self.manuallyInvested = settings!.manuallyInvested
        if let gType = settings!.goalType { self.currentGoalType = gType }
        if let gTarget = settings!.goalTarget { self.currentGoalTarget = gTarget }
        if let dType = settings!.dividendGoalType { self.dividendGoalType = dType }
        if let dTarget = settings!.dividendGoalTarget { self.dividendGoalTarget = dTarget }
        if let dStart = settings!.dividendStartYear { self.dividendStartYear = dStart }
        if let grType = settings!.growthGoalType { self.growthGoalType = grType }
        if let grTarget = settings!.growthGoalTarget { self.growthGoalTarget = grTarget }
        if let bTarget = settings!.benchmarkGoalTarget { self.benchmarkGoalTarget = bTarget }
        if let txCols = settings!.transactionCustomColumns { self.transactionCustomColumns = txCols }
        if let txTarget = settings!.transactionGoalTarget { self.transactionGoalTarget = txTarget }
        if let wTarget = settings!.wealthGoalTarget { self.wealthGoalTarget = wTarget }
        if let swr = settings!.safeWithdrawalRate { self.safeWithdrawalRate = swr }
        
        // 3. CHARGEMENT DE TOUS LES TABLEAUX DEPUIS LA BASE DE DONNÉES
        self.positions = (try? context.fetch(FetchDescriptor<Position>())) ?? []
        self.positions.sort(using: sortOrder)
        
        self.dividendYears = (try? context.fetch(FetchDescriptor<DividendYear>())) ?? []
        self.growthYears = (try? context.fetch(FetchDescriptor<GrowthYear>())) ?? []
        self.benchmarkIndices = (try? context.fetch(FetchDescriptor<BenchmarkIndex>())) ?? []
        self.transactions = (try? context.fetch(FetchDescriptor<Transaction>())) ?? []
        self.watchlistItems = (try? context.fetch(FetchDescriptor<WatchlistItem>())) ?? []
        self.calendarEvents = (try? context.fetch(FetchDescriptor<CalendarEvent>())) ?? []
        self.fundamentalCriteria = (try? context.fetch(FetchDescriptor<FundamentalCriterion>())) ?? []
        self.manualWealthAssets = (try? context.fetch(FetchDescriptor<WealthAsset>())) ?? []
        self.manualWealthLiabilities = (try? context.fetch(FetchDescriptor<WealthLiability>())) ?? []
        
        // 4. SETUP FINAL
        setupDividendYears()
        setupGrowthYears()
        updateDividendsViewData()
        Task { await refreshPrices() }
    }
    
    // ==========================================
    // GESTION DES AJOUTS / SUPPRESSIONS (CRUD)
    // ==========================================
    
    // --- POSITIONS ---
    func addPosition(ticker: String, quantity: Double, pru: Double, dividend: Double, dividendGrowth5Y: Double, country: String, sector: String, marketCap: String, purchaseDate: Date) {
        let newPos = Position(ticker: ticker.uppercased(), quantity: quantity, averageCost: pru, currentPrice: pru, annualDividendNet: dividend, country: country, sector: sector, marketCap: marketCap, purchaseDate: purchaseDate, dividendGrowth5Y: dividendGrowth5Y)
        modelContext?.insert(newPos)
        positions.append(newPos)
        positions.sort(using: sortOrder)
        Task { await refreshPrices() }
    }
    func updatePosition(id: UUID, quantity: Double, pru: Double, dividend: Double, dividendGrowth5Y: Double, country: String, sector: String, marketCap: String, dividendMonths: Set<Int>, purchaseDate: Date) {
        if let idx = positions.firstIndex(where: { $0.id == id }) {
            positions[idx].quantity = quantity; positions[idx].averageCost = pru; positions[idx].annualDividendNet = dividend; positions[idx].country = country; positions[idx].sector = sector; positions[idx].marketCap = marketCap; positions[idx].dividendMonths = dividendMonths; positions[idx].purchaseDate = purchaseDate;
            positions.sort(using: sortOrder)
            objectWillChange.send() // Force UI Update
        }
    }
    func deletePosition(id: UUID) {
        if let pos = positions.first(where: { $0.id == id }) {
            modelContext?.delete(pos)
            positions.removeAll { $0.id == id }
        }
    }
    
    func updateRevenueExposures(for positionId: UUID, exposures: [RevenueSegment]) {
        if let idx = positions.firstIndex(where: { $0.id == positionId }) {
            positions[idx].revenueExposures = exposures
            objectWillChange.send()
        }
    }
    
    func updateFundamentalValue(for positionId: UUID, criterionId: UUID, value: Double) {
        if let idx = positions.firstIndex(where: { $0.id == positionId }) {
            if positions[idx].fundamentalValues == nil { positions[idx].fundamentalValues = [:] }
            positions[idx].fundamentalValues?[criterionId.uuidString] = value
            objectWillChange.send()
        }
    }
    
    // --- TRANSACTIONS ---
    func addTransaction(_ transaction: Transaction) {
        modelContext?.insert(transaction)
        transactions.append(transaction)
    }
    func deleteTransaction(id: UUID) {
        if let tx = transactions.first(where: { $0.id == id }) {
            modelContext?.delete(tx)
            transactions.removeAll { $0.id == id }
        }
    }
    
    // --- WEALTH & LIABILITIES ---
    func addNewLiability() {
        guard !newLiabilityName.isEmpty, let amount = newLiabilityAmount else { return }
        let liability = WealthLiability(name: newLiabilityName, amount: amount)
        modelContext?.insert(liability)
        manualWealthLiabilities.append(liability)
        newLiabilityName = ""
        newLiabilityAmount = nil
    }
    func deleteLiability(id: UUID) {
        if let liab = manualWealthLiabilities.first(where: { $0.id == id }) {
            modelContext?.delete(liab)
            manualWealthLiabilities.removeAll { $0.id == id }
        }
    }
    func addWealthAsset(_ asset: WealthAsset) {
        modelContext?.insert(asset)
        manualWealthAssets.append(asset)
    }
    func deleteWealthAsset(id: UUID) {
        if let asset = manualWealthAssets.first(where: { $0.id == id }) {
            modelContext?.delete(asset)
            manualWealthAssets.removeAll { $0.id == id }
        }
    }
    
    // --- BENCHMARK ---
    func addBenchmarkIndex(_ index: BenchmarkIndex) {
        modelContext?.insert(index)
        benchmarkIndices.append(index)
    }
    func deleteBenchmarkIndex(id: UUID) {
        if let idx = benchmarkIndices.first(where: { $0.id == id }) {
            modelContext?.delete(idx)
            benchmarkIndices.removeAll { $0.id == id }
        }
    }

    // ==========================================
    // SETUP ET CALCULS
    // ==========================================
    
    func setupDividendYears() {
        let currentYear = Calendar.current.component(.year, from: Date())
        let endYear = currentYear + 30
        var newYears: [DividendYear] = []
        for y in dividendStartYear...endYear {
            if let existing = dividendYears.first(where: { $0.year == y }) {
                newYears.append(existing)
            } else {
                let ny = DividendYear(year: y)
                modelContext?.insert(ny)
                newYears.append(ny)
            }
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
                let gy = GrowthYear(year: y, startWallet: 0, invested: 0, endWallet: 0, totalInvest: 0)
                modelContext?.insert(gy)
                newYears.append(gy)
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
        positions.sort(using: sortOrder); updateDividendsViewData(); isLoading = false
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
    
    // === PROPRIÉTÉS CALCULÉES ===
    
    var allWealthAssets: [WealthAsset] {
        let stocksAsset = WealthAsset(name: "Brokerage Account", invested: manuallyInvested, current: currentTotalCapital, isAutoFilled: true)
        return [stocksAsset] + manualWealthAssets
    }
    
    var totalAssets: Double { allWealthAssets.reduce(0) { $0 + $1.current } }
    var totalWealthInvested: Double { allWealthAssets.reduce(0) { $0 + $1.invested } }
    var totalWealthVariationEUR: Double { totalAssets - totalWealthInvested }
    var totalWealthVariationPercent: Double { totalWealthInvested > 0 ? (totalWealthVariationEUR / totalWealthInvested) : 0 }
    var wealthStockWeight: Double { totalAssets > 0 ? (currentTotalCapital / totalAssets) : 0 }
    var bestWealthAsset: String { allWealthAssets.max(by: { $0.variationPercent < $1.variationPercent })?.name ?? "-" }
    
    var totalLiabilities: Double { manualWealthLiabilities.reduce(0) { $0 + $1.amount } }
    var trueNetWorth: Double { totalAssets - totalLiabilities }
    var debtToAssetRatio: Double { totalAssets > 0 ? (totalLiabilities / totalAssets) : 0 }
    var wealthGoalProgress: Double { wealthGoalTarget > 0 ? (trueNetWorth / wealthGoalTarget) : 0 }
    var fireAnnualIncome: Double { trueNetWorth * (safeWithdrawalRate / 100.0) }
    var fireMonthlyIncome: Double { fireAnnualIncome / 12.0 }
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
        let invested = manuallyInvested
        let pvLatente = totalValue - manuallyInvested
        var items: [ValueSourceItem] = []
        items.append(ValueSourceItem(category: "Total Invested", value: invested))
        if pvLatente > 0 { items.append(ValueSourceItem(category: "Unrealized P/L", value: pvLatente)) }
        return items
    }
    
    var capitalStatusData: [ChartDataItem] {
        let inProfit = positions.filter { $0.roiValue >= 0 }.reduce(0) { $0 + $1.currentValueEUR }
        let underwater = positions.filter { $0.roiValue < 0 }.reduce(0) { $0 + $1.currentValueEUR }
        var items: [ChartDataItem] = []
        if inProfit > 0 { items.append(ChartDataItem(name: "In-Profit", value: inProfit)) }
        if underwater > 0 { items.append(ChartDataItem(name: "Underwater", value: underwater)) }
        return items
    }
}
