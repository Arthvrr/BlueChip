import SwiftUI
import Charts

// =========================================================================
// MARK: - WATCHLIST DATA MODEL
// =========================================================================

struct WatchlistItem: Identifiable, Codable {
    var id: UUID = UUID()
    var ticker: String
    var currentPrice: Double
    var targetPrice: Double
    var currentPE: Double
    var forwardPE: Double     // <-- NOUVEAU : Forward PE
    var historicalPE10Y: Double
    var guruFocusPrice: Double
    var tipRanksPrice: Double
    var peg: Double
    var currency: String = "EUR"
    var note: String = ""
    
    // Calcul du Fair Price : ((GF + TipRanks) / 2) * (1 - Margin of Safety)
    func fairPrice(marginOfSafety: Double) -> Double {
        let avgValuation = (guruFocusPrice + tipRanksPrice) / 2.0
        return avgValuation * (1.0 - (marginOfSafety / 100.0))
    }
    
    // Potentiel de hausse vers le Prix Cible (%)
    var targetUpsidePercent: Double {
        guard currentPrice > 0 else { return 0 }
        return (targetPrice - currentPrice) / currentPrice
    }
    
    // Potentiel de hausse vers le Fair Price (%)
    func fairPriceUpsidePercent(marginOfSafety: Double) -> Double {
        guard currentPrice > 0 else { return 0 }
        let fp = fairPrice(marginOfSafety: marginOfSafety)
        return (fp - currentPrice) / currentPrice
    }
}

// Zoom Enum
enum WatchListChartZoomType: String, Identifiable {
    case priceComparison, peComparison, pegComparison, potentialUpside
    var id: String { self.rawValue }
}

// =========================================================================
// MARK: - MAIN WATCHLIST VIEW
// =========================================================================

struct WatchListView: View {
    @ObservedObject var viewModel: PortfolioViewModel
    @Binding var privacyMode: Bool
    
    @State private var marginOfSafety: Double = 10.0 // 10% par défaut
    @State private var searchText: String = ""
    @State private var showAddSheet: Bool = false
    @State private var editingItem: WatchlistItem? = nil
    @State private var chartToZoom: WatchListChartZoomType? = nil
    @State private var isRefreshingPrices: Bool = false

    // Utilisation des données sauvegardées du ViewModel !
    var filteredItems: [WatchlistItem] {
        if searchText.isEmpty { return viewModel.watchlistItems }
        return viewModel.watchlistItems.filter { $0.ticker.localizedCaseInsensitiveContains(searchText) || $0.note.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 24) {
                
                // 1. DASHBOARD DE SYNTHÈSE
                WatchListDashboardSection(
                    items: viewModel.watchlistItems,
                    marginOfSafety: marginOfSafety,
                    privacyMode: $privacyMode
                )
                
                // 2. PANNEAU DE CONTRÔLE (Slider Marge de Sécurité & Actions)
                WatchListControlsSection(
                    marginOfSafety: $marginOfSafety,
                    searchText: $searchText,
                    isRefreshing: $isRefreshingPrices,
                    onAdd: { showAddSheet = true },
                    onRefresh: { refreshPrices() }
                )
                
                // 3. TABLEAU DES ENTREPRISES SUIVIES
                WatchListTableSection(
                    items: filteredItems,
                    marginOfSafety: marginOfSafety,
                    privacyMode: $privacyMode,
                    onEdit: { editingItem = $0 },
                    onDelete: { id in viewModel.watchlistItems.removeAll { $0.id == id } }
                )
                
                // 4. LES 4 GRAPHIQUES ANALYTIQUES
                WatchListChartsSection(
                    items: viewModel.watchlistItems,
                    marginOfSafety: marginOfSafety,
                    privacyMode: $privacyMode,
                    chartToZoom: $chartToZoom
                )
            }
            .padding()
        }
        .sheet(isPresented: $showAddSheet) {
            AddEditWatchListItemView(item: nil) { newItem in
                viewModel.watchlistItems.append(newItem)
            }
        }
        .sheet(item: $editingItem) { item in
            AddEditWatchListItemView(item: item) { updatedItem in
                if let idx = viewModel.watchlistItems.firstIndex(where: { $0.id == item.id }) {
                    viewModel.watchlistItems[idx] = updatedItem
                }
            }
        }
        .sheet(item: $chartToZoom) { type in
            WatchListFullScreenChartView(
                zoomType: type,
                items: viewModel.watchlistItems,
                marginOfSafety: marginOfSafety,
                privacyMode: $privacyMode
            )
        }
    }
    
    // Rafraîchissement des prix via Yahoo Finance
    func refreshPrices() {
        isRefreshingPrices = true
        Task {
            let service = YahooFinanceService()
            for idx in viewModel.watchlistItems.indices {
                if let data = await service.fetchStockData(for: viewModel.watchlistItems[idx].ticker) {
                    await MainActor.run {
                        viewModel.watchlistItems[idx].currentPrice = data.price
                        viewModel.watchlistItems[idx].currency = data.currency
                    }
                }
            }
            await MainActor.run { isRefreshingPrices = false }
        }
    }
}

