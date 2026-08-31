import SwiftUI
import Charts

// MARK: - SPECIFIC ZOOM ENUM FOR PROJECTION
enum ProjectionChartZoomType: String, Identifiable {
    case capitalProjection, dividendProjection
    case cumulativeDividends, projectedYOC
    var id: String { self.rawValue }
}

// Struct de données pour chaque année projetée
struct ProjectionYearData: Identifiable {
    let id = UUID()
    let yearIndex: Int        // Année 0, 1, 2...
    let calendarYear: Int     // 2026, 2027...
    let portfolioValue: Double
    let capitalGain: Double
    let annualDividend: Double
    let monthlyDividend: Double
    let cumulativeDividends: Double
    let projectedYOC: Double
}

struct ProjectionView: View {
    @ObservedObject var viewModel: PortfolioViewModel
    @Binding var privacyMode: Bool
    
    // Paramètres réglables
    @State private var timeHorizonYears: Double = 30
    @State private var customCAGR: Double? = nil
    @State private var customDivGrowth: Double? = nil
    @State private var chartToZoom: ProjectionChartZoomType? = nil
    
    // MARK: - CALCULS DES TAUX
    
    var currentYear: Int { Calendar.current.component(.year, from: Date()) }
    
    var defaultCAGR: Double {
        let activeYearsCount = max(1, currentYear - viewModel.dividendStartYear + 1)
        let allTimeReturnPercent = viewModel.totalROIPercent
        let calculated = pow(1.0 + max(allTimeReturnPercent, -0.999), 1.0 / Double(activeYearsCount)) - 1.0
        return calculated.isNaN || calculated.isInfinite ? 0.08 : calculated
    }
    
    var effectiveCAGR: Double {
        (customCAGR ?? (defaultCAGR * 100)) / 100.0
    }
    
    var defaultWeightedDivGrowth: Double {
        var totalAnnualDiv: Double = 0
        for pos in viewModel.positions {
            totalAnnualDiv += pos.totalDividendEUR
        }
        
        guard totalAnnualDiv > 0 else { return 0.06 }
        
        var weightedSum: Double = 0
        for pos in viewModel.positions {
            let posGrowth = Mirror(reflecting: pos).children.first(where: { $0.label == "dividendGrowth5Y" })?.value as? Double ?? 5.0
            weightedSum += (pos.totalDividendEUR * (posGrowth / 100.0))
        }
        
        return weightedSum / totalAnnualDiv
    }
    
    var effectiveDivGrowth: Double {
        (customDivGrowth ?? (defaultWeightedDivGrowth * 100)) / 100.0
    }
    
