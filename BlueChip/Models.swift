import Foundation
import SwiftUI
import SwiftData // <-- NOUVEAU : Importation du framework d'Apple

// MARK: - COLOR PALETTES GLOBALES
let positionColors: [Color] = [.blue, .green, .orange, .purple, .red, .teal, .yellow, .pink, .indigo, .mint, .cyan, .brown]
let geographicColors: [Color] = [.indigo, .cyan, .blue, .mint, .teal, .purple, .gray, .black]
let sectorColors: [Color] = [.orange, .red, .brown, .yellow, .pink, .purple, .green, .mint]
let marketCapColors: [Color] = [.purple, .indigo, .blue, .cyan, .teal, .gray, .black, .brown]

// =========================================================================
// MARK: - ENUMS (Supportés nativement par SwiftData car ils sont Codable)
// =========================================================================

enum GoalType: String, Codable, CaseIterable {
    case totalValue = "Total Value (€)"
    case invested = "Initial Investment (€)"
}

enum DividendGoalType: String, Codable, CaseIterable {
    case dividendsAnnual = "Annual Expected Dividends (€)"
    case portfolioYield = "Portfolio Yield Goal (%)"
}

enum CalendarEventType: String, Codable, CaseIterable {
    case earnings = "Quarterly Earnings"
    case dividend = "Dividend Payment"
    case exDividend = "Ex-Dividend Date"
    case stockSplit = "Stock Split"
    case reverseSplit = "Reverse Split"
    case freeShares = "Free Shares"
    case ipo = "IPO"
    case spinOff = "Spin-off"
    case macro = "Macro"
    case anniversary = "Anniversary"
    
    var color: Color {
        switch self {
        case .earnings: return .blue
        case .dividend: return .green
        case .exDividend: return .mint
        case .stockSplit: return .purple
        case .reverseSplit: return .red
        case .freeShares: return .yellow
        case .ipo: return .orange
        case .spinOff: return .teal
        case .macro: return .indigo
        case .anniversary: return .pink
        }
    }
}

enum TransactionType: String, Codable, CaseIterable {
    case deposit   = "Deposit"
    case withdrawal = "Withdrawal"
    case buy       = "Buy"
    case sell      = "Sell"
    case dividend  = "Dividend"
    case other     = "Other"

    var icon: String {
        switch self {
        case .deposit:    return "arrow.down.circle.fill"
        case .withdrawal: return "arrow.up.circle.fill"
        case .buy:        return "cart.fill"
        case .sell:       return "dollarsign.circle.fill"
        case .dividend:   return "banknote.fill"
        case .other:      return "ellipsis.circle.fill"
        }
    }

    var color: String {
        switch self {
        case .deposit:    return "green"
        case .withdrawal: return "red"
        case .buy:        return "blue"
        case .sell:       return "orange"
        case .dividend:   return "mint"
        case .other:      return "gray"
        }
    }
}

enum GrowthGoalType: String, Codable, CaseIterable {
    case targetReturnCurrency = "Target Return (€)"
    case targetReturnPercent = "Target Return (%)"
}

enum CriterionType: String, Codable, CaseIterable {
    case percentage = "Pourcentage (%)"
    case number = "Nombre / Ratio"
    case boolean = "Oui / Non"
    
    var displayName: String {
        switch self {
        case .percentage: return "Percentage (%)"
        case .number: return "Number / Ratio"
        case .boolean: return "Yes / No"
        }
    }
}

// Struct Codable imbriquée (SwiftData la gérera comme du JSON interne)
struct RevenueSegment: Identifiable, Codable {
    var id = UUID()
    var regionName: String
    var isUSA: Bool
    var percentage: Double
}


// =========================================================================
// MARK: - SWIFTDATA MODELS (Les tables de la base de données)
// =========================================================================

// 1. Les réglages globaux du portefeuille (Cash, Objectifs, etc.)
@Model final class AppSettings {
    var availableCash: Double
    var manuallyInvested: Double
    
    var goalType: GoalType?
    var goalTarget: Double?
    
    var dividendGoalType: DividendGoalType?
    var dividendGoalTarget: Double?
    var dividendStartYear: Int?
    
    var growthGoalType: GrowthGoalType?
    var growthGoalTarget: Double?
    
    var benchmarkGoalTarget: Double?
    var transactionGoalTarget: Double?
    
