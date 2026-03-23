import SwiftUI
import Charts

// MARK: - SPECIFIC ZOOM ENUM FOR DIVIDENDS
enum DividendChartZoomType: String, Identifiable {
    case monthly, yearly, expectedMonthly, stockYield, totalDividends, yoc
    var id: String { self.rawValue }
}

// MARK: - MAIN VIEW (Ultra-légère pour compilation instantanée)
struct DividendsView: View {
    @ObservedObject var viewModel: PortfolioViewModel
    @Binding var privacyMode: Bool
    
    @State private var showGoalSheet = false
    @State private var chartToZoom: DividendChartZoomType? = nil
    
    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 24) {
                DividendsDashboardSection(viewModel: viewModel, privacyMode: $privacyMode)
                
                DividendGoalProgressBar(viewModel: viewModel, privacyMode: $privacyMode)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { showGoalSheet = true }
                
                DividendsProjectedChartsSection(viewModel: viewModel, chartToZoom: $chartToZoom)
                
                DividendsTableSection(viewModel: viewModel)
                
                DividendsManualChartsSection(viewModel: viewModel, chartToZoom: $chartToZoom)
                
                DividendsSecurityMetricsSection(viewModel: viewModel, chartToZoom: $chartToZoom)
            }
            .padding()
        }
        .sheet(isPresented: $showGoalSheet) { EditDividendGoalView(viewModel: viewModel) }
        .sheet(item: $chartToZoom) { type in DividendFullScreenChartView(zoomType: type, viewModel: viewModel) }
    }
}

// =========================================================================
// MARK: - FORMULAIRE GOAL (Dédié aux Dividendes)
// =========================================================================
struct EditDividendGoalView: View {
    @Environment(\.dismiss) var dismiss; @ObservedObject var viewModel: PortfolioViewModel
    @State private var selectedGoal: DividendGoalType; @State private var targetInput: Double
    init(viewModel: PortfolioViewModel) { self.viewModel = viewModel; _selectedGoal = State(initialValue: viewModel.dividendGoalType); _targetInput = State(initialValue: viewModel.dividendGoalTarget) }
    var body: some View {
        Form {
            Section(header: Text("Set Dividend Goal").font(.headline)) { Picker("Goal Type", selection: $selectedGoal) { ForEach(DividendGoalType.allCases, id: \.self) { type in Text(type.rawValue).tag(type) } }; TextField("Target Amount", value: $targetInput, format: .number) }.padding()
            HStack { Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button("Save") { viewModel.dividendGoalType = selectedGoal; viewModel.dividendGoalTarget = targetInput; dismiss() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent) }.padding()
        }.frame(width: 380).padding()
    }
}

// =========================================================================
// MARK: - SECTIONS DÉCOUPÉES
// =========================================================================

struct DividendsDashboardSection: View {
    @ObservedObject var viewModel: PortfolioViewModel
    @Binding var privacyMode: Bool
    
    var totalReceivedAllTime: Double { viewModel.dividendYears.reduce(0) { $0 + $1.total } }
    var currentYear: Int { Calendar.current.component(.year, from: Date()) }
    var currentMonthIndex: Int { Calendar.current.component(.month, from: Date()) }
    var thisYearData: DividendYear? { viewModel.dividendYears.first { $0.year == currentYear } }
    var lastYearData: DividendYear? { viewModel.dividendYears.first { $0.year == currentYear - 1 } }
    var receivedThisYear: Double { thisYearData?.total ?? 0 }
    var receivedLastYear: Double { lastYearData?.total ?? 0 }
    
    var receivedThisMonth: Double {
        guard let data = thisYearData else { return 0 }
        let months = [data.jan, data.feb, data.mar, data.apr, data.may, data.jun, data.jul, data.aug, data.sep, data.oct, data.nov, data.dec]
        return months[currentMonthIndex - 1]
    }
    
