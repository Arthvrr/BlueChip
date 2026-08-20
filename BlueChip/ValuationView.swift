import SwiftUI
import Charts

// =========================================================================
// MARK: - EXTENSION FOR VALUATION CALCULATIONS
// =========================================================================
extension Position {
    // Helpers to safely unwrap optionals
    var valTargetPrice: Double { targetPrice ?? 0.0 }
    var valGuruFocusPrice: Double { guruFocusPrice ?? 0.0 }
    var valTipRanksPrice: Double { tipRanksPrice ?? 0.0 }
    var valCurrentPE: Double { currentPE ?? 0.0 }
    var valForwardPE: Double { forwardPE ?? 0.0 }
    var valHistoricalPE10Y: Double { historicalPE10Y ?? 0.0 }
    var valPeg: Double { peg ?? 0.0 }
    var valPFcf: Double { pFcf ?? 0.0 } // NEW
    
    // Auto-calculated Yields
    var earningsYield: Double { valCurrentPE > 0 ? (1.0 / valCurrentPE) : 0.0 }
    var fcfYield: Double { valPFcf > 0 ? (1.0 / valPFcf) : 0.0 }
    
    // Fair Price calculation with Margin of Safety
    func fairPrice(marginOfSafety: Double) -> Double {
        let avgValuation = (valGuruFocusPrice + valTipRanksPrice) / 2.0
        return avgValuation * (1.0 - (marginOfSafety / 100.0))
    }
    
    // Upside Fair Price vs Current Price
    func fairPriceUpside(marginOfSafety: Double) -> Double {
        guard currentPrice > 0 else { return 0 }
        let fp = fairPrice(marginOfSafety: marginOfSafety)
        return (fp - currentPrice) / currentPrice
    }
    
    // Upside Historical 10Y PE vs Current PE
    var peUpside: Double {
        guard valCurrentPE > 0 else { return 0 }
        return (valHistoricalPE10Y - valCurrentPE) / valCurrentPE
    }
    
    // Implied Growth from PEG (Used for Scatter Plot)
    var impliedGrowth: Double {
        guard valPeg > 0 else { return 0 }
        return valCurrentPE / valPeg
    }
}

// Zoom Enum for Charts
enum ValuationChartZoomType: String, Identifiable {
    case priceComparison, peBullet, yieldBarometer, cashMatrix, pegScatter, valuationHeatmap
    var id: String { self.rawValue }
}

// =========================================================================
// MARK: - MAIN VALUATION VIEW
// =========================================================================

struct ValuationView: View {
    @ObservedObject var viewModel: PortfolioViewModel
    @Binding var privacyMode: Bool
    
    @State private var marginOfSafety: Double = 10.0
    @State private var editingPosition: Position? = nil
    @State private var chartToZoom: ValuationChartZoomType? = nil
    
    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 24) {
                
                // 1. DASHBOARD SUMMARY
                ValuationDashboardSection(
                    viewModel: viewModel,
                    marginOfSafety: marginOfSafety,
                    privacyMode: $privacyMode
                )
                
                // 2. CONTROLS (Margin of Safety Slider)
                ValuationControlsSection(marginOfSafety: $marginOfSafety)
                
                // 3. PRICE VALUATION TABLE
                ValuationPriceTableSection(
                    viewModel: viewModel,
                    marginOfSafety: marginOfSafety,
                    privacyMode: $privacyMode,
                    onEdit: { pos in editingPosition = pos }
                )
                
                // 4. MULTIPLES & YIELDS TABLE
                ValuationPETableSection(
                    viewModel: viewModel,
                    privacyMode: $privacyMode,
                    onEdit: { pos in editingPosition = pos }
                )
                
                // 5. CHARTS (6x GRAPHS)
                ValuationChartsSection(
                    viewModel: viewModel,
                    marginOfSafety: marginOfSafety,
                    privacyMode: $privacyMode,
                    chartToZoom: $chartToZoom
                )
            }
            .padding()
        }
        .background(Color(NSColor.windowBackgroundColor))
        // EDIT SHEET
        .sheet(item: $editingPosition) { pos in
            EditValuationSheet(viewModel: viewModel, position: pos)
        }
        // FULL SCREEN CHARTS
        .sheet(item: $chartToZoom) { type in
            ValuationFullScreenChartView(
                zoomType: type,
                viewModel: viewModel,
                marginOfSafety: marginOfSafety,
                privacyMode: $privacyMode
            )
        }
    }
}

// =========================================================================
// MARK: - 1. DASHBOARD SECTION (8 CARDS)
// =========================================================================

struct ValuationDashboardSection: View {
    @ObservedObject var viewModel: PortfolioViewModel
    let marginOfSafety: Double
    @Binding var privacyMode: Bool
    
    var valuatedStocks: [Position] {
        viewModel.positions.filter { $0.valGuruFocusPrice > 0 || $0.valTipRanksPrice > 0 }
    }
    
    var undervaluedCount: Int {
        valuatedStocks.filter { $0.currentPrice < $0.fairPrice(marginOfSafety: marginOfSafety) }.count
    }
    
    var avgFairPriceUpside: Double {
        guard !valuatedStocks.isEmpty else { return 0 }
        let total = valuatedStocks.reduce(0.0) { $0 + $1.fairPriceUpside(marginOfSafety: marginOfSafety) }
        return total / Double(valuatedStocks.count)
    }
    
    var avgPEUpside: Double {
        let peStocks = viewModel.positions.filter { $0.valCurrentPE > 0 && $0.valHistoricalPE10Y > 0 }
        guard !peStocks.isEmpty else { return 0 }
        let total = peStocks.reduce(0.0) { $0 + $1.peUpside }
        return total / Double(peStocks.count)
    }
    
    var avgCurrentPE: Double {
        let peStocks = viewModel.positions.filter { $0.valCurrentPE > 0 }
        guard !peStocks.isEmpty else { return 0 }
        let total = peStocks.reduce(0.0) { $0 + $1.valCurrentPE }
        return total / Double(peStocks.count)
    }
    