    var transactionCustomColumns: [String]?
    
    var wealthGoalTarget: Double?
    var safeWithdrawalRate: Double?
    
    init(availableCash: Double = 0, manuallyInvested: Double = 0) {
        self.availableCash = availableCash
        self.manuallyInvested = manuallyInvested
    }
}

@Model final class Position: Identifiable {
    @Attribute(.unique) var id: UUID
    var ticker: String
    var quantity: Double
    var averageCost: Double
    var currentPrice: Double
    var currency: String
    var usdToEurRate: Double
    var annualDividendNet: Double
    var country: String
    var sector: String
    var marketCap: String
    var dividendMonths: Set<Int>
    var purchaseDate: Date
    var dividendGrowth5Y: Double
    var revenueExposures: [RevenueSegment]?
    
    var fundamentalValues: [String: Double]?
    
    var targetPrice: Double?
    var guruFocusPrice: Double?
    var tipRanksPrice: Double?
    var currentPE: Double?
    var forwardPE: Double?
    var historicalPE10Y: Double?
    var peg: Double?
    var pFcf: Double?
    
    var companyName: String = ""
    var logoData: Data? = nil
    var logoScale: Double = 1.0
    
    init(id: UUID = UUID(), ticker: String, quantity: Double, averageCost: Double, currentPrice: Double, currency: String = "EUR", usdToEurRate: Double = 1.0, annualDividendNet: Double = 0.0, country: String = "", sector: String = "", marketCap: String = "", dividendMonths: Set<Int> = [], purchaseDate: Date = Date(), dividendGrowth5Y: Double, revenueExposures: [RevenueSegment]? = nil, fundamentalValues: [String: Double]? = nil) {
        self.id = id; self.ticker = ticker; self.quantity = quantity; self.averageCost = averageCost; self.currentPrice = currentPrice; self.currency = currency; self.usdToEurRate = usdToEurRate; self.annualDividendNet = annualDividendNet; self.country = country; self.sector = sector; self.marketCap = marketCap; self.dividendMonths = dividendMonths; self.purchaseDate = purchaseDate; self.dividendGrowth5Y = dividendGrowth5Y; self.revenueExposures = revenueExposures; self.fundamentalValues = fundamentalValues;
    }
    
    // Les propriétés calculées sont ignorées par la base de données (ce qui est parfait)
    @Transient var investedAmountEUR: Double { quantity * averageCost * (currency == "USD" ? usdToEurRate : 1.0) }
    @Transient var currentValueEUR: Double { quantity * currentPrice * (currency == "USD" ? usdToEurRate : 1.0) }
    @Transient var totalDividendEUR: Double { quantity * annualDividendNet * (currency == "USD" ? usdToEurRate : 1.0) }
    @Transient var roiValue: Double { currentValueEUR - investedAmountEUR }
    @Transient var roiPercent: Double { investedAmountEUR > 0 ? roiValue / investedAmountEUR : 0 }
    @Transient var daysHeld: Int { max(1, Calendar.current.dateComponents([.day], from: purchaseDate, to: Date()).day ?? 1) }
    @Transient var dailyROIValue: Double { roiValue / Double(daysHeld) }
    @Transient var stockYieldEUR: Double { (quantity > 0 && currentPrice > 0) ? (totalDividendEUR / currentValueEUR) : 0 }
}

@Model final class DividendYear: Identifiable {
    @Attribute(.unique) var id: UUID
    var year: Int
    var jan: Double; var feb: Double; var mar: Double; var apr: Double
    var may: Double; var jun: Double; var jul: Double; var aug: Double
    var sep: Double; var oct: Double; var nov: Double; var dec: Double
    
    init(id: UUID = UUID(), year: Int, jan: Double = 0, feb: Double = 0, mar: Double = 0, apr: Double = 0, may: Double = 0, jun: Double = 0, jul: Double = 0, aug: Double = 0, sep: Double = 0, oct: Double = 0, nov: Double = 0, dec: Double = 0) {
        self.id = id; self.year = year
        self.jan = jan; self.feb = feb; self.mar = mar; self.apr = apr
        self.may = may; self.jun = jun; self.jul = jul; self.aug = aug
        self.sep = sep; self.oct = oct; self.nov = nov; self.dec = dec
    }
    