    var averageMonthlyThisYear: Double { return receivedThisYear / Double(max(1, currentMonthIndex)) }
    var bestYear: Double { viewModel.dividendYears.map { $0.total }.max() ?? 0 }
    var yoyGrowth: Double { guard receivedLastYear > 0 else { return 0 }; return (receivedThisYear - receivedLastYear) / receivedLastYear }
    
    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                DashboardCard(title: "Total Received (All Time)", value: totalReceivedAllTime.formatted(.currency(code: "EUR")), privacyMode: $privacyMode)
                DashboardCard(title: "Received This Year", value: receivedThisYear.formatted(.currency(code: "EUR")), privacyMode: $privacyMode)
                DashboardCard(title: "Received This Month", value: receivedThisMonth.formatted(.currency(code: "EUR")), privacyMode: $privacyMode)
                DashboardCard(title: "Avg. Monthly (This Year)", value: averageMonthlyThisYear.formatted(.currency(code: "EUR")) + "/mo", privacyMode: $privacyMode)
            }
            HStack(spacing: 16) {
                DashboardCard(title: "Best Year", value: bestYear.formatted(.currency(code: "EUR")), privacyMode: $privacyMode)
                YoYCard(yoyGrowth: yoyGrowth, privacyMode: $privacyMode)
                DashboardCard(title: "Projected Annual Yield", value: viewModel.portfolioYield.formatted(.percent.precision(.fractionLength(2))), privacyMode: $privacyMode)
                StartYearCard(viewModel: viewModel)
            }
        }
    }
}

struct YoYCard: View {
    let yoyGrowth: Double; @Binding var privacyMode: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("YoY Growth (vs Last Year)").font(.subheadline).foregroundColor(.secondary).lineLimit(1)
            Text(yoyGrowth.formatted(.percent.precision(.fractionLength(1)).sign(strategy: .always())))
                .font(.title2).fontWeight(.bold).foregroundColor(yoyGrowth >= 0 ? .green : .red).blur(radius: privacyMode ? 8 : 0)
        }.padding().frame(maxWidth: .infinity, alignment: .leading).frame(height: 110).background(Color(NSColor.controlBackgroundColor)).cornerRadius(10).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

struct StartYearCard: View {
    @ObservedObject var viewModel: PortfolioViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Start Year").font(.subheadline).foregroundColor(.secondary)
            TextField("Year", value: $viewModel.dividendStartYear, format: .number.grouping(.never))
                .textFieldStyle(.roundedBorder).frame(maxWidth: 80).font(.title3.bold())
        }.padding().frame(maxWidth: .infinity, alignment: .leading).frame(height: 110).background(Color(NSColor.controlBackgroundColor)).cornerRadius(10).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

struct DividendsProjectedChartsSection: View {
    @ObservedObject var viewModel: PortfolioViewModel; @Binding var chartToZoom: DividendChartZoomType?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Projected Dividend Analytics").font(.title2).fontWeight(.bold).foregroundColor(.secondary)
            HStack(spacing: 24) {
                ExpectedMonthlyDividendChart(viewModel: viewModel, expandedChart: $chartToZoom)
                StockYieldChart(viewModel: viewModel, expandedChart: $chartToZoom)
            }
        }
    }
}

struct DividendsTableSection: View {
    @ObservedObject var viewModel: PortfolioViewModel; typealias YearBinding = Binding<DividendYear>
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Manual Dividend Received Tracker").font(.title2).fontWeight(.bold).foregroundColor(.secondary).padding(.bottom, 4)
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text("Year").fontWeight(.bold).frame(width: 50, alignment: .leading)
                    Group { Text("Jan").frame(maxWidth: .infinity, alignment: .leading); Text("Feb").frame(maxWidth: .infinity, alignment: .leading); Text("Mar").frame(maxWidth: .infinity, alignment: .leading); Text("Apr").frame(maxWidth: .infinity, alignment: .leading); Text("May").frame(maxWidth: .infinity, alignment: .leading); Text("Jun").frame(maxWidth: .infinity, alignment: .leading); Text("Jul").frame(maxWidth: .infinity, alignment: .leading); Text("Aug").frame(maxWidth: .infinity, alignment: .leading); Text("Sep").frame(maxWidth: .infinity, alignment: .leading); Text("Oct").frame(maxWidth: .infinity, alignment: .leading); Text("Nov").frame(maxWidth: .infinity, alignment: .leading); Text("Dec").frame(maxWidth: .infinity, alignment: .leading) }.font(.subheadline).foregroundColor(.secondary)
                    Text("Total").fontWeight(.bold).frame(width: 80, alignment: .trailing)
                }.padding(.horizontal, 16).padding(.vertical, 12).background(Color(NSColor.windowBackgroundColor)); Divider()
                ScrollView { LazyVStack(spacing: 0) { ForEach($viewModel.dividendYears) { $yearData in SpreadsheetRowView(yearData: $yearData).padding(.horizontal, 16).padding(.vertical, 8); Divider() } } }
            }.background(Color(NSColor.controlBackgroundColor)).cornerRadius(8).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))
        }.frame(height: 380).padding().background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

