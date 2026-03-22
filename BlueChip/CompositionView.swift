import SwiftUI
import Charts

enum ChartZoomType: Identifiable { case positions, countries, sectors, marketCaps, priceCompare, roiCombo, scatter, valueSource, heatmap, dailyRoi; var id: Int { self.hashValue } }

struct ModernDonutChart: View {
    let data: [ChartDataItem]; let title: String; let zoomType: ChartZoomType; let palette: [Color]; var isExpanded: Bool = false
    @Binding var expandedChart: ChartZoomType?
    @State private var selectedAngleValue: Double? = nil; @State private var hiddenItems: Set<String> = []
    
    func color(for name: String) -> Color { if let idx = data.firstIndex(where: { $0.name == name }) { return palette[idx % palette.count] }; return .gray }
    var filteredData: [ChartDataItem] { data.filter { !hiddenItems.contains($0.name) } }
    
    var body: some View {
        VStack {
            HStack {
                if !isExpanded { Text(title).font(.headline).foregroundColor(.secondary) }
                Spacer()
                if !isExpanded { Button(action: { expandedChart = zoomType }) { Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary) }.buttonStyle(.plain) }
            }.padding(.bottom, 4)
            InteractiveLegendView(items: data.map { $0.name }, colorMap: color, hiddenItems: $hiddenItems).padding(.bottom, 8)
            if filteredData.isEmpty { Spacer(); Text("No data").foregroundColor(.secondary); Spacer() } else {
                Chart(filteredData) { item in SectorMark(angle: .value("Value", item.value), innerRadius: .ratio(0.65), angularInset: 1.5).foregroundStyle(color(for: item.name)).cornerRadius(4) }
                    .chartLegend(.hidden).chartAngleSelection(value: $selectedAngleValue).chartBackground { proxy in
                    GeometryReader { geometry in
                        if let value = selectedAngleValue {
                            let item = findItem(for: value)
                            VStack { Text(item.name).font(.headline); Text(item.value.formatted(.currency(code: "EUR"))).font(.subheadline).foregroundColor(.secondary) }.position(x: geometry.frame(in: .local).midX, y: geometry.frame(in: .local).midY)
                        }
                    }
                }.animation(.easeInOut(duration: 0.2), value: selectedAngleValue)
            }
            BlueChipWatermark()
        }.padding().frame(minHeight: 360, maxHeight: isExpanded ? .infinity : 360).background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    func findItem(for value: Double) -> ChartDataItem { var cum = 0.0; for item in filteredData { cum += item.value; if value <= cum { return item } }; return filteredData.last! }
}

struct PRUPriceChart: View {
    @ObservedObject var viewModel: PortfolioViewModel
    let data: [PriceCompareItem]; var isExpanded: Bool = false; @Binding var expandedChart: ChartZoomType?
    @State private var hiddenCategories: Set<String> = []; @State private var hiddenTickers: Set<String> = []; @State private var hoveredTicker: String? = nil
    
    var uniqueTickers: [String] { Array(Set(data.map { $0.ticker })).sorted() }
    var filteredData: [PriceCompareItem] { data.filter { !hiddenCategories.contains($0.category) && !hiddenTickers.contains($0.ticker) } }
    
