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
    @Published var dividendStartYear: Int = Calendar.current.component(.year, from: Date()) { didSet { settings?.dividendStartYear = dividendStartYear; setupDividendYears(); setupGrowthYears() } }

    
    @Published var growthGoalType: GrowthGoalType = .targetReturnPercent { didSet { settings?.growthGoalType = growthGoalType } }
    @Published var growthGoalTarget: Double = 10.0 { didSet { settings?.growthGoalTarget = growthGoalTarget } }
    @Published var growthYears: [GrowthYear] = []
    
    @Published var benchmarkIndices: [BenchmarkIndex] = []
    @Published var benchmarkGoalType: BenchmarkGoalType = .averageAlpha { didSet { settings?.benchmarkGoalType = benchmarkGoalType } }
    @Published var benchmarkGoalTarget: Double = 2.5 { didSet { settings?.benchmarkGoalTarget = benchmarkGoalTarget } }
    
    @Published var transactions: [Transaction] = []
    @Published var transactionCustomColumns: [String] = ["State Tax", "Broker Tax", "Other Taxes"] { didSet { settings?.transactionCustomColumns = transactionCustomColumns } }

    @Published var transactionGoalType: TransactionGoalType = .count { didSet { settings?.transactionGoalType = transactionGoalType } }
    @Published var transactionGoalTarget: Double = 50 { didSet { settings?.transactionGoalTarget = transactionGoalTarget } }
    
    @Published var watchlistItems: [WatchlistItem] = []
    @Published var calendarEvents: [CalendarEvent] = []
    @Published var fundamentalCriteria: [FundamentalCriterion] = []
    
    @Published var wealthGoalType: WealthGoalType = .netWorth { didSet { settings?.wealthGoalType = wealthGoalType } } // <-- NOUVEAU
    @Published var wealthGoalTarget: Double = 100000 { didSet { settings?.wealthGoalTarget = wealthGoalTarget } }
    @Published var manualWealthAssets: [WealthAsset] = []
    @Published var manualWealthLiabilities: [WealthLiability] = []
    @Published var safeWithdrawalRate: Double = 4.0 { didSet { settings?.safeWithdrawalRate = safeWithdrawalRate } }
    
    @Published var isLoading = false
    @Published var sortOrder = [KeyPathComparator(\Position.ticker)] { didSet { positions.sort(using: sortOrder) } }
    @Published var expectedMonthlyDividendSeries: [ExpectedMonthlyDividendSeries] = []
    @Published var stockYieldsData: [StockYieldDataItem] = []
    
    @Published var newLiabilityName: String = ""
    @Published var newLiabilityAmount: Double? = nil
    
    @Published var showSettings: Bool = false
    
    @Published var dividendTaxRate: Double = 15.0 { didSet { settings?.dividendTaxRate = dividendTaxRate; updateDividendsViewData() } }
    @Published var userTimeZoneIdentifier: String = TimeZone.current.identifier { didSet { settings?.userTimeZoneIdentifier = userTimeZoneIdentifier } }
    
    private let yahooService = YahooFinanceService()
    
    // ==========================================
    // INITIALISATION SWIFTDATA
    // ==========================================
    
    init() {}
    
    // MÉTHODE POUR LA BARRE DES MENUS
    func fetchData(context: ModelContext) {
        do {
            let positionDescriptor = FetchDescriptor<Position>()
            self.positions = try context.fetch(positionDescriptor)
            
            let eventDescriptor = FetchDescriptor<CalendarEvent>()
            self.calendarEvents = try context.fetch(eventDescriptor)
            
            // NOUVEAU : On fetch la Watchlist !
            let watchlistDescriptor = FetchDescriptor<WatchlistItem>()
            self.watchlistItems = try context.fetch(watchlistDescriptor)
            
            let settingsFetch = FetchDescriptor<AppSettings>()
            if let existingSettings = try? context.fetch(settingsFetch).first {
                self.settings = existingSettings
                if let tax = existingSettings.dividendTaxRate { self.dividendTaxRate = tax }
                self.availableCash = existingSettings.availableCash
                
                // NOUVEAU : On fetch l'investissement manuel pour le calcul correct du ROI
                self.manuallyInvested = existingSettings.manuallyInvested
            }
        } catch {
            print("Erreur de chargement des données dans le ViewModel (Menu Bar) : \(error)")
        }
    }
    
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
        
        // 2. CHARGEMENT DE TOUS LES TABLEAUX DEPUIS LA BASE DE DONNÉES EN PREMIER !!!
        // (Il est vital de le faire avant d'assigner les variables simples pour éviter les déclenchements didSet à vide)
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
        
        // 3. SYNCHRONISATION DES VARIABLES SIMPLES
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
        if let txType = settings!.transactionGoalType { self.transactionGoalType = txType }
        if let txTarget = settings!.transactionGoalTarget { self.transactionGoalTarget = txTarget }
        if let wType = settings!.wealthGoalType { self.wealthGoalType = wType }
        if let wTarget = settings!.wealthGoalTarget { self.wealthGoalTarget = wTarget }
        if let swr = settings!.safeWithdrawalRate { self.safeWithdrawalRate = swr }
        
        if let tax = settings!.dividendTaxRate { self.dividendTaxRate = tax }
        if let tz = settings!.userTimeZoneIdentifier { self.userTimeZoneIdentifier = tz }
        
        if let bmkType = settings!.benchmarkGoalType { self.benchmarkGoalType = bmkType }
        if let bmkTarget = settings!.benchmarkGoalTarget { self.benchmarkGoalTarget = bmkTarget }
        
        // 4. SETUP FINAL
        setupDividendYears()
        setupGrowthYears()
        updateDividendsViewData()
        Task { await refreshPrices() }
        
        refreshSpotlightIndex()
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
        refreshSpotlightIndex()
    }
    func updatePosition(id: UUID, quantity: Double, pru: Double, dividend: Double, dividendGrowth5Y: Double, country: String, sector: String, marketCap: String, dividendMonths: Set<Int>, purchaseDate: Date) {
        if let idx = positions.firstIndex(where: { $0.id == id }) {
            positions[idx].quantity = quantity; positions[idx].averageCost = pru; positions[idx].annualDividendNet = dividend; positions[idx].country = country; positions[idx].sector = sector; positions[idx].marketCap = marketCap; positions[idx].dividendMonths = dividendMonths; positions[idx].purchaseDate = purchaseDate;
            positions.sort(using: sortOrder)
            objectWillChange.send() // Force UI Update
        }
        refreshSpotlightIndex()
    }
    func deletePosition(id: UUID) {
        if let pos = positions.first(where: { $0.id == id }) {
            modelContext?.delete(pos)
            positions.removeAll { $0.id == id }
        }
        refreshSpotlightIndex()
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
        refreshSpotlightIndex()
    }
    func deleteTransaction(id: UUID) {
        if let tx = transactions.first(where: { $0.id == id }) {
            modelContext?.delete(tx)
            transactions.removeAll { $0.id == id }
        }
        refreshSpotlightIndex()
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
    // SETUP ET CALCULS (AVEC AUTO-NETTOYAGE)
    // ==========================================
    
    func setupDividendYears() {
        let currentYear = Calendar.current.component(.year, from: Date())
        let endYear = currentYear + 30
        var newYears: [DividendYear] = []
        
        for y in dividendStartYear...endYear {
            // S'il y a des doublons fantômes créés par le bug précédent, on garde celui avec tes vraies données
            let duplicates = dividendYears.filter { $0.year == y }.sorted { $0.total > $1.total }
            
            if let bestExisting = duplicates.first {
                newYears.append(bestExisting)
                // Nettoie silencieusement les autres lignes vides en base de données
                for dup in duplicates.dropFirst() { modelContext?.delete(dup) }
            } else {
                let ny = DividendYear(year: y)
                modelContext?.insert(ny)
                newYears.append(ny)
            }
        }
        
        dividendYears = newYears.sorted { $0.year < $1.year }
    }
    
    func setupGrowthYears() {
        let currentYear = Calendar.current.component(.year, from: Date())
        let endYear = currentYear + 30
        var newYears: [GrowthYear] = []
        
        for y in dividendStartYear...endYear {
            // Même logique : on récupère la ligne qui contient ton vrai capital
            let duplicates = growthYears.filter { $0.year == y }.sorted { ($0.invested + $0.endWallet) > ($1.invested + $1.endWallet) }
            
            if let bestExisting = duplicates.first {
                newYears.append(bestExisting)
                for dup in duplicates.dropFirst() { modelContext?.delete(dup) }
            } else {
                let gy = GrowthYear(year: y, startWallet: 0, invested: 0, endWallet: 0, totalInvest: 0)
                modelContext?.insert(gy)
                newYears.append(gy)
            }
        }
        
        growthYears = newYears.sorted { $0.year < $1.year }
    }
    
    func refreshPrices() async {
        isLoading = true
        let rate = await yahooService.fetchUSDEURRate()
        
        // On combine les tickers des positions ET de la watchlist
        let positionTickers = positions.map { $0.ticker }
        let watchlistTickers = watchlistItems.map { $0.ticker }
        let allTickers = Array(Set(positionTickers + watchlistTickers))
        
        for ticker in allTickers {
            if let data = await yahooService.fetchStockData(for: ticker) {
                
                // Mise à jour des positions
                for i in 0..<positions.count where positions[i].ticker == ticker {
                    positions[i].currentPrice = data.price
                    positions[i].currency = data.currency
                    positions[i].usdToEurRate = rate
                }
                
                // Mise à jour de la watchlist (en supposant que WatchlistItem a les propriétés currentPrice et currency)
                for i in 0..<watchlistItems.count where watchlistItems[i].ticker == ticker {
                    watchlistItems[i].currentPrice = data.price
                    watchlistItems[i].currency = data.currency
                }
            }
        }
        
        positions.sort(using: sortOrder)
        updateDividendsViewData()
        isLoading = false
        
        checkAlertsAndNotify()
    }
    
    func updateDividendsViewData() {
        let monthsShort = Calendar.current.shortMonthSymbols
        var newExpectedSeries: [ExpectedMonthlyDividendSeries] = []
        
        // Calcul du multiplicateur de taxe (ex: 15% de taxe -> on garde 85% soit 0.85)
        let taxMultiplier = max(0.0, 1.0 - (dividendTaxRate / 100.0))
        
        for pos in positions {
            guard pos.annualDividendNet > 0, !pos.dividendMonths.isEmpty else { continue }
            
            // 1. Calcul du dividende annuel total BRUT en Euros
            // annualDividendNet stocke le brut local par action, on le convertit en brut total €
            let rate = pos.currency == "USD" ? pos.usdToEurRate : 1.0
            let brutPerYearEUR = pos.quantity * pos.annualDividendNet * rate
            
            // 2. Calcul du dividende annuel total NET en Euros
            let netPerYearEUR = brutPerYearEUR * taxMultiplier
            
            // 3. Division par le nombre de mois de versements pour avoir le montant par mois
            let monthsCount = Double(pos.dividendMonths.count)
            let brutPerMonthEUR = brutPerYearEUR / monthsCount
            let netPerMonthEUR = netPerYearEUR / monthsCount
            
            for m in pos.dividendMonths {
                guard m >= 1 && m <= 12 else { continue }
                let monthName = monthsShort[m-1]
                newExpectedSeries.append(ExpectedMonthlyDividendSeries(month: m, monthName: monthName, type: "Net", ticker: pos.ticker, amount: netPerMonthEUR))
                newExpectedSeries.append(ExpectedMonthlyDividendSeries(month: m, monthName: monthName, type: "Gross", ticker: pos.ticker, amount: brutPerMonthEUR))
            }
        }
        self.expectedMonthlyDividendSeries = newExpectedSeries.sorted { $0.month < $1.month }
        
        // On s'assure de multiplier par 100 pour obtenir un pourcentage
        self.stockYieldsData = positions.filter { $0.currentValueEUR > 0 }
            .map { StockYieldDataItem(ticker: $0.ticker, yield: $0.stockYieldEUR * 100.0) }
            .sorted { $0.ticker < $1.ticker }
    }
    
    // === PROPRIÉTÉS CALCULÉES ===
    
    // === NOUVEAUX CALCULS GLOBAUX POUR LA PAGE GROWTH ===
    var allTimeReturnEUR: Double {
        currentTotalCapital - (manuallyInvested > 0 ? manuallyInvested : positionsInvestedSum)
    }
    
    var averageReturnPercent: Double {
        let currentYear = Calendar.current.component(.year, from: Date())
        let activeYears = growthYears.filter { yearData in
            let effectiveEnd = yearData.year == currentYear ? currentTotalCapital : yearData.endWallet
            return yearData.year <= currentYear && (yearData.startWallet > 0 || yearData.invested > 0 || effectiveEnd > 0)
        }
        guard !activeYears.isEmpty else { return 0 }
        
        let totalPct = activeYears.reduce(0.0) { sum, yearData in
            let effectiveEnd = (yearData.year == currentYear) ? currentTotalCapital : yearData.endWallet
            let base = yearData.startWallet + yearData.invested
            guard base > 0 else { return sum }
            return sum + ((effectiveEnd - base) / base)
        }
        return totalPct / Double(activeYears.count)
    }
    
    var cagr: Double {
        let currentYear = Calendar.current.component(.year, from: Date())
        let activeYearsCount = max(1, currentYear - dividendStartYear + 1)
        let totalInvested = manuallyInvested > 0 ? manuallyInvested : positionsInvestedSum
        let allTimeReturnPct = totalInvested > 0 ? (allTimeReturnEUR / totalInvested) : 0
        return pow(1.0 + max(allTimeReturnPct, -0.999), 1.0 / Double(activeYearsCount)) - 1.0
    }
    
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
    
    
    // ==========================================
    // DANGER ZONE : RÉINITIALISATION TOTALE
    // ==========================================
    func wipeAllData() {
        guard let context = modelContext else { return }
        
        // 1. Supprimer toutes les entités de SwiftData
        positions.forEach { context.delete($0) }
        dividendYears.forEach { context.delete($0) }
        growthYears.forEach { context.delete($0) }
        benchmarkIndices.forEach { context.delete($0) }
        transactions.forEach { context.delete($0) }
        watchlistItems.forEach { context.delete($0) }
        calendarEvents.forEach { context.delete($0) }
        fundamentalCriteria.forEach { context.delete($0) }
        manualWealthAssets.forEach { context.delete($0) }
        manualWealthLiabilities.forEach { context.delete($0) }
        
        // 2. Vider les tableaux locaux de l'interface
        positions.removeAll()
        dividendYears.removeAll()
        growthYears.removeAll()
        benchmarkIndices.removeAll()
        transactions.removeAll()
        watchlistItems.removeAll()
        calendarEvents.removeAll()
        fundamentalCriteria.removeAll()
        manualWealthAssets.removeAll()
        manualWealthLiabilities.removeAll()
        
        // 3. Remettre les compteurs à zéro
        availableCash = 0.0
        manuallyInvested = 0.0
        
        // 4. Recréer les années vierges et rafraîchir
        setupDividendYears()
        setupGrowthYears()
        updateDividendsViewData()
        
        objectWillChange.send()
    }
    
    
    // ==========================================
    // MARK: - NOTIFICATIONS & ALERTES RÉACTIVES
    // ==========================================

    private var notifiedAlerts: Set<String> = []

    func checkAlertsAndNotify() {
        
        // -----------------------------------------------------
        // 1. Target Prices (Opportunités d'achat / Vente)
        // -----------------------------------------------------
        for pos in positions {
            if let target = pos.targetPrice, target > 0, pos.currentPrice <= target {
                let alertId = "pos_target_\(pos.ticker)"
                if !notifiedAlerts.contains(alertId) {
                    NotificationManager.shared.sendImmediateNotification(
                        title: "🎯 Target Reached: \(pos.ticker)",
                        subtitle: "Portfolio Position",
                        body: "The price of \(pos.ticker) (\(pos.currentPrice.formatted(.currency(code: pos.currency.isEmpty ? "USD" : pos.currency)))) has hit your target of \(target.formatted())."
                    )
                    notifiedAlerts.insert(alertId)
                }
            }
        }
        
        for item in watchlistItems {
            if item.targetPrice > 0, item.currentPrice <= item.targetPrice {
                let alertId = "watch_target_\(item.ticker)"
                if !notifiedAlerts.contains(alertId) {
                    NotificationManager.shared.sendImmediateNotification(
                        title: "📉 Buying Opportunity: \(item.ticker)",
                        subtitle: "Watchlist Alert",
                        body: "\(item.ticker) dropped to \(item.currentPrice.formatted(.currency(code: item.currency.isEmpty ? "USD" : item.currency))), hitting your target of \(item.targetPrice.formatted())."
                    )
                    notifiedAlerts.insert(alertId)
                }
            }
        }
        
        // -----------------------------------------------------
        // 2. Alerte de Volatilité Journalière (> 2% ou < -2%)
        // -----------------------------------------------------
        let totalDailyROIValue = positions.reduce(0) { $0 + $1.dailyROIValue }
        let previousTotalValue = currentTotalCapital - totalDailyROIValue
        let dailyROIPercent = previousTotalValue > 0 ? (totalDailyROIValue / previousTotalValue) : 0
        
        if abs(dailyROIPercent) >= 0.02 {
            let todayString = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none)
            let volAlertId = "volatility_\(todayString)"
            
            if !notifiedAlerts.contains(volAlertId) {
                let isUp = dailyROIPercent > 0
                let sign = isUp ? "+" : ""
                let emoji = isUp ? "🚀" : "🎢"
                
                NotificationManager.shared.sendImmediateNotification(
                    title: "\(emoji) High Volatility Detected",
                    subtitle: "Daily Market Action",
                    body: "Your portfolio moved by \(sign)\(dailyROIPercent.formatted(.percent.precision(.fractionLength(2)))) (\(sign)\(totalDailyROIValue.formatted(.currency(code: "EUR")))) today."
                )
                notifiedAlerts.insert(volAlertId)
            }
        }
        
        // -----------------------------------------------------
        // 3. Goals (Vérification de tous les objectifs)
        // -----------------------------------------------------
        
        // 3. Objectif Principal (Goal)
        if currentGoalTarget > 0, currentGoalValue >= currentGoalTarget {
            let alertId = "goal_reached_\(currentGoalTarget)"
            if !notifiedAlerts.contains(alertId) {
                NotificationManager.shared.sendImmediateNotification(
                    title: "🏆 Goal Reached!",
                    subtitle: "Congratulations!",
                    body: "Your portfolio has surpassed your goal of \(currentGoalTarget.formatted(.currency(code: "EUR")))."
                )
                notifiedAlerts.insert(alertId)
            }
        }
        
        // A. GROWTH GOAL (Percent, Currency, or CAGR)
        if growthGoalTarget > 0 {
            let currentValue: Double
            let formattedGoal: String
            
            switch growthGoalType {
            case .targetReturnPercent:
                currentValue = averageReturnPercent * 100
                formattedGoal = "\(growthGoalTarget.formatted(.number.precision(.fractionLength(2))))%"
            case .targetReturnCurrency:
                let currentYear = Calendar.current.component(.year, from: Date())
                if let yearData = growthYears.first(where: { $0.year == currentYear }) {
                    let base = yearData.startWallet + yearData.invested
                    currentValue = currentTotalCapital - base
                } else {
                    currentValue = 0.0
                }
                formattedGoal = growthGoalTarget.formatted(.currency(code: "EUR"))
            case .cagr:
                currentValue = cagr * 100
                formattedGoal = "\(growthGoalTarget.formatted(.number.precision(.fractionLength(2))))%"
            }
            
            if currentValue >= growthGoalTarget {
                let alertId = "growth_goal_reached_\(growthGoalTarget)_\(growthGoalType.rawValue)"
                if !notifiedAlerts.contains(alertId) {
                    NotificationManager.shared.sendImmediateNotification(
                        title: "🚀 Growth Goal Reached!",
                        subtitle: "Composition Dashboard",
                        body: "Your portfolio has surpassed your growth goal of \(formattedGoal)."
                    )
                    notifiedAlerts.insert(alertId)
                }
            }
        }
        
        // B. DIVIDEND GOAL (Annual Income, Yield, Current Year or All-Time)
        if dividendGoalTarget > 0 {
            let goalType = dividendGoalType ?? .dividendsAnnual
            let currentValue: Double
            let formattedGoal: String
            let goalDescription: String // <-- NOUVEAU : Un texte sur mesure !
            
            switch goalType {
            case .dividendsAnnual:
                currentValue = totalDividends
                formattedGoal = dividendGoalTarget.formatted(.currency(code: "EUR"))
                goalDescription = "expected annual dividend"
            case .portfolioYield:
                currentValue = portfolioYield * 100
                formattedGoal = "\(dividendGoalTarget.formatted(.number.precision(.fractionLength(2))))%"
                goalDescription = "portfolio yield"
            case .currentYearTotal:
                let currentYear = Calendar.current.component(.year, from: Date())
                currentValue = dividendYears.first(where: { $0.year == currentYear })?.total ?? 0.0
                formattedGoal = dividendGoalTarget.formatted(.currency(code: "EUR"))
                goalDescription = "dividends received this year"
            case .allTimeTotal:
                currentValue = dividendYears.reduce(0) { $0 + $1.total }
                formattedGoal = dividendGoalTarget.formatted(.currency(code: "EUR"))
                goalDescription = "total all-time received dividends"
            }
            
            if currentValue >= dividendGoalTarget {
                let alertId = "dividend_goal_reached_\(dividendGoalTarget)_\(goalType.rawValue)"
                if !notifiedAlerts.contains(alertId) {
                    NotificationManager.shared.sendImmediateNotification(
                        title: "💸 Dividend Goal Reached!",
                        subtitle: "Passive Income Tracker",
                        // Le texte va maintenant dire : "Congratulations! You have hit your [dividends received this year] goal of [€100.00]."
                        body: "Congratulations! You have hit your \(goalDescription) goal of \(formattedGoal)."
                    )
                    notifiedAlerts.insert(alertId)
                }
            }
        }
        
        // C. TRANSACTION GOAL (Count, Invested, Sold ou Fees)
        if transactionGoalTarget > 0 {
            let currentValue: Double
            let formattedGoal: String
            let formattedCurrent: String
            
            switch transactionGoalType {
            case .count:
                currentValue = Double(transactions.count)
                formattedGoal = "\(Int(transactionGoalTarget))"
                formattedCurrent = "\(Int(currentValue)) transactions"
            case .totalInvested:
                currentValue = transactions.filter { $0.type == .buy }.reduce(0) { $0 + $1.amountEUR }
                formattedGoal = transactionGoalTarget.formatted(.currency(code: "EUR"))
                formattedCurrent = "\(currentValue.formatted(.currency(code: "EUR"))) invested"
            case .totalSold:
                currentValue = transactions.filter { $0.type == .sell }.reduce(0) { $0 + $1.amountEUR }
                formattedGoal = transactionGoalTarget.formatted(.currency(code: "EUR"))
                formattedCurrent = "\(currentValue.formatted(.currency(code: "EUR"))) sold"
            case .totalFees:
                currentValue = transactions.reduce(0) { $0 + $1.customFields.values.reduce(0, +) }
                formattedGoal = transactionGoalTarget.formatted(.currency(code: "EUR"))
                formattedCurrent = "\(currentValue.formatted(.currency(code: "EUR"))) in fees"
            }
            
            if currentValue >= transactionGoalTarget {
                let alertId = "transaction_goal_reached_\(transactionGoalTarget)_\(transactionGoalType.rawValue)"
                if !notifiedAlerts.contains(alertId) {
                    NotificationManager.shared.sendImmediateNotification(
                        title: "🧾 Transaction Goal Reached!",
                        subtitle: "Ledger History",
                        body: "You have reached \(formattedCurrent), hitting your target of \(formattedGoal)."
                    )
                    notifiedAlerts.insert(alertId)
                }
            }
        }
        
        // D. BENCHMARK GOAL (Average Alpha, Current Year Alpha, or Positive Alpha Years)
        if benchmarkGoalTarget > 0 {
            let currentYear = Calendar.current.component(.year, from: Date())
            let startYear = dividendStartYear
            let activeYears = Array(startYear...currentYear)
            
            let portfolioAvgReturn: Double = {
                var vals: [Double] = []
                for year in activeYears {
                    guard let yearData = growthYears.first(where: { $0.year == year }) else { vals.append(0); continue }
                    let isCurrentYear = year == currentYear
                    let effectiveEnd = isCurrentYear ? currentTotalCapital : yearData.endWallet
                    let base = yearData.startWallet + yearData.invested
                    vals.append(base > 0 ? ((effectiveEnd - base) / base) * 100.0 : 0)
                }
                guard !vals.isEmpty else { return 0 }
                return vals.reduce(0, +) / Double(vals.count)
            }()
            
            let bestIndex = benchmarkIndices.max { $0.averageReturn(years: activeYears) < $1.averageReturn(years: activeYears) }
            
            let currentValue: Double
            let formattedGoal: String
            let goalDescription: String
            
            switch benchmarkGoalType {
            case .averageAlpha:
                let bestAvg = bestIndex?.averageReturn(years: activeYears) ?? 0
                currentValue = portfolioAvgReturn - bestAvg
                formattedGoal = "\(benchmarkGoalTarget.formatted(.number.precision(.fractionLength(2))))%"
                goalDescription = "average alpha"
            case .currentYearAlpha:
                let portfolioCurrentYear: Double = {
                    guard let yearData = growthYears.first(where: { $0.year == currentYear }) else { return 0 }
                    let base = yearData.startWallet + yearData.invested
                    return base > 0 ? ((currentTotalCapital - base) / base) * 100.0 : 0
                }()
                let bestCurrentYear = bestIndex?.returns[currentYear] ?? 0
                currentValue = portfolioCurrentYear - bestCurrentYear
                formattedGoal = "\(benchmarkGoalTarget.formatted(.number.precision(.fractionLength(2))))%"
                goalDescription = "current year alpha"
            case .positiveAlphaYears:
                var positiveYearsCount = 0
                for year in activeYears {
                    let pReturn: Double = {
                        guard let yearData = growthYears.first(where: { $0.year == year }) else { return 0 }
                        let isCurrentYear = year == currentYear
                        let effectiveEnd = isCurrentYear ? currentTotalCapital : yearData.endWallet
                        let base = yearData.startWallet + yearData.invested
                        return base > 0 ? ((effectiveEnd - base) / base) * 100.0 : 0
                    }()
                    let iReturn = bestIndex?.returns[year] ?? 0
                    if (pReturn - iReturn) > 0 { positiveYearsCount += 1 }
                }
                currentValue = Double(positiveYearsCount)
                formattedGoal = "\(Int(benchmarkGoalTarget)) years"
                goalDescription = "positive alpha years"
            }
            
            if currentValue >= benchmarkGoalTarget {
                let alertId = "benchmark_goal_reached_\(benchmarkGoalTarget)_\(benchmarkGoalType.rawValue)"
                if !notifiedAlerts.contains(alertId) {
                    NotificationManager.shared.sendImmediateNotification(
                        title: "📈 Benchmark Goal Reached!",
                        subtitle: "Outperformance Tracker",
                        body: "Congratulations! You have hit your \(goalDescription) goal of \(formattedGoal)."
                    )
                    notifiedAlerts.insert(alertId)
                }
            }
        }
        
        // E. WEALTH GOAL (Net Worth, Total Assets, or Passive Income)
        if wealthGoalTarget > 0 {
            let currentValue: Double
            let formattedGoal: String
            let goalDescription: String
            
            switch wealthGoalType {
            case .netWorth:
                currentValue = trueNetWorth
                formattedGoal = wealthGoalTarget.formatted(.currency(code: "EUR"))
                goalDescription = "true net worth"
            case .totalAssets:
                currentValue = totalAssets
                formattedGoal = wealthGoalTarget.formatted(.currency(code: "EUR"))
                goalDescription = "total assets"
            case .passiveIncome:
                currentValue = fireMonthlyIncome
                formattedGoal = wealthGoalTarget.formatted(.currency(code: "EUR"))
                goalDescription = "monthly passive income"
            case .debtAssetsRatio:
                currentValue = debtToAssetRatio * 100 // <-- CORRECTION ICI : debtToAssetRatio
                formattedGoal = "\(wealthGoalTarget.formatted(.number.precision(.fractionLength(2))))%"
                goalDescription = "debt-to-assets ratio"
            }
            
            if currentValue >= wealthGoalTarget {
                let alertId = "wealth_goal_reached_\(wealthGoalTarget)_\(wealthGoalType.rawValue)"
                if !notifiedAlerts.contains(alertId) {
                    NotificationManager.shared.sendImmediateNotification(
                        title: "🏰 Wealth Goal Reached!",
                        subtitle: "Financial Independence",
                        body: "Congratulations! You have hit your \(goalDescription) goal of \(formattedGoal)."
                    )
                    notifiedAlerts.insert(alertId)
                }
            }
        }
        
        // -----------------------------------------------------
        // 4. Programmation des Notifications Périodiques
        // -----------------------------------------------------
        scheduleDividendOutlookNotification()
        scheduleWeeklyRecapNotification()
    }

    // MARK: - MÉTÉO DES DIVIDENDES (1er du mois à 9h00)
    private func scheduleDividendOutlookNotification() {
        let cal = Calendar.current
        let now = Date()
        
        // Cible le 1er du mois (si on est déjà le 1er mais après 9h, le système programmera automatiquement au 1er du mois SUIVANT)
        let targetMonthIndex = cal.component(.month, from: now)
        var nextMonthDate = cal.date(byAdding: .month, value: 1, to: now) ?? now
        // On calcule pour le mois prochain par défaut (sauf si on est le 1er du mois avant 9h)
        let isFirstBeforeNine = cal.component(.day, from: now) == 1 && cal.component(.hour, from: now) < 9
        let workingMonthIndex = isFirstBeforeNine ? targetMonthIndex : cal.component(.month, from: nextMonthDate)
        
        let monthName = DateFormatter().monthSymbols[workingMonthIndex - 1]
        
        var grossTotal = 0.0
        var netTotal = 0.0
        var payingTickers: [String] = []
        
        for pos in positions where pos.dividendMonths.contains(workingMonthIndex) {
            let payments = max(1.0, Double(pos.dividendMonths.count))
            let taxMultiplier = 1.0 - (dividendTaxRate / 100.0)
            
            let netPayment = pos.totalDividendEUR / payments
            let grossPayment = taxMultiplier > 0 ? (netPayment / taxMultiplier) : netPayment
            
            grossTotal += grossPayment
            netTotal += netPayment
            payingTickers.append(pos.ticker)
        }
        
        guard !payingTickers.isEmpty else { return }
        
        // Formater proprement les tickers (limite à 5 pour que ça reste lisible dans une notif)
        let displayTickers = payingTickers.prefix(5).joined(separator: ", ") + (payingTickers.count > 5 ? " and others" : "")
        
        let body = "Expected: \(grossTotal.formatted(.currency(code: "EUR"))) Gross (\(netTotal.formatted(.currency(code: "EUR"))) Net) from \(displayTickers)."
        
        NotificationManager.shared.scheduleMonthlyNotification(
            day: 1, hour: 9, minute: 0,
            title: "💸 \(monthName) Dividend Outlook",
            body: body,
            identifier: "monthly_dividend_outlook"
        )
    }

    // MARK: - BILAN HEBDOMADAIRE (Samedi à 9h00)
    private func scheduleWeeklyRecapNotification() {
        let keyCapital = "start_of_week_capital"
        let keyDate = "start_of_week_date"
        
        var startCapital = UserDefaults.standard.double(forKey: keyCapital)
        let startDate = UserDefaults.standard.object(forKey: keyDate) as? Date ?? Date.distantPast
        
        // Si la date sauvegardée date d'une autre semaine (ou plus de 6 jours), on la met à jour
        let cal = Calendar.current
        if !cal.isDate(startDate, equalTo: Date(), toGranularity: .weekOfYear) {
            startCapital = currentTotalCapital
            UserDefaults.standard.set(startCapital, forKey: keyCapital)
            UserDefaults.standard.set(Date(), forKey: keyDate)
        }
        
        let diff = currentTotalCapital - startCapital
        let pct = startCapital > 0 ? (diff / startCapital) : 0
        let sign = diff >= 0 ? "+" : ""
        
        let body = "Your portfolio closed at \(currentTotalCapital.formatted(.currency(code: "EUR"))). A performance of \(sign)\(diff.formatted(.currency(code: "EUR"))) (\(sign)\(pct.formatted(.percent.precision(.fractionLength(1))))) this week."
        
        // weekday: 7 = Samedi en Swift
        NotificationManager.shared.scheduleWeeklyNotification(
            weekday: 7, hour: 9, minute: 0,
            title: "📊 Weekly Recap",
            body: body,
            identifier: "weekly_recap"
        )
    }
    
    func refreshSpotlightIndex() {
        SpotlightManager.shared.indexPortfolio(
            positions: self.positions,
            transactions: self.transactions,
            watchlistItems: self.watchlistItems,
            calendarEvents: self.calendarEvents
        )
    }
    
}