struct SpreadsheetRowView: View {
    @Binding var yearData: DividendYear
    var body: some View {
        HStack(spacing: 8) {
            Text(String(yearData.year)).fontWeight(.bold).frame(width: 50, alignment: .leading)
            MonthField(value: $yearData.jan); MonthField(value: $yearData.feb); MonthField(value: $yearData.mar); MonthField(value: $yearData.apr); MonthField(value: $yearData.may); MonthField(value: $yearData.jun); MonthField(value: $yearData.jul); MonthField(value: $yearData.aug); MonthField(value: $yearData.sep); MonthField(value: $yearData.oct); MonthField(value: $yearData.nov); MonthField(value: $yearData.dec)
            Text(yearData.total.formatted(.currency(code: "EUR"))).fontWeight(.bold).foregroundColor(.green).frame(width: 80, alignment: .trailing)
        }
    }
}

struct MonthField: View { @Binding var value: Double; var body: some View { TextField("0", value: $value, format: .number).textFieldStyle(.plain).frame(maxWidth: .infinity, alignment: .leading) } }

struct DividendsManualChartsSection: View {
    @ObservedObject var viewModel: PortfolioViewModel; @Binding var chartToZoom: DividendChartZoomType?
    var currentYear: Int { Calendar.current.component(.year, from: Date()) }; var thisYearData: DividendYear? { viewModel.dividendYears.first { $0.year == currentYear } }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Spreadsheet Received History").font(.title2).fontWeight(.bold).foregroundColor(.secondary)
            HStack(spacing: 24) {
                MonthlyDividendChart(viewModel: viewModel, thisYearData: thisYearData, expandedChart: $chartToZoom)
                YearlyDividendChart(viewModel: viewModel, currentYear: currentYear, expandedChart: $chartToZoom)
            }
        }
    }
}

struct DividendsSecurityMetricsSection: View {
    @ObservedObject var viewModel: PortfolioViewModel; @Binding var chartToZoom: DividendChartZoomType?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Positions Dividends & Yield On Cost").font(.title2).fontWeight(.bold).foregroundColor(.secondary)
            HStack(spacing: 24) {
                TotalDividendsDonutChart(viewModel: viewModel, expandedChart: $chartToZoom)
                YieldOnCostChart(viewModel: viewModel, expandedChart: $chartToZoom)
            }
        }
    }
}

// =========================================================================
// MARK: - DIVIDEND CUSTOM UI COMPONENTS & CHARTS
// =========================================================================

