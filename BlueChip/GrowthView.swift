import SwiftUI
import Charts

// MARK: - SPECIFIC ZOOM ENUM FOR GROWTH
enum GrowthChartZoomType: String, Identifiable {
    case cashVsStocks, capitalVsGains, gainsProvenance
    case annualReturnsCombo, investedVsValue
    case wealthWaterfall, momMultiple // NOUVEAUX GRAPHES
    var id: String { self.rawValue }
}

struct GrowthView: View {
    @ObservedObject var viewModel: PortfolioViewModel
    @Binding var privacyMode: Bool
    
    @State private var showGoalSheet = false
    @State private var chartToZoom: GrowthChartZoomType? = nil
    
    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 24) {
                
                // 1. DASHBOARD
                GrowthDashboardSection(viewModel: viewModel, privacyMode: $privacyMode)
                
                // 2. GOAL PROGRESS
                GrowthGoalProgressBar(viewModel: viewModel, privacyMode: $privacyMode)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { showGoalSheet = true }
                
                // 3. CHARTS: COMPOSITION & GAINS (LES 3 DONUTS)
                GrowthCompositionChartsSection(viewModel: viewModel, privacyMode: $privacyMode, chartToZoom: $chartToZoom)
                
                // 4. TABLEAU DE SUIVI
                GrowthTableSection(viewModel: viewModel, privacyMode: $privacyMode)
                
                // 5. CHARTS: PERFORMANCE ANNUELLE
                GrowthPerformanceChartsSection(viewModel: viewModel, privacyMode: $privacyMode, chartToZoom: $chartToZoom)
                
                // 6. CHARTS: ADVANCED GROWTH METRICS (NOUVEAU)
                GrowthAdvancedMetricsSection(viewModel: viewModel, privacyMode: $privacyMode, chartToZoom: $chartToZoom)
            }
            .padding()
        }
        .sheet(isPresented: $showGoalSheet) { EditGrowthGoalView(viewModel: viewModel) }
        .sheet(item: $chartToZoom) { type in GrowthFullScreenChartView(zoomType: type, viewModel: viewModel, privacyMode: $privacyMode) }
    }
}

// =========================================================================
// MARK: - FORMULAIRE GOAL (Dédié à la Croissance)
// =========================================================================
struct EditGrowthGoalView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: PortfolioViewModel
    @State private var selectedGoal: GrowthGoalType
    @State private var targetInput: Double
    
    init(viewModel: PortfolioViewModel) {
        self.viewModel = viewModel
        _selectedGoal = State(initialValue: viewModel.growthGoalType)
        _targetInput = State(initialValue: viewModel.growthGoalTarget)
    }
    
    var body: some View {
        Form {
            Section(header: Text("Set Annual Growth Goal").font(.headline)) {
                Picker("Goal Type", selection: $selectedGoal) {
                    ForEach(GrowthGoalType.allCases, id: \.self) { type in Text(type.rawValue).tag(type) }
                }
                TextField("Target", value: $targetInput, format: .number)
            }.padding()
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    viewModel.growthGoalType = selectedGoal
                    viewModel.growthGoalTarget = targetInput
                    viewModel.saveData()
                    dismiss()
                }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }.padding()
        }.frame(width: 380).padding()
    }
}

// =========================================================================
// MARK: - SECTIONS DÉCOUPÉES
// =========================================================================

struct GrowthDashboardSection: View {
    @ObservedObject var viewModel: PortfolioViewModel
    @Binding var privacyMode: Bool
    
    var currentYear: Int { Calendar.current.component(.year, from: Date()) }
    
    var currentWallet: Double { viewModel.currentTotalCapital }
    var totalInvested: Double { viewModel.manuallyInvested > 0 ? viewModel.manuallyInvested : viewModel.positionsInvestedSum }

    var allTimeReturnEUR: Double { viewModel.totalROIValue }
    var allTimeReturnPercent: Double { viewModel.totalROIPercent }
    
    var activeYears: [GrowthYear] {
        viewModel.growthYears.filter { yearData in
            let isCurrentYear = yearData.year == currentYear
            let effectiveEnd = isCurrentYear ? currentWallet : yearData.endWallet
            return yearData.year <= currentYear && (yearData.startWallet > 0 || yearData.invested > 0 || effectiveEnd > 0)
        }
    }
    var activeYearsCount: Int { currentYear - viewModel.dividendStartYear + 1 }
    
    var averageReturnEUR: Double { allTimeReturnEUR / Double(max(1, activeYearsCount)) }
    
    var averageReturnPercent: Double {
        guard !activeYears.isEmpty else { return 0 }
        let totalPct = activeYears.reduce(0.0) { sum, yearData in
            let effectiveEnd = (yearData.year == currentYear) ? currentWallet : yearData.endWallet
            let base = yearData.startWallet + yearData.invested
            guard base > 0 else { return sum }
            let ret = effectiveEnd - base
            return sum + (ret / base)
        }
        return totalPct / Double(activeYears.count)
    }
    
    var cagr: Double { pow(1.0 + max(allTimeReturnPercent, -0.999), 1.0 / Double(max(1, activeYearsCount))) - 1.0 }
    
