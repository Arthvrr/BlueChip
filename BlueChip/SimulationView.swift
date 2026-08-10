import SwiftUI
import Charts

// =========================================================================
// MARK: - ENUMS & MODELS FOR SIMULATION
// =========================================================================

enum SimulationChartZoomType: String, Identifiable {
    case currentPositions, simulatedPositions
    case currentSectors, simulatedSectors
    case cashAllocation, totalValueCompare
    var id: String { self.rawValue }
}

enum DiffType { case add, remove, modify, neutral }

struct SimulationDiff: Identifiable {
    let id = UUID()
    let text: String
    let type: DiffType
    let onUndo: (() -> Void)? // Action pour annuler la transaction
    
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
    
    // Données du Bac à sable (Non sauvegardées)
    @State private var simulatedPositions: [Position] = []
    @State private var simulatedCash: Double = 0.0
    
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
    
    var simulatedTotalCapital: Double {
        simulatedTotalValue + simulatedCash
    }
    
    var simulatedTotalDividends: Double {
        var total: Double = 0
        for pos in simulatedPositions { total += (pos.quantity * pos.annualDividendNet * (pos.currency == "USD" ? pos.usdToEurRate : 1.0)) }
        return total
    }
    
    var simulatedYield: Double {
        simulatedTotalCapital > 0 ? (simulatedTotalDividends / simulatedTotalCapital) : 0
    }
    
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
    
    // NOUVEAU : Répartition du Cash Investi
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
        
        if simulatedCash > 0 {
            items.append(ChartDataItem(name: "Remaining Cash", value: simulatedCash))
        }
        
