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
    var positions: [Position]; var availableCash: Double; var manuallyInvested: Double;
    var goalType: GoalType?; var goalTarget: Double?;
    var dividendGoalType: DividendGoalType?; var dividendGoalTarget: Double?; // NOUVEAU
    var dividendYears: [DividendYear]?; var dividendStartYear: Int?
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