    var bestYearReturn: Double {
        let returns = activeYears.map { yearData -> Double in
            let effectiveEnd = (yearData.year == currentYear) ? currentWallet : yearData.endWallet
            let base = yearData.startWallet + yearData.invested
            guard base > 0 else { return 0 }
            return (effectiveEnd - base) / base
        }
        return returns.max() ?? 0
    }
    
    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                DashboardCard(title: "Current Wallet Value", value: currentWallet.formatted(.currency(code: "EUR").precision(.fractionLength(2))), privacyMode: $privacyMode)
                DashboardCard(title: "Total Invested", value: totalInvested.formatted(.currency(code: "EUR").precision(.fractionLength(2))), privacyMode: $privacyMode)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("All-Time Return").font(.subheadline).foregroundColor(.secondary).lineLimit(1)
                    Text(allTimeReturnEUR.formatted(.currency(code: "EUR").precision(.fractionLength(2)).sign(strategy: .always())))
                        .font(.title2).fontWeight(.bold)
                        .foregroundColor(allTimeReturnEUR >= 0 ? .green : .red)
                        .blur(radius: privacyMode ? 8 : 0)
                    Text(allTimeReturnPercent.formatted(.percent.precision(.fractionLength(2)).sign(strategy: .always())))
                        .font(.caption).padding(.horizontal, 6).padding(.vertical, 2)
                        .background((allTimeReturnEUR >= 0 ? Color.green : Color.red).opacity(0.1))
                        .foregroundColor(allTimeReturnEUR >= 0 ? .green : .red)
                        .cornerRadius(4)
                        .blur(radius: privacyMode ? 8 : 0)
                }
                .padding().frame(maxWidth: .infinity, alignment: .leading).frame(height: 110)
                .background(Color(NSColor.controlBackgroundColor)).cornerRadius(10)
                .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                
                DashboardCard(title: "Best Year Return", value: bestYearReturn.formatted(.percent.precision(.fractionLength(2))), privacyMode: $privacyMode)
            }
            HStack(spacing: 16) {
                DashboardCard(title: "Avg. Return / Year (€)", value: averageReturnEUR.formatted(.currency(code: "EUR").precision(.fractionLength(2)).sign(strategy: .always())), privacyMode: $privacyMode)
                DashboardCard(title: "Avg. Return / Year (%)", value: averageReturnPercent.formatted(.percent.precision(.fractionLength(2)).sign(strategy: .always())), privacyMode: $privacyMode)
                DashboardCard(title: "CAGR (Compound Growth)", value: cagr.formatted(.percent.precision(.fractionLength(2))), privacyMode: $privacyMode)
                DashboardCard(title: "Active Years Tracked", value: "\(activeYearsCount)", privacyMode: $privacyMode)
            }
        }
    }
}

struct GrowthGoalProgressBar: View {
    @ObservedObject var viewModel: PortfolioViewModel
    @Binding var privacyMode: Bool
    
    var currentYear: Int { Calendar.current.component(.year, from: Date()) }
    var currentYearData: GrowthYear? { viewModel.growthYears.first { $0.year == currentYear } }
    
    var isPercentGoal: Bool { viewModel.growthGoalType == .targetReturnPercent }
    var targetTitle: String { isPercentGoal ? "Target Annual Return (%)" : "Target Annual Return (€)" }
    
    var currentValueString: String {
        guard let data = currentYearData else { return "0" }
        let base = data.startWallet + data.invested
        let retAmount = viewModel.currentTotalCapital - base
        let retPercent = base > 0 ? (retAmount / base) : 0
        return isPercentGoal ? retPercent.formatted(.percent.precision(.fractionLength(2))) : retAmount.formatted(.currency(code: "EUR").precision(.fractionLength(2)))
    }
    
    var targetValueString: String {
        isPercentGoal ? (viewModel.growthGoalTarget / 100.0).formatted(.percent.precision(.fractionLength(2))) : viewModel.growthGoalTarget.formatted(.currency(code: "EUR").precision(.fractionLength(2)))
    }
    
    var progress: Double {
        guard viewModel.growthGoalTarget > 0, let data = currentYearData else { return 0 }
        let base = data.startWallet + data.invested
        let retAmount = viewModel.currentTotalCapital - base
        let retPercent = base > 0 ? (retAmount / base) : 0
        if isPercentGoal { return min(max(retPercent / (viewModel.growthGoalTarget / 100.0), 0), 1) }
        else { return min(max(retAmount / viewModel.growthGoalTarget, 0), 1) }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(targetTitle) (\(String(currentYear))) Goal").font(.headline)
                Spacer()
                Text("\(currentValueString) / \(targetValueString)").font(.subheadline).fontWeight(.bold).foregroundColor(progress >= 1 ? .green : .primary).blur(radius: privacyMode ? 8 : 0)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.windowBackgroundColor)).frame(height: 14)
                    RoundedRectangle(cornerRadius: 8).fill(LinearGradient(gradient: Gradient(colors: [.blue, .purple]), startPoint: .leading, endPoint: .trailing)).frame(width: max(0, geometry.size.width * CGFloat(progress)), height: 14).animation(.spring(), value: progress)
                }
            }.frame(height: 14)
        }
        .padding().background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1).help("Double-click to edit your Growth Goal")
    }
}

// =========================================================================
// MARK: - TABLEAU SPREADSHEET
// =========================================================================

struct GrowthTableSection: View {
    @ObservedObject var viewModel: PortfolioViewModel
    @Binding var privacyMode: Bool
    
    var currentYear: Int { Calendar.current.component(.year, from: Date()) }
    
    func cumulativeInvest(for targetYear: Int) -> Double {
        let initialWallet = viewModel.growthYears.first?.startWallet ?? 0
        let investedSum = viewModel.growthYears.filter { $0.year <= targetYear }.reduce(0) { $0 + $1.invested }
        return initialWallet + investedSum
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Capital Growth History").font(.title2).fontWeight(.bold).foregroundColor(.secondary).padding(.bottom, 4)
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text("Year").fontWeight(.bold).frame(width: 50, alignment: .leading)
                    Text("Start Wallet").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Invested").frame(maxWidth: .infinity, alignment: .leading)
                    Text("End Wallet").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Return €").fontWeight(.bold).frame(maxWidth: .infinity, alignment: .trailing)
                    Text("Return %").fontWeight(.bold).frame(maxWidth: .infinity, alignment: .trailing)
                    Text("TOTAL Invest").fontWeight(.bold).frame(maxWidth: .infinity, alignment: .trailing)
                }
                .font(.subheadline).foregroundColor(.secondary).padding(.horizontal, 16).padding(.vertical, 12).background(Color(NSColor.windowBackgroundColor))
                Divider()
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach($viewModel.growthYears) { $yearData in
                            let isCurrent = (yearData.year == currentYear)
                            GrowthRowView(
                                yearData: $yearData,
                                isCurrentYear: isCurrent,
                                liveWalletValue: viewModel.currentTotalCapital,
                                cumulativeInvest: cumulativeInvest(for: yearData.year),
                                privacyMode: privacyMode
                            )
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            Divider()
                        }
                    }
                }
            }
            .background(Color(NSColor.controlBackgroundColor)).cornerRadius(8).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))
        }
        .frame(height: 380).padding().background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