    var body: some View {
        VStack {
            HStack {
                if !isExpanded { Text("Avg Cost vs Current Price").font(.headline).foregroundColor(.secondary) }
                Spacer()
                if !isExpanded { Button(action: { expandedChart = .priceCompare }) { Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary) }.buttonStyle(.plain) }
            }.padding(.bottom, 4)
            VStack(spacing: 4) {
                HStack(spacing: 16) {
                    Button(action: { withAnimation { if hiddenCategories.contains("Avg Cost") { hiddenCategories.remove("Avg Cost") } else { hiddenCategories.insert("Avg Cost") } } }) {
                        HStack(spacing: 6) { Circle().fill(Color.gray.opacity(0.4)).frame(width: 10, height: 10); Text("Avg Cost").font(.caption).foregroundColor(hiddenCategories.contains("Avg Cost") ? .secondary : .primary) }
                    }.buttonStyle(.plain).opacity(hiddenCategories.contains("Avg Cost") ? 0.4 : 1.0)
                    
                    Button(action: { withAnimation { if hiddenCategories.contains("Current") { hiddenCategories.remove("Current") } else { hiddenCategories.insert("Current") } } }) {
                        HStack(spacing: 6) { Circle().fill(Color.gray).frame(width: 10, height: 10); Text("Current Price").font(.caption).foregroundColor(hiddenCategories.contains("Current") ? .secondary : .primary) }
                    }.buttonStyle(.plain).opacity(hiddenCategories.contains("Current") ? 0.4 : 1.0)
                }
                InteractiveLegendView(items: uniqueTickers, colorMap: { viewModel.color(for: $0) }, hiddenItems: $hiddenTickers)
            }.padding(.bottom, 8)
            if filteredData.isEmpty { Spacer(); Text("No data").foregroundColor(.secondary); Spacer() } else {
                Chart(filteredData) { item in
                    BarMark(x: .value("Ticker", item.ticker), y: .value("Price", item.value)).foregroundStyle(viewModel.color(for: item.ticker).opacity(item.category == "Avg Cost" ? 0.4 : 1.0)).position(by: .value("Category", item.category)).cornerRadius(4)
                        .annotation(position: .top) { if hoveredTicker == item.ticker { Text(item.value.formatted(.currency(code: "EUR"))).font(.system(size: 9, weight: .bold)).foregroundColor(.secondary) } }
                }.chartLegend(.hidden).chartXSelection(value: $hoveredTicker)
            }
            BlueChipWatermark()
        }.padding().frame(minHeight: 360, maxHeight: isExpanded ? .infinity : 360).background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

struct ROIComboChart: View {
    @ObservedObject var viewModel: PortfolioViewModel
    let positions: [Position]; var isExpanded: Bool = false; @Binding var expandedChart: ChartZoomType?
    @State private var hiddenTickers: Set<String> = []; @State private var hiddenMetrics: Set<String> = []; @State private var hoveredTicker: String? = nil
    
    var uniqueTickers: [String] { positions.map { $0.ticker }.sorted() }
    var filteredPositions: [Position] { positions.filter { !hiddenTickers.contains($0.ticker) } }
    
