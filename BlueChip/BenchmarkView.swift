import SwiftUI
import Charts

// MARK: - ZOOM ENUM
enum BenchmarkChartZoomType: String, Identifiable {
    case annualBars, growth10k
    var id: String { rawValue }
}

// MARK: - COLORS FOR INDICES
let benchmarkColors: [Color] = [.red, .orange, .yellow, .green, .teal, .purple, .pink, .mint, .cyan, .brown]

// MARK: - MAIN VIEW
struct BenchmarkView: View {
    @ObservedObject var viewModel: PortfolioViewModel
    @Binding var privacyMode: Bool

    @State private var showGoalSheet = false
    @State private var showAddIndexSheet = false
    @State private var chartToZoom: BenchmarkChartZoomType? = nil

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 24) {
                BenchmarkDashboardSection(viewModel: viewModel, privacyMode: $privacyMode)

                BenchmarkGoalProgressBar(viewModel: viewModel, privacyMode: $privacyMode)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { showGoalSheet = true }

                BenchmarkTableSection(viewModel: viewModel, showAddIndexSheet: $showAddIndexSheet)

                BenchmarkChartsSection(viewModel: viewModel, chartToZoom: $chartToZoom)
            }
            .padding()
        }
        .sheet(isPresented: $showGoalSheet) { EditBenchmarkGoalView(viewModel: viewModel) }
        .sheet(isPresented: $showAddIndexSheet) { AddBenchmarkIndexView(viewModel: viewModel) }
        .sheet(item: $chartToZoom) { type in BenchmarkFullScreenChartView(zoomType: type, viewModel: viewModel) }
    }
}

// =========================================================================
// MARK: - GOAL FORM
// =========================================================================

struct EditBenchmarkGoalView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: PortfolioViewModel
    @State private var targetInput: Double

    init(viewModel: PortfolioViewModel) {
        self.viewModel = viewModel
        _targetInput = State(initialValue: viewModel.benchmarkGoalTarget)
    }

    var body: some View {
        Form {
            Section(header: Text("Set Benchmark Goal").font(.headline)) {
                TextField("Outperformance target (%)", value: $targetInput, format: .number)
            }.padding()
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") { viewModel.benchmarkGoalTarget = targetInput; dismiss() }
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }.padding()
        }.frame(width: 380).padding()
    }
}

// =========================================================================
// MARK: - ADD INDEX FORM
// =========================================================================

struct AddBenchmarkIndexView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: PortfolioViewModel
    @State private var name: String = ""

    var body: some View {
        Form {
            Section(header: Text("New Index").font(.headline)) {
                TextField("Index name (e.g. S&P 500, MSCI World…)", text: $name)
            }.padding()
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add") {
                    guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    viewModel.benchmarkIndices.append(BenchmarkIndex(name: name, returns: [:]))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }.padding()
        }.frame(width: 380).padding()
    }
}

// =========================================================================
// MARK: - DASHBOARD
// =========================================================================

struct BenchmarkDashboardSection: View {
    @ObservedObject var viewModel: PortfolioViewModel
    @Binding var privacyMode: Bool

    var currentYear: Int { Calendar.current.component(.year, from: Date()) }
    var startYear: Int { viewModel.dividendStartYear }

    // Retours du portefeuille par année (depuis GrowthView)
    var portfolioReturns: [Int: Double] {
        var dict: [Int: Double] = [:]
        for yearData in viewModel.growthYears {
            guard yearData.year >= startYear && yearData.year <= currentYear else { continue }
            let isCurrentYear = yearData.year == currentYear
            let effectiveEnd = isCurrentYear ? viewModel.currentTotalCapital : yearData.endWallet
            let base = yearData.startWallet + yearData.invested
            guard base > 0 else { continue }
            dict[yearData.year] = ((effectiveEnd - base) / base) * 100.0
        }
        return dict
    }

    var activeYears: [Int] { Array(startYear...currentYear) }

    var portfolioAvgReturn: Double {
        let vals = activeYears.compactMap { portfolioReturns[$0] }
        guard !vals.isEmpty else { return 0 }
        return vals.reduce(0, +) / Double(vals.count)
    }