struct GrowthRowView: View {
    @Binding var yearData: GrowthYear
    let isCurrentYear: Bool
    let liveWalletValue: Double
    let cumulativeInvest: Double
    let privacyMode: Bool
    
    var effectiveEndWallet: Double { isCurrentYear ? liveWalletValue : yearData.endWallet }
    var displayReturnAmount: Double { effectiveEndWallet - yearData.startWallet - yearData.invested }
    var displayReturnPercent: Double { let base = yearData.startWallet + yearData.invested; guard base > 0 else { return 0 }; return displayReturnAmount / base }
    var isBlankYear: Bool { yearData.startWallet == 0 && yearData.invested == 0 && effectiveEndWallet == 0 && !isCurrentYear }
    var isZeroReturn: Bool { abs(displayReturnAmount) < 0.001 }
    
    var body: some View {
        HStack(spacing: 8) {
            Text(String(yearData.year)).fontWeight(.bold).frame(width: 50, alignment: .leading) // Year stays visible
            
            GrowthField(value: $yearData.startWallet, privacyMode: privacyMode)
            GrowthField(value: $yearData.invested, privacyMode: privacyMode)
            
            if isCurrentYear {
                Text(liveWalletValue.formatted(.number.precision(.fractionLength(2))))
                    .frame(maxWidth: .infinity, alignment: .leading).foregroundColor(.secondary)
                    .blur(radius: privacyMode ? 6 : 0)
                    .help("Live portfolio value")
            } else {
                GrowthField(value: $yearData.endWallet, privacyMode: privacyMode)
            }
            
            if isBlankYear {
                Text("-").frame(maxWidth: .infinity, alignment: .trailing).foregroundColor(.secondary)
                Text("-").frame(maxWidth: .infinity, alignment: .trailing).foregroundColor(.secondary)
            } else if isZeroReturn {
                Text("0,00 €").fontWeight(.bold).foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .trailing).blur(radius: privacyMode ? 6 : 0)
                Text("0,00%").fontWeight(.bold).foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .trailing).blur(radius: privacyMode ? 6 : 0)
            } else {
                Text(displayReturnAmount.formatted(.currency(code: "EUR").precision(.fractionLength(2)).sign(strategy: .always())))
                    .fontWeight(.bold).foregroundColor(displayReturnAmount > 0 ? .green : .red).frame(maxWidth: .infinity, alignment: .trailing)
                    .blur(radius: privacyMode ? 6 : 0)
                
                Text(displayReturnPercent.formatted(.percent.precision(.fractionLength(2)).sign(strategy: .always())))
                    .fontWeight(.bold).padding(.horizontal, 8).padding(.vertical, 2)
                    .background((displayReturnPercent > 0 ? Color.green : Color.red).opacity(0.1))
                    .foregroundColor(displayReturnPercent > 0 ? .green : .red).cornerRadius(4)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .blur(radius: privacyMode ? 6 : 0)
            }
            
            Text(cumulativeInvest.formatted(.currency(code: "EUR").precision(.fractionLength(2))))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .foregroundColor(cumulativeInvest == 0 ? .secondary.opacity(0.5) : .primary)
                .blur(radius: privacyMode ? 6 : 0)
        }
    }
}

struct GrowthField: View {
    @Binding var value: Double
    var privacyMode: Bool
    var body: some View {
        TextField("0", value: $value, format: .number)
            .textFieldStyle(.plain).frame(maxWidth: .infinity, alignment: .leading)
            .blur(radius: privacyMode ? 6 : 0)
    }
}

// =========================================================================
// MARK: - SECTIONS DE GRAPHIQUES
// =========================================================================

struct GrowthCompositionChartsSection: View {
    @ObservedObject var viewModel: PortfolioViewModel
    @Binding var privacyMode: Bool
    @Binding var chartToZoom: GrowthChartZoomType?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Portfolio Structure & Gains").font(.title2).fontWeight(.bold).foregroundColor(.secondary)
            HStack(spacing: 16) {
                CashVsStocksChart(viewModel: viewModel, expandedChart: $chartToZoom)
                CapitalVsGainsChart(viewModel: viewModel, expandedChart: $chartToZoom)
                GainsProvenanceChart(viewModel: viewModel, expandedChart: $chartToZoom)
            }
        }
    }
}

struct GrowthPerformanceChartsSection: View {
    @ObservedObject var viewModel: PortfolioViewModel
    @Binding var privacyMode: Bool
    @Binding var chartToZoom: GrowthChartZoomType?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Annual Performance & Long Term Growth").font(.title2).fontWeight(.bold).foregroundColor(.secondary)
            HStack(spacing: 24) {
                AnnualReturnsComboChart(viewModel: viewModel, expandedChart: $chartToZoom)
                InvestedVsValueChart(viewModel: viewModel, expandedChart: $chartToZoom)
            }
        }
    }
}

struct GrowthAdvancedMetricsSection: View {
    @ObservedObject var viewModel: PortfolioViewModel
    @Binding var privacyMode: Bool
    @Binding var chartToZoom: GrowthChartZoomType?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Advanced Wealth Metrics").font(.title2).fontWeight(.bold).foregroundColor(.secondary)
            HStack(spacing: 24) {
                WealthWaterfallChart(viewModel: viewModel, expandedChart: $chartToZoom)
                MoICMultipleChart(viewModel: viewModel, expandedChart: $chartToZoom)
            }
        }
    }
}

// =========================================================================
// MARK: - COMPOSANTS GRAPHIQUES INDIVIDUELS
// =========================================================================

