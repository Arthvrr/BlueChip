import SwiftUI
import Charts

// MARK: - SPECIFIC ZOOM ENUM FOR GROWTH
enum GrowthChartZoomType: String, Identifiable {
    case capitalHistory, yearlyReturn
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
                
                // 1. LES 8 CASES DU DASHBOARD
                GrowthDashboardSection(viewModel: viewModel, privacyMode: $privacyMode)
                
                // 2. LA BARRE DE PROGRESSION (GOAL)
                GrowthGoalProgressBar(viewModel: viewModel, privacyMode: $privacyMode)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { showGoalSheet = true }
                
                // 3. LE TABLEAU DE SUIVI ANNUEL
                GrowthTableSection(viewModel: viewModel)
                
                // 4. PLACEHOLDER POUR LES GRAPHES
                Text("Charts Coming Soon...")
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .padding(.top, 40)
            }
            .padding()
        }
        .sheet(isPresented: $showGoalSheet) { EditGrowthGoalView(viewModel: viewModel) }
        .sheet(item: $chartToZoom) { type in GrowthFullScreenChartView(zoomType: type, viewModel: viewModel) }
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
    
    // 1. LES VRAIES VALEURS DE LA PAGE COMPOSITION
    var currentWallet: Double { viewModel.currentTotalCapital }
    var totalInvested: Double { viewModel.manuallyInvested > 0 ? viewModel.manuallyInvested : viewModel.positionsInvestedSum }
    
    var allTimeReturnEUR: Double { viewModel.totalROIValue }
    var allTimeReturnPercent: Double { viewModel.totalROIPercent }
    
    // 2. RECHERCHE DES ANNÉES ACTIVES (CORRIGÉ)
    // On prend strictement TOUTES les années depuis le début jusqu'à l'année en cours (même si elles sont à 0)
    var activeYears: [GrowthYear] {
        viewModel.growthYears.filter { $0.year <= currentYear }
    }
    
    var activeYearsCount: Int { max(1, activeYears.count) }
    
    // 3. MOYENNES
    var averageReturnEUR: Double {
        allTimeReturnEUR / Double(activeYearsCount)
    }
    
    var averageReturnPercent: Double {
        guard !activeYears.isEmpty else { return 0 }
        let totalPct = activeYears.reduce(0.0) { sum, yearData in
            let effectiveEnd = (yearData.year == currentYear) ? currentWallet : yearData.endWallet
            let base = yearData.startWallet + yearData.invested
            
            // Si la base est 0 (ex: 1ère année), le retour en % est de 0%.
            // On ajoute donc 0 à la somme, mais l'année compte bien dans le diviseur final.
            guard base > 0 else { return sum }
            
            let ret = effectiveEnd - base
            return sum + (ret / base)
        }
        return totalPct / Double(activeYearsCount)
    }
    
    // 4. CAGR
    var cagr: Double {
        pow(1.0 + allTimeReturnPercent, 1.0 / Double(activeYearsCount)) - 1.0
    }
    
    // 5. BEST YEAR
    var bestYearReturn: Double {
        let returns = activeYears.map { yearData -> Double in
            let effectiveEnd = (yearData.year == currentYear) ? currentWallet : yearData.endWallet
            let base = yearData.startWallet + yearData.invested
            guard base > 0 else { return 0 } // On retourne 0 au lieu d'ignorer pour la 1ère année
            return (effectiveEnd - base) / base
        }
        return returns.max() ?? 0
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // LIGNE 1
            HStack(spacing: 16) {
                DashboardCard(title: "Current Wallet Value", value: currentWallet.formatted(.currency(code: "EUR").precision(.fractionLength(2))), privacyMode: $privacyMode)
                DashboardCard(title: "Total Invested", value: totalInvested.formatted(.currency(code: "EUR").precision(.fractionLength(2))), privacyMode: $privacyMode)
                DashboardCard(title: "All-Time Return (€)", value: allTimeReturnEUR.formatted(.currency(code: "EUR").precision(.fractionLength(2)).sign(strategy: .always())), privacyMode: $privacyMode)
                DashboardCard(title: "All-Time Return (%)", value: allTimeReturnPercent.formatted(.percent.precision(.fractionLength(2)).sign(strategy: .always())), privacyMode: $privacyMode)
            }
            // LIGNE 2
            HStack(spacing: 16) {
                DashboardCard(title: "Avg. Return / Year (€)", value: averageReturnEUR.formatted(.currency(code: "EUR").precision(.fractionLength(2)).sign(strategy: .always())), privacyMode: $privacyMode)
                DashboardCard(title: "Avg. Return / Year (%)", value: averageReturnPercent.formatted(.percent.precision(.fractionLength(2)).sign(strategy: .always())), privacyMode: $privacyMode)
                DashboardCard(title: "CAGR (Compound Growth)", value: cagr.formatted(.percent.precision(.fractionLength(2))), privacyMode: $privacyMode)
                DashboardCard(title: "Best Year Return", value: bestYearReturn.formatted(.percent.precision(.fractionLength(2))), privacyMode: $privacyMode)
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
        
        return isPercentGoal
        ? retPercent.formatted(.percent.precision(.fractionLength(2)))
        : retAmount.formatted(.currency(code: "EUR").precision(.fractionLength(2)))
    }
    
    var targetValueString: String {
        isPercentGoal
        ? (viewModel.growthGoalTarget / 100.0).formatted(.percent.precision(.fractionLength(2)))
        : viewModel.growthGoalTarget.formatted(.currency(code: "EUR").precision(.fractionLength(2)))
    }
    
    var progress: Double {
        guard viewModel.growthGoalTarget > 0, let data = currentYearData else { return 0 }
        let base = data.startWallet + data.invested
        let retAmount = viewModel.currentTotalCapital - base
        let retPercent = base > 0 ? (retAmount / base) : 0
        
        if isPercentGoal {
            return min(max(retPercent / (viewModel.growthGoalTarget / 100.0), 0), 1)
        } else {
            return min(max(retAmount / viewModel.growthGoalTarget, 0), 1)
        }
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
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        .help("Double-click to edit your Growth Goal")
    }
}