    var projectionSeries: [ProjectionYearData] {
        let startCapital = viewModel.currentTotalCapital
        
        var startDividend: Double = 0
        for pos in viewModel.positions {
            startDividend += pos.totalDividendEUR
        }
        
        let startInvested = viewModel.manuallyInvested > 0 ? viewModel.manuallyInvested : viewModel.positionsInvestedSum
        let safeInvested = startInvested > 0 ? startInvested : 1.0
        
        var result: [ProjectionYearData] = []
        var currentCap = startCapital
        var currentDiv = startDividend
        var cumulDiv = 0.0
        
        for i in 0...Int(timeHorizonYears) {
            let yearNum = currentYear + i
            let gain = currentCap - startInvested
            cumulDiv += currentDiv
            
            result.append(ProjectionYearData(
                yearIndex: i,
                calendarYear: yearNum,
                portfolioValue: currentCap,
                capitalGain: gain,
                annualDividend: currentDiv,
                monthlyDividend: currentDiv / 12.0,
                cumulativeDividends: cumulDiv,
                projectedYOC: (currentDiv / safeInvested) * 100.0
            ))
            
            currentCap *= (1.0 + effectiveCAGR)
            currentDiv *= (1.0 + effectiveDivGrowth)
        }
        return result
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 24) {
                
                ProjectionDashboardSection(
                    viewModel: viewModel,
                    privacyMode: $privacyMode,
                    series: projectionSeries,
                    effectiveCAGR: effectiveCAGR,
                    effectiveDivGrowth: effectiveDivGrowth,
                    horizon: Int(timeHorizonYears)
                )
                
                ProjectionControlsSection(
                    timeHorizonYears: $timeHorizonYears,
                    customCAGR: $customCAGR,
                    customDivGrowth: $customDivGrowth,
                    defaultCAGR: defaultCAGR * 100,
                    defaultWeightedDivGrowth: defaultWeightedDivGrowth * 100
                )
                
                ProjectionChartsSection(
                    series: projectionSeries,
                    chartToZoom: $chartToZoom,
                    privacyMode: $privacyMode
                )
                
                ProjectionAdvancedChartsSection(
                    series: projectionSeries,
                    chartToZoom: $chartToZoom,
                    privacyMode: $privacyMode
                )
                
                ProjectionTableSection(
                    series: projectionSeries,
                    privacyMode: $privacyMode
                )
            }
            .padding()
        }
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(item: $chartToZoom) { type in
            ProjectionFullScreenChartView(
                zoomType: type,
                series: projectionSeries,
                privacyMode: $privacyMode
            )
        }
        .onAppear {
            if customCAGR == nil { customCAGR = defaultCAGR * 100 }
            if customDivGrowth == nil { customDivGrowth = defaultWeightedDivGrowth * 100 }
        }
    }
}

// =========================================================================
// MARK: - DASHBOARD SYNTHÈSE
// =========================================================================

struct ProjectionDashboardSection: View {
    @ObservedObject var viewModel: PortfolioViewModel
    @Binding var privacyMode: Bool
    let series: [ProjectionYearData]
    let effectiveCAGR: Double
    let effectiveDivGrowth: Double
    let horizon: Int
    
    var startCap: Double { series.first?.portfolioValue ?? 0 }
    var endCap: Double { series.last?.portfolioValue ?? 0 }
    var startDiv: Double { series.first?.annualDividend ?? 0 }
    var endDiv: Double { series.last?.annualDividend ?? 0 }

    var body: some View {
        let startCapStr = startCap.formatted(.currency(code: "EUR").precision(.fractionLength(2)))
        let endCapStr = endCap.formatted(.currency(code: "EUR").precision(.fractionLength(0)))
        let cagrStr = effectiveCAGR.formatted(.percent.precision(.fractionLength(2)))
        let gainStr = (endCap - startCap).formatted(.currency(code: "EUR").precision(.fractionLength(0)).sign(strategy: .always()))
        
        let startDivStr = startDiv.formatted(.currency(code: "EUR").precision(.fractionLength(2)))
        let endDivStr = endDiv.formatted(.currency(code: "EUR").precision(.fractionLength(0)))
        let divGrowthStr = effectiveDivGrowth.formatted(.percent.precision(.fractionLength(2)))
        let monthlyDivStr = (endDiv / 12.0).formatted(.currency(code: "EUR").precision(.fractionLength(0)))

        VStack(spacing: 16) {
            HStack(spacing: 16) {
                DashboardCard(title: "Current Portfolio Value", value: startCapStr, titleIcon: nil, privacyMode: $privacyMode)
                DashboardCard(title: "Projected Value (\(horizon)Y)", value: endCapStr, titleIcon: nil, privacyMode: $privacyMode)
                DashboardCard(title: "Portfolio CAGR Used", value: cagrStr, titleIcon: nil, privacyMode: $privacyMode)
                DashboardCard(title: "Projected Capital Gain", value: gainStr, titleIcon: nil, privacyMode: $privacyMode)
            }
            HStack(spacing: 16) {
                DashboardCard(title: "Current Annual Div.", value: startDivStr, titleIcon: nil, privacyMode: $privacyMode)
                DashboardCard(title: "Projected Div. (\(horizon)Y)", value: endDivStr, titleIcon: nil, privacyMode: $privacyMode)
                DashboardCard(title: "Weighted 5Y Div Growth", value: divGrowthStr, titleIcon: nil, privacyMode: $privacyMode)
                DashboardCard(title: "Projected Monthly Div.", value: monthlyDivStr, titleIcon: nil, privacyMode: $privacyMode)
            }
        }
    }
}

