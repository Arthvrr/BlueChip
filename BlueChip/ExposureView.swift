import SwiftUI
import Charts
import SwiftData // <-- NOUVEAU

// =========================================================================
// MARK: - ENUMS & MODELS FOR EXPOSURE
// =========================================================================

enum ExposureChartZoomType: String, Identifiable {
    case donutExposure, stackedBarExposure
    case geographicTreemap, sectorRegionMatrix // NOUVEAUX GRAPHES
    var id: String { self.rawValue }
}

struct StackedBarItem: Identifiable {
    let id = UUID()
    let ticker: String
    let region: String
    let percentage: Double
}

struct FXRiskItem: Identifiable {
    let id = UUID()
    let currencyZone: String
    let percentage: Double
    let color: Color
}

// Modèles pour les nouveaux graphiques
struct SectorRegionItem: Identifiable {
    let id = UUID()
    let sector: String
    let region: String
    let weight: Double
}

struct TreemapRegionNode: Identifiable {
    let id = UUID()
    let name: String
    let percentage: Double
    let rect: CGRect
}

// =========================================================================
// MARK: - MAIN EXPOSURE VIEW
// =========================================================================

struct ExposureView: View {
    @ObservedObject var viewModel: PortfolioViewModel
    @Binding var privacyMode: Bool
    
    @State private var editingPosition: Position? = nil
    @State private var chartToZoom: ExposureChartZoomType? = nil
    
    // Extraction dynamique de toutes les régions uniques
    var allRegions: [String] {
        let regions = viewModel.positions.flatMap { ($0.revenueExposures ?? []).map { $0.regionName } }
        return Array(Set(regions)).sorted()
    }
    
    // MARK: - CALCULS PONDÉRÉS (USA vs ROW)
    var usaWeightedValue: Double {
        viewModel.positions.reduce(0) { total, pos in
            let usaPercent = (pos.revenueExposures ?? []).filter { $0.isUSA }.reduce(0) { $0 + $1.percentage }
            return total + (pos.currentValueEUR * (usaPercent / 100.0))
        }
    }
    
    var rowWeightedValue: Double {
        viewModel.positions.reduce(0) { total, pos in
            let rowPercent = (pos.revenueExposures ?? []).filter { !$0.isUSA }.reduce(0) { $0 + $1.percentage }
            return total + (pos.currentValueEUR * (rowPercent / 100.0))
        }
    }
    
    var unknownWeightedValue: Double {
        viewModel.positions.reduce(0) { total, pos in
            let knownPercent = (pos.revenueExposures ?? []).reduce(0) { $0 + $1.percentage }
            let unknownPercent = max(0, 100.0 - knownPercent)
            return total + (pos.currentValueEUR * (unknownPercent / 100.0))
        }
    }
    
    var donutData: [ChartDataItem] {
        [
            ChartDataItem(name: "USA Revenue", value: usaWeightedValue),
            ChartDataItem(name: "Rest of World (ROW)", value: rowWeightedValue),
            ChartDataItem(name: "Unknown / Unassigned", value: unknownWeightedValue)
        ].filter { $0.value > 0 }
    }
    
    // MARK: - CALCULS TOP MARCHÉS & FX RISK
    var regionalExposure: [(name: String, percentage: Double)] {
        var dict: [String: Double] = [:]
        let total = viewModel.totalValue
        guard total > 0 else { return [] }
        
        for pos in viewModel.positions {
            let exposures = pos.revenueExposures ?? []
            var knownPct = 0.0
            for exp in exposures {
                let weightedVal = pos.currentValueEUR * (exp.percentage / 100.0)
                dict[exp.regionName, default: 0] += weightedVal
                knownPct += exp.percentage
            }
            let unknownPct = max(0, 100.0 - knownPct)
            if unknownPct > 0 {
                dict["Unknown", default: 0] += pos.currentValueEUR * (unknownPct / 100.0)
            }
        }
        
        return dict.map { ($0.key, $0.value / total) }
            .sorted { $0.percentage > $1.percentage }
    }
    
    var fxRiskData: [FXRiskItem] {
        var usd = 0.0; var eur = 0.0; var asia = 0.0; var emerging = 0.0
        
        for market in regionalExposure {
            if market.name == "Unknown" { continue }
            let name = market.name.lowercased()
            
            if name.contains("us") || name.contains("america") { usd += market.percentage }
            else if name.contains("eu") || name.contains("emea") || name.contains("uk") { eur += market.percentage }
            else if name.contains("asia") || name.contains("apac") || name.contains("china") || name.contains("japan") { asia += market.percentage }
            else { emerging += market.percentage }
        }
        
        return [
            FXRiskItem(currencyZone: "USD (Americas)", percentage: usd, color: .green),
            FXRiskItem(currencyZone: "EUR/GBP (EMEA)", percentage: eur, color: .blue),
            FXRiskItem(currencyZone: "JPY/CNY (Asia)", percentage: asia, color: .red),
            FXRiskItem(currencyZone: "Other / Emerging", percentage: emerging, color: .orange)
        ].filter { $0.percentage > 0 }.sorted { $0.percentage > $1.percentage }
    }
    