    @Transient var total: Double { jan + feb + mar + apr + may + jun + jul + aug + sep + oct + nov + dec }
}

@Model final class CalendarEvent: Identifiable {
    @Attribute(.unique) var id: UUID
    var date: Date
    var type: CalendarEventType
    var ticker: String
    var note: String
    
    init(id: UUID = UUID(), date: Date, type: CalendarEventType, ticker: String, note: String) {
        self.id = id; self.date = date; self.type = type; self.ticker = ticker; self.note = note
    }
}

@Model final class BenchmarkIndex: Identifiable {
    @Attribute(.unique) var id: UUID
    var name: String
    var returns: [Int: Double]

    init(id: UUID = UUID(), name: String, returns: [Int: Double]) {
        self.id = id; self.name = name; self.returns = returns
    }

    func value10k(upToYear year: Int, startYear: Int) -> Double {
        var value = 10000.0
        for y in startYear...year { let ret = returns[y] ?? 0; value *= (1 + ret / 100.0) }
        return value
    }

    func averageReturn(years: [Int]) -> Double {
        let validYears = years.compactMap { returns[$0] }
        guard !validYears.isEmpty else { return 0 }
        return validYears.reduce(0, +) / Double(validYears.count)
    }
}

@Model final class Transaction: Identifiable {
    @Attribute(.unique) var id: UUID
    var date: Date
    var type: TransactionType
    var ticker: String
    var quantity: Double
    var amountEUR: Double
    var note: String
    var customFields: [String: Double]

    init(id: UUID = UUID(), date: Date = Date(), type: TransactionType = .buy,
         ticker: String = "", quantity: Double = 0, amountEUR: Double = 0,
         note: String = "", customFields: [String: Double] = [:]) {
        self.id = id; self.date = date; self.type = type; self.ticker = ticker
        self.quantity = quantity; self.amountEUR = amountEUR; self.note = note
        self.customFields = customFields
    }
}

@Model final class GrowthYear: Identifiable {
    @Attribute(.unique) var id: UUID
    var year: Int
    var startWallet: Double
    var invested: Double
    var endWallet: Double
    var totalInvest: Double
    
    init(id: UUID = UUID(), year: Int, startWallet: Double, invested: Double, endWallet: Double, totalInvest: Double) {
        self.id = id; self.year = year; self.startWallet = startWallet; self.invested = invested; self.endWallet = endWallet; self.totalInvest = totalInvest
    }
    
    @Transient var returnAmount: Double { endWallet - startWallet - invested }
    @Transient var returnPercent: Double {
        let base = startWallet + invested
        guard base > 0 else { return 0 }
        return returnAmount / base
    }
}

@Model final class FundamentalCriterion: Identifiable {
    @Attribute(.unique) var id: UUID
    var name: String
    var section: String
    var weight: Double
    var type: CriterionType
    var isHigherBetter: Bool
    var premiumThreshold: Double
    var standardThreshold: Double
    
    init(id: UUID = UUID(), name: String, section: String, weight: Double, type: CriterionType, isHigherBetter: Bool, premiumThreshold: Double, standardThreshold: Double) {
        self.id = id; self.name = name; self.section = section; self.weight = weight; self.type = type; self.isHigherBetter = isHigherBetter; self.premiumThreshold = premiumThreshold; self.standardThreshold = standardThreshold
    }
}

@Model final class WealthAsset: Identifiable {
    @Attribute(.unique) var id: UUID
    var name: String
    var invested: Double
    var current: Double
    var isAutoFilled: Bool
    
    init(id: UUID = UUID(), name: String, invested: Double, current: Double, isAutoFilled: Bool) {
        self.id = id; self.name = name; self.invested = invested; self.current = current; self.isAutoFilled = isAutoFilled
    }
    
    @Transient var variationEUR: Double { current - invested }
    @Transient var variationPercent: Double { invested > 0 ? (variationEUR / invested) : 0 }
}

@Model final class WealthLiability: Identifiable {
    @Attribute(.unique) var id: UUID
    var name: String
    var amount: Double
    
    init(id: UUID = UUID(), name: String, amount: Double) {
        self.id = id; self.name = name; self.amount = amount
    }
}

// =========================================================================
// MARK: - UI HELPER STRUCTS (Éphémères, restent des struct)
// =========================================================================

