import SwiftUI
import Charts

// =========================================================================
// MARK: - LOGIQUE DE SCORING INTERNE
// =========================================================================

struct ScoreEngine {
    static func getScoreStatus(value: Double, criterion: FundamentalCriterion) -> (points: Double, status: ScoreStatus) {
        if criterion.type == .boolean {
            if value == 1.0 {
                return (2.0 * criterion.weight, .premium)
            } else {
                return (0.0, .failed)
            }
        } else {
            if criterion.isHigherBetter {
                if value >= criterion.premiumThreshold { return (2.0 * criterion.weight, .premium) }
                else if value >= criterion.standardThreshold { return (1.0 * criterion.weight, .standard) }
                else { return (0.0, .failed) }
            } else {
                if value <= criterion.premiumThreshold { return (2.0 * criterion.weight, .premium) }
                else if value <= criterion.standardThreshold { return (1.0 * criterion.weight, .standard) }
                else { return (0.0, .failed) }
            }
        }
    }
    
    enum ScoreStatus { case premium, standard, failed, none }
}

enum FundamentalsChartZoomType: String, Identifiable {
    case totalScore, sectionScore, lineChart, polarChart
    var id: String { self.rawValue }
}

// =========================================================================
// MARK: - MAIN FUNDAMENTALS VIEW
// =========================================================================

struct FundamentalsView: View {
    @ObservedObject var viewModel: PortfolioViewModel
    @Binding var privacyMode: Bool
    
    @State private var showCriteriaManager: Bool = false
    @State private var editingCell: (position: Position, criterion: FundamentalCriterion)? = nil
    @State private var chartToZoom: FundamentalsChartZoomType? = nil
    
    var groupedCriteria: [(section: String, criteria: [FundamentalCriterion])] {
        let dict = Dictionary(grouping: viewModel.fundamentalCriteria, by: { $0.section })
        return dict.map { (section: $0.key, criteria: $0.value) }.sorted { $0.section < $1.section }
    }
    
    func color(for section: String) -> Color {
        let sortedSections = Array(Set(viewModel.fundamentalCriteria.map { $0.section })).sorted()
        if let idx = sortedSections.firstIndex(of: section) {
            let colors: [Color] = [.blue, .green, .purple, .orange, .pink, .teal, .mint, .indigo]
            return colors[idx % colors.count].opacity(0.2)
        }
        return .gray.opacity(0.2)
    }
    
    func colorForTicker(_ ticker: String) -> Color {
        let idx = abs(ticker.hashValue) % positionColors.count
        return positionColors[idx]
    }
    
    var maxPossibleScore: Double {
        viewModel.fundamentalCriteria.reduce(0) { $0 + ($1.weight * 2.0) }
    }
    
    func getTotalScore(for pos: Position) -> Double {
        var total = 0.0
        for crit in viewModel.fundamentalCriteria {
            if let val = pos.fundamentalValues?[crit.id.uuidString] {
                total += ScoreEngine.getScoreStatus(value: val, criterion: crit).points
            }
        }
        return total
    }
    
    // Calcul du score MAX possible pour une section donnée
    func getSectionMaxScore(section: String) -> Double {
        let crits = viewModel.fundamentalCriteria.filter { $0.section == section }
        return crits.reduce(0) { $0 + ($1.weight * 2.0) }
    }
    