    var avgForwardPE: Double {
        let peStocks = viewModel.positions.filter { $0.valForwardPE > 0 }
        guard !peStocks.isEmpty else { return 0 }
        let total = peStocks.reduce(0.0) { $0 + $1.valForwardPE }
        return total / Double(peStocks.count)
    }
    
    var avgHistoricalPE: Double {
        let peStocks = viewModel.positions.filter { $0.valHistoricalPE10Y > 0 }
        guard !peStocks.isEmpty else { return 0 }
        let total = peStocks.reduce(0.0) { $0 + $1.valHistoricalPE10Y }
        return total / Double(peStocks.count)
    }
    
    var avgPEG: Double {
        let pegStocks = viewModel.positions.filter { $0.valPeg > 0 }
        guard !pegStocks.isEmpty else { return 0 }
        let total = pegStocks.reduce(0.0) { $0 + $1.valPeg }
        return total / Double(pegStocks.count)
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                DashboardCard(title: "Valuated Stocks", value: "\(valuatedStocks.count) / \(viewModel.positions.count)", titleIcon: nil, privacyMode: .constant(false))
                DashboardCard(title: "Undervalued (Fair Price)", value: "\(undervaluedCount)", titleIcon: nil, privacyMode: .constant(false))
                DashboardCard(title: "Avg. Fair Price Upside", value: avgFairPriceUpside.formatted(.percent.precision(.fractionLength(1)).sign(strategy: .always())), titleIcon: nil, privacyMode: .constant(false))
                DashboardCard(title: "Avg. Historical PE Upside", value: avgPEUpside.formatted(.percent.precision(.fractionLength(1)).sign(strategy: .always())), titleIcon: nil, privacyMode: .constant(false))
            }
            HStack(spacing: 16) {
                DashboardCard(title: "Avg. Current PE", value: avgCurrentPE > 0 ? avgCurrentPE.formatted(.number.precision(.fractionLength(1))) + "x" : "-", titleIcon: nil, privacyMode: .constant(false))
                DashboardCard(title: "Avg. Forward PE", value: avgForwardPE > 0 ? avgForwardPE.formatted(.number.precision(.fractionLength(1))) + "x" : "-", titleIcon: nil, privacyMode: .constant(false))
                DashboardCard(title: "Avg. 10Y Historical PE", value: avgHistoricalPE > 0 ? avgHistoricalPE.formatted(.number.precision(.fractionLength(1))) + "x" : "-", titleIcon: nil, privacyMode: .constant(false))
                DashboardCard(title: "Avg. Portfolio PEG", value: avgPEG > 0 ? avgPEG.formatted(.number.precision(.fractionLength(2))) : "-", titleIcon: nil, privacyMode: .constant(false))
            }
        }
    }
}

// =========================================================================
// MARK: - 2. CONTROLS SECTION
// =========================================================================

struct ValuationControlsSection: View {
    @Binding var marginOfSafety: Double
    
    var body: some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Global Margin of Safety:").fontWeight(.semibold)
                    Text("\(Int(marginOfSafety))%").font(.title3).fontWeight(.bold).foregroundColor(.orange)
                    Spacer()
                }
                Slider(value: $marginOfSafety, in: 0...50, step: 1).tint(.orange)
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// =========================================================================
// MARK: - 3. PRICE VALUATION TABLE
// =========================================================================

struct ValuationPriceTableSection: View {
    @ObservedObject var viewModel: PortfolioViewModel
    let marginOfSafety: Double
    @Binding var privacyMode: Bool
    let onEdit: (Position) -> Void
    
    var body: some View {
        let isPrivate = privacyMode
        
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Price Valuation Models").font(.title2).fontWeight(.bold).foregroundColor(.secondary)
                Spacer()
                Text("(Double-click to edit valuation metrics)").font(.caption).foregroundColor(.secondary).italic()
            }.padding(.bottom, 4)
            
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text("Ticker").fontWeight(.bold).frame(width: 70, alignment: .leading)
                    Text("Current Price").fontWeight(.bold).frame(maxWidth: .infinity, alignment: .trailing)
                    Text("Target Price").fontWeight(.bold).frame(maxWidth: .infinity, alignment: .trailing)
                    Text("GuruFocus").fontWeight(.bold).frame(maxWidth: .infinity, alignment: .trailing)
                    Text("TipRanks").fontWeight(.bold).frame(maxWidth: .infinity, alignment: .trailing)
                    Text("Fair Price").fontWeight(.bold).frame(maxWidth: .infinity, alignment: .trailing)
                    Text("Upside (Fair)").fontWeight(.bold).frame(maxWidth: .infinity, alignment: .trailing)
                }
                .font(.subheadline).foregroundColor(.secondary).padding(.horizontal, 16).padding(.vertical, 12).background(Color(NSColor.windowBackgroundColor))
                
                Divider()
                
                if viewModel.positions.isEmpty {
                    Text("No positions in portfolio.").foregroundColor(.secondary).padding(30)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(viewModel.positions) { pos in
                                let fairP = pos.fairPrice(marginOfSafety: marginOfSafety)
                                let upside = pos.fairPriceUpside(marginOfSafety: marginOfSafety)
                                let isUndervalued = pos.currentPrice < fairP && fairP > 0
                                
                                HStack(spacing: 8) {
                                    Text(pos.ticker).fontWeight(.bold).frame(width: 70, alignment: .leading)
                                    Text(pos.currentPrice.formatted(.currency(code: pos.currency).precision(.fractionLength(2)))).fontWeight(.semibold).blur(radius: isPrivate ? 6 : 0).frame(maxWidth: .infinity, alignment: .trailing)
                                    Text(pos.valTargetPrice > 0 ? pos.valTargetPrice.formatted(.currency(code: pos.currency).precision(.fractionLength(2))) : "-").foregroundColor(.purple).blur(radius: isPrivate ? 6 : 0).frame(maxWidth: .infinity, alignment: .trailing)
                                    Text(pos.valGuruFocusPrice > 0 ? pos.valGuruFocusPrice.formatted(.currency(code: pos.currency).precision(.fractionLength(2))) : "-").foregroundColor(.secondary).blur(radius: isPrivate ? 6 : 0).frame(maxWidth: .infinity, alignment: .trailing)
                                    Text(pos.valTipRanksPrice > 0 ? pos.valTipRanksPrice.formatted(.currency(code: pos.currency).precision(.fractionLength(2))) : "-").foregroundColor(.secondary).blur(radius: isPrivate ? 6 : 0).frame(maxWidth: .infinity, alignment: .trailing)
                                    Text(fairP > 0 ? fairP.formatted(.currency(code: pos.currency).precision(.fractionLength(2))) : "-").fontWeight(.bold).foregroundColor(isUndervalued ? .green : .primary).blur(radius: isPrivate ? 6 : 0).frame(maxWidth: .infinity, alignment: .trailing)
                                    
                                    if fairP > 0 {
                                        Text(upside.formatted(.percent.precision(.fractionLength(1)).sign(strategy: .always()))).fontWeight(.bold).padding(.horizontal, 6).padding(.vertical, 2).background((upside >= 0 ? Color.green : Color.red).opacity(0.15)).foregroundColor(upside >= 0 ? .green : .red).cornerRadius(4).blur(radius: isPrivate ? 6 : 0).frame(maxWidth: .infinity, alignment: .trailing)
                                    } else {
                                        Text("-").frame(maxWidth: .infinity, alignment: .trailing)
                                    }
                                }
                                .padding(.horizontal, 16).padding(.vertical, 12).contentShape(Rectangle())
                                .onTapGesture(count: 2) { onEdit(pos) }
                                Divider()
                            }
                        }
                    }
                }
            }.background(Color(NSColor.controlBackgroundColor)).cornerRadius(8).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))
        }.frame(height: 380).padding().background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// =========================================================================
