import SwiftUI
import Charts
import SwiftData
import Combine

// MARK: - SPECIFIC ZOOM ENUM FOR DIVIDENDS
enum DividendChartZoomType: String, Identifiable {
    case monthly, yearly, expectedMonthly, stockYield, totalDividends, yoc, allTimeHistory, heatmap
    case seasonality, dgr
    var id: String { self.rawValue }
}

// MARK: - MAIN VIEW
struct DividendsView: View {
    @ObservedObject var viewModel: PortfolioViewModel
    @Binding var privacyMode: Bool
    
    @State private var showGoalSheet = false
    @State private var chartToZoom: DividendChartZoomType? = nil
            
    var currentGoalValueForProgressBar: Double {
        let goalType = viewModel.dividendGoalType ?? .dividendsAnnual
        
        switch goalType {
        case .dividendsAnnual:
            return viewModel.totalDividends
        case .portfolioYield:
            return viewModel.portfolioYield * 100
        case .currentYearTotal: // <-- NOUVEAU
            let currentYear = Calendar.current.component(.year, from: Date())
            let thisYearData = viewModel.dividendYears.first { $0.year == currentYear }
            return thisYearData?.total ?? 0.0
        case .allTimeTotal:
            return viewModel.dividendYears.reduce(0) { $0 + $1.total }
        }
    }
    
    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 24) {
                DividendsDashboardSection(viewModel: viewModel, privacyMode: $privacyMode)
                
                // -----------------------------------------------------------
                // Utilisation du composant universel GoalProgressBar
                // -----------------------------------------------------------
                GoalProgressBar(
                    title: viewModel.dividendGoalType.rawValue ?? DividendGoalType.dividendsAnnual.rawValue,
                    currentValue: currentGoalValueForProgressBar,
                    targetValue: viewModel.dividendGoalTarget ?? 0.0,
                    privacyMode: $privacyMode,
                    isPercentage: viewModel.dividendGoalType == .portfolioYield
                )
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { showGoalSheet = true }
                
                DividendsProjectedChartsSection(viewModel: viewModel, privacyMode: $privacyMode, chartToZoom: $chartToZoom)
                
                DividendsThisMonthSection(viewModel: viewModel, privacyMode: $privacyMode)
                
                DividendsTableSection(viewModel: viewModel, privacyMode: $privacyMode)
                                
                DividendsManualChartsSection(viewModel: viewModel, privacyMode: $privacyMode, chartToZoom: $chartToZoom)
                
                DividendsSecurityMetricsSection(viewModel: viewModel, privacyMode: $privacyMode, chartToZoom: $chartToZoom)
                
                DividendsAdvancedAnalyticsSection(viewModel: viewModel, privacyMode: $privacyMode, chartToZoom: $chartToZoom)
                
                DividendsGrowthAndSeasonalitySection(viewModel: viewModel, privacyMode: $privacyMode, chartToZoom: $chartToZoom)
            }
            .padding()
        }
        .sheet(isPresented: $showGoalSheet) { EditDividendGoalView(viewModel: viewModel) }
        .sheet(item: $chartToZoom) { type in DividendFullScreenChartView(zoomType: type, viewModel: viewModel, privacyMode: $privacyMode) }
    }
}

// =========================================================================
// MARK: - FORMULAIRE GOAL (Dédié aux Dividendes - Design Uniformisé)
// =========================================================================
struct EditDividendGoalView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: PortfolioViewModel
    @State private var selectedGoal: DividendGoalType
    @State private var targetInput: Double
    
    init(viewModel: PortfolioViewModel) {
        self.viewModel = viewModel
        _selectedGoal = State(initialValue: viewModel.dividendGoalType ?? .dividendsAnnual)
        _targetInput = State(initialValue: viewModel.dividendGoalTarget ?? 1000.0)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Set Dividend Goal").font(.title2).fontWeight(.bold)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill").font(.title2).foregroundColor(.secondary)
                }.buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            // Content
            VStack(alignment: .leading, spacing: 16) {
                GroupBox {
                    VStack(spacing: 16) {
                        HStack {
                            Text("Goal Type:")
                            Spacer()
                            Picker("", selection: $selectedGoal) {
                                ForEach(DividendGoalType.allCases, id: \.self) { type in Text(type.rawValue).tag(type) }
                            }
                            .labelsHidden()
                            .frame(width: 250) // Plus large pour accommoder "Total All-Time Received (€)"
                        }
                        
                        Divider().opacity(0.5)
                        
                        HStack {
                            Text("Target Amount:")
                            Spacer()
                            TextField("e.g. 500", value: $targetInput, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 150)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding()
            
            Spacer()
            Divider()
            
            // Footer
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save Goal") {
                    viewModel.dividendGoalType = selectedGoal
                    viewModel.dividendGoalTarget = targetInput
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }.padding()
        }
        .frame(width: 440, height: 280) // Un peu plus large pour que le picker ne coupe pas le texte
    }
}

// =========================================================================
// MARK: - SECTIONS DÉCOUPÉES
// =========================================================================

struct DividendsDashboardSection: View {
    @ObservedObject var viewModel: PortfolioViewModel; @Binding var privacyMode: Bool
    
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
                DashboardCard(title: "Total Received (All Time)", value: totalReceivedAllTime.formatted(.currency(code: "EUR").precision(.fractionLength(2))), privacyMode: $privacyMode)
                DashboardCard(title: "Received This Year", value: receivedThisYear.formatted(.currency(code: "EUR").precision(.fractionLength(2))), privacyMode: $privacyMode)
                DashboardCard(title: "Received This Month", value: receivedThisMonth.formatted(.currency(code: "EUR").precision(.fractionLength(2))), privacyMode: $privacyMode)
                DashboardCard(title: "Avg. Monthly (This Year)", value: averageMonthlyThisYear.formatted(.currency(code: "EUR").precision(.fractionLength(2))) + "/mo", privacyMode: $privacyMode)
            }
            HStack(spacing: 16) {
                DashboardCard(title: "Best Year", value: bestYear.formatted(.currency(code: "EUR").precision(.fractionLength(2))), privacyMode: $privacyMode)
                YoYCard(yoyGrowth: yoyGrowth, privacyMode: $privacyMode)
                DashboardCard(title: "Projected Annual Yield", value: viewModel.portfolioYield.formatted(.percent.precision(.fractionLength(2))), privacyMode: $privacyMode)
                DashboardCard(title: "Projected Annual Income", value: viewModel.totalDividends.formatted(.currency(code: "EUR").precision(.fractionLength(2))), privacyMode: $privacyMode)
            }
        }
    }
}