    // Calcul du pourcentage atteint par une action dans une section donnée
    func getStockSectionScorePct(pos: Position, section: String) -> Double {
        let crits = viewModel.fundamentalCriteria.filter { $0.section == section }
        var total = 0.0
        for crit in crits {
            if let val = pos.fundamentalValues?[crit.id.uuidString] {
                total += ScoreEngine.getScoreStatus(value: val, criterion: crit).points
            }
        }
        let maxScore = getSectionMaxScore(section: section)
        guard maxScore > 0 else { return 0 }
        return (total / maxScore) * 100.0
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 24) {
                
                // HEADER
                HStack {
                    Text("Stock Quality Screener").font(.title).fontWeight(.bold)
                    Spacer()
                    Button(action: { showCriteriaManager = true }) {
                        Label("Manage Criteria", systemImage: "tablecells.badge.ellipsis")
                    }
                    .buttonStyle(.borderedProminent)
                }
                
                // 1. DASHBOARD (8 CARTES)
                FundamentalsDashboardSection(
                    viewModel: viewModel,
                    privacyMode: $privacyMode,
                    maxPossibleScore: maxPossibleScore,
                    getTotalScore: getTotalScore
                )
                
                // 2. LE SPREADSHEET (TABLEAU)
                FundamentalsSpreadsheetSection(
                    viewModel: viewModel,
                    groupedCriteria: groupedCriteria,
                    colorForSection: color,
                    getTotalScore: getTotalScore,
                    onCellTap: { pos, crit in
                        editingCell = (pos, crit)
                    }
                )
                
                // 3. GRAPHIQUES DE FORCES ET FAIBLESSES (Ligne 1)
                HStack(alignment: .top, spacing: 24) {
                    FundamentalsTotalScoreChart(
                        viewModel: viewModel,
                        maxPossibleScore: maxPossibleScore,
                        getTotalScore: getTotalScore,
                        expandedChart: $chartToZoom
                    )
                    
                    FundamentalsLineChart(
                        viewModel: viewModel,
                        uniqueSections: Array(Set(viewModel.fundamentalCriteria.map { $0.section })).sorted(),
                        getStockSectionScorePct: getStockSectionScorePct,
                        colorForTicker: colorForTicker,
                        expandedChart: $chartToZoom
                    )
                }
                
                // 4. GRAPHIQUES RADAR ET SCORECARD (Ligne 2)
                HStack(alignment: .top, spacing: 24) {
                    FundamentalsPolarChart(
                        viewModel: viewModel,
                        uniqueSections: Array(Set(viewModel.fundamentalCriteria.map { $0.section })).sorted(),
                        getStockSectionScorePct: getStockSectionScorePct,
                        colorForSection: color,
                        expandedChart: $chartToZoom
                    )
                    
                    FundamentalsRadarChart(
                        viewModel: viewModel,
                        uniqueSections: Array(Set(viewModel.fundamentalCriteria.map { $0.section })).sorted(),
                        getStockSectionScorePct: getStockSectionScorePct,
                        colorForTicker: colorForTicker
                    )
                }
            }
            .padding()
        }
        .sheet(isPresented: $showCriteriaManager) {
            CriteriaManagerSheet(viewModel: viewModel)
        }
        .sheet(item: Binding<EditingCellWrapper?>(
            get: { editingCell != nil ? EditingCellWrapper(position: editingCell!.position, criterion: editingCell!.criterion) : nil },
            set: { _ in editingCell = nil }
        )) { wrapper in
            ValueEntrySheet(
                viewModel: viewModel,
                position: wrapper.position,
                criterion: wrapper.criterion
            )
        }
        .sheet(item: $chartToZoom) { type in
            FundamentalsFullScreenChartView(
                zoomType: type,
                viewModel: viewModel,
                maxPossibleScore: maxPossibleScore,
                getTotalScore: getTotalScore,
                colorForSection: color,
                uniqueSections: Array(Set(viewModel.fundamentalCriteria.map { $0.section })).sorted(),
                getStockSectionScorePct: getStockSectionScorePct,
                colorForTicker: colorForTicker
            )
        }
    }
}

struct EditingCellWrapper: Identifiable {
    let id = UUID()
    let position: Position
    let criterion: FundamentalCriterion
}

// =========================================================================
// MARK: - DASHBOARD SECTION
// =========================================================================

struct FundamentalsDashboardSection: View {
    @ObservedObject var viewModel: PortfolioViewModel
    @Binding var privacyMode: Bool
    let maxPossibleScore: Double
    let getTotalScore: (Position) -> Double
    
    var body: some View {
        VStack(spacing: 16) {
            let trackedStocks = viewModel.positions.filter { ($0.fundamentalValues?.count ?? 0) > 0 }
            
            let avgScore = trackedStocks.isEmpty ? 0 : trackedStocks.reduce(0) { $0 + getTotalScore($1) } / Double(trackedStocks.count)
            let avgScorePct = maxPossibleScore > 0 ? (avgScore / maxPossibleScore) : 0
            
            let bestStock = trackedStocks.max(by: { getTotalScore($0) < getTotalScore($1) })
            let bestScore = bestStock != nil ? getTotalScore(bestStock!) : 0
            
            HStack(spacing: 16) {
                DashboardCard(title: "Tracked Criteria", value: "\(viewModel.fundamentalCriteria.count)", titleIcon: "checklist", privacyMode: .constant(false))
                DashboardCard(title: "Stocks Analyzed", value: "\(trackedStocks.count) / \(viewModel.positions.count)", titleIcon: "magnifyingglass", privacyMode: .constant(false))
                DashboardCard(title: "Avg Portfolio Quality", value: "\(avgScore.formatted(.number.precision(.fractionLength(1)))) / \(Int(maxPossibleScore))", titleIcon: "star.fill", privacyMode: .constant(false))
                DashboardCard(title: "Avg Quality Score (%)", value: avgScorePct.formatted(.percent.precision(.fractionLength(1))), titleIcon: "percent", privacyMode: .constant(false))
            }
            
            HStack(spacing: 16) {
                DashboardCard(title: "Top Quality Stock", value: bestStock?.ticker ?? "-", titleIcon: "trophy.fill", privacyMode: .constant(false))
                DashboardCard(title: "Top Stock Score", value: bestStock != nil ? "\(bestScore.formatted(.number.precision(.fractionLength(1))))" : "-", titleIcon: "crown.fill", privacyMode: .constant(false))
                DashboardCard(title: "Strongest Section", value: getStrongestSection(), titleIcon: "arrow.up.right.circle.fill", privacyMode: .constant(false))
                DashboardCard(title: "Weakest Section", value: getWeakestSection(), titleIcon: "arrow.down.right.circle.fill", privacyMode: .constant(false))
            }
        }
    }
    