    // MARK: - DONNÉES BARRES EMPILÉES
    var stackedBarData: [StackedBarItem] {
        var items: [StackedBarItem] = []
        for pos in viewModel.positions {
            let exposures = pos.revenueExposures ?? []
            var totalKnown = 0.0
            
            for exp in exposures {
                items.append(StackedBarItem(ticker: pos.ticker, region: exp.regionName, percentage: exp.percentage))
                totalKnown += exp.percentage
            }
            
            if totalKnown < 100.0 {
                items.append(StackedBarItem(ticker: pos.ticker, region: "Unknown", percentage: 100.0 - totalKnown))
            }
        }
        return items
    }
    
    // MARK: - DONNÉES SECTOR X GEOGRAPHY MATRIX
    var sectorRegionData: [SectorRegionItem] {
        var dict: [String: [String: Double]] = [:]
        let totalVal = viewModel.totalValue
        guard totalVal > 0 else { return [] }
        
        for pos in viewModel.positions {
            let sector = pos.sector.isEmpty ? "Unknown" : pos.sector
            let posWeight = pos.currentValueEUR / totalVal
            let exposures = pos.revenueExposures ?? []
            var knownPct = 0.0
            
            for exp in exposures {
                dict[sector, default: [:]][exp.regionName, default: 0] += posWeight * (exp.percentage / 100.0)
                knownPct += exp.percentage
            }
            let unknownPct = max(0, 100.0 - knownPct)
            if unknownPct > 0 {
                dict[sector, default: [:]]["Unknown", default: 0] += posWeight * (unknownPct / 100.0)
            }
        }
        
        var result: [SectorRegionItem] = []
        for (sec, regions) in dict {
            for (reg, weight) in regions {
                if weight > 0 { result.append(SectorRegionItem(sector: sec, region: reg, weight: weight)) }
            }
        }
        return result
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 24) {
                
                // HEADER
                HStack {
                    Text("Geographic Revenue Exposure").font(.title).fontWeight(.bold)
                    Spacer()
                }
                
                // 1. DASHBOARD
                VStack(spacing: 16) {
                    let totalVal = viewModel.totalValue
                    let usaPct = totalVal > 0 ? (usaWeightedValue / totalVal) : 0
                    let rowPct = totalVal > 0 ? (rowWeightedValue / totalVal) : 0
                    let unknownPct = totalVal > 0 ? (unknownWeightedValue / totalVal) : 0
                    let topRegionStr = usaPct >= rowPct ? "USA (\(usaPct.formatted(.percent.precision(.fractionLength(1)))))" : "ROW (\(rowPct.formatted(.percent.precision(.fractionLength(1)))))"
                    
                    let fullyMapped = viewModel.positions.filter { ($0.revenueExposures ?? []).reduce(0) { $0 + $1.percentage } >= 100.0 }.count
                    let maxConcentration = regionalExposure.first(where: { $0.name != "Unknown" })?.percentage ?? 0
                    let estFxRisk = rowPct // Risque de change = tout ce qui n'est pas aux US
                    
                    HStack(spacing: 16) {
                        DashboardCard(title: "Weighted USA Exposure", value: usaPct.formatted(.percent.precision(.fractionLength(1))), titleIcon: "star.fill", privacyMode: $privacyMode)
                        DashboardCard(title: "Weighted ROW Exposure", value: rowPct.formatted(.percent.precision(.fractionLength(1))), titleIcon: "globe.europe.africa.fill", privacyMode: $privacyMode)
                        DashboardCard(title: "Unassigned Revenue", value: unknownPct.formatted(.percent.precision(.fractionLength(1))), titleIcon: "questionmark.circle.fill", privacyMode: $privacyMode)
                        DashboardCard(title: "Primary Market Target", value: topRegionStr, titleIcon: "chart.bar.fill", privacyMode: $privacyMode)
                    }
                    HStack(spacing: 16) {
                        DashboardCard(title: "Total Regions Tracked", value: "\(allRegions.count)", titleIcon: nil, privacyMode: $privacyMode)
                        DashboardCard(title: "Fully Mapped Stocks", value: "\(fullyMapped) / \(viewModel.positions.count)", titleIcon: nil, privacyMode: $privacyMode)
                        DashboardCard(title: "Max Single-Region Focus", value: maxConcentration.formatted(.percent.precision(.fractionLength(1))), titleIcon: nil, privacyMode: $privacyMode)
                        DashboardCard(title: "Est. FX Risk (Non-USA)", value: estFxRisk.formatted(.percent.precision(.fractionLength(1))), titleIcon: nil, privacyMode: $privacyMode)
                    }
                }
                
                // 2. TOP MARCHÉS DOMINANTS & FX RISK MATRIX
                HStack(alignment: .top, spacing: 24) {
                    
                    // TOP MARCHÉS
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "list.number").foregroundColor(.blue)
                            Text("Top Dominant Markets").font(.headline).foregroundColor(.secondary)
                        }
                        