struct YoYCard: View {
    let yoyGrowth: Double; @Binding var privacyMode: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("YoY Growth (vs Last Year)").font(.subheadline).foregroundColor(.secondary).lineLimit(1)
            Text(yoyGrowth.formatted(.percent.precision(.fractionLength(2)).sign(strategy: .always())))
                .font(.title2).fontWeight(.bold).foregroundColor(yoyGrowth >= 0 ? .green : .red).blur(radius: privacyMode ? 8 : 0)
        }.padding().frame(maxWidth: .infinity, alignment: .leading).frame(height: 110).background(Color(NSColor.controlBackgroundColor)).cornerRadius(10).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

struct DividendsProjectedChartsSection: View {
    @ObservedObject var viewModel: PortfolioViewModel
    @Binding var privacyMode: Bool
    @Binding var chartToZoom: DividendChartZoomType?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Projected Dividend Analytics").font(.title2).fontWeight(.bold).foregroundColor(.secondary)
            HStack(spacing: 24) {
                ExpectedMonthlyDividendChart(viewModel: viewModel, privacyMode: $privacyMode, expandedChart: $chartToZoom)
                StockYieldChart(viewModel: viewModel, privacyMode: $privacyMode, expandedChart: $chartToZoom)
            }
        }
    }
}

// =========================================================================
// MARK: - TABLEAU SPREADSHEET
// =========================================================================

struct DividendsTableSection: View {
    @ObservedObject var viewModel: PortfolioViewModel
    @Binding var privacyMode: Bool
    
    var currentYear: Int { Calendar.current.component(.year, from: Date()) }
    var displayedYears: [DividendYear] { viewModel.dividendYears.filter { $0.year <= currentYear } }
    
    var dynamicHeight: CGFloat {
        let rowHeight: CGFloat = 38
        let headerHeight: CGFloat = 46
        if displayedYears.isEmpty { return 120 }
        return CGFloat(displayedYears.count) * rowHeight + headerHeight + 20
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Manual Dividend Received Tracker").font(.title2).fontWeight(.bold).foregroundColor(.secondary).padding(.bottom, 4)
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text("Year").fontWeight(.bold).frame(width: 50, alignment: .leading)
                    Group { Text("Jan").frame(maxWidth: .infinity, alignment: .leading); Text("Feb").frame(maxWidth: .infinity, alignment: .leading); Text("Mar").frame(maxWidth: .infinity, alignment: .leading); Text("Apr").frame(maxWidth: .infinity, alignment: .leading); Text("May").frame(maxWidth: .infinity, alignment: .leading); Text("Jun").frame(maxWidth: .infinity, alignment: .leading) }.font(.subheadline).foregroundColor(.secondary)
                    Group { Text("Jul").frame(maxWidth: .infinity, alignment: .leading); Text("Aug").frame(maxWidth: .infinity, alignment: .leading); Text("Sep").frame(maxWidth: .infinity, alignment: .leading); Text("Oct").frame(maxWidth: .infinity, alignment: .leading); Text("Nov").frame(maxWidth: .infinity, alignment: .leading); Text("Dec").frame(maxWidth: .infinity, alignment: .leading) }.font(.subheadline).foregroundColor(.secondary)
                    Text("Total").fontWeight(.bold).frame(width: 80, alignment: .trailing)
                }.padding(.horizontal, 16).padding(.vertical, 12).background(Color(NSColor.windowBackgroundColor)); Divider()
                
                VStack(spacing: 0) {
                    ForEach(displayedYears) { yearData in
                        SpreadsheetRowView(yearData: yearData, privacyMode: privacyMode, viewModel: viewModel)
                            .padding(.horizontal, 16).padding(.vertical, 8)
                        Divider()
                    }
                }
            }.background(Color(NSColor.controlBackgroundColor)).cornerRadius(8).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))
        }
        .frame(height: dynamicHeight).padding().background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

struct SpreadsheetRowView: View {
    @Bindable var yearData: DividendYear
    var privacyMode: Bool
    @ObservedObject var viewModel: PortfolioViewModel
    
    var body: some View {
        HStack(spacing: 8) {
            Group {
                Text(String(yearData.year)).fontWeight(.bold).frame(width: 50, alignment: .leading)
                MonthField(value: $yearData.jan, privacyMode: privacyMode, viewModel: viewModel); MonthField(value: $yearData.feb, privacyMode: privacyMode, viewModel: viewModel); MonthField(value: $yearData.mar, privacyMode: privacyMode, viewModel: viewModel)
                MonthField(value: $yearData.apr, privacyMode: privacyMode, viewModel: viewModel); MonthField(value: $yearData.may, privacyMode: privacyMode, viewModel: viewModel); MonthField(value: $yearData.jun, privacyMode: privacyMode, viewModel: viewModel)
            }
            Group {
                MonthField(value: $yearData.jul, privacyMode: privacyMode, viewModel: viewModel); MonthField(value: $yearData.aug, privacyMode: privacyMode, viewModel: viewModel); MonthField(value: $yearData.sep, privacyMode: privacyMode, viewModel: viewModel)
                MonthField(value: $yearData.oct, privacyMode: privacyMode, viewModel: viewModel); MonthField(value: $yearData.nov, privacyMode: privacyMode, viewModel: viewModel); MonthField(value: $yearData.dec, privacyMode: privacyMode, viewModel: viewModel)
                Text(yearData.total.formatted(.currency(code: "EUR").precision(.fractionLength(2))))
                    .fontWeight(.bold).foregroundColor(.green).frame(width: 80, alignment: .trailing)
                    .blur(radius: privacyMode ? 6 : 0)
            }
        }
    }
}

struct MonthField: View {
    @Binding var value: Double
    var privacyMode: Bool
    @ObservedObject var viewModel: PortfolioViewModel
    
    @State private var textValue: String = ""
    
    var body: some View {
        TextField("0", text: $textValue)
            .textFieldStyle(.plain).frame(maxWidth: .infinity, alignment: .leading)
            .blur(radius: privacyMode ? 6 : 0)
            .onAppear {
                if value != 0 { textValue = value.formatted(.number.grouping(.never)) }
            }
            .onChange(of: textValue) { _, newValue in
                let cleanString = newValue.replacingOccurrences(of: ",", with: ".")
                if let doubleVal = Double(cleanString) {
                    value = doubleVal
                } else if newValue.isEmpty {
                    value = 0
                }
                viewModel.objectWillChange.send()
            }
    }
}

struct DividendsManualChartsSection: View {
    @ObservedObject var viewModel: PortfolioViewModel
    @Binding var privacyMode: Bool
    @Binding var chartToZoom: DividendChartZoomType?
    var currentYear: Int { Calendar.current.component(.year, from: Date()) }; var thisYearData: DividendYear? { viewModel.dividendYears.first { $0.year == currentYear } }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Spreadsheet Received History").font(.title2).fontWeight(.bold).foregroundColor(.secondary)
            HStack(spacing: 24) {
                MonthlyDividendChart(viewModel: viewModel, thisYearData: thisYearData, privacyMode: $privacyMode, expandedChart: $chartToZoom)
                YearlyDividendChart(viewModel: viewModel, currentYear: currentYear, privacyMode: $privacyMode, expandedChart: $chartToZoom)
            }
        }
    }
}