    func getStrongestSection() -> String { return sectionRanking().first?.key ?? "-" }
    func getWeakestSection() -> String { return sectionRanking().last?.key ?? "-" }
    
    func sectionRanking() -> [(key: String, value: Double)] {
        var sectionScores: [String: Double] = [:]
        var sectionMax: [String: Double] = [:]
        
        for crit in viewModel.fundamentalCriteria {
            sectionMax[crit.section, default: 0] += (crit.weight * 2.0 * Double(viewModel.positions.count))
            for pos in viewModel.positions {
                if let val = pos.fundamentalValues?[crit.id.uuidString] {
                    sectionScores[crit.section, default: 0] += ScoreEngine.getScoreStatus(value: val, criterion: crit).points
                }
            }
        }
        
        var pctDict: [String: Double] = [:]
        for (sec, score) in sectionScores {
            let maxScore = sectionMax[sec] ?? 1
            pctDict[sec] = score / maxScore
        }
        return pctDict.sorted { $0.value > $1.value }
    }
}

// =========================================================================
// MARK: - THE SPREADSHEET (TABLEAU)
// =========================================================================

struct InfoHeaderCell: View {
    let title: String
    let width: CGFloat
    var body: some View {
        Text(title).font(.caption).fontWeight(.bold).frame(width: width, height: 30)
            .background(Color(NSColor.windowBackgroundColor)).border(Color.gray.opacity(0.2), width: 0.5)
    }
}

struct CriterionHeaderCell: View {
    let crit: FundamentalCriterion
    let width: CGFloat
    let bgColor: Color
    var body: some View {
        Text(crit.name).font(.caption).fontWeight(.bold).frame(width: width, height: 30)
            .background(bgColor.opacity(0.5)).border(Color.gray.opacity(0.2), width: 0.5)
            .help("Weight: \(crit.weight) | Premium: \(crit.premiumThreshold) | Standard: \(crit.standardThreshold)")
    }
}

struct InfoCell: View {
    let text: String
    let width: CGFloat
    var isBold: Bool = true
    let height: CGFloat
    var body: some View {
        Text(text).font(.subheadline).fontWeight(isBold ? .bold : .regular).frame(width: width, height: height)
            .background(Color(NSColor.windowBackgroundColor)).border(Color.gray.opacity(0.2), width: 0.5)
    }
}

struct FundamentalsSpreadsheetSection: View {
    @ObservedObject var viewModel: PortfolioViewModel
    let groupedCriteria: [(section: String, criteria: [FundamentalCriterion])]
    let colorForSection: (String) -> Color
    let getTotalScore: (Position) -> Double
    let onCellTap: (Position, FundamentalCriterion) -> Void
    
    let rowHeight: CGFloat = 40
    let colWidthInfo: CGFloat = 85
    let colWidthCrit: CGFloat = 110
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Screener Data").font(.title2).fontWeight(.bold)
            