// MARK: - 4. MULTIPLES & YIELDS TABLE
// =========================================================================

struct ValuationPETableSection: View {
    @ObservedObject var viewModel: PortfolioViewModel
    @Binding var privacyMode: Bool
    let onEdit: (Position) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Multiples & Yields").font(.title2).fontWeight(.bold).foregroundColor(.secondary)
                Spacer()
                Text("(Double-click to edit valuation metrics)").font(.caption).foregroundColor(.secondary).italic()
            }.padding(.bottom, 4)
            
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text("Ticker").fontWeight(.bold).frame(width: 70, alignment: .leading)
                    Text("Cur. PE").fontWeight(.bold).frame(maxWidth: .infinity, alignment: .trailing)
                    Text("Fwd PE").fontWeight(.bold).frame(maxWidth: .infinity, alignment: .trailing)
                    Text("10Y PE").fontWeight(.bold).frame(maxWidth: .infinity, alignment: .trailing)
                    Text("P/FCF").fontWeight(.bold).frame(maxWidth: .infinity, alignment: .trailing)
                    Text("PEG").fontWeight(.bold).frame(maxWidth: .infinity, alignment: .trailing)
                    Text("Earn. Yld").fontWeight(.bold).frame(maxWidth: .infinity, alignment: .trailing)
                    Text("FCF Yld").fontWeight(.bold).frame(maxWidth: .infinity, alignment: .trailing)
                }
                .font(.subheadline).foregroundColor(.secondary).padding(.horizontal, 16).padding(.vertical, 12).background(Color(NSColor.windowBackgroundColor))
                
                Divider()
                
                if viewModel.positions.isEmpty {
                    Text("No positions in portfolio.").foregroundColor(.secondary).padding(30)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(viewModel.positions) { pos in
                                HStack(spacing: 8) {
                                    Text(pos.ticker).fontWeight(.bold).frame(width: 70, alignment: .leading)
                                    Text(pos.valCurrentPE > 0 ? pos.valCurrentPE.formatted(.number.precision(.fractionLength(1))) : "-").foregroundColor((pos.valCurrentPE < pos.valHistoricalPE10Y && pos.valHistoricalPE10Y > 0) ? .green : .primary).frame(maxWidth: .infinity, alignment: .trailing)
                                    Text(pos.valForwardPE > 0 ? pos.valForwardPE.formatted(.number.precision(.fractionLength(1))) : "-").foregroundColor((pos.valForwardPE < pos.valCurrentPE && pos.valCurrentPE > 0) ? .teal : .primary).frame(maxWidth: .infinity, alignment: .trailing)
                                    Text(pos.valHistoricalPE10Y > 0 ? pos.valHistoricalPE10Y.formatted(.number.precision(.fractionLength(1))) : "-").foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .trailing)
                                    Text(pos.valPFcf > 0 ? pos.valPFcf.formatted(.number.precision(.fractionLength(1))) : "-").fontWeight(.medium).frame(maxWidth: .infinity, alignment: .trailing)
                                    
                                    if pos.valPeg > 0 {
                                        Text(pos.valPeg.formatted(.number.precision(.fractionLength(2)))).fontWeight(.semibold).foregroundColor(pos.valPeg <= 1.0 ? .green : (pos.valPeg > 2.0 ? .orange : .primary)).frame(maxWidth: .infinity, alignment: .trailing)
                                    } else {
                                        Text("-").frame(maxWidth: .infinity, alignment: .trailing)
                                    }
                                    
                                    if pos.earningsYield > 0 {
                                        Text(pos.earningsYield.formatted(.percent.precision(.fractionLength(1)))).foregroundColor(.blue).frame(maxWidth: .infinity, alignment: .trailing)
                                    } else {
                                        Text("-").frame(maxWidth: .infinity, alignment: .trailing)
                                    }
                                    
                                    if pos.fcfYield > 0 {
                                        Text(pos.fcfYield.formatted(.percent.precision(.fractionLength(1)))).fontWeight(.bold).foregroundColor(.green).frame(maxWidth: .infinity, alignment: .trailing)
                                    } else {
                                        Text("-").frame(maxWidth: .infinity, alignment: .trailing)
                                    }
                                }
                                .padding(.horizontal, 16).padding(.vertical, 12).contentShape(Rectangle())
                                .onTapGesture(count: 2) { onEdit(pos) }
                                Divider()
                            }
                        }
                    }
                }
            }.background(Color(NSColor.controlBackgroundColor)).cornerRadius(8).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))
        }.frame(height: 380).padding().background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// =========================================================================