struct DividendGoalProgressBar: View {
    @ObservedObject var viewModel: PortfolioViewModel; @Binding var privacyMode: Bool
    var isYieldGoal: Bool { viewModel.dividendGoalType == .portfolioYield }
    var targetTitle: String { isYieldGoal ? "Portfolio Yield" : "Annual Expected Dividends" }
    var currentValueString: String { isYieldGoal ? viewModel.portfolioYield.formatted(.percent.precision(.fractionLength(2))) : viewModel.totalDividends.formatted(.currency(code: "EUR").precision(.fractionLength(2))) }
    var targetValueString: String { isYieldGoal ? (viewModel.dividendGoalTarget / 100.0).formatted(.percent.precision(.fractionLength(2))) : viewModel.dividendGoalTarget.formatted(.currency(code: "EUR").precision(.fractionLength(2))) }
    var progress: Double {
        guard viewModel.dividendGoalTarget > 0 else { return 0 }
        if isYieldGoal { return min(max(viewModel.portfolioYield / (viewModel.dividendGoalTarget / 100.0), 0), 1) }
        else { return min(max(viewModel.totalDividends / viewModel.dividendGoalTarget, 0), 1) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Text("\(targetTitle) Goal").font(.headline); Spacer(); Text("\(currentValueString) / \(targetValueString)").font(.subheadline).fontWeight(.bold).foregroundColor(progress >= 1 ? .green : .primary).blur(radius: privacyMode ? 8 : 0) }
            GeometryReader { geometry in ZStack(alignment: .leading) { RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.windowBackgroundColor)).frame(height: 14); RoundedRectangle(cornerRadius: 8).fill(LinearGradient(gradient: Gradient(colors: [.orange, .purple]), startPoint: .leading, endPoint: .trailing)).frame(width: max(0, geometry.size.width * CGFloat(progress)), height: 14).animation(.spring(), value: progress) } }.frame(height: 14)
        }.padding().background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1).help("Double-click to edit your goal")
    }
}

// MARK: - CHART 1: EXPECTED MONTHLY (Bar Chart grouped)
struct ExpectedMonthlyDividendChart: View {
    @ObservedObject var viewModel: PortfolioViewModel
    var isExpanded: Bool = false
    @Binding var expandedChart: DividendChartZoomType?
    @State private var hoveredMonth: String? = nil
    
    var body: some View {
        VStack {
            HStack {
                if !isExpanded { Text("Expected Monthly Income (Net vs Gross)").font(.headline).foregroundColor(.secondary) }
                Spacer()
                if !isExpanded { Button(action: { expandedChart = .expectedMonthly }) { Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary) }.buttonStyle(.plain) }
            }.padding(.bottom, 8)
            
            if viewModel.expectedMonthlyDividendSeries.isEmpty { Spacer(); Text("No data").foregroundColor(.secondary); Spacer() } else {
                Chart(viewModel.expectedMonthlyDividendSeries) { item in
                    BarMark(x: .value("Month", item.monthName), y: .value("Amount", item.amount))
                        .foregroundStyle(item.type == "Net" ? viewModel.color(for: item.ticker) : viewModel.color(for: item.ticker).opacity(0.4))
                        .position(by: .value("Type", item.type)).cornerRadius(4)
                        
                        // ANNOTATION COMME DANS COMPOSITION (Pas de RuleMark)
                        .annotation(position: .top) {
                            if hoveredMonth == item.monthName {
                                Text(item.amount.formatted(.currency(code: "EUR"))).font(.system(size: 9, weight: .bold)).foregroundColor(.secondary)
                            }
                        }
                }
                .chartLegend(.hidden)
                .chartYAxis { AxisMarks(position: .leading) { value in AxisGridLine(); AxisTick(); if let v = value.as(Double.self) { AxisValueLabel(v.formatted(.currency(code: "EUR").precision(.fractionLength(0)))) } } }
                .chartXSelection(value: $hoveredMonth)
            }
            BlueChipWatermark()
        }.padding().frame(minHeight: 360, maxHeight: isExpanded ? .infinity : 360).background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// MARK: - CHART 2: STOCK YIELD
struct StockYieldChart: View {
    @ObservedObject var viewModel: PortfolioViewModel
    var isExpanded: Bool = false
    @Binding var expandedChart: DividendChartZoomType?
    @State private var hoveredTicker: String? = nil
    