            if viewModel.fundamentalCriteria.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tablecells.badge.ellipsis").font(.system(size: 40)).foregroundColor(.secondary.opacity(0.5))
                    Text("No criteria defined. Click 'Manage Criteria' to build your screener.").foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 250)
                .background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.2), lineWidth: 1))
            } else {
                ScrollView([.horizontal, .vertical], showsIndicators: true) {
                    VStack(spacing: 0) {
                        // HEADER 1 : SECTIONS
                        HStack(spacing: 0) {
                            Text("INFO").font(.subheadline).fontWeight(.bold).foregroundColor(.secondary).frame(width: colWidthInfo * 3, height: 30)
                                .background(Color(NSColor.windowBackgroundColor)).border(Color.gray.opacity(0.2), width: 0.5)
                            
                            ForEach(groupedCriteria, id: \.section) { group in
                                Text(group.section).font(.subheadline).fontWeight(.bold).frame(width: CGFloat(group.criteria.count) * colWidthCrit, height: 30)
                                    .background(colorForSection(group.section)).border(Color.gray.opacity(0.2), width: 0.5)
                            }
                        }
                        
                        // HEADER 2 : CRITÈRES
                        HStack(spacing: 0) {
                            InfoHeaderCell(title: "Ticker", width: colWidthInfo)
                            InfoHeaderCell(title: "Quality", width: colWidthInfo)
                            InfoHeaderCell(title: "Weight", width: colWidthInfo)
                            
                            ForEach(groupedCriteria, id: \.section) { group in
                                ForEach(group.criteria) { crit in
                                    CriterionHeaderCell(crit: crit, width: colWidthCrit, bgColor: colorForSection(group.section))
                                }
                            }
                        }
                        
                        // LIGNES : ACTIONS
                        ForEach(viewModel.positions) { pos in
                            HStack(spacing: 0) {
                                InfoCell(text: pos.ticker, width: colWidthInfo, height: rowHeight)
                                InfoCell(text: getTotalScore(pos).formatted(.number.precision(.fractionLength(1))), width: colWidthInfo, height: rowHeight)
                                
                                let weight = viewModel.totalValue > 0 ? (pos.currentValueEUR / viewModel.totalValue) : 0
                                InfoCell(text: weight.formatted(.percent.precision(.fractionLength(2))), width: colWidthInfo, isBold: false, height: rowHeight)
                                
                                ForEach(groupedCriteria, id: \.section) { group in
                                    ForEach(group.criteria) { crit in
                                        let val = pos.fundamentalValues?[crit.id.uuidString]
                                        let statusInfo = val != nil ? ScoreEngine.getScoreStatus(value: val!, criterion: crit) : (0.0, .none)
                                        
                                        Button(action: { onCellTap(pos, crit) }) {
                                            Text(formatValue(val, type: crit.type))
                                                .font(.subheadline).fontWeight(.semibold).foregroundColor(statusColor(statusInfo.status))
                                                .frame(width: colWidthCrit, height: rowHeight).background(Color(NSColor.controlBackgroundColor))
                                                .border(Color.gray.opacity(0.2), width: 0.5).contentShape(Rectangle())
                                        }.buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                }
                .background(Color(NSColor.controlBackgroundColor)).cornerRadius(8).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1)).frame(maxHeight: 450)
            }
        }
    }
    
    func formatValue(_ value: Double?, type: CriterionType) -> String {
        guard let v = value else { return "-" }
        switch type {
        case .boolean: return v == 1.0 ? "Yes" : "No"
        case .percentage: return (v / 100.0).formatted(.percent.precision(.fractionLength(2)))
        case .number: return v.formatted(.number.precision(.fractionLength(2)))
        }
    }
    
    func statusColor(_ status: ScoreEngine.ScoreStatus) -> Color {
        switch status {
        case .premium: return .green
        case .standard: return .blue
        case .failed: return .red
        case .none: return .secondary
        }
    }
}

// =========================================================================
// MARK: - VISUAL ANALYTICS (CHARTS)
// =========================================================================

struct FundamentalsTotalScoreChart: View {
    @ObservedObject var viewModel: PortfolioViewModel
    let maxPossibleScore: Double
    let getTotalScore: (Position) -> Double
    var isExpanded: Bool = false
    @Binding var expandedChart: FundamentalsChartZoomType?
    
    @State private var hoveredTicker: String? = nil

    var body: some View {
        VStack {
            HStack {
                if !isExpanded { Text("Quality Score Comparison").font(.headline).foregroundColor(.secondary) }
                Spacer()
                if !isExpanded {
                    Button(action: { expandedChart = .totalScore }) { Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary) }.buttonStyle(.plain)
                }
            }.padding(.bottom, 16)
            
            if viewModel.fundamentalCriteria.isEmpty || viewModel.positions.isEmpty {
                Spacer(); Text("No data").foregroundColor(.secondary); Spacer()
            } else {
                Chart(viewModel.positions.sorted(by: { getTotalScore($0) > getTotalScore($1) })) { pos in
                    let score = getTotalScore(pos)
                    BarMark(x: .value("Ticker", pos.ticker), y: .value("Score", score))
                        .foregroundStyle(Color.blue.gradient).cornerRadius(4)
                    
                    if let hTicker = hoveredTicker, pos.ticker == hTicker {
                        RuleMark(x: .value("Ticker", hTicker))
                            .foregroundStyle(.secondary.opacity(0.3))
                            .annotation(position: .top, alignment: .center) {
                                VStack {
                                    Text(hTicker).font(.caption.bold())
                                    Text("\(score.formatted(.number.precision(.fractionLength(1)))) pts").font(.caption2)
                                }.padding(6).background(Color(NSColor.windowBackgroundColor).opacity(0.95)).cornerRadius(6).shadow(radius: 4)
                            }
                    }
                }
                .chartYScale(domain: [0, max(maxPossibleScore, 1)])
                .chartLegend(.hidden)
                .chartXSelection(value: $hoveredTicker)
            }
            
            Spacer()
            BlueChipWatermark()
        }
        .padding().frame(minHeight: isExpanded ? 500 : 360, maxHeight: isExpanded ? .infinity : 360)
        .background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// CORRECTION : Sous-vue dédiée pour l'annotation afin de soulager le compilateur SwiftUI
struct FundamentalsLineChartTooltip: View {
    let section: String
    let positions: [Position]
    let getScorePct: (Position, String) -> Double
    let colorForTicker: (String) -> Color
    