// CHART 1: Cash vs Stocks (Donut)
struct CashVsStocksChart: View {
    @ObservedObject var viewModel: PortfolioViewModel
    var isExpanded: Bool = false
    @Binding var expandedChart: GrowthChartZoomType?
    
    @State private var selectedAngleValue: Double? = nil
    @State private var hiddenItems: Set<String> = []
    
    var data: [ChartDataItem] {
        let stockValue = viewModel.positions.reduce(0) { $0 + $1.currentValueEUR }
        return [
            ChartDataItem(name: "Cash", value: viewModel.availableCash),
            ChartDataItem(name: "Stocks", value: stockValue)
        ].sorted { $0.value > $1.value }
    }
    
    var filteredData: [ChartDataItem] { data.filter { !hiddenItems.contains($0.name) } }
    func color(for name: String) -> Color { name == "Cash" ? .yellow.opacity(0.6) : .blue.opacity(0.4) }
    
    var body: some View {
        VStack {
            HStack {
                if !isExpanded { Text("Cash vs Stocks").font(.headline).foregroundColor(.secondary) }
                Spacer()
                if !isExpanded { Button(action: { expandedChart = .cashVsStocks }) { Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary) }.buttonStyle(.plain) }
            }.padding(.bottom, 4)
            
            InteractiveLegendView(items: data.map { $0.name }, colorMap: color, hiddenItems: $hiddenItems).padding(.bottom, 8)
            
            if filteredData.isEmpty { Spacer(); Text("No data").foregroundColor(.secondary); Spacer() } else {
                Chart(filteredData) { item in
                    SectorMark(angle: .value("Value", item.value), innerRadius: .ratio(0.65), angularInset: 1.5)
                        .foregroundStyle(color(for: item.name))
                        .cornerRadius(4)
                }
                .chartLegend(.hidden)
                .chartAngleSelection(value: $selectedAngleValue)
                .chartBackground { proxy in
                    GeometryReader { geometry in
                        if let value = selectedAngleValue, let item = findItem(for: value) {
                            VStack {
                                Text(item.name).font(.headline)
                                Text(item.value.formatted(.currency(code: "EUR").precision(.fractionLength(2)))).font(.subheadline).foregroundColor(.secondary)
                            }.position(x: geometry.frame(in: .local).midX, y: geometry.frame(in: .local).midY)
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: selectedAngleValue)
            }
            BlueChipWatermark()
        }
        .padding()
        .frame(minHeight: isExpanded ? 500 : 300, maxHeight: isExpanded ? .infinity : 300)
        .background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    func findItem(for value: Double) -> ChartDataItem? { var cum = 0.0; for item in filteredData { cum += item.value; if value <= cum { return item } }; return filteredData.last }
}

// CHART 2: Source de la valeur (Capital vs Gain)
struct CapitalVsGainsChart: View {
    @ObservedObject var viewModel: PortfolioViewModel
    var isExpanded: Bool = false
    @Binding var expandedChart: GrowthChartZoomType?
    
    @State private var selectedAngleValue: Double? = nil
    @State private var hiddenItems: Set<String> = []
    
    var data: [ChartDataItem] {
        let invested = viewModel.manuallyInvested > 0 ? viewModel.manuallyInvested : viewModel.positionsInvestedSum
        let gain = max(0, viewModel.currentTotalCapital - invested)
        return [
            ChartDataItem(name: "Invested", value: invested),
            ChartDataItem(name: "Total Gain", value: gain)
        ].sorted { $0.value > $1.value }
    }
    
    var filteredData: [ChartDataItem] { data.filter { !hiddenItems.contains($0.name) } }
    func color(for name: String) -> Color { name == "Invested" ? .gray.opacity(0.3) : .green.opacity(0.6) }
    
    var body: some View {
        VStack {
            HStack {
                if !isExpanded { Text("Value Source").font(.headline).foregroundColor(.secondary) }
                Spacer()
                if !isExpanded { Button(action: { expandedChart = .capitalVsGains }) { Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary) }.buttonStyle(.plain) }
            }.padding(.bottom, 4)
            
            InteractiveLegendView(items: data.map { $0.name }, colorMap: color, hiddenItems: $hiddenItems).padding(.bottom, 8)
            
            if filteredData.isEmpty { Spacer(); Text("No data").foregroundColor(.secondary); Spacer() } else {
                Chart(filteredData) { item in
                    SectorMark(angle: .value("Value", item.value), innerRadius: .ratio(0.65), angularInset: 1.5)
                        .foregroundStyle(color(for: item.name))
                        .cornerRadius(4)
                }
                .chartLegend(.hidden)
                .chartAngleSelection(value: $selectedAngleValue)
                .chartBackground { proxy in
                    GeometryReader { geometry in
                        if let value = selectedAngleValue, let item = findItem(for: value) {
                            VStack {
                                Text(item.name).font(.headline)
                                Text(item.value.formatted(.currency(code: "EUR").precision(.fractionLength(2)))).font(.subheadline).foregroundColor(.secondary)
                            }.position(x: geometry.frame(in: .local).midX, y: geometry.frame(in: .local).midY)
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: selectedAngleValue)
            }
            BlueChipWatermark()
        }
        .padding()
        .frame(minHeight: isExpanded ? 500 : 300, maxHeight: isExpanded ? .infinity : 300)
        .background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    func findItem(for value: Double) -> ChartDataItem? { var cum = 0.0; for item in filteredData { cum += item.value; if value <= cum { return item } }; return filteredData.last }
}

// CHART 3: Provenance des gains (Dividendes vs Plus-Value)
struct GainsProvenanceChart: View {
    @ObservedObject var viewModel: PortfolioViewModel
    var isExpanded: Bool = false
    @Binding var expandedChart: GrowthChartZoomType?
    
    @State private var selectedAngleValue: Double? = nil
    @State private var hiddenItems: Set<String> = []
    
    var data: [ChartDataItem] {
        let invested = viewModel.manuallyInvested > 0 ? viewModel.manuallyInvested : viewModel.positionsInvestedSum
        let totalGain = max(0, viewModel.currentTotalCapital - invested)
        
        let totalDiv = viewModel.dividendYears.reduce(0) { $0 + $1.total }
        let plusValue = max(0, totalGain - totalDiv)
        
        return [
            ChartDataItem(name: "Dividends", value: totalDiv),
            ChartDataItem(name: "Capital Gain", value: plusValue)
        ].sorted { $0.value > $1.value }
    }
    
    var filteredData: [ChartDataItem] { data.filter { !hiddenItems.contains($0.name) } }
    func color(for name: String) -> Color { name == "Dividends" ? .green.opacity(0.3) : .green.opacity(0.7) }
    
    var body: some View {
        VStack {
            HStack {
                if !isExpanded { Text("Gains Source").font(.headline).foregroundColor(.secondary) }
                Spacer()
                if !isExpanded { Button(action: { expandedChart = .gainsProvenance }) { Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary) }.buttonStyle(.plain) }
            }.padding(.bottom, 4)
            
            InteractiveLegendView(items: data.map { $0.name }, colorMap: color, hiddenItems: $hiddenItems).padding(.bottom, 8)
            
            if filteredData.isEmpty { Spacer(); Text("No data").foregroundColor(.secondary); Spacer() } else {
                Chart(filteredData) { item in
                    SectorMark(angle: .value("Value", item.value), innerRadius: .ratio(0.65), angularInset: 1.5)
                        .foregroundStyle(color(for: item.name))
                        .cornerRadius(4)
                }
                .chartLegend(.hidden)
                .chartAngleSelection(value: $selectedAngleValue)
                .chartBackground { proxy in
                    GeometryReader { geometry in
                        if let value = selectedAngleValue, let item = findItem(for: value) {
                            VStack {
                                Text(item.name).font(.headline)
                                Text(item.value.formatted(.currency(code: "EUR").precision(.fractionLength(2)))).font(.subheadline).foregroundColor(.secondary)
                            }.position(x: geometry.frame(in: .local).midX, y: geometry.frame(in: .local).midY)
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: selectedAngleValue)
            }
            BlueChipWatermark()
        }
        .padding()
        .frame(minHeight: isExpanded ? 500 : 300, maxHeight: isExpanded ? .infinity : 300)
        .background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    func findItem(for value: Double) -> ChartDataItem? { var cum = 0.0; for item in filteredData { cum += item.value; if value <= cum { return item } }; return filteredData.last }
}

// CHART 4: Annual Returns
struct AnnualReturnsComboChart: View {
    @ObservedObject var viewModel: PortfolioViewModel
    var isExpanded: Bool = false
    @Binding var expandedChart: GrowthChartZoomType?

    var currentYear: Int { Calendar.current.component(.year, from: Date()) }

    struct AnnualReturnItem: Identifiable {
        let id = UUID()
        let year: Int
        let returnEUR: Double
        let returnPercent: Double
    }

    var data: [AnnualReturnItem] {
        let startYear = viewModel.dividendStartYear
        return (startYear...currentYear).compactMap { year in
            guard let yearData = viewModel.growthYears.first(where: { $0.year == year }) else { return nil }
            let effectiveEnd = (year == currentYear) ? viewModel.currentTotalCapital : yearData.endWallet
            let base = yearData.startWallet + yearData.invested
            let retEUR = effectiveEnd - base
            let retPct = base > 0 ? (retEUR / base) * 100.0 : 0
            return AnnualReturnItem(year: year, returnEUR: retEUR, returnPercent: retPct)
        }
    }

    var maxAbsEUR: Double { max(data.map { abs($0.returnEUR) }.max() ?? 1, 1) }
    var maxAbsPct: Double { max(data.map { abs($0.returnPercent) }.max() ?? 1, 1) }
    func scaledPct(_ pct: Double) -> Double { (pct / maxAbsPct) * maxAbsEUR }

    @State private var hiddenSeries: Set<String> = []
    @State private var hoveredYear: String? = nil

    var hoveredItem: AnnualReturnItem? {
        guard let y = hoveredYear, let yr = Int(y) else { return nil }
        return data.first { $0.year == yr }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if !isExpanded { Text("Annual Returns").font(.headline).foregroundColor(.secondary) }
                Spacer()
                HStack(spacing: 12) {
                    Button(action: { withAnimation { toggle("Return €") } }) {
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 2).fill(Color.blue.opacity(0.55)).frame(width: 12, height: 12)
                            Text("Return €").font(.caption).foregroundColor(hiddenSeries.contains("Return €") ? .secondary : .primary)
                        }
                    }.buttonStyle(.plain).opacity(hiddenSeries.contains("Return €") ? 0.4 : 1.0)

                    Button(action: { withAnimation { toggle("Return %") } }) {
                        HStack(spacing: 4) {
                            Circle().fill(Color.orange).frame(width: 8, height: 8)
                            Text("Return %").font(.caption).foregroundColor(hiddenSeries.contains("Return %") ? .secondary : .primary)
                        }
                    }.buttonStyle(.plain).opacity(hiddenSeries.contains("Return %") ? 0.4 : 1.0)
                }
                if !isExpanded { Button(action: { expandedChart = .annualReturnsCombo }) { Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary) }.buttonStyle(.plain).padding(.leading, 8) }
            }.padding(.bottom, 4)

            if let item = hoveredItem {
                HStack(spacing: 16) {
                    Text(String(item.year)).fontWeight(.bold)
                    Text(item.returnEUR.formatted(.currency(code: "EUR").precision(.fractionLength(2)).sign(strategy: .always())))
                        .foregroundColor(item.returnEUR >= 0 ? .green : .red).fontWeight(.semibold)
                    Text(String(format: "%+.2f%%", item.returnPercent))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background((item.returnPercent >= 0 ? Color.green : Color.red).opacity(0.1))
                        .foregroundColor(item.returnPercent >= 0 ? .green : .red)
                        .cornerRadius(4).fontWeight(.semibold)
                }
                .font(.caption).padding(.horizontal, 8).padding(.vertical, 4).background(Color(NSColor.windowBackgroundColor)).cornerRadius(6).transition(.opacity)
            }

            if data.isEmpty {
                Spacer()
                Text("Fill in the Growth table to see annual returns.").foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                Chart {
                    if !hiddenSeries.contains("Return €") {
                        ForEach(data) { item in
                            BarMark(x: .value("Year", String(item.year)), y: .value("Return €", item.returnEUR))
                                .foregroundStyle(item.returnEUR >= 0 ? Color.blue.opacity(0.55) : Color.red.opacity(0.55)).cornerRadius(4)
                                .opacity(hoveredYear == nil || hoveredYear == String(item.year) ? 1.0 : 0.4)
                        }
                    }
                    if !hiddenSeries.contains("Return %") {
                        ForEach(data) { item in
                            LineMark(x: .value("Year", String(item.year)), y: .value("Return % (scaled)", scaledPct(item.returnPercent)))
                                .foregroundStyle(Color.orange).lineStyle(StrokeStyle(lineWidth: 2))
                                .symbol { Circle().fill(item.returnPercent >= 0 ? Color.orange : Color.red).frame(width: 7, height: 7) }
                        }
                    }
                }
                .chartXSelection(value: $hoveredYear)
                .chartYAxis { AxisMarks(position: .leading) { value in AxisGridLine(); AxisTick(); AxisValueLabel { if let v = value.as(Double.self) { Text(v.formatted(.currency(code: "EUR").precision(.fractionLength(0)))).font(.system(size: 10)) } } } }
                .chartXAxis { AxisMarks { value in AxisValueLabel { if let s = value.as(String.self) { Text(s).font(.caption) } } } }
                .animation(.easeInOut(duration: 0.15), value: hoveredYear)
            }
            BlueChipWatermark()
        }
        .padding().frame(minHeight: isExpanded ? 500 : 300, maxHeight: isExpanded ? .infinity : 300).background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    func toggle(_ key: String) { if hiddenSeries.contains(key) { hiddenSeries.remove(key) } else { hiddenSeries.insert(key) } }
}

// CHART 5: Invested cumulé vs Valeur
struct InvestedVsValueChart: View {
    @ObservedObject var viewModel: PortfolioViewModel
    var isExpanded: Bool = false
    @Binding var expandedChart: GrowthChartZoomType?

    var currentYear: Int { Calendar.current.component(.year, from: Date()) }

    struct InvestedVsValueItem: Identifiable { let id = UUID(); let year: Int; let category: String; let value: Double }

    var cleanData: [InvestedVsValueItem] {
        let startYear = viewModel.dividendStartYear; var items: [InvestedVsValueItem] = []; var cumInvested: Double = 0
        for year in startYear...currentYear {
            guard let yearData = viewModel.growthYears.first(where: { $0.year == year }) else { continue }
            cumInvested += yearData.invested
            let effectiveEnd = (year == currentYear) ? viewModel.currentTotalCapital : yearData.endWallet
            items.append(InvestedVsValueItem(year: year, category: "Portfolio Value", value: effectiveEnd))
            items.append(InvestedVsValueItem(year: year, category: "Cumulative Invested", value: cumInvested + (viewModel.growthYears.first?.startWallet ?? 0)))
        }
        return items
    }

    var portfolioItems: [InvestedVsValueItem] { cleanData.filter { $0.category == "Portfolio Value" } }
    var investedItems: [InvestedVsValueItem] { cleanData.filter { $0.category == "Cumulative Invested" } }

    @State private var hiddenItems: Set<String> = []; @State private var hoveredYear: String? = nil
    var hoveredPortfolio: InvestedVsValueItem? { guard let y = hoveredYear else { return nil }; return portfolioItems.first { String($0.year) == y } }
    var hoveredInvested: InvestedVsValueItem? { guard let y = hoveredYear else { return nil }; return investedItems.first { String($0.year) == y } }

    func color(for category: String) -> Color { category == "Portfolio Value" ? .blue : .gray.opacity(0.6) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if !isExpanded { Text("Invested vs Portfolio Value").font(.headline).foregroundColor(.secondary) }
                Spacer()
                InteractiveLegendView(items: ["Portfolio Value", "Cumulative Invested"], colorMap: color, hiddenItems: $hiddenItems)
                if !isExpanded { Button(action: { expandedChart = .investedVsValue }) { Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary) }.buttonStyle(.plain).padding(.leading, 8) }
            }.padding(.bottom, 4)

            if let pItem = hoveredPortfolio {
                HStack(spacing: 16) {
                    Text(String(pItem.year)).fontWeight(.bold)
                    if !hiddenItems.contains("Portfolio Value") { HStack(spacing: 4) { Circle().fill(Color.blue).frame(width: 7, height: 7); Text(pItem.value.formatted(.currency(code: "EUR").precision(.fractionLength(0)))).foregroundColor(.blue).fontWeight(.semibold) } }
                    if !hiddenItems.contains("Cumulative Invested"), let iItem = hoveredInvested { HStack(spacing: 4) { Circle().fill(Color.gray).frame(width: 7, height: 7); Text(iItem.value.formatted(.currency(code: "EUR").precision(.fractionLength(0)))).foregroundColor(.secondary).fontWeight(.semibold) } }
                    if let iItem = hoveredInvested, !hiddenItems.contains("Portfolio Value"), !hiddenItems.contains("Cumulative Invested") {
                        let diff = pItem.value - iItem.value
                        Text(diff.formatted(.currency(code: "EUR").precision(.fractionLength(0)).sign(strategy: .always()))).foregroundColor(diff >= 0 ? .green : .red).fontWeight(.bold)
                    }
                }
                .font(.caption).padding(.horizontal, 8).padding(.vertical, 4).background(Color(NSColor.windowBackgroundColor)).cornerRadius(6).transition(.opacity)
            }

            if cleanData.isEmpty {
                Spacer()
                Text("Fill in the Growth table to see the evolution.").foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                Chart {
                    if !hiddenItems.contains("Portfolio Value") {
                        ForEach(portfolioItems) { item in
                            AreaMark(x: .value("Year", String(item.year)), y: .value("€", item.value), series: .value("Series", "portfolio"))
                                .foregroundStyle(LinearGradient(colors: [Color.blue.opacity(0.35), Color.blue.opacity(0.05)], startPoint: .top, endPoint: .bottom)).interpolationMethod(.monotone)
                            LineMark(x: .value("Year", String(item.year)), y: .value("€", item.value), series: .value("Series", "portfolio"))
                                .foregroundStyle(Color.blue).lineStyle(StrokeStyle(lineWidth: 2.5)).interpolationMethod(.monotone).symbol { Circle().fill(Color.blue).frame(width: 7, height: 7) }
                        }
                    }
                    if !hiddenItems.contains("Cumulative Invested") {
                        ForEach(investedItems) { item in
                            LineMark(x: .value("Year", String(item.year)), y: .value("€", item.value), series: .value("Series", "invested"))
                                .foregroundStyle(Color.gray.opacity(0.7)).lineStyle(StrokeStyle(lineWidth: 2, dash: [6, 4])).interpolationMethod(.linear).symbol { Circle().fill(Color.gray).frame(width: 6, height: 6) }
                        }
                    }
                    if let y = hoveredYear { RuleMark(x: .value("Year", y)).foregroundStyle(Color.secondary.opacity(0.4)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3])) }
                }
                .chartXSelection(value: $hoveredYear)
                .chartYAxis { AxisMarks(position: .leading) { value in AxisGridLine(); AxisTick(); AxisValueLabel { if let v = value.as(Double.self) { Text(v.formatted(.currency(code: "EUR").precision(.fractionLength(0)))).font(.system(size: 10)) } } } }
                .chartXAxis { AxisMarks { value in AxisValueLabel { if let s = value.as(String.self) { Text(s).font(.caption) } } } }
                .animation(.easeInOut(duration: 0.1), value: hoveredYear)
            }
            BlueChipWatermark()
        }
        .padding().frame(minHeight: isExpanded ? 500 : 300, maxHeight: isExpanded ? .infinity : 300).background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// --- CHART 6 (NOUVEAU) : WEALTH WATERFALL CHART ---
