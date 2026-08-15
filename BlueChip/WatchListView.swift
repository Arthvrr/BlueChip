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
    var forwardPE: Double
    var historicalPE10Y: Double
    var guruFocusPrice: Double
    var tipRanksPrice: Double
    var peg: Double
    var currency: String = "EUR"
    var note: String = ""
    
    // NOUVEAU : Sauvegarde des critères fondamentaux pour la Watchlist
    var fundamentalValues: [String: Double]?
    
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
    case priceComparison, peComparison, pegComparison, potentialUpside, labScore, labRadar
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
    
    // État global pour savoir quelle action est analysée dans le labo
    // (Permet au Zoom Plein Écran de retrouver la bonne action)
    @State private var labSelectedItemID: UUID? = nil

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
                
                // 5. LE LABORATOIRE DE QUALITÉ FONDAMENTALE
                WatchlistQualityLabSection(
                    viewModel: viewModel,
                    selectedItemID: $labSelectedItemID,
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
                privacyMode: $privacyMode,
                viewModel: viewModel,
                labSelectedItemID: $labSelectedItemID // Permet au Zoom de fonctionner
            )
        }
    }
    
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
    
    var totalCount: Int { items.count }
    var undervaluedCount: Int { items.filter { $0.currentPrice < $0.fairPrice(marginOfSafety: marginOfSafety) }.count }
    var avgUpsideToTarget: Double { guard !items.isEmpty else { return 0 }; return items.reduce(0.0) { $0 + $1.targetUpsidePercent } / Double(items.count) }
    var avgPEG: Double { guard !items.isEmpty else { return 0 }; return items.reduce(0.0) { $0 + $1.peg } / Double(items.count) }
    var avgCurrentPE: Double { guard !items.isEmpty else { return 0 }; return items.reduce(0.0) { $0 + $1.currentPE } / Double(items.count) }
    var avgForwardPE: Double { guard !items.isEmpty else { return 0 }; return items.reduce(0.0) { $0 + $1.forwardPE } / Double(items.count) }
    var bargainPEGCount: Int { items.filter { $0.peg > 0 && $0.peg <= 1.0 }.count }
    
    var topPickTicker: String {
        guard !items.isEmpty else { return "-" }
        if let topStock = items.max(by: { $0.fairPriceUpsidePercent(marginOfSafety: marginOfSafety) < $1.fairPriceUpsidePercent(marginOfSafety: marginOfSafety) }) {
            return topStock.ticker
        }
        return "-"
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                DashboardCard(title: "Watchlist Companies", value: "\(totalCount)", titleIcon: nil, privacyMode: .constant(false))
                DashboardCard(title: "Undervalued (Fair Price)", value: "\(undervaluedCount) / \(totalCount)", titleIcon: nil, privacyMode: .constant(false))
                DashboardCard(title: "Avg. Target Upside", value: avgUpsideToTarget.formatted(.percent.precision(.fractionLength(1)).sign(strategy: .always())), titleIcon: nil, privacyMode: .constant(false))
                DashboardCard(title: "Avg. Watchlist PEG", value: avgPEG.formatted(.number.precision(.fractionLength(2))), titleIcon: nil, privacyMode: .constant(false))
            }
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
// MARK: - PANNEAU DE CONTRÔLE
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
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Margin of Safety:").fontWeight(.semibold)
                        Text("\(Int(marginOfSafety))%").font(.title3).fontWeight(.bold).foregroundColor(.orange)
                        Spacer()
                    }
                    Slider(value: $marginOfSafety, in: 0...50, step: 1).tint(.orange)
                }.frame(maxWidth: .infinity)
                
                Divider().frame(height: 40)
                
                HStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                        TextField("Search ticker, note…", text: $searchText).textFieldStyle(.plain).frame(width: 150)
                    }.padding(6).background(Color(NSColor.windowBackgroundColor)).cornerRadius(8)
                    
                    Button(action: onRefresh) {
                        HStack(spacing: 4) {
                            Image(systemName: isRefreshing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                                .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                                .animation(isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isRefreshing)
                            Text("Fetch Prices")
                        }
                    }.buttonStyle(.bordered).disabled(isRefreshing)
                    
                    Button(action: onAdd) { Label("Add Stock", systemImage: "plus") }.buttonStyle(.borderedProminent)
                }
            }
        }.padding().background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// =========================================================================