    var sortedPositions: [Position] {
        positions.sorted { getScorePct($0, section) > getScorePct($1, section) }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(section).font(.caption.bold())
            ForEach(sortedPositions) { pos in
                let pct = getScorePct(pos, section)
                HStack {
                    Circle().fill(colorForTicker(pos.ticker)).frame(width: 6, height: 6)
                    Text(pos.ticker).font(.caption2)
                    Spacer(minLength: 12)
                    Text("\(pct.formatted(.number.precision(.fractionLength(1))))%").font(.caption2.bold())
                }
            }
        }
        .padding(8).background(Color(NSColor.windowBackgroundColor).opacity(0.95)).cornerRadius(8).shadow(radius: 4)
    }
}

struct FundamentalsLineChart: View {
    @ObservedObject var viewModel: PortfolioViewModel
    let uniqueSections: [String]
    let getStockSectionScorePct: (Position, String) -> Double
    let colorForTicker: (String) -> Color
    var isExpanded: Bool = false
    @Binding var expandedChart: FundamentalsChartZoomType?
    
    @State private var hoveredSection: String? = nil
    @State private var hiddenTickers: Set<String> = []
    
    var filteredPositions: [Position] {
        viewModel.positions.filter { !hiddenTickers.contains($0.ticker) }
    }

    var body: some View {
        VStack {
            HStack {
                if !isExpanded { Text("Stock Quality by Segment (%)").font(.headline).foregroundColor(.secondary) }
                Spacer()
                if !isExpanded {
                    Button(action: { expandedChart = .lineChart }) { Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary) }.buttonStyle(.plain)
                }
            }.padding(.bottom, 4)
            
            InteractiveLegendView(items: viewModel.positions.map { $0.ticker }, colorMap: colorForTicker, hiddenItems: $hiddenTickers)
                .padding(.bottom, 8)
            
            if uniqueSections.isEmpty || filteredPositions.isEmpty {
                Spacer(); Text("No data").foregroundColor(.secondary); Spacer()
            } else {
                Chart {
                    ForEach(filteredPositions) { pos in
                        ForEach(uniqueSections, id: \.self) { section in
                            let pct = getStockSectionScorePct(pos, section)
                            LineMark(
                                x: .value("Section", section),
                                y: .value("Score (%)", pct)
                            )
                            .foregroundStyle(colorForTicker(pos.ticker))
                            .interpolationMethod(.catmullRom)
                            
                            PointMark(
                                x: .value("Section", section),
                                y: .value("Score (%)", pct)
                            )
                            .foregroundStyle(colorForTicker(pos.ticker))
                        }
                    }
                    
                    if let hSection = hoveredSection {
                        RuleMark(x: .value("Section", hSection))
                            .foregroundStyle(.secondary.opacity(0.5))
                            .annotation(position: .top, alignment: .center) {
                                // Appel à notre Tooltip Extrait
                                FundamentalsLineChartTooltip(
                                    section: hSection,
                                    positions: filteredPositions,
                                    getScorePct: getStockSectionScorePct,
                                    colorForTicker: colorForTicker
                                )
                            }
                    }
                }
                .chartYScale(domain: [0, 100])
                .chartLegend(.hidden)
                .chartXSelection(value: $hoveredSection)
            }
            
            Spacer()
            BlueChipWatermark()
        }
        .padding().frame(minHeight: isExpanded ? 500 : 360, maxHeight: isExpanded ? .infinity : 360)
        .background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

struct FundamentalsPolarChart: View {
    @ObservedObject var viewModel: PortfolioViewModel
    let uniqueSections: [String]
    let getStockSectionScorePct: (Position, String) -> Double
    let colorForSection: (String) -> Color
    var isExpanded: Bool = false
    @Binding var expandedChart: FundamentalsChartZoomType?
    
    @State private var hoveredAngle: Int? = nil

    var weightedSectionScores: [(section: String, score: Double)] {
        let totalValue = viewModel.totalValue
        guard totalValue > 0 else { return [] }
        var results: [(String, Double)] = []
        for section in uniqueSections {
            var weightedScore = 0.0
            for pos in viewModel.positions {
                let weight = pos.currentValueEUR / totalValue
                let scorePct = getStockSectionScorePct(pos, section)
                weightedScore += (scorePct * weight)
            }
            results.append((section, weightedScore))
        }
        return results
    }

