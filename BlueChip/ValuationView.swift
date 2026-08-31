import SwiftUI
import Charts

// =========================================================================
// MARK: - EXTENSION FOR VALUATION CALCULATIONS
// =========================================================================
extension Position {
    var valTargetPrice: Double { targetPrice ?? 0.0 }
    var valGuruFocusPrice: Double { guruFocusPrice ?? 0.0 }
    var valTipRanksPrice: Double { tipRanksPrice ?? 0.0 }
    var valCurrentPE: Double { currentPE ?? 0.0 }
    var valForwardPE: Double { forwardPE ?? 0.0 }
    var valHistoricalPE10Y: Double { historicalPE10Y ?? 0.0 }
    var valPeg: Double { peg ?? 0.0 }
    var valPFcf: Double { pFcf ?? 0.0 }
    
    var earningsYield: Double { valCurrentPE > 0 ? (1.0 / valCurrentPE) : 0.0 }
    var fcfYield: Double { valPFcf > 0 ? (1.0 / valPFcf) : 0.0 }
    
    func fairPrice(marginOfSafety: Double) -> Double {
        let avgValuation = (valGuruFocusPrice + valTipRanksPrice) / 2.0
        return avgValuation * (1.0 - (marginOfSafety / 100.0))
    }
    
    func fairPriceUpside(marginOfSafety: Double) -> Double {
        guard currentPrice > 0 else { return 0 }
        let fp = fairPrice(marginOfSafety: marginOfSafety)
        return (fp - currentPrice) / currentPrice
    }
    
    var peUpside: Double {
        guard valCurrentPE > 0 else { return 0 }
        return (valHistoricalPE10Y - valCurrentPE) / valCurrentPE
    }
    
    var impliedGrowth: Double {
        guard valPeg > 0 else { return 0 }
        return valCurrentPE / valPeg
    }
}

// Zoom Enum for Charts
enum ValuationChartZoomType: String, Identifiable {
    case priceComparison, peBullet, yieldBarometer, cashMatrix, pegScatter, valuationHeatmap
    case peContraction, valuationDistribution
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
                
