import SwiftUI
import Charts

// =========================================================================
// MARK: - ENUMS & MODELS FOR SIMULATION
// =========================================================================

enum SimulationChartZoomType: String, Identifiable {
    case currentPositions, simulatedPositions
    case currentSectors, simulatedSectors
    case cashAllocation, totalValueCompare
    case yieldImpact, simulatedDividends
    var id: String { self.rawValue }
}

enum DiffType { case add, remove, modify, neutral }

struct SimulationDiff: Identifiable {
    let id = UUID()
    let text: String
    let type: DiffType
    let onUndo: (() -> Void)?
    
    var color: Color {
        switch type {
        case .add: return .green
        case .remove: return .red
        case .modify: return .orange
        case .neutral: return .secondary
        }
    }
    var icon: String {
        switch type {
        case .add: return "plus.circle.fill"
        case .remove: return "minus.circle.fill"
        case .modify: return "arrow.triangle.2.circlepath.circle.fill"
        case .neutral: return "equal.circle.fill"
        }
    }
}

// =========================================================================
// MARK: - MAIN SIMULATION VIEW
// =========================================================================

struct SimulationView: View {
    @ObservedObject var viewModel: PortfolioViewModel
    @Binding var privacyMode: Bool
    
    // Données du Bac à sable
    @State private var simulatedPositions: [Position] = []
    @State private var simulatedCash: Double = 0.0
    
    // Registres comptables pour les actions Undo
    @State private var manualCashOffset: Double = 0.0
    @State private var tradeCashImpacts: [String: Double] = [:]
    
    @State private var chartToZoom: SimulationChartZoomType? = nil
    @State private var showAddSimulatedStock: Bool = false
    @State private var showSimulatedCashSheet: Bool = false
    @State private var editingSimulatedPosition: Position? = nil

    // MARK: - CALCULS SIMULATION
    var simulatedTotalValue: Double {
        var total: Double = 0
        for pos in simulatedPositions { total += pos.currentValueEUR }
        return total
    }
    
    var simulatedTotalCapital: Double { simulatedTotalValue + simulatedCash }
    
    var simulatedTotalDividends: Double {
        var total: Double = 0
        for pos in simulatedPositions { total += (pos.quantity * pos.annualDividendNet * (pos.currency == "USD" ? pos.usdToEurRate : 1.0)) }
        return total
    }
    
    var simulatedYield: Double { simulatedTotalCapital > 0 ? (simulatedTotalDividends / simulatedTotalCapital) : 0 }
    
    var simulatedAllocationByPosition: [ChartDataItem] {
        var items = simulatedPositions.map { ChartDataItem(name: $0.ticker, value: $0.currentValueEUR) }
        if simulatedCash > 0 { items.append(ChartDataItem(name: "Cash", value: simulatedCash)) }
        return items.sorted { $0.value > $1.value }
    }
    
    var simulatedAllocationBySector: [ChartDataItem] {
        var dict: [String: Double] = [:]
        for pos in simulatedPositions { dict[pos.sector.isEmpty ? "Unknown" : pos.sector.capitalized, default: 0] += pos.currentValueEUR }
        if simulatedCash > 0 { dict["Cash", default: 0] += simulatedCash }
        return dict.map { ChartDataItem(name: $0.key, value: $0.value) }.sorted { $0.value > $1.value }
    }
    
    var simulatedDividendsByPosition: [ChartDataItem] {
        var items: [ChartDataItem] = []
        for pos in simulatedPositions {
            let div = pos.quantity * pos.annualDividendNet * (pos.currency == "USD" ? pos.usdToEurRate : 1.0)
            if div > 0 { items.append(ChartDataItem(name: pos.ticker, value: div)) }
        }
        return items.sorted { $0.value > $1.value }
    }
    
    var cashAllocationData: [ChartDataItem] {
        var items: [ChartDataItem] = []
        let realDict = Dictionary(uniqueKeysWithValues: viewModel.positions.map { ($0.ticker, $0) })
        for simPos in simulatedPositions {
            let realQty = realDict[simPos.ticker]?.quantity ?? 0
            let addedQty = simPos.quantity - realQty
            if addedQty > 0 {
                let rate = simPos.currency == "USD" ? simPos.usdToEurRate : 1.0
                let spent = addedQty * simPos.averageCost * rate
                items.append(ChartDataItem(name: "\(simPos.ticker) (Invested)", value: spent))
            }
        }
        if simulatedCash > 0 { items.append(ChartDataItem(name: "Remaining Cash", value: simulatedCash)) }
        return items.sorted { $0.value > $1.value }
    }
    
    var totalValueComparisonData: [ChartDataItem] {
        [ChartDataItem(name: "Current", value: viewModel.currentTotalCapital), ChartDataItem(name: "Simulated", value: simulatedTotalCapital)]
    }
    
    var yieldComparisonData: [ChartDataItem] {
        [ChartDataItem(name: "Current", value: viewModel.portfolioYield * 100), ChartDataItem(name: "Simulated", value: simulatedYield * 100)]
    }