// MARK: - 5. CHARTS SECTION (3x2 GRID)
// =========================================================================

struct ValuationChartsSection: View {
    @ObservedObject var viewModel: PortfolioViewModel
    let marginOfSafety: Double
    @Binding var privacyMode: Bool
    @Binding var chartToZoom: ValuationChartZoomType?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Valuation Visual Analytics").font(.title2).fontWeight(.bold).foregroundColor(.secondary)
            
            HStack(spacing: 20) {
                ValuationPriceComparisonChart(viewModel: viewModel, marginOfSafety: marginOfSafety, privacyMode: $privacyMode, expandedChart: $chartToZoom)
                ValuationPEBulletChart(viewModel: viewModel, privacyMode: $privacyMode, expandedChart: $chartToZoom)
            }
            HStack(spacing: 20) {
                ValuationYieldsChart(viewModel: viewModel, privacyMode: $privacyMode, expandedChart: $chartToZoom)
                ValuationCashMatrixChart(viewModel: viewModel, privacyMode: $privacyMode, expandedChart: $chartToZoom)
            }
            HStack(spacing: 20) {
                ValuationPEGScatterChart(viewModel: viewModel, privacyMode: $privacyMode, expandedChart: $chartToZoom)
                ValuationDiscountHeatmap(viewModel: viewModel, marginOfSafety: marginOfSafety, expandedChart: $chartToZoom)
            }
        }
    }
}

// --- CHART 1: PRICE COMPARISON (Current vs GF vs TipRanks) ---

struct ValPriceSeriesItem: Identifiable { let id = UUID(); let ticker: String; let type: String; let price: Double }

struct ValuationPriceComparisonChart: View {
    @ObservedObject var viewModel: PortfolioViewModel
    let marginOfSafety: Double
    @Binding var privacyMode: Bool
    var isExpanded: Bool = false
    @Binding var expandedChart: ValuationChartZoomType?
    
    @State private var hiddenSeries: Set<String> = []
    @State private var hoveredTicker: String? = nil

    var seriesData: [ValPriceSeriesItem] {
        var result: [ValPriceSeriesItem] = []
        for pos in viewModel.positions {
            result.append(ValPriceSeriesItem(ticker: pos.ticker, type: "Current Price", price: pos.currentPrice))
            if pos.valGuruFocusPrice > 0 { result.append(ValPriceSeriesItem(ticker: pos.ticker, type: "GuruFocus", price: pos.valGuruFocusPrice)) }
            if pos.valTipRanksPrice > 0 { result.append(ValPriceSeriesItem(ticker: pos.ticker, type: "TipRanks", price: pos.valTipRanksPrice)) }
        }
        return result
    }
    
    let allTypes = ["Current Price", "GuruFocus", "TipRanks"]
    func color(for type: String) -> Color {
        switch type { case "Current Price": return .blue; case "GuruFocus": return .gray; case "TipRanks": return .teal; default: return .primary }
    }

    var body: some View {
        let filteredSeries = seriesData.filter { !hiddenSeries.contains($0.type) }
        
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if !isExpanded { Text("Price vs Analyst Consensus").font(.headline).foregroundColor(.secondary) }
                Spacer()
                if !isExpanded { Button(action: { expandedChart = .priceComparison }) { Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary) }.buttonStyle(.plain) }
            }.padding(.bottom, 4)
            
            InteractiveLegendView(items: allTypes, colorMap: color, hiddenItems: $hiddenSeries).padding(.bottom, 4)
            
            if viewModel.positions.isEmpty {
                Spacer(); Text("No data").foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .center); Spacer()
            } else {
                Chart(filteredSeries) { item in
                    BarMark(x: .value("Ticker", item.ticker), y: .value("Price", item.price))
                        .foregroundStyle(color(for: item.type)).position(by: .value("Type", item.type)).cornerRadius(4)
                    
                    if let hTicker = hoveredTicker, item.ticker == hTicker {
                        RuleMark(x: .value("Ticker", hTicker)).foregroundStyle(.secondary.opacity(0.3)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                    }
                }
                .chartLegend(.hidden).chartXSelection(value: $hoveredTicker)
                .chartYAxis { AxisMarks(position: .leading) { value in AxisGridLine(); AxisTick(); if let val = value.as(Double.self) { AxisValueLabel(val.formatted(.currency(code: "EUR").notation(.compactName))) } } }
            }
            HStack { Text("Hover to compare metrics").font(.caption2).foregroundColor(.secondary); Spacer(); BlueChipWatermark() }
        }.padding().frame(minHeight: isExpanded ? 500 : 360, maxHeight: isExpanded ? .infinity : 360).background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// --- CHART 2: PE BULLET CHART (Historical Range Gauge) ---

struct ValuationPEBulletChart: View {
    @ObservedObject var viewModel: PortfolioViewModel
    @Binding var privacyMode: Bool
    var isExpanded: Bool = false
    @Binding var expandedChart: ValuationChartZoomType?
    
    @State private var hoveredTicker: String? = nil
    
