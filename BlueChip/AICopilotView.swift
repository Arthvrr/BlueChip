import SwiftUI

// =========================================================================
// MARK: - CHAT HISTORY MANAGER (SAUVEGARDE LOCALE ROBUSTE VIA FILEMANAGER)
// =========================================================================
class ChatHistoryManager {
    static let shared = ChatHistoryManager()
    private let keyPrefix = "ai_chat_"
    
    // Récupère l'URL du dossier Documents de l'application
    private func getDocumentDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0]
    }
    
    // Construit le chemin complet du fichier pour un onglet donné
    private func getFileURL(for tab: String) -> URL {
        return getDocumentDirectory().appendingPathComponent("\(keyPrefix)\(tab).json")
    }

    func save(_ messages: [ChatMessage], for tab: String) {
        let fileURL = getFileURL(for: tab)
        
        do {
            let encoder = JSONEncoder()
            // Ajoute de l'indentation pour que le fichier soit lisible si tu veux le vérifier
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(messages)
            
            // L'option .atomic force l'écriture d'un fichier temporaire avant de remplacer l'ancien
            try data.write(to: fileURL, options: .atomic)
            
            // Notifie l'interface
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: NSNotification.Name("ChatHistoryUpdated"), object: nil)
            }
        } catch {
            print("Erreur critique lors de la sauvegarde de l'historique pour \(tab): \(error)")
        }
    }

    func load(for tab: String) -> [ChatMessage]? {
        let fileURL = getFileURL(for: tab)
        
        // Vérifie si le fichier existe
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            let decodedMessages = try decoder.decode([ChatMessage].self, from: data)
            return decodedMessages
        } catch {
            print("⚠️ Erreur de décodage JSON pour \(tab): \(error)")
            // On ne supprime plus le fichier ici brutalement !
            // Peut-être que la structure de ChatMessage a changé. On retourne simplement nil pour forcer un nouveau chat.
            return nil
        }
    }

    func clear(for tab: String) {
        let fileURL = getFileURL(for: tab)
        
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
                print("🗑 Historique effacé pour \(tab)")
            }
        } catch {
            print("Erreur lors de la suppression de l'historique pour \(tab): \(error)")
        }
        
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: NSNotification.Name("ChatHistoryUpdated"), object: nil)
        }
    }
    
    func hasHistory(for tab: String) -> Bool {
        let fileURL = getFileURL(for: tab)
        return FileManager.default.fileExists(atPath: fileURL.path)
    }
}