    var simulationDiffs: [SimulationDiff] {
        var diffs = [SimulationDiff]()
        
        // 1. Log exclusif pour les ajouts/retraits manuels de cash
        if abs(manualCashOffset) > 0.01 {
            diffs.append(SimulationDiff(
                text: manualCashOffset > 0 ? "Manual Cash added: \(manualCashOffset.formatted(.currency(code: "EUR")))" : "Manual Cash removed: \((-manualCashOffset).formatted(.currency(code: "EUR")))",
                type: manualCashOffset > 0 ? .add : .remove,
                onUndo: {
                    simulatedCash -= manualCashOffset
                    manualCashOffset = 0.0
                }
            ))
        }
        
        let realDict = Dictionary(uniqueKeysWithValues: viewModel.positions.map { ($0.ticker, $0) })
        let simDict = Dictionary(uniqueKeysWithValues: simulatedPositions.map { ($0.ticker, $0) })
        
        // 2. Achats et Ventes d'actions
        for (ticker, simPos) in simDict {
            if let realPos = realDict[ticker] {
                if abs(simPos.quantity - realPos.quantity) > 0.001 || abs(simPos.averageCost - realPos.averageCost) > 0.001 {
                    let qtyDiff = simPos.quantity - realPos.quantity
                    let impact = tradeCashImpacts[ticker] ?? 0.0
                    let impactStr = impact != 0 ? " (\(impact > 0 ? "+" : "")\(impact.formatted(.currency(code: "EUR"))))" : ""
                    
                    let text = abs(qtyDiff) > 0.001 ? (qtyDiff > 0 ? "Added \(qtyDiff.formatted()) shares of \(ticker)\(impactStr)" : "Sold \((-qtyDiff).formatted()) shares of \(ticker)\(impactStr)") : "Modified \(ticker) (Avg Cost or Sector)"
                    
                    diffs.append(SimulationDiff(text: text, type: qtyDiff > 0 ? .add : (qtyDiff < 0 ? .remove : .modify), onUndo: {
                        if let idx = simulatedPositions.firstIndex(where: { $0.ticker == ticker }) { simulatedPositions[idx] = realPos }
                        simulatedCash -= impact // Rembourse ou déduit l'impact du cash
                        tradeCashImpacts[ticker] = 0.0
                    }))
                }
            } else {
                let impact = tradeCashImpacts[ticker] ?? 0.0
                let impactStr = impact != 0 ? " (\(impact > 0 ? "+" : "")\(impact.formatted(.currency(code: "EUR"))))" : ""
                diffs.append(SimulationDiff(text: "New position added: \(simPos.quantity.formatted())x \(ticker)\(impactStr)", type: .add, onUndo: {
                    simulatedPositions.removeAll { $0.ticker == ticker }
                    simulatedCash -= impact
                    tradeCashImpacts[ticker] = 0.0
                }))
            }
        }
        
        // 3. Liquidations totales
        for (ticker, realPos) in realDict {
            if simDict[ticker] == nil {
                let impact = tradeCashImpacts[ticker] ?? 0.0
                let impactStr = impact != 0 ? " (\(impact > 0 ? "+" : "")\(impact.formatted(.currency(code: "EUR"))))" : ""
                diffs.append(SimulationDiff(text: "Liquidated position: \(ticker)\(impactStr)", type: .remove, onUndo: {
                    simulatedPositions.append(realPos)
                    simulatedCash -= impact
                    tradeCashImpacts[ticker] = 0.0
                }))
            }
        }
        
        if diffs.isEmpty { diffs.append(SimulationDiff(text: "No changes. Sandbox exactly matches current portfolio.", type: .neutral, onUndo: nil)) }
        return diffs
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 24) {
                
                SimulationDashboardSection(
                    viewModel: viewModel,
                    simulatedTotalCapital: simulatedTotalCapital,
                    simulatedCash: simulatedCash,
                    simulatedTotalDividends: simulatedTotalDividends,
                    simulatedYield: simulatedYield,
                    privacyMode: $privacyMode
                )
                
                SimulationDiffSection(diffs: simulationDiffs, privacyMode: $privacyMode)
                
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Current Portfolio").font(.title2).fontWeight(.bold)
                            Spacer()
                            Text(viewModel.currentTotalCapital.formatted(.currency(code: "EUR"))).font(.headline).foregroundColor(.secondary).blur(radius: privacyMode ? 6 : 0)
                        }
                        CurrentPortfolioTable(positions: viewModel.positions, totalCapital: viewModel.currentTotalCapital, privacyMode: $privacyMode)
                    }.frame(maxWidth: .infinity)
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Simulated Sandbox").font(.title2).fontWeight(.bold).foregroundColor(.blue)
                            Spacer()
                            Text(simulatedTotalCapital.formatted(.currency(code: "EUR"))).font(.headline).foregroundColor(.blue).blur(radius: privacyMode ? 6 : 0)
                            
                            Button(action: { showSimulatedCashSheet = true }) { Image(systemName: "eurosign.circle.fill").foregroundColor(.green).font(.title3) }.buttonStyle(.plain).help("Modify Simulated Cash")
                            Button(action: { showAddSimulatedStock = true }) { Image(systemName: "plus.circle.fill").foregroundColor(.blue).font(.title3) }.buttonStyle(.plain).help("Add Simulated Stock")
                            Button(action: resetSimulation) { Image(systemName: "arrow.counterclockwise.circle.fill").foregroundColor(.secondary).font(.title3) }.buttonStyle(.plain).help("Reset Sandbox")
                        }
                        SimulatedPortfolioTable(
                            positions: $simulatedPositions,
                            totalCapital: simulatedTotalCapital,
                            privacyMode: $privacyMode,
                            onEdit: { editingSimulatedPosition = $0 },
                            onDelete: { id in
                                // Gère aussi la suppression directe via menu contextuel
                                if let pos = simulatedPositions.first(where: { $0.id == id }) {
                                    let valEUR = pos.quantity * pos.currentPrice * (pos.currency == "USD" ? pos.usdToEurRate : 1.0)
                                    simulatedCash += valEUR
                                    tradeCashImpacts[pos.ticker, default: 0] += valEUR
                                }
                                simulatedPositions.removeAll { $0.id == id }
                            }
                        )
                    }.frame(maxWidth: .infinity)
                }.padding().background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                
                // 1. POIDS PAR POSITION
                HStack(spacing: 24) {
                    SimulationDonutChart(data: viewModel.allocationByPosition, title: "Current Weight by Position", zoomType: .currentPositions, palette: positionColors, privacyMode: $privacyMode, expandedChart: $chartToZoom)
                    SimulationDonutChart(data: simulatedAllocationByPosition, title: "Simulated Weight by Position", zoomType: .simulatedPositions, palette: positionColors, privacyMode: $privacyMode, expandedChart: $chartToZoom)
                }
                
                // 2. SECTEURS RESTAURÉS
                HStack(spacing: 24) {
                    SimulationDonutChart(data: viewModel.allocationBySector, title: "Current Sector Allocation", zoomType: .currentSectors, palette: sectorColors, privacyMode: $privacyMode, expandedChart: $chartToZoom)
                    SimulationDonutChart(data: simulatedAllocationBySector, title: "Simulated Sector Allocation", zoomType: .simulatedSectors, palette: sectorColors, privacyMode: $privacyMode, expandedChart: $chartToZoom)
                }
                
                // 3. BAR CHARTS (COULEURS CORRIGÉES)
                HStack(spacing: 24) {
                    SimulationBarChart(data: totalValueComparisonData, title: "Total Value Comparison", zoomType: .totalValueCompare, isEuro: true, colorCurrent: .blue, colorSimulated: .purple, privacyMode: $privacyMode, expandedChart: $chartToZoom)
                    SimulationBarChart(data: yieldComparisonData, title: "Portfolio Yield Impact", zoomType: .yieldImpact, isEuro: false, colorCurrent: .orange, colorSimulated: .green, privacyMode: $privacyMode, expandedChart: $chartToZoom)
                }
                
                // 4. CASH ALLOCATION ET DIVIDENDES SIMULÉS
                HStack(spacing: 24) {
                    SimulationDonutChart(data: cashAllocationData, title: "Simulated Cash Investments", zoomType: .cashAllocation, palette: marketCapColors, privacyMode: $privacyMode, expandedChart: $chartToZoom)
                    SimulationDonutChart(data: simulatedDividendsByPosition, title: "Simulated Dividends by Position", zoomType: .simulatedDividends, palette: positionColors, privacyMode: $privacyMode, expandedChart: $chartToZoom)
                }
            }
            .padding()
        }
        .onAppear { resetSimulation() }
        .sheet(item: $chartToZoom) { type in
            SimulationFullScreenChartView(
                zoomType: type,
                currentPosData: viewModel.allocationByPosition,
                simPosData: simulatedAllocationByPosition,
                currentSecData: viewModel.allocationBySector,
                simSecData: simulatedAllocationBySector,
                cashAllocData: cashAllocationData,
                totalValData: totalValueComparisonData,
                yieldData: yieldComparisonData,
                simDivData: simulatedDividendsByPosition,
                privacyMode: $privacyMode
            )
        }
        .sheet(isPresented: $showAddSimulatedStock) {
            SimulatedAddEditSheet(simulatedPositions: $simulatedPositions, simulatedCash: $simulatedCash, tradeCashImpacts: $tradeCashImpacts, totalCapital: simulatedTotalCapital, itemToEdit: nil)
        }
        .sheet(item: $editingSimulatedPosition) { pos in
            SimulatedAddEditSheet(simulatedPositions: $simulatedPositions, simulatedCash: $simulatedCash, tradeCashImpacts: $tradeCashImpacts, totalCapital: simulatedTotalCapital, itemToEdit: pos)
        }
        .sheet(isPresented: $showSimulatedCashSheet) {
            SimulatedCashSheet(simulatedCash: $simulatedCash, manualCashOffset: $manualCashOffset)
        }
    }
    
    private func resetSimulation() {
        simulatedPositions = viewModel.positions.map { $0 }
        simulatedCash = viewModel.availableCash
        manualCashOffset = 0.0
        tradeCashImpacts = [:]
    }
}