    var validPositions: [Position] { viewModel.positions.filter { $0.valCurrentPE > 0 } }
    var maxPE: Double {
        let maxC = validPositions.map(\.valCurrentPE).max() ?? 0
        let maxH = validPositions.map(\.valHistoricalPE10Y).max() ?? 0
        return max(maxC, maxH) * 1.2
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if !isExpanded { Text("Historical PE Valuation Gauge").font(.headline).foregroundColor(.secondary) }
                Spacer()
                if !isExpanded { Button(action: { expandedChart = .peBullet }) { Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary) }.buttonStyle(.plain) }
            }.padding(.bottom, 4)
            
            HStack(spacing: 16) {
                HStack(spacing: 4) { Rectangle().fill(Color.blue).frame(width: 10, height: 10); Text("Current PE").font(.caption) }
                HStack(spacing: 4) { Rectangle().fill(Color.primary).frame(width: 2, height: 12); Text("10Y Avg PE").font(.caption) }
                HStack(spacing: 4) { Circle().fill(Color.teal).frame(width: 8, height: 8); Text("Forward PE").font(.caption) }
            }.padding(.bottom, 8)
            
            if validPositions.isEmpty {
                Spacer(); Text("No PE data").foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .center); Spacer()
            } else {
                Chart(validPositions) { pos in
                    // Background Gauge
                    BarMark(
                        xStart: .value("Zero", 0),
                        xEnd: .value("PE Range", maxPE),
                        y: .value("Ticker", pos.ticker)
                    )
                    .foregroundStyle(Color.gray.opacity(0.1))
                    
                    // Current PE Bar
                    BarMark(
                        xStart: .value("Zero", 0),
                        xEnd: .value("Current PE", pos.valCurrentPE),
                        y: .value("Ticker", pos.ticker),
                        height: .fixed(12)
                    )
                    .foregroundStyle(Color.blue)
                    
                    // 10Y Avg Marker
                    if pos.valHistoricalPE10Y > 0 {
                        RectangleMark(x: .value("PE", pos.valHistoricalPE10Y), y: .value("Ticker", pos.ticker), width: .fixed(3), height: .fixed(24))
                            .foregroundStyle(Color.primary)
                    }
                    
                    // Forward PE Dot
                    if pos.valForwardPE > 0 {
                        PointMark(x: .value("PE", pos.valForwardPE), y: .value("Ticker", pos.ticker))
                            .foregroundStyle(Color.teal).symbol(.circle).symbolSize(80)
                    }
                    
                    if let hTicker = hoveredTicker, pos.ticker == hTicker {
                        RuleMark(y: .value("Ticker", hTicker)).foregroundStyle(.secondary.opacity(0.2))
                            .annotation(position: .top) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(pos.ticker).font(.caption.bold())
                                    Text("Current: \(pos.valCurrentPE.formatted())x").font(.caption2).foregroundColor(.blue)
                                    Text("10Y Avg: \(pos.valHistoricalPE10Y.formatted())x").font(.caption2).foregroundColor(.primary)
                                    Text("Forward: \(pos.valForwardPE.formatted())x").font(.caption2).foregroundColor(.teal)
                                }.padding(6).background(Color(NSColor.windowBackgroundColor).opacity(0.95)).cornerRadius(6).shadow(radius: 3)
                            }
                    }
                }
                .chartLegend(.hidden).chartYSelection(value: $hoveredTicker)
            }
            
            HStack { Text("Current PE beyond the black line = Overvalued historically").font(.caption2).foregroundColor(.secondary); Spacer(); BlueChipWatermark() }
        }.padding().frame(minHeight: isExpanded ? 500 : 360, maxHeight: isExpanded ? .infinity : 360).background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// --- CHART 3: YIELD BAROMETER ---

struct YieldSeriesItem: Identifiable { let id = UUID(); let ticker: String; let type: String; let yield: Double }

struct ValuationYieldsChart: View {
    @ObservedObject var viewModel: PortfolioViewModel
    @Binding var privacyMode: Bool
    var isExpanded: Bool = false
    @Binding var expandedChart: ValuationChartZoomType?
    
    @State private var hiddenSeries: Set<String> = []
    @State private var hoveredTicker: String? = nil

    var seriesData: [YieldSeriesItem] {
        var result: [YieldSeriesItem] = []
        for pos in viewModel.positions {
            if pos.earningsYield > 0 { result.append(YieldSeriesItem(ticker: pos.ticker, type: "Earnings Yield", yield: pos.earningsYield)) }
            if pos.fcfYield > 0 { result.append(YieldSeriesItem(ticker: pos.ticker, type: "FCF Yield", yield: pos.fcfYield)) }
        }
        return result
    }
    
    let allTypes = ["Earnings Yield", "FCF Yield"]
    func color(for type: String) -> Color { type == "Earnings Yield" ? .blue : .green }

    var body: some View {
        let filteredSeries = seriesData.filter { !hiddenSeries.contains($0.type) }
        
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if !isExpanded { Text("Yield Barometer (Earnings vs Cash)").font(.headline).foregroundColor(.secondary) }
                Spacer()
                if !isExpanded { Button(action: { expandedChart = .yieldBarometer }) { Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary) }.buttonStyle(.plain) }
            }.padding(.bottom, 4)
            
            InteractiveLegendView(items: allTypes, colorMap: color, hiddenItems: $hiddenSeries).padding(.bottom, 4)
            
            if filteredSeries.isEmpty {
                Spacer(); Text("No yield data").foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .center); Spacer()
            } else {
                Chart(filteredSeries) { item in
                    BarMark(x: .value("Ticker", item.ticker), y: .value("Yield", item.yield))
                        .foregroundStyle(color(for: item.type)).position(by: .value("Type", item.type)).cornerRadius(4)
                    
                    if let hTicker = hoveredTicker, item.ticker == hTicker {
                        RuleMark(x: .value("Ticker", hTicker)).foregroundStyle(.secondary.opacity(0.3)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                    }
                }
                .chartLegend(.hidden).chartXSelection(value: $hoveredTicker)
                .chartYAxis { AxisMarks(position: .leading) { value in AxisGridLine(); AxisTick(); if let val = value.as(Double.self) { AxisValueLabel(val.formatted(.percent.precision(.fractionLength(0)))) } } }
            }
            HStack { Text("Higher Yields generally indicate better value").font(.caption2).foregroundColor(.secondary); Spacer(); BlueChipWatermark() }
        }.padding().frame(minHeight: isExpanded ? 500 : 360, maxHeight: isExpanded ? .infinity : 360).background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// --- CHART 4: CASH VS ACCOUNTING MATRIX ---

struct ValuationCashMatrixChart: View {
    @ObservedObject var viewModel: PortfolioViewModel
    @Binding var privacyMode: Bool
    var isExpanded: Bool = false
    @Binding var expandedChart: ValuationChartZoomType?
    
    @State private var hoveredYield: Double? = nil
    