struct AICopilotView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: PortfolioViewModel
    let currentTab: AppTab
    let resumeChat: Bool
    
    @AppStorage("geminiApiKey") private var geminiApiKey: String = ""
    
    @State private var messages: [ChatMessage] = []
    @State private var inputText: String = ""
    @State private var isThinking: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            // HEADER
            HStack {
                Image("AI")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20) // Ajuste la taille selon tes préférences
                    .foregroundColor(.secondary) // Ça marchera grâce au "Template Image" !
                Text("BlueChip AI Copilot")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("• \(currentTab.rawValue) Analysis")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if !messages.isEmpty {
                    Button(action: {
                        ChatHistoryManager.shared.clear(for: currentTab.rawValue)
                        messages.removeAll()
                        startInitialAnalysis()
                    }) {
                        Image(systemName: "trash")
                            .font(.title3)
                            .foregroundColor(.red.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 8)
                    .help("Clear Chat History and Restart")
                }
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            if geminiApiKey.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.orange)
                    Text("API Key Required")
                        .font(.title)
                        .fontWeight(.bold)
                    Text("Please configure your Google Gemini API Key in the Preferences (Cmd + ,) to enable the AI Copilot.")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 40)
                    
                    Button("Close") { dismiss() }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 10)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // INTERFACE DU CHAT
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 16) {
                            ForEach(messages) { message in
                                // NOUVEAU : On cache le tout premier prompt de lancement
                                if message.text != "Analyze the current page data." {
                                    ChatBubble(message: message)
                                        .id(message.id)
                                }
                            }
                            if isThinking {
                                HStack {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("Analyzing portfolio data...")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                }
                                .padding(.horizontal)
                                .id("thinking")
                            }
                        }
                        .padding()
                    }
                    .onChange(of: messages.count) { _ in
                        // Un léger délai permet à SwiftUI de calculer la taille finale du texte avant de scroller
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation { proxy.scrollTo(messages.last?.id, anchor: .bottom) }
                        }
                    }
                    .onChange(of: isThinking) { _ in
                        if isThinking {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                withAnimation { proxy.scrollTo("thinking", anchor: .bottom) }
                            }
                        }
                    }
                }
                
                Divider()
                
                // INPUT BAR
                HStack(spacing: 12) {
                    TextField("Ask a follow-up question...", text: $inputText)
                        .textFieldStyle(.plain)
                        .padding(10)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))
                        .onSubmit { sendMessage() }
                        .disabled(isThinking)
                    
                    Button(action: { sendMessage() }) {
                        Image(systemName: "paperplane.fill")
                            .foregroundColor(inputText.isEmpty || isThinking ? .secondary : .white)
                            .padding(10)
                            .background(inputText.isEmpty || isThinking ? Color.gray.opacity(0.2) : Color.blue)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .disabled(inputText.isEmpty || isThinking)
                }
                .padding()
                .background(Color(NSColor.windowBackgroundColor))
            }
        }
        .frame(width: 700, height: 600)
        .onAppear {
            if !geminiApiKey.isEmpty && messages.isEmpty {
                // 1. On ignore totalement la variable "resumeChat" du bouton parent.
                // 2. On vérifie directement sur le disque dur de ton Mac si un fichier existe.
                if let savedMessages = ChatHistoryManager.shared.load(for: currentTab.rawValue), !savedMessages.isEmpty {
                    self.messages = savedMessages
                } else {
                    // 3. S'il n'y a vraiment aucun fichier, alors on lance une nouvelle analyse.
                    startInitialAnalysis()
                }
            }
        }

    }
    
    // ==========================================
    // LOGIQUE DE GÉNÉRATION DU CONTEXTE
    // ==========================================
    private func startInitialAnalysis() {
        isThinking = true
        let systemPrompt = generateSystemPrompt()
        
        Task {
            do {
                // Le message caché qui lance l'analyse
                let hiddenInitialMessage = ChatMessage(role: "user", text: "Analyze the current page data.")
                
                let response = try await GeminiService.shared.generateChatResponse(systemPrompt: systemPrompt, messages: [hiddenInitialMessage], apiKey: geminiApiKey)
                
                await MainActor.run {
                    // MODIFIÉ : On ajoute le message caché à la vraie liste locale (pour la sauvegarde API)
                    messages.append(hiddenInitialMessage)
                    // Puis on ajoute la réponse de l'IA
                    messages.append(ChatMessage(role: "model", text: response))
                    
                    ChatHistoryManager.shared.save(messages, for: currentTab.rawValue)
                    isThinking = false
                }
            } catch {
                await MainActor.run {
                    messages.append(ChatMessage(role: "model", text: "⚠️ Error: \(error.localizedDescription)"))
                    ChatHistoryManager.shared.save(messages, for: currentTab.rawValue)
                    isThinking = false
                }
            }
        }
    }
    
    private func generateSystemPrompt() -> String {
        let currency = viewModel.preferredCurrency
        
        var prompt = """
        You are a highly skilled, professional financial analyst and wealth manager integrated into the macOS application 'BlueChip'.
        The user has just opened the 'AI Insights' window. Your job is to analyze the data provided below and give a crisp, actionable, and insightful financial summary.
        Do NOT use generic disclaimers like "This is not financial advice". Speak directly and professionally.
        
        CRITICAL FORMATTING RULES:
        1. DO NOT use markdown headings (like "#" or "###") or horizontal lines (like "---").
        2. For section headers, simply write the title in bold (e.g., **Portfolio Overview**).
        3. Use standard bullet points (-) for lists.
        4. Add line breaks between paragraphs to keep the layout breathable.
        
        --- CURRENT PORTFOLIO CONTEXT ---
        Current Tab Being Viewed: \(currentTab.rawValue)
        Total Portfolio Value: \(viewModel.currentTotalCapital) \(currency)
        Total Cash Available: \(viewModel.availableCash) \(currency)
        Total Positions: \(viewModel.positions.count)
        
        """
        
        switch currentTab {
        case .composition:
            // 1. Calculs globaux de performance
            let totalInvested = viewModel.manuallyInvested > 0 ? viewModel.manuallyInvested : viewModel.positionsInvestedSum
            let trueROIValue = viewModel.currentTotalCapital - totalInvested
            let trueROIPercent = totalInvested > 0 ? (trueROIValue / totalInvested) * 100 : 0
            let cashWeight = viewModel.currentTotalCapital > 0 ? (viewModel.availableCash / viewModel.currentTotalCapital) * 100 : 0
            
            prompt += "\n--- COMPOSITION & PERFORMANCE OVERVIEW ---\n"
            prompt += "Total Invested: \(totalInvested.formatted(.currency(code: currency)))\n"
            prompt += "Unrealized P/L: \(trueROIValue.formatted(.currency(code: currency))) (\(trueROIPercent.formatted(.number.precision(.fractionLength(2))))%)\n"
            prompt += "Available Cash: \(viewModel.availableCash.formatted(.currency(code: currency))) (Cash Drag Weight: \(cashWeight.formatted(.number.precision(.fractionLength(1))))%)\n"
            
            prompt += "\n--- TOP HOLDINGS (By Weight) ---\n"
            let sortedPositions = viewModel.positions.sorted { $0.currentValueEUR > $1.currentValueEUR }
            for pos in sortedPositions.prefix(10) { // On limite aux 10 plus grosses pour ne pas saturer l'API
                let weight = viewModel.currentTotalCapital > 0 ? (pos.currentValueEUR / viewModel.currentTotalCapital) * 100 : 0
                prompt += "- \(pos.ticker) (\(pos.sector.isEmpty ? "Unknown Sector" : pos.sector)): \(weight.formatted(.number.precision(.fractionLength(1))))% weight | P/L: \(pos.roiPercent.formatted(.percent.precision(.fractionLength(1))))\n"
            }
            
            prompt += "\n--- SECTOR EXPOSURE ---\n"
            let sortedSectors = viewModel.allocationBySector.sorted { $0.value > $1.value }
            for sector in sortedSectors.prefix(5) {
                let weight = viewModel.currentTotalCapital > 0 ? (sector.value / viewModel.currentTotalCapital) * 100 : 0
                prompt += "- \(sector.name): \(weight.formatted(.number.precision(.fractionLength(1))))%\n"
            }
            
            prompt += "\n--- GEOGRAPHIC EXPOSURE ---\n"
            let sortedCountries = viewModel.allocationByCountry.sorted { $0.value > $1.value }
            for country in sortedCountries.prefix(5) {
                let weight = viewModel.currentTotalCapital > 0 ? (country.value / viewModel.currentTotalCapital) * 100 : 0
                prompt += "- \(country.name): \(weight.formatted(.number.precision(.fractionLength(1))))%\n"
            }
            
            prompt += """
            \nTask: Perform a deep, institutional-grade analysis of this portfolio's composition. 
            1. Evaluate the asset allocation, highlighting the top convictions and any critical concentration risks (stock-specific, sector-specific, or geographic).
            2. Assess the overall performance (ROI) vs the capital deployed.
            3. Comment on the cash position (is there too much cash drag or too little dry powder?).
            4. Provide 2-3 actionable, precise recommendations to optimize the risk/reward profile or improve diversification.
            Be verbose, highly analytical, and use professional wealth management terminology. Use bolding for metrics and tickers.
            """
            
        case .fundamentals:
            let trackedStocks = viewModel.positions.filter { ($0.fundamentalValues?.count ?? 0) > 0 }
            let maxScore = viewModel.fundamentalCriteria.reduce(0) { $0 + ($1.weight * 2.0) }
            
            prompt += "\n--- FUNDAMENTAL QUALITY SCREENER DATA ---\n"
            prompt += "Criteria Tracked: \(viewModel.fundamentalCriteria.count) metrics\n"
            prompt += "Stocks Analyzed: \(trackedStocks.count) out of \(viewModel.positions.count) total positions\n"
            prompt += "Maximum Possible Score per Stock: \(maxScore.formatted(.number.precision(.fractionLength(1)))) pts\n"
            
            if !trackedStocks.isEmpty {
                var stockScores: [(ticker: String, score: Double)] = []
                var sectionScores: [String: Double] = [:]
                var sectionMax: [String: Double] = [:]
                var totalScoreSum = 0.0
                
                // Calcul des scores par section
                for crit in viewModel.fundamentalCriteria {
                    sectionMax[crit.section, default: 0] += (crit.weight * 2.0 * Double(trackedStocks.count))
                }
                
                // Calcul des scores par action
                for pos in trackedStocks {
                    var posScore = 0.0
                    for crit in viewModel.fundamentalCriteria {
                        if let val = pos.fundamentalValues?[crit.id.uuidString] {
                            let pts = ScoreEngine.getScoreStatus(value: val, criterion: crit).points
                            posScore += pts
                            sectionScores[crit.section, default: 0] += pts
                        }
                    }
                    stockScores.append((pos.ticker, posScore))
                    totalScoreSum += posScore
                }
                
                let avgScore = totalScoreSum / Double(trackedStocks.count)
                let avgScorePct = maxScore > 0 ? (avgScore / maxScore) * 100 : 0
                
                prompt += "Portfolio Average Quality Score: \(avgScore.formatted(.number.precision(.fractionLength(1)))) pts (\(avgScorePct.formatted(.number.precision(.fractionLength(1))))%)\n"
                
                let sortedStocks = stockScores.sorted { $0.score > $1.score }
                
                prompt += "\n--- TOP QUALITY STOCKS ---\n"
                for item in sortedStocks.prefix(3) { // On prend le Top 3
                    let pct = maxScore > 0 ? (item.score / maxScore) * 100 : 0
                    prompt += "- \(item.ticker): \(item.score.formatted(.number.precision(.fractionLength(1)))) pts (\(pct.formatted(.number.precision(.fractionLength(1))))%)\n"
                }
                
                if sortedStocks.count > 3 {
                    prompt += "\n--- BOTTOM QUALITY STOCKS ---\n"
                    for item in sortedStocks.suffix(3).reversed() { // On prend le Flop 3
                        let pct = maxScore > 0 ? (item.score / maxScore) * 100 : 0
                        prompt += "- \(item.ticker): \(item.score.formatted(.number.precision(.fractionLength(1)))) pts (\(pct.formatted(.number.precision(.fractionLength(1))))%)\n"
                    }
                }
                
                var pctDict: [String: Double] = [:]
                for (sec, score) in sectionScores {
                    let sMax = sectionMax[sec] ?? 1
                    pctDict[sec] = sMax > 0 ? (score / sMax) * 100 : 0
                }
                let sortedSections = pctDict.sorted { $0.value > $1.value }
                
                prompt += "\n--- CATEGORY STRENGTHS & WEAKNESSES ---\n"
                if let bestSec = sortedSections.first {
                    prompt += "Strongest Category: \(bestSec.key) (\(bestSec.value.formatted(.number.precision(.fractionLength(1))))% fulfillment)\n"
                }
                if let worstSec = sortedSections.last, sortedSections.count > 1 {
                    prompt += "Weakest Category: \(worstSec.key) (\(worstSec.value.formatted(.number.precision(.fractionLength(1))))% fulfillment)\n"
                }
            } else {
                prompt += "No stocks have been analyzed fundamentally yet.\n"
            }
            
            prompt += """
            \nTask: Perform a rigorous, institutional-grade fundamental analysis of this portfolio based on the custom quality screener data.
            1. Evaluate the overall quality of the portfolio. Is the portfolio built on solid fundamentals?
            2. Identify the fundamental strengths (Strongest Category) and what it means for downside protection.
            3. Critically analyze the weaknesses (Weakest Category) and explain the specific risks involved.
            4. Comment on the dispersion between the Top Quality Stocks and Bottom Quality Stocks. Provide actionable advice on whether the bottom-tier stocks should be cut, trimmed, or re-evaluated.
            Be highly analytical, objective, and use professional equity research terminology (e.g., 'quality compounding', 'fundamental deterioration', 'balance sheet fortitude'). Use bolding for metrics and tickers.
            """
        
        case .growth:
            // 1. Recréation des calculs de performance et de temps
            let currentYear = Calendar.current.component(.year, from: Date())
            let activeYearsCount = max(1, currentYear - viewModel.dividendStartYear + 1)
            
            let totalInvested = viewModel.manuallyInvested > 0 ? viewModel.manuallyInvested : viewModel.positionsInvestedSum
            let currentWallet = viewModel.currentTotalCapital
            let totalGain = currentWallet - totalInvested
            let allTimeReturnPercent = totalInvested > 0 ? (totalGain / totalInvested) * 100 : 0
            
            // 2. Métriques avancées (CAGR & MoIC)
            let cagrRaw = pow(1.0 + max(totalGain / (totalInvested > 0 ? totalInvested : 1), -0.999), 1.0 / Double(activeYearsCount)) - 1.0
            let cagr = cagrRaw * 100
            let moic = totalInvested > 0 ? (currentWallet / totalInvested) : 1.0
            
            // 3. Provenance des gains (Tipping Point & Compounding)
            let totalDividends = viewModel.dividendYears.reduce(0) { $0 + $1.total }
            let pureCapitalGain = max(0, totalGain - totalDividends)
            
            prompt += "\n--- GROWTH & PERFORMANCE OVERVIEW ---\n"
            prompt += "Total Capital Invested (Net Deposits): \(totalInvested.formatted(.currency(code: currency)))\n"
            prompt += "Current Portfolio Value: \(currentWallet.formatted(.currency(code: currency)))\n"
            prompt += "All-Time Unrealized Return: \(totalGain.formatted(.currency(code: currency).sign(strategy: .always()))) (\(allTimeReturnPercent.formatted(.number.precision(.fractionLength(2))))%)\n"
            prompt += "Tracking Period: \(activeYearsCount) active years\n"
            
            prompt += "\n--- ADVANCED COMPOUNDING METRICS ---\n"
            prompt += "CAGR (Compound Annual Growth Rate): \(cagr.formatted(.number.precision(.fractionLength(2))))%\n"
            prompt += "MoIC (Multiple on Invested Capital): \(moic.formatted(.number.precision(.fractionLength(2))))x\n"
            
            prompt += "\n--- GAINS PROVENANCE (VALUE SOURCE) ---\n"
            prompt += "Total Wealth Generated: \(totalGain.formatted(.currency(code: currency)))\n"
            prompt += "- From Dividends (Cash Flow): \(totalDividends.formatted(.currency(code: currency)))\n"
            prompt += "- From Capital Appreciation (Price ROI): \(pureCapitalGain.formatted(.currency(code: currency)))\n"
            
            prompt += "\n--- GROWTH GOALS ---\n"
            if viewModel.growthGoalType == .targetReturnPercent {
                prompt += "User Target Annual Return: \(viewModel.growthGoalTarget)%\n"
            } else {
                prompt += "User Target Annual Return: \(viewModel.growthGoalTarget) \(currency)\n"
            }
            
            prompt += """
            \nTask: Perform a deep, institutional-grade analysis of the portfolio's growth and compounding trajectory.
            1. Evaluate the overall capital appreciation, focusing heavily on the CAGR and MoIC (Multiple on Invested Capital).
            2. Analyze the 'Gains Provenance' to determine if the wealth generation is primarily driven by capital appreciation or dividend compounding.
            3. Assess the portfolio's compounding momentum (how well the market returns are scaling relative to the out-of-pocket invested capital).
            4. Provide actionable insights on whether the current growth trajectory aligns with standard market benchmarks and how to optimize capital compounding.
            Be highly analytical, objective, and use professional equity management terminology (e.g., 'compounding velocity', 'MoIC expansion', 'capital efficiency'). Use bolding for metrics.
            """

        case .dividends:
            // 1. Calculs des métriques de temps
            let currentYear = Calendar.current.component(.year, from: Date())
            let currentMonth = Calendar.current.component(.month, from: Date())
            let currentMonthName = Calendar.current.monthSymbols[currentMonth - 1]
            
            // 2. Historique et performances YoY
            let totalReceivedAllTime = viewModel.dividendYears.reduce(0) { $0 + $1.total }
            let thisYearData = viewModel.dividendYears.first { $0.year == currentYear }
            let lastYearData = viewModel.dividendYears.first { $0.year == currentYear - 1 }
            let receivedThisYear = thisYearData?.total ?? 0
            let receivedLastYear = lastYearData?.total ?? 0
            let yoyGrowth = receivedLastYear > 0 ? ((receivedThisYear - receivedLastYear) / receivedLastYear) * 100 : 0
            let bestYear = viewModel.dividendYears.map { $0.total }.max() ?? 0
            let payingCount = viewModel.positions.filter { $0.totalDividendEUR > 0 }.count
            
            // 3. Calculs du mois en cours
            let payingStocksThisMonth = viewModel.positions.filter { $0.dividendMonths.contains(currentMonth) }
            let expectedThisMonth = payingStocksThisMonth.reduce(0.0) { sum, pos in
                sum + (pos.totalDividendEUR / Double(max(1, pos.dividendMonths.count)))
            }
            
            // 4. Progression des objectifs (Goals)
            let isYieldGoal = viewModel.dividendGoalType == .portfolioYield
            let goalProgress = viewModel.dividendGoalTarget > 0 ? (isYieldGoal ? (viewModel.portfolioYield / (viewModel.dividendGoalTarget / 100.0)) : (viewModel.totalDividends / viewModel.dividendGoalTarget)) * 100 : 0
            
            prompt += "\n--- DIVIDEND PORTFOLIO OVERVIEW ---\n"
            prompt += "Projected Annual Dividends: \(viewModel.totalDividends.formatted(.currency(code: currency)))\n"
            prompt += "Projected Portfolio Yield: \((viewModel.portfolioYield * 100).formatted(.number.precision(.fractionLength(2))))%\n"
            prompt += "Dividend-Paying Stocks: \(payingCount) out of \(viewModel.positions.count)\n"
            
            prompt += "\n--- HISTORICAL PERFORMANCE ---\n"
            prompt += "All-Time Dividends Collected: \(totalReceivedAllTime.formatted(.currency(code: currency)))\n"
            prompt += "Dividends Received This Year (\(currentYear)): \(receivedThisYear.formatted(.currency(code: currency)))\n"
            prompt += "YoY Growth (vs Last Year): \(yoyGrowth.formatted(.number.precision(.fractionLength(2))))%\n"
            prompt += "Best Year on Record: \(bestYear.formatted(.currency(code: currency)))\n"
            
            prompt += "\n--- THIS MONTH (\(currentMonthName)) PAYOUT RADAR ---\n"
            prompt += "Expected Income This Month: \(expectedThisMonth.formatted(.currency(code: currency)))\n"
            prompt += "Stocks Paying This Month: \(payingStocksThisMonth.isEmpty ? "None" : payingStocksThisMonth.map { $0.ticker }.joined(separator: ", "))\n"
            
            prompt += "\n--- GOALS & TARGETS ---\n"
            let goalTypeStr = isYieldGoal ? "Portfolio Yield" : "Annual Expected Dividends"
            let targetStr = isYieldGoal ? "\(viewModel.dividendGoalTarget)%" : "\(viewModel.dividendGoalTarget) \(currency)"
            prompt += "User Goal: \(goalTypeStr) target of \(targetStr)\n"
            prompt += "Current Goal Progress: \(min(goalProgress, 100).formatted(.number.precision(.fractionLength(1))))%\n"
            
            prompt += "\n--- TOP DIVIDEND CONTRIBUTORS (YIELD ON COST) ---\n"
            let yocStocks = viewModel.positions.filter { $0.investedAmountEUR > 0 && $0.totalDividendEUR > 0 }
                .map { (ticker: $0.ticker, yoc: ($0.totalDividendEUR / $0.investedAmountEUR) * 100.0) }
                .sorted { $0.yoc > $1.yoc }
            for item in yocStocks.prefix(5) {
                prompt += "- \(item.ticker): \(item.yoc.formatted(.number.precision(.fractionLength(2))))% YOC\n"
            }
            
            prompt += """
            \nTask: Perform an institutional-grade analysis of this dividend portfolio's income generation, sustainability, and growth.
            1. Evaluate the overall dividend yield and projected annual income. Is it a sustainable 'Dividend Growth' strategy or a 'High Yield' strategy?
            2. Analyze the historical performance (YoY Growth and All-Time cash collected) to assess the snowball/compounding effect.
            3. Comment on the current month's expected payouts and the Yield on Cost (YOC) of the top contributors.
            4. Assess the progress towards the user's dividend goal and provide 2-3 actionable, professional recommendations to optimize income generation or dividend safety.
            Be highly analytical, objective, and use professional equity management terminology (e.g., 'yield on cost expansion', 'cash flow compounding', 'payout sustainability'). Use bolding for metrics and tickers.
            """

        case .valuation:
            // 1. Récupération de la Marge de Sécurité actuelle de l'utilisateur
            let moS = UserDefaults.standard.double(forKey: "valuation_marginOfSafety")
            let activeMoS = moS > 0 ? moS : 10.0
            
            // 2. Calculs des métriques de valorisation du portefeuille
            let valuatedStocks = viewModel.positions.filter { $0.valGuruFocusPrice > 0 || $0.valTipRanksPrice > 0 }
            let undervaluedStocks = valuatedStocks.filter { $0.currentPrice < $0.fairPrice(marginOfSafety: activeMoS) && $0.fairPrice(marginOfSafety: activeMoS) > 0 }
            
            var avgFairUpside = 0.0
            if !valuatedStocks.isEmpty {
                let totalUpside = valuatedStocks.reduce(0.0) { $0 + $1.fairPriceUpside(marginOfSafety: activeMoS) }
                avgFairUpside = (totalUpside / Double(valuatedStocks.count)) * 100
            }
            
            let peStocks = viewModel.positions.filter { $0.valCurrentPE > 0 }
            let avgCurrentPE = peStocks.isEmpty ? 0 : peStocks.reduce(0.0) { $0 + $1.valCurrentPE } / Double(peStocks.count)
            
            let pegStocks = viewModel.positions.filter { $0.valPeg > 0 }
            let avgPEG = pegStocks.isEmpty ? 0 : pegStocks.reduce(0.0) { $0 + $1.valPeg } / Double(pegStocks.count)
            
            prompt += "\n--- VALUATION & MARGIN OF SAFETY OVERVIEW ---\n"
            prompt += "Global Margin of Safety Set: \(Int(activeMoS))%\n"
            prompt += "Valuated Positions: \(valuatedStocks.count) out of \(viewModel.positions.count)\n"
            prompt += "Undervalued Positions (vs Fair Price): \(undervaluedStocks.count)\n"
            prompt += "Average Fair Price Upside: \(avgFairUpside.formatted(.number.precision(.fractionLength(1))))%\n"
            
            prompt += "\n--- PORTFOLIO MULTIPLES ---\n"
            prompt += "Average Current P/E: \(avgCurrentPE.formatted(.number.precision(.fractionLength(1))))x\n"
            prompt += "Average PEG Ratio: \(avgPEG.formatted(.number.precision(.fractionLength(2))))\n"
            
            prompt += "\n--- INDIVIDUAL POSITION BREAKDOWN (TOP VALUATIONS) ---\n"
            for pos in viewModel.positions {
                let fairP = pos.fairPrice(marginOfSafety: activeMoS)
                let upside = pos.fairPriceUpside(marginOfSafety: activeMoS) * 100
                prompt += "- \(pos.ticker): Price = \(pos.currentPrice.formatted(.currency(code: pos.currency))) | Fair Price = \(fairP > 0 ? fairP.formatted(.currency(code: pos.currency)) : "N/A") | Upside = \(upside.formatted(.number.precision(.fractionLength(1))))% | Current PE = \(pos.valCurrentPE > 0 ? "\(pos.valCurrentPE)x" : "N/A") | PEG = \(pos.valPeg > 0 ? "\(pos.valPeg)" : "N/A")\n"
            }
            
            prompt += """
            \nTask: Perform a rigorous, institutional-grade valuation analysis of this portfolio based on intrinsic value models and market multiples.
            1. Evaluate the overall valuation health of the portfolio using the current Margin of Safety (\(Int(activeMoS))%). Identify which positions offer the highest margin of safety and deep value.
            2. Analyze the portfolio's aggregate multiples (Average P/E and PEG Ratio) to determine if the overall allocation leans toward growth, value, or expensive territory.
            3. Point out any overvalued assets or severe multiple expansions that pose a capital risk.
            4. Provide 2-3 precise, actionable recommendations on which undervalued positions to accumulate or which overvalued positions to trim.
            Be highly analytical, objective, and use professional value investing terminology (e.g., 'margin of safety buffer', 'multiple contraction risk', 'intrinsic value discount', 'GARP'). Use bolding for metrics and tickers.
            """
            
        case .projection:
            // 1. Récupération des paramètres de projection (UserDefaults & ViewModel)
            let ud = UserDefaults.standard
            let rawHorizon = ud.double(forKey: "proj_timeHorizonYears")
            let horizon = rawHorizon == 0 ? 30.0 : rawHorizon
            let enableContrib = ud.bool(forKey: "proj_enableMonthlyContrib")
            let contribAmount = ud.double(forKey: "proj_monthlyContribAmount")
            let enableDRIP = ud.bool(forKey: "proj_enableDRIP")
            let enableInflation = ud.bool(forKey: "proj_enableInflation")
            let rawInflation = ud.double(forKey: "proj_inflationRate")
            let inflationRate = rawInflation == 0 ? 2.0 : rawInflation
            
            // 2. Calcul des taux de base (CAGR & Div Growth) comme sur la page
            let currentYear = Calendar.current.component(.year, from: Date())
            let activeYearsCount = max(1, currentYear - viewModel.dividendStartYear + 1)
            let totalInvested = viewModel.manuallyInvested > 0 ? viewModel.manuallyInvested : viewModel.positionsInvestedSum
            let currentWallet = viewModel.currentTotalCapital
            let allTimeReturnEUR = currentWallet - totalInvested
            let allTimeReturnPercent = totalInvested > 0 ? (allTimeReturnEUR / totalInvested) : 0
            
            let cagrRaw = pow(1.0 + max(allTimeReturnPercent, -0.999), 1.0 / Double(activeYearsCount)) - 1.0
            let defaultCAGR = cagrRaw.isNaN || cagrRaw.isInfinite ? 0.08 : cagrRaw
            
            var totalAnnualDiv: Double = 0
            for pos in viewModel.positions { totalAnnualDiv += pos.totalDividendEUR }
            
            var defaultWeightedDivGrowth: Double = 0.06
            if totalAnnualDiv > 0 {
                var weightedSum: Double = 0
                for pos in viewModel.positions {
                    weightedSum += (pos.totalDividendEUR * (pos.dividendGrowth5Y / 100.0))
                }
                defaultWeightedDivGrowth = weightedSum / totalAnnualDiv
            }
            
            // 3. Exécution d'une simulation rapide en arrière-plan pour l'IA
            var currentCap = currentWallet
            var currentDiv = totalAnnualDiv
            var cumulDiv = 0.0
            var outOfPocketInvested = totalInvested
            let initialYield = currentWallet > 0 ? (totalAnnualDiv / currentWallet) : 0.0
            
            for i in 0...Int(horizon) {
                if i > 0 {
                    currentCap *= (1.0 + defaultCAGR)
                    currentDiv *= (1.0 + defaultWeightedDivGrowth)
                    if enableContrib {
                        let yearlyContrib = contribAmount * 12.0
                        currentCap += yearlyContrib
                        outOfPocketInvested += yearlyContrib
                        currentDiv += yearlyContrib * initialYield
                    }
                    if enableDRIP {
                        currentCap += currentDiv
                        currentDiv += currentDiv * initialYield
                    }
                }
                cumulDiv += currentDiv
            }
            
            // Ajustement final de l'inflation
            let finalInflationDiscount = enableInflation ? pow(1.0 + (inflationRate / 100.0), Double(Int(horizon))) : 1.0
            let finalCap = currentCap / finalInflationDiscount
            let finalDiv = currentDiv / finalInflationDiscount
            let finalCumulDiv = cumulDiv / finalInflationDiscount
            let finalGain = finalCap - outOfPocketInvested
            let finalYOC = outOfPocketInvested > 0 ? (currentDiv / outOfPocketInvested) * 100.0 : 0.0
            
            prompt += "\n--- PROJECTION PARAMETERS & ASSUMPTIONS ---\n"
            prompt += "Time Horizon: \(Int(horizon)) Years (Target Year: \(currentYear + Int(horizon)))\n"
            prompt += "Base Capital CAGR: \((defaultCAGR * 100).formatted(.number.precision(.fractionLength(2))))%\n"
            prompt += "Base Dividend Growth (Weighted 5Y): \((defaultWeightedDivGrowth * 100).formatted(.number.precision(.fractionLength(2))))%\n"
            prompt += "Monthly Contributions: \(enableContrib ? "\(contribAmount.formatted(.currency(code: currency)))/month" : "Disabled")\n"
            prompt += "DRIP (Dividend Reinvestment): \(enableDRIP ? "Enabled" : "Disabled")\n"
            prompt += "Inflation Adjustment: \(enableInflation ? "Enabled (\(inflationRate)% per year)" : "Disabled (Nominal Values)")\n"
            
            prompt += "\n--- END OF PERIOD PROJECTIONS (YEAR \(currentYear + Int(horizon))) ---\n"
            prompt += "Projected Portfolio Value: \(finalCap.formatted(.currency(code: currency)))\n"
            prompt += "Total Out-of-Pocket Invested: \(outOfPocketInvested.formatted(.currency(code: currency)))\n"
            prompt += "Projected Capital Gain: \(finalGain.formatted(.currency(code: currency)))\n"
            prompt += "Projected Annual Dividend Income: \(finalDiv.formatted(.currency(code: currency)))\n"
            prompt += "Cumulative Dividends Collected over \(Int(horizon))Y: \(finalCumulDiv.formatted(.currency(code: currency)))\n"
            prompt += "Projected Yield on Cost (YOC): \(finalYOC.formatted(.number.precision(.fractionLength(2))))%\n"
            
            prompt += """
            \nTask: Perform a robust, institutional-grade analysis of this portfolio's long-term projection trajectory.
            1. Evaluate the compounding trajectory over the given time horizon. Is the terminal value and projected income realistic based on the historical assumptions (CAGR and Dividend Growth)?
            2. Analyze the specific levers the user has activated or ignored (e.g., the presence or absence of Monthly Contributions, DRIP, and Inflation adjustments). How do they impact the final result?
            3. Assess the "snowball effect" by reviewing the Projected Yield on Cost (YOC) and the Cumulative Dividends collected versus the out-of-pocket capital.
            4. Provide 2-3 strategic, actionable recommendations to optimize the terminal value or de-risk the portfolio (e.g., increasing savings rate, toggling DRIP, adjusting for real vs nominal returns).
            Be highly analytical, objective, and use professional quantitative forecasting terminology (e.g., 'terminal value', 'compounding velocity', 'real vs nominal returns', 'cash drag'). Use bolding for metrics.
            """
            
        case .simulation:
            prompt += "\n--- SIMULATION & SANDBOX ANALYSIS ---\n"
            
            // 1. Comparaison Globale (Current vs Simulated)
            prompt += "CURRENT PORTFOLIO:\n"
            prompt += "- Total Value: \(viewModel.currentTotalCapital.formatted(.currency(code: currency)))\n"
            prompt += "- Current Cash: \(viewModel.availableCash.formatted(.currency(code: currency)))\n"
            prompt += "- Annual Dividends: \(viewModel.totalDividends.formatted(.currency(code: currency)))\n"
            prompt += "- Portfolio Yield: \((viewModel.portfolioYield * 100).formatted(.number.precision(.fractionLength(2))))%\n"
            
            // Récupération des données simulées (on suppose ici qu'elles sont stockées/sauvegardées, sinon l'IA fera l'analyse sur base des logs).
            // NOTE: Les données simulées sont normalement stockées dans SimulationView, mais on peut donner le journal des actions (Logs) pour compenser.
            prompt += "\n--- USER SANDBOX ACTIONS (WHAT CHANGED?) ---\n"
            prompt += "The user has tested the following trades in the Sandbox environment:\n"
            // On peut injecter ici une description textuelle si tu passes les logs à l'AICopilotView, mais sinon on force l'IA à analyser la logique de rebalancement
            prompt += "Task: Perform a comparative analysis of a portfolio rebalancing strategy.\n"
            prompt += "1. Evaluate the impact of rebalancing a \(viewModel.currentTotalCapital.formatted(.currency(code: currency))) portfolio. If the user were to deploy their \(viewModel.availableCash.formatted(.currency(code: currency))) in cash, which sectors or stocks should they prioritize based on the current composition?\n"
            prompt += "2. Discuss the trade-offs between increasing Dividend Yield versus chasing Capital Growth in the current market environment.\n"
            prompt += "3. What are the primary risks of holding too much cash (Cash Drag) versus being 100% deployed? Provide a verdict on the current cash level.\n"
            prompt += "Provide actionable, institutional-grade advice on how to optimally deploy capital or trim existing positions to improve the risk/reward ratio. Use professional terms like 'rebalancing alpha', 'cash drag', and 'opportunity cost'."
            
        case .watchlist:
            // 1. Récupération de la Marge de Sécurité spécifique à la Watchlist
            let moS = UserDefaults.standard.double(forKey: "watchlist_marginOfSafety")
            let activeMoS = moS > 0 ? moS : 10.0
            let items = viewModel.watchlistItems
            
            prompt += "\n--- PROSPECTIVE WATCHLIST OVERVIEW ---\n"
            prompt += "Total Companies Tracked: \(items.count)\n"
            prompt += "Required Margin of Safety: \(Int(activeMoS))%\n"
            
            if !items.isEmpty {
                // 2. Calculs globaux de la Watchlist
                let undervaluedCount = items.filter { $0.currentPrice < $0.fairPrice(marginOfSafety: activeMoS) }.count
                let avgPEG = items.reduce(0.0) { $0 + $1.peg } / Double(items.count)
                let avgCurrentPE = items.reduce(0.0) { $0 + $1.currentPE } / Double(items.count)
                let bargainPEGCount = items.filter { $0.peg > 0 && $0.peg <= 1.0 }.count
                
                prompt += "Undervalued Stocks (Discount to Fair Value): \(undervaluedCount) out of \(items.count)\n"
                prompt += "Watchlist Average P/E: \(avgCurrentPE.formatted(.number.precision(.fractionLength(1))))x\n"
                prompt += "Watchlist Average PEG Ratio: \(avgPEG.formatted(.number.precision(.fractionLength(2))))\n"
                prompt += "Bargain PEG Stocks (PEG ≤ 1.0): \(bargainPEGCount)\n"
                
                // 3. Top Opportunités triées par Upside potentiel
                prompt += "\n--- TOP ENTRY OPPORTUNITIES (By Fair Value Upside) ---\n"
                let sortedByUpside = items.sorted { $0.fairPriceUpsidePercent(marginOfSafety: activeMoS) > $1.fairPriceUpsidePercent(marginOfSafety: activeMoS) }
                
                for item in sortedByUpside.prefix(5) { // On lui donne le Top 5 pour cibler l'analyse
                    let upside = item.fairPriceUpsidePercent(marginOfSafety: activeMoS) * 100
                    let fairP = item.fairPrice(marginOfSafety: activeMoS)
                    prompt += "- \(item.ticker): Price = \(item.currentPrice.formatted(.currency(code: item.currency))) | Fair Price = \(fairP > 0 ? fairP.formatted(.currency(code: item.currency)) : "N/A") | Upside = \(upside.formatted(.number.precision(.fractionLength(1))))% | PE = \(item.currentPE > 0 ? "\(item.currentPE)x" : "N/A") | PEG = \(item.peg > 0 ? "\(item.peg)" : "N/A")\n"
                }
                
                prompt += """
                \nTask: Act as a Senior Equity Analyst reviewing a prospective stock watchlist.
                1. Evaluate the overall valuation temperature of the watchlist based on aggregate multiples (Average P/E, PEG).
                2. Identify the highest-conviction entry opportunities from the 'Top Entry Opportunities' list, balancing deep value (High Upside) and growth at a reasonable price (Low PEG).
                3. Warn against potential 'value traps' (e.g., stocks with high upside but questionable multiples or missing data).
                4. Provide 2-3 precise, actionable recommendations on which specific stocks the user should deploy capital into right now.
                Be highly analytical, objective, and use professional equity research terminology (e.g., 'multiple expansion', 'margin of safety cushion', 'GARP profile', 'value trap'). Use bolding for metrics and tickers.
                """
            } else {
                prompt += "The watchlist is currently empty.\n"
                prompt += "Task: Advise the user on the importance of building a prospective watchlist to monitor market opportunities."
            }

        case .exposure:
            // 1. Recréation des calculs de pondération géographique
            let totalVal = viewModel.totalValue
            var usaWeightedValue = 0.0
            var rowWeightedValue = 0.0
            var unknownWeightedValue = 0.0
            var regionalExposureDict: [String: Double] = [:]
            var fxRiskDict: [String: Double] = ["USD (Americas)": 0, "EUR/GBP (EMEA)": 0, "JPY/CNY (Asia)": 0, "Other / Emerging": 0]
            var sectorRegionDict: [String: Double] = [:]
            
            for pos in viewModel.positions {
                let posWeight = totalVal > 0 ? (pos.currentValueEUR / totalVal) : 0
                let exposures = pos.revenueExposures ?? []
                var knownPct = 0.0
                
                for exp in exposures {
                    let weightedExp = posWeight * (exp.percentage / 100.0)
                    if exp.isUSA { usaWeightedValue += weightedExp } else { rowWeightedValue += weightedExp }
                    
                    regionalExposureDict[exp.regionName, default: 0] += weightedExp
                    knownPct += exp.percentage
                    
                    let sec = pos.sector.isEmpty ? "Unknown Sector" : pos.sector
                    sectorRegionDict["\(sec) in \(exp.regionName)", default: 0] += weightedExp
                    
                    let name = exp.regionName.lowercased()
                    if name.contains("us") || name.contains("america") { fxRiskDict["USD (Americas)", default: 0] += weightedExp }
                    else if name.contains("eu") || name.contains("emea") || name.contains("uk") { fxRiskDict["EUR/GBP (EMEA)", default: 0] += weightedExp }
                    else if name.contains("asia") || name.contains("apac") || name.contains("china") || name.contains("japan") { fxRiskDict["JPY/CNY (Asia)", default: 0] += weightedExp }
                    else { fxRiskDict["Other / Emerging", default: 0] += weightedExp }
                }
                
                let unknownPct = max(0, 100.0 - knownPct)
                if unknownPct > 0 {
                    let unknownW = posWeight * (unknownPct / 100.0)
                    unknownWeightedValue += unknownW
                }
            }
            
            let fullyMappedCount = viewModel.positions.filter { ($0.revenueExposures ?? []).reduce(0) { $0 + $1.percentage } >= 100.0 }.count
            
            prompt += "\n--- MACRO & GEOGRAPHIC EXPOSURE OVERVIEW ---\n"
            prompt += "Data Quality: \(fullyMappedCount) out of \(viewModel.positions.count) stocks are fully mapped.\n"
            prompt += "USA Revenue Exposure: \((usaWeightedValue * 100).formatted(.number.precision(.fractionLength(1))))%\n"
            prompt += "Rest of World (ROW) Exposure: \((rowWeightedValue * 100).formatted(.number.precision(.fractionLength(1))))%\n"
            prompt += "Unassigned/Unknown Exposure: \((unknownWeightedValue * 100).formatted(.number.precision(.fractionLength(1))))%\n"
            
            prompt += "\n--- TOP DOMINANT MARKETS ---\n"
            let sortedMarkets = regionalExposureDict.sorted { $0.value > $1.value }.prefix(5)
            for market in sortedMarkets {
                prompt += "- \(market.key): \((market.value * 100).formatted(.number.precision(.fractionLength(1))))% portfolio weight\n"
            }
            
            prompt += "\n--- FX RISK (CURRENCY EXPOSURE MATRIX) ---\n"
            for (zone, weight) in fxRiskDict.sorted(by: { $0.value > $1.value }) {
                prompt += "- \(zone): \((weight * 100).formatted(.number.precision(.fractionLength(1))))%\n"
            }
            
            prompt += "\n--- HIGHEST RISK CONCENTRATIONS (Sector × Geography) ---\n"
            let sortedSectorRegions = sectorRegionDict.sorted { $0.value > $1.value }.prefix(3)
            for sr in sortedSectorRegions {
                prompt += "- \(sr.key): \((sr.value * 100).formatted(.number.precision(.fractionLength(1))))% of total portfolio\n"
            }
            
            prompt += """
            \nTask: Act as a Global Macro Analyst and Chief Risk Officer. Perform an institutional-grade assessment of this portfolio's geographic revenue exposure.
            1. Evaluate the geopolitical and macro-economic risk based on the 'Top Dominant Markets' and 'USA vs ROW' breakdown. Is the portfolio suffering from extreme 'home bias' or over-dependence on a single economy?
            2. Analyze the 'FX Risk Matrix'. Comment on the currency exposure and potential headwinds/tailwinds from foreign exchange fluctuations.
            3. Review the 'Highest Risk Concentrations (Sector × Geography)' and warn about specific supply chain, regulatory, or cyclical vulnerabilities.
            4. Provide 2-3 strategic, actionable recommendations to hedge geographic risk or capitalize on emerging market opportunities.
            Be highly analytical, objective, and use professional macro-investing terminology (e.g., 'home bias', 'FX headwinds', 'geopolitical tail risks', 'revenue diversification'). Use bolding for metrics and regions.
            """
            
        case .transactions:
            let txs = viewModel.transactions
            
            // 1. Calcul des flux de trésorerie (Cash Flow)
            let totalDeposited = txs.filter { $0.type == .deposit }.reduce(0) { $0 + $1.amountEUR }
            let totalWithdrawn = txs.filter { $0.type == .withdrawal }.reduce(0) { $0 + $1.amountEUR }
            let netCashFlow = totalDeposited - totalWithdrawn
            
            // 2. Calcul du capital déployé
            let totalBought = txs.filter { $0.type == .buy }.reduce(0) { $0 + $1.amountEUR }
            let totalSold = txs.filter { $0.type == .sell }.reduce(0) { $0 + $1.amountEUR }
            let netInvested = totalBought - totalSold
            
            // 3. Calcul des frictions (Taxes & Frais)
            let totalFees = txs.reduce(0) { $0 + $1.customFields.values.reduce(0, +) }
            let feeDragRatio = totalBought > 0 ? (totalFees / totalBought) * 100 : 0
            
            prompt += "\n--- CASH FLOW & CAPITAL DEPLOYMENT ---\n"
            prompt += "Lifetime Deposits: \(totalDeposited.formatted(.currency(code: currency)))\n"
            prompt += "Lifetime Withdrawals: \(totalWithdrawn.formatted(.currency(code: currency)))\n"
            prompt += "Net Cash Flow (Capital injected by user): \(netCashFlow.formatted(.currency(code: currency)))\n"
            prompt += "Total Assets Bought: \(totalBought.formatted(.currency(code: currency)))\n"
            prompt += "Total Assets Sold: \(totalSold.formatted(.currency(code: currency)))\n"
            prompt += "Net Capital Deployed in Markets: \(netInvested.formatted(.currency(code: currency)))\n"
            
            prompt += "\n--- TRADING FRICTION (TAXES & FEES) ---\n"
            prompt += "Total Frictional Costs: \(totalFees.formatted(.currency(code: currency)))\n"
            prompt += "Fee Drag Ratio (Fees / Total Bought): \(feeDragRatio.formatted(.number.precision(.fractionLength(2))))%\n"
            if !viewModel.transactionCustomColumns.isEmpty {
                prompt += "Fee Breakdown:\n"
                for col in viewModel.transactionCustomColumns {
                    let colTotal = txs.reduce(0) { $0 + ($1.customFields[col] ?? 0) }
                    prompt += "- \(col): \(colTotal.formatted(.currency(code: currency)))\n"
                }
            }
            
            prompt += "\n--- BEHAVIORAL METRICS ---\n"
            prompt += "Total Transactions Logged: \(txs.count)\n"
            prompt += "Buy Orders: \(txs.filter { $0.type == .buy }.count)\n"
            prompt += "Sell Orders: \(txs.filter { $0.type == .sell }.count)\n"
            
            let sortedTx = txs.sorted { $0.date > $1.date }
            if !sortedTx.isEmpty {
                prompt += "\n--- RECENT ACTIVITY (LAST 5 TRANSACTIONS) ---\n"
                let df = DateFormatter(); df.dateStyle = .short
                for tx in sortedTx.prefix(5) {
                    prompt += "- \(df.string(from: tx.date)): \(tx.type.rawValue.uppercased()) \(tx.ticker.isEmpty ? "CASH" : tx.ticker) | \(tx.amountEUR.formatted(.currency(code: currency)))\n"
                }
            }
            
            prompt += """
            \nTask: Act as an institutional Portfolio Risk Manager and Quantitative Analyst reviewing the user's transaction ledger.
            1. Evaluate the capital deployment velocity: Is the user effectively deploying their Net Cash Flow into the markets, or is too much cash sitting idle?
            2. Deeply analyze the 'Trading Friction': Assess the impact of fees and taxes (Fee Drag Ratio) on the portfolio. Is the tax drag within acceptable institutional limits (< 1.0%), or does it indicate severe structural inefficiencies?
            3. Review the 'Behavioral Metrics' (Buy/Sell ratio and Recent Activity). Does the ledger reflect a disciplined, long-term compounding strategy (high buy-to-sell ratio), or speculative churn/over-trading?
            4. Provide 2-3 strict, actionable recommendations to minimize frictional costs (taxes/fees) and optimize the timing of capital injections.
            Be highly analytical, objective, and use professional quantitative terminology (e.g., 'frictional drag', 'portfolio turnover', 'capital deployment efficiency', 'buy-to-hold discipline'). Use bolding for metrics and emphasize structural inefficiencies if any.
            """
            
        case .benchmark:
            // 1. Définition de la période
            let currentYear = Calendar.current.component(.year, from: Date())
            let startYear = viewModel.dividendStartYear
            let allYears = Array(startYear...currentYear)
            
            // 2. Calcul des rendements du portefeuille
            var portfolioReturns: [Int: Double] = [:]
            for year in allYears {
                if let yearData = viewModel.growthYears.first(where: { $0.year == year }) {
                    let isCurrentYear = year == currentYear
                    let effectiveEnd = isCurrentYear ? viewModel.currentTotalCapital : yearData.endWallet
                    let base = yearData.startWallet + yearData.invested
                    portfolioReturns[year] = base > 0 ? ((effectiveEnd - base) / base) * 100.0 : 0
                } else {
                    portfolioReturns[year] = 0
                }
            }
            
            let portfolioAvgReturn = !allYears.isEmpty ? allYears.map { portfolioReturns[$0] ?? 0 }.reduce(0, +) / Double(allYears.count) : 0
            
            // 3. Récupération du meilleur indice et calcul de l'Alpha
            let bestIndex = viewModel.benchmarkIndices.max { a, b in
                a.averageReturn(years: allYears) < b.averageReturn(years: allYears)
            }
            let bestIndexAvgReturn = bestIndex?.averageReturn(years: allYears) ?? 0
            let alpha = portfolioAvgReturn - bestIndexAvgReturn
            
            // 4. Calcul de la simulation 10,000 EUR
            var portfolio10k = 10000.0
            for y in allYears { portfolio10k *= (1 + (portfolioReturns[y] ?? 0) / 100.0) }
            
            var best10k = 10000.0
            if let best = bestIndex {
                for y in allYears { best10k *= (1 + (best.returns[y] ?? 0) / 100.0) }
            }
            
            prompt += "\n--- RELATIVE PERFORMANCE (BENCHMARKING) ---\n"
            prompt += "Tracking Period: \(allYears.count) years (\(startYear) - \(currentYear))\n"
            prompt += "Indices Tracked: \(viewModel.benchmarkIndices.count) (\(viewModel.benchmarkIndices.map { $0.name }.joined(separator: ", ")))\n"
            
            prompt += "\n--- ALPHA GENERATION ---\n"
            prompt += "Portfolio Average Annual Return: \(portfolioAvgReturn.formatted(.number.precision(.fractionLength(2))))%\n"
            if let best = bestIndex {
                prompt += "Best Performing Benchmark (\(best.name)): \(bestIndexAvgReturn.formatted(.number.precision(.fractionLength(2))))%\n"
                prompt += "Generated Alpha (vs Best Index): \(alpha > 0 ? "+" : "")\(alpha.formatted(.number.precision(.fractionLength(2))))%\n"
            } else {
                prompt += "No benchmarks defined yet.\n"
            }
            
            prompt += "\n--- 10,000 \(currency) SIMULATION (COMPOUNDING IMPACT) ---\n"
            prompt += "Portfolio Final Value: \(portfolio10k.formatted(.currency(code: currency)))\n"
            if bestIndex != nil {
                prompt += "Best Benchmark Final Value: \(best10k.formatted(.currency(code: currency)))\n"
                let opportunityCost = portfolio10k - best10k
                prompt += "Opportunity Cost (vs Index): \(opportunityCost.formatted(.currency(code: currency).sign(strategy: .always())))\n"
            }
            
            prompt += "\n--- USER GOALS ---\n"
            prompt += "Target Alpha (Outperformance Goal): \(viewModel.benchmarkGoalTarget)%\n"
            
            prompt += """
            \nTask: Act as an institutional Portfolio Manager evaluating 'Active Risk' and 'Alpha Generation'.
            1. Analyze the portfolio's relative performance against its benchmarks. Is the active management strategy actually adding value (positive Alpha) or destroying wealth (negative Alpha) compared to a passive index?
            2. Evaluate the compounding effect using the 10,000 \(currency) simulation data. Discuss the absolute 'Opportunity Cost' if the portfolio is lagging behind the best index.
            3. Assess the user's progress towards their Target Alpha goal.
            4. Provide 2-3 actionable, professional recommendations. Should the user index a larger core portion of their portfolio? Re-evaluate their stock picking? Adjust their active risk profile?
            Be highly analytical, objective, and use professional performance measurement terminology (e.g., 'alpha generation', 'opportunity cost', 'active management drag', 'relative outperformance'). Use bolding for metrics.
            """

        case .calendar:
            let today = Calendar.current.startOfDay(for: Date())
            let currentYear = Calendar.current.component(.year, from: Date())
            let df = DateFormatter()
            df.dateStyle = .medium
            df.timeStyle = .none
            
            // 1. Recréation des événements virtuels (Anniversaires et Macro) pour les donner à l'IA
            var allEvents = viewModel.calendarEvents
            
            // Les 4 sorcières (Quadruple Witching)
            for month in [3, 6, 9, 12] {
                if let witchingDate = USMarketHolidayHelper.nthWeekday(nth: 3, weekday: 6, month: month, year: currentYear) {
                    allEvents.append(CalendarEvent(id: UUID(), date: witchingDate, type: .macro, ticker: "MARKET", note: "Quadruple Witching Day"))
                }
            }
            
            // Anniversaires d'achat
            for pos in viewModel.positions {
                let pYear = Calendar.current.component(.year, from: pos.purchaseDate)
                let yearsHeld = currentYear - pYear
                if yearsHeld > 0 {
                    var comps = Calendar.current.dateComponents([.month, .day], from: pos.purchaseDate)
                    comps.year = currentYear
                    if let annivDate = Calendar.current.date(from: comps) {
                        allEvents.append(CalendarEvent(id: UUID(), date: annivDate, type: .anniversary, ticker: pos.ticker, note: "Holding for \(yearsHeld) Years"))
                    }
                }
            }

            
            // 2. Filtrage des événements futurs et des jours fériés
            let upcomingEvents = allEvents.filter { Calendar.current.startOfDay(for: $0.date) >= today }.sorted { $0.date < $1.date }
            let nextHolidays = USMarketHolidayHelper.getHolidays(forYear: currentYear).filter { $0.date >= today }.sorted { $0.date < $1.date }
            
            prompt += "\n--- MACRO & MICRO EVENT HORIZON ---\n"
            prompt += "Current Date: \(df.string(from: today))\n"
            prompt += "Total Upcoming Scheduled Events: \(upcomingEvents.count)\n"
            
            prompt += "\n--- NEXT 7 UPCOMING CATALYSTS & EVENTS ---\n"
            if upcomingEvents.isEmpty {
                prompt += "No upcoming events scheduled.\n"
            } else {
                for event in upcomingEvents.prefix(7) {
                    prompt += "- \(df.string(from: event.date)) | **\(event.ticker)**: \(event.type.rawValue.uppercased()) (\(event.note.isEmpty ? "No specific note" : event.note))\n"
                }
            }
            
            prompt += "\n--- UPCOMING MARKET HOLIDAYS (LIQUIDITY CONSTRAINTS) ---\n"
            if let nextHoliday = nextHolidays.first {
                prompt += "- Next market closure: \(nextHoliday.name) on \(df.string(from: nextHoliday.date))\n"
            } else {
                prompt += "No upcoming holidays in the current year.\n"
            }
            
            prompt += """
            \nTask: Act as an institutional Event-Driven Analyst and Portfolio Strategist reviewing the upcoming calendar.
            1. Summarize the immediate event horizon. Are we entering a high-volatility earnings season, a period of dividend cash flows, or facing macro liquidity events (e.g., Quadruple Witching)?
            2. Identify specific 'Volatility Catalysts' (Earnings/Macro) versus 'Cash Flow Events' (Dividends) from the upcoming list.
            3. Note the next market holiday and briefly mention its potential impact on short-term trading liquidity.
            4. Provide tactical guidance on how to navigate these dates (e.g., "prepare to deploy incoming dividend cash", "brace for idiosyncratic volatility on ticker X", "review thesis for anniversary holdings").
            Be highly analytical, objective, and use professional event-driven terminology (e.g., 'catalyst horizon', 'liquidity constraints', 'idiosyncratic risk', 'corporate actions'). Use bolding for dates and tickers.
            """

        case .wealth:
            // 1. Synthèse du bilan comptable (Balance Sheet)
            let trueNetWorth = viewModel.trueNetWorth
            let totalAssets = viewModel.totalAssets
            let totalLiabilities = viewModel.totalLiabilities
            let debtToAssetRatio = viewModel.debtToAssetRatio * 100
            let assetsROI = viewModel.totalWealthVariationPercent * 100
            let stockWeight = viewModel.wealthStockWeight * 100
            let wealthProgress = viewModel.wealthGoalProgress * 100
            
            prompt += "\n--- BALANCE SHEET OVERVIEW ---\n"
            prompt += "Total Assets: \(totalAssets.formatted(.currency(code: currency)))\n"
            prompt += "Total Liabilities (Debt): \(totalLiabilities.formatted(.currency(code: currency)))\n"
            prompt += "True Net Worth: \(trueNetWorth.formatted(.currency(code: currency)))\n"
            prompt += "Debt-to-Asset Ratio (Leverage): \(debtToAssetRatio.formatted(.number.precision(.fractionLength(1))))%\n"
            
            prompt += "\n--- ASSET ALLOCATION (MACRO) ---\n"
            prompt += "Overall Assets ROI: \(assetsROI.formatted(.number.precision(.fractionLength(2))))%\n"
            prompt += "Brokerage (Stock Portfolio) Weight: \(stockWeight.formatted(.number.precision(.fractionLength(1))))% of total assets\n"
            
            let sortedAssets = viewModel.allWealthAssets.sorted { $0.current > $1.current }.prefix(5)
            for asset in sortedAssets {
                let weight = totalAssets > 0 ? (asset.current / totalAssets) * 100 : 0
                prompt += "- \(asset.name): \(asset.current.formatted(.currency(code: currency))) (\(weight.formatted(.number.precision(.fractionLength(1))))% weight) | ROI: \(asset.variationPercent.formatted(.percent.precision(.fractionLength(1))))\n"
            }
            
            prompt += "\n--- LIABILITIES & DEBT STRUCTURE ---\n"
            if !viewModel.manualWealthLiabilities.isEmpty {
                let sortedLiabilities = viewModel.manualWealthLiabilities.sorted { $0.amount > $1.amount }.prefix(5)
                for liab in sortedLiabilities {
                    let leftPct = liab.initialAmount > 0 ? (liab.amount / liab.initialAmount) * 100 : 0
                    prompt += "- \(liab.name): Owed \(liab.amount.formatted(.currency(code: currency))) (\(leftPct.formatted(.number.precision(.fractionLength(1))))% of principal left to pay)\n"
                }
            } else {
                prompt += "No liabilities recorded. The user is currently 100% debt-free.\n"
            }
            
            prompt += "\n--- FIRE (FINANCIAL INDEPENDENCE) SIMULATOR ---\n"
            prompt += "Safe Withdrawal Rate (SWR) Assumption: \(viewModel.safeWithdrawalRate.formatted(.number.precision(.fractionLength(1))))%\n"
            prompt += "Estimated Passive Income: \(viewModel.fireAnnualIncome.formatted(.currency(code: currency)))/year (\(viewModel.fireMonthlyIncome.formatted(.currency(code: currency)))/month)\n"
            
            prompt += "\n--- WEALTH TARGETS ---\n"
            prompt += "Target Net Worth: \(viewModel.wealthGoalTarget.formatted(.currency(code: currency)))\n"
            prompt += "Current Goal Progress: \(min(wealthProgress, 100).formatted(.number.precision(.fractionLength(1))))%\n"
            
            prompt += """
            \nTask: Act as a high-net-worth Private Wealth Manager and Financial Planner. Perform a holistic, institutional-grade analysis of this user's overall balance sheet.
            1. Evaluate the 'Balance Sheet Health' focusing on the Debt-to-Asset ratio. Is the user over-leveraged, under-leveraged, or managing debt efficiently?
            2. Analyze the Macro Asset Allocation (e.g., brokerage weight vs. manual assets like real estate or crypto). Is the overall wealth appropriately diversified across different asset classes?
            3. Assess the 'FIRE Trajectory'. Based on their current True Net Worth and Safe Withdrawal Rate (SWR), is the projected passive income robust enough for financial independence, and what are the sequence-of-returns risks?
            4. Provide 2-3 strategic, actionable recommendations on how to optimize liability management (debt paydown vs investing), accelerate net worth compounding, or improve asset class diversification.
            Be highly analytical, objective, and use professional wealth management terminology (e.g., 'leverage ratio', 'asset class diversification', 'sequence of returns risk', 'liability management', 'illiquidity premium'). Use bolding for metrics and asset names.
            """
            
        default:
            prompt += "\nTask: Give a general health check of the portfolio based on the provided metrics."
        }
        
        return prompt
    }
    
    // ==========================================
    // LOGIQUE DE DISCUSSION CONTINUE
    // ==========================================
    private func sendMessage() {
        guard !inputText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        
        let userText = inputText
        let newUserMsg = ChatMessage(role: "user", text: userText)
        messages.append(newUserMsg)
        inputText = ""
        isThinking = true
        
        let systemPrompt = generateSystemPrompt()
        
        Task {
            do {
                // On envoie le premier message caché + l'historique visible
                var apiMessages = [ChatMessage(role: "user", text: "Analyze the current page data.")]
                apiMessages.append(contentsOf: messages)
                
                let response = try await GeminiService.shared.generateChatResponse(systemPrompt: systemPrompt, messages: apiMessages, apiKey: geminiApiKey)
                
                await MainActor.run {
                    messages.append(ChatMessage(role: "model", text: response))
                    // NOUVEAU : On sauvegarde la discussion mise à jour !
                    ChatHistoryManager.shared.save(messages, for: currentTab.rawValue)
                    isThinking = false
                }
            } catch {
                await MainActor.run {
                    messages.append(ChatMessage(role: "model", text: "⚠️ Error: \(error.localizedDescription)"))
                    // NOUVEAU : On sauvegarde même s'il y a une erreur
                    ChatHistoryManager.shared.save(messages, for: currentTab.rawValue)
                    isThinking = false
                }
            }
        }
    }
}