// =========================================================================
// MARK: - DASHBOARD & DIFF SECTION
// =========================================================================

struct SimulationDashboardSection: View {
    @ObservedObject var viewModel: PortfolioViewModel
    let simulatedTotalCapital: Double
    let simulatedCash: Double
    let simulatedTotalDividends: Double
    let simulatedYield: Double
    @Binding var privacyMode: Bool

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                DashboardCard(title: "Current Portfolio Value", value: viewModel.currentTotalCapital.formatted(.currency(code: "EUR")), titleIcon: nil, privacyMode: $privacyMode)
                DashboardCard(title: "Simulated Portfolio Value", value: simulatedTotalCapital.formatted(.currency(code: "EUR")), titleIcon: nil, privacyMode: $privacyMode)
                DashboardCard(title: "Current Cash", value: viewModel.availableCash.formatted(.currency(code: "EUR")), titleIcon: nil, privacyMode: $privacyMode)
                DashboardCard(title: "Simulated Cash", value: simulatedCash.formatted(.currency(code: "EUR")), titleIcon: nil, privacyMode: $privacyMode)
            }
            HStack(spacing: 16) {
                DashboardCard(title: "Current Annual Div.", value: viewModel.totalDividends.formatted(.currency(code: "EUR")), titleIcon: nil, privacyMode: $privacyMode)
                DashboardCard(title: "Simulated Annual Div.", value: simulatedTotalDividends.formatted(.currency(code: "EUR")), titleIcon: nil, privacyMode: $privacyMode)
                DashboardCard(title: "Current Total Yield", value: viewModel.portfolioYield.formatted(.percent.precision(.fractionLength(2))), titleIcon: nil, privacyMode: $privacyMode)
                DashboardCard(title: "Simulated Total Yield", value: simulatedYield.formatted(.percent.precision(.fractionLength(2))), titleIcon: nil, privacyMode: $privacyMode)
            }
        }
    }
}