    var body: some View {
        VStack {
            HStack {
                if !isExpanded { Text("Return on Investment (P/L)").font(.headline).foregroundColor(.secondary) }
                Spacer()
                if !isExpanded { Button(action: { expandedChart = .roiCombo }) { Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary) }.buttonStyle(.plain) }
            }.padding(.bottom, 4)
            VStack(spacing: 4) {
                HStack(spacing: 16) {
                    Button(action: { withAnimation { if hiddenMetrics.contains("Euros") { hiddenMetrics.remove("Euros") } else { hiddenMetrics.insert("Euros") } } }) {
                        HStack(spacing: 6) { Rectangle().fill(Color.gray.opacity(hiddenMetrics.contains("Euros") ? 0.3 : 0.6)).frame(width: 12, height: 10).cornerRadius(2); Text("P/L (€)").font(.caption).foregroundColor(hiddenMetrics.contains("Euros") ? .secondary : .primary) }
                    }.buttonStyle(.plain)
                    Button(action: { withAnimation { if hiddenMetrics.contains("Percent") { hiddenMetrics.remove("Percent") } else { hiddenMetrics.insert("Percent") } } }) {
                        HStack(spacing: 6) { Circle().stroke(Color.gray, lineWidth: 2).frame(width: 10, height: 10); Text("P/L (%)").font(.caption).foregroundColor(hiddenMetrics.contains("Percent") ? .secondary : .primary) }
                    }.buttonStyle(.plain).opacity(hiddenMetrics.contains("Percent") ? 0.4 : 1.0)
                }
                InteractiveLegendView(items: uniqueTickers, colorMap: { viewModel.color(for: $0) }, hiddenItems: $hiddenTickers)
            }.padding(.bottom, 8)
            if filteredPositions.isEmpty { Spacer(); Text("No data").foregroundColor(.secondary); Spacer() } else {
                Chart {
                    ForEach(filteredPositions) { pos in
                        if !hiddenMetrics.contains("Euros") {
                            BarMark(x: .value("Ticker", pos.ticker), y: .value("P/L (€)", pos.roiValue)).foregroundStyle(pos.roiValue >= 0 ? Color.green.opacity(0.7) : Color.red.opacity(0.7)).cornerRadius(4)
                                .annotation(position: pos.roiValue >= 0 ? .top : .bottom) { if hoveredTicker == pos.ticker { Text(pos.roiValue.formatted(.currency(code: "EUR"))).font(.system(size: 9, weight: .bold)).padding(2).background(Color(NSColor.windowBackgroundColor).opacity(0.8)).cornerRadius(2) } }
                        }
                        if !hiddenMetrics.contains("Percent") {
                            LineMark(x: .value("Ticker", pos.ticker), y: .value("P/L (%)", pos.roiValue)).foregroundStyle(Color.primary.opacity(0.6)).interpolationMethod(.monotone)
                            PointMark(x: .value("Ticker", pos.ticker), y: .value("P/L (%)", pos.roiValue)).foregroundStyle(Color.primary)
                                .annotation(position: pos.roiValue >= 0 ? .top : .bottom) { if hoveredTicker == pos.ticker { Text(pos.roiPercent.formatted(.percent.precision(.fractionLength(1)))).font(.system(size: 9, weight: .bold)).padding(2).background(Color(NSColor.windowBackgroundColor).opacity(0.8)).cornerRadius(2).offset(y: pos.roiValue >= 0 ? -15 : 15) } }
                        }
                    }
                }.chartLegend(.hidden).chartXSelection(value: $hoveredTicker)
            }
            BlueChipWatermark()
        }.padding().frame(minHeight: 360, maxHeight: isExpanded ? .infinity : 360).background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

struct ModernScatterPlotChart: View {
    @ObservedObject var viewModel: PortfolioViewModel
    let data: [ScatterItem]; var isExpanded: Bool = false; @Binding var expandedChart: ChartZoomType?
    @State private var hiddenTickers: Set<String> = []; @State private var hoveredWeight: Double? = nil
    
    var uniqueTickers: [String] { data.map { $0.ticker }.sorted() }
    var filteredData: [ScatterItem] { data.filter { !hiddenTickers.contains($0.ticker) } }
    var hoveredItem: ScatterItem? { guard let w = hoveredWeight else { return nil }; return filteredData.min(by: { abs($0.weight - w) < abs($1.weight - w) }) }
    
    var xDomain: [Double] { guard let maxW = filteredData.map({$0.weight}).max() else { return [0, 0.1] }; return [0, maxW * 1.1] }
    var yDomain: [Double] { guard let maxR = filteredData.map({$0.roi}).max() else { return [0, 0.1] }; return [0, maxR * 1.1] }
    
    var body: some View {
        VStack {
            HStack {
                if !isExpanded { Text("Portfolio Weight vs Unrealized Performance").font(.headline).foregroundColor(.secondary) }
                Spacer()
                if !isExpanded { Button(action: { expandedChart = .scatter }) { Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary) }.buttonStyle(.plain) }
            }.padding(.bottom, 4)
            InteractiveLegendView(items: uniqueTickers, colorMap: { viewModel.color(for: $0) }, hiddenItems: $hiddenTickers).padding(.bottom, 8)
            if filteredData.isEmpty { Spacer(); Text("No data").foregroundColor(.secondary); Spacer() } else {
                Chart(filteredData) { item in
                    PointMark(x: .value("Weight", item.weight), y: .value("ROI", item.roi)).foregroundStyle(viewModel.color(for: item.ticker)).symbolSize(100)
                        .annotation(position: .top, alignment: .center) {
                            if hoveredItem?.id == item.id {
                                VStack {
                                    Text(item.ticker).font(.system(size: 10, weight: .bold))
                                    Text("\(item.weight.formatted(.percent.precision(.fractionLength(1)))) | \(item.roi.formatted(.percent.precision(.fractionLength(1))))").font(.system(size: 9))
                                }.padding(4).background(Color(NSColor.windowBackgroundColor).opacity(0.9)).cornerRadius(4)
                            }
                        }
                }.chartLegend(.hidden).chartXScale(domain: xDomain).chartYScale(domain: yDomain)
                 .chartXAxis { AxisMarks { value in AxisGridLine(); AxisTick(); if let v = value.as(Double.self) { AxisValueLabel(v.formatted(.percent.precision(.fractionLength(0)))) } } }
                 .chartYAxis { AxisMarks { value in AxisGridLine(); AxisTick(); if let v = value.as(Double.self) { AxisValueLabel(v.formatted(.percent.precision(.fractionLength(0)))) } } }
                 .chartXSelection(value: $hoveredWeight)
            }
            BlueChipWatermark()
        }.padding().frame(minHeight: 360, maxHeight: isExpanded ? .infinity : 360).background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

struct ModernValueSourceChart: View {
    let data: [ValueSourceItem]; var isExpanded: Bool = false; @Binding var expandedChart: ChartZoomType?
    @State private var selectedAngleValue: Double? = nil; @State private var hiddenItems: Set<String> = []
    