        return items.sorted { $0.value > $1.value }
    }
    
    // Comparaison Valeur Totale
    var totalValueComparisonData: [ChartDataItem] {
        [
            ChartDataItem(name: "Current Portfolio", value: viewModel.currentTotalCapital),
            ChartDataItem(name: "Simulated Portfolio", value: simulatedTotalCapital)
        ]
    }

    // NOUVEAU : Générateur des différences interactives (Ligne par Ligne avec UNDO)
    var simulationDiffs: [SimulationDiff] {
        var diffs = [SimulationDiff]()
        
        // 1. Cash Diff
        if abs(simulatedCash - viewModel.availableCash) > 0.01 {
            let diff = simulatedCash - viewModel.availableCash
            diffs.append(SimulationDiff(
                text: diff > 0 ? "Cash increased by \(diff.formatted(.currency(code: "EUR")))" : "Cash decreased by \((-diff).formatted(.currency(code: "EUR")))",
                type: diff > 0 ? .add : .remove,
                onUndo: { simulatedCash = viewModel.availableCash }
            ))
        }
        
        let realDict = Dictionary(uniqueKeysWithValues: viewModel.positions.map { ($0.ticker, $0) })
        let simDict = Dictionary(uniqueKeysWithValues: simulatedPositions.map { ($0.ticker, $0) })
        
        // 2. Additions & Modifications
        for (ticker, simPos) in simDict {
            if let realPos = realDict[ticker] {
                if abs(simPos.quantity - realPos.quantity) > 0.001 || abs(simPos.averageCost - realPos.averageCost) > 0.001 {
                    let qtyDiff = simPos.quantity - realPos.quantity
                    let text = abs(qtyDiff) > 0.001
                        ? (qtyDiff > 0 ? "Added \(qtyDiff.formatted()) shares of \(ticker)" : "Sold \((-qtyDiff).formatted()) shares of \(ticker)")
                        : "Modified \(ticker) (PRU or Sector)"
                    
                    diffs.append(SimulationDiff(
                        text: text,
                        type: qtyDiff > 0 ? .add : (qtyDiff < 0 ? .remove : .modify),
                        onUndo: {
                            if let idx = simulatedPositions.firstIndex(where: { $0.ticker == ticker }) {
                                simulatedPositions[idx] = realPos
                            }
                        }
                    ))
                }
            } else {
                diffs.append(SimulationDiff(
                    text: "New position added: \(simPos.quantity.formatted())x \(ticker)",
                    type: .add,
                    onUndo: { simulatedPositions.removeAll { $0.ticker == ticker } }
                ))
            }
        }
        
        // 3. Liquidations
        for (ticker, realPos) in realDict {
            if simDict[ticker] == nil {
                diffs.append(SimulationDiff(
                    text: "Liquidated position: \(ticker)",
                    type: .remove,
                    onUndo: { simulatedPositions.append(realPos) }
                ))
            }
        }
        
        if diffs.isEmpty {
            diffs.append(SimulationDiff(text: "No changes. Sandbox exactly matches current portfolio.", type: .neutral, onUndo: nil))
        }
        
        return diffs
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 24) {
                
                // 1. DASHBOARD DE SYNTHÈSE (8 CARTES)
                SimulationDashboardSection(
                    viewModel: viewModel,
                    simulatedTotalCapital: simulatedTotalCapital,
                    simulatedCash: simulatedCash,
                    simulatedTotalDividends: simulatedTotalDividends,
                    simulatedYield: simulatedYield,
                    privacyMode: $privacyMode
                )
                
                // 2. ONGLET DES MODIFICATIONS (LIGNE PAR LIGNE AVEC UNDO)
                SimulationDiffSection(diffs: simulationDiffs)
                
                // 3. LES DEUX TABLEAUX CÔTE À CÔTE
                HStack(alignment: .top, spacing: 20) {
                    // LEFT: Current Portfolio
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Current Portfolio").font(.title2).fontWeight(.bold)
                            Spacer()
                            Text(viewModel.currentTotalCapital.formatted(.currency(code: "EUR"))).font(.headline).foregroundColor(.secondary).blur(radius: privacyMode ? 6 : 0)
                        }
                        CurrentPortfolioTable(positions: viewModel.positions, totalCapital: viewModel.currentTotalCapital, privacyMode: $privacyMode)
                    }
                    .frame(maxWidth: .infinity)
                    
                    Divider()
                    
                    // RIGHT: Simulated Portfolio
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Simulated Sandbox").font(.title2).fontWeight(.bold).foregroundColor(.blue)
                            Spacer()
                            Text(simulatedTotalCapital.formatted(.currency(code: "EUR"))).font(.headline).foregroundColor(.blue).blur(radius: privacyMode ? 6 : 0)
                            
                            // Boutons d'action
                            Button(action: { showSimulatedCashSheet = true }) { Image(systemName: "eurosign.circle.fill").foregroundColor(.green).font(.title3) }.buttonStyle(.plain).help("Modify Simulated Cash")
                            Button(action: { showAddSimulatedStock = true }) { Image(systemName: "plus.circle.fill").foregroundColor(.blue).font(.title3) }.buttonStyle(.plain).help("Add Simulated Stock")
                            Button(action: resetSimulation) { Image(systemName: "arrow.counterclockwise.circle.fill").foregroundColor(.secondary).font(.title3) }.buttonStyle(.plain).help("Reset Sandbox")
                        }
                        SimulatedPortfolioTable(
                            positions: $simulatedPositions,
                            totalCapital: simulatedTotalCapital,
                            privacyMode: $privacyMode,
                            onEdit: { editingSimulatedPosition = $0 },
                            onDelete: { id in simulatedPositions.removeAll { $0.id == id } }
                        )
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                
                // 4. GRAPHIQUES WEIGHT BY POSITION
                HStack(spacing: 24) {
                    SimulationDonutChart(data: viewModel.allocationByPosition, title: "Current Weight by Position", zoomType: .currentPositions, palette: positionColors, expandedChart: $chartToZoom)
                    SimulationDonutChart(data: simulatedAllocationByPosition, title: "Simulated Weight by Position", zoomType: .simulatedPositions, palette: positionColors, expandedChart: $chartToZoom)
                }
                
                // 5. GRAPHIQUES SECTOR ALLOCATION
                HStack(spacing: 24) {
                    SimulationDonutChart(data: viewModel.allocationBySector, title: "Current Sector Allocation", zoomType: .currentSectors, palette: sectorColors, expandedChart: $chartToZoom)
                    SimulationDonutChart(data: simulatedAllocationBySector, title: "Simulated Sector Allocation", zoomType: .simulatedSectors, palette: sectorColors, expandedChart: $chartToZoom)
                }
                
                // 6. NOUVEAUX GRAPHIQUES (CASH ALLOCATION & TOTAL VALUE)
                HStack(spacing: 24) {
                    SimulationDonutChart(data: cashAllocationData, title: "Simulated Cash Investments", zoomType: .cashAllocation, palette: marketCapColors, expandedChart: $chartToZoom)
                    SimulationBarChart(data: totalValueComparisonData, title: "Total Portfolio Value Comparison", zoomType: .totalValueCompare, expandedChart: $chartToZoom)
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
                totalValData: totalValueComparisonData
            )
        }
        .sheet(isPresented: $showAddSimulatedStock) {
            SimulatedAddEditSheet(simulatedPositions: $simulatedPositions, simulatedCash: $simulatedCash, totalCapital: simulatedTotalCapital, itemToEdit: nil)
        }
        .sheet(item: $editingSimulatedPosition) { pos in
            SimulatedAddEditSheet(simulatedPositions: $simulatedPositions, simulatedCash: $simulatedCash, totalCapital: simulatedTotalCapital, itemToEdit: pos)
        }
        .sheet(isPresented: $showSimulatedCashSheet) {
            SimulatedCashSheet(simulatedCash: $simulatedCash)
        }
    }
    
    private func resetSimulation() {
        simulatedPositions = viewModel.positions.map { $0 }
        simulatedCash = viewModel.availableCash
    }
}