struct SimulationDiffSection: View {
    let diffs: [SimulationDiff]
    @Binding var privacyMode: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sandbox Actions Log (Line by Line)").font(.headline).foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(diffs) { diff in
                    HStack(spacing: 12) {
                        Image(systemName: diff.icon).foregroundColor(diff.color)
                        Text(diff.text).font(.subheadline).fontWeight(.medium).blur(radius: privacyMode ? 6 : 0)
                        Spacer()
                        if let undoAction = diff.onUndo {
                            Button(action: undoAction) {
                                HStack(spacing: 4) { Image(systemName: "arrow.uturn.backward"); Text("Undo") }
                                .font(.caption).fontWeight(.bold).foregroundColor(.red)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Color.red.opacity(0.1)).cornerRadius(6)
                            }.buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color(NSColor.windowBackgroundColor))
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.1), lineWidth: 1))
                }
            }
        }.padding().background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// =========================================================================
// MARK: - TABLES
// =========================================================================

struct CurrentPortfolioTable: View {
    let positions: [Position]
    let totalCapital: Double
    @Binding var privacyMode: Bool
    
    var body: some View {
        Table(positions) {
            TableColumn("Ticker") { pos in Text(pos.ticker).fontWeight(.bold) }
            TableColumn("Qty") { pos in Text(pos.quantity.formatted()).blur(radius: privacyMode ? 6 : 0) }
            TableColumn("Avg Cost") { pos in Text(pos.averageCost.formatted(.currency(code: pos.currency))).foregroundColor(.secondary).blur(radius: privacyMode ? 6 : 0) }
            TableColumn("Weight") { pos in
                let weight = totalCapital > 0 ? (pos.currentValueEUR / totalCapital) : 0
                Text(weight.formatted(.percent.precision(.fractionLength(1)))).foregroundColor(.blue).blur(radius: privacyMode ? 6 : 0)
            }
        }.frame(height: 300)
    }
}

struct SimulatedPortfolioTable: View {
    @Binding var positions: [Position]
    let totalCapital: Double
    @Binding var privacyMode: Bool
    let onEdit: (Position) -> Void
    let onDelete: (UUID) -> Void
    