struct WaterfallItem: Identifiable { let id = UUID(); let name: String; let start: Double; let end: Double; let color: Color }

struct WealthWaterfallChart: View {
    @ObservedObject var viewModel: PortfolioViewModel
    var isExpanded: Bool = false
    @Binding var expandedChart: GrowthChartZoomType?
    
    var data: [WaterfallItem] {
        let currentYear = Calendar.current.component(.year, from: Date())
        let startWallet = viewModel.growthYears.first?.startWallet ?? 0.0
        let totalDeposits = viewModel.growthYears.filter { $0.year <= currentYear }.reduce(0) { $0 + $1.invested }
        let currentWallet = viewModel.currentTotalCapital
        let gains = currentWallet - (startWallet + totalDeposits)
        
        var items: [WaterfallItem] = []
        items.append(WaterfallItem(name: "Initial Capital", start: 0, end: startWallet, color: .gray.opacity(0.8)))
        items.append(WaterfallItem(name: "Net Deposits", start: startWallet, end: startWallet + totalDeposits, color: .blue.opacity(0.8)))
        
        if gains >= 0 {
            items.append(WaterfallItem(name: "Capital Gains", start: startWallet + totalDeposits, end: currentWallet, color: .green.opacity(0.8)))
        } else {
            items.append(WaterfallItem(name: "Capital Losses", start: startWallet + totalDeposits + gains, end: startWallet + totalDeposits, color: .red.opacity(0.8)))
        }
        
        items.append(WaterfallItem(name: "Current Value", start: 0, end: currentWallet, color: .purple.opacity(0.8)))
        return items
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if !isExpanded { Text("Wealth Accumulation Waterfall").font(.headline).foregroundColor(.secondary) }
                Spacer()
                if !isExpanded { Button(action: { expandedChart = .wealthWaterfall }) { Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary) }.buttonStyle(.plain) }
            }.padding(.bottom, 4)
            
            if data.isEmpty || data.last?.end == 0 {
                Spacer(); Text("Fill in your initial investment to see the waterfall.").foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .center); Spacer()
            } else {
                Chart(data) { item in
                    BarMark(
                        x: .value("Category", item.name),
                        yStart: .value("Start", item.start),
                        yEnd: .value("End", item.end)
                    )
                    .foregroundStyle(item.color)
                    .cornerRadius(4)
                    .annotation(position: .top, alignment: .center) {
                        let diff = abs(item.end - item.start)
                        Text(diff.formatted(.currency(code: "EUR").precision(.fractionLength(0))))
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                    }
                }
                .chartYAxis { AxisMarks(position: .leading) { value in AxisGridLine(); AxisTick(); AxisValueLabel { if let v = value.as(Double.self) { Text(v.formatted(.currency(code: "EUR").notation(.compactName))) } } } }
            }
            HStack { Text("Shows the exact bridge from your initial capital to your current wealth").font(.caption2).foregroundColor(.secondary); Spacer(); BlueChipWatermark() }
        }
        .padding().frame(minHeight: isExpanded ? 500 : 300, maxHeight: isExpanded ? .infinity : 300).background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// --- CHART 7 (NOUVEAU) : MoIC (Multiple on Invested Capital) ---