    var validPositions: [Position] { viewModel.positions.filter { $0.earningsYield > 0 && $0.fcfYield > 0 } }
    
    var maxVal: Double {
        let maxE = validPositions.map(\.earningsYield).max() ?? 0.1
        let maxF = validPositions.map(\.fcfYield).max() ?? 0.1
        return max(maxE, maxF) * 1.1
    }
    
    var hoveredItem: Position? {
        guard let g = hoveredYield else { return nil }
        return validPositions.min(by: { abs($0.earningsYield - g) < abs($1.earningsYield - g) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if !isExpanded { Text("Quality Matrix (Cash vs Accounting)").font(.headline).foregroundColor(.secondary) }
                Spacer()
                if !isExpanded { Button(action: { expandedChart = .cashMatrix }) { Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary) }.buttonStyle(.plain) }
            }.padding(.bottom, 4)
            
            if validPositions.isEmpty {
                Spacer(); Text("No yield data").foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .center); Spacer()
            } else {
                Chart {
                    // Y = X Line (Cash = Earnings boundary)
                    LineMark(x: .value("E", 0), y: .value("F", 0)).foregroundStyle(Color.green).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5]))
                    LineMark(x: .value("E", maxVal), y: .value("F", maxVal)).foregroundStyle(Color.green).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5]))
                        .annotation(position: .bottom, alignment: .trailing) { Text("FCF = Earnings").font(.caption2).foregroundColor(.green) }
                    
                    // Scatter Points
                    ForEach(validPositions) { pos in
                        PointMark(
                            x: .value("Earnings Yield", pos.earningsYield),
                            y: .value("FCF Yield", pos.fcfYield)
                        )
                        .foregroundStyle(pos.fcfYield > pos.earningsYield ? Color.green : Color.orange)
                        .symbolSize(100)
                        .annotation(position: .top, alignment: .center) {
                            if hoveredItem?.id == pos.id {
                                VStack(spacing: 2) {
                                    Text(pos.ticker).font(.caption.bold())
                                    Text("FCF Yld: \(pos.fcfYield.formatted(.percent.precision(.fractionLength(1))))").font(.caption2)
                                }.padding(4).background(Color(NSColor.windowBackgroundColor).opacity(0.9)).cornerRadius(4)
                            } else if isExpanded {
                                Text(pos.ticker).font(.system(size: 8)).foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .chartXScale(domain: [0, maxVal]).chartYScale(domain: [0, maxVal])
                .chartXAxis { AxisMarks { value in AxisGridLine(); AxisTick(); if let v = value.as(Double.self) { AxisValueLabel(v.formatted(.percent.precision(.fractionLength(0)))) } } }
                .chartYAxis { AxisMarks { value in AxisGridLine(); AxisTick(); if let v = value.as(Double.self) { AxisValueLabel(v.formatted(.percent.precision(.fractionLength(0)))) } } }
                .chartXSelection(value: $hoveredYield)
            }
            
            HStack { Text("Above green line = Generates more cash than paper profit").font(.caption2).foregroundColor(.secondary); Spacer(); BlueChipWatermark() }
        }.padding().frame(minHeight: isExpanded ? 500 : 360, maxHeight: isExpanded ? .infinity : 360).background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// --- CHART 5: PEG SCATTER PLOT ---

struct ValuationPEGScatterChart: View {
    @ObservedObject var viewModel: PortfolioViewModel
    @Binding var privacyMode: Bool
    var isExpanded: Bool = false
    @Binding var expandedChart: ValuationChartZoomType?
    
    @State private var hoveredGrowth: Double? = nil
    
    var validPositions: [Position] { viewModel.positions.filter { $0.valCurrentPE > 0 && $0.valPeg > 0 } }
    
    var maxVal: Double {
        let maxPE = validPositions.map(\.valCurrentPE).max() ?? 20
        let maxG = validPositions.map(\.impliedGrowth).max() ?? 20
        return max(maxPE, maxG) * 1.1
    }
    
    var hoveredItem: Position? {
        guard let g = hoveredGrowth else { return nil }
        return validPositions.min(by: { abs($0.impliedGrowth - g) < abs($1.impliedGrowth - g) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if !isExpanded { Text("PEG Ratio Matrix (Price vs Growth)").font(.headline).foregroundColor(.secondary) }
                Spacer()
                if !isExpanded { Button(action: { expandedChart = .pegScatter }) { Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary) }.buttonStyle(.plain) }
            }.padding(.bottom, 4)
            
            if validPositions.isEmpty {
                Spacer(); Text("No PEG data").foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .center); Spacer()
            } else {
                Chart {
                    // Y = X Line (PEG = 1 boundary)
                    LineMark(x: .value("Growth", 0), y: .value("PE", 0)).foregroundStyle(Color.green).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5]))
                    LineMark(x: .value("Growth", maxVal), y: .value("PE", maxVal)).foregroundStyle(Color.green).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5]))
                        .annotation(position: .bottom, alignment: .trailing) { Text("PEG = 1.0").font(.caption2).foregroundColor(.green) }
                    
                    // Scatter Points
                    ForEach(validPositions) { pos in
                        PointMark(
                            x: .value("Expected Growth", pos.impliedGrowth),
                            y: .value("Current PE", pos.valCurrentPE)
                        )
                        .foregroundStyle(pos.valPeg <= 1.0 ? Color.green : (pos.valPeg > 2.0 ? Color.red : Color.blue))
                        .symbolSize(100)
                        .annotation(position: .top, alignment: .center) {
                            if hoveredItem?.id == pos.id {
                                VStack(spacing: 2) {
                                    Text(pos.ticker).font(.caption.bold())
                                    Text("PEG: \(pos.valPeg.formatted(.number.precision(.fractionLength(2))))").font(.caption2)
                                }.padding(4).background(Color(NSColor.windowBackgroundColor).opacity(0.9)).cornerRadius(4)
                            } else if isExpanded {
                                Text(pos.ticker).font(.system(size: 8)).foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .chartXScale(domain: [0, maxVal]).chartYScale(domain: [0, maxVal])
                .chartXAxis { AxisMarks { value in AxisGridLine(); AxisTick(); if let v = value.as(Double.self) { AxisValueLabel("\(v.formatted(.number.precision(.fractionLength(0))))%") } } }
                .chartYAxis { AxisMarks { value in AxisGridLine(); AxisTick(); if let v = value.as(Double.self) { AxisValueLabel("\(v.formatted(.number.precision(.fractionLength(0))))x") } } }
                .chartXSelection(value: $hoveredGrowth)
            }
            
            HStack { Text("Below the green line = Undervalued (PEG < 1)").font(.caption2).foregroundColor(.secondary); Spacer(); BlueChipWatermark() }
        }.padding().frame(minHeight: isExpanded ? 500 : 360, maxHeight: isExpanded ? .infinity : 360).background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// --- CHART 6: VALUATION HEATMAP ---

struct ValTreemapNode: Identifiable { let id = UUID(); let position: Position; let rect: CGRect }

struct ValHeatmapNodeView: View {
    let node: ValTreemapNode
    let marginOfSafety: Double
    @Binding var hoveredTicker: String?
    
    func color(for upside: Double) -> Color {
        if upside == 0 { return Color.gray.opacity(0.4) }
        let intensity = min(max(abs(upside) / 0.5, 0.3), 1.0) // Cap intensity
        return upside > 0 ? Color.green.opacity(intensity) : Color.red.opacity(intensity)
    }
    var isHovered: Bool { hoveredTicker == node.position.ticker }
    
    var body: some View {
        let upside = node.position.fairPriceUpside(marginOfSafety: marginOfSafety)
        
        ZStack {
            Rectangle().fill(color(for: upside)).border(Color(NSColor.windowBackgroundColor), width: 1.5)
            VStack(spacing: 4) {
                Text(node.position.ticker).font(.system(size: node.rect.width > 45 && node.rect.height > 35 ? 14 : 8, weight: .bold)).foregroundColor(.white).lineLimit(1)
                if node.rect.width > 60 && node.rect.height > 50 {
                    Text(upside.formatted(.percent.precision(.fractionLength(1)))).font(.caption).foregroundColor(.white.opacity(0.9)).lineLimit(1)
                }
            }
            if isHovered {
                VStack {
                    Text(node.position.ticker).font(.caption.bold())
                    Text("Fair Price: \(node.position.fairPrice(marginOfSafety: marginOfSafety).formatted(.currency(code: "EUR")))").font(.caption2)
                    Text("Upside: \(upside.formatted(.percent.precision(.fractionLength(1)).sign(strategy: .always())))").font(.caption2)
                }.padding(6).background(Color(NSColor.windowBackgroundColor).opacity(0.95)).cornerRadius(6).shadow(radius: 4).zIndex(10)
            }
        }.frame(width: node.rect.width, height: node.rect.height).offset(x: node.rect.minX, y: node.rect.minY).scaleEffect(isHovered ? 1.02 : 1.0).zIndex(isHovered ? 1 : 0).onContinuousHover { phase in
            switch phase { case .active(_): hoveredTicker = node.position.ticker; case .ended: hoveredTicker = nil }
        }
    }
}

struct ValuationDiscountHeatmap: View {
    @ObservedObject var viewModel: PortfolioViewModel
    let marginOfSafety: Double
    var isExpanded: Bool = false
    @Binding var expandedChart: ValuationChartZoomType?
    
    @State private var hoveredTicker: String? = nil
    
    var validPositions: [Position] { viewModel.positions.filter { $0.fairPrice(marginOfSafety: marginOfSafety) > 0 } }
    var totalValue: Double { validPositions.reduce(0) { $0 + $1.currentValueEUR } }
    var sortedPositions: [Position] { validPositions.sorted { $0.currentValueEUR > $1.currentValueEUR } }
    
    func layoutNodes(in rect: CGRect) -> [ValTreemapNode] {
        var nodes: [ValTreemapNode] = []
        var currentRect = rect
        var remainingWeight = totalValue
        
        for item in sortedPositions {
            guard remainingWeight > 0 else { continue }
            let fraction = item.currentValueEUR / remainingWeight
            if currentRect.width > currentRect.height {
                let w = currentRect.width * CGFloat(fraction)
                nodes.append(ValTreemapNode(position: item, rect: CGRect(x: currentRect.minX, y: currentRect.minY, width: w, height: currentRect.height)))
                currentRect = CGRect(x: currentRect.minX + w, y: currentRect.minY, width: currentRect.width - w, height: currentRect.height)
            } else {
                let h = currentRect.height * CGFloat(fraction)
                nodes.append(ValTreemapNode(position: item, rect: CGRect(x: currentRect.minX, y: currentRect.minY, width: currentRect.width, height: h)))
                currentRect = CGRect(x: currentRect.minX, y: currentRect.minY + h, width: currentRect.width, height: currentRect.height - h)
            }
            remainingWeight -= item.currentValueEUR
        }
        return nodes
    }
    
    var body: some View {
        VStack {
            HStack {
                if !isExpanded { Text("Portfolio Discount Heatmap").font(.headline).foregroundColor(.secondary) }
                Spacer()
                if !isExpanded { Button(action: { expandedChart = .valuationHeatmap }) { Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary) }.buttonStyle(.plain) }
            }.padding(.bottom, 8)
            
            if validPositions.isEmpty {
                Spacer(); Text("No fair price data").foregroundColor(.secondary); Spacer()
            } else {
                GeometryReader { geo in
                    ZStack(alignment: .topLeading) {
                        ForEach(layoutNodes(in: CGRect(origin: .zero, size: geo.size))) { node in
                            ValHeatmapNodeView(node: node, marginOfSafety: marginOfSafety, hoveredTicker: $hoveredTicker)
                        }
                    }
                }
            }
            HStack { Text("Size = Portfolio Weight | Color = Fair Price Upside").font(.caption2).foregroundColor(.secondary); Spacer(); BlueChipWatermark() }.padding(.top, 4)
        }.padding().frame(minHeight: isExpanded ? 500 : 360, maxHeight: isExpanded ? .infinity : 360).background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// =========================================================================
// MARK: - EDIT VALUATION SHEET
// =========================================================================

struct EditValuationSheet: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: PortfolioViewModel
    let position: Position
    
    @State private var targetPrice: Double? = nil
    @State private var guruFocusPrice: Double? = nil
    @State private var tipRanksPrice: Double? = nil
    @State private var currentPE: Double? = nil
    @State private var forwardPE: Double? = nil
    @State private var historicalPE10Y: Double? = nil
    @State private var peg: Double? = nil
    @State private var pFcf: Double? = nil // NEW
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Edit Valuation: \(position.ticker)").font(.title2).fontWeight(.bold)
                Spacer()
                Button(action: { dismiss() }) { Image(systemName: "xmark.circle.fill").font(.title2).foregroundColor(.secondary) }.buttonStyle(.plain)
            }.padding()
            Divider()
            
            Form {
                GroupBox("Price Targets") {
                    VStack(spacing: 10) {
                        HStack { Text("Target Price:").frame(width: 130, alignment: .leading); TextField("0.0", value: $targetPrice, format: .number).textFieldStyle(.roundedBorder) }
                        HStack { Text("GuruFocus Fair Value:").frame(width: 130, alignment: .leading); TextField("0.0", value: $guruFocusPrice, format: .number).textFieldStyle(.roundedBorder) }
                        HStack { Text("TipRanks Target:").frame(width: 130, alignment: .leading); TextField("0.0", value: $tipRanksPrice, format: .number).textFieldStyle(.roundedBorder) }
                    }
                }
                
                GroupBox("Valuation Multiples & Cash Flow") {
                    VStack(spacing: 10) {
                        HStack { Text("Current PE:").frame(width: 130, alignment: .leading); TextField("0.0", value: $currentPE, format: .number).textFieldStyle(.roundedBorder) }
                        HStack { Text("Forward PE:").frame(width: 130, alignment: .leading); TextField("0.0", value: $forwardPE, format: .number).textFieldStyle(.roundedBorder) }
                        HStack { Text("10Y Avg PE:").frame(width: 130, alignment: .leading); TextField("0.0", value: $historicalPE10Y, format: .number).textFieldStyle(.roundedBorder) }
                        HStack { Text("PEG Ratio:").frame(width: 130, alignment: .leading); TextField("0.0", value: $peg, format: .number).textFieldStyle(.roundedBorder) }
                        HStack { Text("P/FCF Ratio:").frame(width: 130, alignment: .leading); TextField("0.0", value: $pFcf, format: .number).textFieldStyle(.roundedBorder) } // NEW
                    }
                }
            }
            .padding()
            
            Divider()
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") { save() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }.padding()
        }
        .frame(width: 480, height: 500)
        .onAppear {
            targetPrice = position.targetPrice
            guruFocusPrice = position.guruFocusPrice
            tipRanksPrice = position.tipRanksPrice
            currentPE = position.currentPE
            forwardPE = position.forwardPE
            historicalPE10Y = position.historicalPE10Y
            peg = position.peg
            pFcf = position.pFcf
        }
    }
    
    func save() {
        if let idx = viewModel.positions.firstIndex(where: { $0.id == position.id }) {
            viewModel.positions[idx].targetPrice = targetPrice
            viewModel.positions[idx].guruFocusPrice = guruFocusPrice
            viewModel.positions[idx].tipRanksPrice = tipRanksPrice
            viewModel.positions[idx].currentPE = currentPE
            viewModel.positions[idx].forwardPE = forwardPE
            viewModel.positions[idx].historicalPE10Y = historicalPE10Y
            viewModel.positions[idx].peg = peg
            viewModel.positions[idx].pFcf = pFcf
            viewModel.saveData()
        }
        dismiss()
    }
}