    func color(for name: String) -> Color { name == "Total Invested" ? .blue : .green }
    var filteredData: [ValueSourceItem] { data.filter { !hiddenItems.contains($0.category) } }
    
    var body: some View {
        VStack {
            HStack {
                if !isExpanded { Text("Source of Total Stock Value").font(.headline).foregroundColor(.secondary) }
                Spacer()
                if !isExpanded { Button(action: { expandedChart = .valueSource }) { Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary) }.buttonStyle(.plain) }
            }.padding(.bottom, 4)
            InteractiveLegendView(items: data.map { $0.category }, colorMap: color, hiddenItems: $hiddenItems).padding(.bottom, 8)
            if filteredData.isEmpty { Spacer(); Text("No data").foregroundColor(.secondary); Spacer() } else {
                Chart(filteredData) { item in
                    SectorMark(angle: .value("Value", item.value), innerRadius: .ratio(0.65), angularInset: 1.5).foregroundStyle(color(for: item.category)).cornerRadius(4)
                }.chartLegend(.hidden).chartAngleSelection(value: $selectedAngleValue).chartBackground { proxy in
                    GeometryReader { geometry in
                        if let value = selectedAngleValue {
                            let item = findItem(for: value)
                            VStack { Text(item.category).font(.headline).foregroundColor(.secondary).lineLimit(1).minimumScaleFactor(0.5); Text(item.value.formatted(.currency(code: "EUR").precision(.fractionLength(0)))).font(.title3).fontWeight(.bold) }.position(x: geometry.frame(in: .local).midX, y: geometry.frame(in: .local).midY)
                        } else {
                            let total = filteredData.reduce(0) { $0 + $1.value }
                            VStack { Text("Stock Value").font(.subheadline).foregroundColor(.secondary); Text(total.formatted(.currency(code: "EUR").precision(.fractionLength(0)))).font(.title2).fontWeight(.bold) }.position(x: geometry.frame(in: .local).midX, y: geometry.frame(in: .local).midY)
                        }
                    }
                }.animation(.easeInOut(duration: 0.2), value: selectedAngleValue)
            }
            BlueChipWatermark()
        }.padding().frame(minHeight: 360, maxHeight: isExpanded ? .infinity : 360).background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    func findItem(for value: Double) -> ValueSourceItem { var cum = 0.0; for item in filteredData { cum += item.value; if value <= cum { return item } }; return filteredData.last! }
}

struct HeatmapNodeView: View {
    let node: TreemapNode
    @Binding var hoveredTicker: String?
    
    func color(for roi: Double) -> Color {
        if roi == 0 { return Color.gray.opacity(0.4) }
        let intensity = min(max(abs(roi) / 0.5, 0.3), 1.0)
        return roi > 0 ? Color.green.opacity(intensity) : Color.red.opacity(intensity)
    }
    var isHovered: Bool { hoveredTicker == node.position.ticker }
    