// =========================================================================
// MARK: - CONTRÔLES & SLIDER HORIZON
// =========================================================================

struct ProjectionControlsSection: View {
    @Binding var timeHorizonYears: Double
    @Binding var customCAGR: Double?
    @Binding var customDivGrowth: Double?
    let defaultCAGR: Double
    let defaultWeightedDivGrowth: Double
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Projection Parameters & Assumptions").font(.headline).foregroundColor(.secondary)
            
            HStack(spacing: 32) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Time Horizon:").fontWeight(.semibold)
                        Text("\(Int(timeHorizonYears)) Years").font(.title3).fontWeight(.bold).foregroundColor(.blue)
                        Spacer()
                    }
                    Slider(value: $timeHorizonYears, in: 5...50, step: 1).tint(.blue)
                }
                .frame(maxWidth: .infinity)
                
                Divider().frame(height: 50)
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Annual Capital CAGR (%):").font(.subheadline).foregroundColor(.secondary)
                        Spacer()
                        Button("Reset") { customCAGR = defaultCAGR }.font(.caption).buttonStyle(.plain).foregroundColor(.blue)
                    }
                    HStack {
                        TextField("CAGR", value: Binding(get: { customCAGR ?? defaultCAGR }, set: { customCAGR = $0 }), format: .number)
                            .textFieldStyle(.roundedBorder).frame(width: 80)
                        Text("% / year").font(.caption).foregroundColor(.secondary)
                    }
                }
                .frame(width: 200)
                
                Divider().frame(height: 50)
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Dividend Growth 5Y (%):").font(.subheadline).foregroundColor(.secondary)
                        Spacer()
                        Button("Reset") { customDivGrowth = defaultWeightedDivGrowth }.font(.caption).buttonStyle(.plain).foregroundColor(.blue)
                    }
                    HStack {
                        TextField("Div Growth", value: Binding(get: { customDivGrowth ?? defaultWeightedDivGrowth }, set: { customDivGrowth = $0 }), format: .number)
                            .textFieldStyle(.roundedBorder).frame(width: 80)
                        Text("% / year").font(.caption).foregroundColor(.secondary)
                    }
                }
                .frame(width: 220)
            }
        }
        .padding().background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// =========================================================================
// MARK: - SECTION DES 4 GRAPHIQUES (2x2 GRID)
// =========================================================================

struct ProjectionChartsSection: View {
    let series: [ProjectionYearData]
    @Binding var chartToZoom: ProjectionChartZoomType?
    @Binding var privacyMode: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Long-Term Projections").font(.title2).fontWeight(.bold).foregroundColor(.secondary)
            HStack(spacing: 24) {
                CapitalProjectionChart(series: series, privacyMode: $privacyMode, expandedChart: $chartToZoom)
                DividendProjectionChart(series: series, privacyMode: $privacyMode, expandedChart: $chartToZoom)
            }
        }
    }
}

struct ProjectionAdvancedChartsSection: View {
    let series: [ProjectionYearData]
    @Binding var chartToZoom: ProjectionChartZoomType?
    @Binding var privacyMode: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Advanced Compounding Analytics").font(.title2).fontWeight(.bold).foregroundColor(.secondary)
            HStack(spacing: 24) {
                CumulativeDividendsChart(series: series, privacyMode: $privacyMode, expandedChart: $chartToZoom)
                ProjectedYOCChart(series: series, privacyMode: $privacyMode, expandedChart: $chartToZoom)
            }
        }
    }
}

// GRAPHE 1 : Capital Growth Projection
struct CapitalProjectionChart: View {
    let series: [ProjectionYearData]
    @Binding var privacyMode: Bool
    var isExpanded: Bool = false
    @Binding var expandedChart: ProjectionChartZoomType?
    