    var body: some View {
        VStack {
            HStack {
                if !isExpanded { Text("Weighted Portfolio Scorecard").font(.headline).foregroundColor(.secondary) }
                Spacer()
                if !isExpanded {
                    Button(action: { expandedChart = .polarChart }) { Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary) }.buttonStyle(.plain)
                }
            }.padding(.bottom, 16)
            
            if weightedSectionScores.isEmpty {
                Spacer(); Text("No data").foregroundColor(.secondary); Spacer()
            } else {
                Chart(Array(weightedSectionScores.enumerated()), id: \.element.section) { index, item in
                    SectorMark(
                        angle: .value("Angle", 1),
                        innerRadius: .ratio(0.1),
                        outerRadius: .ratio(max(item.score, 5) / 100.0),
                        angularInset: 1.0
                    )
                    .foregroundStyle(colorForSection(item.section).opacity(0.8))
                    .cornerRadius(2)
                }
                .chartAngleSelection(value: $hoveredAngle)
                .chartBackground { proxy in
                    GeometryReader { geo in
                        let center = CGPoint(x: geo.frame(in: .local).midX, y: geo.frame(in: .local).midY)
                        let radius = min(geo.size.width, geo.size.height) / 2
                        
                        ForEach(1...5, id: \.self) { i in
                            Circle()
                                .stroke(Color.gray.opacity(0.1), lineWidth: 1)
                                .frame(width: radius * 2 * CGFloat(i)/5, height: radius * 2 * CGFloat(i)/5)
                                .position(center)
                        }
                        
                        if let angle = hoveredAngle, angle >= 0, angle < weightedSectionScores.count {
                            let item = weightedSectionScores[angle]
                            VStack {
                                Text(item.section).font(.caption.bold())
                                Text("Score: \(item.score.formatted(.number.precision(.fractionLength(1))))%")
                                    .font(.caption2)
                            }
                            .padding(8).background(Color(NSColor.windowBackgroundColor).opacity(0.95)).cornerRadius(8).shadow(radius: 4)
                            .position(x: center.x, y: center.y)
                        }
                    }
                }
                
                HStack(spacing: 12) {
                    ForEach(weightedSectionScores, id: \.section) { item in
                        HStack(spacing: 4) {
                            Circle().fill(colorForSection(item.section)).frame(width: 8, height: 8)
                            Text(item.section).font(.caption2)
                        }
                    }
                }
                .padding(.top, 16)
            }
            
            Spacer()
            BlueChipWatermark()
        }
        .padding().frame(minHeight: isExpanded ? 500 : 360, maxHeight: isExpanded ? .infinity : 360)
        .background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// CORRECTION : Le nouveau Radar affiche une signature par action, filtrable via sa légende interactive !
struct FundamentalsRadarChart: View {
    @ObservedObject var viewModel: PortfolioViewModel
    let uniqueSections: [String]
    let getStockSectionScorePct: (Position, String) -> Double
    let colorForTicker: (String) -> Color
    
    @State private var hiddenTickers: Set<String> = []
    
    var filteredPositions: [Position] {
        viewModel.positions.filter { !hiddenTickers.contains($0.ticker) }
    }

    var body: some View {
        VStack {
            HStack {
                Text("Stock Radar Profiles").font(.headline).foregroundColor(.secondary)
                Spacer()
            }.padding(.bottom, 4)
            
            InteractiveLegendView(items: viewModel.positions.map { $0.ticker }, colorMap: colorForTicker, hiddenItems: $hiddenTickers)
                .padding(.bottom, 8)
            
            if uniqueSections.isEmpty || filteredPositions.isEmpty {
                Spacer(); Text("No data").foregroundColor(.secondary); Spacer()
            } else {
                GeometryReader { geo in
                    let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                    let radius = min(geo.size.width, geo.size.height) / 2 - 30
                    let dataCount = uniqueSections.count
                    
                    ZStack {
                        // Dessin des toiles d'araignées (niveaux de base 0 à 100%)
                        ForEach(1...5, id: \.self) { i in
                            RadarPolygon(dataCount: dataCount, radius: radius * CGFloat(i) / 5)
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        }
                        
                        // Dessin des axes et labels des sections
                        ForEach(0..<dataCount, id: \.self) { i in
                            let angle = CGFloat(i) * (2 * .pi / CGFloat(dataCount)) - .pi / 2
                            Path { p in
                                p.move(to: center)
                                p.addLine(to: CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle)))
                            }.stroke(Color.gray.opacity(0.2), lineWidth: 1)
                            
                            Text(uniqueSections[i])
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .position(x: center.x + (radius + 25) * cos(angle), y: center.y + (radius + 25) * sin(angle))
                        }
                        
                        // Dessin des polygones de données pour CHAQUE action
                        ForEach(filteredPositions) { pos in
                            let values = uniqueSections.map { getStockSectionScorePct(pos, $0) / 100.0 }
                            RadarDataPolygon(values: values, radius: radius)
                                .fill(colorForTicker(pos.ticker).opacity(0.15))
                            RadarDataPolygon(values: values, radius: radius)
                                .stroke(colorForTicker(pos.ticker), lineWidth: 2)
                        }
                    }
                }
            }
            