    var body: some View {
        ZStack {
            Rectangle().fill(color(for: node.position.roiPercent)).border(Color(NSColor.windowBackgroundColor), width: 1.5)
            VStack(spacing: 4) {
                Text(node.position.ticker).font(.system(size: node.rect.width > 45 && node.rect.height > 35 ? 14 : 8, weight: .bold)).foregroundColor(.white).lineLimit(1)
                if node.rect.width > 60 && node.rect.height > 50 { Text(node.position.roiPercent.formatted(.percent.precision(.fractionLength(1)))).font(.caption).foregroundColor(.white.opacity(0.9)).lineLimit(1) }
            }
            if isHovered {
                VStack {
                    Text(node.position.ticker).font(.caption.bold())
                    Text(node.position.currentValueEUR.formatted(.currency(code: "EUR"))).font(.caption2)
                    Text("Daily: \(node.position.dailyROIValue.formatted(.currency(code: "EUR").sign(strategy: .always())))").font(.caption2)
                }.padding(6).background(Color(NSColor.windowBackgroundColor).opacity(0.95)).cornerRadius(6).shadow(radius: 4).zIndex(10)
            }
        }.frame(width: node.rect.width, height: node.rect.height).offset(x: node.rect.minX, y: node.rect.minY).scaleEffect(isHovered ? 1.02 : 1.0).zIndex(isHovered ? 1 : 0).onContinuousHover { phase in
            switch phase { case .active(_): hoveredTicker = node.position.ticker; case .ended: hoveredTicker = nil }
        }
    }
}

struct PerformanceHeatmap: View {
    let positions: [Position]; var isExpanded: Bool = false; @Binding var expandedChart: ChartZoomType?
    @State private var hoveredTicker: String? = nil
    
    var totalValue: Double { positions.reduce(0) { $0 + $1.currentValueEUR } }
    var sortedPositions: [Position] { positions.sorted { $0.currentValueEUR > $1.currentValueEUR } }
    
    func layoutNodes(in rect: CGRect) -> [TreemapNode] {
        var nodes: [TreemapNode] = []; var currentRect = rect; var remainingWeight = totalValue
        for item in sortedPositions {
            guard remainingWeight > 0 else { continue }
            let fraction = item.currentValueEUR / remainingWeight
            if currentRect.width > currentRect.height {
                let w = currentRect.width * CGFloat(fraction)
                nodes.append(TreemapNode(position: item, rect: CGRect(x: currentRect.minX, y: currentRect.minY, width: w, height: currentRect.height)))
                currentRect = CGRect(x: currentRect.minX + w, y: currentRect.minY, width: currentRect.width - w, height: currentRect.height)
            } else {
                let h = currentRect.height * CGFloat(fraction)
                nodes.append(TreemapNode(position: item, rect: CGRect(x: currentRect.minX, y: currentRect.minY, width: currentRect.width, height: h)))
                currentRect = CGRect(x: currentRect.minX, y: currentRect.minY + h, width: currentRect.width, height: currentRect.height - h)
            }
            remainingWeight -= item.currentValueEUR
        }
        return nodes
    }
    
    var body: some View {
        VStack {
            HStack {
                if !isExpanded { Text("Performance Heatmap").font(.headline).foregroundColor(.secondary) }
                Spacer()
                if !isExpanded { Button(action: { expandedChart = .heatmap }) { Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary) }.buttonStyle(.plain) }
            }.padding(.bottom, 8)
            if positions.isEmpty { Spacer(); Text("No data").foregroundColor(.secondary); Spacer() } else {
                GeometryReader { geo in ZStack(alignment: .topLeading) { ForEach(layoutNodes(in: CGRect(origin: .zero, size: geo.size))) { node in HeatmapNodeView(node: node, hoveredTicker: $hoveredTicker) } } }
            }
            BlueChipWatermark()
        }.padding().frame(minHeight: 360, maxHeight: isExpanded ? .infinity : 360).background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

struct DailyROIChart: View {
    @ObservedObject var viewModel: PortfolioViewModel
    let positions: [Position]; var isExpanded: Bool = false; @Binding var expandedChart: ChartZoomType?
    @State private var hiddenTickers: Set<String> = []; @State private var hoveredTicker: String? = nil
    
    var uniqueTickers: [String] { positions.map { $0.ticker }.sorted() }
    var filteredPositions: [Position] { positions.filter { !hiddenTickers.contains($0.ticker) } }
    