// =========================================================================
// MARK: - DASHBOARD (8 CARTES) & DIFF SUMMARY
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
            // Ligne 1 : Valeurs et Cash
            HStack(spacing: 16) {
                DashboardCard(title: "Current Portfolio Value", value: viewModel.currentTotalCapital.formatted(.currency(code: "EUR")), titleIcon: nil, privacyMode: $privacyMode)
                DashboardCard(title: "Simulated Portfolio Value", value: simulatedTotalCapital.formatted(.currency(code: "EUR")), titleIcon: nil, privacyMode: $privacyMode)
                DashboardCard(title: "Current Cash", value: viewModel.availableCash.formatted(.currency(code: "EUR")), titleIcon: nil, privacyMode: $privacyMode)
                DashboardCard(title: "Simulated Cash", value: simulatedCash.formatted(.currency(code: "EUR")), titleIcon: nil, privacyMode: $privacyMode)
            }
            // Ligne 2 : Dividendes et Yield
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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sandbox Actions Log (Line by Line)").font(.headline).foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 8) {
                ForEach(diffs) { diff in
                    HStack(spacing: 12) {
                        Image(systemName: diff.icon).foregroundColor(diff.color)
                        Text(diff.text).font(.subheadline).fontWeight(.medium)
                        
                        Spacer()
                        
                        // Bouton Undo
                        if let undoAction = diff.onUndo {
                            Button(action: undoAction) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.uturn.backward")
                                    Text("Undo")
                                }
                                .font(.caption).fontWeight(.bold)
                                .foregroundColor(.red)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.red.opacity(0.1))
                                .cornerRadius(6)
                            }.buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(NSColor.windowBackgroundColor))
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.1), lineWidth: 1))
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
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
            TableColumn("Qty") { pos in Text(pos.quantity.formatted()) }
            TableColumn("Avg Cost") { pos in Text(pos.averageCost.formatted(.currency(code: pos.currency))).foregroundColor(.secondary) }
            TableColumn("Weight") { pos in
                let weight = totalCapital > 0 ? (pos.currentValueEUR / totalCapital) : 0
                Text(weight.formatted(.percent.precision(.fractionLength(1)))).foregroundColor(.blue)
            }
        }
        .frame(height: 300)
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
            TableColumn("Ticker") { pos in Text(pos.ticker).fontWeight(.bold) }
            TableColumn("Qty") { pos in Text(pos.quantity.formatted()) }
            TableColumn("Avg Cost") { pos in Text(pos.averageCost.formatted(.currency(code: pos.currency))).foregroundColor(.secondary) }
            TableColumn("Weight") { pos in
                let weight = totalCapital > 0 ? (pos.currentValueEUR / totalCapital) : 0
                Text(weight.formatted(.percent.precision(.fractionLength(1)))).foregroundColor(.blue)
            }
            TableColumn("Actions") { pos in
                HStack(spacing: 12) {
                    Button(action: { onEdit(pos) }) { Image(systemName: "pencil").foregroundColor(.secondary) }.buttonStyle(.plain)
                    Button(action: { onDelete(pos.id) }) { Image(systemName: "trash").foregroundColor(.red.opacity(0.7)) }.buttonStyle(.plain)
                }
            }
        }
        .frame(height: 300)
    }
}