// =========================================================================
// MARK: - TABLEAU SPREADSHEET (SAISIE MANUELLE)
// =========================================================================

struct GrowthTableSection: View {
    @ObservedObject var viewModel: PortfolioViewModel
    var currentYear: Int { Calendar.current.component(.year, from: Date()) }
    
    // Fonction qui calcule la somme de l'investissement cumulé jusqu'à une année donnée
    func cumulativeInvest(for targetYear: Int) -> Double {
        let initialWallet = viewModel.growthYears.first?.startWallet ?? 0
        let investedSum = viewModel.growthYears.filter { $0.year <= targetYear }.reduce(0) { $0 + $1.invested }
        return initialWallet + investedSum
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Capital Growth History").font(.title2).fontWeight(.bold).foregroundColor(.secondary).padding(.bottom, 4)
            
            VStack(spacing: 0) {
                // HEADER
                HStack(spacing: 8) {
                    Text("Year").fontWeight(.bold).frame(width: 50, alignment: .leading)
                    Text("Start Wallet").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Invested").frame(maxWidth: .infinity, alignment: .leading)
                    Text("End Wallet").frame(maxWidth: .infinity, alignment: .leading)
                    
                    Text("Return €").fontWeight(.bold).frame(maxWidth: .infinity, alignment: .trailing)
                    Text("Return %").fontWeight(.bold).frame(maxWidth: .infinity, alignment: .trailing)
                    Text("TOTAL Invest").fontWeight(.bold).frame(maxWidth: .infinity, alignment: .trailing)
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.horizontal, 16).padding(.vertical, 12).background(Color(NSColor.windowBackgroundColor))
                
                Divider()
                
                // LIGNES SPREADSHEET
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach($viewModel.growthYears) { $yearData in
                            let isCurrent = (yearData.year == currentYear)
                            GrowthRowView(
                                yearData: $yearData,
                                isCurrentYear: isCurrent,
                                liveWalletValue: viewModel.currentTotalCapital,
                                cumulativeInvest: cumulativeInvest(for: yearData.year)
                            )
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            Divider()
                        }
                    }
                }
            }
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))
        }
        .frame(height: 380).padding().background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