    var portfolioCurrentYear: Double { portfolioReturns[currentYear] ?? 0 }

    var bestIndex: BenchmarkIndex? {
        viewModel.benchmarkIndices.max { a, b in
            a.averageReturn(years: activeYears) < b.averageReturn(years: activeYears)
        }
    }

    var portfolioVsBest: Double {
        guard let best = bestIndex else { return 0 }
        return portfolioAvgReturn - best.averageReturn(years: activeYears)
    }

    // 10k simulé pour le portefeuille
    var portfolio10k: Double {
        var value = 10000.0
        for y in activeYears { value *= (1 + (portfolioReturns[y] ?? 0) / 100.0) }
        return value
    }

    var best10k: Double {
        guard let best = bestIndex else { return 0 }
        return best.value10k(upToYear: currentYear, startYear: startYear)
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                // Retour portefeuille année courante
                VStack(alignment: .leading, spacing: 4) {
                    Text("Portfolio Return \(currentYear)").font(.subheadline).foregroundColor(.secondary).lineLimit(1)
                    Text(portfolioCurrentYear.formatted(.number.precision(.fractionLength(2)).sign(strategy: .always())) + "%")
                        .font(.title2).fontWeight(.bold)
                        .foregroundColor(portfolioCurrentYear >= 0 ? .green : .red)
                        .blur(radius: privacyMode ? 8 : 0)
                }
                .padding().frame(maxWidth: .infinity, alignment: .leading).frame(height: 110)
                .background(Color(NSColor.controlBackgroundColor)).cornerRadius(10)
                .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)

                // Retour moyen du portefeuille
                VStack(alignment: .leading, spacing: 4) {
                    Text("Portfolio Avg. Return").font(.subheadline).foregroundColor(.secondary).lineLimit(1)
                    Text(portfolioAvgReturn.formatted(.number.precision(.fractionLength(2)).sign(strategy: .always())) + "%")
                        .font(.title2).fontWeight(.bold)
                        .foregroundColor(portfolioAvgReturn >= 0 ? .green : .red)
                        .blur(radius: privacyMode ? 8 : 0)
                }
                .padding().frame(maxWidth: .infinity, alignment: .leading).frame(height: 110)
                .background(Color(NSColor.controlBackgroundColor)).cornerRadius(10)
                .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)

                // Meilleur indice (avg)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Best Index (Avg.)").font(.subheadline).foregroundColor(.secondary).lineLimit(1)
                    if let best = bestIndex {
                        Text(best.name).font(.title2).fontWeight(.bold).lineLimit(1).minimumScaleFactor(0.7)
                        Text(best.averageReturn(years: activeYears).formatted(.number.precision(.fractionLength(2)).sign(strategy: .always())) + "%")
                            .font(.caption).foregroundColor(.secondary)
                    } else {
                        Text("—").font(.title2).fontWeight(.bold).foregroundColor(.secondary)
                    }
                }
                .padding().frame(maxWidth: .infinity, alignment: .leading).frame(height: 110)
                .background(Color(NSColor.controlBackgroundColor)).cornerRadius(10)
                .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)

                // Portfolio vs Best index
                VStack(alignment: .leading, spacing: 4) {
                    Text("vs Best Index (Avg.)").font(.subheadline).foregroundColor(.secondary).lineLimit(1)
                    Text(portfolioVsBest.formatted(.number.precision(.fractionLength(2)).sign(strategy: .always())) + "%")
                        .font(.title2).fontWeight(.bold)
                        .foregroundColor(portfolioVsBest >= 0 ? .green : .red)
                        .blur(radius: privacyMode ? 8 : 0)
                    Text(portfolioVsBest >= 0 ? "Ahead" : "Behind")
                        .font(.caption).padding(.horizontal, 6).padding(.vertical, 2)
                        .background((portfolioVsBest >= 0 ? Color.green : Color.red).opacity(0.1))
                        .foregroundColor(portfolioVsBest >= 0 ? .green : .red)
                        .cornerRadius(4)
                }
                .padding().frame(maxWidth: .infinity, alignment: .leading).frame(height: 110)
                .background(Color(NSColor.controlBackgroundColor)).cornerRadius(10)
                .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
            }
            HStack(spacing: 16) {
                // Indices suivis
                DashboardCard(title: "Indices Tracked", value: "\(viewModel.benchmarkIndices.count)", privacyMode: .constant(false))

                // Années suivies
                DashboardCard(title: "Years Tracked", value: "\(currentYear - startYear + 1)", privacyMode: .constant(false))

                // 10k portefeuille
                VStack(alignment: .leading, spacing: 4) {
                    Text("Portfolio 10k€ Simulation").font(.subheadline).foregroundColor(.secondary).lineLimit(1)
                    Text(portfolio10k.formatted(.currency(code: "EUR").precision(.fractionLength(0))))
                        .font(.title2).fontWeight(.bold)
                        .foregroundColor(portfolio10k >= 10000 ? .green : .red)
                        .blur(radius: privacyMode ? 8 : 0)
                }
                .padding().frame(maxWidth: .infinity, alignment: .leading).frame(height: 110)
                .background(Color(NSColor.controlBackgroundColor)).cornerRadius(10)
                .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)

                // 10k best index
                VStack(alignment: .leading, spacing: 4) {
                    Text("Best Index 10k€").font(.subheadline).foregroundColor(.secondary).lineLimit(1)
                    if let best = bestIndex {
                        Text(best10k.formatted(.currency(code: "EUR").precision(.fractionLength(0))))
                            .font(.title2).fontWeight(.bold)
                            .foregroundColor(best10k >= 10000 ? .green : .red)
                            .blur(radius: privacyMode ? 8 : 0)
                        Text(best.name).font(.caption).foregroundColor(.secondary)
                    } else {
                        Text("—").font(.title2).fontWeight(.bold).foregroundColor(.secondary)
                    }
                }
                .padding().frame(maxWidth: .infinity, alignment: .leading).frame(height: 110)
                .background(Color(NSColor.controlBackgroundColor)).cornerRadius(10)
                .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
            }
        }
    }
}

