import SwiftUI
import Charts

// MARK: - SPECIFIC ZOOM ENUM FOR DIVIDENDS
enum DividendChartZoomType: String, Identifiable {
    case monthly, yearly
    var id: String { self.rawValue }
}

struct DividendsView: View {
    @ObservedObject var viewModel: PortfolioViewModel
    @Binding var privacyMode: Bool
    
    @State private var showGoalSheet = false
    @State private var chartToZoom: DividendChartZoomType? = nil
    
    typealias YearBinding = Binding<DividendYear>
    
    // --- CALCUL DES STATISTIQUES ---
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
    
    var averageMonthlyThisYear: Double {
        let elapsedMonths = Double(max(1, currentMonthIndex))
        return receivedThisYear / elapsedMonths
    }
    
    var bestYear: Double { viewModel.dividendYears.map { $0.total }.max() ?? 0 }
    
    var yoyGrowth: Double {
        guard receivedLastYear > 0 else { return 0 }
        return (receivedThisYear - receivedLastYear) / receivedLastYear
    }
    
    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 24) {
                
                // --- 1. DASHBOARD CARDS ---
                VStack(spacing: 16) {
                    HStack(spacing: 16) {
                        DashboardCard(title: "Total Received (All Time)", value: totalReceivedAllTime.formatted(.currency(code: "EUR")), privacyMode: $privacyMode)
                        DashboardCard(title: "Received This Year", value: receivedThisYear.formatted(.currency(code: "EUR")), privacyMode: $privacyMode)
                        DashboardCard(title: "Received This Month", value: receivedThisMonth.formatted(.currency(code: "EUR")), privacyMode: $privacyMode)
                        DashboardCard(title: "Avg. Monthly (This Year)", value: averageMonthlyThisYear.formatted(.currency(code: "EUR")) + "/mo", privacyMode: $privacyMode)
                    }
                    
                    HStack(spacing: 16) {
                        DashboardCard(title: "Best Year", value: bestYear.formatted(.currency(code: "EUR")), privacyMode: $privacyMode)
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text("YoY Growth (vs Last Year)").font(.subheadline).foregroundColor(.secondary).lineLimit(1)
                            Text(yoyGrowth.formatted(.percent.precision(.fractionLength(1)).sign(strategy: .always())))
                                .font(.title2).fontWeight(.bold)
                                .foregroundColor(yoyGrowth >= 0 ? .green : .red)
                                .blur(radius: privacyMode ? 8 : 0)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: 110)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(10)
                        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                        
                        DashboardCard(title: "Projected Annual Yield", value: viewModel.portfolioYield.formatted(.percent.precision(.fractionLength(2))), privacyMode: $privacyMode)
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Start Year").font(.subheadline).foregroundColor(.secondary)
                            TextField("Year", value: $viewModel.dividendStartYear, format: .number.grouping(.never))
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 80)
                                .font(.title3.bold())
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: 110)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(10)
                        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                    }
                }
                
                // --- 2. PROGRESS BAR CUSTOM DIVIDEND ---
                DividendGoalProgressBar(
                    currentValue: receivedThisYear,
                    targetValue: viewModel.currentGoalTarget,
                    currentCapital: viewModel.currentTotalCapital,
                    privacyMode: $privacyMode
                )
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { showGoalSheet = true }
                
                // --- 3. SPREADSHEET TABLE ---
                VStack(alignment: .leading, spacing: 8) {
                    Text("Dividend Tracker").font(.headline).foregroundColor(.secondary).padding(.bottom, 4)
                    
                    Table($viewModel.dividendYears) {
                        
                        Group {
                            TableColumn("Year") { (yearBinding: YearBinding) in
                                Text(String(yearBinding.wrappedValue.year)).fontWeight(.bold)
                            }.width(50)
                            
                            TableColumn("Jan") { (yearBinding: YearBinding) in
                                TextField("", value: yearBinding.jan, format: .number).textFieldStyle(.plain)
                            }
                            TableColumn("Feb") { (yearBinding: YearBinding) in
                                TextField("", value: yearBinding.feb, format: .number).textFieldStyle(.plain)
                            }
                            TableColumn("Mar") { (yearBinding: YearBinding) in
                                TextField("", value: yearBinding.mar, format: .number).textFieldStyle(.plain)
                            }
                            TableColumn("Apr") { (yearBinding: YearBinding) in
                                TextField("", value: yearBinding.apr, format: .number).textFieldStyle(.plain)
                            }
                            TableColumn("May") { (yearBinding: YearBinding) in
                                TextField("", value: yearBinding.may, format: .number).textFieldStyle(.plain)
                            }
                            TableColumn("Jun") { (yearBinding: YearBinding) in
                                TextField("", value: yearBinding.jun, format: .number).textFieldStyle(.plain)
                            }
                        }
                        
                        Group {
                            TableColumn("Jul") { (yearBinding: YearBinding) in
                                TextField("", value: yearBinding.jul, format: .number).textFieldStyle(.plain)
                            }
                            TableColumn("Aug") { (yearBinding: YearBinding) in
                                TextField("", value: yearBinding.aug, format: .number).textFieldStyle(.plain)
                            }
                            TableColumn("Sep") { (yearBinding: YearBinding) in
                                TextField("", value: yearBinding.sep, format: .number).textFieldStyle(.plain)
                            }
                            TableColumn("Oct") { (yearBinding: YearBinding) in
                                TextField("", value: yearBinding.oct, format: .number).textFieldStyle(.plain)
                            }
                            TableColumn("Nov") { (yearBinding: YearBinding) in
                                TextField("", value: yearBinding.nov, format: .number).textFieldStyle(.plain)
                            }
                            TableColumn("Dec") { (yearBinding: YearBinding) in
                                TextField("", value: yearBinding.dec, format: .number).textFieldStyle(.plain)
                            }
                            
                            TableColumn("Total") { (yearBinding: YearBinding) in
                                Text(yearBinding.wrappedValue.total.formatted(.currency(code: "EUR")))
                                    .fontWeight(.bold)
                                    .foregroundColor(.green)
                            }.width(80)
                        }
                    }
                    .tableStyle(.inset)
                }
                .frame(height: 400)
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                
                // --- 4. CHARTS ---
                HStack(spacing: 24) {
                    MonthlyDividendChart(viewModel: viewModel, expandedChart: $chartToZoom)
                    YearlyDividendChart(viewModel: viewModel, expandedChart: $chartToZoom)
                }
                
            }.padding()
        }
        .sheet(isPresented: $showGoalSheet) { EditGoalView(viewModel: viewModel) }
        .sheet(item: $chartToZoom) { type in DividendFullScreenChartView(zoomType: type, viewModel: viewModel) }
    }
}

