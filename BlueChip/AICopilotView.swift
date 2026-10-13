import SwiftUI

struct AICopilotView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: PortfolioViewModel
    let currentTab: AppTab
    
    @AppStorage("geminiApiKey") private var geminiApiKey: String = ""
    
    @State private var messages: [ChatMessage] = []
    @State private var inputText: String = ""
    @State private var isThinking: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            // HEADER
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(.blue)
                Text("BlueChip AI Copilot")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("• \(currentTab.rawValue) Analysis")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Spacer()
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
                        LazyVStack(spacing: 16) {
                            ForEach(messages) { message in
                                ChatBubble(message: message)
                                    .id(message.id)
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
                        withAnimation { proxy.scrollTo(messages.last?.id, anchor: .bottom) }
                    }
                    .onChange(of: isThinking) { _ in
                        if isThinking { withAnimation { proxy.scrollTo("thinking", anchor: .bottom) } }
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
                startInitialAnalysis()
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
                // On crée un message utilisateur "caché" pour lancer l'analyse sans l'afficher dans l'UI
                let hiddenInitialMessage = ChatMessage(role: "user", text: "Analyze the current page data.")
                
                let response = try await GeminiService.shared.generateChatResponse(systemPrompt: systemPrompt, messages: [hiddenInitialMessage], apiKey: geminiApiKey)
                
                await MainActor.run {
                    // On n'affiche QUE la réponse du modèle !
                    messages.append(ChatMessage(role: "model", text: response))
                    isThinking = false
                }
            } catch {
                await MainActor.run {
                    messages.append(ChatMessage(role: "model", text: "⚠️ Error: \(error.localizedDescription)"))
                    isThinking = false
                }
            }
        }
    }
    
    private func generateSystemPrompt() -> String {
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
        Total Portfolio Value: \(viewModel.currentTotalCapital) EUR
        Total Cash Available: \(viewModel.availableCash) EUR
        Total Positions: \(viewModel.positions.count)
        
        """
        
        switch currentTab {
        case .composition:
            prompt += "\n--- COMPOSITION DATA ---\n"
            if let topPos = viewModel.positions.max(by: { $0.currentValueEUR < $1.currentValueEUR }) {
                prompt += "Top Position: \(topPos.ticker) (\(topPos.currentValueEUR) EUR)\n"
            }
            prompt += "Task: Analyze the diversification and asset allocation. Point out any concentration risks."
            
        case .dividends:
            prompt += "\n--- DIVIDEND DATA ---\n"
            prompt += "Projected Annual Dividends: \(viewModel.totalDividends) EUR\n"
            prompt += "Portfolio Yield: \((viewModel.portfolioYield * 100).formatted(.number.precision(.fractionLength(2))))%\n"
            let payingCount = viewModel.positions.filter { $0.totalDividendEUR > 0 }.count
            prompt += "Dividend-paying stocks: \(payingCount) out of \(viewModel.positions.count)\n"
            prompt += "Task: Analyze the dividend yield and income generation. Is it sustainable? What strategy is the user likely following?"
            
        case .growth:
            let invested = viewModel.manuallyInvested > 0 ? viewModel.manuallyInvested : viewModel.positionsInvestedSum
            let gain = viewModel.currentTotalCapital - invested
            prompt += "\n--- GROWTH DATA ---\n"
            prompt += "Total Invested: \(invested) EUR\n"
            prompt += "Unrealized Gain/Loss: \(gain) EUR\n"
            prompt += "Task: Analyze the capital appreciation. Comment on the return on investment."
            
        case .valuation:
            let moS = UserDefaults.standard.double(forKey: "valuation_marginOfSafety")
            let undervalued = viewModel.positions.filter { $0.currentPrice < $0.fairPrice(marginOfSafety: moS > 0 ? moS : 10.0) && $0.fairPrice(marginOfSafety: moS > 0 ? moS : 10.0) > 0 }.count
            prompt += "\n--- VALUATION DATA ---\n"
            prompt += "User's Margin of Safety: \(moS > 0 ? moS : 10.0)%\n"
            prompt += "Undervalued stocks (vs Fair Price): \(undervalued)\n"
            prompt += "Task: Review the valuation metrics. Are there bargains? Warn about overvalued assets if any."
            
        case .wealth:
            prompt += "\n--- WEALTH & FIRE DATA ---\n"
            prompt += "True Net Worth: \(viewModel.trueNetWorth) EUR\n"
            prompt += "Total Liabilities: \(viewModel.totalLiabilities) EUR\n"
            prompt += "SWR (Safe Withdrawal Rate): \(viewModel.safeWithdrawalRate)%\n"
            prompt += "Monthly Passive Income Estimate: \(viewModel.fireMonthlyIncome) EUR\n"
            prompt += "Task: Evaluate the user's progress towards Financial Independence (FIRE). Comment on the debt-to-asset ratio."
            
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
                    isThinking = false
                }
            } catch {
                await MainActor.run {
                    messages.append(ChatMessage(role: "model", text: "⚠️ Error: \(error.localizedDescription)"))
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
                        Image(systemName: "sparkles")
                            .font(.caption2)
                            .foregroundColor(.blue)
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