// =========================================================================
// MARK: - GRAPHIQUES SPÉCIFIQUES À LA SIMULATION
// =========================================================================

struct SimulationDonutChart: View {
    let data: [ChartDataItem]; let title: String; let zoomType: SimulationChartZoomType; let palette: [Color]; var isExpanded: Bool = false
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

struct SimulationBarChart: View {
    let data: [ChartDataItem]
    let title: String
    let zoomType: SimulationChartZoomType
    var isExpanded: Bool = false
    @Binding var expandedChart: SimulationChartZoomType?

    var body: some View {
        VStack {
            HStack {
                if !isExpanded { Text(title).font(.headline).foregroundColor(.secondary) }
                Spacer()
                if !isExpanded { Button(action: { expandedChart = zoomType }) { Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary) }.buttonStyle(.plain) }
            }.padding(.bottom, 16)
            
            Chart(data) { item in
                BarMark(
                    x: .value("Portfolio", item.name),
                    y: .value("Value", item.value)
                )
                .foregroundStyle(item.name == "Current Portfolio" ? Color.blue : Color.purple)
                .cornerRadius(6)
                .annotation(position: .top) {
                    Text(item.value.formatted(.currency(code: "EUR").precision(.fractionLength(0))))
                        .font(.caption).fontWeight(.bold).foregroundColor(.secondary)
                }
            }
            .chartLegend(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine(); AxisTick()
                    if let val = value.as(Double.self) {
                        AxisValueLabel(val.formatted(.currency(code: "EUR").notation(.compactName)))
                    }
                }
            }
            
            Spacer()
            BlueChipWatermark()
        }
        .padding()
        .frame(minHeight: 360, maxHeight: isExpanded ? .infinity : 360)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
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

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text(titleForZoom).font(.title).fontWeight(.bold)
                Spacer()
                Button(action: { dismiss() }) { Image(systemName: "xmark.circle.fill").font(.title).foregroundColor(.secondary) }.buttonStyle(.plain)
            }
            
            switch zoomType {
            case .currentPositions:
                SimulationDonutChart(data: currentPosData, title: titleForZoom, zoomType: zoomType, palette: positionColors, isExpanded: true, expandedChart: .constant(nil))
            case .simulatedPositions:
                SimulationDonutChart(data: simPosData, title: titleForZoom, zoomType: zoomType, palette: positionColors, isExpanded: true, expandedChart: .constant(nil))
            case .currentSectors:
                SimulationDonutChart(data: currentSecData, title: titleForZoom, zoomType: zoomType, palette: sectorColors, isExpanded: true, expandedChart: .constant(nil))
            case .simulatedSectors:
                SimulationDonutChart(data: simSecData, title: titleForZoom, zoomType: zoomType, palette: sectorColors, isExpanded: true, expandedChart: .constant(nil))
            case .cashAllocation:
                SimulationDonutChart(data: cashAllocData, title: titleForZoom, zoomType: zoomType, palette: marketCapColors, isExpanded: true, expandedChart: .constant(nil))
            case .totalValueCompare:
                SimulationBarChart(data: totalValData, title: titleForZoom, zoomType: zoomType, isExpanded: true, expandedChart: .constant(nil))
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
        }
    }
}

// =========================================================================
// MARK: - SHEET : AJOUT CASH SEUL
// =========================================================================

struct SimulatedCashSheet: View {
    @Environment(\.dismiss) var dismiss
    @Binding var simulatedCash: Double
    @State private var cashInput: Double? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Modify Sandbox Cash").font(.title2).fontWeight(.bold)
                Spacer()
                Button(action: { dismiss() }) { Image(systemName: "xmark.circle.fill").font(.title2).foregroundColor(.secondary) }.buttonStyle(.plain)
            }.padding()
            Divider()
            
            Form {
                Section(header: Text("Add or Remove Cash").font(.headline)) {
                    TextField("Amount to Add or Remove (€)", value: $cashInput, format: .number)
                    Text("Current Simulated Cash: \(simulatedCash.formatted(.currency(code: "EUR")))").font(.caption).foregroundColor(.secondary)
                }.padding(.bottom, 12)
            }.padding()
            
            Divider()
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Update") {
                    simulatedCash += (cashInput ?? 0.0)
                    dismiss()
                }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }.padding()
        }
        .frame(width: 350, height: 250)
    }
}

