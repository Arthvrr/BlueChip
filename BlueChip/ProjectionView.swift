import SwiftUI
import Charts

// MARK: - SPECIFIC ZOOM ENUM FOR PROJECTION
enum ProjectionChartZoomType: String, Identifiable {
    case capitalProjection, dividendProjection
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
    
    // 1. CAGR moyen du portefeuille (depuis la page Growth / Historique)
    var defaultCAGR: Double {
        let activeYears = viewModel.growthYears.filter { $0.year <= currentYear }
        let activeYearsCount = max(1, activeYears.count)
        let totalInvested = viewModel.manuallyInvested > 0 ? viewModel.manuallyInvested : viewModel.positionsInvestedSum
        let totalReturnPct = totalInvested > 0 ? ((viewModel.currentTotalCapital - totalInvested) / totalInvested) : 0
        
        let calculated = pow(1.0 + totalReturnPct, 1.0 / Double(activeYearsCount)) - 1.0
        return calculated.isNaN || calculated.isInfinite ? 0.08 : calculated
    }
    
    var effectiveCAGR: Double {
        (customCAGR ?? (defaultCAGR * 100)) / 100.0
    }
    
    // 2. Moyenne pondérée du taux de croissance du dividende sur 5 ans (par action)
    var defaultWeightedDivGrowth: Double {
        // CORRECTION DU BUG XCODE: Utilisation d'une boucle for explicite
        var totalAnnualDiv: Double = 0
        for pos in viewModel.positions {
            totalAnnualDiv += pos.totalDividendEUR
        }
        
        guard totalAnnualDiv > 0 else { return 0.06 } // 6% par défaut si pas de dividende
        
        // CORRECTION DU BUG XCODE: Utilisation d'une boucle for explicite
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
    
    // 3. Génération de la série de données sur N années
    var projectionSeries: [ProjectionYearData] {
        let startCapital = viewModel.currentTotalCapital
        
        // CORRECTION DU BUG XCODE: Utilisation d'une boucle for explicite
        var startDividend: Double = 0
        for pos in viewModel.positions {
            startDividend += pos.totalDividendEUR
        }
        
        let startInvested = viewModel.manuallyInvested > 0 ? viewModel.manuallyInvested : viewModel.positionsInvestedSum
        
        var result: [ProjectionYearData] = []
        var currentCap = startCapital
        var currentDiv = startDividend
        
        for i in 0...Int(timeHorizonYears) {
            let yearNum = currentYear + i
            let gain = currentCap - startInvested
            
            result.append(ProjectionYearData(
                yearIndex: i,
                calendarYear: yearNum,
                portfolioValue: currentCap,
                capitalGain: gain,
                annualDividend: currentDiv,
                monthlyDividend: currentDiv / 12.0
            ))
            
            // Croissance pour l'année suivante
            currentCap *= (1.0 + effectiveCAGR)
            currentDiv *= (1.0 + effectiveDivGrowth)
        }
        return result
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 24) {
                
                // 1. DASHBOARD DE SYNTHÈSE PROJECTION
                ProjectionDashboardSection(
                    viewModel: viewModel,
                    privacyMode: $privacyMode,
                    series: projectionSeries,
                    effectiveCAGR: effectiveCAGR,
                    effectiveDivGrowth: effectiveDivGrowth,
                    horizon: Int(timeHorizonYears)
                )
                
                // 2. PANNEAU DE CONTRÔLE (Slider Horizon & Ajustement des taux)
                ProjectionControlsSection(
                    timeHorizonYears: $timeHorizonYears,
                    customCAGR: $customCAGR,
                    customDivGrowth: $customDivGrowth,
                    defaultCAGR: defaultCAGR * 100,
                    defaultWeightedDivGrowth: defaultWeightedDivGrowth * 100
                )
                
                // 3. LES 2 GRAPHIQUES CÔTE À CÔTE
                ProjectionChartsSection(
                    series: projectionSeries,
                    chartToZoom: $chartToZoom,
                    privacyMode: $privacyMode
                )
                
                // 4. TABLEAU DE DÉTAIL ANNÉE PAR ANNÉE
                ProjectionTableSection(
                    series: projectionSeries,
                    privacyMode: $privacyMode
                )
            }
            .padding()
        }
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
        // Extraction des textes pour soulager le compilateur SwiftUI
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
                DashboardCard(title: "Portfolio CAGR Used", value: cagrStr, titleIcon: nil, privacyMode: .constant(false))
                DashboardCard(title: "Projected Capital Gain", value: gainStr, titleIcon: nil, privacyMode: $privacyMode)
            }
            HStack(spacing: 16) {
                DashboardCard(title: "Current Annual Div.", value: startDivStr, titleIcon: nil, privacyMode: $privacyMode)
                DashboardCard(title: "Projected Div. (\(horizon)Y)", value: endDivStr, titleIcon: nil, privacyMode: $privacyMode)
                DashboardCard(title: "Weighted 5Y Div Growth", value: divGrowthStr, titleIcon: nil, privacyMode: .constant(false))
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
                // Jauge d'horizon temporel
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Time Horizon:").fontWeight(.semibold)
                        Text("\(Int(timeHorizonYears)) Years").font(.title3).fontWeight(.bold).foregroundColor(.blue)
                        Spacer()
                    }
                    Slider(value: $timeHorizonYears, in: 5...50, step: 1)
                        .tint(.blue)
                }
                .frame(maxWidth: .infinity)
                
                Divider().frame(height: 50)
                
                // Réglage CAGR Capital
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Annual Capital CAGR (%):").font(.subheadline).foregroundColor(.secondary)
                        Spacer()
                        Button("Reset") { customCAGR = defaultCAGR }.font(.caption).buttonStyle(.plain).foregroundColor(.blue)
                    }
                    HStack {
                        TextField("CAGR", value: Binding(get: { customCAGR ?? defaultCAGR }, set: { customCAGR = $0 }), format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        Text("% / year").font(.caption).foregroundColor(.secondary)
                    }
                }
                .frame(width: 200)
                
                Divider().frame(height: 50)
                
                // Réglage Croissance Dividende
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Dividend Growth 5Y (%):").font(.subheadline).foregroundColor(.secondary)
                        Spacer()
                        Button("Reset") { customDivGrowth = defaultWeightedDivGrowth }.font(.caption).buttonStyle(.plain).foregroundColor(.blue)
                    }
                    HStack {
                        TextField("Div Growth", value: Binding(get: { customDivGrowth ?? defaultWeightedDivGrowth }, set: { customDivGrowth = $0 }), format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        Text("% / year").font(.caption).foregroundColor(.secondary)
                    }
                }
                .frame(width: 220)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// =========================================================================