                        let knownMarkets = regionalExposure.filter { $0.name != "Unknown" }
                        if knownMarkets.isEmpty {
                            Text("No data available.").foregroundColor(.secondary).italic().padding(.top, 4)
                            Spacer()
                        } else {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(Array(knownMarkets.prefix(5).enumerated()), id: \.element.name) { index, market in
                                    HStack {
                                        Text("\(index + 1).").font(.subheadline).fontWeight(.bold).foregroundColor(.secondary).frame(width: 20, alignment: .leading)
                                        Text(market.name).font(.subheadline).fontWeight(.semibold)
                                        Spacer()
                                        Text(market.percentage.formatted(.percent.precision(.fractionLength(1))))
                                            .font(.subheadline).fontWeight(.bold).foregroundColor(.blue)
                                            .blur(radius: privacyMode ? 6 : 0)
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 200)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                    
                    // FX RISK MATRIX
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "dollarsign.arrow.circlepath").foregroundColor(.green)
                            Text("FX Risk Matrix (Currency Exposure)").font(.headline).foregroundColor(.secondary)
                        }
                        
                        if fxRiskData.isEmpty {
                            Text("No regional data to estimate FX risk.").foregroundColor(.secondary).italic().padding(.top, 4)
                            Spacer()
                        } else {
                            VStack(spacing: 12) {
                                ForEach(fxRiskData) { item in
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(item.currencyZone).font(.caption).fontWeight(.semibold)
                                            Spacer()
                                            Text(item.percentage.formatted(.percent.precision(.fractionLength(1))))
                                                .font(.caption).fontWeight(.bold)
                                                .blur(radius: privacyMode ? 6 : 0)
                                        }
                                        GeometryReader { geo in
                                            ZStack(alignment: .leading) {
                                                Capsule().fill(Color.gray.opacity(0.2)).frame(height: 6)
                                                Capsule().fill(item.color).frame(width: geo.size.width * CGFloat(item.percentage), height: 6)
                                            }
                                        }.frame(height: 6)
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 200)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                }
                
                // 3. TABLEAU PLEINE LARGEUR
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Revenue Segmentation by Stock").font(.title2).fontWeight(.bold)
                        Spacer()
                        Text("(Double-click on any row to edit regions)").font(.caption).foregroundColor(.secondary).italic()
                    }
                    
                    GeometryReader { geo in
                        ScrollView(.horizontal, showsIndicators: true) {
                            VStack(spacing: 0) {
                                HStack(spacing: 12) {
                                    Text("Ticker").fontWeight(.bold).frame(width: 80, alignment: .leading)
                                    Text("Known %").fontWeight(.bold).frame(width: 110, alignment: .leading)
                                    
                                    ForEach(allRegions, id: \.self) { region in
                                        Text(region).fontWeight(.bold).frame(maxWidth: .infinity, alignment: .trailing)
                                    }
                                }
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(Color(NSColor.windowBackgroundColor))
                                
                                Divider()
                                
                                if viewModel.positions.isEmpty {
                                    Text("No positions in portfolio.").foregroundColor(.secondary).padding(20)
                                } else {
                                    ScrollView(.vertical) {
                                        LazyVStack(spacing: 0) {
                                            ForEach(viewModel.positions) { pos in
                                                let exposures = pos.revenueExposures ?? []
                                                let totalKnown = exposures.reduce(0) { $0 + $1.percentage }
                                                
                                                HStack(spacing: 12) {
                                                    Text(pos.ticker).fontWeight(.bold).frame(width: 80, alignment: .leading)
                                                    
                                                    HStack {
                                                        ProgressView(value: min(totalKnown, 100.0), total: 100.0)
                                                            .tint(totalKnown >= 100 ? .green : .orange)
                                                            .frame(width: 50)
                                                        Text("\(Int(totalKnown))%")
                                                            .font(.caption).fontWeight(.bold)
                                                            .foregroundColor(totalKnown >= 100 ? .green : .orange)
                                                            .blur(radius: privacyMode ? 6 : 0)
                                                    }
                                                    .frame(width: 110, alignment: .leading)
                                                    
                                                    ForEach(allRegions, id: \.self) { region in
                                                        let pct = exposures.first(where: { $0.regionName == region })?.percentage
                                                        Text(pct != nil ? "\(pct!.formatted(.number.precision(.fractionLength(1))))%" : "/")
                                                            .frame(maxWidth: .infinity, alignment: .trailing)
                                                            .foregroundColor(pct != nil ? .primary : .secondary.opacity(0.3))
                                                            .blur(radius: privacyMode ? 6 : 0)
                                                    }
                                                }
                                                .padding(.horizontal, 16)
                                                .padding(.vertical, 10)
                                                .contentShape(Rectangle())
                                                .onTapGesture(count: 2) {
                                                    editingPosition = pos
                                                }
                                                
                                                Divider()
                                            }
                                        }
                                    }
                                }
                            }
                            .frame(minWidth: geo.size.width)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))
                        }
                    }
                    .frame(height: 300)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                
                // 4. LES 2 PREMIERS GRAPHIQUES INTERACTIFS
                HStack(alignment: .top, spacing: 24) {
                    let totalPortfolioValue = viewModel.totalValue
                    ExposureDonutChart(data: donutData, totalValue: totalPortfolioValue, title: "Weighted Portfolio Exposure (USA vs ROW)", privacyMode: $privacyMode, expandedChart: $chartToZoom)
                    ExposureStackedBarChart(data: stackedBarData, allRegions: allRegions, title: "Detailed Geographic Breakdown by Stock", privacyMode: $privacyMode, expandedChart: $chartToZoom)
                }
                
                // 5. NOUVEAUX GRAPHIQUES : GLOBAL HEATMAP & RISK MATRIX
                HStack(alignment: .top, spacing: 24) {
                    GeographicTreemapChart(data: regionalExposure, privacyMode: $privacyMode, expandedChart: $chartToZoom)
                    SectorRegionMatrixChart(data: sectorRegionData, allRegions: allRegionCategories, privacyMode: $privacyMode, expandedChart: $chartToZoom)
                }
            }
            .padding()
        }
        .sheet(item: $editingPosition) { pos in
            ExposureEditorSheet(viewModel: viewModel, position: pos)
        }
        .sheet(item: $chartToZoom) { type in
            let totalPortfolioValue = viewModel.totalValue
            ExposureFullScreenChartView(
                zoomType: type,
                donutData: donutData,
                stackedBarData: stackedBarData,
                allRegions: allRegions,
                totalValue: totalPortfolioValue,
                treemapData: regionalExposure,
                matrixData: sectorRegionData,
                allRegionCategories: allRegionCategories,
                privacyMode: $privacyMode
            )
        }
    }
    
    var allRegionCategories: [String] {
        var list = allRegions
        if !list.contains("Unknown") { list.append("Unknown") }
        return list
    }
}