    // CHANGEMENT : Index numérique pour le survol
    @State private var hoveredYearIndex: Int? = nil

    var body: some View {
        let isPrivate = privacyMode
        
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if !isExpanded { Text("Portfolio Capital Growth").font(.headline).foregroundColor(.secondary) }
                Spacer()
                if !isExpanded {
                    Button(action: { expandedChart = .capitalProjection }) { Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary) }.buttonStyle(.plain)
                }
            }.padding(.bottom, 4)
            
            Chart(series) { item in
                // CHANGEMENT : Utilisation de yearIndex au lieu de calendarYear
                AreaMark(
                    x: .value("Year Index", item.yearIndex),
                    y: .value("Value", item.portfolioValue)
                )
                .foregroundStyle(LinearGradient(colors: [.blue.opacity(0.4), .clear], startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.monotone)
                
                LineMark(
                    x: .value("Year Index", item.yearIndex),
                    y: .value("Value", item.portfolioValue)
                )
                .foregroundStyle(Color.blue)
                .lineStyle(StrokeStyle(lineWidth: 3))
                .interpolationMethod(.monotone)
                
                if let hIdx = hoveredYearIndex, item.yearIndex == hIdx {
                    RuleMark(x: .value("Year Index", hIdx))
                        .foregroundStyle(.secondary.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                        .annotation(position: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                // AFFICHAGE DES DEUX : Index + Année
                                Text("Year \(item.yearIndex) (\(item.calendarYear))").font(.caption.bold())
                                Divider()
                                Text("Portfolio: \(item.portfolioValue.formatted(.currency(code: "EUR").precision(.fractionLength(0))))")
                                    .font(.caption2.bold()).foregroundColor(.blue)
                                    .blur(radius: isPrivate ? 6 : 0)
                                Text("Gain: \(item.capitalGain.formatted(.currency(code: "EUR").precision(.fractionLength(0)).sign(strategy: .always())))")
                                    .font(.caption2).foregroundColor(.green)
                                    .blur(radius: isPrivate ? 6 : 0)
                            }
                            .padding(8).background(Color(NSColor.windowBackgroundColor).opacity(0.95)).cornerRadius(8).shadow(radius: 4)
                        }
                }
            }
            .chartLegend(.hidden)
            .chartXSelection(value: $hoveredYearIndex) // Selection via l'index Int
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine(); AxisTick()
                    if let val = value.as(Double.self) { AxisValueLabel(val.formatted(.currency(code: "EUR").notation(.compactName))) }
                }
            }
            .chartXAxis {
                // SwiftUI gère automatiquement les pas (0, 10, 20...)
                AxisMarks(values: .automatic) { value in
                    if let intVal = value.as(Int.self) { AxisValueLabel { Text("\(intVal)").font(.caption) } }
                }
            }
            
            HStack {
                HStack(spacing: 4) { RoundedRectangle(cornerRadius: 2).fill(Color.blue).frame(width: 12, height: 12); Text("Projected Capital (€)").font(.caption).foregroundColor(.secondary) }
                Spacer()
                BlueChipWatermark()
            }
        }
        .padding().frame(minHeight: isExpanded ? 500 : 360, maxHeight: isExpanded ? .infinity : 360).background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// GRAPHE 2 : Dividend Growth Projection
struct DividendProjectionChart: View {
    let series: [ProjectionYearData]
    @Binding var privacyMode: Bool
    var isExpanded: Bool = false
    @Binding var expandedChart: ProjectionChartZoomType?
    
    @State private var hoveredYearIndex: Int? = nil

