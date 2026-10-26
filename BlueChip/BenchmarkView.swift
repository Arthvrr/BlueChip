import SwiftUI
import Charts
import SwiftData // <-- NOUVEAU
import Combine
import Combine

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
    
    @State private var editingIndex: BenchmarkIndex? = nil
    
    var currentYear: Int { Calendar.current.component(.year, from: Date()) }
    var startYear: Int { viewModel.dividendStartYear }
    var activeYears: [Int] { Array(startYear...currentYear) }
    
    // NOUVEAU : Calcul dynamique de la valeur courante pour le Goal
    var currentGoalValueForProgressBar: Double {
        let bestIndex = viewModel.benchmarkIndices.max { $0.averageReturn(years: activeYears) < $1.averageReturn(years: activeYears) }
        
        switch viewModel.benchmarkGoalType {
        case .averageAlpha:
            let portfolioAvgReturn: Double = {
                var vals: [Double] = []
                for year in activeYears {
                    guard let yearData = viewModel.growthYears.first(where: { $0.year == year }) else { vals.append(0); continue }
                    let isCurrentYear = year == currentYear
                    let effectiveEnd = isCurrentYear ? viewModel.currentTotalCapital : yearData.endWallet
                    let base = yearData.startWallet + yearData.invested
                    vals.append(base > 0 ? ((effectiveEnd - base) / base) * 100.0 : 0)
                }
                guard !vals.isEmpty else { return 0 }
                return vals.reduce(0, +) / Double(vals.count)
            }()
            let bestAvg = bestIndex?.averageReturn(years: activeYears) ?? 0
            return portfolioAvgReturn - bestAvg
            
        case .currentYearAlpha:
            let portfolioCurrentYear: Double = {
                guard let yearData = viewModel.growthYears.first(where: { $0.year == currentYear }) else { return 0 }
                let base = yearData.startWallet + yearData.invested
                return base > 0 ? ((viewModel.currentTotalCapital - base) / base) * 100.0 : 0
            }()
            let bestCurrentYear = bestIndex?.returns[currentYear] ?? 0
            return portfolioCurrentYear - bestCurrentYear
            
        case .positiveAlphaYears:
            var positiveYearsCount = 0
            for year in activeYears {
                let pReturn: Double = {
                    guard let yearData = viewModel.growthYears.first(where: { $0.year == year }) else { return 0 }
                    let isCurrentYear = year == currentYear
                    let effectiveEnd = isCurrentYear ? viewModel.currentTotalCapital : yearData.endWallet
                    let base = yearData.startWallet + yearData.invested
                    return base > 0 ? ((effectiveEnd - base) / base) * 100.0 : 0
                }()
                let iReturn = bestIndex?.returns[year] ?? 0
                if (pReturn - iReturn) > 0 { positiveYearsCount += 1 }
            }
            return Double(positiveYearsCount)
        }
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 24) {
                BenchmarkDashboardSection(viewModel: viewModel, privacyMode: $privacyMode)

                // -----------------------------------------------------------
                // NOUVEAU : Utilisation du composant universel GoalProgressBar
                // -----------------------------------------------------------
                GoalProgressBar(
                    title: viewModel.benchmarkGoalType.rawValue,
                    currentValue: currentGoalValueForProgressBar,
                    targetValue: viewModel.benchmarkGoalTarget,
                    privacyMode: $privacyMode,
                    currency: $viewModel.preferredCurrency,
                    isPercentage: viewModel.benchmarkGoalType != .positiveAlphaYears,
                    isCount: viewModel.benchmarkGoalType == .positiveAlphaYears // <-- NOUVEAU
                )
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { showGoalSheet = true }

                BenchmarkTableSection(viewModel: viewModel, privacyMode: $privacyMode, showAddIndexSheet: $showAddIndexSheet, onEditIndex: { editingIndex = $0 })

                BenchmarkChartsSection(viewModel: viewModel, privacyMode: $privacyMode, chartToZoom: $chartToZoom)
            }
            .padding()
        }
        .sheet(isPresented: $showGoalSheet) { EditBenchmarkGoalView(viewModel: viewModel) }
        .sheet(isPresented: $showAddIndexSheet) { AddBenchmarkIndexView(viewModel: viewModel) }
        .sheet(item: $chartToZoom) { type in BenchmarkFullScreenChartView(zoomType: type, viewModel: viewModel, privacyMode: $privacyMode) }
        .sheet(item: $editingIndex) { idx in EditBenchmarkIndexView(viewModel: viewModel, index: idx)}
    }
}