// =========================================================================
// MARK: - GRAPHE 1 : DONUT CHART INTERACTIF (POURCENTAGES)
// =========================================================================

struct ExposureDonutChart: View {
    let data: [ChartDataItem]
    let totalValue: Double
    let title: String
    @Binding var privacyMode: Bool
    var isExpanded: Bool = false
    @Binding var expandedChart: ExposureChartZoomType?
    
    @State private var selectedAngleValue: Double? = nil
    @State private var hiddenItems: Set<String> = []
    
    func color(for name: String) -> Color {
        switch name {
        case "USA Revenue": return .blue
        case "Rest of World (ROW)": return .green
        default: return .gray.opacity(0.5)
        }
    }
    
    var filteredData: [ChartDataItem] {
        data.filter { !hiddenItems.contains($0.name) }
    }
    
    var body: some View {
        VStack {
            HStack {
                if !isExpanded { Text(title).font(.headline).foregroundColor(.secondary) }
                Spacer()
                if !isExpanded {
                    Button(action: { expandedChart = .donutExposure }) {
                        Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary)
                    }.buttonStyle(.plain)
                }
            }.padding(.bottom, 4)
            
            InteractiveLegendView(items: data.map { $0.name }, colorMap: color, hiddenItems: $hiddenItems)
                .padding(.bottom, 8)
            
            if filteredData.isEmpty || totalValue <= 0 {
                Spacer(); Text("No exposure data available").foregroundColor(.secondary); Spacer()
            } else {
                Chart(filteredData) { item in
                    SectorMark(
                        angle: .value("Value", item.value),
                        innerRadius: .ratio(0.65),
                        angularInset: 1.5
                    )
                    .foregroundStyle(color(for: item.name))
                    .cornerRadius(4)
                }
                .chartLegend(.hidden)
                .chartAngleSelection(value: $selectedAngleValue)
                .chartBackground { proxy in
                    GeometryReader { geometry in
                        if let value = selectedAngleValue {
                            let item = findItem(for: value)
                            let percent = item.value / totalValue
                            VStack {
                                Text(item.name).font(.headline).lineLimit(1)
                                Text(percent.formatted(.percent.precision(.fractionLength(1))))
                                    .font(.title3).fontWeight(.bold).foregroundColor(color(for: item.name))
                                    .blur(radius: privacyMode ? 6 : 0)
                            }
                            .position(x: geometry.frame(in: .local).midX, y: geometry.frame(in: .local).midY)
                        } else {
                            let displayedTotal = filteredData.reduce(0) { $0 + $1.value }
                            let displayedPercent = displayedTotal / totalValue
                            VStack {
                                Text("Displayed").font(.caption).foregroundColor(.secondary)
                                Text(displayedPercent.formatted(.percent.precision(.fractionLength(1))))
                                    .font(.title2).fontWeight(.bold)
                                    .blur(radius: privacyMode ? 6 : 0)
                            }
                            .position(x: geometry.frame(in: .local).midX, y: geometry.frame(in: .local).midY)
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: selectedAngleValue)
            }
            
            BlueChipWatermark()
        }
        .padding()
        .frame(minHeight: isExpanded ? 500 : 360, maxHeight: isExpanded ? .infinity : 360)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    func findItem(for value: Double) -> ChartDataItem {
        var cum = 0.0
        for item in filteredData {
            cum += item.value
            if value <= cum { return item }
        }
        return filteredData.last ?? ChartDataItem(name: "-", value: 0)
    }
}

// =========================================================================
// MARK: - GRAPHE 2 : STACKED BAR CHART INTERACTIF
// =========================================================================

struct ExposureStackedBarChart: View {
    let data: [StackedBarItem]
    let allRegions: [String]
    let title: String
    @Binding var privacyMode: Bool
    var isExpanded: Bool = false
    @Binding var expandedChart: ExposureChartZoomType?
    
    @State private var hiddenRegions: Set<String> = []
    @State private var hoveredTicker: String? = nil
    
    var allRegionCategories: [String] {
        var list = allRegions
        if !list.contains("Unknown") { list.append("Unknown") }
        return list
    }
    
    func color(for region: String) -> Color {
        if region == "Unknown" { return .gray.opacity(0.4) }
        let idx = allRegions.firstIndex(of: region) ?? 0
        return positionColors[idx % positionColors.count]
    }
    
    var filteredData: [StackedBarItem] {
        data.filter { !hiddenRegions.contains($0.region) }
    }

    var body: some View {
        VStack {
            HStack {
                if !isExpanded { Text(title).font(.headline).foregroundColor(.secondary) }
                Spacer()
                if !isExpanded {
                    Button(action: { expandedChart = .stackedBarExposure }) {
                        Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary)
                    }.buttonStyle(.plain)
                }
            }.padding(.bottom, 4)
            
            InteractiveLegendView(items: allRegionCategories, colorMap: color, hiddenItems: $hiddenRegions)
                .padding(.bottom, 8)
            
            if filteredData.isEmpty {
                Spacer(); Text("No data").foregroundColor(.secondary); Spacer()
            } else {
                Chart(filteredData) { item in
                    BarMark(
                        x: .value("Ticker", item.ticker),
                        y: .value("Percentage", item.percentage)
                    )
                    .foregroundStyle(color(for: item.region))
                    
                    if let hTicker = hoveredTicker, item.ticker == hTicker {
                        RuleMark(x: .value("Ticker", hTicker))
                            .foregroundStyle(Color.secondary.opacity(0.3))
                            .zIndex(-1)
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let location):
                                    if let ticker: String = proxy.value(atX: location.x) { hoveredTicker = ticker }
                                case .ended:
                                    hoveredTicker = nil
                                }
                            }
                        
                        if let hTicker = hoveredTicker {
                            if let xPosition = proxy.position(forX: hTicker) {
                                let tickerSegments = data.filter { $0.ticker == hTicker && !hiddenRegions.contains($0.region) }
                                    .sorted { $0.percentage > $1.percentage }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(hTicker).font(.caption.bold())
                                    ForEach(tickerSegments) { seg in
                                        HStack(spacing: 6) {
                                            Circle().fill(color(for: seg.region)).frame(width: 6, height: 6)
                                            Text("\(seg.region): \(seg.percentage.formatted(.number.precision(.fractionLength(1))))%")
                                                .font(.caption2)
                                                .blur(radius: privacyMode ? 6 : 0)
                                        }
                                    }
                                }
                                .padding(8)
                                .background(Color(NSColor.windowBackgroundColor).opacity(0.95))
                                .cornerRadius(8)
                                .shadow(radius: 4)
                                .position(x: max(70, min(geometry.size.width - 70, xPosition)), y: geometry.size.height / 3)
                            }
                        }
                    }
                }
                .chartLegend(.hidden)
                .chartYScale(domain: [0, 100])
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine(); AxisTick()
                        if let val = value.as(Double.self) {
                            AxisValueLabel("\(Int(val))%")
                        }
                    }
                }
            }
            
            HStack {
                Text("Hover over bars to inspect stock regions").font(.caption2).foregroundColor(.secondary)
                Spacer()
                BlueChipWatermark()
            }
        }
        .padding()
        .frame(minHeight: isExpanded ? 500 : 360, maxHeight: isExpanded ? .infinity : 360)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// =========================================================================