// =========================================================================
// MARK: - DASHBOARD SYNTHÈSE
// =========================================================================

struct WatchListDashboardSection: View {
    let items: [WatchlistItem]
    let marginOfSafety: Double
    @Binding var privacyMode: Bool
    
    // -- Ligne 1 : Métriques existantes --
    var totalCount: Int { items.count }
    
    var undervaluedCount: Int {
        items.filter { $0.currentPrice < $0.fairPrice(marginOfSafety: marginOfSafety) }.count
    }
    
    var avgUpsideToTarget: Double {
        guard !items.isEmpty else { return 0 }
        let total = items.reduce(0.0) { $0 + $1.targetUpsidePercent }
        return total / Double(items.count)
    }
    
    var avgPEG: Double {
        guard !items.isEmpty else { return 0 }
        let total = items.reduce(0.0) { $0 + $1.peg }
        return total / Double(items.count)
    }

    // -- Ligne 2 : Nouvelles métriques --
    var avgCurrentPE: Double {
        guard !items.isEmpty else { return 0 }
        let total = items.reduce(0.0) { $0 + $1.currentPE }
        return total / Double(items.count)
    }
    
    var avgForwardPE: Double {
        guard !items.isEmpty else { return 0 }
        let total = items.reduce(0.0) { $0 + $1.forwardPE }
        return total / Double(items.count)
    }
    
    var bargainPEGCount: Int {
        items.filter { $0.peg > 0 && $0.peg <= 1.0 }.count
    }
    
    var topPickTicker: String {
        guard !items.isEmpty else { return "-" }
        // Trouve l'action avec le plus gros potentiel de hausse vers le Fair Price
        if let topStock = items.max(by: { $0.fairPriceUpsidePercent(marginOfSafety: marginOfSafety) < $1.fairPriceUpsidePercent(marginOfSafety: marginOfSafety) }) {
            return topStock.ticker
        }
        return "-"
    }

    var body: some View {
        VStack(spacing: 16) {
            // Ligne 1
            HStack(spacing: 16) {
                DashboardCard(title: "Watchlist Companies", value: "\(totalCount)", titleIcon: nil, privacyMode: .constant(false))
                DashboardCard(title: "Undervalued (Fair Price)", value: "\(undervaluedCount) / \(totalCount)", titleIcon: nil, privacyMode: .constant(false))
                DashboardCard(title: "Avg. Target Upside", value: avgUpsideToTarget.formatted(.percent.precision(.fractionLength(1)).sign(strategy: .always())), titleIcon: nil, privacyMode: .constant(false))
                DashboardCard(title: "Avg. Watchlist PEG", value: avgPEG.formatted(.number.precision(.fractionLength(2))), titleIcon: nil, privacyMode: .constant(false))
            }
            
            // Ligne 2 (Nouvelle)
            HStack(spacing: 16) {
                DashboardCard(title: "Avg. Current PE", value: avgCurrentPE > 0 ? avgCurrentPE.formatted(.number.precision(.fractionLength(1))) + "x" : "0", titleIcon: nil, privacyMode: .constant(false))
                DashboardCard(title: "Avg. Forward PE", value: avgForwardPE > 0 ? avgForwardPE.formatted(.number.precision(.fractionLength(1))) + "x" : "0", titleIcon: nil, privacyMode: .constant(false))
                DashboardCard(title: "PEG ≤ 1.0 (Bargains)", value: "\(bargainPEGCount)", titleIcon: nil, privacyMode: .constant(false))
                DashboardCard(title: "Top Pick (Fair Price)", value: topPickTicker, titleIcon: nil, privacyMode: .constant(false))
            }
        }
    }
}

// =========================================================================
// MARK: - PANNEAU DE CONTRÔLE & SLIDER MARGE DE SÉCURITÉ
// =========================================================================