    var body: some View {
        Table(positions) {
            TableColumn("Ticker") { pos in
                Text(pos.ticker).fontWeight(.bold)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { onEdit(pos) }
                    .contextMenu {
                        Button("Edit") { onEdit(pos) }
                        Button(role: .destructive) { onDelete(pos.id) } label: { Label("Delete", systemImage: "trash") }
                    }
            }
            TableColumn("Qty") { pos in
                Text(pos.quantity.formatted()).blur(radius: privacyMode ? 6 : 0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { onEdit(pos) }
                    .contextMenu {
                        Button("Edit") { onEdit(pos) }
                        Button(role: .destructive) { onDelete(pos.id) } label: { Label("Delete", systemImage: "trash") }
                    }
            }
            TableColumn("Avg Cost") { pos in
                Text(pos.averageCost.formatted(.currency(code: pos.currency))).foregroundColor(.secondary).blur(radius: privacyMode ? 6 : 0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { onEdit(pos) }
                    .contextMenu {
                        Button("Edit") { onEdit(pos) }
                        Button(role: .destructive) { onDelete(pos.id) } label: { Label("Delete", systemImage: "trash") }
                    }
            }
            TableColumn("Weight") { pos in
                let weight = totalCapital > 0 ? (pos.currentValueEUR / totalCapital) : 0
                Text(weight.formatted(.percent.precision(.fractionLength(1)))).foregroundColor(.blue).blur(radius: privacyMode ? 6 : 0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { onEdit(pos) }
                    .contextMenu {
                        Button("Edit") { onEdit(pos) }
                        Button(role: .destructive) { onDelete(pos.id) } label: { Label("Delete", systemImage: "trash") }
                    }
            }
        }.frame(height: 300)
    }
}

// =========================================================================
// MARK: - GRAPHIQUES SPÉCIFIQUES
// =========================================================================

struct SimulationDonutChart: View {
    let data: [ChartDataItem]; let title: String; let zoomType: SimulationChartZoomType; let palette: [Color]
    @Binding var privacyMode: Bool
    var isExpanded: Bool = false
    @Binding var expandedChart: SimulationChartZoomType?
    
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
            if filteredData.isEmpty { Spacer(); Text("No data / No investments made").foregroundColor(.secondary); Spacer() } else {
                Chart(filteredData) { item in SectorMark(angle: .value("Value", item.value), innerRadius: .ratio(0.65), angularInset: 1.5).foregroundStyle(color(for: item.name)).cornerRadius(4) }
                .chartLegend(.hidden).chartAngleSelection(value: $selectedAngleValue)
                .chartBackground { proxy in
                    GeometryReader { geometry in
                        if let value = selectedAngleValue {
                            let item = findItem(for: value)
                            VStack {
                                Text(item.name).font(.headline)
                                Text(item.value.formatted(.currency(code: "EUR"))).font(.subheadline).foregroundColor(.secondary).blur(radius: privacyMode ? 6 : 0)
                            }.position(x: geometry.frame(in: .local).midX, y: geometry.frame(in: .local).midY)
                        }
                    }
                }.animation(.easeInOut(duration: 0.2), value: selectedAngleValue)
            }
            BlueChipWatermark()
        }.padding().frame(minHeight: 360, maxHeight: isExpanded ? .infinity : 360).background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    func findItem(for value: Double) -> ChartDataItem { var cum = 0.0; for item in filteredData { cum += item.value; if value <= cum { return item } }; return filteredData.last! }
}

struct SimulationBarChart: View {
    let data: [ChartDataItem]; let title: String; let zoomType: SimulationChartZoomType; let isEuro: Bool
    var colorCurrent: Color = .blue
    var colorSimulated: Color = .purple
    @Binding var privacyMode: Bool
    var isExpanded: Bool = false
    @Binding var expandedChart: SimulationChartZoomType?
    @State private var hoveredName: String? = nil

    var body: some View {
        VStack {
            HStack {
                if !isExpanded { Text(title).font(.headline).foregroundColor(.secondary) }
                Spacer()
                if !isExpanded { Button(action: { expandedChart = zoomType }) { Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary) }.buttonStyle(.plain) }
            }.padding(.bottom, 16)
            
            Chart(data) { item in
                BarMark(x: .value("Portfolio", item.name), y: .value("Value", item.value))
                    .foregroundStyle(item.name == "Current" ? colorCurrent : colorSimulated)
                    .cornerRadius(6)
                    .annotation(position: .top) {
                        if hoveredName == item.name {
                            Text(isEuro ? item.value.formatted(.currency(code: "EUR").precision(.fractionLength(0))) : "\(item.value.formatted(.number.precision(.fractionLength(2))))%")
                                .font(.caption).fontWeight(.bold).foregroundColor(.secondary).blur(radius: privacyMode ? 6 : 0)
                        }
                    }
            }
            .chartLegend(.hidden).chartXSelection(value: $hoveredName)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine(); AxisTick()
                    if let val = value.as(Double.self) { AxisValueLabel(isEuro ? val.formatted(.currency(code: "EUR").notation(.compactName)) : "\(val.formatted(.number.precision(.fractionLength(0))))%") }
                }
            }
            Spacer()
            BlueChipWatermark()
        }.padding().frame(minHeight: 360, maxHeight: isExpanded ? .infinity : 360).background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// =========================================================================
// MARK: - FULLSCREEN ZOOM POUR SIMULATION
// =========================================================================

struct SimulationFullScreenChartView: View {
    @Environment(\.dismiss) var dismiss
    let zoomType: SimulationChartZoomType
    