// =========================================================================
// MARK: - SHEET : AJOUT / MODIFICATION DANS LE BAC À SABLE (COMPLEXE)
// =========================================================================

enum InputMethod: String, CaseIterable {
    case shares = "Exact Shares"
    case targetWeight = "Target Weight (%)"
}

struct SimulatedAddEditSheet: View {
    @Environment(\.dismiss) var dismiss
    @Binding var simulatedPositions: [Position]
    @Binding var simulatedCash: Double
    let totalCapital: Double
    let itemToEdit: Position?
    
    @State private var ticker: String = ""
    @State private var inputMethod: InputMethod = .shares
    
    // NOUVEAU: Variables optionnelles pour afficher le Placeholder au lieu de 0
    @State private var quantityInput: Double? = nil
    @State private var targetWeightInput: Double? = nil
    @State private var pru: Double? = nil
    @State private var currentPrice: Double? = nil
    @State private var dividendPerShare: Double? = nil
    @State private var brokerTax: Double? = nil
    @State private var countryTax: Double? = nil
    
    @State private var sector: String = ""
    @State private var brokerTaxIsPercent: Bool = false
    @State private var countryTaxIsPercent: Bool = false
    @State private var adjustCash: Bool = false
    @State private var isFetching: Bool = false
    
    var isEditing: Bool { itemToEdit != nil }
    
    // Sécurité pour les optionnels
    var safePrice: Double { currentPrice ?? 0.0 }
    var safeQtyInput: Double { quantityInput ?? 0.0 }
    var safeWeightInput: Double { targetWeightInput ?? 0.0 }
    var safeBrokerTax: Double { brokerTax ?? 0.0 }
    var safeCountryTax: Double { countryTax ?? 0.0 }
    
    // Calculs dynamiques
    var calculatedQuantity: Double {
        if inputMethod == .shares { return safeQtyInput }
        else {
            guard safePrice > 0 else { return 0 }
            return (totalCapital * (safeWeightInput / 100.0)) / safePrice
        }
    }
    
    var baseCost: Double { calculatedQuantity * safePrice }
    var calcBrokerTax: Double { brokerTaxIsPercent ? baseCost * (safeBrokerTax / 100.0) : safeBrokerTax }
    var calcCountryTax: Double { countryTaxIsPercent ? baseCost * (safeCountryTax / 100.0) : safeCountryTax }
    var totalTransactionCost: Double { baseCost + calcBrokerTax + calcCountryTax }
    
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
                    
                    // STOCK INFO
                    GroupBox("Stock Info") {
                        HStack {
                            TextField("Ticker (e.g., AAPL)", text: $ticker)
                                .textFieldStyle(.roundedBorder)
                                .disabled(isEditing)
                                .onChange(of: ticker) { ticker = ticker.uppercased() }
                            
                            Button(action: fetchYahooData) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.clockwise")
                                    Text("Fetch Price")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(ticker.isEmpty || isFetching)
                        }
                        HStack(spacing: 16) {
                            TextField("Current Price", value: $currentPrice, format: .number).textFieldStyle(.roundedBorder)
                            TextField("Avg Cost / PRU", value: $pru, format: .number).textFieldStyle(.roundedBorder)
                        }
                        HStack(spacing: 16) {
                            TextField("Net Dividend / Share", value: $dividendPerShare, format: .number).textFieldStyle(.roundedBorder)
                            TextField("Sector", text: $sector).textFieldStyle(.roundedBorder)
                        }
                    }
                    
                    // PURCHASE METHOD
                    GroupBox("Purchase Method") {
                        Picker("Input Method", selection: $inputMethod) {
                            ForEach(InputMethod.allCases, id: \.self) { method in
                                Text(method.rawValue).tag(method)
                            }
                        }.pickerStyle(.segmented).padding(.bottom, 8)
                        
                        if inputMethod == .shares {
                            TextField("Number of Shares", value: $quantityInput, format: .number).textFieldStyle(.roundedBorder)
                        } else {
                            HStack {
                                TextField("Target Portfolio Weight", value: $targetWeightInput, format: .number).textFieldStyle(.roundedBorder)
                                Text("%").foregroundColor(.secondary)
                            }
                            Text("Calculated Shares: \(calculatedQuantity.formatted(.number.precision(.fractionLength(2))))").font(.caption).foregroundColor(.blue)
                        }
                    }
                    