struct ExpectedMonthlyDividendSeries: Identifiable { let id = UUID(); let month: Int; let monthName: String; let type: String; let ticker: String; let amount: Double }
struct StockYieldDataItem: Identifiable { let id = UUID(); let ticker: String; let yield: Double }
struct ChartDataItem: Identifiable { let id = UUID(); let name: String; let value: Double }
struct PriceCompareItem: Identifiable { let id = UUID(); let ticker: String; let category: String; let value: Double }
struct ScatterItem: Identifiable { let id = UUID(); let ticker: String; let weight: Double; let roi: Double }
struct ValueSourceItem: Identifiable { let id = UUID(); let category: String; let value: Double }
struct TreemapNode: Identifiable { let id = UUID(); let position: Position; let rect: CGRect } // Ne sera pas persisté

// =========================================================================
// MARK: - LEGACY JSON MIGRATION MODELS
// (Ne sert QUE pour aspirer ton vieux fichier JSON à l'étape 5)
// =========================================================================

struct LegacyPortfolioSaveData: Codable {
    var positions: [LegacyPosition]?
    var availableCash: Double?
    var manuallyInvested: Double?
    var goalType: GoalType?
    var goalTarget: Double?
    var dividendGoalType: DividendGoalType?
    var dividendGoalTarget: Double?
    var dividendYears: [LegacyDividendYear]?
    var dividendStartYear: Int?
    var growthGoalType: GrowthGoalType?
    var growthGoalTarget: Double?
    var growthYears: [LegacyGrowthYear]?
    var benchmarkIndices: [LegacyBenchmarkIndex]?
    var benchmarkGoalTarget: Double?
    var transactions: [LegacyTransaction]?
    var transactionCustomColumns: [String]?
    var transactionGoalTarget: Double?
    var calendarEvents: [LegacyCalendarEvent]?
    var fundamentalCriteria: [LegacyFundamentalCriterion]?
    var wealthGoalTarget: Double?
    var manualWealthAssets: [LegacyWealthAsset]?
    var manualWealthLiabilities: [LegacyWealthLiability]?
    var safeWithdrawalRate: Double?
    var watchlistItems: [LegacyWatchlistItem]?
}

struct LegacyPosition: Codable { var id: UUID; let ticker: String; var quantity: Double; var averageCost: Double; var currentPrice: Double; var currency: String; var usdToEurRate: Double; var annualDividendNet: Double; var country: String; var sector: String; var marketCap: String; var dividendMonths: Set<Int>; var purchaseDate: Date; var dividendGrowth5Y: Double; var revenueExposures: [RevenueSegment]?; var fundamentalValues: [String: Double]?; var targetPrice: Double?; var guruFocusPrice: Double?; var tipRanksPrice: Double?; var currentPE: Double?; var forwardPE: Double?; var historicalPE10Y: Double?; var peg: Double?; var pFcf: Double? }
struct LegacyDividendYear: Codable { var id: UUID; var year: Int; var jan: Double; var feb: Double; var mar: Double; var apr: Double; var may: Double; var jun: Double; var jul: Double; var aug: Double; var sep: Double; var oct: Double; var nov: Double; var dec: Double }
struct LegacyCalendarEvent: Codable { var id: UUID; var date: Date; var type: CalendarEventType; var ticker: String; var note: String }
struct LegacyBenchmarkIndex: Codable { var id: UUID; var name: String; var returns: [Int: Double] }
struct LegacyTransaction: Codable { var id: UUID; var date: Date; var type: TransactionType; var ticker: String; var quantity: Double; var amountEUR: Double; var note: String; var customFields: [String: Double] }
struct LegacyGrowthYear: Codable { var id: UUID; var year: Int; var startWallet: Double; var invested: Double; var endWallet: Double; var totalInvest: Double }
struct LegacyFundamentalCriterion: Codable { var id: UUID; var name: String; var section: String; var weight: Double; var type: CriterionType; var isHigherBetter: Bool; var premiumThreshold: Double; var standardThreshold: Double }
struct LegacyWealthAsset: Codable { var id: UUID; var name: String; var invested: Double; var current: Double; var isAutoFilled: Bool }
struct LegacyWealthLiability: Codable { var id: UUID; var name: String; var amount: Double }
struct LegacyWatchlistItem: Codable { var id: UUID; var ticker: String; var orderIndex: Int }