    var body: some View {
        VStack {
            HStack {
                if !isExpanded { Text("Current Stock Yield (by Ticker)").font(.headline).foregroundColor(.secondary) }
                Spacer()
                if !isExpanded { Button(action: { expandedChart = .stockYield }) { Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary) }.buttonStyle(.plain) }
            }.padding(.bottom, 8)
            
            if viewModel.stockYieldsData.isEmpty { Spacer(); Text("No data").foregroundColor(.secondary); Spacer() } else {
                Chart(viewModel.stockYieldsData) { item in
                    LineMark(x: .value("Ticker", item.ticker), y: .value("Yield", item.yield)).foregroundStyle(Color.gray.opacity(0.4)).interpolationMethod(.monotone)
                    PointMark(x: .value("Ticker", item.ticker), y: .value("Yield", item.yield)).foregroundStyle(viewModel.color(for: item.ticker)).symbolSize(hoveredTicker == item.ticker ? 100 : 40)
                        
                        // ANNOTATION COMME DANS COMPOSITION
                        .annotation(position: .top) {
                            if hoveredTicker == item.ticker {
                                Text("\(item.yield.formatted(.number.precision(.fractionLength(2))))%").font(.system(size: 9, weight: .bold)).foregroundColor(.secondary)
                            }
                        }
                }
                .chartLegend(.hidden)
                .chartYAxis { AxisMarks(position: .leading) { value in AxisGridLine(); AxisTick(); if let v = value.as(Double.self) { AxisValueLabel("\(v.formatted(.number.precision(.fractionLength(0))))%") } } }
                .chartXSelection(value: $hoveredTicker)
            }
            BlueChipWatermark()
        }.padding().frame(minHeight: 360, maxHeight: isExpanded ? .infinity : 360).background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// MARK: - CHART 3: MANUAL MONTHLY
struct MonthlyDividendChart: View {
    @ObservedObject var viewModel: PortfolioViewModel
    var thisYearData: DividendYear?
    var isExpanded: Bool = false
    @Binding var expandedChart: DividendChartZoomType?
    @State private var hoveredMonth: String? = nil
    
    var monthlyData: [(String, Double)] {
        guard let thisYear = thisYearData else { return [] }
        return [("Jan", thisYear.jan), ("Feb", thisYear.feb), ("Mar", thisYear.mar), ("Apr", thisYear.apr), ("May", thisYear.may), ("Jun", thisYear.jun), ("Jul", thisYear.jul), ("Aug", thisYear.aug), ("Sep", thisYear.sep), ("Oct", thisYear.oct), ("Nov", thisYear.nov), ("Dec", thisYear.dec)]
    }
    
    var body: some View {
        VStack {
            HStack {
                if !isExpanded { Text("Spreadsheet: Received This Year").font(.headline).foregroundColor(.secondary) }
                Spacer()
                if !isExpanded { Button(action: { expandedChart = .monthly }) { Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary) }.buttonStyle(.plain) }
            }.padding(.bottom, 8)
            
            if monthlyData.isEmpty { Spacer(); Text("No data").foregroundColor(.secondary); Spacer() } else {
                Chart(monthlyData, id: \.0) { item in
                    BarMark(x: .value("Month", item.0), y: .value("Amount", item.1)).foregroundStyle(Color.orange.opacity(0.8)).cornerRadius(4)
                        
                        // ANNOTATION COMME DANS COMPOSITION
                        .annotation(position: .top) {
                            if hoveredMonth == item.0 {
                                Text(item.1.formatted(.currency(code: "EUR"))).font(.system(size: 9, weight: .bold)).foregroundColor(.secondary)
                            }
                        }
                }
                .chartYAxis { AxisMarks { value in if let v = value.as(Double.self) { AxisValueLabel(v.formatted(.currency(code: "EUR").precision(.fractionLength(0)))) } } }
                .chartXSelection(value: $hoveredMonth)
            }
            BlueChipWatermark()
        }.padding().frame(minHeight: 360, maxHeight: isExpanded ? .infinity : 360).background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// MARK: - CHART 4: MANUAL YEARLY
struct YearlyDividendChart: View {
    @ObservedObject var viewModel: PortfolioViewModel
    var currentYear: Int
    var isExpanded: Bool = false
    @Binding var expandedChart: DividendChartZoomType?
    @State private var hoveredYear: String? = nil
    
    var activeYears: [DividendYear] { viewModel.dividendYears.filter { $0.total > 0 || $0.year == currentYear } }
    