// =========================================================================
// MARK: - GOAL PROGRESS BAR
// =========================================================================

struct BenchmarkGoalProgressBar: View {
    @ObservedObject var viewModel: PortfolioViewModel
    @Binding var privacyMode: Bool

    var currentYear: Int { Calendar.current.component(.year, from: Date()) }
    var startYear: Int { viewModel.dividendStartYear }
    var activeYears: [Int] { Array(startYear...currentYear) }

    var portfolioAvgReturn: Double {
        var vals: [Double] = []
        for yearData in viewModel.growthYears {
            guard yearData.year >= startYear && yearData.year <= currentYear else { continue }
            let isCurrentYear = yearData.year == currentYear
            let effectiveEnd = isCurrentYear ? viewModel.currentTotalCapital : yearData.endWallet
            let base = yearData.startWallet + yearData.invested
            guard base > 0 else { continue }
            vals.append(((effectiveEnd - base) / base) * 100.0)
        }
        guard !vals.isEmpty else { return 0 }
        return vals.reduce(0, +) / Double(vals.count)
    }

    var progress: Double {
        guard viewModel.benchmarkGoalTarget > 0 else { return 0 }
        return min(max(portfolioAvgReturn / viewModel.benchmarkGoalTarget, 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Goal : Avg. Annual Return ≥ \(viewModel.benchmarkGoalTarget.formatted(.number.precision(.fractionLength(1))))%")
                    .font(.headline)
                Spacer()
                Text("\(portfolioAvgReturn.formatted(.number.precision(.fractionLength(2)).sign(strategy: .always())))% / \(viewModel.benchmarkGoalTarget.formatted(.number.precision(.fractionLength(1))))%")
                    .font(.subheadline).fontWeight(.bold)
                    .foregroundColor(progress >= 1 ? .green : .primary)
                    .blur(radius: privacyMode ? 8 : 0)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.windowBackgroundColor)).frame(height: 14)
                    RoundedRectangle(cornerRadius: 8)
                        .fill(LinearGradient(gradient: Gradient(colors: [.blue, .purple]), startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(0, geometry.size.width * CGFloat(progress)), height: 14)
                        .animation(.spring(), value: progress)
                }
            }.frame(height: 14)
        }
        .padding().background(Color(NSColor.controlBackgroundColor)).cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        .help("Double-click to edit your Benchmark Goal")
    }
}