            Spacer()
            BlueChipWatermark()
        }
        .padding().frame(minHeight: 360, maxHeight: 360)
        .background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

struct RadarPolygon: Shape {
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

struct RadarDataPolygon: Shape {
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
// MARK: - FULLSCREEN ZOOM FOR FUNDAMENTALS
// =========================================================================

struct FundamentalsFullScreenChartView: View {
    @Environment(\.dismiss) var dismiss
    let zoomType: FundamentalsChartZoomType
    @ObservedObject var viewModel: PortfolioViewModel
    let maxPossibleScore: Double
    let getTotalScore: (Position) -> Double
    let colorForSection: (String) -> Color
    let uniqueSections: [String]
    let getStockSectionScorePct: (Position, String) -> Double
    let colorForTicker: (String) -> Color

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text(titleForZoom).font(.title).fontWeight(.bold)
                Spacer()
                Button(action: { dismiss() }) { Image(systemName: "xmark.circle.fill").font(.title).foregroundColor(.secondary) }.buttonStyle(.plain)
            }
            
            switch zoomType {
            case .totalScore:
                FundamentalsTotalScoreChart(viewModel: viewModel, maxPossibleScore: maxPossibleScore, getTotalScore: getTotalScore, isExpanded: true, expandedChart: .constant(nil))
            case .sectionScore:
                Text("Not used")
            case .lineChart:
                FundamentalsLineChart(viewModel: viewModel, uniqueSections: uniqueSections, getStockSectionScorePct: getStockSectionScorePct, colorForTicker: colorForTicker, isExpanded: true, expandedChart: .constant(nil))
            case .polarChart:
                FundamentalsPolarChart(viewModel: viewModel, uniqueSections: uniqueSections, getStockSectionScorePct: getStockSectionScorePct, colorForSection: colorForSection, isExpanded: true, expandedChart: .constant(nil))
            }
        }.padding(30).frame(minWidth: 900, minHeight: 700)
    }
    
    var titleForZoom: String {
        switch zoomType {
        case .totalScore: return "Quality Score Comparison"
        case .sectionScore: return "Strengths & Weaknesses"
        case .lineChart: return "Stock Quality by Segment (%)"
        case .polarChart: return "Weighted Portfolio Scorecard"
        }
    }
}

// =========================================================================
// MARK: - SHEET : GÉRER LES CRITÈRES (AJOUT / SUPPRESSION)
// =========================================================================

struct CriteriaManagerSheet: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: PortfolioViewModel
    
    @State private var name: String = ""
    @State private var sectionStr: String = ""
    @State private var weight: Double = 1.0
    @State private var type: CriterionType = .percentage
    @State private var isHigherBetter: Bool = true
    @State private var premiumThreshold: Double = 15.0
    @State private var standardThreshold: Double = 8.0
    
    var uniqueSections: [String] {
        Array(Set(viewModel.fundamentalCriteria.map { $0.section })).sorted()
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Manage Criteria").font(.title2).fontWeight(.bold)
                Spacer()
                Button(action: { dismiss() }) { Image(systemName: "xmark.circle.fill").font(.title2).foregroundColor(.secondary) }.buttonStyle(.plain)
            }.padding()
            Divider()
            