                // 5. CHARTS (8x GRAPHS)
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
                DashboardCard(title: "Valuated Stocks", value: "\(valuatedStocks.count) / \(viewModel.positions.count)", titleIcon: nil, privacyMode: $privacyMode)
                DashboardCard(title: "Undervalued (Fair Price)", value: "\(undervaluedCount)", titleIcon: nil, privacyMode: $privacyMode)
                DashboardCard(title: "Avg. Fair Price Upside", value: avgFairPriceUpside.formatted(.percent.precision(.fractionLength(1)).sign(strategy: .always())), titleIcon: nil, privacyMode: $privacyMode)
                DashboardCard(title: "Avg. Historical PE Upside", value: avgPEUpside.formatted(.percent.precision(.fractionLength(1)).sign(strategy: .always())), titleIcon: nil, privacyMode: $privacyMode)
            }
            HStack(spacing: 16) {
                DashboardCard(title: "Avg. Current PE", value: avgCurrentPE > 0 ? avgCurrentPE.formatted(.number.precision(.fractionLength(1))) + "x" : "-", titleIcon: nil, privacyMode: $privacyMode)
                DashboardCard(title: "Avg. Forward PE", value: avgForwardPE > 0 ? avgForwardPE.formatted(.number.precision(.fractionLength(1))) + "x" : "-", titleIcon: nil, privacyMode: $privacyMode)
                DashboardCard(title: "Avg. 10Y Historical PE", value: avgHistoricalPE > 0 ? avgHistoricalPE.formatted(.number.precision(.fractionLength(1))) + "x" : "-", titleIcon: nil, privacyMode: $privacyMode)
                DashboardCard(title: "Avg. Portfolio PEG", value: avgPEG > 0 ? avgPEG.formatted(.number.precision(.fractionLength(2))) : "-", titleIcon: nil, privacyMode: $privacyMode)
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
                                    Text(pos.currentPrice.formatted(.currency(code: pos.currency).precision(.fractionLength(2)))).fontWeight(.semibold).blur(radius: privacyMode ? 6 : 0).frame(maxWidth: .infinity, alignment: .trailing)
                                    Text(pos.valTargetPrice > 0 ? pos.valTargetPrice.formatted(.currency(code: pos.currency).precision(.fractionLength(2))) : "-").foregroundColor(.purple).blur(radius: privacyMode ? 6 : 0).frame(maxWidth: .infinity, alignment: .trailing)
                                    Text(pos.valGuruFocusPrice > 0 ? pos.valGuruFocusPrice.formatted(.currency(code: pos.currency).precision(.fractionLength(2))) : "-").foregroundColor(.secondary).blur(radius: privacyMode ? 6 : 0).frame(maxWidth: .infinity, alignment: .trailing)
                                    Text(pos.valTipRanksPrice > 0 ? pos.valTipRanksPrice.formatted(.currency(code: pos.currency).precision(.fractionLength(2))) : "-").foregroundColor(.secondary).blur(radius: privacyMode ? 6 : 0).frame(maxWidth: .infinity, alignment: .trailing)
                                    Text(fairP > 0 ? fairP.formatted(.currency(code: pos.currency).precision(.fractionLength(2))) : "-").fontWeight(.bold).foregroundColor(isUndervalued ? .green : .primary).blur(radius: privacyMode ? 6 : 0).frame(maxWidth: .infinity, alignment: .trailing)
                                    
                                    if fairP > 0 {
                                        Text(upside.formatted(.percent.precision(.fractionLength(1)).sign(strategy: .always()))).fontWeight(.bold).padding(.horizontal, 6).padding(.vertical, 2).background((upside >= 0 ? Color.green : Color.red).opacity(0.15)).foregroundColor(upside >= 0 ? .green : .red).cornerRadius(4).blur(radius: privacyMode ? 6 : 0).frame(maxWidth: .infinity, alignment: .trailing)
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
                                    Text(pos.valCurrentPE > 0 ? pos.valCurrentPE.formatted(.number.precision(.fractionLength(1))) : "-").foregroundColor((pos.valCurrentPE < pos.valHistoricalPE10Y && pos.valHistoricalPE10Y > 0) ? .green : .primary).blur(radius: privacyMode ? 6 : 0).frame(maxWidth: .infinity, alignment: .trailing)
                                    Text(pos.valForwardPE > 0 ? pos.valForwardPE.formatted(.number.precision(.fractionLength(1))) : "-").foregroundColor((pos.valForwardPE < pos.valCurrentPE && pos.valCurrentPE > 0) ? .teal : .primary).blur(radius: privacyMode ? 6 : 0).frame(maxWidth: .infinity, alignment: .trailing)
                                    Text(pos.valHistoricalPE10Y > 0 ? pos.valHistoricalPE10Y.formatted(.number.precision(.fractionLength(1))) : "-").foregroundColor(.secondary).blur(radius: privacyMode ? 6 : 0).frame(maxWidth: .infinity, alignment: .trailing)
                                    Text(pos.valPFcf > 0 ? pos.valPFcf.formatted(.number.precision(.fractionLength(1))) : "-").fontWeight(.medium).blur(radius: privacyMode ? 6 : 0).frame(maxWidth: .infinity, alignment: .trailing)
                                    
                                    if pos.valPeg > 0 {
                                        Text(pos.valPeg.formatted(.number.precision(.fractionLength(2)))).fontWeight(.semibold).foregroundColor(pos.valPeg <= 1.0 ? .green : (pos.valPeg > 2.0 ? .orange : .primary)).blur(radius: privacyMode ? 6 : 0).frame(maxWidth: .infinity, alignment: .trailing)
                                    } else {
                                        Text("-").frame(maxWidth: .infinity, alignment: .trailing)
                                    }
                                    
                                    if pos.earningsYield > 0 {
                                        Text(pos.earningsYield.formatted(.percent.precision(.fractionLength(1)))).foregroundColor(.blue).blur(radius: privacyMode ? 6 : 0).frame(maxWidth: .infinity, alignment: .trailing)
                                    } else {
                                        Text("-").frame(maxWidth: .infinity, alignment: .trailing)
                                    }
                                    
                                    if pos.fcfYield > 0 {
                                        Text(pos.fcfYield.formatted(.percent.precision(.fractionLength(1)))).fontWeight(.bold).foregroundColor(.green).blur(radius: privacyMode ? 6 : 0).frame(maxWidth: .infinity, alignment: .trailing)
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
// MARK: - 5. CHARTS SECTION (4x2 GRID)
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
                ValuationDiscountHeatmap(viewModel: viewModel, marginOfSafety: marginOfSafety, privacyMode: $privacyMode, expandedChart: $chartToZoom)
            }
            HStack(spacing: 20) {
                ValuationPEContractionChart(viewModel: viewModel, privacyMode: $privacyMode, expandedChart: $chartToZoom)
                ValuationDistributionDonutChart(viewModel: viewModel, marginOfSafety: marginOfSafety, privacyMode: $privacyMode, expandedChart: $chartToZoom)
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
                            .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                                if let targetPos = viewModel.positions.first(where: { $0.ticker == hTicker }) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(hTicker).font(.caption.bold())
                                        
                                        // J'en ai profité pour utiliser la devise dynamique de l'action au lieu de "EUR" en dur !
                                        let currency = targetPos.currency.isEmpty ? "EUR" : targetPos.currency
                                        
                                        Text("Current: \(targetPos.currentPrice.formatted(.currency(code: currency)))")
                                            .font(.caption2).foregroundColor(.blue).blur(radius: privacyMode ? 6 : 0)
                                        
                                        // 👉 L'AJOUT DE GURUFOCUS EST ICI
                                        if targetPos.valGuruFocusPrice > 0 {
                                            Text("GuruFocus: \(targetPos.valGuruFocusPrice.formatted(.currency(code: currency)))")
                                                .font(.caption2).foregroundColor(.gray).blur(radius: privacyMode ? 6 : 0)
                                        }
                                        
                                        if targetPos.valTipRanksPrice > 0 {
                                            Text("TipRanks: \(targetPos.valTipRanksPrice.formatted(.currency(code: currency)))")
                                                .font(.caption2).foregroundColor(.teal).blur(radius: privacyMode ? 6 : 0)
                                        }
                                    }.padding(6).background(Color(NSColor.windowBackgroundColor).opacity(0.95)).cornerRadius(6).shadow(radius: 4)
                                }
                            }
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
                            .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(pos.ticker).font(.caption.bold())
                                    Text("Current: \(pos.valCurrentPE.formatted())x").font(.caption2).foregroundColor(.blue).blur(radius: privacyMode ? 6 : 0)
                                    Text("10Y Avg: \(pos.valHistoricalPE10Y.formatted())x").font(.caption2).foregroundColor(.primary).blur(radius: privacyMode ? 6 : 0)
                                    Text("Forward: \(pos.valForwardPE.formatted())x").font(.caption2).foregroundColor(.teal).blur(radius: privacyMode ? 6 : 0)
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
                            .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                                if let targetPos = viewModel.positions.first(where: { $0.ticker == hTicker }) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(hTicker).font(.caption.bold())
                                        Text("Earnings Yld: \(targetPos.earningsYield.formatted(.percent.precision(.fractionLength(1))))").font(.caption2).foregroundColor(.blue).blur(radius: privacyMode ? 6 : 0)
                                        Text("FCF Yld: \(targetPos.fcfYield.formatted(.percent.precision(.fractionLength(1))))").font(.caption2).foregroundColor(.green).blur(radius: privacyMode ? 6 : 0)
                                    }.padding(6).background(Color(NSColor.windowBackgroundColor).opacity(0.95)).cornerRadius(6).shadow(radius: 4)
                                }
                            }
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
                        .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                            if hoveredItem?.id == pos.id {
                                VStack(spacing: 2) {
                                    Text(pos.ticker).font(.caption.bold())
                                    Text("E Yld: \(pos.earningsYield.formatted(.percent.precision(.fractionLength(1))))").font(.caption2).blur(radius: privacyMode ? 6 : 0)
                                    Text("FCF Yld: \(pos.fcfYield.formatted(.percent.precision(.fractionLength(1))))").font(.caption2).blur(radius: privacyMode ? 6 : 0)
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
                        .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                            if hoveredItem?.id == pos.id {
                                VStack(spacing: 2) {
                                    Text(pos.ticker).font(.caption.bold())
                                    Text("PEG: \(pos.valPeg.formatted(.number.precision(.fractionLength(2))))").font(.caption2).blur(radius: privacyMode ? 6 : 0)
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
    @Binding var privacyMode: Bool
    
    func color(for upside: Double) -> Color {
        if upside == 0 { return Color.gray.opacity(0.4) }
        let intensity = min(max(abs(upside) / 0.5, 0.3), 1.0)
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
                    Text(upside.formatted(.percent.precision(.fractionLength(1)))).font(.caption).foregroundColor(.white.opacity(0.9)).lineLimit(1).blur(radius: privacyMode ? 6 : 0)
                }
            }
            if isHovered {
                VStack {
                    Text(node.position.ticker).font(.caption.bold())
                    Text("Fair Price: \(node.position.fairPrice(marginOfSafety: marginOfSafety).formatted(.currency(code: "EUR")))").font(.caption2).blur(radius: privacyMode ? 6 : 0)
                    Text("Upside: \(upside.formatted(.percent.precision(.fractionLength(1)).sign(strategy: .always())))").font(.caption2).blur(radius: privacyMode ? 6 : 0)
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
    @Binding var privacyMode: Bool
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
                            ValHeatmapNodeView(node: node, marginOfSafety: marginOfSafety, hoveredTicker: $hoveredTicker, privacyMode: $privacyMode)
                        }
                    }
                }
            }
            HStack { Text("Size = Portfolio Weight | Color = Fair Price Upside").font(.caption2).foregroundColor(.secondary); Spacer(); BlueChipWatermark() }.padding(.top, 4)
        }.padding().frame(minHeight: isExpanded ? 500 : 360, maxHeight: isExpanded ? .infinity : 360).background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// --- CHART 7 (NEW) : P/E CONTRACTION DUMBBELL ---