// =========================================================================
// MARK: - TABLE SECTION
// =========================================================================

struct BenchmarkTableSection: View {
    @ObservedObject var viewModel: PortfolioViewModel
    @Binding var showAddIndexSheet: Bool

    var currentYear: Int { Calendar.current.component(.year, from: Date()) }
    var startYear: Int { viewModel.dividendStartYear }
    var years: [Int] { Array(startYear...currentYear) }

    // Retours du portefeuille (depuis GrowthYear)
    func portfolioReturn(for year: Int) -> Double? {
        guard let yearData = viewModel.growthYears.first(where: { $0.year == year }) else { return nil }
        let isCurrentYear = year == currentYear
        let effectiveEnd = isCurrentYear ? viewModel.currentTotalCapital : yearData.endWallet
        let base = yearData.startWallet + yearData.invested
        guard base > 0 else { return nil }
        return ((effectiveEnd - base) / base) * 100.0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Performance Comparison").font(.title2).fontWeight(.bold).foregroundColor(.secondary)
                Spacer()
                Button(action: { showAddIndexSheet = true }) {
                    Label("Add Index", systemImage: "plus")
                }.buttonStyle(.borderedProminent)
            }.padding(.bottom, 4)

            VStack(spacing: 0) {
                // HEADER
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        // Colonne "Year"
                        Text("Year").fontWeight(.bold)
                            .frame(width: 60, alignment: .leading)
                            .padding(.horizontal, 8)

                        // Colonne "Portfolio"
                        HStack(spacing: 4) {
                            Circle().fill(Color.blue).frame(width: 8, height: 8)
                            Text("Portfolio").fontWeight(.bold)
                        }
                        .frame(width: 110, alignment: .trailing)
                        .padding(.horizontal, 8)

                        // Colonnes indices
                        ForEach(viewModel.benchmarkIndices.indices, id: \.self) { idx in
                            let index = viewModel.benchmarkIndices[idx]
                            HStack(spacing: 4) {
                                Circle().fill(benchmarkColors[idx % benchmarkColors.count]).frame(width: 8, height: 8)
                                Text(index.name).fontWeight(.bold).lineLimit(1)
                                Button(action: { viewModel.benchmarkIndices.remove(at: idx) }) {
                                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary.opacity(0.5)).font(.caption)
                                }.buttonStyle(.plain)
                            }
                            .frame(width: 140, alignment: .trailing)
                            .padding(.horizontal, 8)
                        }
                    }
                    .font(.subheadline).foregroundColor(.secondary)
                    .padding(.vertical, 12).padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color(NSColor.windowBackgroundColor))
                Divider()

                // ROWS
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(years, id: \.self) { year in
                            BenchmarkRowView(
                                year: year,
                                portfolioReturn: portfolioReturn(for: year),
                                viewModel: viewModel,
                                isCurrentYear: year == currentYear
                            )
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            Divider()
                        }

                        // Ligne Moyenne
                        BenchmarkAverageRowView(
                            years: years,
                            portfolioReturn: portfolioReturn,
                            viewModel: viewModel
                        )
                        .padding(.horizontal, 16).padding(.vertical, 10)
                    }
                }
            }
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))
        }
        .frame(height: 420).padding().background(Color(NSColor.controlBackgroundColor)).cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// MARK: - Benchmark Row (année)
struct BenchmarkRowView: View {
    let year: Int
    let portfolioReturn: Double?
    @ObservedObject var viewModel: PortfolioViewModel
    let isCurrentYear: Bool