// =========================================================================
// MARK: - GOAL FORM (Dédié au Benchmark - Design Uniformisé)
// =========================================================================

struct EditBenchmarkGoalView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: PortfolioViewModel
    @State private var selectedGoal: BenchmarkGoalType
    @State private var targetInput: Double

    init(viewModel: PortfolioViewModel) {
        self.viewModel = viewModel
        _selectedGoal = State(initialValue: viewModel.benchmarkGoalType)
        _targetInput = State(initialValue: viewModel.benchmarkGoalTarget)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Set Alpha Goal").font(.title2).fontWeight(.bold)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill").font(.title2).foregroundColor(.secondary)
                }.buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            VStack(alignment: .leading, spacing: 16) {
                GroupBox {
                    VStack(spacing: 16) {
                        HStack {
                            Text("Goal Type:")
                            Spacer()
                            Picker("", selection: $selectedGoal) {
                                ForEach(BenchmarkGoalType.allCases, id: \.self) { type in Text(type.rawValue).tag(type) }
                            }
                            .labelsHidden()
                            .frame(width: 250)
                        }
                        
                        Divider().opacity(0.5)
                        
                        HStack {
                            Text("Target Amount:")
                            Spacer()
                            TextField("e.g. 2.5", value: $targetInput, format: .number)
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
            
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save Goal") {
                    viewModel.benchmarkGoalType = selectedGoal
                    viewModel.benchmarkGoalTarget = targetInput
                    dismiss()
                }
                .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }.padding()
        }
        .frame(width: 440, height: 280) // Taille unifiée
    }
}

// =========================================================================
// MARK: - ADD INDEX FORM
// =========================================================================

struct AddBenchmarkIndexView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: PortfolioViewModel
    @State private var name: String = ""
    @State private var referenceLink: String = "" // <-- NOUVEAU

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add New Index").font(.title2).fontWeight(.bold)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill").font(.title2).foregroundColor(.secondary)
                }.buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            VStack(alignment: .leading, spacing: 16) {
                Text("Add a stock market index to compare your portfolio's performance against it.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Index Name")
                            TextField("e.g. S&P 500, MSCI World...", text: $name)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        // NOUVEAU : Champ pour le lien personnalisé
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Performance Link (Optional)")
                            TextField("e.g. https://finance.yahoo.com/quote/%5EGSPC", text: $referenceLink)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }
            }
            .padding()
            
            Spacer()
            Divider()
            
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add Index") {
                    guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    // NOUVEAU : On passe le lien configuré à la création
                    viewModel.addBenchmarkIndex(BenchmarkIndex(name: name, returns: [:], referenceLink: referenceLink))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }.padding()
        }
        .frame(width: 400, height: 330) // <-- Hauteur légèrement augmentée
    }
}