struct MoICSeriesItem: Identifiable { let id = UUID(); let year: Int; let multiple: Double }

struct MoICMultipleChart: View {
    @ObservedObject var viewModel: PortfolioViewModel
    var isExpanded: Bool = false
    @Binding var expandedChart: GrowthChartZoomType?
    
    @State private var hoveredYear: String? = nil
    var currentYear: Int { Calendar.current.component(.year, from: Date()) }
    
    var data: [MoICSeriesItem] {
        let startYear = viewModel.dividendStartYear
        var items: [MoICSeriesItem] = []
        var cumInvested: Double = viewModel.growthYears.first?.startWallet ?? 0
        
        for year in startYear...currentYear {
            guard let yearData = viewModel.growthYears.first(where: { $0.year == year }) else { continue }
            cumInvested += yearData.invested
            let effectiveEnd = (year == currentYear) ? viewModel.currentTotalCapital : yearData.endWallet
            let multiple = cumInvested > 0 ? (effectiveEnd / cumInvested) : 1.0
            
            // On ne trace le point que s'il y a eu un début d'investissement ou si on n'est pas à 0
            if cumInvested > 0 || effectiveEnd > 0 {
                items.append(MoICSeriesItem(year: year, multiple: multiple))
            }
        }
        return items
    }
    