// MARK: - DIVIDEND CUSTOM UI COMPONENTS

struct DividendGoalProgressBar: View {
    var currentValue: Double
    var targetValue: Double
    var currentCapital: Double
    @Binding var privacyMode: Bool
    
    var progress: Double { guard targetValue > 0 else { return 0 }; return min(max(currentValue / targetValue, 0), 1) }
    var targetYield: Double { guard currentCapital > 0 else { return 0 }; return targetValue / currentCapital }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Annual Dividend Goal : \(targetValue.formatted(.currency(code: "EUR"))) (\(targetYield.formatted(.percent.precision(.fractionLength(2)))) Yield)").font(.headline)
                Spacer()
                Text("\(currentValue.formatted(.currency(code: "EUR"))) / \(targetValue.formatted(.currency(code: "EUR")))")
                    .font(.subheadline).fontWeight(.bold)
                    .foregroundColor(progress >= 1 ? .green : .primary)
                    .blur(radius: privacyMode ? 8 : 0)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.windowBackgroundColor)).frame(height: 14)
                    RoundedRectangle(cornerRadius: 8).fill(LinearGradient(gradient: Gradient(colors: [.blue, .purple]), startPoint: .leading, endPoint: .trailing)).frame(width: max(0, geometry.size.width * CGFloat(progress)), height: 14).animation(.spring(), value: progress)
                }
            }.frame(height: 14)
        }.padding().background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1).help("Double-click to edit your goal")
    }
}