    var body: some View {
        VStack {
            HStack {
                if !isExpanded { Text("Spreadsheet: Annual Received History").font(.headline).foregroundColor(.secondary) }
                Spacer()
                if !isExpanded { Button(action: { expandedChart = .yearly }) { Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary) }.buttonStyle(.plain) }
            }.padding(.bottom, 8)
            
            if activeYears.isEmpty { Spacer(); Text("No data").foregroundColor(.secondary); Spacer() } else {
                Chart(activeYears) { yearData in
                    let yearStr = String(yearData.year)
                    BarMark(x: .value("Year", yearStr), y: .value("Total", yearData.total)).foregroundStyle(Color.green.opacity(0.8)).cornerRadius(4)
                        
                        // ANNOTATION COMME DANS COMPOSITION
                        .annotation(position: .top) {
                            if hoveredYear == yearStr {
                                Text(yearData.total.formatted(.currency(code: "EUR"))).font(.system(size: 9, weight: .bold)).foregroundColor(.secondary)
                            }
                        }
                }
                .chartYAxis { AxisMarks { value in if let v = value.as(Double.self) { AxisValueLabel(v.formatted(.currency(code: "EUR").precision(.fractionLength(0)))) } } }
                .chartXSelection(value: $hoveredYear)
            }
            BlueChipWatermark()
        }.padding().frame(minHeight: 360, maxHeight: isExpanded ? .infinity : 360).background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// MARK: - CHART 5: TOTAL DIVIDENDS BY POSITION (DONUT)
struct TotalDividendsDonutChart: View {
    @ObservedObject var viewModel: PortfolioViewModel
    var isExpanded: Bool = false
    @Binding var expandedChart: DividendChartZoomType?
    @State private var selectedAngleValue: Double? = nil
    @State private var hiddenItems: Set<String> = []

    var data: [ChartDataItem] {
        viewModel.positions.filter { $0.totalDividendEUR > 0 }
            .map { ChartDataItem(name: $0.ticker, value: $0.totalDividendEUR) }
            .sorted { $0.value > $1.value }
    }
    var filteredData: [ChartDataItem] { data.filter { !hiddenItems.contains($0.name) } }

    var body: some View {
        VStack {
            HStack {
                if !isExpanded { Text("Total Dividends by Position").font(.headline).foregroundColor(.secondary) }
                Spacer()
                if !isExpanded { Button(action: { expandedChart = .totalDividends }) { Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary) }.buttonStyle(.plain) }
            }.padding(.bottom, 4)
            InteractiveLegendView(items: data.map { $0.name }, colorMap: { viewModel.color(for: $0) }, hiddenItems: $hiddenItems).padding(.bottom, 8)

            if filteredData.isEmpty { Spacer(); Text("No data").foregroundColor(.secondary); Spacer() } else {
                Chart(filteredData) { item in
                    SectorMark(angle: .value("Value", item.value), innerRadius: .ratio(0.65), angularInset: 1.5)
                        .foregroundStyle(viewModel.color(for: item.name)).cornerRadius(4)
                }
                .chartLegend(.hidden)
                .chartAngleSelection(value: $selectedAngleValue)
                .chartBackground { proxy in
                    GeometryReader { geometry in
                        if let value = selectedAngleValue {
                            let item = findItem(for: value)
                            VStack {
                                Text(item.name).font(.headline)
                                Text(item.value.formatted(.currency(code: "EUR"))).font(.subheadline).foregroundColor(.secondary)
                            }.position(x: geometry.frame(in: .local).midX, y: geometry.frame(in: .local).midY)
                        }
                    }
                }.animation(.easeInOut(duration: 0.2), value: selectedAngleValue)
            }
            BlueChipWatermark()
        }.padding().frame(minHeight: 360, maxHeight: isExpanded ? .infinity : 360).background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }

    func findItem(for value: Double) -> ChartDataItem {
        var cum = 0.0
        for item in filteredData { cum += item.value; if value <= cum { return item } }
        return filteredData.last!
    }
}

// MARK: - CHART 6: YIELD ON COST (BAR CHART)
struct YieldOnCostChart: View {
    @ObservedObject var viewModel: PortfolioViewModel
    var isExpanded: Bool = false
    @Binding var expandedChart: DividendChartZoomType?
    @State private var hoveredTicker: String? = nil