    var hoveredItem: MoICSeriesItem? { guard let y = hoveredYear, let yr = Int(y) else { return nil }; return data.first { $0.year == yr } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if !isExpanded { Text("MoIC Trend (Money on Money)").font(.headline).foregroundColor(.secondary) }
                Spacer()
                if !isExpanded { Button(action: { expandedChart = .momMultiple }) { Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary) }.buttonStyle(.plain) }
            }.padding(.bottom, 4)
            
            if let item = hoveredItem {
                HStack(spacing: 16) {
                    Text(String(item.year)).fontWeight(.bold)
                    Text("\(item.multiple.formatted(.number.precision(.fractionLength(2))))x")
                        .foregroundColor(item.multiple >= 1.0 ? .green : .red).fontWeight(.bold)
                }
                .font(.caption).padding(.horizontal, 8).padding(.vertical, 4).background(Color(NSColor.windowBackgroundColor)).cornerRadius(6).transition(.opacity)
            } else {
                Text("Hover to view multiplier").font(.caption).foregroundColor(.clear) // Placeholder
            }
            
            if data.isEmpty {
                Spacer(); Text("Not enough data to calculate multiple.").foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .center); Spacer()
            } else {
                Chart {
                    RuleMark(y: .value("Breakeven", 1.0))
                        .foregroundStyle(Color.gray.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5]))
                        .annotation(position: .top, alignment: .trailing) { Text("1.0x (Breakeven)").font(.caption2).foregroundColor(.gray) }
                    
                    ForEach(data) { item in
                        LineMark(x: .value("Year", String(item.year)), y: .value("Multiple", item.multiple))
                            .foregroundStyle(Color.indigo)
                            .lineStyle(StrokeStyle(lineWidth: 2.5))
                            .interpolationMethod(.monotone)
                        
                        PointMark(x: .value("Year", String(item.year)), y: .value("Multiple", item.multiple))
                            .foregroundStyle(Color.indigo)
                            .symbol { Circle().fill(item.multiple >= 1.0 ? Color.indigo : Color.red).frame(width: 8, height: 8) }
                    }
                    if let y = hoveredYear { RuleMark(x: .value("Year", y)).foregroundStyle(Color.secondary.opacity(0.4)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3])) }
                }
                .chartXSelection(value: $hoveredYear)
                .chartYScale(domain: .automatic(includesZero: false))
                .chartYAxis { AxisMarks(position: .leading) { value in AxisGridLine(); AxisTick(); AxisValueLabel { if let v = value.as(Double.self) { Text("\(v.formatted(.number.precision(.fractionLength(1))))x").font(.system(size: 10)) } } } }
                .chartXAxis { AxisMarks { value in AxisValueLabel { if let s = value.as(String.self) { Text(s).font(.caption) } } } }
            }
            HStack { Text("Total Value divided by Total Invested Capital").font(.caption2).foregroundColor(.secondary); Spacer(); BlueChipWatermark() }
        }
        .padding().frame(minHeight: isExpanded ? 500 : 300, maxHeight: isExpanded ? .infinity : 300).background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// MARK: - FULL SCREEN ZOOM GROWTH
