import SwiftUI
import Charts

// =========================================================================
// MARK: - EXTENSION POUR LES CALCULS DE VALORISATION
// =========================================================================
extension Position {
    // Helpers pour gérer les optionnels de manière transparente
    var valTargetPrice: Double { targetPrice ?? 0.0 }
    var valGuruFocusPrice: Double { guruFocusPrice ?? 0.0 }
    var valTipRanksPrice: Double { tipRanksPrice ?? 0.0 }
    var valCurrentPE: Double { currentPE ?? 0.0 }
    var valForwardPE: Double { forwardPE ?? 0.0 }
    var valHistoricalPE10Y: Double { historicalPE10Y ?? 0.0 }
    var valPeg: Double { peg ?? 0.0 }
    
    // Calcul du Fair Price avec marge de sécurité
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
}

// Zoom Enum pour les graphiques
enum ValuationChartZoomType: String, Identifiable {
    case priceComparison, peComparison
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
                
                // 4. MULTIPLES (PE) VALUATION TABLE
                ValuationPETableSection(
                    viewModel: viewModel,
                    privacyMode: $privacyMode,
                    onEdit: { pos in editingPosition = pos }
                )
                
                // 5. CHARTS (PRICES & PE)
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
            // Row 1
            HStack(spacing: 16) {
                DashboardCard(title: "Valuated Stocks", value: "\(valuatedStocks.count) / \(viewModel.positions.count)", titleIcon: nil, privacyMode: .constant(false))
                DashboardCard(title: "Undervalued (Fair Price)", value: "\(undervaluedCount)", titleIcon: nil, privacyMode: .constant(false))
                DashboardCard(title: "Avg. Fair Price Upside", value: avgFairPriceUpside.formatted(.percent.precision(.fractionLength(1)).sign(strategy: .always())), titleIcon: nil, privacyMode: .constant(false))
                DashboardCard(title: "Avg. Historical PE Upside", value: avgPEUpside.formatted(.percent.precision(.fractionLength(1)).sign(strategy: .always())), titleIcon: nil, privacyMode: .constant(false))
            }
            
            // Row 2
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
                // Header
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
// MARK: - 4. MULTIPLES (PE) VALUATION TABLE
// =========================================================================

struct ValuationPETableSection: View {
    @ObservedObject var viewModel: PortfolioViewModel
    @Binding var privacyMode: Bool
    let onEdit: (Position) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Multiples & Historical PE").font(.title2).fontWeight(.bold).foregroundColor(.secondary)
                Spacer()
                Text("(Double-click to edit valuation metrics)").font(.caption).foregroundColor(.secondary).italic()
            }.padding(.bottom, 4)
            