struct GrowthRowView: View {
    @Binding var yearData: GrowthYear
    let isCurrentYear: Bool
    let liveWalletValue: Double
    let cumulativeInvest: Double // Total cumulé
    
    // Le End Wallet effectif : Live si année en cours, sinon manuel
    var effectiveEndWallet: Double {
        isCurrentYear ? liveWalletValue : yearData.endWallet
    }
    
    var displayReturnAmount: Double {
        effectiveEndWallet - yearData.startWallet - yearData.invested
    }
    
    var displayReturnPercent: Double {
        let base = yearData.startWallet + yearData.invested
        guard base > 0 else { return 0 }
        return displayReturnAmount / base
    }
    
    var isBlankYear: Bool {
        yearData.startWallet == 0 && yearData.invested == 0 && effectiveEndWallet == 0 && !isCurrentYear
    }
    
    var isZeroReturn: Bool {
        abs(displayReturnAmount) < 0.001
    }
    
    var body: some View {
        HStack(spacing: 8) {
            // 1. Année
            Text(String(yearData.year)).fontWeight(.bold).frame(width: 50, alignment: .leading)
            
            // 2. Start & Invested
            GrowthField(value: $yearData.startWallet)
            GrowthField(value: $yearData.invested)
            
            // 3. End Wallet
            if isCurrentYear {
                Text(liveWalletValue.formatted(.number.precision(.fractionLength(2))))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundColor(.secondary)
                    .help("Valeur connectée en temps réel au portefeuille")
            } else {
                GrowthField(value: $yearData.endWallet)
            }
            
            // 4. Return € et Return %
            if isBlankYear {
                Text("-").frame(maxWidth: .infinity, alignment: .trailing).foregroundColor(.secondary)
                Text("-").frame(maxWidth: .infinity, alignment: .trailing).foregroundColor(.secondary)
            } else if isZeroReturn {
                Text("0,00 €").fontWeight(.bold).foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .trailing)
                Text("0,00%").fontWeight(.bold).foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                Text(displayReturnAmount.formatted(.currency(code: "EUR").precision(.fractionLength(2)).sign(strategy: .always())))
                    .fontWeight(.bold)
                    .foregroundColor(displayReturnAmount > 0 ? .green : .red)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                
                Text(displayReturnPercent.formatted(.percent.precision(.fractionLength(2)).sign(strategy: .always())))
                    .fontWeight(.bold)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background((displayReturnPercent > 0 ? Color.green : Color.red).opacity(0.1))
                    .foregroundColor(displayReturnPercent > 0 ? .green : .red)
                    .cornerRadius(4)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            
            // 5. Total Investi cumulé (Calculé automatiquement)
            Text(cumulativeInvest.formatted(.currency(code: "EUR").precision(.fractionLength(2))))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .foregroundColor(cumulativeInvest == 0 ? .secondary.opacity(0.5) : .primary)
        }
    }
}

struct GrowthField: View {
    @Binding var value: Double
    var body: some View {
        TextField("0", value: $value, format: .number)
            .textFieldStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - FULL SCREEN ZOOM
struct GrowthFullScreenChartView: View {
    @Environment(\.dismiss) var dismiss
    let zoomType: GrowthChartZoomType
    @ObservedObject var viewModel: PortfolioViewModel
    
    var body: some View {
        VStack(spacing: 20) {
            HStack { Text("Zoom").font(.title).fontWeight(.bold); Spacer(); Button(action: { dismiss() }) { Image(systemName: "xmark.circle.fill").font(.title).foregroundColor(.secondary) }.buttonStyle(.plain) }
            Text("Chart will appear here.")
        }.padding(30).frame(minWidth: 900, minHeight: 700)
    }
}