    func badge(_ value: Double) -> some View {
        Text(value.formatted(.number.precision(.fractionLength(2)).sign(strategy: .always())) + "%")
            .fontWeight(.bold)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background((value >= 0 ? Color.green : Color.red).opacity(0.12))
            .foregroundColor(value >= 0 ? .green : .red)
            .cornerRadius(4)
            .font(.system(size: 13))
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                // Année
                HStack(spacing: 4) {
                    Text(String(year)).fontWeight(.bold)
                    if isCurrentYear {
                        Text("live").font(.caption2).padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Color.blue.opacity(0.15)).foregroundColor(.blue).cornerRadius(3)
                    }
                }
                .frame(width: 60, alignment: .leading).padding(.horizontal, 8)

                // Portfolio
                Group {
                    if let ret = portfolioReturn {
                        badge(ret)
                    } else {
                        Text("—").foregroundColor(.secondary)
                    }
                }
                .frame(width: 110, alignment: .trailing).padding(.horizontal, 8)

                // Indices — cellules éditables
                ForEach(viewModel.benchmarkIndices.indices, id: \.self) { idx in
                    BenchmarkReturnCell(index: $viewModel.benchmarkIndices[idx], year: year, color: benchmarkColors[idx % benchmarkColors.count])
                        .frame(width: 140, alignment: .trailing).padding(.horizontal, 8)
                }
            }
        }
    }
}

// MARK: - Cellule éditable pour un indice
struct BenchmarkReturnCell: View {
    @Binding var index: BenchmarkIndex
    let year: Int
    let color: Color

    @State private var editMode = false
    @State private var inputText: String = ""

    var currentValue: Double? { index.returns[year] }

    var body: some View {
        Group {
            if editMode {
                TextField("0.00", text: $inputText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                    .onSubmit { commit() }
                    .onExitCommand { editMode = false }
            } else {
                if let val = currentValue {
                    Text(val.formatted(.number.precision(.fractionLength(2)).sign(strategy: .always())) + "%")
                        .fontWeight(.bold)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background((val >= 0 ? Color.green : Color.red).opacity(0.12))
                        .foregroundColor(val >= 0 ? color : .red)
                        .cornerRadius(4)
                        .font(.system(size: 13))
                        .onTapGesture { startEdit() }
                } else {
                    Text("—")
                        .foregroundColor(.secondary.opacity(0.5))
                        .onTapGesture { startEdit() }
                }
            }
        }
    }

    func startEdit() {
        inputText = currentValue.map { String(format: "%.2f", $0) } ?? ""
        editMode = true
    }

    func commit() {
        let cleaned = inputText.replacingOccurrences(of: ",", with: ".")
        if let val = Double(cleaned) {
            index.returns[year] = val
        } else if inputText.isEmpty {
            index.returns.removeValue(forKey: year)
        }
        editMode = false
    }
}

// MARK: - Ligne Moyenne
struct BenchmarkAverageRowView: View {
    let years: [Int]
    let portfolioReturn: (Int) -> Double?
    @ObservedObject var viewModel: PortfolioViewModel

    var portfolioAvg: Double {
        let vals = years.compactMap { portfolioReturn($0) }
        guard !vals.isEmpty else { return 0 }
        return vals.reduce(0, +) / Double(vals.count)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                Text("Avg.").fontWeight(.bold).italic()
                    .frame(width: 60, alignment: .leading).padding(.horizontal, 8)

                // Portfolio avg
                Text(portfolioAvg.formatted(.number.precision(.fractionLength(2)).sign(strategy: .always())) + "%")
                    .fontWeight(.bold).foregroundColor(portfolioAvg >= 0 ? .green : .red)
                    .frame(width: 110, alignment: .trailing).padding(.horizontal, 8)

                // Indices avg
                ForEach(viewModel.benchmarkIndices.indices, id: \.self) { idx in
                    let avg = viewModel.benchmarkIndices[idx].averageReturn(years: years)
                    Text(avg.formatted(.number.precision(.fractionLength(2)).sign(strategy: .always())) + "%")
                        .fontWeight(.bold)
                        .foregroundColor(avg >= 0 ? benchmarkColors[idx % benchmarkColors.count] : .red)
                        .frame(width: 140, alignment: .trailing).padding(.horizontal, 8)
                }
            }
        }
        .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
    }
}