// MARK: - TABLEAU DES ACTIONS
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
                HStack(spacing: 8) {
                    Text("Ticker").fontWeight(.bold).frame(width: 70, alignment: .leading)
                    Text("Current").fontWeight(.bold).frame(maxWidth: .infinity, alignment: .trailing)
                    Text("Target").fontWeight(.bold).frame(maxWidth: .infinity, alignment: .trailing)
                    Text("Fair Price").fontWeight(.bold).frame(maxWidth: .infinity, alignment: .trailing)
                    Text("PE Act.").fontWeight(.bold).frame(maxWidth: .infinity, alignment: .trailing)
                    Text("PE Fwd").fontWeight(.bold).frame(maxWidth: .infinity, alignment: .trailing)
                    Text("PE 10Y").fontWeight(.bold).frame(maxWidth: .infinity, alignment: .trailing)
                    Text("PEG").fontWeight(.bold).frame(maxWidth: .infinity, alignment: .trailing)
                    Text("Upside").fontWeight(.bold).frame(maxWidth: .infinity, alignment: .trailing)
                    Text("Actions").fontWeight(.bold).frame(width: 60, alignment: .center)
                }.font(.subheadline).foregroundColor(.secondary).padding(.horizontal, 16).padding(.vertical, 12).background(Color(NSColor.windowBackgroundColor))
                
                Divider()
                
                if items.isEmpty {
                    Text("No companies in Watchlist. Click '+ Add Stock' to get started.").foregroundColor(.secondary).padding(30)
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
                                        if !item.note.isEmpty { Text(item.note).font(.caption2).foregroundColor(.secondary).lineLimit(1) }
                                    }.frame(width: 70, alignment: .leading)
                                    
                                    Text(item.currentPrice.formatted(.currency(code: item.currency).precision(.fractionLength(2)))).fontWeight(.semibold).blur(radius: isPrivate ? 6 : 0).frame(maxWidth: .infinity, alignment: .trailing)
                                    Text(item.targetPrice.formatted(.currency(code: item.currency).precision(.fractionLength(2)))).foregroundColor(.purple).blur(radius: isPrivate ? 6 : 0).frame(maxWidth: .infinity, alignment: .trailing)
                                    Text(fairP.formatted(.currency(code: item.currency).precision(.fractionLength(2)))).fontWeight(.bold).foregroundColor(isUndervalued ? .green : .primary).blur(radius: isPrivate ? 6 : 0).frame(maxWidth: .infinity, alignment: .trailing)
                                    Text(item.currentPE.formatted(.number.precision(.fractionLength(1)))).foregroundColor(item.currentPE < item.historicalPE10Y ? .green : .primary).frame(maxWidth: .infinity, alignment: .trailing)
                                    Text(item.forwardPE.formatted(.number.precision(.fractionLength(1)))).foregroundColor(item.forwardPE < item.currentPE ? .teal : .primary).frame(maxWidth: .infinity, alignment: .trailing)
                                    Text(item.historicalPE10Y.formatted(.number.precision(.fractionLength(1)))).foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .trailing)
                                    Text(item.peg.formatted(.number.precision(.fractionLength(2)))).fontWeight(.semibold).foregroundColor(item.peg <= 1.0 ? .green : (item.peg > 2.0 ? .orange : .primary)).frame(maxWidth: .infinity, alignment: .trailing)
                                    Text(upside.formatted(.percent.precision(.fractionLength(1)).sign(strategy: .always()))).fontWeight(.bold).padding(.horizontal, 6).padding(.vertical, 2).background((upside >= 0 ? Color.green : Color.red).opacity(0.15)).foregroundColor(upside >= 0 ? .green : .red).cornerRadius(4).blur(radius: isPrivate ? 6 : 0).frame(maxWidth: .infinity, alignment: .trailing)
                                    
                                    HStack(spacing: 8) {
                                        Button(action: { onEdit(item) }) { Image(systemName: "pencil").foregroundColor(.secondary) }.buttonStyle(.plain)
                                        Button(action: { onDelete(item.id) }) { Image(systemName: "trash").foregroundColor(.red.opacity(0.7)) }.buttonStyle(.plain)
                                    }.frame(width: 60, alignment: .center)
                                }.padding(.horizontal, 16).padding(.vertical, 8)
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
// MARK: - SECTION LES 4 GRAPHIQUES ORIGINAUX
// =========================================================================

struct WatchListChartsSection: View {
    let items: [WatchlistItem]
    let marginOfSafety: Double
    @Binding var privacyMode: Bool
    @Binding var chartToZoom: WatchListChartZoomType?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Watchlist Visual Analytics").font(.title2).fontWeight(.bold).foregroundColor(.secondary)
            
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

struct PriceSeriesItem: Identifiable { let id = UUID(); let ticker: String; let type: String; let price: Double }

struct WatchListPriceComparisonChart: View {
    let items: [WatchlistItem]; let marginOfSafety: Double; @Binding var privacyMode: Bool; var isExpanded: Bool = false; @Binding var expandedChart: WatchListChartZoomType?
    @State private var hiddenSeries: Set<String> = []; @State private var hoveredTicker: String? = nil
    var seriesData: [PriceSeriesItem] { var result: [PriceSeriesItem] = []; for item in items { result.append(PriceSeriesItem(ticker: item.ticker, type: "Current Price", price: item.currentPrice)); result.append(PriceSeriesItem(ticker: item.ticker, type: "Target Price", price: item.targetPrice)); result.append(PriceSeriesItem(ticker: item.ticker, type: "GuruFocus", price: item.guruFocusPrice)); result.append(PriceSeriesItem(ticker: item.ticker, type: "TipRanks", price: item.tipRanksPrice)); result.append(PriceSeriesItem(ticker: item.ticker, type: "Fair Price", price: item.fairPrice(marginOfSafety: marginOfSafety))) }; return result }
    let allTypes = ["Current Price", "Target Price", "GuruFocus", "TipRanks", "Fair Price"]
    func color(for type: String) -> Color { switch type { case "Current Price": return .blue; case "Target Price": return .purple; case "GuruFocus": return .gray; case "TipRanks": return .teal; case "Fair Price": return .green; default: return .primary } }

