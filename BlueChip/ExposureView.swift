import SwiftUI
import Charts

// =========================================================================
// MARK: - ENUMS & MODELS FOR EXPOSURE
// =========================================================================

enum ExposureChartZoomType: String, Identifiable {
    case donutExposure, stackedBarExposure
    var id: String { self.rawValue }
}

struct StackedBarItem: Identifiable {
    let id = UUID()
    let ticker: String
    let region: String
    let percentage: Double
}

// =========================================================================
// MARK: - MAIN EXPOSURE VIEW
// =========================================================================

struct ExposureView: View {
    @ObservedObject var viewModel: PortfolioViewModel
    @Binding var privacyMode: Bool
    
    @State private var editingPosition: Position? = nil
    @State private var chartToZoom: ExposureChartZoomType? = nil
    
    // Extraction dynamique de toutes les régions uniques saisies dans le portefeuille
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

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 24) {
                
                // HEADER
                HStack {
                    Text("Geographic Revenue Exposure").font(.title).fontWeight(.bold)
                    Spacer()
                }
                
                // 1. DASHBOARD
                HStack(spacing: 16) {
                    let totalVal = viewModel.totalValue
                    let usaPct = totalVal > 0 ? (usaWeightedValue / totalVal) : 0
                    let rowPct = totalVal > 0 ? (rowWeightedValue / totalVal) : 0
                    let unknownPct = totalVal > 0 ? (unknownWeightedValue / totalVal) : 0
                    let topRegionStr = usaPct >= rowPct ? "USA (\(usaPct.formatted(.percent.precision(.fractionLength(1)))))" : "ROW (\(rowPct.formatted(.percent.precision(.fractionLength(1)))))"
                    
                    DashboardCard(title: "Portfolio Weighted USA Exposure", value: usaPct.formatted(.percent.precision(.fractionLength(1))), titleIcon: "star.fill", privacyMode: .constant(false))
                    DashboardCard(title: "Portfolio Weighted ROW Exposure", value: rowPct.formatted(.percent.precision(.fractionLength(1))), titleIcon: "globe.europe.africa.fill", privacyMode: .constant(false))
                    DashboardCard(title: "Unassigned Revenue Share", value: unknownPct.formatted(.percent.precision(.fractionLength(1))), titleIcon: "questionmark.circle.fill", privacyMode: .constant(false))
                    DashboardCard(title: "Primary Market Target", value: topRegionStr, titleIcon: "chart.bar.fill", privacyMode: .constant(false))
                }
                
                // 2. TABLEAU D'ÉDITION PAR DOUBLE-CLIC (AVEC COLONNES DYNAMIQUES PAR RÉGION)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Revenue Segmentation by Stock").font(.title2).fontWeight(.bold)
                        Spacer()
                        Text("(Double-click on any row to edit regions)").font(.caption).foregroundColor(.secondary).italic()
                    }
                    
                    ScrollView(.horizontal, showsIndicators: true) {
                        VStack(spacing: 0) {
                            // Header du Tableau
                            HStack(spacing: 12) {
                                Text("Ticker").fontWeight(.bold).frame(width: 80, alignment: .leading)
                                Text("Known %").fontWeight(.bold).frame(width: 110, alignment: .leading)
                                
                                ForEach(allRegions, id: \.self) { region in
                                    Text(region).fontWeight(.bold).frame(width: 90, alignment: .trailing)
                                }
                            }
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(Color(NSColor.windowBackgroundColor))
                            
                            Divider()
                            
                            // Rows du Tableau
                            if viewModel.positions.isEmpty {
                                Text("No positions in portfolio.").foregroundColor(.secondary).padding(20)
                            } else {
                                ScrollView(.vertical) {
                                    LazyVStack(spacing: 0) {
                                        ForEach(viewModel.positions) { pos in
                                            let exposures = pos.revenueExposures ?? []
                                            let totalKnown = exposures.reduce(0) { $0 + $1.percentage }
                                            
                                            HStack(spacing: 12) {
                                                // Ticker
                                                Text(pos.ticker).fontWeight(.bold).frame(width: 80, alignment: .leading)
                                                
                                                // Known %
                                                HStack {
                                                    ProgressView(value: min(totalKnown, 100.0), total: 100.0)
                                                        .tint(totalKnown >= 100 ? .green : .orange)
                                                        .frame(width: 50)
                                                    Text("\(Int(totalKnown))%")
                                                        .font(.caption).fontWeight(.bold)
                                                        .foregroundColor(totalKnown >= 100 ? .green : .orange)
                                                }
                                                .frame(width: 110, alignment: .leading)
                                                
                                                // Colonnes Dynamiques de chaque région
                                                ForEach(allRegions, id: \.self) { region in
                                                    let pct = exposures.first(where: { $0.regionName == region })?.percentage
                                                    Text(pct != nil ? "\(pct!.formatted(.number.precision(.fractionLength(1))))%" : "/")
                                                        .frame(width: 90, alignment: .trailing)
                                                        .foregroundColor(pct != nil ? .primary : .secondary.opacity(0.5))
                                                }
                                            }
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 10)
                                            .contentShape(Rectangle())
                                            // DOUBLE-CLIC POUR ÉDITER L'ACTION
                                            .onTapGesture(count: 2) {
                                                editingPosition = pos
                                            }
                                            
                                            Divider()
                                        }
                                    }
                                }
                            }
                        }
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                
                // 3. LES 2 GRAPHIQUES INTERACTIFS (SURVOL, LÉGENDE CLIQUABLE, ZOOM, WATERMARK)
                HStack(alignment: .top, spacing: 24) {
                    ExposureDonutChart(data: donutData, title: "Weighted Portfolio Exposure (USA vs ROW)", expandedChart: $chartToZoom)
                    ExposureStackedBarChart(data: stackedBarData, allRegions: allRegions, title: "Detailed Geographic Breakdown by Stock", expandedChart: $chartToZoom)
                }
            }
            .padding()
        }
        .sheet(item: $editingPosition) { pos in
            ExposureEditorSheet(viewModel: viewModel, position: pos)
        }
        .sheet(item: $chartToZoom) { type in
            ExposureFullScreenChartView(
                zoomType: type,
                donutData: donutData,
                stackedBarData: stackedBarData,
                allRegions: allRegions
            )
        }
    }
}

