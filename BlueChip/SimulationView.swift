import SwiftUI
import Charts

// =========================================================================
// MARK: - ENUMS & MODELS FOR SIMULATION
// =========================================================================

enum SimulationChartZoomType: String, Identifiable {
    case currentPositions, simulatedPositions
    case currentSectors, simulatedSectors
    var id: String { self.rawValue }
}

enum DiffType { case add, remove, modify, neutral }

struct SimulationDiff: Identifiable {
    let id = UUID()
    let text: String
    let type: DiffType
    
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
    @State private var editingSimulatedPosition: Position? = nil

    // MARK: - CALCULS SIMULATION
    var simulatedTotalValue: Double {
        simulatedPositions.reduce(0) { $0 + $1.currentValueEUR }
    }
    var simulatedTotalCapital: Double {
        simulatedTotalValue + simulatedCash
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

    // Générateur des différences (Diff)
    var simulationDiffs: [SimulationDiff] {
        var diffs = [SimulationDiff]()
        
        // Cash Diff
        if simulatedCash != viewModel.availableCash {
            let diff = simulatedCash - viewModel.availableCash
            diffs.append(SimulationDiff(
                text: diff > 0 ? "Cash increased by \(diff.formatted(.currency(code: "EUR")))" : "Cash decreased by \((-diff).formatted(.currency(code: "EUR")))",
                type: diff > 0 ? .add : .remove
            ))
        }
        
        let realDict = Dictionary(uniqueKeysWithValues: viewModel.positions.map { ($0.ticker, $0) })
        let simDict = Dictionary(uniqueKeysWithValues: simulatedPositions.map { ($0.ticker, $0) })
        
        for (ticker, simPos) in simDict {
            if let realPos = realDict[ticker] {
                if simPos.quantity != realPos.quantity {
                    let qtyDiff = simPos.quantity - realPos.quantity
                    diffs.append(SimulationDiff(
                        text: qtyDiff > 0 ? "Added \(qtyDiff.formatted()) shares of \(ticker)" : "Sold \((-qtyDiff).formatted()) shares of \(ticker)",
                        type: qtyDiff > 0 ? .add : .remove
                    ))
                }
                if simPos.averageCost != realPos.averageCost {
                    diffs.append(SimulationDiff(
                        text: "Modified \(ticker) PRU to \(simPos.averageCost.formatted(.currency(code: simPos.currency)))",
                        type: .modify
                    ))
                }
            } else {
                diffs.append(SimulationDiff(text: "New position added: \(simPos.quantity.formatted())x \(ticker)", type: .add))
            }
        }
        
        for (ticker, realPos) in realDict {
            if simDict[ticker] == nil {
                diffs.append(SimulationDiff(text: "Liquidated position: \(ticker) (\(realPos.quantity.formatted()) shares)", type: .remove))
            }
        }
        
        if diffs.isEmpty {
            diffs.append(SimulationDiff(text: "No changes. Sandbox matches current portfolio.", type: .neutral))
        }
        
        return diffs
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 24) {
                
                // 1. ONGLET DES MODIFICATIONS (DIFFS)
                SimulationDiffSection(diffs: simulationDiffs)
                
                // 2. LES DEUX TABLEAUX CÔTE À CÔTE
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
                            Button(action: { showAddSimulatedStock = true }) { Image(systemName: "plus.circle.fill").foregroundColor(.blue).font(.title3) }.buttonStyle(.plain)
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
                
                // 3. GRAPHIQUES WEIGHT BY POSITION
                HStack(spacing: 24) {
                    SimulationDonutChart(data: viewModel.allocationByPosition, title: "Current Weight by Position", zoomType: .currentPositions, palette: positionColors, expandedChart: $chartToZoom)
                    SimulationDonutChart(data: simulatedAllocationByPosition, title: "Simulated Weight by Position", zoomType: .simulatedPositions, palette: positionColors, expandedChart: $chartToZoom)
                }
                
                // 4. GRAPHIQUES SECTOR ALLOCATION
                HStack(spacing: 24) {
                    SimulationDonutChart(data: viewModel.allocationBySector, title: "Current Sector Allocation", zoomType: .currentSectors, palette: sectorColors, expandedChart: $chartToZoom)
                    SimulationDonutChart(data: simulatedAllocationBySector, title: "Simulated Sector Allocation", zoomType: .simulatedSectors, palette: sectorColors, expandedChart: $chartToZoom)
                }
                
            }
            .padding()
        }
        // RESET SUR CHARGEMENT DE LA PAGE
        .onAppear { resetSimulation() }
        .sheet(item: $chartToZoom) { type in
            SimulationFullScreenChartView(
                zoomType: type,
                currentPosData: viewModel.allocationByPosition,
                simPosData: simulatedAllocationByPosition,
                currentSecData: viewModel.allocationBySector,
                simSecData: simulatedAllocationBySector
            )
        }
        .sheet(isPresented: $showAddSimulatedStock) {
            SimulatedAddEditSheet(simulatedPositions: $simulatedPositions, simulatedCash: $simulatedCash, itemToEdit: nil)
        }
        .sheet(item: $editingSimulatedPosition) { pos in
            SimulatedAddEditSheet(simulatedPositions: $simulatedPositions, simulatedCash: $simulatedCash, itemToEdit: pos)
        }
    }
    
    private func resetSimulation() {
        simulatedPositions = viewModel.positions.map { $0 } // Copie de la structure (valeur)
        simulatedCash = viewModel.availableCash
    }
}