    var body: some View {
        let filteredSeries = seriesData.filter { !hiddenSeries.contains($0.type) }
        VStack(alignment: .leading, spacing: 8) {
            HStack { if !isExpanded { Text("Valuation & Target Prices Comparison").font(.headline).foregroundColor(.secondary) }; Spacer(); if !isExpanded { Button(action: { expandedChart = .priceComparison }) { Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary) }.buttonStyle(.plain) } }.padding(.bottom, 4)
            InteractiveLegendView(items: allTypes, colorMap: color, hiddenItems: $hiddenSeries).padding(.bottom, 4)
            if items.isEmpty { Spacer(); Text("No data").foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .center); Spacer() } else {
                Chart(filteredSeries) { item in BarMark(x: .value("Ticker", item.ticker), y: .value("Price", item.price)).foregroundStyle(color(for: item.type)).position(by: .value("Type", item.type)).cornerRadius(4); if let hTicker = hoveredTicker, item.ticker == hTicker { RuleMark(x: .value("Ticker", hTicker)).foregroundStyle(.secondary.opacity(0.3)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4])) } }
                .chartLegend(.hidden).chartXSelection(value: $hoveredTicker).chartYAxis { AxisMarks(position: .leading) { value in AxisGridLine(); AxisTick(); if let val = value.as(Double.self) { AxisValueLabel(val.formatted(.currency(code: "EUR").notation(.compactName))) } } }
            }
            HStack { Text("Hover over bars for comparison").font(.caption2).foregroundColor(.secondary); Spacer(); BlueChipWatermark() }
        }.padding().frame(minHeight: isExpanded ? 500 : 360, maxHeight: isExpanded ? .infinity : 360).background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

struct WatchListPEComparisonChart: View {
    let items: [WatchlistItem]; @Binding var privacyMode: Bool; var isExpanded: Bool = false; @Binding var expandedChart: WatchListChartZoomType?
    @State private var hiddenSeries: Set<String> = []; @State private var hoveredTicker: String? = nil
    struct PESeriesItem: Identifiable { let id = UUID(); let ticker: String; let type: String; let pe: Double }
    var seriesData: [PESeriesItem] { var result: [PESeriesItem] = []; for item in items { result.append(PESeriesItem(ticker: item.ticker, type: "Current PE", pe: item.currentPE)); result.append(PESeriesItem(ticker: item.ticker, type: "Forward PE", pe: item.forwardPE)); result.append(PESeriesItem(ticker: item.ticker, type: "10Y Avg PE", pe: item.historicalPE10Y)) }; return result }
    func color(for type: String) -> Color { switch type { case "Current PE": return .orange; case "Forward PE": return .teal; case "10Y Avg PE": return .indigo; default: return .gray } }

    var body: some View {
        let filtered = seriesData.filter { !hiddenSeries.contains($0.type) }; let legendTypes = ["Current PE", "Forward PE", "10Y Avg PE"]
        VStack(alignment: .leading, spacing: 8) {
            HStack { if !isExpanded { Text("PE Valuation (Current vs Fwd vs 10Y)").font(.headline).foregroundColor(.secondary) }; Spacer(); if !isExpanded { Button(action: { expandedChart = .peComparison }) { Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary) }.buttonStyle(.plain) } }.padding(.bottom, 4)
            InteractiveLegendView(items: legendTypes, colorMap: color, hiddenItems: $hiddenSeries).padding(.bottom, 4)
            if items.isEmpty { Spacer(); Text("No data").foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .center); Spacer() } else {
                Chart(filtered) { item in BarMark(x: .value("Ticker", item.ticker), y: .value("PE", item.pe)).foregroundStyle(color(for: item.type)).position(by: .value("Type", item.type)).cornerRadius(4); if let hTicker = hoveredTicker, item.ticker == hTicker, let watchItem = items.first(where: { $0.ticker == hTicker }) { RuleMark(x: .value("Ticker", hTicker)).foregroundStyle(.secondary.opacity(0.4)).annotation(position: .top) { VStack(alignment: .leading, spacing: 2) { Text(watchItem.ticker).font(.caption.bold()); Text("Current PE: \(watchItem.currentPE.formatted())x").font(.caption2).foregroundColor(.orange); Text("Forward PE: \(watchItem.forwardPE.formatted())x").font(.caption2).foregroundColor(.teal); Text("10Y Avg PE: \(watchItem.historicalPE10Y.formatted())x").font(.caption2).foregroundColor(.indigo) }.padding(6).background(Color(NSColor.windowBackgroundColor)).cornerRadius(6).shadow(radius: 3) } } }
                .chartLegend(.hidden).chartXSelection(value: $hoveredTicker)
            }
            HStack { Text("Forward PE < Current PE indicates expected growth").font(.caption2).foregroundColor(.secondary); Spacer(); BlueChipWatermark() }
        }.padding().frame(minHeight: isExpanded ? 500 : 360, maxHeight: isExpanded ? .infinity : 360).background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