// =========================================================================
// MARK: - CHARTS SECTION
// =========================================================================

struct BenchmarkChartsSection: View {
    @ObservedObject var viewModel: PortfolioViewModel
    @Binding var chartToZoom: BenchmarkChartZoomType?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Performance Analytics").font(.title2).fontWeight(.bold).foregroundColor(.secondary)
            HStack(spacing: 24) {
                BenchmarkAnnualBarsChart(viewModel: viewModel, expandedChart: $chartToZoom)
                BenchmarkGrowth10kChart(viewModel: viewModel, expandedChart: $chartToZoom)
            }
        }
    }
}

// =========================================================================
// MARK: - CHART 1 : BARRES ANNUELLES %
// =========================================================================

struct BenchmarkAnnualBarsChart: View {
    @ObservedObject var viewModel: PortfolioViewModel
    var isExpanded: Bool = false
    @Binding var expandedChart: BenchmarkChartZoomType?

    var currentYear: Int { Calendar.current.component(.year, from: Date()) }
    var startYear: Int { viewModel.dividendStartYear }
    var years: [Int] { Array(startYear...currentYear) }

    struct BarItem: Identifiable {
        let id = UUID()
        let year: Int
        let label: String   // "Portfolio", index name
        let value: Double
        let color: Color
    }

    var portfolioReturns: [Int: Double] {
        var dict: [Int: Double] = [:]
        for yearData in viewModel.growthYears {
            guard yearData.year >= startYear && yearData.year <= currentYear else { continue }
            let isCurrentYear = yearData.year == currentYear
            let effectiveEnd = isCurrentYear ? viewModel.currentTotalCapital : yearData.endWallet
            let base = yearData.startWallet + yearData.invested
            guard base > 0 else { continue }
            dict[yearData.year] = ((effectiveEnd - base) / base) * 100.0
        }
        return dict
    }

    var items: [BarItem] {
        var result: [BarItem] = []
        for year in years {
            // Portfolio
            result.append(BarItem(year: year, label: "Portfolio", value: portfolioReturns[year] ?? 0, color: .blue))
            // Indices
            for (idx, index) in viewModel.benchmarkIndices.enumerated() {
                result.append(BarItem(year: year, label: index.name, value: index.returns[year] ?? 0, color: benchmarkColors[idx % benchmarkColors.count]))
            }
        }
        return result
    }

    @State private var hiddenSeries: Set<String> = []
    @State private var hoveredYear: String? = nil

    var seriesLabels: [String] {
        var labels = ["Portfolio"]
        labels += viewModel.benchmarkIndices.map { $0.name }
        return labels
    }