// MARK: - GRAPHE 3 : GLOBAL GEOGRAPHIC TREEMAP (NOUVEAU)
// =========================================================================

struct TreemapRegionNodeView: View {
    let node: TreemapRegionNode
    @Binding var hoveredRegion: String?
    @Binding var privacyMode: Bool
    
    // Couleur dynamique basée sur la taille
    func color(for percentage: Double) -> Color {
        if node.name == "Unknown" { return Color.gray.opacity(0.4) }
        // On intensifie le bleu selon la concentration
        let intensity = min(max(percentage * 2, 0.4), 1.0)
        return Color.blue.opacity(intensity)
    }
    
    var isHovered: Bool { hoveredRegion == node.name }
    
    var body: some View {
        ZStack {
            Rectangle()
                .fill(color(for: node.percentage))
                .border(Color(NSColor.windowBackgroundColor), width: 1.5)
            
            VStack(spacing: 4) {
                Text(node.name)
                    .font(.system(size: node.rect.width > 60 && node.rect.height > 40 ? 14 : 10, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                if node.rect.width > 80 && node.rect.height > 60 {
                    Text(node.percentage.formatted(.percent.precision(.fractionLength(1))))
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(1)
                        .blur(radius: privacyMode ? 6 : 0)
                }
            }
            
            // Tooltip au survol
            if isHovered {
                VStack {
                    Text(node.name).font(.caption.bold())
                    Text(node.percentage.formatted(.percent.precision(.fractionLength(1))))
                        .font(.caption2)
                        .blur(radius: privacyMode ? 6 : 0)
                }
                .padding(6)
                .background(Color(NSColor.windowBackgroundColor).opacity(0.95))
                .cornerRadius(6)
                .shadow(radius: 4)
                .zIndex(10)
            }
        }
        .frame(width: node.rect.width, height: node.rect.height)
        .offset(x: node.rect.minX, y: node.rect.minY)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .zIndex(isHovered ? 1 : 0)
        .onContinuousHover { phase in
            switch phase {
            case .active(_): hoveredRegion = node.name
            case .ended: hoveredRegion = nil
            }
        }
    }
}

struct GeographicTreemapChart: View {
    let data: [(name: String, percentage: Double)] // regionalExposure
    @Binding var privacyMode: Bool
    var isExpanded: Bool = false
    @Binding var expandedChart: ExposureChartZoomType?
    
    @State private var hoveredRegion: String? = nil
    
    // Algorithme de squarification simple pour créer le Treemap
    func layoutNodes(in rect: CGRect) -> [TreemapRegionNode] {
        var nodes: [TreemapRegionNode] = []
        var currentRect = rect
        var remainingWeight = data.reduce(0) { $0 + $1.percentage }
        
        for item in data {
            guard remainingWeight > 0 else { continue }
            let fraction = item.percentage / remainingWeight
            
            if currentRect.width > currentRect.height {
                let w = currentRect.width * CGFloat(fraction)
                // SUPPRESSION DE 'id: UUID(),' ICI
                nodes.append(TreemapRegionNode(name: item.name, percentage: item.percentage, rect: CGRect(x: currentRect.minX, y: currentRect.minY, width: w, height: currentRect.height)))
                currentRect = CGRect(x: currentRect.minX + w, y: currentRect.minY, width: currentRect.width - w, height: currentRect.height)
            } else {
                let h = currentRect.height * CGFloat(fraction)
                // SUPPRESSION DE 'id: UUID(),' ICI
                nodes.append(TreemapRegionNode(name: item.name, percentage: item.percentage, rect: CGRect(x: currentRect.minX, y: currentRect.minY, width: currentRect.width, height: h)))
                currentRect = CGRect(x: currentRect.minX, y: currentRect.minY + h, width: currentRect.width, height: currentRect.height - h)
            }
            remainingWeight -= item.percentage
        }
        return nodes
    }
    
    var body: some View {
        VStack {
            HStack {
                if !isExpanded { Text("Global Exposure Heatmap (Treemap)").font(.headline).foregroundColor(.secondary) }
                Spacer()
                if !isExpanded {
                    Button(action: { expandedChart = .geographicTreemap }) {
                        Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary)
                    }.buttonStyle(.plain)
                }
            }.padding(.bottom, 8)
            
            if data.isEmpty {
                Spacer(); Text("No regional data").foregroundColor(.secondary); Spacer()
            } else {
                GeometryReader { geo in
                    ZStack(alignment: .topLeading) {
                        ForEach(layoutNodes(in: CGRect(origin: .zero, size: geo.size))) { node in
                            TreemapRegionNodeView(node: node, hoveredRegion: $hoveredRegion, privacyMode: $privacyMode)
                        }
                    }
                }
            }
            
            HStack {
                Text("Block size represents portfolio weight").font(.caption2).foregroundColor(.secondary)
                Spacer()
                BlueChipWatermark()
            }.padding(.top, 4)
        }
        .padding()
        .frame(minHeight: isExpanded ? 500 : 360, maxHeight: isExpanded ? .infinity : 360)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// =========================================================================
// MARK: - GRAPHE 4 : SECTOR X GEOGRAPHY RISK MATRIX (NOUVEAU)
// =========================================================================

struct SectorRegionMatrixChart: View {
    let data: [SectorRegionItem]
    let allRegions: [String]
    @Binding var privacyMode: Bool
    var isExpanded: Bool = false
    @Binding var expandedChart: ExposureChartZoomType?
    
    @State private var hoveredSector: String? = nil
    @State private var hoveredRegion: String? = nil
    
    // On intensifie la couleur en fonction du poids dans le portefeuille (ex: 20% = très rouge/bleu)
    func color(for weight: Double) -> Color {
        if weight == 0 { return Color.gray.opacity(0.1) }
        let intensity = min(max(weight * 3, 0.2), 1.0)
        // Les fortes concentrations virent au rouge pour alerter sur le risque
        return weight > 0.15 ? Color.orange.opacity(intensity) : Color.blue.opacity(intensity)
    }
    
    var body: some View {
        VStack {
            HStack {
                if !isExpanded { Text("Sector × Geography Risk Matrix").font(.headline).foregroundColor(.secondary) }
                Spacer()
                if !isExpanded {
                    Button(action: { expandedChart = .sectorRegionMatrix }) {
                        Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary)
                    }.buttonStyle(.plain)
                }
            }.padding(.bottom, 8)
            
            if data.isEmpty {
                Spacer(); Text("No intersection data").foregroundColor(.secondary); Spacer()
            } else {
                Chart(data) { item in
                    RectangleMark(
                        x: .value("Region", item.region),
                        y: .value("Sector", item.sector)
                    )
                    .foregroundStyle(color(for: item.weight))
                    .annotation(position: .overlay) {
                        // N'affiche le texte que si la cellule est assez grande ou en mode Zoom
                        if isExpanded || data.count < 20 {
                            Text(item.weight.formatted(.percent.precision(.fractionLength(1))))
                                .font(.system(size: isExpanded ? 10 : 8))
                                .foregroundColor(item.weight > 0.15 ? .white : .primary)
                                .blur(radius: privacyMode ? 6 : 0)
                        }
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let location):
                                    if let region: String = proxy.value(atX: location.x),
                                       let sector: String = proxy.value(atY: location.y) {
                                        hoveredRegion = region
                                        hoveredSector = sector
                                    }
                                case .ended:
                                    hoveredRegion = nil
                                    hoveredSector = nil
                                }
                            }
                        
                        // Tooltip
                        if let hReg = hoveredRegion, let hSec = hoveredSector,
                           let item = data.first(where: { $0.region == hReg && $0.sector == hSec }) {
                            if let xPos = proxy.position(forX: hReg), let yPos = proxy.position(forY: hSec) {
                                VStack {
                                    Text("\(hSec) - \(hReg)").font(.caption.bold())
                                    Text("Portfolio Weight: \(item.weight.formatted(.percent.precision(.fractionLength(1))))")
                                        .font(.caption2)
                                        .blur(radius: privacyMode ? 6 : 0)
                                }
                                .padding(6).background(Color(NSColor.windowBackgroundColor).opacity(0.95)).cornerRadius(6).shadow(radius: 4)
                                .position(x: xPos, y: yPos - 30) // Affiche juste au-dessus de la cellule
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks { value in AxisValueLabel(centered: true) }
                }
                .chartYAxis {
                    AxisMarks { value in AxisValueLabel(centered: true) }
                }
            }
            
            HStack {
                Text("Orange indicates high risk concentration (>15%)").font(.caption2).foregroundColor(.secondary)
                Spacer()
                BlueChipWatermark()
            }.padding(.top, 4)
        }
        .padding()
        .frame(minHeight: isExpanded ? 500 : 360, maxHeight: isExpanded ? .infinity : 360)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}


// =========================================================================
// MARK: - FULLSCREEN ZOOM FOR EXPOSURE
// =========================================================================

struct ExposureFullScreenChartView: View {
    @Environment(\.dismiss) var dismiss
    let zoomType: ExposureChartZoomType
    
    let donutData: [ChartDataItem]
    let stackedBarData: [StackedBarItem]
    let allRegions: [String]
    let totalValue: Double
    
    let treemapData: [(name: String, percentage: Double)]
    let matrixData: [SectorRegionItem]
    let allRegionCategories: [String]
    
    @Binding var privacyMode: Bool

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text(titleForZoom).font(.title).fontWeight(.bold)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill").font(.title).foregroundColor(.secondary)
                }.buttonStyle(.plain)
            }
            
            switch zoomType {
            case .donutExposure:
                ExposureDonutChart(data: donutData, totalValue: totalValue, title: "Weighted Portfolio Exposure", privacyMode: $privacyMode, isExpanded: true, expandedChart: .constant(nil))
            case .stackedBarExposure:
                ExposureStackedBarChart(data: stackedBarData, allRegions: allRegions, title: "Detailed Breakdown by Stock", privacyMode: $privacyMode, isExpanded: true, expandedChart: .constant(nil))
            case .geographicTreemap:
                GeographicTreemapChart(data: treemapData, privacyMode: $privacyMode, isExpanded: true, expandedChart: .constant(nil))
            case .sectorRegionMatrix:
                SectorRegionMatrixChart(data: matrixData, allRegions: allRegionCategories, privacyMode: $privacyMode, isExpanded: true, expandedChart: .constant(nil))
            }
        }
        .padding(30)
        .frame(minWidth: 900, minHeight: 700)
    }
    
    var titleForZoom: String {
        switch zoomType {
        case .donutExposure: return "Weighted Portfolio Exposure"
        case .stackedBarExposure: return "Detailed Geographic Breakdown"
        case .geographicTreemap: return "Global Exposure Heatmap"
        case .sectorRegionMatrix: return "Sector × Geography Risk Matrix"
        }
    }
}