struct MonthlyDividendChart: View {
    @ObservedObject var viewModel: PortfolioViewModel
    var isExpanded: Bool = false
    @Binding var expandedChart: DividendChartZoomType?
    
    var currentYear: Int { Calendar.current.component(.year, from: Date()) }
    var thisYearData: DividendYear? { viewModel.dividendYears.first { $0.year == currentYear } }
    
    var body: some View {
        VStack {
            HStack {
                if !isExpanded { Text("Dividends Received This Year").font(.headline).foregroundColor(.secondary) }
                Spacer()
                if !isExpanded { Button(action: { expandedChart = .monthly }) { Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary) }.buttonStyle(.plain) }
            }.padding(.bottom, 8)
            
            if let thisYear = thisYearData {
                let monthlyData = [
                    ("Jan", thisYear.jan), ("Feb", thisYear.feb), ("Mar", thisYear.mar), ("Apr", thisYear.apr),
                    ("May", thisYear.may), ("Jun", thisYear.jun), ("Jul", thisYear.jul), ("Aug", thisYear.aug),
                    ("Sep", thisYear.sep), ("Oct", thisYear.oct), ("Nov", thisYear.nov), ("Dec", thisYear.dec)
                ]
                Chart(monthlyData, id: \.0) { item in
                    BarMark(x: .value("Month", item.0), y: .value("Amount", item.1))
                        .foregroundStyle(Color.orange.opacity(0.8)).cornerRadius(4)
                        .annotation(position: .top) { if item.1 > 0 { Text(item.1.formatted(.currency(code: "EUR"))).font(.system(size: 9)).foregroundColor(.secondary) } }
                }
            } else { Spacer(); Text("No data").foregroundColor(.secondary); Spacer() }
            BlueChipWatermark()
        }.padding().frame(minHeight: 360, maxHeight: isExpanded ? .infinity : 360).background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

struct YearlyDividendChart: View {
    @ObservedObject var viewModel: PortfolioViewModel
    var isExpanded: Bool = false
    @Binding var expandedChart: DividendChartZoomType?
    
    var currentYear: Int { Calendar.current.component(.year, from: Date()) }
    
    var body: some View {
        VStack {
            HStack {
                if !isExpanded { Text("Annual Net Income").font(.headline).foregroundColor(.secondary) }
                Spacer()
                if !isExpanded { Button(action: { expandedChart = .yearly }) { Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary) }.buttonStyle(.plain) }
            }.padding(.bottom, 8)
            
            let activeYears = viewModel.dividendYears.filter { $0.total > 0 || $0.year == currentYear }
            if activeYears.isEmpty { Spacer(); Text("No data").foregroundColor(.secondary); Spacer() } else {
                Chart(activeYears) { yearData in
                    BarMark(x: .value("Year", String(yearData.year)), y: .value("Total", yearData.total))
                        .foregroundStyle(Color.green.opacity(0.8)).cornerRadius(4)
                        .annotation(position: .top) { if yearData.total > 0 { Text(yearData.total.formatted(.currency(code: "EUR"))).font(.system(size: 9)).foregroundColor(.secondary) } }
                }
            }
            BlueChipWatermark()
        }.padding().frame(minHeight: 360, maxHeight: isExpanded ? .infinity : 360).background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

struct DividendFullScreenChartView: View {
    @Environment(\.dismiss) var dismiss
    let zoomType: DividendChartZoomType
    @ObservedObject var viewModel: PortfolioViewModel
    
    var body: some View {
        VStack(spacing: 20) {
            HStack { Text(titleForZoom).font(.title).fontWeight(.bold); Spacer(); Button(action: { dismiss() }) { Image(systemName: "xmark.circle.fill").font(.title).foregroundColor(.secondary) }.buttonStyle(.plain) }
            
            if zoomType == .monthly {
                MonthlyDividendChart(viewModel: viewModel, isExpanded: true, expandedChart: .constant(nil))
            } else {
                YearlyDividendChart(viewModel: viewModel, isExpanded: true, expandedChart: .constant(nil))
            }
        }.padding(30).frame(minWidth: 900, minHeight: 700)
    }
    
    var titleForZoom: String { zoomType == .monthly ? "Dividends Received This Year" : "Annual Net Income" }
}