struct DividendsSecurityMetricsSection: View {
    @ObservedObject var viewModel: PortfolioViewModel
    @Binding var privacyMode: Bool
    @Binding var chartToZoom: DividendChartZoomType?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Positions Dividends & Yield On Cost").font(.title2).fontWeight(.bold).foregroundColor(.secondary)
            HStack(spacing: 24) {
                TotalDividendsDonutChart(viewModel: viewModel, privacyMode: $privacyMode, expandedChart: $chartToZoom)
                YieldOnCostChart(viewModel: viewModel, privacyMode: $privacyMode, expandedChart: $chartToZoom)
            }
        }
    }
}

struct DividendsAdvancedAnalyticsSection: View {
    @ObservedObject var viewModel: PortfolioViewModel
    @Binding var privacyMode: Bool
    @Binding var chartToZoom: DividendChartZoomType?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Advanced Analytics & History").font(.title2).fontWeight(.bold).foregroundColor(.secondary)
            HStack(spacing: 24) {
                AllTimeHistoryChart(viewModel: viewModel, privacyMode: $privacyMode, expandedChart: $chartToZoom)
                ExpectedDividendHeatmapChart(viewModel: viewModel, privacyMode: $privacyMode, expandedChart: $chartToZoom)
            }
        }
    }
}

struct DividendsGrowthAndSeasonalitySection: View {
    @ObservedObject var viewModel: PortfolioViewModel
    @Binding var privacyMode: Bool
    @Binding var chartToZoom: DividendChartZoomType?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Seasonality & Growth Rate").font(.title2).fontWeight(.bold).foregroundColor(.secondary)
            HStack(spacing: 24) {
                TotalMonthlySeasonalityChart(viewModel: viewModel, privacyMode: $privacyMode, expandedChart: $chartToZoom)
                DividendGrowthRateChart(viewModel: viewModel, privacyMode: $privacyMode, expandedChart: $chartToZoom)
            }
        }
    }
}

// =========================================================================
// MARK: - DIVIDEND CUSTOM UI COMPONENTS & CHARTS
// =========================================================================

// MARK: - CHART 1: EXPECTED MONTHLY
struct ExpectedMonthlyDividendChart: View {
    @ObservedObject var viewModel: PortfolioViewModel
    @Binding var privacyMode: Bool
    var isExpanded: Bool = false
    @Binding var expandedChart: DividendChartZoomType?
    @State private var hoveredMonth: String? = nil
    
    @State private var hiddenTypes: Set<String> = []
    
    struct MonthlyAggregated: Identifiable {
        var id = UUID()
        var month: String
        var type: String
        var amount: Double
    }
    
    let allMonths = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    
    var aggregatedData: [MonthlyAggregated] {
        var result: [MonthlyAggregated] = []
        for month in allMonths {
            let net = viewModel.expectedMonthlyDividendSeries.filter { $0.monthName == month && $0.type == "Net" }.reduce(0) { $0 + $1.amount }
            let gross = viewModel.expectedMonthlyDividendSeries.filter { $0.monthName == month && $0.type == "Gross" }.reduce(0) { $0 + $1.amount }
            
            result.append(MonthlyAggregated(month: month, type: "Gross", amount: gross))
            result.append(MonthlyAggregated(month: month, type: "Net", amount: net))
        }
        return result
    }
    
    var filteredData: [MonthlyAggregated] {
        aggregatedData.filter { !hiddenTypes.contains($0.type) }
    }
    
    var yMaxStatic: Double {
        let maxTotal = filteredData.map { $0.amount }.max() ?? 10.0
        return maxTotal > 0 ? maxTotal * 1.25 : 100.0
    }
    
    var body: some View {
        VStack {
            HStack {
                if !isExpanded { Text("Expected Monthly Income (Net vs Gross)").font(.headline).foregroundColor(.secondary) }
                Spacer()
                if !isExpanded { Button(action: { expandedChart = .expectedMonthly }) { Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary) }.buttonStyle(.plain) }
            }.padding(.bottom, 4)
            
            HStack(spacing: 16) {
                Button(action: { toggle("Gross") }) {
                    HStack(spacing: 6) { Circle().fill(Color.green).frame(width: 8, height: 8); Text("Gross").font(.caption).foregroundColor(hiddenTypes.contains("Gross") ? .secondary : .primary) }
                }.buttonStyle(.plain).opacity(hiddenTypes.contains("Gross") ? 0.4 : 1.0)
                
                Button(action: { toggle("Net") }) {
                    HStack(spacing: 6) { Circle().fill(Color.green.opacity(0.5)).frame(width: 8, height: 8); Text("Net").font(.caption).foregroundColor(hiddenTypes.contains("Net") ? .secondary : .primary) }
                }.buttonStyle(.plain).opacity(hiddenTypes.contains("Net") ? 0.4 : 1.0)
            }.padding(.bottom, 8)
            
            if filteredData.isEmpty { Spacer(); Text("No data").foregroundColor(.secondary); Spacer() } else {
                Chart(filteredData) { item in
                    BarMark(x: .value("Month", item.month), y: .value("Amount", item.amount))
                        .foregroundStyle(item.type == "Gross" ? Color.green : Color.green.opacity(0.5))
                        .position(by: .value("Type", item.type))
                        .cornerRadius(4)
                        .annotation(position: .top) {
                            if hoveredMonth == item.month && item.amount > 0 {
                                Text(item.amount.formatted(.currency(code: "EUR").precision(.fractionLength(2))))
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(.secondary)
                                    .blur(radius: privacyMode ? 6 : 0)
                            }
                        }
                }
                .chartLegend(.hidden)
                .chartXScale(domain: allMonths)
                .chartYScale(domain: 0...yMaxStatic)
                .chartYAxis { AxisMarks(position: .leading) { value in AxisGridLine(); AxisTick(); if let v = value.as(Double.self) { AxisValueLabel(v.formatted(.currency(code: "EUR").precision(.fractionLength(0)))) } } }
                .chartXSelection(value: $hoveredMonth)
            }
            BlueChipWatermark()
        }.padding().frame(minHeight: 360, maxHeight: isExpanded ? .infinity : 360).background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    func toggle(_ type: String) { withAnimation { if hiddenTypes.contains(type) { hiddenTypes.remove(type) } else { hiddenTypes.insert(type) } } }
}