extension PortfolioViewModel {
    // MARK: - FULL APP BACKUP (EXPORT)
    func generateFullBackup() -> Data? {
        var backup = LegacyPortfolioSaveData()
        
        // 1. App Settings & Goals
        backup.availableCash = availableCash
        backup.manuallyInvested = manuallyInvested
        backup.goalType = currentGoalType
        backup.goalTarget = currentGoalTarget
        backup.dividendGoalType = dividendGoalType
        backup.dividendGoalTarget = dividendGoalTarget
        backup.dividendStartYear = dividendStartYear
        backup.growthGoalType = growthGoalType
        backup.growthGoalTarget = growthGoalTarget
        backup.benchmarkGoalType = benchmarkGoalType
        backup.benchmarkGoalTarget = benchmarkGoalTarget
        backup.transactionGoalType = transactionGoalType
        backup.transactionGoalTarget = transactionGoalTarget
        backup.transactionCustomColumns = transactionCustomColumns
        backup.wealthGoalType = wealthGoalType
        backup.wealthGoalTarget = wealthGoalTarget
        backup.safeWithdrawalRate = safeWithdrawalRate
        
        // 2. Arrays & Data
        backup.positions = positions.map { pos in
            LegacyPosition(id: pos.id, ticker: pos.ticker, quantity: pos.quantity, averageCost: pos.averageCost, currentPrice: pos.currentPrice, currency: pos.currency, usdToEurRate: pos.usdToEurRate, annualDividendNet: pos.annualDividendNet, country: pos.country, sector: pos.sector, marketCap: pos.marketCap, dividendMonths: pos.dividendMonths, purchaseDate: pos.purchaseDate, dividendGrowth5Y: pos.dividendGrowth5Y, revenueExposures: pos.revenueExposures, fundamentalValues: pos.fundamentalValues, targetPrice: pos.targetPrice, guruFocusPrice: pos.guruFocusPrice, tipRanksPrice: pos.tipRanksPrice, currentPE: pos.currentPE, forwardPE: pos.forwardPE, historicalPE10Y: pos.historicalPE10Y, peg: pos.peg, pFcf: pos.pFcf)
        }
        backup.transactions = transactions.map { LegacyTransaction(id: $0.id, date: $0.date, type: $0.type, ticker: $0.ticker, quantity: $0.quantity, amountEUR: $0.amountEUR, note: $0.note, customFields: $0.customFields) }
        backup.dividendYears = dividendYears.map { LegacyDividendYear(id: $0.id, year: $0.year, jan: $0.jan, feb: $0.feb, mar: $0.mar, apr: $0.apr, may: $0.may, jun: $0.jun, jul: $0.jul, aug: $0.aug, sep: $0.sep, oct: $0.oct, nov: $0.nov, dec: $0.dec) }
        backup.growthYears = growthYears.map { LegacyGrowthYear(id: $0.id, year: $0.year, startWallet: $0.startWallet, invested: $0.invested, endWallet: $0.endWallet, totalInvest: $0.totalInvest) }
        backup.benchmarkIndices = benchmarkIndices.map { LegacyBenchmarkIndex(id: $0.id, name: $0.name, returns: $0.returns, referenceLink: $0.referenceLink) }
        backup.watchlistItems = watchlistItems.map {
                    LegacyWatchlistItem(id: $0.id, ticker: $0.ticker, currentPrice: $0.currentPrice, targetPrice: $0.targetPrice, currentPE: $0.currentPE, forwardPE: $0.forwardPE, historicalPE10Y: $0.historicalPE10Y, guruFocusPrice: $0.guruFocusPrice, tipRanksPrice: $0.tipRanksPrice, peg: $0.peg, currency: $0.currency, note: $0.note, fundamentalValues: $0.fundamentalValues)
                }
        backup.calendarEvents = calendarEvents.map { LegacyCalendarEvent(id: $0.id, date: $0.date, type: $0.type, ticker: $0.ticker, note: $0.note) }
        backup.fundamentalCriteria = fundamentalCriteria.map { LegacyFundamentalCriterion(id: $0.id, name: $0.name, section: $0.section, weight: $0.weight, type: $0.type, isHigherBetter: $0.isHigherBetter, premiumThreshold: $0.premiumThreshold, standardThreshold: $0.standardThreshold) }
        backup.manualWealthAssets = manualWealthAssets.map { LegacyWealthAsset(id: $0.id, name: $0.name, invested: $0.invested, current: $0.current, isAutoFilled: $0.isAutoFilled) }
        backup.manualWealthLiabilities = manualWealthLiabilities.map { LegacyWealthLiability(id: $0.id, name: $0.name, amount: $0.amount, initialAmount: $0.initialAmount) }
        
        // 3. Global AppSettings manquants
        backup.dividendTaxRate = dividendTaxRate
        backup.userTimeZoneIdentifier = userTimeZoneIdentifier
        
        // 4. Capture universelle des UserDefaults (AppStorage)
        var prefs: [String: String] = [:]
        let ud = UserDefaults.standard
        
        // Chaînes de caractères
        for key in ["appTheme", "geminiApiKey", "wl_urlGuruFocus", "wl_urlTipRanks", "wl_urlValuation"] {
            if let str = ud.string(forKey: key) { prefs[key] = str }
        }
        // Booléens
        for key in ["forcePrivacyOnStartup", "requireAuthOnStartup", "proj_enableMonthlyContrib", "proj_enableDRIP", "proj_enableInflation"] {
            prefs[key] = String(ud.bool(forKey: key))
        }
        // Doubles
        for key in ["valuation_marginOfSafety", "watchlist_marginOfSafety", "proj_timeHorizonYears", "proj_monthlyContribAmount", "proj_inflationRate"] {
            prefs[key] = String(ud.double(forKey: key))
        }
        
        backup.userPreferences = prefs
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted // Rend le fichier lisible par un humain
        return try? encoder.encode(backup)
    }