// =========================================================================
// MARK: - EDITOR SHEET FOR A STOCK
// =========================================================================

struct ExposureEditorSheet: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: PortfolioViewModel
    let position: Position
    
    @State private var segments: [RevenueSegment] = []
    
    @State private var newRegionName: String = ""
    @State private var newPercentage: Double? = nil
    @State private var newIsUSA: Bool = false
    
    var totalPercentage: Double {
        segments.reduce(0) { $0 + $1.percentage }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Revenue Segments for \(position.ticker)").font(.title2).fontWeight(.bold)
                Spacer()
                Button(action: { dismiss() }) { Image(systemName: "xmark.circle.fill").font(.title2).foregroundColor(.secondary) }.buttonStyle(.plain)
            }.padding()
            Divider()
            
            VStack(alignment: .leading, spacing: 16) {
                
                // STATUS BAR
                HStack {
                    Text("Total Identified:")
                    ProgressView(value: min(totalPercentage, 100.0), total: 100.0)
                        .tint(totalPercentage == 100 ? .green : (totalPercentage > 100 ? .red : .blue))
                    Text("\(Int(totalPercentage)) / 100%")
                        .fontWeight(.bold)
                        .foregroundColor(totalPercentage == 100 ? .green : (totalPercentage > 100 ? .red : .primary))
                }
                .padding()
                .background(Color(NSColor.windowBackgroundColor))
                .cornerRadius(8)
                
                // LISTE DES SEGMENTS
                if segments.isEmpty {
                    Text("No revenue data entered yet. Add segments below.")
                        .foregroundColor(.secondary).italic()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                } else {
                    List {
                        ForEach(segments) { segment in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(segment.regionName).fontWeight(.bold)
                                    Text(segment.isUSA ? "Classified as USA" : "Classified as Rest of World (ROW)")
                                        .font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                Text("\(segment.percentage.formatted(.number.precision(.fractionLength(1)))) %")
                                    .fontWeight(.bold).foregroundColor(.blue)
                                
                                Button(action: { segments.removeAll { $0.id == segment.id } }) {
                                    Image(systemName: "trash.circle.fill").foregroundColor(.red)
                                }.buttonStyle(.plain).padding(.leading, 8)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .frame(height: 200)
                    .cornerRadius(8)
                }
                
                Divider()
                
                // AJOUTER UN NOUVEAU SEGMENT
                Text("Add New Region").font(.headline)
                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading) {
                        Text("Region Name (e.g. EMEA, Asia, USA)")
                        TextField("Region", text: $newRegionName).textFieldStyle(.roundedBorder)
                    }
                    VStack(alignment: .leading) {
                        Text("Revenue %")
                        TextField("%", value: $newPercentage, format: .number).textFieldStyle(.roundedBorder).frame(width: 80)
                    }
                    VStack(alignment: .center) {
                        Text("Is USA?")
                        Toggle("", isOn: $newIsUSA).labelsHidden()
                    }.padding(.bottom, 4)
                    
                    Button(action: addSegment) {
                        Text("Add").fontWeight(.bold)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newRegionName.isEmpty || (newPercentage ?? 0) <= 0)
                }
                
            }
            .padding()
            
            Divider()
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save Exposures") {
                    viewModel.updateRevenueExposures(for: position.id, exposures: segments)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(totalPercentage > 100.0)
            }.padding()
        }
        .frame(width: 550, height: 600)
        .onAppear {
            self.segments = position.revenueExposures ?? []
        }
    }
    
    private func addSegment() {
        guard !newRegionName.isEmpty, let pct = newPercentage, pct > 0 else { return }
        segments.append(RevenueSegment(regionName: newRegionName, isUSA: newIsUSA, percentage: pct))
        
        newRegionName = ""
        newPercentage = nil
        newIsUSA = false
    }
}