    func color(for label: String) -> Color {
        if label == "Portfolio" { return .blue }
        if let idx = viewModel.benchmarkIndices.firstIndex(where: { $0.name == label }) {
            return benchmarkColors[idx % benchmarkColors.count]
        }
        return .gray
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if !isExpanded { Text("Annual Return (%)").font(.headline).foregroundColor(.secondary) }
                Spacer()
                InteractiveLegendView(items: seriesLabels, colorMap: color, hiddenItems: $hiddenSeries)
                if !isExpanded {
                    Button(action: { expandedChart = .annualBars }) {
                        Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary)
                    }.buttonStyle(.plain).padding(.leading, 8)
                }
            }

            // Tooltip
            if let y = hoveredYear, let yr = Int(y) {
                HStack(spacing: 12) {
                    Text(String(yr)).fontWeight(.bold)
                    ForEach(seriesLabels.filter { !hiddenSeries.contains($0) }, id: \.self) { label in
                        let val: Double = {
                            if label == "Portfolio" { return portfolioReturns[yr] ?? 0 }
                            return viewModel.benchmarkIndices.first(where: { $0.name == label })?.returns[yr] ?? 0
                        }()
                        HStack(spacing: 4) {
                            Circle().fill(color(for: label)).frame(width: 7, height: 7)
                            Text(val.formatted(.number.precision(.fractionLength(2)).sign(strategy: .always())) + "%")
                                .foregroundColor(val >= 0 ? .green : .red).fontWeight(.semibold)
                        }
                    }
                }
                .font(.caption)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color(NSColor.windowBackgroundColor)).cornerRadius(6)
                .transition(.opacity)
            }

            if items.isEmpty {
                Spacer()
                Text("Add indices and fill in the table to see this chart.")
                    .foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                Chart {
                    ForEach(items.filter { !hiddenSeries.contains($0.label) }) { item in
                        BarMark(
                            x: .value("Year", String(item.year)),
                            y: .value("Return %", item.value),
                            width: .ratio(0.7)
                        )
                        .foregroundStyle(item.color.opacity(item.value >= 0 ? 0.7 : 0.5))
                        .position(by: .value("Index", item.label))
                        .cornerRadius(3)
                        .opacity(hoveredYear == nil || hoveredYear == String(item.year) ? 1.0 : 0.4)
                    }

                    // Ligne zéro
                    RuleMark(y: .value("Zero", 0)).foregroundStyle(Color.secondary.opacity(0.3))
                        .lineStyle(StrokeStyle(lineWidth: 1))

                    // Règle verticale survol
                    if let y = hoveredYear {
                        RuleMark(x: .value("Year", y))
                            .foregroundStyle(Color.secondary.opacity(0.3))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                }
                .chartXSelection(value: $hoveredYear)
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine(); AxisTick()
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(v.formatted(.number.precision(.fractionLength(0)).sign(strategy: .always())) + "%").font(.system(size: 10))
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisValueLabel { if let s = value.as(String.self) { Text(s).font(.caption) } }
                    }
                }
                .animation(.easeInOut(duration: 0.1), value: hoveredYear)
            }
            BlueChipWatermark()
        }
        .padding()
        .frame(minHeight: isExpanded ? 500 : 320, maxHeight: isExpanded ? .infinity : 320)
        .background(Color(NSColor.controlBackgroundColor)).cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// =========================================================================
// MARK: - CHART 2 : SIMULATION 10 000 €
// =========================================================================

struct BenchmarkGrowth10kChart: View {
    @ObservedObject var viewModel: PortfolioViewModel
    var isExpanded: Bool = false
    @Binding var expandedChart: BenchmarkChartZoomType?

    var currentYear: Int { Calendar.current.component(.year, from: Date()) }
    var startYear: Int { viewModel.dividendStartYear }
    var years: [Int] { Array(startYear...currentYear) }

    struct LinePoint: Identifiable {
        let id = UUID()
        let year: Int
        let label: String
        let value: Double
        let color: Color
    }

    var portfolioReturns: [Int: Double] {
        var dict: [Int: Double] = [:]
        for yearData in viewModel.growthYears {
            guard yearData.year >= startYear && yearData.year <= currentYear else { continue }
            let isCurrentYear = yearData.year == currentYear
            let effectiveEnd = isCurrentYear ? viewModel.currentTotalCapital : yearData.endWallet
            let base = yearData.startWallet + yearData.invested
            guard base > 0 else { continue }
            dict[yearData.year] = ((effectiveEnd - base) / base) * 100.0
        }
        return dict
    }

    var lineData: [LinePoint] {
        var result: [LinePoint] = []

        // Portfolio
        var portfolioVal = 10000.0
        for year in years {
            portfolioVal *= (1 + (portfolioReturns[year] ?? 0) / 100.0)
            result.append(LinePoint(year: year, label: "Portfolio", value: portfolioVal, color: .blue))
        }

        // Indices
        for (idx, index) in viewModel.benchmarkIndices.enumerated() {
            var val = 10000.0
            for year in years {
                val *= (1 + (index.returns[year] ?? 0) / 100.0)
                result.append(LinePoint(year: year, label: index.name, value: val, color: benchmarkColors[idx % benchmarkColors.count]))
            }
        }
        return result
    }

    @State private var hiddenSeries: Set<String> = []
    @State private var hoveredYear: String? = nil

    var seriesLabels: [String] {
        var labels = ["Portfolio"]
        labels += viewModel.benchmarkIndices.map { $0.name }
        return labels
    }