struct WatchListPEGChart: View {
    let items: [WatchlistItem]; @Binding var privacyMode: Bool; var isExpanded: Bool = false; @Binding var expandedChart: WatchListChartZoomType?
    @State private var hoveredTicker: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { if !isExpanded { Text("PEG Ratio (PEG < 1.0 = Undervalued)").font(.headline).foregroundColor(.secondary) }; Spacer(); if !isExpanded { Button(action: { expandedChart = .pegComparison }) { Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary) }.buttonStyle(.plain) } }.padding(.bottom, 4)
            if items.isEmpty { Spacer(); Text("No data").foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .center); Spacer() } else {
                Chart(items) { item in BarMark(x: .value("Ticker", item.ticker), y: .value("PEG", item.peg)).foregroundStyle(item.peg <= 1.0 ? Color.green.opacity(0.8) : (item.peg > 2.0 ? Color.orange.opacity(0.8) : Color.blue.opacity(0.8))).cornerRadius(4); RuleMark(y: .value("Fair PEG", 1.0)).foregroundStyle(Color.green).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4])).annotation(position: .top, alignment: .trailing) { Text("PEG = 1.0").font(.caption2).foregroundColor(.green) }; if let hTicker = hoveredTicker, item.ticker == hTicker { RuleMark(x: .value("Ticker", hTicker)).foregroundStyle(.secondary.opacity(0.3)).annotation(position: .top) { VStack(alignment: .leading) { Text("\(item.ticker) PEG: \(item.peg.formatted(.number.precision(.fractionLength(2))))").font(.caption.bold()).foregroundColor(item.peg <= 1.0 ? .green : .primary) }.padding(6).background(Color(NSColor.windowBackgroundColor)).cornerRadius(6) } } }
                .chartXSelection(value: $hoveredTicker)
            }
            HStack { HStack(spacing: 12) { HStack(spacing: 4) { Circle().fill(Color.green).frame(width: 8, height: 8); Text("PEG ≤ 1.0 (Bargain)").font(.caption).foregroundColor(.secondary) }; HStack(spacing: 4) { Circle().fill(Color.blue).frame(width: 8, height: 8); Text("1.0 < PEG ≤ 2.0").font(.caption).foregroundColor(.secondary) }; HStack(spacing: 4) { Circle().fill(Color.orange).frame(width: 8, height: 8); Text("PEG > 2.0 (Expensive)").font(.caption).foregroundColor(.secondary) } }; Spacer(); BlueChipWatermark() }
        }.padding().frame(minHeight: isExpanded ? 500 : 360, maxHeight: isExpanded ? .infinity : 360).background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

struct UpsideSeriesItem: Identifiable { let id = UUID(); let ticker: String; let type: String; let upside: Double }

struct WatchListUpsideChart: View {
    let items: [WatchlistItem]; let marginOfSafety: Double; @Binding var privacyMode: Bool; var isExpanded: Bool = false; @Binding var expandedChart: WatchListChartZoomType?
    @State private var hiddenSeries: Set<String> = []; @State private var hoveredTicker: String? = nil
    var seriesData: [UpsideSeriesItem] { var result: [UpsideSeriesItem] = []; for item in items { result.append(UpsideSeriesItem(ticker: item.ticker, type: "Target Upside %", upside: item.targetUpsidePercent * 100)); result.append(UpsideSeriesItem(ticker: item.ticker, type: "Fair Price Upside %", upside: item.fairPriceUpsidePercent(marginOfSafety: marginOfSafety) * 100)) }; return result }
    func color(for type: String) -> Color { type == "Target Upside %" ? .purple : .green }

    var body: some View {
        let isPrivate = privacyMode; let filtered = seriesData.filter { !hiddenSeries.contains($0.type) }
        VStack(alignment: .leading, spacing: 8) {
            HStack { if !isExpanded { Text("Potential Upside % (Target vs Fair Price)").font(.headline).foregroundColor(.secondary) }; Spacer(); if !isExpanded { Button(action: { expandedChart = .potentialUpside }) { Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary) }.buttonStyle(.plain) } }.padding(.bottom, 4)
            InteractiveLegendView(items: ["Target Upside %", "Fair Price Upside %"], colorMap: color, hiddenItems: $hiddenSeries).padding(.bottom, 4)
            if items.isEmpty { Spacer(); Text("No data").foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .center); Spacer() } else {
                Chart(filtered) { item in BarMark(x: .value("Ticker", item.ticker), y: .value("Upside %", item.upside)).foregroundStyle(item.upside >= 0 ? color(for: item.type).opacity(0.8) : Color.red.opacity(0.8)).position(by: .value("Type", item.type)).cornerRadius(4); RuleMark(y: .value("Zero", 0)).foregroundStyle(Color.gray.opacity(0.5)); if let hTicker = hoveredTicker, item.ticker == hTicker, let watchItem = items.first(where: { $0.ticker == hTicker }) { RuleMark(x: .value("Ticker", hTicker)).foregroundStyle(.secondary.opacity(0.3)).annotation(position: .top) { let tUp = watchItem.targetUpsidePercent * 100; let fUp = watchItem.fairPriceUpsidePercent(marginOfSafety: marginOfSafety) * 100; VStack(alignment: .leading, spacing: 2) { Text(watchItem.ticker).font(.caption.bold()); Text("To Target: \(tUp.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always())))%").font(.caption2).foregroundColor(.purple).blur(radius: isPrivate ? 6 : 0); Text("To Fair Price: \(fUp.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always())))%").font(.caption2).foregroundColor(.green).blur(radius: isPrivate ? 6 : 0) }.padding(6).background(Color(NSColor.windowBackgroundColor)).cornerRadius(6) } } }
                .chartLegend(.hidden).chartXSelection(value: $hoveredTicker)
            }
            HStack { Text("Positive % indicates discount / upside potential").font(.caption2).foregroundColor(.secondary); Spacer(); BlueChipWatermark() }
        }.padding().frame(minHeight: isExpanded ? 500 : 360, maxHeight: isExpanded ? .infinity : 360).background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// =========================================================================