    var body: some View {
        let isPrivate = privacyMode
        
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if !isExpanded { Text("Annual Dividend Income Growth").font(.headline).foregroundColor(.secondary) }
                Spacer()
                if !isExpanded {
                    Button(action: { expandedChart = .dividendProjection }) { Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary) }.buttonStyle(.plain)
                }
            }.padding(.bottom, 4)
            
            Chart(series) { item in
                BarMark(
                    x: .value("Year Index", item.yearIndex),
                    y: .value("Dividends", item.annualDividend)
                )
                .foregroundStyle(Color.green.opacity(0.7))
                .cornerRadius(4)
                
                LineMark(
                    x: .value("Year Index", item.yearIndex),
                    y: .value("Dividends", item.annualDividend)
                )
                .foregroundStyle(Color.mint)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.monotone)
                
                if let hIdx = hoveredYearIndex, item.yearIndex == hIdx {
                    RuleMark(x: .value("Year Index", hIdx))
                        .foregroundStyle(.secondary.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                        .annotation(position: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Year \(item.yearIndex) (\(item.calendarYear))").font(.caption.bold())
                                Divider()
                                Text("Annual Div.: \(item.annualDividend.formatted(.currency(code: "EUR").precision(.fractionLength(0))))")
                                    .font(.caption2.bold()).foregroundColor(.green)
                                    .blur(radius: isPrivate ? 6 : 0)
                                Text("Monthly Div.: \(item.monthlyDividend.formatted(.currency(code: "EUR").precision(.fractionLength(0))))/mo")
                                    .font(.caption2).foregroundColor(.mint)
                                    .blur(radius: isPrivate ? 6 : 0)
                            }
                            .padding(8).background(Color(NSColor.windowBackgroundColor).opacity(0.95)).cornerRadius(8).shadow(radius: 4)
                        }
                }
            }
            .chartLegend(.hidden)
            .chartXSelection(value: $hoveredYearIndex)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine(); AxisTick()
                    if let val = value.as(Double.self) { AxisValueLabel(val.formatted(.currency(code: "EUR").notation(.compactName))) }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic) { value in
                    if let intVal = value.as(Int.self) { AxisValueLabel { Text("\(intVal)").font(.caption) } }
                }
            }
            
            HStack {
                HStack(spacing: 4) { RoundedRectangle(cornerRadius: 2).fill(Color.green.opacity(0.7)).frame(width: 12, height: 12); Text("Gross Annual Dividends (€)").font(.caption).foregroundColor(.secondary) }
                Spacer()
                BlueChipWatermark()
            }
        }
        .padding().frame(minHeight: isExpanded ? 500 : 360, maxHeight: isExpanded ? .infinity : 360).background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// GRAPHE 3 : Cumulative Dividends Area
struct CumulativeDividendsChart: View {
    let series: [ProjectionYearData]
    @Binding var privacyMode: Bool
    var isExpanded: Bool = false
    @Binding var expandedChart: ProjectionChartZoomType?
    
    @State private var hoveredYearIndex: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if !isExpanded { Text("Total Cumulative Dividends Collected").font(.headline).foregroundColor(.secondary) }
                Spacer()
                if !isExpanded { Button(action: { expandedChart = .cumulativeDividends }) { Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary) }.buttonStyle(.plain) }
            }.padding(.bottom, 4)
            
            Chart(series) { item in
                AreaMark(
                    x: .value("Year Index", item.yearIndex),
                    y: .value("Cumul", item.cumulativeDividends)
                )
                .foregroundStyle(LinearGradient(colors: [.purple.opacity(0.6), .purple.opacity(0.1)], startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.monotone)
                
                LineMark(
                    x: .value("Year Index", item.yearIndex),
                    y: .value("Cumul", item.cumulativeDividends)
                )
                .foregroundStyle(Color.purple)
                .lineStyle(StrokeStyle(lineWidth: 3))
                .interpolationMethod(.monotone)
                
                if let hIdx = hoveredYearIndex, item.yearIndex == hIdx {
                    RuleMark(x: .value("Year Index", hIdx))
                        .foregroundStyle(.secondary.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                        .annotation(position: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Year \(item.yearIndex) (\(item.calendarYear))").font(.caption.bold())
                                Divider()
                                Text("Total Collected:")
                                    .font(.caption2).foregroundColor(.secondary)
                                Text(item.cumulativeDividends.formatted(.currency(code: "EUR").precision(.fractionLength(0))))
                                    .font(.caption.bold()).foregroundColor(.purple)
                                    .blur(radius: privacyMode ? 6 : 0)
                            }
                            .padding(8).background(Color(NSColor.windowBackgroundColor).opacity(0.95)).cornerRadius(8).shadow(radius: 4)
                        }
                }
            }
            .chartLegend(.hidden)
            .chartXSelection(value: $hoveredYearIndex)
            .chartYAxis { AxisMarks(position: .leading) { value in AxisGridLine(); AxisTick(); if let val = value.as(Double.self) { AxisValueLabel(val.formatted(.currency(code: "EUR").notation(.compactName))) } } }
            .chartXAxis { AxisMarks(values: .automatic) { value in if let intVal = value.as(Int.self) { AxisValueLabel { Text("\(intVal)").font(.caption) } } } }
            
            HStack { Text("The snowball effect: sum of all cash generated").font(.caption2).foregroundColor(.secondary); Spacer(); BlueChipWatermark() }
        }
        .padding().frame(minHeight: isExpanded ? 500 : 360, maxHeight: isExpanded ? .infinity : 360).background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// GRAPHE 4 : Projected YOC Line Chart