    var body: some View {
        VStack {
            HStack {
                if !isExpanded { Text("Daily P/L by Holding Period").font(.headline).foregroundColor(.secondary) }
                Spacer()
                if !isExpanded { Button(action: { expandedChart = .dailyRoi }) { Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary) }.buttonStyle(.plain) }
            }.padding(.bottom, 4)
            InteractiveLegendView(items: uniqueTickers, colorMap: { viewModel.color(for: $0) }, hiddenItems: $hiddenTickers).padding(.bottom, 8)
            
            if filteredPositions.isEmpty { Spacer(); Text("No data").foregroundColor(.secondary); Spacer() } else {
                Chart(filteredPositions) { pos in
                    BarMark(x: .value("Ticker", pos.ticker), y: .value("Daily P/L", pos.dailyROIValue))
                        .foregroundStyle(pos.dailyROIValue >= 0 ? Color.green.opacity(0.7) : Color.red.opacity(0.7)).cornerRadius(4)
                        .annotation(position: pos.dailyROIValue >= 0 ? .top : .bottom) {
                            if hoveredTicker == pos.ticker { Text(pos.dailyROIValue.formatted(.currency(code: "EUR").sign(strategy: .always()))).font(.system(size: 9, weight: .bold)).padding(2).background(Color(NSColor.windowBackgroundColor).opacity(0.8)).cornerRadius(2) }
                        }
                }.chartLegend(.hidden).chartXSelection(value: $hoveredTicker)
            }
            BlueChipWatermark()
        }.padding().frame(minHeight: 360, maxHeight: isExpanded ? .infinity : 360).background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

struct FullScreenChartView: View {
    @Environment(\.dismiss) var dismiss; let zoomType: ChartZoomType; @ObservedObject var viewModel: PortfolioViewModel
    var body: some View {
        VStack(spacing: 20) {
            HStack { Text(titleForZoom).font(.title).fontWeight(.bold); Spacer(); Button(action: { dismiss() }) { Image(systemName: "xmark.circle.fill").font(.title).foregroundColor(.secondary) }.buttonStyle(.plain) }
            switch zoomType {
            case .positions: ModernDonutChart(data: viewModel.allocationByPosition, title: "Weight by Position", zoomType: zoomType, palette: positionColors, isExpanded: true, expandedChart: .constant(nil))
            case .countries: ModernDonutChart(data: viewModel.allocationByCountry, title: "Geographic Exposure", zoomType: zoomType, palette: geographicColors, isExpanded: true, expandedChart: .constant(nil))
            case .sectors: ModernDonutChart(data: viewModel.allocationBySector, title: "Sector Allocation", zoomType: zoomType, palette: sectorColors, isExpanded: true, expandedChart: .constant(nil))
            case .marketCaps: ModernDonutChart(data: viewModel.allocationByMarketCap, title: "Market Cap Allocation", zoomType: zoomType, palette: marketCapColors, isExpanded: true, expandedChart: .constant(nil))
            case .priceCompare: PRUPriceChart(viewModel: viewModel, data: viewModel.priceComparisonData, isExpanded: true, expandedChart: .constant(nil))
            case .roiCombo: ROIComboChart(viewModel: viewModel, positions: viewModel.positions, isExpanded: true, expandedChart: .constant(nil))
            case .scatter: ModernScatterPlotChart(viewModel: viewModel, data: viewModel.scatterData, isExpanded: true, expandedChart: .constant(nil))
            case .valueSource: ModernValueSourceChart(data: viewModel.valueSourceDonutData, isExpanded: true, expandedChart: .constant(nil))
            case .heatmap: PerformanceHeatmap(positions: viewModel.positions, isExpanded: true, expandedChart: .constant(nil))
            case .dailyRoi: DailyROIChart(viewModel: viewModel, positions: viewModel.positions, isExpanded: true, expandedChart: .constant(nil))
            }
        }.padding(30).frame(minWidth: 900, minHeight: 700)
    }
    var titleForZoom: String {
        switch zoomType {
        case .positions: return "Weight by Position"; case .countries: return "Geographic Exposure"; case .sectors: return "Sector Allocation"; case .marketCaps: return "Market Cap Allocation"
        case .priceCompare: return "Avg Cost vs Current Price"; case .roiCombo: return "Return on Investment (P/L)"; case .scatter: return "Portfolio Weight vs Unrealized Performance"
        case .valueSource: return "Source of Total Stock Value"; case .heatmap: return "Performance Heatmap"; case .dailyRoi: return "Daily P/L by Holding Period"
        }
    }
}

struct CompositionTabView: View {
    @ObservedObject var viewModel: PortfolioViewModel
    @Binding var privacyMode: Bool
    