// =========================================================================
// MARK: - COMPOSANT BULLE DE CHAT (AVEC COPIE & ESPACEMENT PARFAIT)
// =========================================================================
struct ChatBubble: View {
    let message: ChatMessage
    @State private var showCopiedFeedback: Bool = false
    
    var isUser: Bool {
        message.role == "user"
    }
    
    // Nettoyage de sécurité au cas où l'IA s'entête à utiliser des symboles interdits
    var cleanedText: String {
        message.text
            .replacingOccurrences(of: "### ", with: "")
            .replacingOccurrences(of: "###", with: "")
            .replacingOccurrences(of: "---", with: "")
    }
    
    var body: some View {
        HStack {
            if isUser { Spacer() }
            
            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                HStack(spacing: 6) {
                    if !isUser {
                        Image("AI")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20) // Ajuste la taille selon tes préférences
                            .foregroundColor(.secondary) // Ça marchera grâce au "Template Image" !

                    }
                    Text(isUser ? "You" : "BlueChip AI")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    // L'astuce magique: inlineOnlyPreservingWhitespace empêche SwiftUI d'écraser les sauts de ligne !
                    if let mdText = try? AttributedString(markdown: cleanedText, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                        Text(mdText)
                            .lineSpacing(6)
                            .padding(14)
                            .background(isUser ? Color.blue : Color(NSColor.controlBackgroundColor))
                            .foregroundColor(isUser ? .white : .primary)
                            .cornerRadius(12)
                    } else {
                        Text(cleanedText)
                            .lineSpacing(6)
                            .padding(14)
                            .background(isUser ? Color.blue : Color(NSColor.controlBackgroundColor))
                            .foregroundColor(isUser ? .white : .primary)
                            .cornerRadius(12)
                    }
                    
                    // BOUTON DE COPIE POUR L'IA
                    if !isUser {
                        Button(action: {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(cleanedText, forType: .string)
                            withAnimation { showCopiedFeedback = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                withAnimation { showCopiedFeedback = false }
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: showCopiedFeedback ? "checkmark" : "doc.on.clipboard")
                                Text(showCopiedFeedback ? "Copied!" : "Copy")
                            }
                            .font(.caption2)
                            .foregroundColor(showCopiedFeedback ? .green : .secondary)
                            .padding(.leading, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: 600, alignment: isUser ? .trailing : .leading)
            
            if !isUser { Spacer() }
        }
    }
}