// =========================================================================
// MARK: - FULL SCREEN ZOOM MODAL
// =========================================================================

struct ValuationFullScreenChartView: View {
    @Environment(\.dismiss) var dismiss
    let zoomType: ValuationChartZoomType
    @ObservedObject var viewModel: PortfolioViewModel
    let marginOfSafety: Double
    @Binding var privacyMode: Bool

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text(titleForZoom).font(.title).fontWeight(.bold)
                Spacer()
                Button(action: { dismiss() }) { Image(systemName: "xmark.circle.fill").font(.title).foregroundColor(.secondary) }.buttonStyle(.plain)
            }
            
            switch zoomType {
            case .priceComparison: ValuationPriceComparisonChart(viewModel: viewModel, marginOfSafety: marginOfSafety, privacyMode: $privacyMode, isExpanded: true, expandedChart: .constant(nil))
            case .peBullet: ValuationPEBulletChart(viewModel: viewModel, privacyMode: $privacyMode, isExpanded: true, expandedChart: .constant(nil))
            case .yieldBarometer: ValuationYieldsChart(viewModel: viewModel, privacyMode: $privacyMode, isExpanded: true, expandedChart: .constant(nil))
            case .cashMatrix: ValuationCashMatrixChart(viewModel: viewModel, privacyMode: $privacyMode, isExpanded: true, expandedChart: .constant(nil))
            case .pegScatter: ValuationPEGScatterChart(viewModel: viewModel, privacyMode: $privacyMode, isExpanded: true, expandedChart: .constant(nil))
            case .valuationHeatmap: ValuationDiscountHeatmap(viewModel: viewModel, marginOfSafety: marginOfSafety, isExpanded: true, expandedChart: .constant(nil))
            }
        }.padding(30).frame(minWidth: 900, minHeight: 700)
    }
    
    var titleForZoom: String {
        switch zoomType {
        case .priceComparison: return "Valuation & Target Prices Comparison"
        case .peBullet: return "Historical PE Valuation Gauge"
        case .yieldBarometer: return "Yield Barometer (Earnings vs Cash)"
        case .cashMatrix: return "Quality Matrix (Cash vs Accounting)"
        case .pegScatter: return "PEG Ratio Matrix (Price vs Growth)"
        case .valuationHeatmap: return "Portfolio Discount Heatmap"
        }
    }
}