    let currentPosData: [ChartDataItem]
    let simPosData: [ChartDataItem]
    let currentSecData: [ChartDataItem]
    let simSecData: [ChartDataItem]
    let cashAllocData: [ChartDataItem]
    let totalValData: [ChartDataItem]
    let yieldData: [ChartDataItem]
    let simDivData: [ChartDataItem]
    @Binding var privacyMode: Bool

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text(titleForZoom).font(.title).fontWeight(.bold)
                Spacer()
                Button(action: { dismiss() }) { Image(systemName: "xmark.circle.fill").font(.title).foregroundColor(.secondary) }.buttonStyle(.plain)
            }
            
            switch zoomType {
            case .currentPositions: SimulationDonutChart(data: currentPosData, title: titleForZoom, zoomType: zoomType, palette: positionColors, privacyMode: $privacyMode, isExpanded: true, expandedChart: .constant(nil))
            case .simulatedPositions: SimulationDonutChart(data: simPosData, title: titleForZoom, zoomType: zoomType, palette: positionColors, privacyMode: $privacyMode, isExpanded: true, expandedChart: .constant(nil))
            case .currentSectors: SimulationDonutChart(data: currentSecData, title: titleForZoom, zoomType: zoomType, palette: sectorColors, privacyMode: $privacyMode, isExpanded: true, expandedChart: .constant(nil))
            case .simulatedSectors: SimulationDonutChart(data: simSecData, title: titleForZoom, zoomType: zoomType, palette: sectorColors, privacyMode: $privacyMode, isExpanded: true, expandedChart: .constant(nil))
            case .cashAllocation: SimulationDonutChart(data: cashAllocData, title: titleForZoom, zoomType: zoomType, palette: marketCapColors, privacyMode: $privacyMode, isExpanded: true, expandedChart: .constant(nil))
            case .totalValueCompare: SimulationBarChart(data: totalValData, title: titleForZoom, zoomType: zoomType, isEuro: true, colorCurrent: .blue, colorSimulated: .purple, privacyMode: $privacyMode, isExpanded: true, expandedChart: .constant(nil))
            case .yieldImpact: SimulationBarChart(data: yieldData, title: titleForZoom, zoomType: zoomType, isEuro: false, colorCurrent: .orange, colorSimulated: .green, privacyMode: $privacyMode, isExpanded: true, expandedChart: .constant(nil))
            case .simulatedDividends: SimulationDonutChart(data: simDivData, title: titleForZoom, zoomType: zoomType, palette: positionColors, privacyMode: $privacyMode, isExpanded: true, expandedChart: .constant(nil))
            }
        }.padding(30).frame(minWidth: 900, minHeight: 700)
    }
    
    var titleForZoom: String {
        switch zoomType {
        case .currentPositions: return "Current Weight by Position"
        case .simulatedPositions: return "Simulated Weight by Position"
        case .currentSectors: return "Current Sector Allocation"
        case .simulatedSectors: return "Simulated Sector Allocation"
        case .cashAllocation: return "Simulated Cash Investments"
        case .totalValueCompare: return "Total Portfolio Value Comparison"
        case .yieldImpact: return "Portfolio Yield Impact"
        case .simulatedDividends: return "Simulated Dividends by Position"
        }
    }
}

// =========================================================================
// MARK: - SHEET : AJOUT/RETRAIT CASH SEUL
// =========================================================================

enum CashAction: String, CaseIterable {
    case add = "Add Cash"
    case remove = "Remove Cash"
}

struct SimulatedCashSheet: View {
    @Environment(\.dismiss) var dismiss
    @Binding var simulatedCash: Double
    @Binding var manualCashOffset: Double // Mémorise la transaction pour l'historique
    @State private var cashInput: Double? = nil
    @State private var action: CashAction = .add
    
    var newBalance: Double {
        let amount = cashInput ?? 0.0
        return action == .add ? simulatedCash + amount : max(0, simulatedCash - amount)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Modify Sandbox Cash").font(.title2).fontWeight(.bold)
                Spacer()
                Button(action: { dismiss() }) { Image(systemName: "xmark.circle.fill").font(.title2).foregroundColor(.secondary) }.buttonStyle(.plain)
            }.padding()
            Divider()
            
            VStack(alignment: .leading, spacing: 20) {
                Picker("Action", selection: $action) {
                    ForEach(CashAction.allCases, id: \.self) { act in
                        Text(act.rawValue).tag(act)
                    }
                }
                .pickerStyle(.segmented)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Amount (€)").font(.headline).foregroundColor(.secondary)
                    TextField("0.00", value: $cashInput, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .font(.title3)
                }
                
                VStack(spacing: 8) {
                    HStack {
                        Text("Current Cash:").foregroundColor(.secondary)
                        Spacer()
                        Text(simulatedCash.formatted(.currency(code: "EUR"))).foregroundColor(.secondary)
                    }
                    Divider()
                    HStack {
                        Text("New Balance:").fontWeight(.semibold)
                        Spacer()
                        Text(newBalance.formatted(.currency(code: "EUR")))
                            .fontWeight(.bold)
                            .foregroundColor(action == .add ? .green : .orange)
                    }
                }.font(.subheadline)
            }.padding(24)
            