// MARK: - CHART 2: STOCK YIELD
struct StockYieldChart: View {
    @ObservedObject var viewModel: PortfolioViewModel
    @Binding var privacyMode: Bool
    var isExpanded: Bool = false; @Binding var expandedChart: DividendChartZoomType?
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
                        .annotation(position: .top) { if hoveredTicker == item.ticker { Text("\(item.yield.formatted(.number.precision(.fractionLength(2))))%").font(.system(size: 9, weight: .bold)).foregroundColor(.secondary).blur(radius: privacyMode ? 6 : 0) } }
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
    @ObservedObject var viewModel: PortfolioViewModel; var thisYearData: DividendYear?
    @Binding var privacyMode: Bool
    var isExpanded: Bool = false; @Binding var expandedChart: DividendChartZoomType?
    @State private var hoveredMonth: String? = nil
    let allMonths = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    var monthlyData: [(String, Double)] { guard let thisYear = thisYearData else { return [] }; return [("Jan", thisYear.jan), ("Feb", thisYear.feb), ("Mar", thisYear.mar), ("Apr", thisYear.apr), ("May", thisYear.may), ("Jun", thisYear.jun), ("Jul", thisYear.jul), ("Aug", thisYear.aug), ("Sep", thisYear.sep), ("Oct", thisYear.oct), ("Nov", thisYear.nov), ("Dec", thisYear.dec)] }
    var yMaxStatic: Double { guard let thisYear = thisYearData else { return 10 }; let months = [thisYear.jan, thisYear.feb, thisYear.mar, thisYear.apr, thisYear.may, thisYear.jun, thisYear.jul, thisYear.aug, thisYear.sep, thisYear.oct, thisYear.nov, thisYear.dec]; return (months.max() ?? 10) * 1.2 }
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
                        .annotation(position: .top) { if hoveredMonth == item.0 && item.1 > 0 { Text(item.1.formatted(.currency(code: "EUR").precision(.fractionLength(2)))).font(.system(size: 9, weight: .bold)).foregroundColor(.secondary).blur(radius: privacyMode ? 6 : 0) } }
                }
                .chartXScale(domain: allMonths)
                .chartYScale(domain: 0...yMaxStatic)
                .chartYAxis { AxisMarks { value in if let v = value.as(Double.self) { AxisValueLabel(v.formatted(.currency(code: "EUR").precision(.fractionLength(0)))) } } }
                .chartXSelection(value: $hoveredMonth)
            }
            BlueChipWatermark()
        }.padding().frame(minHeight: 360, maxHeight: isExpanded ? .infinity : 360).background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// MARK: - CHART 4: MANUAL YEARLY
struct YearlyDividendChart: View {
    @ObservedObject var viewModel: PortfolioViewModel; var currentYear: Int
    @Binding var privacyMode: Bool
    var isExpanded: Bool = false; @Binding var expandedChart: DividendChartZoomType?
    @State private var hoveredYear: String? = nil
    var activeYears: [DividendYear] { viewModel.dividendYears.filter { $0.total > 0 || $0.year == currentYear } }
    var yMaxStatic: Double { return (activeYears.map { $0.total }.max() ?? 10) * 1.2 }
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
                        .annotation(position: .top) { if hoveredYear == yearStr { Text(yearData.total.formatted(.currency(code: "EUR").precision(.fractionLength(2)))).font(.system(size: 9, weight: .bold)).foregroundColor(.secondary).blur(radius: privacyMode ? 6 : 0) } }
                }
                .chartYScale(domain: 0...yMaxStatic)
                .chartYAxis { AxisMarks { value in if let v = value.as(Double.self) { AxisValueLabel(v.formatted(.currency(code: "EUR").precision(.fractionLength(0)))) } } }
                .chartXSelection(value: $hoveredYear)
            }
            BlueChipWatermark()
        }.padding().frame(minHeight: 360, maxHeight: isExpanded ? .infinity : 360).background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// MARK: - CHART 5: TOTAL DIVIDENDS DONUT
struct TotalDividendsDonutChart: View {
    @ObservedObject var viewModel: PortfolioViewModel
    @Binding var privacyMode: Bool
    var isExpanded: Bool = false; @Binding var expandedChart: DividendChartZoomType?
    @State private var selectedAngleValue: Double? = nil; @State private var hiddenItems: Set<String> = []
    var data: [ChartDataItem] { viewModel.positions.filter { $0.totalDividendEUR > 0 }.map { ChartDataItem(name: $0.ticker, value: $0.totalDividendEUR) }.sorted { $0.value > $1.value } }
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
                Chart(filteredData) { item in SectorMark(angle: .value("Value", item.value), innerRadius: .ratio(0.65), angularInset: 1.5).foregroundStyle(viewModel.color(for: item.name)).cornerRadius(4) }
                .chartLegend(.hidden).chartAngleSelection(value: $selectedAngleValue)
                .chartBackground { proxy in
                    GeometryReader { geometry in
                        if let value = selectedAngleValue {
                            let item = findItem(for: value)
                            VStack { Text(item.name).font(.headline); Text(item.value.formatted(.currency(code: "EUR").precision(.fractionLength(2)))).font(.subheadline).foregroundColor(.secondary).blur(radius: privacyMode ? 6 : 0) }.position(x: geometry.frame(in: .local).midX, y: geometry.frame(in: .local).midY)
                        }
                    }
                }.animation(.easeInOut(duration: 0.2), value: selectedAngleValue)
            }
            BlueChipWatermark()
        }.padding().frame(minHeight: 360, maxHeight: isExpanded ? .infinity : 360).background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    func findItem(for value: Double) -> ChartDataItem { var cum = 0.0; for item in filteredData { cum += item.value; if value <= cum { return item } }; return filteredData.last! }
}

// MARK: - CHART 6: YIELD ON COST
struct YieldOnCostChart: View {
    @ObservedObject var viewModel: PortfolioViewModel
    @Binding var privacyMode: Bool
    var isExpanded: Bool = false; @Binding var expandedChart: DividendChartZoomType?
    @State private var hoveredTicker: String? = nil
    var data: [ChartDataItem] { viewModel.positions.filter { $0.investedAmountEUR > 0 && $0.totalDividendEUR > 0 }.map { ChartDataItem(name: $0.ticker, value: ($0.totalDividendEUR / $0.investedAmountEUR) * 100.0) }.sorted { $0.name < $1.name } }
    var body: some View {
        VStack {
            HStack {
                if !isExpanded { Text("Yield On Cost (YOC)").font(.headline).foregroundColor(.secondary) }
                Spacer()
                if !isExpanded { Button(action: { expandedChart = .yoc }) { Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary) }.buttonStyle(.plain) }
            }.padding(.bottom, 8)
            if data.isEmpty { Spacer(); Text("No data").foregroundColor(.secondary); Spacer() } else {
                Chart(data) { item in
                    BarMark(x: .value("Ticker", item.name), y: .value("YOC", item.value)).foregroundStyle(viewModel.color(for: item.name)).cornerRadius(4)
                        .annotation(position: .top) { if hoveredTicker == item.name { Text("\(item.value.formatted(.number.precision(.fractionLength(2))))%").font(.system(size: 9, weight: .bold)).foregroundColor(.secondary).blur(radius: privacyMode ? 6 : 0) } }
                }
                .chartLegend(.hidden)
                .chartYAxis { AxisMarks(position: .leading) { value in AxisGridLine(); AxisTick(); if let v = value.as(Double.self) { AxisValueLabel("\(v.formatted(.number.precision(.fractionLength(0))))%") } } }
                .chartXSelection(value: $hoveredTicker)
            }
            BlueChipWatermark()
        }.padding().frame(minHeight: 360, maxHeight: isExpanded ? .infinity : 360).background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// MARK: - CHART 7: ALL-TIME HISTORY & TREND LINE
struct HistoricalDividendItem: Identifiable {
    let id = UUID()
    let date: Date
    let amount: Double
    let trend: Double
}

struct AllTimeHistoryChart: View {
    @ObservedObject var viewModel: PortfolioViewModel
    @Binding var privacyMode: Bool
    var isExpanded: Bool = false
    @Binding var expandedChart: DividendChartZoomType?
    @State private var hoveredDate: Date? = nil