struct WatchListControlsSection: View {
    @Binding var marginOfSafety: Double
    @Binding var searchText: String
    @Binding var isRefreshing: Bool
    let onAdd: () -> Void
    let onRefresh: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 24) {
                // Jauge de Marge de Sécurité
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Margin of Safety:").fontWeight(.semibold)
                        Text("\(Int(marginOfSafety))%").font(.title3).fontWeight(.bold).foregroundColor(.orange)
                        Spacer()
                    }
                    Slider(value: $marginOfSafety, in: 0...50, step: 1)
                        .tint(.orange)
                }
                .frame(maxWidth: .infinity)
                
                Divider().frame(height: 40)
                
                // Recherche & Boutons d'action
                HStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                        TextField("Search ticker, note…", text: $searchText)
                            .textFieldStyle(.plain)
                            .frame(width: 150)
                    }
                    .padding(6)
                    .background(Color(NSColor.windowBackgroundColor))
                    .cornerRadius(8)
                    
                    Button(action: onRefresh) {
                        HStack(spacing: 4) {
                            Image(systemName: isRefreshing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                                .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                                .animation(isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isRefreshing)
                            Text("Fetch Prices")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isRefreshing)
                    
                    Button(action: onAdd) {
                        Label("Add Stock", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
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
// MARK: - TABLEAU DES ACTIONS DE LA WATCHLIST
// =========================================================================

struct WatchListTableSection: View {
    let items: [WatchlistItem]
    let marginOfSafety: Double
    @Binding var privacyMode: Bool
    let onEdit: (WatchlistItem) -> Void
    let onDelete: (UUID) -> Void
    
    var body: some View {
        let isPrivate = privacyMode
        
        VStack(alignment: .leading, spacing: 8) {
            Text("Watchlist Valuation Table").font(.title2).fontWeight(.bold).foregroundColor(.secondary).padding(.bottom, 4)
            
            VStack(spacing: 0) {
                // Header
                HStack(spacing: 8) {
                    Text("Ticker").fontWeight(.bold).frame(width: 70, alignment: .leading)
                    Text("Current").fontWeight(.bold).frame(maxWidth: .infinity, alignment: .trailing)
                    Text("Target").fontWeight(.bold).frame(maxWidth: .infinity, alignment: .trailing)
                    Text("Fair Price").fontWeight(.bold).frame(maxWidth: .infinity, alignment: .trailing)
                    Text("PE Act.").fontWeight(.bold).frame(maxWidth: .infinity, alignment: .trailing)
                    Text("PE Fwd").fontWeight(.bold).frame(maxWidth: .infinity, alignment: .trailing) // <-- Ajouté
                    Text("PE 10Y").fontWeight(.bold).frame(maxWidth: .infinity, alignment: .trailing)
                    Text("PEG").fontWeight(.bold).frame(maxWidth: .infinity, alignment: .trailing)
                    Text("Upside").fontWeight(.bold).frame(maxWidth: .infinity, alignment: .trailing)
                    Text("Actions").fontWeight(.bold).frame(width: 60, alignment: .center)
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(NSColor.windowBackgroundColor))
                
                Divider()
                
                // Rows
                if items.isEmpty {
                    Text("No companies in Watchlist. Click '+ Add Stock' to get started.")
                        .foregroundColor(.secondary)
                        .padding(30)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(items) { item in
                                let fairP = item.fairPrice(marginOfSafety: marginOfSafety)
                                let upside = item.fairPriceUpsidePercent(marginOfSafety: marginOfSafety)
                                let isUndervalued = item.currentPrice < fairP
                                
                                HStack(spacing: 8) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.ticker).fontWeight(.bold)
                                        if !item.note.isEmpty {
                                            Text(item.note).font(.caption2).foregroundColor(.secondary).lineLimit(1)
                                        }
                                    }
                                    .frame(width: 70, alignment: .leading)
                                    
                                    // Prix Actuel
                                    Text(item.currentPrice.formatted(.currency(code: item.currency).precision(.fractionLength(2))))
                                        .fontWeight(.semibold)
                                        .blur(radius: isPrivate ? 6 : 0)
                                        .frame(maxWidth: .infinity, alignment: .trailing)
                                    
                                    // Prix Cible
                                    Text(item.targetPrice.formatted(.currency(code: item.currency).precision(.fractionLength(2))))
                                        .foregroundColor(.purple)
                                        .blur(radius: isPrivate ? 6 : 0)
                                        .frame(maxWidth: .infinity, alignment: .trailing)
                                    
                                    // Fair Price (Calculé)
                                    Text(fairP.formatted(.currency(code: item.currency).precision(.fractionLength(2))))
                                        .fontWeight(.bold)
                                        .foregroundColor(isUndervalued ? .green : .primary)
                                        .blur(radius: isPrivate ? 6 : 0)
                                        .frame(maxWidth: .infinity, alignment: .trailing)
                                    
                                    // PE Actuel
                                    Text(item.currentPE.formatted(.number.precision(.fractionLength(1))))
                                        .foregroundColor(item.currentPE < item.historicalPE10Y ? .green : .primary)
                                        .frame(maxWidth: .infinity, alignment: .trailing)
                                        
                                    // Forward PE (Nouveau)
                                    Text(item.forwardPE.formatted(.number.precision(.fractionLength(1))))
                                        .foregroundColor(item.forwardPE < item.currentPE ? .teal : .primary)
                                        .frame(maxWidth: .infinity, alignment: .trailing)
                                    
                                    // PE 10Y
                                    Text(item.historicalPE10Y.formatted(.number.precision(.fractionLength(1))))
                                        .foregroundColor(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .trailing)
                                    
                                    // PEG
                                    Text(item.peg.formatted(.number.precision(.fractionLength(2))))
                                        .fontWeight(.semibold)
                                        .foregroundColor(item.peg <= 1.0 ? .green : (item.peg > 2.0 ? .orange : .primary))
                                        .frame(maxWidth: .infinity, alignment: .trailing)
                                    
                                    // Potentiel Upside
                                    Text(upside.formatted(.percent.precision(.fractionLength(1)).sign(strategy: .always())))
                                        .fontWeight(.bold)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background((upside >= 0 ? Color.green : Color.red).opacity(0.15))
                                        .foregroundColor(upside >= 0 ? .green : .red)
                                        .cornerRadius(4)
                                        .blur(radius: isPrivate ? 6 : 0)
                                        .frame(maxWidth: .infinity, alignment: .trailing)
                                    
                                    // Actions
                                    HStack(spacing: 8) {
                                        Button(action: { onEdit(item) }) {
                                            Image(systemName: "pencil").foregroundColor(.secondary)
                                        }.buttonStyle(.plain)
                                        
                                        Button(action: { onDelete(item.id) }) {
                                            Image(systemName: "trash").foregroundColor(.red.opacity(0.7))
                                        }.buttonStyle(.plain)
                                    }
                                    .frame(width: 60, alignment: .center)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                
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
        .frame(height: 380)
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// =========================================================================
// MARK: - SECTION LES 4 GRAPHIQUES
// =========================================================================

struct WatchListChartsSection: View {
    let items: [WatchlistItem]
    let marginOfSafety: Double
    @Binding var privacyMode: Bool
    @Binding var chartToZoom: WatchListChartZoomType?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Watchlist Visual Analytics").font(.title2).fontWeight(.bold).foregroundColor(.secondary)
            
            // Grille 2x2
            HStack(spacing: 20) {
                WatchListPriceComparisonChart(items: items, marginOfSafety: marginOfSafety, privacyMode: $privacyMode, expandedChart: $chartToZoom)
                WatchListPEComparisonChart(items: items, privacyMode: $privacyMode, expandedChart: $chartToZoom)
            }
            HStack(spacing: 20) {
                WatchListPEGChart(items: items, privacyMode: $privacyMode, expandedChart: $chartToZoom)
                WatchListUpsideChart(items: items, marginOfSafety: marginOfSafety, privacyMode: $privacyMode, expandedChart: $chartToZoom)
            }
        }
    }
}

// -------------------------------------------------------------------------
// GRAPHE 1 : Comparatif des Prix
// -------------------------------------------------------------------------

struct PriceSeriesItem: Identifiable {
    let id = UUID()
    let ticker: String
    let type: String
    let price: Double
}

struct WatchListPriceComparisonChart: View {
    let items: [WatchlistItem]
    let marginOfSafety: Double
    @Binding var privacyMode: Bool
    var isExpanded: Bool = false
    @Binding var expandedChart: WatchListChartZoomType?
    
    @State private var hiddenSeries: Set<String> = []
    @State private var hoveredTicker: String? = nil

    var seriesData: [PriceSeriesItem] {
        var result: [PriceSeriesItem] = []
        for item in items {
            result.append(PriceSeriesItem(ticker: item.ticker, type: "Current Price", price: item.currentPrice))
            result.append(PriceSeriesItem(ticker: item.ticker, type: "Target Price", price: item.targetPrice))
            result.append(PriceSeriesItem(ticker: item.ticker, type: "GuruFocus", price: item.guruFocusPrice))
            result.append(PriceSeriesItem(ticker: item.ticker, type: "TipRanks", price: item.tipRanksPrice))
            result.append(PriceSeriesItem(ticker: item.ticker, type: "Fair Price", price: item.fairPrice(marginOfSafety: marginOfSafety)))
        }
        return result
    }
    
    let allTypes = ["Current Price", "Target Price", "GuruFocus", "TipRanks", "Fair Price"]
    
    func color(for type: String) -> Color {
        switch type {
        case "Current Price": return .blue
        case "Target Price":  return .purple
        case "GuruFocus":     return .gray
        case "TipRanks":      return .teal
        case "Fair Price":    return .green
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
                    Button(action: { expandedChart = .priceComparison }) {
                        Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary)
                    }.buttonStyle(.plain)
                }
            }.padding(.bottom, 4)
            
            InteractiveLegendView(items: allTypes, colorMap: color, hiddenItems: $hiddenSeries).padding(.bottom, 4)
            
            if items.isEmpty {
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
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine(); AxisTick()
                        if let val = value.as(Double.self) {
                            AxisValueLabel(val.formatted(.currency(code: "EUR").notation(.compactName)))
                        }
                    }
                }
            }
            
            HStack {
                Text("Hover over bars for comparison").font(.caption2).foregroundColor(.secondary)
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

// -------------------------------------------------------------------------
// GRAPHE 2 : PER Actuel vs Forward PE vs PER Historique
// -------------------------------------------------------------------------

struct WatchListPEComparisonChart: View {
    let items: [WatchlistItem]
    @Binding var privacyMode: Bool
    var isExpanded: Bool = false
    @Binding var expandedChart: WatchListChartZoomType?
    
    @State private var hiddenSeries: Set<String> = []
    @State private var hoveredTicker: String? = nil

    struct PESeriesItem: Identifiable {
        let id = UUID()
        let ticker: String
        let type: String
        let pe: Double
    }

    var seriesData: [PESeriesItem] {
        var result: [PESeriesItem] = []
        for item in items {
            result.append(PESeriesItem(ticker: item.ticker, type: "Current PE", pe: item.currentPE))
            result.append(PESeriesItem(ticker: item.ticker, type: "Forward PE", pe: item.forwardPE))
            result.append(PESeriesItem(ticker: item.ticker, type: "10Y Avg PE", pe: item.historicalPE10Y))
        }
        return result
    }

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
        let legendTypes = ["Current PE", "Forward PE", "10Y Avg PE"]
        
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if !isExpanded { Text("PE Valuation (Current vs Fwd vs 10Y)").font(.headline).foregroundColor(.secondary) }
                Spacer()
                if !isExpanded {
                    Button(action: { expandedChart = .peComparison }) {
                        Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary)
                    }.buttonStyle(.plain)
                }
            }.padding(.bottom, 4)
            
            InteractiveLegendView(items: legendTypes, colorMap: color, hiddenItems: $hiddenSeries)
                .padding(.bottom, 4)
            
            if items.isEmpty {
                Spacer(); Text("No data").foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .center); Spacer()
            } else {
                Chart(filtered) { item in
                    BarMark(
                        x: .value("Ticker", item.ticker),
                        y: .value("PE", item.pe)
                    )
                    .foregroundStyle(color(for: item.type))
                    .position(by: .value("Type", item.type))
                    .cornerRadius(4)
                    
                    if let hTicker = hoveredTicker, item.ticker == hTicker, let watchItem = items.first(where: { $0.ticker == hTicker }) {
                        RuleMark(x: .value("Ticker", hTicker))
                            .foregroundStyle(.secondary.opacity(0.4))
                            .annotation(position: .top) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(watchItem.ticker).font(.caption.bold())
                                    Text("Current PE: \(watchItem.currentPE.formatted())x").font(.caption2).foregroundColor(.orange)
                                    Text("Forward PE: \(watchItem.forwardPE.formatted())x").font(.caption2).foregroundColor(.teal)
                                    Text("10Y Avg PE: \(watchItem.historicalPE10Y.formatted())x").font(.caption2).foregroundColor(.indigo)
                                }
                                .padding(6)
                                .background(Color(NSColor.windowBackgroundColor))
                                .cornerRadius(6)
                                .shadow(radius: 3)
                            }
                    }
                }
                .chartLegend(.hidden)
                .chartXSelection(value: $hoveredTicker)
            }
            
            HStack {
                Text("Forward PE < Current PE indicates expected growth").font(.caption2).foregroundColor(.secondary)
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

// -------------------------------------------------------------------------
// GRAPHE 3 : Ratio PEG (Price/Earnings to Growth)
// -------------------------------------------------------------------------

struct WatchListPEGChart: View {
    let items: [WatchlistItem]
    @Binding var privacyMode: Bool
    var isExpanded: Bool = false
    @Binding var expandedChart: WatchListChartZoomType?
    @State private var hoveredTicker: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if !isExpanded { Text("PEG Ratio (PEG < 1.0 = Undervalued)").font(.headline).foregroundColor(.secondary) }
                Spacer()
                if !isExpanded {
                    Button(action: { expandedChart = .pegComparison }) {
                        Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary)
                    }.buttonStyle(.plain)
                }
            }.padding(.bottom, 4)
            
            if items.isEmpty {
                Spacer(); Text("No data").foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .center); Spacer()
            } else {
                Chart(items) { item in
                    BarMark(
                        x: .value("Ticker", item.ticker),
                        y: .value("PEG", item.peg)
                    )
                    .foregroundStyle(item.peg <= 1.0 ? Color.green.opacity(0.8) : (item.peg > 2.0 ? Color.orange.opacity(0.8) : Color.blue.opacity(0.8)))
                    .cornerRadius(4)
                    
                    // Ligne de référence PEG = 1.0
                    RuleMark(y: .value("Fair PEG", 1.0))
                        .foregroundStyle(Color.green)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                        .annotation(position: .top, alignment: .trailing) {
                            Text("PEG = 1.0").font(.caption2).foregroundColor(.green)
                        }
                    
                    if let hTicker = hoveredTicker, item.ticker == hTicker {
                        RuleMark(x: .value("Ticker", hTicker))
                            .foregroundStyle(.secondary.opacity(0.3))
                            .annotation(position: .top) {
                                VStack(alignment: .leading) {
                                    Text("\(item.ticker) PEG: \(item.peg.formatted(.number.precision(.fractionLength(2))))")
                                        .font(.caption.bold())
                                        .foregroundColor(item.peg <= 1.0 ? .green : .primary)
                                }
                                .padding(6)
                                .background(Color(NSColor.windowBackgroundColor))
                                .cornerRadius(6)
                            }
                    }
                }
                .chartXSelection(value: $hoveredTicker)
            }
            
            HStack {
                HStack(spacing: 12) {
                    HStack(spacing: 4) { Circle().fill(Color.green).frame(width: 8, height: 8); Text("PEG ≤ 1.0 (Bargain)").font(.caption).foregroundColor(.secondary) }
                    HStack(spacing: 4) { Circle().fill(Color.blue).frame(width: 8, height: 8); Text("1.0 < PEG ≤ 2.0").font(.caption).foregroundColor(.secondary) }
                    HStack(spacing: 4) { Circle().fill(Color.orange).frame(width: 8, height: 8); Text("PEG > 2.0 (Expensive)").font(.caption).foregroundColor(.secondary) }
                }
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

// -------------------------------------------------------------------------
// GRAPHE 4 : Potentiel de Hausse (%) (Cible vs Fair Price)
// -------------------------------------------------------------------------

struct UpsideSeriesItem: Identifiable {
    let id = UUID()
    let ticker: String
    let type: String
    let upside: Double
}

struct WatchListUpsideChart: View {
    let items: [WatchlistItem]
    let marginOfSafety: Double
    @Binding var privacyMode: Bool
    var isExpanded: Bool = false
    @Binding var expandedChart: WatchListChartZoomType?
    
    @State private var hiddenSeries: Set<String> = []
    @State private var hoveredTicker: String? = nil

    var seriesData: [UpsideSeriesItem] {
        var result: [UpsideSeriesItem] = []
        for item in items {
            result.append(UpsideSeriesItem(ticker: item.ticker, type: "Target Upside %", upside: item.targetUpsidePercent * 100))
            result.append(UpsideSeriesItem(ticker: item.ticker, type: "Fair Price Upside %", upside: item.fairPriceUpsidePercent(marginOfSafety: marginOfSafety) * 100))
        }
        return result
    }

    func color(for type: String) -> Color {
        type == "Target Upside %" ? .purple : .green
    }

    var body: some View {
        let isPrivate = privacyMode
        let filtered = seriesData.filter { !hiddenSeries.contains($0.type) }
        
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if !isExpanded { Text("Potential Upside % (Target vs Fair Price)").font(.headline).foregroundColor(.secondary) }
                Spacer()
                if !isExpanded {
                    Button(action: { expandedChart = .potentialUpside }) {
                        Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary)
                    }.buttonStyle(.plain)
                }
            }.padding(.bottom, 4)
            
            InteractiveLegendView(items: ["Target Upside %", "Fair Price Upside %"], colorMap: color, hiddenItems: $hiddenSeries)
                .padding(.bottom, 4)
            
            if items.isEmpty {
                Spacer(); Text("No data").foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .center); Spacer()
            } else {
                Chart(filtered) { item in
                    BarMark(
                        x: .value("Ticker", item.ticker),
                        y: .value("Upside %", item.upside)
                    )
                    .foregroundStyle(item.upside >= 0 ? color(for: item.type).opacity(0.8) : Color.red.opacity(0.8))
                    .position(by: .value("Type", item.type))
                    .cornerRadius(4)
                    
                    RuleMark(y: .value("Zero", 0))
                        .foregroundStyle(Color.gray.opacity(0.5))
                    
                    if let hTicker = hoveredTicker, item.ticker == hTicker, let watchItem = items.first(where: { $0.ticker == hTicker }) {
                        RuleMark(x: .value("Ticker", hTicker))
                            .foregroundStyle(.secondary.opacity(0.3))
                            .annotation(position: .top) {
                                let tUp = watchItem.targetUpsidePercent * 100
                                let fUp = watchItem.fairPriceUpsidePercent(marginOfSafety: marginOfSafety) * 100
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(watchItem.ticker).font(.caption.bold())
                                    Text("To Target: \(tUp.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always())))%").font(.caption2).foregroundColor(.purple).blur(radius: isPrivate ? 6 : 0)
                                    Text("To Fair Price: \(fUp.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always())))%").font(.caption2).foregroundColor(.green).blur(radius: isPrivate ? 6 : 0)
                                }
                                .padding(6)
                                .background(Color(NSColor.windowBackgroundColor))
                                .cornerRadius(6)
                            }
                    }
                }
                .chartLegend(.hidden)
                .chartXSelection(value: $hoveredTicker)
            }
            
            HStack {
                Text("Positive % indicates discount / upside potential").font(.caption2).foregroundColor(.secondary)
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
// MARK: - FORMULAIRE AJOUT / ÉDITION STOCK WATCHLIST
// =========================================================================

struct AddEditWatchListItemView: View {
    @Environment(\.dismiss) var dismiss
    let item: WatchlistItem?
    let onSave: (WatchlistItem) -> Void

    @State private var ticker: String = ""
    @State private var currentPrice: Double = 0.0
    @State private var targetPrice: Double = 0.0
    @State private var currentPE: Double = 0.0
    @State private var forwardPE: Double = 0.0      // <-- NOUVEAU
    @State private var historicalPE10Y: Double = 0.0
    @State private var guruFocusPrice: Double = 0.0
    @State private var tipRanksPrice: Double = 0.0
    @State private var peg: Double = 1.0
    @State private var currency: String = "EUR"
    @State private var note: String = ""
    @State private var isFetching: Bool = false

    var isEditing: Bool { item != nil }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(isEditing ? "Edit Watchlist Stock" : "Add Stock to Watchlist").font(.title2).fontWeight(.bold)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill").font(.title2).foregroundColor(.secondary)
                }.buttonStyle(.plain)
            }.padding()
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Ticker & Fetch
                    GroupBox("Company Ticker") {
                        HStack {
                            TextField("e.g. AAPL, ASML.AS", text: $ticker)
                                .textFieldStyle(.roundedBorder)
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
                    }
                    
                    // Prices Group
                    GroupBox("Price & Targets") {
                        VStack(spacing: 10) {
                            HStack {
                                Text("Current Price:").frame(width: 130, alignment: .leading)
                                TextField("Current Price", value: $currentPrice, format: .number).textFieldStyle(.roundedBorder)
                                TextField("Currency", text: $currency).textFieldStyle(.roundedBorder).frame(width: 60)
                            }
                            HStack {
                                Text("Target Price:").frame(width: 130, alignment: .leading)
                                TextField("Target Price", value: $targetPrice, format: .number).textFieldStyle(.roundedBorder)
                            }
                            HStack {
                                Text("GuruFocus Price:").frame(width: 130, alignment: .leading)
                                TextField("GuruFocus Price", value: $guruFocusPrice, format: .number).textFieldStyle(.roundedBorder)
                            }
                            HStack {
                                Text("TipRanks Price:").frame(width: 130, alignment: .leading)
                                TextField("TipRanks Price", value: $tipRanksPrice, format: .number).textFieldStyle(.roundedBorder)
                            }
                        }
                    }
                    
                    // Ratios Group
                    GroupBox("Valuation Ratios") {
                        VStack(spacing: 10) {
                            HStack {
                                Text("Current PE:").frame(width: 130, alignment: .leading)
                                TextField("Current PE", value: $currentPE, format: .number).textFieldStyle(.roundedBorder)
                            }
                            HStack {
                                Text("Forward PE:").frame(width: 130, alignment: .leading)
                                TextField("Forward PE", value: $forwardPE, format: .number).textFieldStyle(.roundedBorder)
                            }
                            HStack {
                                Text("10Y Avg PE:").frame(width: 130, alignment: .leading)
                                TextField("10Y Avg PE", value: $historicalPE10Y, format: .number).textFieldStyle(.roundedBorder)
                            }
                            HStack {
                                Text("PEG Ratio:").frame(width: 130, alignment: .leading)
                                TextField("PEG Ratio", value: $peg, format: .number).textFieldStyle(.roundedBorder)
                            }
                        }
                    }
                    
                    // Note
                    GroupBox("Note / Investment Thesis") {
                        TextField("e.g. Moat, AI Growth, Buy under 150€...", text: $note)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .padding()
            }

            Divider()
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }.padding()
        }
        .frame(width: 480, height: 560)
        .onAppear { populate() }
    }

    func populate() {
        guard let item = item else { return }
        ticker = item.ticker
        currentPrice = item.currentPrice
        targetPrice = item.targetPrice
        currentPE = item.currentPE
        forwardPE = item.forwardPE
        historicalPE10Y = item.historicalPE10Y
        guruFocusPrice = item.guruFocusPrice
        tipRanksPrice = item.tipRanksPrice
        peg = item.peg
        currency = item.currency
        note = item.note
    }

    func fetchYahooData() {
        isFetching = true
        Task {
            let service = YahooFinanceService()
            if let data = await service.fetchStockData(for: ticker) {
                await MainActor.run {
                    currentPrice = data.price
                    currency = data.currency
                    isFetching = false
                }
            } else {
                await MainActor.run { isFetching = false }
            }
        }
    }

    func save() {
        var newItem = item ?? WatchlistItem(ticker: ticker, currentPrice: currentPrice, targetPrice: targetPrice, currentPE: currentPE, forwardPE: forwardPE, historicalPE10Y: historicalPE10Y, guruFocusPrice: guruFocusPrice, tipRanksPrice: tipRanksPrice, peg: peg, currency: currency, note: note)
        newItem.ticker = ticker.uppercased()
        newItem.currentPrice = currentPrice
        newItem.targetPrice = targetPrice
        newItem.currentPE = currentPE
        newItem.forwardPE = forwardPE
        newItem.historicalPE10Y = historicalPE10Y
        newItem.guruFocusPrice = guruFocusPrice
        newItem.tipRanksPrice = tipRanksPrice
        newItem.peg = peg
        newItem.currency = currency
        newItem.note = note
        
        onSave(newItem)
    }
}

