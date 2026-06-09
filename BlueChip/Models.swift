import Foundation
import SwiftUI

// MARK: - COLOR PALETTES GLOBALES
let positionColors: [Color] = [.blue, .green, .orange, .purple, .red, .teal, .yellow, .pink, .indigo, .mint, .cyan, .brown]
let geographicColors: [Color] = [.indigo, .cyan, .blue, .mint, .teal, .purple, .gray, .black]
let sectorColors: [Color] = [.orange, .red, .brown, .yellow, .pink, .purple, .green, .mint]
let marketCapColors: [Color] = [.purple, .indigo, .blue, .cyan, .teal, .gray, .black, .brown]

// MARK: - DATA MODELS
struct Position: Identifiable, Codable {
    var id: UUID
    let ticker: String
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
    
    init(id: UUID = UUID(), ticker: String, quantity: Double, averageCost: Double, currentPrice: Double, currency: String = "EUR", usdToEurRate: Double = 1.0, annualDividendNet: Double = 0.0, country: String = "", sector: String = "", marketCap: String = "", dividendMonths: Set<Int> = [], purchaseDate: Date = Date()) {
        self.id = id; self.ticker = ticker; self.quantity = quantity; self.averageCost = averageCost; self.currentPrice = currentPrice; self.currency = currency; self.usdToEurRate = usdToEurRate; self.annualDividendNet = annualDividendNet; self.country = country; self.sector = sector; self.marketCap = marketCap; self.dividendMonths = dividendMonths; self.purchaseDate = purchaseDate
    }
    
    var investedAmountEUR: Double { quantity * averageCost * (currency == "USD" ? usdToEurRate : 1.0) }
    var currentValueEUR: Double { quantity * currentPrice * (currency == "USD" ? usdToEurRate : 1.0) }
    var totalDividendEUR: Double { quantity * annualDividendNet * (currency == "USD" ? usdToEurRate : 1.0) }
    var roiValue: Double { currentValueEUR - investedAmountEUR }
    var roiPercent: Double { investedAmountEUR > 0 ? roiValue / investedAmountEUR : 0 }
    var daysHeld: Int { max(1, Calendar.current.dateComponents([.day], from: purchaseDate, to: Date()).day ?? 1) }
    var dailyROIValue: Double { roiValue / Double(daysHeld) }
    var stockYieldEUR: Double { (quantity > 0 && currentPrice > 0) ? (totalDividendEUR / currentValueEUR) : 0 }
}

struct DividendYear: Identifiable, Codable {
    var id = UUID(); var year: Int
    var jan: Double = 0; var feb: Double = 0; var mar: Double = 0; var apr: Double = 0
    var may: Double = 0; var jun: Double = 0; var jul: Double = 0; var aug: Double = 0
    var sep: Double = 0; var oct: Double = 0; var nov: Double = 0; var dec: Double = 0
    var total: Double { jan + feb + mar + apr + may + jun + jul + aug + sep + oct + nov + dec }
}

// TYPE POUR LE GOAL GÉNÉRAL (Composition)
enum GoalType: String, Codable, CaseIterable {
    case totalValue = "Total Value (€)"
    case invested = "Initial Investment (€)"
}

// TYPE POUR LE GOAL DIVIDENDES
enum DividendGoalType: String, Codable, CaseIterable {
    case dividendsAnnual = "Annual Expected Dividends (€)"
    case portfolioYield = "Portfolio Yield Goal (%)"
}

struct PortfolioSaveData: Codable {
    var positions: [Position];
    var availableCash: Double;
    var manuallyInvested: Double;
    
    var goalType: GoalType?;
    var goalTarget: Double?;
    
    var dividendGoalType: DividendGoalType?;
    var dividendGoalTarget: Double?;
    var dividendYears: [DividendYear]?;
    var dividendStartYear: Int?
    
    var growthGoalType: GrowthGoalType?
    var growthGoalTarget: Double?
    var growthYears: [GrowthYear]?
    var benchmarkIndices: [BenchmarkIndex]?
    var benchmarkGoalTarget: Double?
    var transactions: [Transaction]?
    var transactionCustomColumns: [String]?
    var transactionGoalTarget: Double?
}

struct ExpectedMonthlyDividendSeries: Identifiable {
    let id = UUID()
    let month: Int
    let monthName: String
    let type: String
    let ticker: String
    let amount: Double
}

struct StockYieldDataItem: Identifiable {
    let id = UUID()
    let ticker: String
    let yield: Double
}

struct ChartDataItem: Identifiable { let id = UUID(); let name: String; let value: Double }
struct PriceCompareItem: Identifiable { let id = UUID(); let ticker: String; let category: String; let value: Double }
struct ScatterItem: Identifiable { let id = UUID(); let ticker: String; let weight: Double; let roi: Double }
struct ValueSourceItem: Identifiable { let id = UUID(); let category: String; let value: Double }
struct TreemapNode: Identifiable { let id = UUID(); let position: Position; let rect: CGRect }

// MARK: - BENCHMARK MODELS

struct BenchmarkIndex: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    // Clé = année (ex: 2022), valeur = performance en % (ex: -19.44)
    var returns: [Int: Double]

    // Valeur d'un investissement de 10 000€ à la fin de chaque année
    func value10k(upToYear year: Int, startYear: Int) -> Double {
        var value = 10000.0
        for y in startYear...year {
            let ret = returns[y] ?? 0
            value *= (1 + ret / 100.0)
        }
        return value
    }

    // Retour annuel moyen
    func averageReturn(years: [Int]) -> Double {
        let validYears = years.compactMap { returns[$0] }
        guard !validYears.isEmpty else { return 0 }
        return validYears.reduce(0, +) / Double(validYears.count)
    }
}

// MARK: - TRANSACTION MODELS

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

struct Transaction: Identifiable, Codable {
    var id: UUID = UUID()
    var date: Date
    var type: TransactionType
    var ticker: String          // Vide si deposit/withdrawal
    var quantity: Double        // 0 si deposit/withdrawal
    var amountEUR: Double       // Montant total en €
    var note: String
    // Colonnes custom (clé = nom de la colonne, valeur = montant en €)
    var customFields: [String: Double]

    init(id: UUID = UUID(), date: Date = Date(), type: TransactionType = .buy,
         ticker: String = "", quantity: Double = 0, amountEUR: Double = 0,
         note: String = "", customFields: [String: Double] = [:]) {
        self.id = id; self.date = date; self.type = type; self.ticker = ticker
        self.quantity = quantity; self.amountEUR = amountEUR; self.note = note
        self.customFields = customFields
    }
}

// MARK: - GROWTH MODELS

// 1. Enum pour les objectifs de croissance
enum GrowthGoalType: String, Codable, CaseIterable {
    case targetReturnCurrency = "Target Return (€)"
    case targetReturnPercent = "Target Return (%)"
}

// 2. Structure pour le tableau de croissance
struct GrowthYear: Identifiable, Codable {
    var id = UUID()
    var year: Int
    var startWallet: Double
    var invested: Double
    var endWallet: Double
    var totalInvest: Double
    
    // Calculs automatiques
    var returnAmount: Double { endWallet - startWallet - invested }
    var returnPercent: Double {
        let base = startWallet + invested
        guard base > 0 else { return 0 }
        return returnAmount / base
    }
}