struct ProjectedYOCChart: View {
    let series: [ProjectionYearData]
    @Binding var privacyMode: Bool
    var isExpanded: Bool = false
    @Binding var expandedChart: ProjectionChartZoomType?
    
    @State private var hoveredYearIndex: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if !isExpanded { Text("Projected Yield On Cost (YOC)").font(.headline).foregroundColor(.secondary) }
                Spacer()
                if !isExpanded { Button(action: { expandedChart = .projectedYOC }) { Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary) }.buttonStyle(.plain) }
            }.padding(.bottom, 4)
            
            Chart {
                RuleMark(y: .value("100%", 100.0))
                    .foregroundStyle(Color.gray.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5]))
                    .annotation(position: .top, alignment: .trailing) { Text("100% YOC (Portfolio pays for itself)").font(.caption2).foregroundColor(.secondary) }
                
                ForEach(series) { item in
                    LineMark(
                        x: .value("Year Index", item.yearIndex),
                        y: .value("YOC", item.projectedYOC)
                    )
                    .foregroundStyle(Color.orange)
                    .lineStyle(StrokeStyle(lineWidth: 3))
                    .interpolationMethod(.monotone)
                    
                    if let hIdx = hoveredYearIndex, item.yearIndex == hIdx {
                        RuleMark(x: .value("Year Index", hIdx))
                            .foregroundStyle(.secondary.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                            .annotation(position: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Year \(item.yearIndex) (\(item.calendarYear))").font(.caption.bold())
                                    Divider()
                                    Text("Projected YOC:")
                                        .font(.caption2).foregroundColor(.secondary)
                                    Text("\(item.projectedYOC.formatted(.number.precision(.fractionLength(1))))%")
                                        .font(.caption.bold()).foregroundColor(.orange)
                                        .blur(radius: privacyMode ? 6 : 0)
                                }
                                .padding(8).background(Color(NSColor.windowBackgroundColor).opacity(0.95)).cornerRadius(8).shadow(radius: 4)
                            }
                    }
                }
            }
            .chartLegend(.hidden)
            .chartXSelection(value: $hoveredYearIndex)
            .chartYAxis { AxisMarks(position: .leading) { value in AxisGridLine(); AxisTick(); if let val = value.as(Double.self) { AxisValueLabel("\(val.formatted(.number.precision(.fractionLength(0))))%") } } }
            .chartXAxis { AxisMarks(values: .automatic) { value in if let intVal = value.as(Int.self) { AxisValueLabel { Text("\(intVal)").font(.caption) } } } }
            
            HStack { Text("Dividends returned per year relative to your initial invested capital").font(.caption2).foregroundColor(.secondary); Spacer(); BlueChipWatermark() }
        }
        .padding().frame(minHeight: isExpanded ? 500 : 360, maxHeight: isExpanded ? .infinity : 360).background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// =========================================================================