// MARK: - 5. LE LABORATOIRE DE QUALITÉ FONDAMENTALE (IN-PAGE)
// =========================================================================

struct WatchlistQualityLabSection: View {
    @ObservedObject var viewModel: PortfolioViewModel
    @Binding var selectedItemID: UUID?
    @Binding var chartToZoom: WatchListChartZoomType?
    
    var selectedItemIndex: Int? {
        viewModel.watchlistItems.firstIndex(where: { $0.id == selectedItemID })
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Quality Analysis Laboratory").font(.title2).fontWeight(.bold).foregroundColor(.secondary)
            
            if viewModel.watchlistItems.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "testtube.2").font(.system(size: 40)).foregroundColor(.secondary.opacity(0.5))
                    Text("Add stocks to your watchlist first to analyze their fundamentals.")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
                .background(Color(NSColor.windowBackgroundColor))
                .cornerRadius(12)
            } else if viewModel.fundamentalCriteria.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checklist").font(.system(size: 40)).foregroundColor(.secondary.opacity(0.5))
                    Text("Define your quality criteria in the Fundamentals tab first.")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
                .background(Color(NSColor.windowBackgroundColor))
                .cornerRadius(12)
            } else {
                HStack {
                    Text("Select a stock to analyze:")
                        .fontWeight(.semibold)
                    Picker("", selection: $selectedItemID) {
                        Text("Select a stock...").tag(UUID?(nil))
                        ForEach(viewModel.watchlistItems) { item in
                            Text(item.ticker).tag(UUID?(item.id))
                        }
                    }
                    .frame(width: 200)
                    .labelsHidden()
                }
                .padding(.bottom, 8)
                
                if let idx = selectedItemIndex {
                    VStack(spacing: 24) {
                        // 1. LE FORMULAIRE EN PLEINE LARGEUR (Grille Adaptative)
                        WatchlistLabForm(viewModel: viewModel, itemIndex: idx)
                        
                        // 2. LES GRAPHIQUES EN DESSOUS (Côte à côte)
                        HStack(alignment: .top, spacing: 24) {
                            WatchlistLabScoreChart(viewModel: viewModel, itemIndex: idx, expandedChart: $chartToZoom)
                            WatchlistLabRadarChart(viewModel: viewModel, itemIndex: idx, expandedChart: $chartToZoom)
                        }
                    }
                } else {
                    Text("Please select a stock from the dropdown above to start the analysis.")
                        .italic()
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 150)
                        .background(Color(NSColor.windowBackgroundColor))
                        .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        .onAppear {
            if selectedItemID == nil && !viewModel.watchlistItems.isEmpty {
                selectedItemID = viewModel.watchlistItems.first?.id
            }
        }
    }
}

// --- SOUS-VUE : FORMULAIRE DE CRITÈRES ---
struct WatchlistLabForm: View {
    @ObservedObject var viewModel: PortfolioViewModel
    let itemIndex: Int
    
    var groupedCriteria: [(section: String, criteria: [FundamentalCriterion])] {
        let dict = Dictionary(grouping: viewModel.fundamentalCriteria, by: { $0.section })
        return dict.map { (section: $0.key, criteria: $0.value) }.sorted { $0.section < $1.section }
    }
    
    func getVal(for crit: FundamentalCriterion) -> Double {
        return viewModel.watchlistItems[itemIndex].fundamentalValues?[crit.id.uuidString] ?? 0.0
    }
    