// MARK: - SECTION LES 2 GRAPHIQUES
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

// GRAPHE 1 : Capital Growth Projection
struct CapitalProjectionChart: View {
    let series: [ProjectionYearData]
    @Binding var privacyMode: Bool
    var isExpanded: Bool = false
    @Binding var expandedChart: ProjectionChartZoomType?
    @State private var hoveredYear: Int? = nil

    var body: some View {
        let isPrivate = privacyMode
        
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if !isExpanded { Text("Portfolio Capital Growth").font(.headline).foregroundColor(.secondary) }
                Spacer()
                if !isExpanded {
                    Button(action: { expandedChart = .capitalProjection }) {
                        Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary)
                    }.buttonStyle(.plain)
                }
            }.padding(.bottom, 4)
            
            Chart(series) { item in
                AreaMark(
                    x: .value("Year", String(item.calendarYear)),
                    y: .value("Value", item.portfolioValue)
                )
                .foregroundStyle(LinearGradient(colors: [.blue.opacity(0.4), .clear], startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.monotone)
                
                LineMark(
                    x: .value("Year", String(item.calendarYear)),
                    y: .value("Value", item.portfolioValue)
                )
                .foregroundStyle(Color.blue)
                .lineStyle(StrokeStyle(lineWidth: 3))
                .interpolationMethod(.monotone)
                
                if let hYear = hoveredYear, String(item.calendarYear) == String(hYear) {
                    RuleMark(x: .value("Year", String(hYear)))
                        .foregroundStyle(.secondary.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                        .annotation(position: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(item.calendarYear) (Year \(item.yearIndex))").font(.caption.bold())
                                Divider()
                                Text("Portfolio: \(item.portfolioValue.formatted(.currency(code: "EUR").precision(.fractionLength(0))))")
                                    .font(.caption2.bold()).foregroundColor(.blue)
                                    .blur(radius: isPrivate ? 6 : 0)
                                Text("Gain: \(item.capitalGain.formatted(.currency(code: "EUR").precision(.fractionLength(0)).sign(strategy: .always())))")
                                    .font(.caption2).foregroundColor(.green)
                                    .blur(radius: isPrivate ? 6 : 0)
                            }
                            .padding(8)
                            .background(Color(NSColor.windowBackgroundColor).opacity(0.95))
                            .cornerRadius(8)
                            .shadow(radius: 4)
                        }
                }
            }
            .chartLegend(.hidden)
            .chartXSelection(value: $hoveredYear)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine(); AxisTick()
                    if let val = value.as(Double.self) {
                        AxisValueLabel(val.formatted(.currency(code: "EUR").notation(.compactName)))
                    }
                }
            }
            
            HStack {
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.blue).frame(width: 12, height: 12)
                    Text("Projected Capital (€)").font(.caption).foregroundColor(.secondary)
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