// =========================================================================
// MARK: - FULL SCREEN ZOOM MODAL
// =========================================================================

struct WatchListFullScreenChartView: View {
    @Environment(\.dismiss) var dismiss
    let zoomType: WatchListChartZoomType
    let items: [WatchlistItem]
    let marginOfSafety: Double
    @Binding var privacyMode: Bool

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Watchlist Analytics Detail").font(.title).fontWeight(.bold)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill").font(.title).foregroundColor(.secondary)
                }.buttonStyle(.plain)
            }
            
            switch zoomType {
            case .priceComparison:
                WatchListPriceComparisonChart(items: items, marginOfSafety: marginOfSafety, privacyMode: $privacyMode, isExpanded: true, expandedChart: .constant(nil))
            case .peComparison:
                WatchListPEComparisonChart(items: items, privacyMode: $privacyMode, isExpanded: true, expandedChart: .constant(nil))
            case .pegComparison:
                WatchListPEGChart(items: items, privacyMode: $privacyMode, isExpanded: true, expandedChart: .constant(nil))
            case .potentialUpside:
                WatchListUpsideChart(items: items, marginOfSafety: marginOfSafety, privacyMode: $privacyMode, isExpanded: true, expandedChart: .constant(nil))
            }
        }
        .padding(30)
        .frame(minWidth: 900, minHeight: 700)
    }
}