            Spacer()
            Divider()
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Update Cash") {
                    let amountAdded = newBalance - simulatedCash
                    manualCashOffset += amountAdded
                    simulatedCash = newBalance
                    dismiss()
                }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                .disabled((cashInput ?? 0) <= 0)
            }.padding()
        }
        .frame(width: 350, height: 350)
    }
}

// =========================================================================
// MARK: - SHEET : ACHAT / VENTE DANS LE BAC À SABLE
// =========================================================================

enum TradeAction: String, CaseIterable {
    case buy = "Buy Shares"
    case sell = "Sell Shares"
}

struct SimulatedAddEditSheet: View {
    @Environment(\.dismiss) var dismiss
    @Binding var simulatedPositions: [Position]
    @Binding var simulatedCash: Double
    @Binding var tradeCashImpacts: [String: Double] // Mémorise l'impact financier du trade
    
    let totalCapital: Double
    let itemToEdit: Position?
    
    @State private var ticker: String = ""
    @State private var tradeAction: TradeAction = .buy
    @State private var tradedShares: Double? = nil
    
    @State private var pru: Double? = nil
    @State private var currentPrice: Double? = nil
    @State private var dividendPerShare: Double? = nil
    @State private var brokerTax: Double? = nil
    @State private var countryTax: Double? = nil
    
    @State private var currency: String = "EUR"
    @State private var usdToEurRate: Double = 1.0
    
    @State private var sector: String = ""
    @State private var brokerTaxIsPercent: Bool = false
    @State private var countryTaxIsPercent: Bool = false
    @State private var isFetching: Bool = false
    
    var isEditing: Bool { itemToEdit != nil }
    
    var safePrice: Double { currentPrice ?? 0.0 }
    var safeTradedShares: Double { tradedShares ?? 0.0 }
    var currentShares: Double { itemToEdit?.quantity ?? 0.0 }
    
    var newQuantity: Double {
        if tradeAction == .buy {
            return currentShares + safeTradedShares
        } else {
            return max(0, currentShares - safeTradedShares)
        }
    }
    
    var safeBrokerTax: Double { brokerTax ?? 0.0 }
    var safeCountryTax: Double { countryTax ?? 0.0 }
    
    var baseValueOriginal: Double { safeTradedShares * safePrice }
    var baseValueEUR: Double { baseValueOriginal * (currency == "USD" ? usdToEurRate : 1.0) }
    
    var calcBrokerTaxEUR: Double { brokerTaxIsPercent ? baseValueEUR * (safeBrokerTax / 100.0) : safeBrokerTax }
    var calcCountryTaxEUR: Double { countryTaxIsPercent ? baseValueEUR * (safeCountryTax / 100.0) : safeCountryTax }
    
    var cashImpactEUR: Double {
        let totalTaxes = calcBrokerTaxEUR + calcCountryTaxEUR
        if tradeAction == .buy {
            return -(baseValueEUR + totalTaxes)
        } else {
            return (baseValueEUR - totalTaxes)
        }
    }
    
    var hasInsufficientCash: Bool {
        tradeAction == .buy && abs(cashImpactEUR) > simulatedCash
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(isEditing ? "Edit Simulated Position" : "Add Simulated Position").font(.title2).fontWeight(.bold)
                Spacer()
                Button(action: { dismiss() }) { Image(systemName: "xmark.circle.fill").font(.title2).foregroundColor(.secondary) }.buttonStyle(.plain)
            }.padding()
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    
                    GroupBox("Stock Info") {
                        HStack {
                            TextField("Ticker (e.g., AAPL)", text: $ticker)
                                .textFieldStyle(.roundedBorder)
                                .disabled(isEditing)
                                .onChange(of: ticker) { ticker = ticker.uppercased() }
                            
                            Button(action: fetchYahooData) { HStack(spacing: 4) { Image(systemName: "arrow.clockwise"); Text("Fetch Price") } }
                            .buttonStyle(.borderedProminent).disabled(ticker.isEmpty || isFetching)
                        }
                        HStack(spacing: 16) {
                            TextField("Current Price (\(currency))", value: $currentPrice, format: .number).textFieldStyle(.roundedBorder)
                            TextField("Avg Cost (\(currency))", value: $pru, format: .number).textFieldStyle(.roundedBorder)
                        }
                        HStack(spacing: 16) {
                            TextField("Net Dividend / Share (\(currency))", value: $dividendPerShare, format: .number).textFieldStyle(.roundedBorder)
                            TextField("Sector", text: $sector).textFieldStyle(.roundedBorder)
                        }
                    }
                    
                    GroupBox("Transaction Details") {
                        if isEditing {
                            Picker("Action", selection: $tradeAction) {
                                ForEach(TradeAction.allCases, id: \.self) { action in Text(action.rawValue).tag(action) }
                            }.pickerStyle(.segmented).padding(.bottom, 8)
                        }
                        
                        HStack {
                            TextField("Shares to trade", value: $tradedShares, format: .number).textFieldStyle(.roundedBorder)
                            Text("Shares").foregroundColor(.secondary)
                        }
                        
                        HStack {
                            if isEditing {
                                Text("Currently owned: \(currentShares.formatted())").font(.caption).foregroundColor(.secondary)
                                Spacer()
                            }
                            Text("New quantity: \(newQuantity.formatted())").font(.caption).foregroundColor(.blue).fontWeight(.bold)
                        }
                        
                        if tradeAction == .sell && safeTradedShares > currentShares {
                            Text("Warning: You are selling more shares than you own.").font(.caption).foregroundColor(.red).padding(.top, 4)
                        }
                    }
                    