    var historicalData: [HistoricalDividendItem] {
        var rawData: [(Date, Double)] = []
        let sortedYears = viewModel.dividendYears.sorted { $0.year < $1.year }
        let currentYear = Calendar.current.component(.year, from: Date())
        let currentMonth = Calendar.current.component(.month, from: Date())

        for yearData in sortedYears {
            let amounts = [yearData.jan, yearData.feb, yearData.mar, yearData.apr, yearData.may, yearData.jun, yearData.jul, yearData.aug, yearData.sep, yearData.oct, yearData.nov, yearData.dec]
            for (mIndex, amount) in amounts.enumerated() {
                if yearData.year > currentYear || (yearData.year == currentYear && (mIndex + 1) > currentMonth) { continue }
                var comps = DateComponents(); comps.year = yearData.year; comps.month = mIndex + 1; comps.day = 1
                if let date = Calendar.current.date(from: comps) { rawData.append((date, amount)) }
            }
        }
        
        while let first = rawData.first, first.1 == 0 { rawData.removeFirst() }
        
        let amounts = rawData.map { $0.1 }
        let n = Double(amounts.count)
        var trends: [Double] = []
        
        if n > 1 {
            let sumX = (0..<Int(n)).reduce(0) { $0 + Double($1) }
            let sumY = amounts.reduce(0, +)
            let sumXY = (0..<Int(n)).reduce(0) { $0 + Double($1) * amounts[$1] }
            let sumX2 = (0..<Int(n)).reduce(0) { $0 + Double($1) * Double($1) }
            let slope = (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX)
            let intercept = (sumY - slope * sumX) / n
            trends = (0..<Int(n)).map { slope * Double($0) + intercept }
        } else { trends = amounts }

        var items: [HistoricalDividendItem] = []
        for i in 0..<rawData.count { items.append(HistoricalDividendItem(date: rawData[i].0, amount: rawData[i].1, trend: trends[i])) }
        return items
    }
    
    var yMaxStatic: Double {
        let maxAmount = historicalData.map { $0.amount }.max() ?? 10
        let maxTrend = historicalData.map { $0.trend }.max() ?? 10
        return max(maxAmount, maxTrend) * 1.25
    }

    var body: some View {
        VStack {
            HStack {
                if !isExpanded { Text("All-Time Dividend History & Trend").font(.headline).foregroundColor(.secondary) }
                Spacer()
                if !isExpanded { Button(action: { expandedChart = .allTimeHistory }) { Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary) }.buttonStyle(.plain) }
            }.padding(.bottom, 8)
            
            if historicalData.isEmpty { Spacer(); Text("No data").foregroundColor(.secondary); Spacer() } else {
                Chart {
                    ForEach(historicalData) { item in
                        AreaMark(x: .value("Date", item.date), y: .value("Amount", item.amount))
                            .foregroundStyle(LinearGradient(gradient: Gradient(colors: [Color.green.opacity(0.4), .clear]), startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.monotone)
                        
                        LineMark(x: .value("Date", item.date), y: .value("Amount", item.amount))
                            .foregroundStyle(Color.green)
                            .interpolationMethod(.monotone)
                        
                        LineMark(x: .value("Date", item.date), y: .value("Trend", item.trend))
                            .foregroundStyle(Color.orange.opacity(0.8))
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [5]))
                    }
                    
                    if let hoveredDate = hoveredDate {
                        if let item = historicalData.min(by: { abs($0.date.timeIntervalSince(hoveredDate)) < abs($1.date.timeIntervalSince(hoveredDate)) }) {
                            RuleMark(x: .value("Date", item.date))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                                .foregroundStyle(.secondary.opacity(0.5))
                                .annotation(position: .top, alignment: .center) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.date.formatted(.dateTime.month(.abbreviated).year())).font(.system(size: 9, weight: .bold))
                                        Text(item.amount.formatted(.currency(code: "EUR").precision(.fractionLength(2)))).font(.system(size: 9)).foregroundColor(.green).blur(radius: privacyMode ? 6 : 0)
                                    }.padding(4).background(Color(NSColor.windowBackgroundColor).opacity(0.8)).cornerRadius(4)
                                }
                        }
                    }
                }
                .chartLegend(.hidden)
                .chartYScale(domain: 0...yMaxStatic)
                .chartYAxis { AxisMarks(position: .leading) { value in AxisGridLine(); AxisTick(); if let v = value.as(Double.self) { AxisValueLabel(v.formatted(.currency(code: "EUR").precision(.fractionLength(0)))) } } }
                .chartXAxis { AxisMarks(preset: .aligned, values: .stride(by: .month, count: 6)) { value in AxisGridLine(); AxisTick(); AxisValueLabel(format: .dateTime.month().year()) } }
                .chartXSelection(value: $hoveredDate)
            }
            BlueChipWatermark()
        }.padding().frame(minHeight: 360, maxHeight: isExpanded ? .infinity : 360).background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// MARK: - CHART 8: DIVIDEND CALENDAR HEATMAP
struct ExpectedDividendHeatmapChart: View {
    @ObservedObject var viewModel: PortfolioViewModel
    @Binding var privacyMode: Bool
    var isExpanded: Bool = false
    @Binding var expandedChart: DividendChartZoomType?
    
    @State private var hoveredMonth: String? = nil
    @State private var hoveredTicker: String? = nil
    
    var netItems: [ExpectedMonthlyDividendSeries] { viewModel.expectedMonthlyDividendSeries.filter { $0.type == "Net" } }
    var maxAmount: Double { netItems.map { $0.amount }.max() ?? 1.0 }