            VStack(spacing: 0) {
                // Header
                HStack(spacing: 8) {
                    Text("Ticker").fontWeight(.bold).frame(width: 70, alignment: .leading)
                    Text("Current PE").fontWeight(.bold).frame(maxWidth: .infinity, alignment: .trailing)
                    Text("Forward PE").fontWeight(.bold).frame(maxWidth: .infinity, alignment: .trailing)
                    Text("10Y Avg PE").fontWeight(.bold).frame(maxWidth: .infinity, alignment: .trailing)
                    Text("PEG Ratio").fontWeight(.bold).frame(maxWidth: .infinity, alignment: .trailing)
                    Text("PE Upside").fontWeight(.bold).frame(maxWidth: .infinity, alignment: .trailing)
                }
                .font(.subheadline).foregroundColor(.secondary).padding(.horizontal, 16).padding(.vertical, 12).background(Color(NSColor.windowBackgroundColor))
                
                Divider()
                
                if viewModel.positions.isEmpty {
                    Text("No positions in portfolio.").foregroundColor(.secondary).padding(30)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(viewModel.positions) { pos in
                                let peUp = pos.peUpside
                                
                                HStack(spacing: 8) {
                                    Text(pos.ticker).fontWeight(.bold).frame(width: 70, alignment: .leading)
                                    
                                    Text(pos.valCurrentPE > 0 ? pos.valCurrentPE.formatted(.number.precision(.fractionLength(1))) : "-")
                                        .foregroundColor((pos.valCurrentPE < pos.valHistoricalPE10Y && pos.valHistoricalPE10Y > 0) ? .green : .primary).frame(maxWidth: .infinity, alignment: .trailing)
                                        
                                    Text(pos.valForwardPE > 0 ? pos.valForwardPE.formatted(.number.precision(.fractionLength(1))) : "-")
                                        .foregroundColor((pos.valForwardPE < pos.valCurrentPE && pos.valCurrentPE > 0) ? .teal : .primary).frame(maxWidth: .infinity, alignment: .trailing)
                                    
                                    Text(pos.valHistoricalPE10Y > 0 ? pos.valHistoricalPE10Y.formatted(.number.precision(.fractionLength(1))) : "-")
                                        .foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .trailing)
                                    
                                    if pos.valPeg > 0 {
                                        Text(pos.valPeg.formatted(.number.precision(.fractionLength(2))))
                                            .fontWeight(.semibold).foregroundColor(pos.valPeg <= 1.0 ? .green : (pos.valPeg > 2.0 ? .orange : .primary)).frame(maxWidth: .infinity, alignment: .trailing)
                                    } else {
                                        Text("-").frame(maxWidth: .infinity, alignment: .trailing)
                                    }
                                    
                                    if pos.valCurrentPE > 0 && pos.valHistoricalPE10Y > 0 {
                                        Text(peUp.formatted(.percent.precision(.fractionLength(1)).sign(strategy: .always()))).fontWeight(.bold).padding(.horizontal, 6).padding(.vertical, 2).background((peUp >= 0 ? Color.green : Color.red).opacity(0.15)).foregroundColor(peUp >= 0 ? .green : .red).cornerRadius(4).frame(maxWidth: .infinity, alignment: .trailing)
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
// MARK: - 5. CHARTS SECTION
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
                ValuationPEComparisonChart(viewModel: viewModel, privacyMode: $privacyMode, expandedChart: $chartToZoom)
            }
        }
    }
}

// --- CHART 1: PRICES COMPARISON ---

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
            if pos.valTargetPrice > 0 { result.append(ValPriceSeriesItem(ticker: pos.ticker, type: "Target Price", price: pos.valTargetPrice)) }
            if pos.fairPrice(marginOfSafety: marginOfSafety) > 0 { result.append(ValPriceSeriesItem(ticker: pos.ticker, type: "Fair Price", price: pos.fairPrice(marginOfSafety: marginOfSafety))) }
        }
        return result
    }
    
    let allTypes = ["Current Price", "Target Price", "Fair Price"]
    func color(for type: String) -> Color {
        switch type {
        case "Current Price": return .blue
        case "Target Price": return .purple
        case "Fair Price": return .green
        default: return .primary
        }
    }

    var body: some View {
        let filteredSeries = seriesData.filter { !hiddenSeries.contains($0.type) }
        
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if !isExpanded { Text("Valuation & Target Prices Comparison").font(.headline).foregroundColor(.secondary) }
                Spacer()
                if !isExpanded {
                    Button(action: { expandedChart = .priceComparison }) { Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary) }.buttonStyle(.plain)
                }
            }.padding(.bottom, 4)
            
            InteractiveLegendView(items: allTypes, colorMap: color, hiddenItems: $hiddenSeries).padding(.bottom, 4)
            
            if viewModel.positions.isEmpty {
                Spacer(); Text("No data").foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .center); Spacer()
            } else {
                Chart(filteredSeries) { item in
                    BarMark(
                        x: .value("Ticker", item.ticker),
                        y: .value("Price", item.price)
                    )
                    .foregroundStyle(color(for: item.type))
                    .position(by: .value("Type", item.type))
                    .cornerRadius(4)
                    
                    if let hTicker = hoveredTicker, item.ticker == hTicker {
                        RuleMark(x: .value("Ticker", hTicker))
                            .foregroundStyle(.secondary.opacity(0.3))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                    }
                }
                .chartLegend(.hidden)
                .chartXSelection(value: $hoveredTicker)
                .chartYAxis { AxisMarks(position: .leading) { value in AxisGridLine(); AxisTick(); if let val = value.as(Double.self) { AxisValueLabel(val.formatted(.currency(code: "EUR").notation(.compactName))) } } }
            }
            
            HStack { Text("Hover over bars for comparison").font(.caption2).foregroundColor(.secondary); Spacer(); BlueChipWatermark() }
        }.padding().frame(minHeight: isExpanded ? 500 : 360, maxHeight: isExpanded ? .infinity : 360).background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// --- CHART 2: PE COMPARISON ---

struct ValuationPEComparisonChart: View {
    @ObservedObject var viewModel: PortfolioViewModel
    @Binding var privacyMode: Bool
    var isExpanded: Bool = false
    @Binding var expandedChart: ValuationChartZoomType?
    
    @State private var hiddenSeries: Set<String> = []
    @State private var hoveredTicker: String? = nil

    struct ValPESeriesItem: Identifiable { let id = UUID(); let ticker: String; let type: String; let pe: Double }
    
    var seriesData: [ValPESeriesItem] {
        var result: [ValPESeriesItem] = []
        for pos in viewModel.positions {
            if pos.valCurrentPE > 0 { result.append(ValPESeriesItem(ticker: pos.ticker, type: "Current PE", pe: pos.valCurrentPE)) }
            if pos.valForwardPE > 0 { result.append(ValPESeriesItem(ticker: pos.ticker, type: "Forward PE", pe: pos.valForwardPE)) }
            if pos.valHistoricalPE10Y > 0 { result.append(ValPESeriesItem(ticker: pos.ticker, type: "10Y Avg PE", pe: pos.valHistoricalPE10Y)) }
        }
        return result
    }