    var data: [ChartDataItem] {
        viewModel.positions.filter { $0.investedAmountEUR > 0 && $0.totalDividendEUR > 0 }
            .map { ChartDataItem(name: $0.ticker, value: ($0.totalDividendEUR / $0.investedAmountEUR) * 100.0) }
            .sorted { $0.value > $1.value }
    }

    var body: some View {
        VStack {
            HStack {
                if !isExpanded { Text("Yield On Cost (YOC)").font(.headline).foregroundColor(.secondary) }
                Spacer()
                if !isExpanded { Button(action: { expandedChart = .yoc }) { Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary) }.buttonStyle(.plain) }
            }.padding(.bottom, 8)

            if data.isEmpty { Spacer(); Text("No data").foregroundColor(.secondary); Spacer() } else {
                Chart(data) { item in
                    BarMark(x: .value("Ticker", item.name), y: .value("YOC", item.value))
                        .foregroundStyle(viewModel.color(for: item.name))
                        .cornerRadius(4)
                        
                        // ANNOTATION COMME DANS COMPOSITION
                        .annotation(position: .top) {
                            if hoveredTicker == item.name {
                                Text("\(item.value.formatted(.number.precision(.fractionLength(2))))%").font(.system(size: 9, weight: .bold)).foregroundColor(.secondary)
                            }
                        }
                }
                .chartLegend(.hidden)
                .chartYAxis { AxisMarks(position: .leading) { value in AxisGridLine(); AxisTick(); if let v = value.as(Double.self) { AxisValueLabel("\(v.formatted(.number.precision(.fractionLength(0))))%") } } }
                .chartXSelection(value: $hoveredTicker)
            }
            BlueChipWatermark()
        }.padding().frame(minHeight: 360, maxHeight: isExpanded ? .infinity : 360).background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// MARK: - FULL SCREEN ZOOM
struct DividendFullScreenChartView: View {
    @Environment(\.dismiss) var dismiss
    let zoomType: DividendChartZoomType
    @ObservedObject var viewModel: PortfolioViewModel
    
    var currentYear: Int { Calendar.current.component(.year, from: Date()) }
    var thisYearData: DividendYear? { viewModel.dividendYears.first { $0.year == currentYear } }
    
    var body: some View {
        VStack(spacing: 20) {
            HStack { Text(titleForZoom).font(.title).fontWeight(.bold); Spacer(); Button(action: { dismiss() }) { Image(systemName: "xmark.circle.fill").font(.title).foregroundColor(.secondary) }.buttonStyle(.plain) }
            
            switch zoomType {
            case .expectedMonthly: ExpectedMonthlyDividendChart(viewModel: viewModel, isExpanded: true, expandedChart: .constant(nil))
            case .stockYield: StockYieldChart(viewModel: viewModel, isExpanded: true, expandedChart: .constant(nil))
            case .monthly: MonthlyDividendChart(viewModel: viewModel, thisYearData: thisYearData, isExpanded: true, expandedChart: .constant(nil))
            case .yearly: YearlyDividendChart(viewModel: viewModel, currentYear: currentYear, isExpanded: true, expandedChart: .constant(nil))
            case .totalDividends: TotalDividendsDonutChart(viewModel: viewModel, isExpanded: true, expandedChart: .constant(nil))
            case .yoc: YieldOnCostChart(viewModel: viewModel, isExpanded: true, expandedChart: .constant(nil))
            }
        }.padding(30).frame(minWidth: 900, minHeight: 700)
    }
    
    var titleForZoom: String {
        switch zoomType {
        case .expectedMonthly: return "Expected Monthly Income (Net vs Gross)"
        case .stockYield: return "Current Stock Yield by Ticker"
        case .monthly: return "Spreadsheet: Received This Year"
        case .yearly: return "Spreadsheet: Annual Received History"
        case .totalDividends: return "Total Dividends by Position"
        case .yoc: return "Yield On Cost (YOC)"
        }
    }
}