                    GroupBox("Taxes & Fees") {
                        HStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Broker Tax").font(.caption).foregroundColor(.secondary)
                                HStack { TextField("Broker Tax", value: $brokerTax, format: .number).textFieldStyle(.roundedBorder); Picker("", selection: $brokerTaxIsPercent) { Text("€").tag(false); Text("%").tag(true) }.frame(width: 60) }
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Country Tax").font(.caption).foregroundColor(.secondary)
                                HStack { TextField("Country Tax", value: $countryTax, format: .number).textFieldStyle(.roundedBorder); Picker("", selection: $countryTaxIsPercent) { Text("€").tag(false); Text("%").tag(true) }.frame(width: 60) }
                            }
                        }
                    }
                    
                    GroupBox("Transaction Impact (in EUR)") {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack { Text("Base Trade Value:"); Spacer(); Text(baseValueEUR.formatted(.currency(code: "EUR"))) }
                            HStack { Text("Total Taxes:"); Spacer(); Text((calcBrokerTaxEUR + calcCountryTaxEUR).formatted(.currency(code: "EUR"))).foregroundColor(.red) }
                            Divider()
                            HStack { Text("Net Cash Impact:"); Spacer(); Text(cashImpactEUR.formatted(.currency(code: "EUR").sign(strategy: .always()))).fontWeight(.bold).foregroundColor(cashImpactEUR >= 0 ? .green : .red) }
                            
                            Text("Remaining Cash will be: \((simulatedCash + cashImpactEUR).formatted(.currency(code: "EUR")))")
                                .font(.caption).foregroundColor(.secondary)
                                .padding(.top, 8)
                            
                            if hasInsufficientCash {
                                Text("Error: Insufficient simulated cash for this purchase!").font(.caption).fontWeight(.bold).foregroundColor(.red).padding(.top, 2)
                            }
                        }
                    }
                }.padding()
            }
            
            Divider()
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                if isEditing {
                    Button("Delete Position") { deletePosition() }.foregroundColor(.red).padding(.trailing, 16)
                }
                Button("Save Simulation") { save() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                    .disabled(ticker.isEmpty || (tradeAction == .sell && safeTradedShares > currentShares) || hasInsufficientCash)
            }.padding()
        }
        .frame(width: 500, height: 750)
        .onAppear {
            if let pos = itemToEdit {
                ticker = pos.ticker; pru = pos.averageCost; currentPrice = pos.currentPrice; dividendPerShare = pos.annualDividendNet; sector = pos.sector; currency = pos.currency; usdToEurRate = pos.usdToEurRate
                tradedShares = nil
            }
        }
    }
    
    private func fetchYahooData() {
        isFetching = true
        Task {
            let service = YahooFinanceService()
            let rate = await service.fetchUSDEURRate()
            if let data = await service.fetchStockData(for: ticker) {
                await MainActor.run { currentPrice = data.price; currency = data.currency; usdToEurRate = rate; isFetching = false }
            } else { await MainActor.run { isFetching = false } }
        }
    }
    
    private func save() {
        let cleanTicker = ticker.uppercased()
        
        simulatedCash += cashImpactEUR
        tradeCashImpacts[cleanTicker, default: 0] += cashImpactEUR
        
        if newQuantity <= 0 && isEditing {
            if let id = itemToEdit?.id { simulatedPositions.removeAll { $0.id == id } }
        } else {
            let newPos = Position(
                id: itemToEdit?.id ?? UUID(), ticker: cleanTicker, quantity: newQuantity, averageCost: pru ?? safePrice, currentPrice: safePrice, currency: currency, usdToEurRate: usdToEurRate, annualDividendNet: dividendPerShare ?? 0.0, country: itemToEdit?.country ?? "", sector: sector, marketCap: itemToEdit?.marketCap ?? "", dividendMonths: itemToEdit?.dividendMonths ?? [], purchaseDate: itemToEdit?.purchaseDate ?? Date(), dividendGrowth5Y: itemToEdit?.dividendGrowth5Y ?? 0.0
            )
            
            if isEditing, let idx = simulatedPositions.firstIndex(where: { $0.id == newPos.id }) { simulatedPositions[idx] = newPos } else { simulatedPositions.append(newPos) }
        }
        dismiss()
    }
    
    private func deletePosition() {
        if let pos = itemToEdit {
            let valEUR = pos.quantity * pos.currentPrice * (pos.currency == "USD" ? pos.usdToEurRate : 1.0)
            simulatedCash += valEUR
            tradeCashImpacts[pos.ticker, default: 0] += valEUR
        }
        if let id = itemToEdit?.id { simulatedPositions.removeAll { $0.id == id } }
        dismiss()
    }
}