    // MARK: - FULL APP RESTORE (IMPORT)
    func restoreFullBackup(from data: Data) throws {
        // 1. Tente de décoder le fichier (si c'est corrompu, ça s'arrête ici sans rien effacer)
        let backup = try JSONDecoder().decode(LegacyPortfolioSaveData.self, from: data)
        guard let context = modelContext else { throw CocoaError(.coreDataError) }
        
        // 2. Efface les données actuelles SEULEMENT si le décodage a réussi
        wipeAllData()
        
        // 3. Restaurer les réglages
        if let v = backup.availableCash { self.availableCash = v }
        if let v = backup.manuallyInvested { self.manuallyInvested = v }
        if let v = backup.goalType { self.currentGoalType = v }
        if let v = backup.goalTarget { self.currentGoalTarget = v }
        if let v = backup.dividendGoalType { self.dividendGoalType = v }
        if let v = backup.dividendGoalTarget { self.dividendGoalTarget = v }
        if let v = backup.dividendStartYear { self.dividendStartYear = v }
        if let v = backup.growthGoalType { self.growthGoalType = v }
        if let v = backup.growthGoalTarget { self.growthGoalTarget = v }
        if let v = backup.benchmarkGoalType { self.benchmarkGoalType = v }
        if let v = backup.benchmarkGoalTarget { self.benchmarkGoalTarget = v }
        if let v = backup.transactionGoalType { self.transactionGoalType = v }
        if let v = backup.transactionGoalTarget { self.transactionGoalTarget = v }
        if let v = backup.transactionCustomColumns { self.transactionCustomColumns = v }
        if let v = backup.wealthGoalType { self.wealthGoalType = v }
        if let v = backup.wealthGoalTarget { self.wealthGoalTarget = v }
        if let v = backup.safeWithdrawalRate { self.safeWithdrawalRate = v }
        
        if let tax = backup.dividendTaxRate { self.dividendTaxRate = tax }
        if let tz = backup.userTimeZoneIdentifier { self.userTimeZoneIdentifier = tz }
        
        // Restaurer les UserDefaults (AppStorage)
        if let prefs = backup.userPreferences {
            let ud = UserDefaults.standard
            for (key, val) in prefs {
                if ["appTheme", "geminiApiKey", "wl_urlGuruFocus", "wl_urlTipRanks", "wl_urlValuation"].contains(key) {
                    ud.set(val, forKey: key)
                } else if ["forcePrivacyOnStartup", "requireAuthOnStartup", "proj_enableMonthlyContrib", "proj_enableDRIP", "proj_enableInflation"].contains(key) {
                    ud.set(val == "true", forKey: key)
                } else {
                    if let doubleVal = Double(val) { ud.set(doubleVal, forKey: key) }
                }
            }
        }
        
        // 4. Restaurer les entités complexes
        if let legPos = backup.positions {
            for lp in legPos {
                let pos = Position(id: lp.id, ticker: lp.ticker, quantity: lp.quantity, averageCost: lp.averageCost, currentPrice: lp.currentPrice, currency: lp.currency, usdToEurRate: lp.usdToEurRate, annualDividendNet: lp.annualDividendNet, country: lp.country, sector: lp.sector, marketCap: lp.marketCap, dividendMonths: lp.dividendMonths, purchaseDate: lp.purchaseDate, dividendGrowth5Y: lp.dividendGrowth5Y, revenueExposures: lp.revenueExposures, fundamentalValues: lp.fundamentalValues)
                pos.targetPrice = lp.targetPrice; pos.guruFocusPrice = lp.guruFocusPrice; pos.tipRanksPrice = lp.tipRanksPrice; pos.currentPE = lp.currentPE; pos.forwardPE = lp.forwardPE; pos.historicalPE10Y = lp.historicalPE10Y; pos.peg = lp.peg; pos.pFcf = lp.pFcf
                context.insert(pos); self.positions.append(pos)
            }
        }
        
        if let legTx = backup.transactions {
            for ltx in legTx {
                let tx = Transaction(id: ltx.id, date: ltx.date, type: ltx.type, ticker: ltx.ticker, quantity: ltx.quantity, amountEUR: ltx.amountEUR, note: ltx.note, customFields: ltx.customFields)
                context.insert(tx); self.transactions.append(tx)
            }
        }
        
        // Supprime les années par défaut créées par wipeAllData()
        self.dividendYears.forEach { context.delete($0) }; self.dividendYears.removeAll()
        self.growthYears.forEach { context.delete($0) }; self.growthYears.removeAll()
        
        if let legDy = backup.dividendYears, !legDy.isEmpty {
            for ldy in legDy {
                let dy = DividendYear(id: ldy.id, year: ldy.year, jan: ldy.jan, feb: ldy.feb, mar: ldy.mar, apr: ldy.apr, may: ldy.may, jun: ldy.jun, jul: ldy.jul, aug: ldy.aug, sep: ldy.sep, oct: ldy.oct, nov: ldy.nov, dec: ldy.dec)
                context.insert(dy); self.dividendYears.append(dy)
            }
        } else { setupDividendYears() }
        
        if let legGy = backup.growthYears, !legGy.isEmpty {
            for lgy in legGy {
                let gy = GrowthYear(id: lgy.id, year: lgy.year, startWallet: lgy.startWallet, invested: lgy.invested, endWallet: lgy.endWallet, totalInvest: lgy.totalInvest)
                context.insert(gy); self.growthYears.append(gy)
            }
        } else { setupGrowthYears() }
        
        if let legBmk = backup.benchmarkIndices {
            for lb in legBmk {
                let bmk = BenchmarkIndex(id: lb.id, name: lb.name, returns: lb.returns, referenceLink: lb.referenceLink ?? "")
                context.insert(bmk); self.benchmarkIndices.append(bmk)
            }
        }
        if let legWl = backup.watchlistItems {
            for lw in legWl {
                let wl = WatchlistItem(id: lw.id, ticker: lw.ticker, currentPrice: lw.currentPrice, targetPrice: lw.targetPrice, currentPE: lw.currentPE, forwardPE: lw.forwardPE, historicalPE10Y: lw.historicalPE10Y, guruFocusPrice: lw.guruFocusPrice, tipRanksPrice: lw.tipRanksPrice, peg: lw.peg, currency: lw.currency, note: lw.note, fundamentalValues: lw.fundamentalValues)
                context.insert(wl)
                self.watchlistItems.append(wl)
            }
        }
        if let legCal = backup.calendarEvents {
            for lc in legCal {
                let cal = CalendarEvent(id: lc.id, date: lc.date, type: lc.type, ticker: lc.ticker, note: lc.note)
                context.insert(cal); self.calendarEvents.append(cal)
            }
        }
        if let legFund = backup.fundamentalCriteria {
            for lf in legFund {
                let crit = FundamentalCriterion(id: lf.id, name: lf.name, section: lf.section, weight: lf.weight, type: lf.type, isHigherBetter: lf.isHigherBetter, premiumThreshold: lf.premiumThreshold, standardThreshold: lf.standardThreshold)
                context.insert(crit); self.fundamentalCriteria.append(crit)
            }
        }
        if let legWA = backup.manualWealthAssets {
            for lwa in legWA {
                let wa = WealthAsset(id: lwa.id, name: lwa.name, invested: lwa.invested, current: lwa.current, isAutoFilled: lwa.isAutoFilled)
                context.insert(wa); self.manualWealthAssets.append(wa)
            }
        }
        if let legWL = backup.manualWealthLiabilities {
            for lwl in legWL {
                let wl = WealthLiability(id: lwl.id, name: lwl.name, amount: lwl.amount, initialAmount: lwl.initialAmount)
                context.insert(wl); self.manualWealthLiabilities.append(wl)
            }
        }
        
        // 5. Rafraîchissement final de l'interface
        self.positions.sort(using: self.sortOrder)
        self.dividendYears.sort { $0.year < $1.year }
        self.growthYears.sort { $0.year < $1.year }
        self.updateDividendsViewData()
        Task { await self.refreshPrices() }
        self.refreshSpotlightIndex()
    }
}