    func color(for label: String) -> Color {
        if label == "Portfolio" { return .blue }
        if let idx = viewModel.benchmarkIndices.firstIndex(where: { $0.name == label }) {
            return benchmarkColors[idx % benchmarkColors.count]
        }
        return .gray
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if !isExpanded { Text("€10,000 Simulated Growth").font(.headline).foregroundColor(.secondary) }
                Spacer()
                InteractiveLegendView(items: seriesLabels, colorMap: color, hiddenItems: $hiddenSeries)
                if !isExpanded {
                    Button(action: { expandedChart = .growth10k }) {
                        Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary)
                    }.buttonStyle(.plain).padding(.leading, 8)
                }
            }

            // Tooltip
            if let y = hoveredYear, let yr = Int(y) {
                HStack(spacing: 12) {
                    Text(String(yr)).fontWeight(.bold)
                    ForEach(seriesLabels.filter { !hiddenSeries.contains($0) }, id: \.self) { label in
                        let val = lineData.first(where: { $0.year == yr && $0.label == label })?.value ?? 0
                        HStack(spacing: 4) {
                            Circle().fill(color(for: label)).frame(width: 7, height: 7)
                            Text(val.formatted(.currency(code: "EUR").precision(.fractionLength(0))))
                                .foregroundColor(val >= 10000 ? .green : .red).fontWeight(.semibold)
                        }
                    }
                }
                .font(.caption)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color(NSColor.windowBackgroundColor)).cornerRadius(6)
                .transition(.opacity)
            }

            if lineData.isEmpty {
                Spacer()
                Text("Add indices and fill in the table to see this chart.")
                    .foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                Chart {
                    // Ligne de référence 10 000 €
                    RuleMark(y: .value("10k", 10000))
                        .foregroundStyle(Color.secondary.opacity(0.25))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))

                    ForEach(lineData.filter { !hiddenSeries.contains($0.label) }) { point in
                        LineMark(
                            x: .value("Year", String(point.year)),
                            y: .value("€", point.value),
                            series: .value("Series", point.label)
                        )
                        .foregroundStyle(point.color)
                        .lineStyle(StrokeStyle(lineWidth: point.label == "Portfolio" ? 3 : 2))
                        .interpolationMethod(.monotone)
                        .symbol { Circle().fill(point.color).frame(width: 7, height: 7) }
                        .opacity(hoveredYear == nil || hoveredYear == String(point.year) ? 1.0 : 0.85)
                    }

                    // Règle verticale survol
                    if let y = hoveredYear {
                        RuleMark(x: .value("Year", y))
                            .foregroundStyle(Color.secondary.opacity(0.3))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                }
                .chartXSelection(value: $hoveredYear)
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine(); AxisTick()
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(v.formatted(.currency(code: "EUR").precision(.fractionLength(0)))).font(.system(size: 10))
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisValueLabel { if let s = value.as(String.self) { Text(s).font(.caption) } }
                    }
                }
                .animation(.easeInOut(duration: 0.1), value: hoveredYear)
            }
            BlueChipWatermark()
        }
        .padding()
        .frame(minHeight: isExpanded ? 500 : 320, maxHeight: isExpanded ? .infinity : 320)
        .background(Color(NSColor.controlBackgroundColor)).cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// =========================================================================
// MARK: - FULLSCREEN
// =========================================================================

struct BenchmarkFullScreenChartView: View {
    @Environment(\.dismiss) var dismiss
    let zoomType: BenchmarkChartZoomType
    @ObservedObject var viewModel: PortfolioViewModel

    var chartTitle: String {
        switch zoomType {
        case .annualBars: return "Annual Return (%)"
        case .growth10k:  return "€10,000 Simulated Growth"
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
            case .annualBars: BenchmarkAnnualBarsChart(viewModel: viewModel, isExpanded: true, expandedChart: .constant(nil))
            case .growth10k:  BenchmarkGrowth10kChart(viewModel: viewModel, isExpanded: true, expandedChart: .constant(nil))
            }
        }.padding(30).frame(minWidth: 900, minHeight: 700)
    }
}