struct ValuationPEContractionChart: View {
    @ObservedObject var viewModel: PortfolioViewModel
    @Binding var privacyMode: Bool
    var isExpanded: Bool = false
    @Binding var expandedChart: ValuationChartZoomType?
    
    @State private var hoveredTicker: String? = nil
    
    var validPositions: [Position] {
        viewModel.positions.filter { $0.valCurrentPE > 0 && $0.valForwardPE > 0 }.sorted { $0.valCurrentPE > $1.valCurrentPE }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if !isExpanded { Text("Forward P/E Contraction").font(.headline).foregroundColor(.secondary) }
                Spacer()
                if !isExpanded { Button(action: { expandedChart = .peContraction }) { Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary) }.buttonStyle(.plain) }
            }.padding(.bottom, 4)
            
            HStack(spacing: 16) {
                HStack(spacing: 4) { Circle().fill(Color.gray).frame(width: 8, height: 8); Text("Current P/E").font(.caption) }
                HStack(spacing: 4) { Circle().fill(Color.teal).frame(width: 8, height: 8); Text("Forward P/E").font(.caption) }
            }.padding(.bottom, 8)
            
            if validPositions.isEmpty {
                Spacer(); Text("No Forward PE data").foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .center); Spacer()
            } else {
                Chart(validPositions) { pos in
                    // Ligne qui relie les deux points
                    BarMark(
                        xStart: .value("PE 1", min(pos.valCurrentPE, pos.valForwardPE)),
                        xEnd: .value("PE 2", max(pos.valCurrentPE, pos.valForwardPE)),
                        y: .value("Ticker", pos.ticker),
                        height: .fixed(4)
                    )
                    .foregroundStyle(pos.valForwardPE < pos.valCurrentPE ? Color.green.opacity(0.4) : Color.red.opacity(0.4))
                    
                    // Point Current PE
                    PointMark(x: .value("Current", pos.valCurrentPE), y: .value("Ticker", pos.ticker))
                        .foregroundStyle(Color.gray).symbolSize(60)
                        
                    // Point Forward PE
                    PointMark(x: .value("Forward", pos.valForwardPE), y: .value("Ticker", pos.ticker))
                        .foregroundStyle(Color.teal).symbolSize(100)
                    
                    if let hTicker = hoveredTicker, pos.ticker == hTicker {
                        RuleMark(y: .value("Ticker", hTicker)).foregroundStyle(.secondary.opacity(0.2))
                            .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(pos.ticker).font(.caption.bold())
                                    Text("Current P/E: \(pos.valCurrentPE.formatted())x").font(.caption2).foregroundColor(.gray).blur(radius: privacyMode ? 6 : 0)
                                    Text("Forward P/E: \(pos.valForwardPE.formatted())x").font(.caption2).foregroundColor(.teal).blur(radius: privacyMode ? 6 : 0)
                                    let diff = ((pos.valForwardPE - pos.valCurrentPE) / pos.valCurrentPE) * 100
                                    Text("\(diff > 0 ? "+" : "")\(diff.formatted(.number.precision(.fractionLength(1))))%").font(.system(size: 8, weight: .bold)).foregroundColor(diff < 0 ? .green : .red)
                                }.padding(6).background(Color(NSColor.windowBackgroundColor).opacity(0.95)).cornerRadius(6).shadow(radius: 3)
                            }
                    }
                }
                .chartLegend(.hidden).chartYSelection(value: $hoveredTicker)
            }
            HStack { Text("Green line = P/E is expected to shrink (getting cheaper)").font(.caption2).foregroundColor(.secondary); Spacer(); BlueChipWatermark() }
        }.padding().frame(minHeight: isExpanded ? 500 : 360, maxHeight: isExpanded ? .infinity : 360).background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// --- CHART 8 (NEW) : VALUATION DISTRIBUTION DONUT ---