    @State private var selection: Set<Position.ID> = []
    @State private var showCashSheet = false; @State private var showInvestedSheet = false
    @State private var showGoalSheet = false; @State private var positionToEdit: Position? = nil; @State private var chartToZoom: ChartZoomType? = nil
    
    let tableFrameHeight: CGFloat = 340
    
    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 24) {
                // --- DASHBOARD ---
                VStack(spacing: 16) {
                    HStack(spacing: 16) {
                        Button(action: { showCashSheet = true }) { DashboardCard(title: "Cash", value: viewModel.availableCash.formatted(.currency(code: "EUR")), titleIcon: "pencil", privacyMode: $privacyMode) }.buttonStyle(.plain)
                        Button(action: { showInvestedSheet = true }) { DashboardCard(title: "Initial Investment", value: viewModel.manuallyInvested.formatted(.currency(code: "EUR")), titleIcon: "pencil", privacyMode: $privacyMode) }.buttonStyle(.plain)
                        DashboardCard(title: "Total (Current + Cash)", value: viewModel.currentTotalCapital.formatted(.currency(code: "EUR")), privacyMode: $privacyMode)
                        DashboardCard(title: "Stock Value", value: viewModel.totalValue.formatted(.currency(code: "EUR")), privacyMode: $privacyMode)
                    }
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Unrealized P/L").font(.subheadline).foregroundColor(.secondary).lineLimit(1)
                            Text(viewModel.totalROIValue.formatted(.currency(code: "EUR").sign(strategy: .always()))).font(.title2).fontWeight(.bold).foregroundColor(getColor(for: viewModel.totalROIValue)).blur(radius: privacyMode ? 8 : 0)
                            Text(viewModel.totalROIPercent.formatted(.percent.precision(.fractionLength(2)).sign(strategy: .always()))).font(.caption).padding(.horizontal, 6).padding(.vertical, 2).background(getColor(for: viewModel.totalROIValue).opacity(0.1)).foregroundColor(getColor(for: viewModel.totalROIValue)).cornerRadius(4).blur(radius: privacyMode ? 8 : 0)
                        }.padding().frame(maxWidth: .infinity, alignment: .leading).frame(height: 110).background(Color(NSColor.controlBackgroundColor)).cornerRadius(10).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                        
                        DashboardCard(title: "Positions", value: "\(viewModel.positionCount)", privacyMode: .constant(false))
                        DashboardCard(title: "Annual Dividends", value: viewModel.totalDividends.formatted(.currency(code: "EUR")), privacyMode: $privacyMode)
                        DashboardCard(title: "Total Yield", value: viewModel.portfolioYield.formatted(.percent.precision(.fractionLength(2))), privacyMode: $privacyMode)
                    }
                }
                
                GoalProgressBar(title: viewModel.currentGoalType.rawValue, currentValue: viewModel.currentGoalValue, targetValue: viewModel.currentGoalTarget, privacyMode: $privacyMode).contentShape(Rectangle()).onTapGesture(count: 2) { showGoalSheet = true }
                