// =========================================================================
// MARK: - GRAPHE 1 : DONUT CHART INTERACTIF (USA VS ROW)
// =========================================================================

struct ExposureDonutChart: View {
    let data: [ChartDataItem]
    let title: String
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
            
            if filteredData.isEmpty {
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
                            VStack {
                                Text(item.name).font(.headline).lineLimit(1)
                                Text(item.value.formatted(.currency(code: "EUR").precision(.fractionLength(0))))
                                    .font(.subheadline).foregroundColor(.secondary)
                            }
                            .position(x: geometry.frame(in: .local).midX, y: geometry.frame(in: .local).midY)
                        } else {
                            let total = filteredData.reduce(0) { $0 + $1.value }
                            VStack {
                                Text("Total Portfolio").font(.caption).foregroundColor(.secondary)
                                Text(total.formatted(.currency(code: "EUR").precision(.fractionLength(0))))
                                    .font(.headline).fontWeight(.bold)
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
// MARK: - GRAPHE 2 : STACKED BAR CHART INTERACTIF (PAR RÉGION)
// =========================================================================

struct ExposureStackedBarChart: View {
    let data: [StackedBarItem]
    let allRegions: [String]
    let title: String
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
                            .foregroundStyle(.secondary.opacity(0.3))
                    }
                }
                .chartLegend(.hidden)
                .chartXSelection(value: $hoveredTicker)
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
// MARK: - FULLSCREEN ZOOM FOR EXPOSURE
// =========================================================================

struct ExposureFullScreenChartView: View {
    @Environment(\.dismiss) var dismiss
    let zoomType: ExposureChartZoomType
    let donutData: [ChartDataItem]
    let stackedBarData: [StackedBarItem]
    let allRegions: [String]

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text(zoomType == .donutExposure ? "Weighted Portfolio Exposure" : "Detailed Geographic Breakdown").font(.title).fontWeight(.bold)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill").font(.title).foregroundColor(.secondary)
                }.buttonStyle(.plain)
            }
            
            switch zoomType {
            case .donutExposure:
                ExposureDonutChart(data: donutData, title: "Weighted Portfolio Exposure", isExpanded: true, expandedChart: .constant(nil))
            case .stackedBarExposure:
                ExposureStackedBarChart(data: stackedBarData, allRegions: allRegions, title: "Detailed Breakdown by Stock", isExpanded: true, expandedChart: .constant(nil))
            }
        }
        .padding(30)
        .frame(minWidth: 900, minHeight: 700)
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
    
    // Nouveaux champs pour l'ajout
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
                .disabled(totalPercentage > 100.0) // Empêche de sauvegarder si > 100%
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
        
        // Reset fields
        newRegionName = ""
        newPercentage = nil
        newIsUSA = false
    }
}