    var body: some View {
        VStack {
            HStack {
                if !isExpanded { Text("Dividend Calendar Heatmap").font(.headline).foregroundColor(.secondary) }
                Spacer()
                if !isExpanded { Button(action: { expandedChart = .heatmap }) { Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary) }.buttonStyle(.plain) }
            }.padding(.bottom, 8)
            
            if netItems.isEmpty { Spacer(); Text("No data").foregroundColor(.secondary); Spacer() } else {
                Chart(netItems) { item in
                    RectangleMark(x: .value("Month", item.monthName), y: .value("Ticker", item.ticker))
                        .foregroundStyle(viewModel.color(for: item.ticker).opacity(0.2 + 0.8 * (item.amount / maxAmount)))
                        .cornerRadius(2)
                }
                .chartLegend(.hidden)
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let location):
                                    if let (month, ticker) = proxy.value(at: location, as: (String, String).self) {
                                        hoveredMonth = month
                                        hoveredTicker = ticker
                                    }
                                case .ended:
                                    hoveredMonth = nil
                                    hoveredTicker = nil
                                }
                            }
                        
                        if let hMonth = hoveredMonth, let hTicker = hoveredTicker {
                            if let item = netItems.first(where: { $0.monthName == hMonth && $0.ticker == hTicker }) {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Circle().fill(viewModel.color(for: item.ticker)).frame(width: 8, height: 8)
                                        Text("\(item.ticker) in \(item.monthName)").font(.caption.bold())
                                    }
                                    Divider()
                                    Text("Net: \(item.amount.formatted(.currency(code: "EUR").precision(.fractionLength(2))))").font(.caption2.bold()).foregroundColor(.primary).blur(radius: privacyMode ? 6 : 0)
                                    Text("Gross: \((item.amount / 0.85).formatted(.currency(code: "EUR").precision(.fractionLength(2))))").font(.caption2).foregroundColor(.secondary).blur(radius: privacyMode ? 6 : 0)
                                }
                                .padding(8).background(Color(NSColor.windowBackgroundColor).opacity(0.95)).cornerRadius(8).shadow(radius: 4)
                                .position(x: geometry.frame(in: .local).midX, y: geometry.frame(in: .local).midY)
                                .allowsHitTesting(false)
                            }
                        }
                    }
                }
            }
            BlueChipWatermark()
        }.padding().frame(minHeight: 360, maxHeight: isExpanded ? .infinity : 360).background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// --- NOUVEAU GRAPHIQUE 9 : ALL-TIME MONTHLY SEASONALITY ---
struct TotalMonthlySeasonalityChart: View {
    @ObservedObject var viewModel: PortfolioViewModel
    @Binding var privacyMode: Bool
    var isExpanded: Bool = false
    @Binding var expandedChart: DividendChartZoomType?
    
    @State private var hoveredMonth: String? = nil
    
    let allMonths = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    
    struct SeasonalityItem: Identifiable {
        let id = UUID()
        let month: String
        let total: Double
    }
    
    var data: [SeasonalityItem] {
        var totals = Array(repeating: 0.0, count: 12)
        
        for yearData in viewModel.dividendYears {
            totals[0] += yearData.jan
            totals[1] += yearData.feb
            totals[2] += yearData.mar
            totals[3] += yearData.apr
            totals[4] += yearData.may
            totals[5] += yearData.jun
            totals[6] += yearData.jul
            totals[7] += yearData.aug
            totals[8] += yearData.sep
            totals[9] += yearData.oct
            totals[10] += yearData.nov
            totals[11] += yearData.dec
        }
        
        var items: [SeasonalityItem] = []
        for i in 0..<12 {
            items.append(SeasonalityItem(month: allMonths[i], total: totals[i]))
        }
        return items
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if !isExpanded { Text("Cumulative Monthly Seasonality").font(.headline).foregroundColor(.secondary) }
                Spacer()
                if !isExpanded { Button(action: { expandedChart = .seasonality }) { Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary) }.buttonStyle(.plain) }
            }.padding(.bottom, 8)
            
            let totalSum = data.reduce(0) { $0 + $1.total }
            
            if totalSum == 0 {
                Spacer(); Text("No data").foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .center); Spacer()
            } else {
                Chart(data) { item in
                    BarMark(
                        x: .value("Month", item.month),
                        y: .value("Total", item.total)
                    )
                    .foregroundStyle(Color.orange.opacity(0.8))
                    .cornerRadius(4)
                    .annotation(position: .top) {
                        if hoveredMonth == item.month && item.total > 0 {
                            Text(item.total.formatted(.currency(code: "EUR").precision(.fractionLength(2))))
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.secondary)
                                .blur(radius: privacyMode ? 6 : 0)
                        }
                    }
                }
                .chartXScale(domain: allMonths)
                .chartYAxis { AxisMarks(position: .leading) { value in AxisGridLine(); AxisTick(); if let v = value.as(Double.self) { AxisValueLabel(v.formatted(.currency(code: "EUR").notation(.compactName))) } } }
                .chartXSelection(value: $hoveredMonth)
            }
            HStack { Text("Total aggregated dividends per month since portfolio inception").font(.caption2).foregroundColor(.secondary); Spacer(); BlueChipWatermark() }
        }
        .padding().frame(minHeight: 360, maxHeight: isExpanded ? .infinity : 360).background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// --- NOUVEAU GRAPHIQUE 10 : DIVIDEND GROWTH RATE (YoY) ---
struct DGRItem: Identifiable {
    let id = UUID()
    let year: Int
    let dgr: Double
}

struct DividendGrowthRateChart: View {
    @ObservedObject var viewModel: PortfolioViewModel
    @Binding var privacyMode: Bool
    var isExpanded: Bool = false
    @Binding var expandedChart: DividendChartZoomType?
    
    @State private var hoveredYear: String? = nil
    
    var currentYear: Int { Calendar.current.component(.year, from: Date()) }
    
    var data: [DGRItem] {
        let startYear = viewModel.dividendStartYear
        var items: [DGRItem] = []
        
        if currentYear <= startYear { return items }
        
        for year in (startYear + 1)...currentYear {
            let prevYearTotal = viewModel.dividendYears.first(where: { $0.year == year - 1 })?.total ?? 0.0
            let currYearTotal = viewModel.dividendYears.first(where: { $0.year == year })?.total ?? 0.0
            
            if prevYearTotal > 0 {
                let dgr = ((currYearTotal - prevYearTotal) / prevYearTotal) * 100.0
                items.append(DGRItem(year: year, dgr: dgr))
            }
        }
        return items
    }
    