    let legendTypes = ["Current PE", "Forward PE", "10Y Avg PE"]
    func color(for type: String) -> Color {
        switch type {
        case "Current PE": return .orange
        case "Forward PE": return .teal
        case "10Y Avg PE": return .indigo
        default: return .gray
        }
    }

    var body: some View {
        let filtered = seriesData.filter { !hiddenSeries.contains($0.type) }
        
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if !isExpanded { Text("PE Valuation (Current vs Fwd vs 10Y)").font(.headline).foregroundColor(.secondary) }
                Spacer()
                if !isExpanded {
                    Button(action: { expandedChart = .peComparison }) { Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary) }.buttonStyle(.plain)
                }
            }.padding(.bottom, 4)
            
            InteractiveLegendView(items: legendTypes, colorMap: color, hiddenItems: $hiddenSeries).padding(.bottom, 4)
            
            if viewModel.positions.isEmpty {
                Spacer(); Text("No data").foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .center); Spacer()
            } else {
                Chart {
                    ForEach(filtered) { item in
                        LineMark(
                            x: .value("Ticker", item.ticker),
                            y: .value("PE", item.pe)
                        )
                        .foregroundStyle(color(for: item.type))
                        .interpolationMethod(.linear)
                        
                        PointMark(
                            x: .value("Ticker", item.ticker),
                            y: .value("PE", item.pe)
                        )
                        .foregroundStyle(color(for: item.type))
                        .symbolSize(hoveredTicker == item.ticker ? 100 : 40)
                    }
                    
                    if let hTicker = hoveredTicker, let pos = viewModel.positions.first(where: { $0.ticker == hTicker }) {
                        RuleMark(x: .value("Ticker", hTicker))
                            .foregroundStyle(.secondary.opacity(0.4))
                            .annotation(position: .top) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(pos.ticker).font(.caption.bold())
                                    Text("Current PE: \(pos.valCurrentPE.formatted())x").font(.caption2).foregroundColor(.orange)
                                    Text("Forward PE: \(pos.valForwardPE.formatted())x").font(.caption2).foregroundColor(.teal)
                                    Text("10Y Avg PE: \(pos.valHistoricalPE10Y.formatted())x").font(.caption2).foregroundColor(.indigo)
                                }
                                .padding(6).background(Color(NSColor.windowBackgroundColor)).cornerRadius(6).shadow(radius: 3)
                            }
                    }
                }
                .chartLegend(.hidden)
                .chartXSelection(value: $hoveredTicker)
            }
            
            HStack { Text("Forward PE < Current PE indicates expected growth").font(.caption2).foregroundColor(.secondary); Spacer(); BlueChipWatermark() }
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
                
                GroupBox("Valuation Multiples") {
                    VStack(spacing: 10) {
                        HStack { Text("Current PE:").frame(width: 130, alignment: .leading); TextField("0.0", value: $currentPE, format: .number).textFieldStyle(.roundedBorder) }
                        HStack { Text("Forward PE:").frame(width: 130, alignment: .leading); TextField("0.0", value: $forwardPE, format: .number).textFieldStyle(.roundedBorder) }
                        HStack { Text("10Y Avg PE:").frame(width: 130, alignment: .leading); TextField("0.0", value: $historicalPE10Y, format: .number).textFieldStyle(.roundedBorder) }
                        HStack { Text("PEG Ratio:").frame(width: 130, alignment: .leading); TextField("0.0", value: $peg, format: .number).textFieldStyle(.roundedBorder) }
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
        .frame(width: 480, height: 480)
        .onAppear {
            targetPrice = position.targetPrice
            guruFocusPrice = position.guruFocusPrice
            tipRanksPrice = position.tipRanksPrice
            currentPE = position.currentPE
            forwardPE = position.forwardPE
            historicalPE10Y = position.historicalPE10Y
            peg = position.peg
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
            case .priceComparison:
                ValuationPriceComparisonChart(viewModel: viewModel, marginOfSafety: marginOfSafety, privacyMode: $privacyMode, isExpanded: true, expandedChart: .constant(nil))
            case .peComparison:
                ValuationPEComparisonChart(viewModel: viewModel, privacyMode: $privacyMode, isExpanded: true, expandedChart: .constant(nil))
            }
        }.padding(30).frame(minWidth: 900, minHeight: 700)
    }
    
    var titleForZoom: String {
        switch zoomType {
        case .priceComparison: return "Valuation & Target Prices Comparison"
        case .peComparison: return "PE Valuation (Current vs Fwd vs 10Y)"
        }
    }
}