    func setVal(for crit: FundamentalCriterion, value: Double) {
        if viewModel.watchlistItems[itemIndex].fundamentalValues == nil {
            viewModel.watchlistItems[itemIndex].fundamentalValues = [:]
        }
        viewModel.watchlistItems[itemIndex].fundamentalValues?[crit.id.uuidString] = value
        // L'update déclenchera SwiftUI automatiquement car viewModel est Observé
    }
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(groupedCriteria, id: \.section) { group in
                    GroupBox(group.section) {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(group.criteria) { crit in
                                HStack {
                                    Text(crit.name)
                                        .font(.subheadline)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    
                                    if crit.type == .boolean {
                                        Toggle("", isOn: Binding<Bool>(
                                            get: { getVal(for: crit) == 1.0 },
                                            set: { setVal(for: crit, value: $0 ? 1.0 : 0.0) }
                                        )).labelsHidden()
                                    } else {
                                        TextField("0", value: Binding<Double>(
                                            get: { getVal(for: crit) },
                                            set: { setVal(for: crit, value: $0) }
                                        ), format: .number)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 80)
                                        
                                        if crit.type == .percentage {
                                            Text("%").font(.caption).foregroundColor(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .padding(.trailing, 8)
        }
        .frame(maxHeight: 500)
    }
}

// --- SOUS-VUE : GRAPHIQUE BARRE SCORE (AVEC ZOOM ET SURVOL) ---
struct WatchlistLabScoreChart: View {
    @ObservedObject var viewModel: PortfolioViewModel
    let itemIndex: Int
    var isExpanded: Bool = false
    @Binding var expandedChart: WatchListChartZoomType?
    
    @State private var hoveredTarget: String? = nil
    
    var analyzedScore: Double {
        var total = 0.0
        for crit in viewModel.fundamentalCriteria {
            if let val = viewModel.watchlistItems[itemIndex].fundamentalValues?[crit.id.uuidString] {
                total += ScoreEngine.getScoreStatus(value: val, criterion: crit).points
            }
        }
        return total
    }
    
    var portfolioWeightedScore: Double {
        let totalVal = viewModel.positions.reduce(0) { $0 + $1.currentValueEUR }
        guard totalVal > 0 else { return 0 }
        
        return viewModel.positions.reduce(0) { sum, pos in
            let w = pos.currentValueEUR / totalVal
            var posScore = 0.0
            for crit in viewModel.fundamentalCriteria {
                if let val = pos.fundamentalValues?[crit.id.uuidString] {
                    posScore += ScoreEngine.getScoreStatus(value: val, criterion: crit).points
                }
            }
            return sum + (posScore * w)
        }
    }
    
    var maxPossibleScore: Double {
        viewModel.fundamentalCriteria.reduce(0) { $0 + ($1.weight * 2.0) }
    }
    
    var body: some View {
        let tickerStr = viewModel.watchlistItems[itemIndex].ticker
        
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if !isExpanded { Text("Analyzed Stock vs Portfolio Avg").font(.headline).foregroundColor(.secondary) }
                Spacer()
                if !isExpanded {
                    Button(action: { expandedChart = .labScore }) {
                        Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.bottom, 4)
            
            Chart {
                BarMark(
                    x: .value("Target", tickerStr),
                    y: .value("Score", analyzedScore)
                )
                .foregroundStyle(Color.purple.gradient)
                .cornerRadius(4)
                .annotation(position: .top) {
                    Text(analyzedScore.formatted(.number.precision(.fractionLength(1))))
                        .font(.caption.bold())
                }
                
                BarMark(
                    x: .value("Target", "Portfolio Avg"),
                    y: .value("Score", portfolioWeightedScore)
                )
                .foregroundStyle(Color.blue.gradient)
                .cornerRadius(4)
                .annotation(position: .top) {
                    Text(portfolioWeightedScore.formatted(.number.precision(.fractionLength(1))))
                        .font(.caption.bold())
                }
                
                if let hTarget = hoveredTarget {
                    RuleMark(x: .value("Target", hTarget))
                        .foregroundStyle(.secondary.opacity(0.3))
                        .annotation(position: .top, alignment: .center) {
                            let score = hTarget == tickerStr ? analyzedScore : portfolioWeightedScore
                            VStack {
                                Text(hTarget).font(.caption.bold())
                                Text("\(score.formatted(.number.precision(.fractionLength(1)))) pts").font(.caption2)
                            }.padding(6).background(Color(NSColor.windowBackgroundColor).opacity(0.95)).cornerRadius(6).shadow(radius: 4)
                        }
                }
            }
            .chartYScale(domain: [0, max(maxPossibleScore, 1)])
            .chartXSelection(value: $hoveredTarget)
            
            Spacer()
            BlueChipWatermark()
        }
        .padding()
        // CORRECTION ICI : Hauteur globale passée à 360 pour s'aligner parfaitement avec le radar
        .frame(minHeight: isExpanded ? 500 : 360, maxHeight: isExpanded ? .infinity : 360)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
    }
}

// --- SOUS-VUE : GRAPHIQUE RADAR (AVEC ZOOM ET LÉGENDE INTERACTIVE) ---
struct WatchlistLabRadarChart: View {
    @ObservedObject var viewModel: PortfolioViewModel
    let itemIndex: Int
    var isExpanded: Bool = false
    @Binding var expandedChart: WatchListChartZoomType?
    
    @State private var hiddenTickers: Set<String> = []
    
    var analyzedTicker: String { viewModel.watchlistItems[itemIndex].ticker }
    
    var allTickers: [String] {
        var list = viewModel.positions.map { $0.ticker }
        if !list.contains(analyzedTicker) { list.append(analyzedTicker) }
        return list.sorted()
    }
    
    func colorForTicker(_ ticker: String) -> Color {
        if ticker == analyzedTicker { return .purple }
        return viewModel.color(for: ticker)
    }
    
    var uniqueSections: [String] {
        Array(Set(viewModel.fundamentalCriteria.map { $0.section })).sorted()
    }
    
    func getScorePct(for ticker: String, section: String) -> Double {
        let crits = viewModel.fundamentalCriteria.filter { $0.section == section }
        let maxScore = crits.reduce(0) { $0 + ($1.weight * 2.0) }
        guard maxScore > 0 else { return 0 }
        
        var total = 0.0
        if ticker == analyzedTicker {
            for crit in crits {
                if let val = viewModel.watchlistItems[itemIndex].fundamentalValues?[crit.id.uuidString] {
                    total += ScoreEngine.getScoreStatus(value: val, criterion: crit).points
                }
            }
        } else if let pos = viewModel.positions.first(where: { $0.ticker == ticker }) {
            for crit in crits {
                if let val = pos.fundamentalValues?[crit.id.uuidString] {
                    total += ScoreEngine.getScoreStatus(value: val, criterion: crit).points
                }
            }
        }
        return total / maxScore
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if !isExpanded { Text("Stock Radar Profiles").font(.headline).foregroundColor(.secondary) }
                Spacer()
                if !isExpanded {
                    Button(action: { expandedChart = .labRadar }) {
                        Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.bottom, 4)
            
            InteractiveLegendView(items: allTickers, colorMap: colorForTicker, hiddenItems: $hiddenTickers)
                .padding(.bottom, 8)
            
            GeometryReader { geo in
                let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                let radius = max(0, min(geo.size.width, geo.size.height) / 2 - 25)
                let dataCount = uniqueSections.count
                
                if dataCount > 0 {
                    ZStack {
                        // Toiles d'araignées
                        ForEach(1...5, id: \.self) { i in
                            WL_RadarPolygon(dataCount: dataCount, radius: radius * CGFloat(i) / 5)
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        }
                        
                        // Axes
                        ForEach(0..<dataCount, id: \.self) { i in
                            let angle = CGFloat(i) * (2 * .pi / CGFloat(dataCount)) - .pi / 2
                            Path { p in
                                p.move(to: center)
                                p.addLine(to: CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle)))
                            }.stroke(Color.gray.opacity(0.2), lineWidth: 1)
                            
                            Text(uniqueSections[i])
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                                .position(x: center.x + (radius + 20) * cos(angle), y: center.y + (radius + 20) * sin(angle))
                        }
                        
                        // Formes des données
                        ForEach(allTickers.filter { !hiddenTickers.contains($0) }, id: \.self) { ticker in
                            let values = uniqueSections.map { getScorePct(for: ticker, section: $0) }
                            let color = colorForTicker(ticker)
                            
                            WL_RadarDataPolygon(values: values, radius: radius)
                                .fill(color.opacity(ticker == analyzedTicker ? 0.3 : 0.05))
                            WL_RadarDataPolygon(values: values, radius: radius)
                                .stroke(color, lineWidth: ticker == analyzedTicker ? 3 : 1.5)
                        }
                    }
                } else {
                    Text("No sections")
                        .foregroundColor(.secondary)
                        .position(x: center.x, y: center.y)
                }
            }
            // CORRECTION ICI : Remplacement par maxHeight: .infinity pour corriger le crash "Invalid frame dimension"
            .frame(maxHeight: .infinity)
            
            Spacer()
            BlueChipWatermark()
        }
        .padding()
        // Hauteur globale 360 pour s'aligner parfaitement avec le graphique de Score
        .frame(minHeight: isExpanded ? 500 : 360, maxHeight: isExpanded ? .infinity : 360)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
    }
}

// Formes dédiées pour le Radar (Évite les conflits de nom avec FundamentalsView)
struct WL_RadarPolygon: Shape {
    let dataCount: Int
    let radius: CGFloat
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        guard dataCount > 0 else { return path }
        for i in 0..<dataCount {
            let angle = CGFloat(i) * (2 * .pi / CGFloat(dataCount)) - .pi / 2
            let point = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

struct WL_RadarDataPolygon: Shape {
    let values: [Double]
    let radius: CGFloat
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        guard !values.isEmpty else { return path }
        for (i, val) in values.enumerated() {
            let angle = CGFloat(i) * (2 * .pi / CGFloat(values.count)) - .pi / 2
            let point = CGPoint(x: center.x + radius * CGFloat(val) * cos(angle), y: center.y + radius * CGFloat(val) * sin(angle))
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

// =========================================================================
// MARK: - FORMULAIRE AJOUT / ÉDITION STOCK WATCHLIST STANDARD
// =========================================================================

struct AddEditWatchListItemView: View {
    @Environment(\.dismiss) var dismiss
    let item: WatchlistItem?
    let onSave: (WatchlistItem) -> Void

    @State private var ticker: String = ""
    @State private var currentPrice: Double = 0.0
    @State private var targetPrice: Double = 0.0
    @State private var currentPE: Double = 0.0
    @State private var forwardPE: Double = 0.0
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
            HStack { Text(isEditing ? "Edit Watchlist Stock" : "Add Stock to Watchlist").font(.title2).fontWeight(.bold); Spacer(); Button(action: { dismiss() }) { Image(systemName: "xmark.circle.fill").font(.title2).foregroundColor(.secondary) }.buttonStyle(.plain) }.padding()
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GroupBox("Company Ticker") { HStack { TextField("e.g. AAPL, ASML.AS", text: $ticker).textFieldStyle(.roundedBorder).onChange(of: ticker) { ticker = ticker.uppercased() }; Button(action: fetchYahooData) { HStack(spacing: 4) { Image(systemName: "arrow.clockwise"); Text("Fetch Price") } }.buttonStyle(.borderedProminent).disabled(ticker.isEmpty || isFetching) } }
                    GroupBox("Price & Targets") { VStack(spacing: 10) { HStack { Text("Current Price:").frame(width: 130, alignment: .leading); TextField("Current Price", value: $currentPrice, format: .number).textFieldStyle(.roundedBorder); TextField("Currency", text: $currency).textFieldStyle(.roundedBorder).frame(width: 60) }; HStack { Text("Target Price:").frame(width: 130, alignment: .leading); TextField("Target Price", value: $targetPrice, format: .number).textFieldStyle(.roundedBorder) }; HStack { Text("GuruFocus Price:").frame(width: 130, alignment: .leading); TextField("GuruFocus Price", value: $guruFocusPrice, format: .number).textFieldStyle(.roundedBorder) }; HStack { Text("TipRanks Price:").frame(width: 130, alignment: .leading); TextField("TipRanks Price", value: $tipRanksPrice, format: .number).textFieldStyle(.roundedBorder) } } }
                    GroupBox("Valuation Ratios") { VStack(spacing: 10) { HStack { Text("Current PE:").frame(width: 130, alignment: .leading); TextField("Current PE", value: $currentPE, format: .number).textFieldStyle(.roundedBorder) }; HStack { Text("Forward PE:").frame(width: 130, alignment: .leading); TextField("Forward PE", value: $forwardPE, format: .number).textFieldStyle(.roundedBorder) }; HStack { Text("10Y Avg PE:").frame(width: 130, alignment: .leading); TextField("10Y Avg PE", value: $historicalPE10Y, format: .number).textFieldStyle(.roundedBorder) }; HStack { Text("PEG Ratio:").frame(width: 130, alignment: .leading); TextField("PEG Ratio", value: $peg, format: .number).textFieldStyle(.roundedBorder) } } }
                    GroupBox("Note / Investment Thesis") { TextField("e.g. Moat, AI Growth, Buy under 150€...", text: $note).textFieldStyle(.roundedBorder) }
                }.padding()
            }

            Divider()
            HStack { Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button("Save") { save() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent) }.padding()
        }.frame(width: 480, height: 560).onAppear { populate() }
    }

    func populate() {
        guard let item = item else { return }
        ticker = item.ticker; currentPrice = item.currentPrice; targetPrice = item.targetPrice; currentPE = item.currentPE; forwardPE = item.forwardPE; historicalPE10Y = item.historicalPE10Y; guruFocusPrice = item.guruFocusPrice; tipRanksPrice = item.tipRanksPrice; peg = item.peg; currency = item.currency; note = item.note
    }

    func fetchYahooData() {
        isFetching = true
        Task { let service = YahooFinanceService(); if let data = await service.fetchStockData(for: ticker) { await MainActor.run { currentPrice = data.price; currency = data.currency; isFetching = false } } else { await MainActor.run { isFetching = false } } }
    }

    func save() {
        var newItem = item ?? WatchlistItem(ticker: ticker, currentPrice: currentPrice, targetPrice: targetPrice, currentPE: currentPE, forwardPE: forwardPE, historicalPE10Y: historicalPE10Y, guruFocusPrice: guruFocusPrice, tipRanksPrice: tipRanksPrice, peg: peg, currency: currency, note: note)
        newItem.ticker = ticker.uppercased(); newItem.currentPrice = currentPrice; newItem.targetPrice = targetPrice; newItem.currentPE = currentPE; newItem.forwardPE = forwardPE; newItem.historicalPE10Y = historicalPE10Y; newItem.guruFocusPrice = guruFocusPrice; newItem.tipRanksPrice = tipRanksPrice; newItem.peg = peg; newItem.currency = currency; newItem.note = note
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
    
    @ObservedObject var viewModel: PortfolioViewModel
    @Binding var labSelectedItemID: UUID?

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text(titleForZoom).font(.title).fontWeight(.bold)
                Spacer()
                Button(action: { dismiss() }) { Image(systemName: "xmark.circle.fill").font(.title).foregroundColor(.secondary) }.buttonStyle(.plain)
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
            case .labScore:
                if let id = labSelectedItemID, let idx = items.firstIndex(where: { $0.id == id }) {
                    WatchlistLabScoreChart(viewModel: viewModel, itemIndex: idx, isExpanded: true, expandedChart: .constant(nil))
                } else {
                    Text("No stock selected").foregroundColor(.secondary)
                }
            case .labRadar:
                if let id = labSelectedItemID, let idx = items.firstIndex(where: { $0.id == id }) {
                    WatchlistLabRadarChart(viewModel: viewModel, itemIndex: idx, isExpanded: true, expandedChart: .constant(nil))
                } else {
                    Text("No stock selected").foregroundColor(.secondary)
                }
            }
        }.padding(30).frame(minWidth: 900, minHeight: 700)
    }
    
    var titleForZoom: String {
        switch zoomType {
        case .priceComparison: return "Valuation & Target Prices Comparison"
        case .peComparison: return "PE Valuation (Current vs Fwd vs 10Y)"
        case .pegComparison: return "PEG Ratio Analysis"
        case .potentialUpside: return "Potential Upside % (Target vs Fair Price)"
        case .labScore: return "Analyzed Stock vs Portfolio Avg"
        case .labRadar: return "Stock Radar Profile"
        }
    }
}