            HStack(spacing: 0) {
                // LISTE DES CRITÈRES EXISTANTS (Magnifique Sidebar style)
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(uniqueSections, id: \.self) { sec in
                            let crits = viewModel.fundamentalCriteria.filter { $0.section == sec }
                            if !crits.isEmpty {
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(sec)
                                        .font(.caption.bold())
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                    
                                    VStack(spacing: 0) {
                                        ForEach(crits) { crit in
                                            HStack {
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text(crit.name).font(.subheadline).fontWeight(.bold).foregroundColor(.primary)
                                                    Text("Weight: \(crit.weight.formatted()) | Type: \(crit.type.displayName)")
                                                        .font(.caption2).foregroundColor(.secondary)
                                                }
                                                Spacer()
                                                Button(action: { viewModel.fundamentalCriteria.removeAll { $0.id == crit.id } }) {
                                                    Image(systemName: "trash").foregroundColor(.red)
                                                }.buttonStyle(.plain)
                                            }
                                            .padding(12)
                                            
                                            if crit.id != crits.last?.id { Divider().padding(.leading, 12) }
                                        }
                                    }
                                    .background(Color(NSColor.windowBackgroundColor))
                                    .cornerRadius(8)
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.1), lineWidth: 1))
                                    .padding(.horizontal, 12)
                                }
                            }
                        }
                    }
                    .padding(.vertical)
                }
                .frame(width: 320)
                .background(Color(NSColor.controlBackgroundColor))
                
                Divider()
                
                // FORMULAIRE D'AJOUT
                Form {
                    Section(header: Text("Add New Criterion").font(.headline)) {
                        TextField("Criterion Name (e.g. Net Margin)", text: $name)
                        
                        VStack(alignment: .leading) {
                            TextField("Section Category (e.g. GROWTH)", text: $sectionStr)
                                .onChange(of: sectionStr) { sectionStr = sectionStr.uppercased() }
                            
                            if !uniqueSections.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack {
                                        ForEach(uniqueSections, id: \.self) { sec in
                                            Button(action: { sectionStr = sec }) {
                                                Text(sec).font(.caption).padding(4).background(Color.blue.opacity(0.1)).cornerRadius(4)
                                            }.buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                        }
                        
                        Picker("Data Type", selection: $type) {
                            ForEach(CriterionType.allCases, id: \.self) { t in
                                Text(t.displayName).tag(t)
                            }
                        }
                        TextField("Weight (Points multiplier)", value: $weight, format: .number)
                    }
                    
                    Section(header: Text("Scoring Rules").font(.headline)) {
                        if type == .boolean {
                            Text("Boolean criteria always award 2x weight if 'Yes', and 0 if 'No'.").font(.caption).foregroundColor(.secondary)
                        } else {
                            Toggle("Higher value is better? (Uncheck if lower is better)", isOn: $isHigherBetter)
                            
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("Premium Threshold").font(.caption)
                                    TextField("e.g. 20", value: $premiumThreshold, format: .number).textFieldStyle(.roundedBorder)
                                }
                                VStack(alignment: .leading) {
                                    Text("Standard Threshold").font(.caption)
                                    TextField("e.g. 10", value: $standardThreshold, format: .number).textFieldStyle(.roundedBorder)
                                }
                            }
                            let premPts = (2 * weight).formatted(.number.precision(.fractionLength(0...2)))
                            let stdPts = (1 * weight).formatted(.number.precision(.fractionLength(0...2)))
                            Text("Premium awards \(premPts) pts. Standard awards \(stdPts) pts.")
                                .font(.caption).foregroundColor(.blue)
                        }
                    }
                    
                    Button("Add Criterion") {
                        let newCrit = FundamentalCriterion(
                            id: UUID(), name: name, section: sectionStr.isEmpty ? "UNCATEGORIZED" : sectionStr, weight: weight, type: type,
                            isHigherBetter: isHigherBetter, premiumThreshold: premiumThreshold, standardThreshold: standardThreshold
                        )
                        viewModel.fundamentalCriteria.append(newCrit)
                        name = ""
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(name.isEmpty || sectionStr.isEmpty)
                    .padding(.top, 10)
                }
                .padding()
            }
        }
        .frame(width: 800, height: 600)
    }
}

// =========================================================================
// MARK: - SHEET : ENTRER UNE VALEUR POUR UNE ACTION
// =========================================================================

struct ValueEntrySheet: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: PortfolioViewModel
    let position: Position
    let criterion: FundamentalCriterion
    
    @State private var inputValue: Double? = nil
    @State private var boolValue: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Edit \(criterion.name)").font(.headline).fontWeight(.bold)
                Spacer()
                Button(action: { dismiss() }) { Image(systemName: "xmark.circle.fill").foregroundColor(.secondary) }.buttonStyle(.plain)
            }.padding()
            Divider()
            
            VStack(spacing: 20) {
                Text(position.ticker).font(.title).fontWeight(.bold).foregroundColor(.blue)
                
                if criterion.type == .boolean {
                    Toggle("Is the condition met? (Yes/No)", isOn: $boolValue)
                        .toggleStyle(.switch)
                } else {
                    let unit = criterion.type == .percentage ? "%" : ""
                    HStack {
                        TextField("Enter value", value: $inputValue, format: .number)
                            .textFieldStyle(.roundedBorder)
                        if !unit.isEmpty { Text(unit).fontWeight(.bold) }
                    }
                }
                
                HStack {
                    Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Save") {
                        let finalValue: Double
                        if criterion.type == .boolean {
                            finalValue = boolValue ? 1.0 : 0.0
                        } else {
                            finalValue = inputValue ?? 0.0
                        }
                        viewModel.updateFundamentalValue(for: position.id, criterionId: criterion.id, value: finalValue)
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
        .frame(width: 350)
        .onAppear {
            if let existing = position.fundamentalValues?[criterion.id.uuidString] {
                if criterion.type == .boolean {
                    boolValue = (existing == 1.0)
                } else {
                    inputValue = existing
                }
            }
        }
    }
}