    var yearsDomain: [String] {
        data.map { String($0.year) }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if !isExpanded { Text("Dividend Growth Rate (YoY DGR)").font(.headline).foregroundColor(.secondary) }
                Spacer()
                if !isExpanded { Button(action: { expandedChart = .dgr }) { Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary) }.buttonStyle(.plain) }
            }.padding(.bottom, 8)
            
            if let hYearStr = hoveredYear, let hYearInt = Int(hYearStr), let item = data.first(where: { $0.year == hYearInt }) {
                HStack(spacing: 8) {
                    Text(String(item.year)).fontWeight(.bold)
                    Text("\(item.dgr > 0 ? "+" : "")\(item.dgr.formatted(.number.precision(.fractionLength(1))))%")
                        .foregroundColor(item.dgr >= 0 ? .green : .red)
                        .fontWeight(.bold)
                        .blur(radius: privacyMode ? 6 : 0)
                }
                .font(.caption).padding(.horizontal, 8).padding(.vertical, 4).background(Color(NSColor.windowBackgroundColor)).cornerRadius(6).transition(.opacity)
            } else {
                Text("Hover to view").font(.caption).foregroundColor(.clear)
            }
            
            if data.isEmpty {
                Spacer(); Text("Need at least two consecutive years with dividends to calculate YoY growth.").foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .center); Spacer()
            } else {
                Chart(data) { item in
                    RuleMark(y: .value("Zero", 0))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                        .foregroundStyle(Color.gray.opacity(0.3))
                    
                    AreaMark(
                        x: .value("Year", String(item.year)),
                        y: .value("DGR", item.dgr)
                    )
                    .foregroundStyle(LinearGradient(colors: [Color.green.opacity(0.4), Color.green.opacity(0.0)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                    
                    LineMark(
                        x: .value("Year", String(item.year)),
                        y: .value("DGR", item.dgr)
                    )
                    .foregroundStyle(Color.green)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    .interpolationMethod(.monotone)
                    .symbol { Circle().fill(item.dgr >= 0 ? Color.green : Color.red).frame(width: 8, height: 8) }
                    
                    if let y = hoveredYear {
                        RuleMark(x: .value("Year", y))
                            .foregroundStyle(Color.secondary.opacity(0.4))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                }
                .chartXSelection(value: $hoveredYear)
                .chartXScale(domain: yearsDomain)
                .chartYAxis { AxisMarks(position: .leading) { value in AxisGridLine(); AxisTick(); if let v = value.as(Double.self) { AxisValueLabel("\(v.formatted(.number.precision(.fractionLength(0))))%") } } }
                .chartXAxis {
                    AxisMarks(values: .automatic) { value in
                        if let strYear = value.as(String.self) { AxisValueLabel { Text(strYear).font(.caption) } }
                    }
                }
            }
            HStack { Text("Year-over-Year percentage increase of total dividends").font(.caption2).foregroundColor(.secondary); Spacer(); BlueChipWatermark() }
        }
        .padding().frame(minHeight: 360, maxHeight: isExpanded ? .infinity : 360).background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}


// MARK: - FULL SCREEN ZOOM
struct DividendFullScreenChartView: View {
    @Environment(\.dismiss) var dismiss
    let zoomType: DividendChartZoomType
    @ObservedObject var viewModel: PortfolioViewModel
    @Binding var privacyMode: Bool
    
    var currentYear: Int { Calendar.current.component(.year, from: Date()) }
    var thisYearData: DividendYear? { viewModel.dividendYears.first { $0.year == currentYear } }
    
    var body: some View {
        VStack(spacing: 20) {
            HStack { Text(titleForZoom).font(.title).fontWeight(.bold); Spacer(); Button(action: { dismiss() }) { Image(systemName: "xmark.circle.fill").font(.title).foregroundColor(.secondary) }.buttonStyle(.plain) }
            
            switch zoomType {
            case .expectedMonthly: ExpectedMonthlyDividendChart(viewModel: viewModel, privacyMode: $privacyMode, isExpanded: true, expandedChart: .constant(nil))
            case .stockYield: StockYieldChart(viewModel: viewModel, privacyMode: $privacyMode, isExpanded: true, expandedChart: .constant(nil))
            case .monthly: MonthlyDividendChart(viewModel: viewModel, thisYearData: thisYearData, privacyMode: $privacyMode, isExpanded: true, expandedChart: .constant(nil))
            case .yearly: YearlyDividendChart(viewModel: viewModel, currentYear: currentYear, privacyMode: $privacyMode, isExpanded: true, expandedChart: .constant(nil))
            case .totalDividends: TotalDividendsDonutChart(viewModel: viewModel, privacyMode: $privacyMode, isExpanded: true, expandedChart: .constant(nil))
            case .yoc: YieldOnCostChart(viewModel: viewModel, privacyMode: $privacyMode, isExpanded: true, expandedChart: .constant(nil))
            case .allTimeHistory: AllTimeHistoryChart(viewModel: viewModel, privacyMode: $privacyMode, isExpanded: true, expandedChart: .constant(nil))
            case .heatmap: ExpectedDividendHeatmapChart(viewModel: viewModel, privacyMode: $privacyMode, isExpanded: true, expandedChart: .constant(nil))
            case .seasonality: TotalMonthlySeasonalityChart(viewModel: viewModel, privacyMode: $privacyMode, isExpanded: true, expandedChart: .constant(nil))
            case .dgr: DividendGrowthRateChart(viewModel: viewModel, privacyMode: $privacyMode, isExpanded: true, expandedChart: .constant(nil))
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
        case .allTimeHistory: return "All-Time Dividend History & Trend"
        case .heatmap: return "Dividend Calendar Heatmap"
        case .seasonality: return "Cumulative Monthly Seasonality"
        case .dgr: return "Dividend Growth Rate (YoY DGR)"
        }
    }
}

// =========================================================================
// MARK: - THIS MONTH'S DIVIDEND TRACKER
// =========================================================================

struct DividendsThisMonthSection: View {
    @ObservedObject var viewModel: PortfolioViewModel
    @Binding var privacyMode: Bool
    
    var currentYear: Int { Calendar.current.component(.year, from: Date()) }
    var currentMonth: Int { Calendar.current.component(.month, from: Date()) }
    var currentMonthName: String { Calendar.current.monthSymbols[currentMonth - 1] }
    
    var payingStocks: [Position] {
        viewModel.positions.filter { $0.dividendMonths.contains(currentMonth) }.sorted { $0.ticker < $1.ticker }
    }
    
    var totalExpected: Double {
        payingStocks.reduce(0.0) { sum, pos in
            let monthsCount = max(1, pos.dividendMonths.count)
            return sum + (pos.totalDividendEUR / Double(monthsCount))
        }
    }
    
    @State private var receivedDict: [String: Double] = [:]
    @State private var selectedAngleValue: Double? = nil
    
    var totalReceived: Double { receivedDict.values.reduce(0, +) }
    
    // CORRECTION 3 : Force les 100% si on a reçu exactement la somme attendue
    var progress: Double {
        guard totalExpected > 0 else { return 0 }
        let diff = abs(totalReceived - totalExpected)
        if diff < 0.01 { return 1.0 } // Moins d'un centime d'écart = 100%
        return totalReceived / totalExpected
    }
    
    var donutData: [ChartDataItem] {
        receivedDict.filter { $0.value > 0 }.map { ChartDataItem(name: $0.key, value: $0.value) }.sorted { $0.value > $1.value }
    }
    
    // CORRECTION 2 : Hauteur dynamique basée sur le nombre de lignes
    var dynamicTableHeight: CGFloat {
        let rowHeight: CGFloat = 44
        let headerHeight: CGFloat = 32
        if payingStocks.isEmpty { return 100 }
        let calculated = CGFloat(payingStocks.count) * rowHeight + headerHeight
        return min(max(calculated, 100), 400) // 400 max pour éviter de prendre tout l'écran s'il y a 20 actions
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("This Month (\(currentMonthName)) Tracker").font(.title2).fontWeight(.bold).foregroundColor(.secondary)
            
            if payingStocks.isEmpty {
                Text("No dividends expected this month based on your portfolio settings.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                HStack(alignment: .center, spacing: 32) {
                    
                    // --- GAUCHE : DONUT CHART ---
                    VStack {
                        if donutData.isEmpty {
                            ZStack {
                                Circle().stroke(Color.gray.opacity(0.2), lineWidth: 30).frame(width: 180, height: 180)
                                Text("Waiting for payouts...").font(.caption).foregroundColor(.secondary)
                            }
                        } else {
                            Chart(donutData) { item in
                                SectorMark(angle: .value("Value", item.value), innerRadius: .ratio(0.65), angularInset: 1.5)
                                    .foregroundStyle(viewModel.color(for: item.name))
                                    .cornerRadius(4)
                            }
                            .chartLegend(.hidden)
                            .chartAngleSelection(value: $selectedAngleValue)
                            .chartBackground { proxy in
                                GeometryReader { geometry in
                                    if let value = selectedAngleValue, let item = findItem(for: value) {
                                        VStack {
                                            Text(item.name).font(.headline)
                                            Text(item.value.formatted(.currency(code: "EUR"))).font(.subheadline).foregroundColor(.secondary).blur(radius: privacyMode ? 6 : 0)
                                        }.position(x: geometry.frame(in: .local).midX, y: geometry.frame(in: .local).midY)
                                    } else {
                                        VStack {
                                            Text("Received").font(.caption).foregroundColor(.secondary)
                                            Text(totalReceived.formatted(.currency(code: "EUR").precision(.fractionLength(2)))).font(.title3).fontWeight(.bold).blur(radius: privacyMode ? 6 : 0)
                                        }.position(x: geometry.frame(in: .local).midX, y: geometry.frame(in: .local).midY)
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 250) // Hauteur fixe pour le donut pour qu'il reste esthétique
                    
                    // --- DROITE : STATS & TABLEAU ---
                    VStack(alignment: .leading, spacing: 16) {
                        
                        // Header Stats
                        HStack(spacing: 20) {
                            VStack(alignment: .leading) {
                                Text("Expected Total").font(.caption).foregroundColor(.secondary)
                                Text(totalExpected.formatted(.currency(code: "EUR"))).font(.title3).fontWeight(.bold).blur(radius: privacyMode ? 6 : 0)
                            }
                            Divider().frame(height: 30)
                            VStack(alignment: .leading) {
                                Text("Remaining").font(.caption).foregroundColor(.secondary)
                                let remaining = max(0, totalExpected - totalReceived)
                                Text(remaining.formatted(.currency(code: "EUR"))).font(.title3).fontWeight(.bold).foregroundColor(.orange).blur(radius: privacyMode ? 6 : 0)
                            }
                            Divider().frame(height: 30)
                            VStack(alignment: .leading) {
                                Text("Progress").font(.caption).foregroundColor(.secondary)
                                Text(progress.formatted(.percent.precision(.fractionLength(1)))).font(.title3).fontWeight(.bold).foregroundColor(progress >= 1 ? .green : .blue).blur(radius: privacyMode ? 6 : 0)
                            }
                        }
                        .padding(12).background(Color(NSColor.windowBackgroundColor)).cornerRadius(8)
                        
                        // Tableau des saisies
                        VStack(spacing: 0) {
                            HStack {
                                Text("Ticker").fontWeight(.bold).frame(width: 60, alignment: .leading)
                                Text("Expected").fontWeight(.bold).frame(maxWidth: .infinity, alignment: .trailing)
                                Text("Received").fontWeight(.bold).frame(width: 100, alignment: .trailing)
                            }
                            .font(.caption).foregroundColor(.secondary).padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Color(NSColor.windowBackgroundColor))
                            
                            Divider()
                            
                            ScrollView {
                                VStack(spacing: 0) {
                                    ForEach(payingStocks) { pos in
                                        let expectedAmount = pos.totalDividendEUR / Double(max(1, pos.dividendMonths.count))
                                        HStack {
                                            HStack(spacing: 6) {
                                                Circle().fill(viewModel.color(for: pos.ticker)).frame(width: 8, height: 8)
                                                Text(pos.ticker).fontWeight(.bold)
                                            }.frame(width: 60, alignment: .leading)
                                            
                                            Text(expectedAmount.formatted(.currency(code: "EUR"))).foregroundColor(.secondary).blur(radius: privacyMode ? 6 : 0).frame(maxWidth: .infinity, alignment: .trailing)
                                            
                                            TickerMonthField(ticker: pos.ticker, value: binding(for: pos.ticker), privacyMode: privacyMode)
                                                .frame(width: 100, alignment: .trailing)
                                        }
                                        .padding(.horizontal, 12).padding(.vertical, 8)
                                        Divider()
                                    }
                                }
                            }
                        }
                        .frame(height: dynamicTableHeight) // CORRECTION 2 : Application de la hauteur dynamique
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        .onAppear { loadDict() }
    }
    
    // --- GESTION DES DONNÉES LOCALES ---
    private var userDefaultsKey: String { "divTracker_\(currentYear)_\(currentMonth)" }
    
    func binding(for ticker: String) -> Binding<Double> {
        Binding<Double>(
            get: { receivedDict[ticker] ?? 0.0 },
            set: { receivedDict[ticker] = $0; saveDict() }
        )
    }
    
    func loadDict() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let dict = try? JSONDecoder().decode([String: Double].self, from: data) {
            receivedDict = dict
        }
    }
    
    func saveDict() {
        if let data = try? JSONEncoder().encode(receivedDict) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }
    
    func findItem(for value: Double) -> ChartDataItem? {
        var cum = 0.0
        for item in donutData {
            cum += item.value
            if value <= cum { return item }
        }
        return donutData.last
    }
}

// =========================================================================
// MARK: - CHAMP DE SAISIE FIABLE (ANTI-BUG)
// =========================================================================
struct TickerMonthField: View {
    let ticker: String
    @Binding var value: Double
    var privacyMode: Bool
    
    @State private var textValue: String = ""
    
    var body: some View {
        TextField("0.00", text: $textValue)
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .blur(radius: privacyMode ? 6 : 0)
            .onAppear {
                if value != 0 { textValue = value.formatted(.number.grouping(.never)) }
            }
            .onChange(of: textValue) { _, newValue in
                let cleanString = newValue.replacingOccurrences(of: ",", with: ".")
                if let doubleVal = Double(cleanString) {
                    value = doubleVal
                } else if newValue.isEmpty {
                    value = 0
                }
            }
    }
}