// GRAPHE 2 : Dividend Growth Projection
struct DividendProjectionChart: View {
    let series: [ProjectionYearData]
    @Binding var privacyMode: Bool
    var isExpanded: Bool = false
    @Binding var expandedChart: ProjectionChartZoomType?
    @State private var hoveredYear: Int? = nil

    var body: some View {
        let isPrivate = privacyMode
        
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if !isExpanded { Text("Annual Dividend Income Growth").font(.headline).foregroundColor(.secondary) }
                Spacer()
                if !isExpanded {
                    Button(action: { expandedChart = .dividendProjection }) {
                        Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary)
                    }.buttonStyle(.plain)
                }
            }.padding(.bottom, 4)
            
            Chart(series) { item in
                BarMark(
                    x: .value("Year", String(item.calendarYear)),
                    y: .value("Dividends", item.annualDividend)
                )
                .foregroundStyle(Color.green.opacity(0.7))
                .cornerRadius(4)
                
                LineMark(
                    x: .value("Year", String(item.calendarYear)),
                    y: .value("Dividends", item.annualDividend)
                )
                .foregroundStyle(Color.mint)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.monotone)
                
                if let hYear = hoveredYear, String(item.calendarYear) == String(hYear) {
                    RuleMark(x: .value("Year", String(hYear)))
                        .foregroundStyle(.secondary.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                        .annotation(position: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(item.calendarYear) (Year \(item.yearIndex))").font(.caption.bold())
                                Divider()
                                Text("Annual Div.: \(item.annualDividend.formatted(.currency(code: "EUR").precision(.fractionLength(0))))")
                                    .font(.caption2.bold()).foregroundColor(.green)
                                    .blur(radius: isPrivate ? 6 : 0)
                                Text("Monthly Div.: \(item.monthlyDividend.formatted(.currency(code: "EUR").precision(.fractionLength(0))))/mo")
                                    .font(.caption2).foregroundColor(.mint)
                                    .blur(radius: isPrivate ? 6 : 0)
                            }
                            .padding(8)
                            .background(Color(NSColor.windowBackgroundColor).opacity(0.95))
                            .cornerRadius(8)
                            .shadow(radius: 4)
                        }
                }
            }
            .chartLegend(.hidden)
            .chartXSelection(value: $hoveredYear)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine(); AxisTick()
                    if let val = value.as(Double.self) {
                        AxisValueLabel(val.formatted(.currency(code: "EUR").notation(.compactName)))
                    }
                }
            }
            
            HStack {
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.green.opacity(0.7)).frame(width: 12, height: 12)
                    Text("Gross Annual Dividends (€)").font(.caption).foregroundColor(.secondary)
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
            }
        }
        .padding(30)
        .frame(minWidth: 900, minHeight: 700)
    }
}