                // --- TABLE ---
                VStack(spacing: 0) {
                    Table(viewModel.positions, selection: $selection, sortOrder: $viewModel.sortOrder) {
                        TableColumn("Ticker", value: \.ticker) { position in
                            HStack { Circle().fill(viewModel.color(for: position.ticker).opacity(0.8)).frame(width: 24, height: 24).overlay(Text(position.ticker.prefix(1)).font(.caption).fontWeight(.bold).foregroundColor(.white)); Text(position.ticker).font(.system(.body, design: .monospaced)).fontWeight(.bold) }
                            .contentShape(Rectangle()).onTapGesture(count: 2) { positionToEdit = position }.contextMenu { Button(role: .destructive) { viewModel.deletePosition(id: position.id) } label: { Label("Delete", systemImage: "trash") } }
                        }
                        TableColumn("Qty", value: \.quantity) { pos in Text("\(pos.quantity, specifier: "%.2f")").frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()).onTapGesture(count: 2) { positionToEdit = pos } }
                        TableColumn("Price", value: \.currentPrice) { pos in Text(pos.currentPrice, format: .currency(code: pos.currency)).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()).onTapGesture(count: 2) { positionToEdit = pos } }
                        TableColumn("Avg Cost", value: \.averageCost) { pos in Text(pos.averageCost, format: .currency(code: pos.currency)).foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()).onTapGesture(count: 2) { positionToEdit = pos } }
                        TableColumn("Total Value", value: \.currentValueEUR) { pos in Text(pos.currentValueEUR, format: .currency(code: "EUR")).fontWeight(.medium).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()).onTapGesture(count: 2) { positionToEdit = pos } }
                        TableColumn("P/L €", value: \.roiValue) { pos in Text(pos.roiValue, format: .currency(code: "EUR").sign(strategy: .always())).foregroundColor(getColor(for: pos.roiValue)).fontWeight(.medium).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()).onTapGesture(count: 2) { positionToEdit = pos } }
                        TableColumn("P/L %", value: \.roiPercent) { pos in Text(pos.roiPercent, format: .percent.precision(.fractionLength(2)).sign(strategy: .always())).padding(.horizontal, 8).padding(.vertical, 2).background(getColor(for: pos.roiValue).opacity(0.1)).foregroundColor(getColor(for: pos.roiValue)).cornerRadius(4).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()).onTapGesture(count: 2) { positionToEdit = pos } }
                    }
                    .tableStyle(.inset)
                }
                .frame(height: tableFrameHeight)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                
                // --- CHARTS ---
                VStack(spacing: 24) {
                    HStack(spacing: 24) {
                        ModernDonutChart(data: viewModel.allocationByPosition, title: "Weight by Position", zoomType: .positions, palette: positionColors, expandedChart: $chartToZoom)
                        ModernDonutChart(data: viewModel.allocationByCountry, title: "Geographic Exposure", zoomType: .countries, palette: geographicColors, expandedChart: $chartToZoom)
                    }
                    HStack(spacing: 24) {
                        ModernDonutChart(data: viewModel.allocationBySector, title: "Sector Allocation", zoomType: .sectors, palette: sectorColors, expandedChart: $chartToZoom)
                        ModernDonutChart(data: viewModel.allocationByMarketCap, title: "Market Cap Allocation", zoomType: .marketCaps, palette: marketCapColors, expandedChart: $chartToZoom)
                    }
                    HStack(spacing: 24) {
                        PRUPriceChart(viewModel: viewModel, data: viewModel.priceComparisonData, expandedChart: $chartToZoom)
                        ROIComboChart(viewModel: viewModel, positions: viewModel.positions, expandedChart: $chartToZoom)
                    }
                    HStack(spacing: 24) {
                        PerformanceHeatmap(positions: viewModel.positions, expandedChart: $chartToZoom)
                        DailyROIChart(viewModel: viewModel, positions: viewModel.positions, expandedChart: $chartToZoom)
                    }
                }
            }.padding()
        }
        .sheet(isPresented: $showCashSheet) { SimpleNumberEditView(title: "Edit Cash", value: $viewModel.availableCash) }
        .sheet(isPresented: $showInvestedSheet) { SimpleNumberEditView(title: "Edit Initial Investment", value: $viewModel.manuallyInvested) }
        .sheet(isPresented: $showGoalSheet) { EditGoalView(viewModel: viewModel) }
        .sheet(item: $positionToEdit) { position in EditPositionView(viewModel: viewModel, position: position) }
        .sheet(item: $chartToZoom) { type in FullScreenChartView(zoomType: type, viewModel: viewModel) }
    }
    func getColor(for value: Double) -> Color { value >= 0 ? .green : .red }
}