                    // TAXES & FEES
                    GroupBox("Taxes & Fees") {
                        HStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Broker Tax").font(.caption).foregroundColor(.secondary)
                                HStack {
                                    TextField("Broker Tax", value: $brokerTax, format: .number).textFieldStyle(.roundedBorder)
                                    Picker("", selection: $brokerTaxIsPercent) {
                                        Text("€").tag(false); Text("%").tag(true)
                                    }.frame(width: 60)
                                }
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Country Tax").font(.caption).foregroundColor(.secondary)
                                HStack {
                                    TextField("Country Tax", value: $countryTax, format: .number).textFieldStyle(.roundedBorder)
                                    Picker("", selection: $countryTaxIsPercent) {
                                        Text("€").tag(false); Text("%").tag(true)
                                    }.frame(width: 60)
                                }
                            }
                        }
                    }
                    
                    // CASH IMPACT SUMMARY
                    GroupBox("Transaction Impact") {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack { Text("Base Cost (Shares x Price):"); Spacer(); Text(baseCost.formatted(.currency(code: "EUR"))) }
                            HStack { Text("Total Taxes:"); Spacer(); Text((calcBrokerTax + calcCountryTax).formatted(.currency(code: "EUR"))).foregroundColor(.red) }
                            Divider()
                            HStack { Text("Total Deduction:"); Spacer(); Text(totalTransactionCost.formatted(.currency(code: "EUR"))).fontWeight(.bold) }
                            
                            Toggle("Deduct total cost from Simulated Cash", isOn: $adjustCash).padding(.top, 8)
                            if adjustCash {
                                Text("Remaining Cash will be: \((simulatedCash - totalTransactionCost).formatted(.currency(code: "EUR")))").font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .padding()
            }
            
            Divider()
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save Simulation") { save() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).disabled(ticker.isEmpty || calculatedQuantity <= 0)
            }.padding()
        }
        .frame(width: 500, height: 750)
        .onAppear {
            if let pos = itemToEdit {
                ticker = pos.ticker
                quantityInput = pos.quantity
                pru = pos.averageCost
                currentPrice = pos.currentPrice
                dividendPerShare = pos.annualDividendNet
                sector = pos.sector
                inputMethod = .shares
            }
        }
    }
    
    private func fetchYahooData() {
        isFetching = true
        Task {
            let service = YahooFinanceService()
            if let data = await service.fetchStockData(for: ticker) {
                await MainActor.run {
                    currentPrice = data.price
                    isFetching = false
                }
            } else {
                await MainActor.run { isFetching = false }
            }
        }
    }
    
    private func save() {
        let cleanTicker = ticker.uppercased()
        
        if adjustCash {
            if isEditing, let oldPos = itemToEdit {
                simulatedCash += (oldPos.quantity * oldPos.currentPrice)
            }
            simulatedCash -= totalTransactionCost
        }
        
        let newPos = Position(
            id: itemToEdit?.id ?? UUID(),
            ticker: cleanTicker,
            quantity: calculatedQuantity,
            averageCost: pru ?? safePrice,
            currentPrice: safePrice,
            currency: "EUR",
            usdToEurRate: 1.0,
            annualDividendNet: dividendPerShare ?? 0.0,
            country: itemToEdit?.country ?? "",
            sector: sector,
            marketCap: itemToEdit?.marketCap ?? "",
            dividendMonths: itemToEdit?.dividendMonths ?? [],
            purchaseDate: itemToEdit?.purchaseDate ?? Date(),
            dividendGrowth5Y: itemToEdit?.dividendGrowth5Y ?? 0.0
        )
        
        if isEditing, let idx = simulatedPositions.firstIndex(where: { $0.id == newPos.id }) {
            simulatedPositions[idx] = newPos
        } else {
            simulatedPositions.append(newPos)
        }
        
        dismiss()
    }
}