// =========================================================================
// MARK: - DIFF SUMMARY SECTION
// =========================================================================

struct SimulationDiffSection: View {
    let diffs: [SimulationDiff]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sandbox Modifications").font(.headline).foregroundColor(.secondary)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(diffs) { diff in
                        HStack(spacing: 6) {
                            Image(systemName: diff.icon).foregroundColor(diff.color)
                            Text(diff.text).font(.subheadline).fontWeight(.semibold)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(diff.color.opacity(0.15))
                        .cornerRadius(8)
                    }
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
// MARK: - DONUT CHART SPÉCIFIQUE À LA SIMULATION
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
            }
        }.padding(30).frame(minWidth: 900, minHeight: 700)
    }
    
    var titleForZoom: String {
        switch zoomType {
        case .currentPositions: return "Current Weight by Position"
        case .simulatedPositions: return "Simulated Weight by Position"
        case .currentSectors: return "Current Sector Allocation"
        case .simulatedSectors: return "Simulated Sector Allocation"
        }
    }
}

// =========================================================================
// MARK: - SHEET : AJOUT / MODIFICATION DANS LE BAC À SABLE
// =========================================================================

struct SimulatedAddEditSheet: View {
    @Environment(\.dismiss) var dismiss
    @Binding var simulatedPositions: [Position]
    @Binding var simulatedCash: Double
    
    let itemToEdit: Position?
    
    @State private var ticker: String = ""
    @State private var quantity: Double = 0.0
    @State private var pru: Double = 0.0
    @State private var currentPrice: Double = 0.0
    @State private var sector: String = ""
    @State private var adjustCash: Bool = false
    
    var isEditing: Bool { itemToEdit != nil }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(isEditing ? "Edit Simulated Position" : "Add Simulated Position").font(.title2).fontWeight(.bold)
                Spacer()
                Button(action: { dismiss() }) { Image(systemName: "xmark.circle.fill").font(.title2).foregroundColor(.secondary) }.buttonStyle(.plain)
            }.padding()
            Divider()
            
            Form {
                Section(header: Text("Stock Info").font(.headline)) {
                    TextField("Ticker (e.g., AAPL)", text: $ticker)
                        .disabled(isEditing) // On ne change pas le ticker d'une position existante
                    TextField("Quantity", value: $quantity, format: .number)
                    TextField("Average Cost (PRU)", value: $pru, format: .number)
                    TextField("Current Price (For Weight Calc)", value: $currentPrice, format: .number)
                    TextField("Sector", text: $sector)
                }.padding(.bottom, 12)
                
                Section(header: Text("Cash Impact").font(.headline)) {
                    Toggle("Deduct/Add cost from Simulated Cash", isOn: $adjustCash)
                    Text("Current Simulated Cash: \(simulatedCash.formatted(.currency(code: "EUR")))").font(.caption).foregroundColor(.secondary)
                }
            }.padding()
            
            Divider()
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") { save() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).disabled(ticker.isEmpty)
            }.padding()
        }
        .frame(width: 400, height: 420)
        .onAppear {
            if let pos = itemToEdit {
                ticker = pos.ticker
                quantity = pos.quantity
                pru = pos.averageCost
                currentPrice = pos.currentPrice
                sector = pos.sector
            }
        }
    }
    
    private func save() {
        let cleanTicker = ticker.uppercased()
        let valueImpact = quantity * currentPrice
        
        if adjustCash {
            if isEditing, let oldPos = itemToEdit {
                // Remettre l'ancien coût dans le cash, puis soustraire le nouveau
                simulatedCash += (oldPos.quantity * oldPos.currentPrice)
                simulatedCash -= valueImpact
            } else {
                simulatedCash -= valueImpact
            }
        }
        
        let newPos = Position(
            id: itemToEdit?.id ?? UUID(),
            ticker: cleanTicker,
            quantity: quantity,
            averageCost: pru,
            currentPrice: currentPrice,
            currency: "EUR", // Simplifié pour la simulation
            usdToEurRate: 1.0,
            annualDividendNet: itemToEdit?.annualDividendNet ?? 0.0,
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