struct ValuationDistributionDonutChart: View {
    @ObservedObject var viewModel: PortfolioViewModel
    let marginOfSafety: Double
    @Binding var privacyMode: Bool
    var isExpanded: Bool = false
    @Binding var expandedChart: ValuationChartZoomType?
    
    @State private var selectedAngleValue: Double? = nil
    @State private var hiddenItems: Set<String> = []
    
    var data: [ChartDataItem] {
        var deepValue = 0.0
        var fairValue = 0.0
        var overValued = 0.0
        
        for pos in viewModel.positions {
            let upside = pos.fairPriceUpside(marginOfSafety: marginOfSafety)
            if upside > 0.20 { deepValue += pos.currentValueEUR }
            else if upside >= 0.0 { fairValue += pos.currentValueEUR }
            else if pos.fairPrice(marginOfSafety: marginOfSafety) > 0 { overValued += pos.currentValueEUR }
        }
        
        var result: [ChartDataItem] = []
        if deepValue > 0 { result.append(ChartDataItem(name: "Deep Value (>20% Upside)", value: deepValue)) }
        if fairValue > 0 { result.append(ChartDataItem(name: "Fairly Valued (0-20% Upside)", value: fairValue)) }
        if overValued > 0 { result.append(ChartDataItem(name: "Overvalued (<0% Upside)", value: overValued)) }
        return result
    }
    