struct EditBenchmarkIndexView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: PortfolioViewModel
    let index: BenchmarkIndex
    
    @State private var name: String = ""
    @State private var referenceLink: String = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Edit Index").font(.title2).fontWeight(.bold)
                Spacer()
                Button(action: { dismiss() }) { Image(systemName: "xmark.circle.fill").font(.title2).foregroundColor(.secondary) }.buttonStyle(.plain)
            }.padding()
            Divider()
            
            VStack(alignment: .leading, spacing: 16) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Index Name")
                            TextField("e.g. S&P 500", text: $name).textFieldStyle(.roundedBorder)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Performance Link (Optional)")
                            TextField("URL", text: $referenceLink).textFieldStyle(.roundedBorder)
                        }
                    }
                }
            }.padding()
            
            Spacer()
            Divider()
            
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                // Bouton de suppression
                Button("Delete Index") {
                    viewModel.deleteBenchmarkIndex(id: index.id)
                    dismiss()
                }.foregroundColor(.red).padding(.trailing, 16)
                
                Button("Save") {
                    guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    index.name = name
                    index.referenceLink = referenceLink
                    viewModel.objectWillChange.send()
                    dismiss()
                }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }.padding()
        }
        .frame(width: 400, height: 330)
        .onAppear {
            name = index.name
            referenceLink = index.referenceLink
        }
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

    var allYears: [Int] { Array(startYear...currentYear) }

    var portfolioReturns: [Int: Double] {
        var dict: [Int: Double] = [:]
        for year in allYears {
            guard let yearData = viewModel.growthYears.first(where: { $0.year == year }) else {
                dict[year] = 0; continue
            }
            let isCurrentYear = year == currentYear
            let effectiveEnd = isCurrentYear ? viewModel.currentTotalCapital : yearData.endWallet
            let base = yearData.startWallet + yearData.invested
            if base > 0 {
                dict[year] = ((effectiveEnd - base) / base) * 100.0
            } else {
                dict[year] = 0
            }
        }
        return dict
    }

    var portfolioAvgReturn: Double {
        let vals = allYears.map { portfolioReturns[$0] ?? 0 }
        guard !vals.isEmpty else { return 0 }
        return vals.reduce(0, +) / Double(vals.count)
    }

    var portfolioCurrentYear: Double { portfolioReturns[currentYear] ?? 0 }

    var bestIndex: BenchmarkIndex? {
        viewModel.benchmarkIndices.max { a, b in
            a.averageReturn(years: allYears) < b.averageReturn(years: allYears)
        }
    }

    var portfolioVsBest: Double {
        guard let best = bestIndex else { return 0 }
        return portfolioAvgReturn - best.averageReturn(years: allYears)
    }

    var portfolio10k: Double {
        var value = 10000.0
        for y in allYears { value *= (1 + (portfolioReturns[y] ?? 0) / 100.0) }
        return value
    }

    var best10k: Double {
        guard let best = bestIndex else { return 0 }
        var value = 10000.0
        for y in allYears { value *= (1 + (best.returns[y] ?? 0) / 100.0) }
        return value
    }

    var body: some View {
        let sym = AppCurrency(rawValue: viewModel.preferredCurrency)?.symbol ?? "€"
        
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Portfolio Return \(String(currentYear))").font(.subheadline).foregroundColor(.secondary).lineLimit(1)
                    Text(portfolioCurrentYear.formatted(.number.precision(.fractionLength(2)).sign(strategy: .always())) + "%")
                        .font(.title2).fontWeight(.bold)
                        .foregroundColor(.primary) // <-- Modifié en noir
                        .blur(radius: privacyMode ? 6 : 0)
                }
                .padding().frame(maxWidth: .infinity, alignment: .leading).frame(height: 110)
                .background(Color(NSColor.controlBackgroundColor)).cornerRadius(10)
                .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Portfolio Avg. Return").font(.subheadline).foregroundColor(.secondary).lineLimit(1)
                    Text(portfolioAvgReturn.formatted(.number.precision(.fractionLength(2)).sign(strategy: .always())) + "%")
                        .font(.title2).fontWeight(.bold)
                        .foregroundColor(.primary) // <-- Modifié en noir
                        .blur(radius: privacyMode ? 6 : 0)
                }
                .padding().frame(maxWidth: .infinity, alignment: .leading).frame(height: 110)
                .background(Color(NSColor.controlBackgroundColor)).cornerRadius(10)
                .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Best Index (Avg.)").font(.subheadline).foregroundColor(.secondary).lineLimit(1)
                    if let best = bestIndex {
                        Text(best.name).font(.title2).fontWeight(.bold).lineLimit(1).minimumScaleFactor(0.7)
                            .blur(radius: privacyMode ? 6 : 0)
                        Text(best.averageReturn(years: allYears).formatted(.number.precision(.fractionLength(2)).sign(strategy: .always())) + "%")
                            .font(.caption).foregroundColor(.secondary)
                            .blur(radius: privacyMode ? 6 : 0)
                    } else {
                        Text("—").font(.title2).fontWeight(.bold).foregroundColor(.secondary)
                    }
                }
                .padding().frame(maxWidth: .infinity, alignment: .leading).frame(height: 110)
                .background(Color(NSColor.controlBackgroundColor)).cornerRadius(10)
                .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)

                VStack(alignment: .leading, spacing: 4) {
                    Text("vs Best Index (Avg.)").font(.subheadline).foregroundColor(.secondary).lineLimit(1)
                    Text(portfolioVsBest.formatted(.number.precision(.fractionLength(2)).sign(strategy: .always())) + "%")
                        .font(.title2).fontWeight(.bold)
                        .foregroundColor(.primary) // <-- Modifié en noir
                        .blur(radius: privacyMode ? 6 : 0)
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
                DashboardCard(title: "Indices Tracked", value: "\(viewModel.benchmarkIndices.count)", titleIcon: nil, privacyMode: $privacyMode)
                DashboardCard(title: "Years Tracked", value: "\(currentYear - startYear + 1)", titleIcon: nil, privacyMode: $privacyMode)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Portfolio 10k\(sym) Simulation").font(.subheadline).foregroundColor(.secondary).lineLimit(1)
                    Text(portfolio10k.formatted(.currency(code: viewModel.preferredCurrency).precision(.fractionLength(0))))
                        .font(.title2).fontWeight(.bold)
                        .foregroundColor(.primary) // <-- Modifié en noir
                        .blur(radius: privacyMode ? 6 : 0)
                }
                .padding().frame(maxWidth: .infinity, alignment: .leading).frame(height: 110)
                .background(Color(NSColor.controlBackgroundColor)).cornerRadius(10)
                .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Best Index 10k\(sym)").font(.subheadline).foregroundColor(.secondary).lineLimit(1)
                    if let best = bestIndex {
                        Text(best10k.formatted(.currency(code: viewModel.preferredCurrency).precision(.fractionLength(0))))
                            .font(.title2).fontWeight(.bold)
                            .foregroundColor(.primary) // <-- Modifié en noir
                            .blur(radius: privacyMode ? 6 : 0)
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
// MARK: - TABLE SECTION
// =========================================================================

struct BenchmarkTableSection: View {
    @ObservedObject var viewModel: PortfolioViewModel
    @Binding var privacyMode: Bool
    @Binding var showAddIndexSheet: Bool

    var currentYear: Int { Calendar.current.component(.year, from: Date()) }
    var startYear: Int { viewModel.dividendStartYear }
    var years: [Int] { Array(startYear...currentYear) }
    
    let onEditIndex: (BenchmarkIndex) -> Void

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
                HStack(spacing: 12) {
                    Text("Year").fontWeight(.bold).foregroundColor(.primary)
                        .frame(width: 60, alignment: .leading)

                    HStack(spacing: 4) {
                        Text("Portfolio").fontWeight(.bold).foregroundColor(.primary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)

                    ForEach(viewModel.benchmarkIndices.indices, id: \.self) { idx in
                        let index = viewModel.benchmarkIndices[idx]
                        HStack(spacing: 4) {
                            Text(index.name).fontWeight(.bold).lineLimit(1).foregroundColor(.primary)
                                .contentShape(Rectangle())
                                .onTapGesture(count: 2) {
                                    onEditIndex(index)
                                }
                            
                            if !index.referenceLink.isEmpty, let url = URL(string: index.referenceLink) {
                                Link(destination: url) {
                                    Image(systemName: "safari").foregroundColor(.primary).font(.system(size: 10))
                                }.help("View index performance")
                                
                                Button(action: {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                                }) {
                                    Image(systemName: "doc.on.clipboard").foregroundColor(.primary).font(.system(size: 10))
                                }.buttonStyle(.plain).help("Copy configured link")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .font(.subheadline)
                .padding(.vertical, 12).padding(.horizontal, 16)
                .background(Color(NSColor.windowBackgroundColor))
                
                Divider()

                VStack(spacing: 0) {
                    ForEach(years, id: \.self) { year in
                        BenchmarkRowView(
                            year: year,
                            portfolioReturn: portfolioReturn(for: year),
                            viewModel: viewModel,
                            isCurrentYear: year == currentYear,
                            privacyMode: $privacyMode
                        )
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        Divider()
                    }

                    BenchmarkAverageRowView(
                        years: years,
                        portfolioReturn: portfolioReturn,
                        viewModel: viewModel,
                        privacyMode: $privacyMode
                    )
                    .padding(.horizontal, 16).padding(.vertical, 12)
                }
            }
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))
        }
        .padding().background(Color(NSColor.controlBackgroundColor)).cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// MARK: - Benchmark Row (année)
struct BenchmarkRowView: View {
    let year: Int
    let portfolioReturn: Double?
    @ObservedObject var viewModel: PortfolioViewModel
    let isCurrentYear: Bool
    @Binding var privacyMode: Bool

    func badge(_ value: Double) -> some View {
        Text(value.formatted(.number.precision(.fractionLength(2)).sign(strategy: .always())) + "%")
            .fontWeight(.bold)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background((value >= 0 ? Color.green : Color.red).opacity(0.12))
            .foregroundColor(value >= 0 ? .green : .red)
            .cornerRadius(4)
            .font(.system(size: 13))
            .blur(radius: privacyMode ? 6 : 0)
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(String(year))
                .fontWeight(.bold)
                .frame(width: 60, alignment: .leading)

            Group {
                if let ret = portfolioReturn {
                    badge(ret)
                } else {
                    Text("—").foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)

            ForEach(viewModel.benchmarkIndices.indices, id: \.self) { idx in
                BenchmarkReturnCell(
                    index: viewModel.benchmarkIndices[idx],
                    year: year,
                    color: benchmarkColors[idx % benchmarkColors.count],
                    privacyMode: $privacyMode,
                    onUpdate: { viewModel.objectWillChange.send() }
                )
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }
}

// MARK: - Cellule éditable pour un indice
struct BenchmarkReturnCell: View {
    @Bindable var index: BenchmarkIndex
    let year: Int
    let color: Color
    @Binding var privacyMode: Bool
    var onUpdate: (() -> Void)? = nil

    @State private var editMode = false
    @State private var inputText: String = ""

    var currentValue: Double? { index.returns[year] }

    var body: some View {
        Group {
            if editMode {
                TextField("0.00", text: $inputText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
                    .multilineTextAlignment(.center)
                    .onSubmit { commit() }
                    .onExitCommand { editMode = false }
            } else {
                if let val = currentValue {
                    Text(val.formatted(.number.precision(.fractionLength(2)).sign(strategy: .always())) + "%")
                        .foregroundColor(.primary) // <-- NOUVEAU: Noir et non-gras (system font)
                        .font(.system(size: 13))
                        .blur(radius: privacyMode ? 6 : 0)
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
        onUpdate?()
        editMode = false
    }
}

// MARK: - Ligne Moyenne
struct BenchmarkAverageRowView: View {
    let years: [Int]
    let portfolioReturn: (Int) -> Double?
    @ObservedObject var viewModel: PortfolioViewModel
    @Binding var privacyMode: Bool

    var portfolioAvg: Double {
        let vals = years.map { portfolioReturn($0) ?? 0 }
        guard !vals.isEmpty else { return 0 }
        return vals.reduce(0, +) / Double(vals.count)
    }

    var body: some View {
        HStack(spacing: 12) {
            Text("Avg.").fontWeight(.bold).italic()
                .frame(width: 60, alignment: .leading)

            Text(portfolioAvg.formatted(.number.precision(.fractionLength(2)).sign(strategy: .always())) + "%")
                .fontWeight(.bold).foregroundColor(portfolioAvg >= 0 ? .green : .red)
                .blur(radius: privacyMode ? 6 : 0)
                .frame(maxWidth: .infinity, alignment: .center)

            ForEach(viewModel.benchmarkIndices.indices, id: \.self) { idx in
                let avg = viewModel.benchmarkIndices[idx].averageReturn(years: years)
                
                Text(avg.formatted(.number.precision(.fractionLength(2)).sign(strategy: .always())) + "%")
                    .foregroundColor(.primary) // <-- NOUVEAU: Noir et non-gras
                    .font(.system(size: 13))
                    .blur(radius: privacyMode ? 6 : 0)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }
}

// =========================================================================
// MARK: - CHARTS SECTION
// =========================================================================

struct BenchmarkChartsSection: View {
    @ObservedObject var viewModel: PortfolioViewModel
    @Binding var privacyMode: Bool
    @Binding var chartToZoom: BenchmarkChartZoomType?

    var body: some View {
        let sym = AppCurrency(rawValue: viewModel.preferredCurrency)?.symbol ?? "€"
        VStack(alignment: .leading, spacing: 12) {
            Text("Performance Analytics").font(.title2).fontWeight(.bold).foregroundColor(.secondary)
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading) {
                    //HStack { Text("Annual Return (%)").font(.headline).foregroundColor(.secondary); Spacer() }
                    BenchmarkAnnualBarsChart(viewModel: viewModel, privacyMode: $privacyMode, expandedChart: $chartToZoom)
                }
                VStack(alignment: .leading) {
                    //HStack { Text("\(sym)10,000 Simulated Growth").font(.headline).foregroundColor(.secondary); Spacer() }
                    BenchmarkGrowth10kChart(viewModel: viewModel, privacyMode: $privacyMode, expandedChart: $chartToZoom)
                }
            }
        }
    }
}

// =========================================================================
// MARK: - CHART 1 : BARRES ANNUELLES %
// =========================================================================

struct BenchmarkAnnualBarsChart: View {
    @ObservedObject var viewModel: PortfolioViewModel
    @Binding var privacyMode: Bool
    var isExpanded: Bool = false
    @Binding var expandedChart: BenchmarkChartZoomType?

    var currentYear: Int { Calendar.current.component(.year, from: Date()) }
    var startYear: Int { viewModel.dividendStartYear }
    var years: [Int] { Array(startYear...currentYear) }

    struct BarItem: Identifiable {
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

    var items: [BarItem] {
        var result: [BarItem] = []
        for year in years {
            result.append(BarItem(year: year, label: "Portfolio", value: portfolioReturns[year] ?? 0, color: .blue))
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
                        
                        if let y = hoveredYear, y == String(item.year) {
                            RuleMark(x: .value("Year", y)).foregroundStyle(Color.secondary.opacity(0.3)).zIndex(-1)
                        }
                    }
                    RuleMark(y: .value("Zero", 0)).foregroundStyle(Color.secondary.opacity(0.3)).lineStyle(StrokeStyle(lineWidth: 1))
                }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let location):
                                    if let year: String = proxy.value(atX: location.x) { hoveredYear = year }
                                case .ended:
                                    hoveredYear = nil
                                }
                            }
                        
                        if let y = hoveredYear, let yr = Int(y) {
                            if let xPosition = proxy.position(forX: y) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(String(yr)).font(.caption.bold())
                                    Divider()
                                    ForEach(seriesLabels.filter { !hiddenSeries.contains($0) }, id: \.self) { label in
                                        let val: Double = {
                                            if label == "Portfolio" { return portfolioReturns[yr] ?? 0 }
                                            return viewModel.benchmarkIndices.first(where: { $0.name == label })?.returns[yr] ?? 0
                                        }()
                                        HStack(spacing: 4) {
                                            Circle().fill(color(for: label)).frame(width: 7, height: 7)
                                            Text(label).font(.caption2).foregroundColor(.secondary)
                                            Spacer(minLength: 8)
                                            Text(val.formatted(.number.precision(.fractionLength(2)).sign(strategy: .always())) + "%")
                                                .font(.caption2.bold())
                                                .foregroundColor(val >= 0 ? .green : .red)
                                                .blur(radius: privacyMode ? 6 : 0)
                                        }
                                    }
                                }
                                .frame(width: 150)
                                .padding(8).background(Color(NSColor.windowBackgroundColor).opacity(0.95)).cornerRadius(8).shadow(radius: 4)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))
                                .position(x: max(85, min(geometry.size.width - 85, xPosition)), y: 60)
                            }
                        }
                    }
                }
                .chartLegend(.hidden)
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
            }
            HStack { Text("Compares annual portfolio returns vs major indices").font(.caption2).foregroundColor(.secondary); Spacer(); BlueChipWatermark() }.padding(.top, 4)
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
    @Binding var privacyMode: Bool
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

        var portfolioVal = 10000.0
        for year in years {
            portfolioVal *= (1 + (portfolioReturns[year] ?? 0) / 100.0)
            result.append(LinePoint(year: year, label: "Portfolio", value: portfolioVal, color: .blue))
        }

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
        let sym = AppCurrency(rawValue: viewModel.preferredCurrency)?.symbol ?? "€"
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if !isExpanded { Text("\(sym)10,000 Simulated Growth").font(.headline).foregroundColor(.secondary) }
                Spacer()
                InteractiveLegendView(items: seriesLabels, colorMap: color, hiddenItems: $hiddenSeries)
                if !isExpanded {
                    Button(action: { expandedChart = .growth10k }) {
                        Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary)
                    }.buttonStyle(.plain).padding(.leading, 8)
                }
            }

            if lineData.isEmpty {
                Spacer()
                Text("Add indices and fill in the table to see this chart.")
                    .foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                Chart {
                    RuleMark(y: .value("10k", 10000))
                        .foregroundStyle(Color.secondary.opacity(0.25))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))

                    ForEach(lineData.filter { !hiddenSeries.contains($0.label) }) { point in
                        LineMark(
                            x: .value("Year", String(point.year)),
                            y: .value("Value", point.value),
                            series: .value("Series", point.label)
                        )
                        .foregroundStyle(point.color)
                        .lineStyle(StrokeStyle(lineWidth: point.label == "Portfolio" ? 3 : 2))
                        .interpolationMethod(.monotone)
                        .symbol { Circle().fill(point.color).frame(width: 7, height: 7) }
                        
                        if let y = hoveredYear, y == String(point.year) {
                            RuleMark(x: .value("Year", y)).foregroundStyle(Color.secondary.opacity(0.3)).zIndex(-1)
                        }
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let location):
                                    if let year: String = proxy.value(atX: location.x) { hoveredYear = year }
                                case .ended:
                                    hoveredYear = nil
                                }
                            }
                        
                        if let y = hoveredYear, let yr = Int(y) {
                            if let xPosition = proxy.position(forX: y) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(String(yr)).font(.caption.bold())
                                    Divider()
                                    ForEach(seriesLabels.filter { !hiddenSeries.contains($0) }, id: \.self) { label in
                                        let val = lineData.first(where: { $0.year == yr && $0.label == label })?.value ?? 0
                                        HStack(spacing: 4) {
                                            Circle().fill(color(for: label)).frame(width: 7, height: 7)
                                            Text(label).font(.caption2).foregroundColor(.secondary)
                                            Spacer(minLength: 8)
                                            Text(val.formatted(.currency(code: viewModel.preferredCurrency).precision(.fractionLength(0))))
                                                .font(.caption2.bold())
                                                .foregroundColor(val >= 10000 ? .green : .red)
                                                .blur(radius: privacyMode ? 6 : 0)
                                        }
                                    }
                                }
                                .frame(width: 150)
                                .padding(8).background(Color(NSColor.windowBackgroundColor).opacity(0.95)).cornerRadius(8).shadow(radius: 4)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))
                                .position(x: max(85, min(geometry.size.width - 85, xPosition)), y: 60)
                            }
                        }
                    }
                }
                .chartLegend(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine(); AxisTick()
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(v.formatted(.currency(code: viewModel.preferredCurrency).precision(.fractionLength(0)))).font(.system(size: 10))
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisValueLabel { if let s = value.as(String.self) { Text(s).font(.caption) } }
                    }
                }
            }
            HStack { Text("Simulates \(sym)10,000 invested across the portfolio and indices").font(.caption2).foregroundColor(.secondary); Spacer(); BlueChipWatermark() }.padding(.top, 4)
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
    @Binding var privacyMode: Bool

    var chartTitle: String {
        let sym = AppCurrency(rawValue: viewModel.preferredCurrency)?.symbol ?? "€"
        switch zoomType {
        case .annualBars: return "Annual Return (%)"
        case .growth10k:  return "\(sym)10,000 Simulated Growth"
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
            case .annualBars: BenchmarkAnnualBarsChart(viewModel: viewModel, privacyMode: $privacyMode, isExpanded: true, expandedChart: .constant(nil))
            case .growth10k:  BenchmarkGrowth10kChart(viewModel: viewModel, privacyMode: $privacyMode, isExpanded: true, expandedChart: .constant(nil))
            }
        }.padding(30).frame(minWidth: 900, minHeight: 700)
    }
}