// MARK: - TABLEAU DE DÉTAIL ANNEE PAR ANNEE
// =========================================================================

struct ProjectionTableSection: View {
    let series: [ProjectionYearData]
    @Binding var privacyMode: Bool
    
    var body: some View {
        let isPrivate = privacyMode
        
        VStack(alignment: .leading, spacing: 8) {
            Text("Year-by-Year Projection Schedule").font(.title2).fontWeight(.bold).foregroundColor(.secondary).padding(.bottom, 4)
            
            VStack(spacing: 0) {
                // Header
                HStack(spacing: 8) {
                    Text("Year #").fontWeight(.bold).frame(width: 60, alignment: .leading)
                    Text("Calendar").fontWeight(.bold).frame(width: 80, alignment: .leading)
                    Text("Portfolio Value (€)").fontWeight(.bold).frame(maxWidth: .infinity, alignment: .trailing)
                    Text("Cumulative Gain (€)").fontWeight(.bold).frame(maxWidth: .infinity, alignment: .trailing)
                    Text("Annual Dividend (€)").fontWeight(.bold).frame(maxWidth: .infinity, alignment: .trailing)
                    Text("Monthly Equivalent (€)").fontWeight(.bold).frame(maxWidth: .infinity, alignment: .trailing)
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(NSColor.windowBackgroundColor))
                
                Divider()
                
                // Rows
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(series) { item in
                            HStack(spacing: 8) {
                                Text("Yr \(item.yearIndex)").fontWeight(.semibold).frame(width: 60, alignment: .leading)
                                Text(String(item.calendarYear)).foregroundColor(.secondary).frame(width: 80, alignment: .leading)
                                
                                Text(item.portfolioValue.formatted(.currency(code: "EUR").precision(.fractionLength(2))))
                                    .fontWeight(.bold)
                                    .blur(radius: isPrivate ? 6 : 0)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                                
                                Text(item.capitalGain.formatted(.currency(code: "EUR").precision(.fractionLength(2)).sign(strategy: .always())))
                                    .foregroundColor(item.capitalGain >= 0 ? .green : .red)
                                    .blur(radius: isPrivate ? 6 : 0)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                                
                                Text(item.annualDividend.formatted(.currency(code: "EUR").precision(.fractionLength(2))))
                                    .fontWeight(.semibold)
                                    .foregroundColor(.green)
                                    .blur(radius: isPrivate ? 6 : 0)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                                
                                Text(item.monthlyDividend.formatted(.currency(code: "EUR").precision(.fractionLength(2))))
                                    .foregroundColor(.mint)
                                    .blur(radius: isPrivate ? 6 : 0)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            
                            Divider()
                        }
                    }
                }
            }
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))
        }
        .frame(height: 420)
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// =========================================================================
// MARK: - FULL SCREEN ZOOM MODAL
// =========================================================================

struct ProjectionFullScreenChartView: View {
    @Environment(\.dismiss) var dismiss
    let zoomType: ProjectionChartZoomType
    let series: [ProjectionYearData]
    @Binding var privacyMode: Bool

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Projection Analysis Detail").font(.title).fontWeight(.bold)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill").font(.title).foregroundColor(.secondary)
                }.buttonStyle(.plain)
            }
            
            switch zoomType {
            case .capitalProjection:
                CapitalProjectionChart(series: series, privacyMode: $privacyMode, isExpanded: true, expandedChart: .constant(nil))
            case .dividendProjection:
                DividendProjectionChart(series: series, privacyMode: $privacyMode, isExpanded: true, expandedChart: .constant(nil))
            case .cumulativeDividends:
                CumulativeDividendsChart(series: series, privacyMode: $privacyMode, isExpanded: true, expandedChart: .constant(nil))
            case .projectedYOC:
                ProjectedYOCChart(series: series, privacyMode: $privacyMode, isExpanded: true, expandedChart: .constant(nil))
            }
        }
        .padding(30)
        .frame(minWidth: 900, minHeight: 700)
    }
}