    var filteredData: [ChartDataItem] { data.filter { !hiddenItems.contains($0.name) } }
    
    func color(for name: String) -> Color {
        if name.contains("Deep") { return .green }
        if name.contains("Fairly") { return .blue }
        return .red
    }
    
    var body: some View {
        VStack {
            HStack {
                if !isExpanded { Text("Valuation Range Distribution").font(.headline).foregroundColor(.secondary) }
                Spacer()
                if !isExpanded { Button(action: { expandedChart = .valuationDistribution }) { Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary) }.buttonStyle(.plain) }
            }.padding(.bottom, 4)
            
            InteractiveLegendView(items: data.map { $0.name }, colorMap: color, hiddenItems: $hiddenItems).padding(.bottom, 8)
            
            if filteredData.isEmpty { Spacer(); Text("No data").foregroundColor(.secondary); Spacer() } else {
                Chart(filteredData) { item in
                    SectorMark(angle: .value("Value", item.value), innerRadius: .ratio(0.65), angularInset: 1.5)
                        .foregroundStyle(color(for: item.name)).cornerRadius(4)
                }
                .chartLegend(.hidden).chartAngleSelection(value: $selectedAngleValue)
                .chartBackground { proxy in
                    GeometryReader { geometry in
                        if let value = selectedAngleValue, let item = findItem(for: value) {
                            VStack {
                                Text(item.name.split(separator: " ").first ?? "").font(.headline)
                                Text(item.value.formatted(.currency(code: "EUR"))).font(.subheadline).foregroundColor(.secondary).blur(radius: privacyMode ? 6 : 0)
                            }.position(x: geometry.frame(in: .local).midX, y: geometry.frame(in: .local).midY)
                        }
                    }
                }.animation(.easeInOut(duration: 0.2), value: selectedAngleValue)
            }
            BlueChipWatermark()
        }.padding().frame(minHeight: 360, maxHeight: isExpanded ? .infinity : 360).background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    func findItem(for value: Double) -> ChartDataItem? { var cum = 0.0; for item in filteredData { cum += item.value; if value <= cum { return item } }; return filteredData.last }
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
    @State private var pFcf: Double? = nil
    
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
                        HStack { Text("P/FCF Ratio:").frame(width: 130, alignment: .leading); TextField("0.0", value: $pFcf, format: .number).textFieldStyle(.roundedBorder) }
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
            case .valuationHeatmap: ValuationDiscountHeatmap(viewModel: viewModel, marginOfSafety: marginOfSafety, privacyMode: $privacyMode, isExpanded: true, expandedChart: .constant(nil))
            case .peContraction: ValuationPEContractionChart(viewModel: viewModel, privacyMode: $privacyMode, isExpanded: true, expandedChart: .constant(nil))
            case .valuationDistribution: ValuationDistributionDonutChart(viewModel: viewModel, marginOfSafety: marginOfSafety, privacyMode: $privacyMode, isExpanded: true, expandedChart: .constant(nil))
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
        case .peContraction: return "Forward P/E Contraction"
        case .valuationDistribution: return "Valuation Range Distribution"
        }
    }
}