struct GrowthFullScreenChartView: View {
    @Environment(\.dismiss) var dismiss
    let zoomType: GrowthChartZoomType
    @ObservedObject var viewModel: PortfolioViewModel
    @Binding var privacyMode: Bool

    var chartTitle: String {
        switch zoomType {
        case .cashVsStocks:       return "Cash vs Stocks"
        case .capitalVsGains:     return "Value Source"
        case .gainsProvenance:    return "Gains Source"
        case .annualReturnsCombo: return "Annual Returns"
        case .investedVsValue:    return "Invested vs Portfolio Value"
        case .wealthWaterfall:    return "Wealth Accumulation Waterfall"
        case .momMultiple:        return "MoIC Trend (Money on Money)"
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text(chartTitle).font(.title).fontWeight(.bold)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill").font(.title).foregroundColor(.secondary)
                }.buttonStyle(.plain)
            }

            switch zoomType {
            case .cashVsStocks:       CashVsStocksChart(viewModel: viewModel, isExpanded: true, expandedChart: .constant(nil))
            case .capitalVsGains:     CapitalVsGainsChart(viewModel: viewModel, isExpanded: true, expandedChart: .constant(nil))
            case .gainsProvenance:    GainsProvenanceChart(viewModel: viewModel, isExpanded: true, expandedChart: .constant(nil))
            case .annualReturnsCombo: AnnualReturnsComboChart(viewModel: viewModel, isExpanded: true, expandedChart: .constant(nil))
            case .investedVsValue:    InvestedVsValueChart(viewModel: viewModel, isExpanded: true, expandedChart: .constant(nil))
            case .wealthWaterfall:    WealthWaterfallChart(viewModel: viewModel, isExpanded: true, expandedChart: .constant(nil))
            case .momMultiple:        MoICMultipleChart(viewModel: viewModel, isExpanded: true, expandedChart: .constant(nil))
            }

        }.padding(30).frame(minWidth: 900, minHeight: 700)
    }
}
