import SwiftUI
import SwiftData

// =========================================================================
// TAGS ET SECTIONS POUR LES FILTRES
// =========================================================================
let thesisTags = [
    "Quarterly Earnings", "Annual Report", "Buy", "Sell",
    "Macro Event", "Dividend Raise", "Dividend Reduction",
    "Stock-Split", "Reverse-Split", "News", "Other"
]

let thesisSections = [
    "Business Anatomy",
    "Competitive Advantage",
    "Bear Case Threats",
    "Exit Strategy",
    "Post-Mortem"
]

// =========================================================================
// VUE PRINCIPALE DE LA THESIS
// =========================================================================
struct ThesisView: View {
    @ObservedObject var viewModel: PortfolioViewModel
    @Binding var privacyMode: Bool
    
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Position.ticker) private var positions: [Position]
    @Query(sort: \WatchlistItem.ticker) private var watchlistItems: [WatchlistItem]
    @Query private var thesisList: [InvestmentJournal]
    
    @State private var editingTicker: String? = nil
    @State private var readingLogEntry: GlobalJournalEntry? = nil
    @State private var showAddLogSheet: Bool = false
    
    // Filtres
    @State private var searchText = ""
    @State private var selectedLogTag = "All Events"
    @State private var selectedSection = "All Sections"
    
    // Grille 2 par 2 pour les logs
    let logColumns = [
        GridItem(.flexible(), spacing: 20),
        GridItem(.flexible(), spacing: 20)
    ]
    
    // Toutes les entités combinées pour le Picker du Add Log
    var allTrackedTickers: [String] {
        let posTickers = positions.map { $0.ticker }
        let watchTickers = watchlistItems.map { $0.ticker }
        return Array(Set(posTickers + watchTickers)).sorted()
    }
    
    // 1. Filtrage des Logs
    var filteredLogs: [GlobalJournalEntry] {
        var allEntries: [GlobalJournalEntry] = []
        for thesis in thesisList {
            for entry in thesis.logEntries {
                allEntries.append(GlobalJournalEntry(ticker: thesis.ticker, entry: entry))
            }
        }
        
        let sorted = allEntries.sorted(by: { $0.entry.date > $1.entry.date })
        
        return sorted.filter { log in
            let matchesTag = (selectedLogTag == "All Events" || log.entry.tag == selectedLogTag)
            let matchesSearch = searchText.isEmpty ||
                                log.ticker.localizedCaseInsensitiveContains(searchText) ||
                                log.entry.content.localizedCaseInsensitiveContains(searchText)
            return matchesTag && matchesSearch
        }
    }
    
    // 2. Filtrage des Positions
    var filteredPositions: [Position] {
        let sorted = positions.sorted { $0.ticker < $1.ticker }
        if searchText.isEmpty && selectedSection == "All Sections" { return sorted }
        
        return sorted.filter { pos in
            let thesis = thesisList.first(where: { $0.ticker == pos.ticker }) ?? InvestmentJournal(ticker: pos.ticker)
            
            // Logique de filtrage par section
            var sectionMatches = false
            switch selectedSection {
            case "All Sections":
                sectionMatches = true
            case "Business Anatomy":
                sectionMatches = !thesis.valueProposition.isEmpty || !thesis.targetMarket.isEmpty || !thesis.leadership.isEmpty || !thesis.customers.isEmpty || !thesis.competitors.isEmpty || !thesis.revenueSegmentation.isEmpty || !thesis.sectorDynamics.isEmpty
            case "Competitive Advantage":
                 sectionMatches = thesis.hasNetworkEffect || thesis.hasSwitchingCosts || thesis.hasIntangibles || thesis.hasCostAdvantage || thesis.hasEfficientScale
            case "Bear Case Threats":
                sectionMatches = !thesis.bearCaseThreats.isEmpty
            case "Exit Strategy":
                sectionMatches = !thesis.exitStrategyRules.isEmpty
            case "Post-Mortem":
                sectionMatches = !thesis.postMortem.isEmpty
            default:
                sectionMatches = true
            }

            if !sectionMatches { return false }
            if searchText.isEmpty { return true }
            
            // Match direct sur le ticker ou le nom
            if pos.ticker.localizedCaseInsensitiveContains(searchText) || pos.companyName.localizedCaseInsensitiveContains(searchText) {
                return true
            }
            
            // Scan approfondi dans la thèse
            let allThesisText = [
                thesis.valueProposition, thesis.revenueSegmentation, thesis.customers,
                thesis.targetMarket, thesis.leadership, thesis.ownership,
                thesis.competitors, thesis.competitivePosition, thesis.sectorDynamics,
                thesis.networkEffectNotes, thesis.switchingCostsNotes, thesis.intangiblesNotes,
                thesis.costAdvantageNotes, thesis.efficientScaleNotes,
                thesis.bearCaseThreats.joined(separator: " "),
                thesis.exitStrategyRules.joined(separator: " "),
                thesis.postMortem
            ].joined(separator: " ")
            
            return allThesisText.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                
                // BARRE DE RECHERCHE, FILTRES ET BOUTON ADD LOG
                HStack(spacing: 16) {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                        TextField("Search ticker, content...", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(.body)
                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                            }.buttonStyle(.plain)
                        }
                    }
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(10)
                    .shadow(color: .black.opacity(0.05), radius: 2)
                    
                    Picker("", selection: $selectedLogTag) {
                        Text("All Events").tag("All Events")
                        Divider()
                        ForEach(thesisTags, id: \.self) { tag in
                            Text(tag).tag(tag)
                        }
                    }
                    .frame(width: 150)
                    .padding(10)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(10)
                    .shadow(color: .black.opacity(0.05), radius: 2)

                    Picker("", selection: $selectedSection) {
                        Text("All Sections").tag("All Sections")
                        Divider()
                        ForEach(thesisSections, id: \.self) { section in
                            Text(section).tag(section)
                        }
                    }
                    .frame(width: 180)
                    .padding(10)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(10)
                    .shadow(color: .black.opacity(0.05), radius: 2)
                    
                    Spacer()
                    
                    // NOUVEAU BOUTON ADD LOG
                    Button(action: { showAddLogSheet = true }) {
                        Label("Add Thesis Note", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                
                // 1. LE FIL D'ACTUALITÉ GLOBAL
                if !filteredLogs.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("Thesis Notes Tracker").font(.title2).fontWeight(.bold).foregroundColor(.secondary)
                            Spacer()
                        }.padding(.bottom, 4)
                        
                        LazyVGrid(columns: logColumns, spacing: 20) {
                            ForEach(filteredLogs) { globalEntry in
                                GlobalLogCard(globalEntry: globalEntry)
                                    .onTapGesture {
                                        readingLogEntry = globalEntry
                                    }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
                
                // 2. STACK DES ENTREPRISES
                VStack(spacing: 24) {
                    HStack {
                        Text("Positions Core Convictions").font(.title2).fontWeight(.bold).foregroundColor(.secondary)
                        Spacer()
                        Text("(Double-click a position to edit)").font(.caption).foregroundColor(.secondary).italic()
                    }.padding(.bottom, 4)

                    if filteredPositions.isEmpty {
                        VStack(spacing: 20) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 50))
                                .foregroundColor(.secondary.opacity(0.5))
                            Text("No thesis or logs match your search criteria.")
                                .font(.headline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 50)
                    } else {
                        ForEach(filteredPositions, id: \.ticker) { position in
                            let thesis = thesisList.first(where: { $0.ticker == position.ticker }) ?? InvestmentJournal(ticker: position.ticker)
                            
                            CompanyThesisCard(thesis: thesis, companyName: position.companyName, privacyMode: privacyMode, selectedSection: selectedSection)
                                .onTapGesture(count: 2) {
                                    editingTicker = position.ticker
                                }
                        }
                    }
                }
                .padding(.horizontal, 20)
                
                Spacer(minLength: 50)
            }
            .padding(.vertical, 20)
        }
        .background(Color(NSColor.windowBackgroundColor))
        
        .sheet(item: $readingLogEntry) { entry in
            LogEntryReaderSheet(globalEntry: entry, editingTicker: $editingTicker, readingLogEntry: $readingLogEntry)
        }
        .sheet(item: $editingTicker) { ticker in
            EditThesisSheet(ticker: ticker)
        }
        .sheet(isPresented: $showAddLogSheet) {
            AddLogEntrySheet(availableTickers: allTrackedTickers, isPresented: $showAddLogSheet)
        }
    }
}

// =========================================================================
// SHEET D'AJOUT RAPIDE DE LOG
// =========================================================================
struct AddLogEntrySheet: View {
    let availableTickers: [String]
    @Binding var isPresented: Bool
    
    @Environment(\.modelContext) private var modelContext
    @Query private var thesisList: [InvestmentJournal]
    
    @State private var selectedTicker: String
    @State private var date: Date = Date()
    @State private var tag: String = "Quarterly Earnings"
    @State private var sentiment: EventSentiment = .none
    @State private var content: String = ""
    
    init(availableTickers: [String], isPresented: Binding<Bool>) {
        self.availableTickers = availableTickers
        self._isPresented = isPresented
        _selectedTicker = State(initialValue: availableTickers.first ?? "")
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add Thesis Log").font(.title2).fontWeight(.bold)
                Spacer()
                Button(action: { isPresented = false }) { Image(systemName: "xmark.circle.fill").font(.title2).foregroundColor(.secondary) }.buttonStyle(.plain)
            }.padding()
            
            Divider()
            
            VStack(alignment: .leading, spacing: 16) {
                if availableTickers.isEmpty {
                    Text("No positions or watchlist items found. Add a stock first.")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                } else {
                    GroupBox {
                        VStack(spacing: 12) {
                            HStack {
                                Text("Company:")
                                Spacer()
                                Picker("", selection: $selectedTicker) {
                                    ForEach(availableTickers, id: \.self) { t in Text(t).tag(t) }
                                }
                                // Suppression du .frame(width: 200)
                            }
                            
                            HStack {
                                Text("Date:")
                                Spacer()
                                DatePicker("", selection: $date, displayedComponents: .date)
                                    .labelsHidden()
                            }
                            
                            HStack {
                                Text("Event Tag:")
                                Spacer()
                                Picker("", selection: $tag) {
                                    ForEach(thesisTags, id: \.self) { t in Text(t).tag(t) }
                                }
                                // Suppression du .frame(width: 200)
                            }
                            
                            HStack {
                                Text("Sentiment:")
                                Spacer()
                                Picker("", selection: $sentiment) {
                                    ForEach(EventSentiment.allCases, id: \.self) { s in Text(s.rawValue).tag(s) }
                                }
                                // Suppression du .frame(width: 200)
                            }
                        }
                    }
                    
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Content").fontWeight(.semibold)
                            // Agrandissement significatif de la zone de texte
                            TextEditor(text: $content)
                                .font(.body) // Assure une police lisible
                                .frame(maxHeight: .infinity) // Prend tout l'espace restant
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
                        }
                    }
                }
            }
            .padding()
            
            Spacer()
            Divider()
            
            HStack {
                Button("Cancel") { isPresented = false }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save Log") {
                    saveLog()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(selectedTicker.isEmpty || content.trimmingCharacters(in: .whitespaces).isEmpty)
            }.padding()
        }
        // Agrandissement de la modale en largeur et en hauteur
        .frame(width: 600, height: 700)
    }
    
    private func saveLog() {
        let thesis = thesisList.first(where: { $0.ticker == selectedTicker }) ?? {
            let newThesis = InvestmentJournal(ticker: selectedTicker)
            modelContext.insert(newThesis)
            return newThesis
        }()
        
        let newEntry = JournalEntry(date: date, tag: tag, content: content)
        newEntry.sentiment = sentiment
        thesis.logEntries.append(newEntry)
        
        try? modelContext.save()
        isPresented = false
    }
}

// =========================================================================
// CARTE D'AFFICHAGE DE LA THESE (PLEINE LARGEUR)
// =========================================================================
struct CompanyThesisCard: View {
    let thesis: InvestmentJournal
    let companyName: String
    var privacyMode: Bool
    var selectedSection: String = "All Sections"
    
    var showAnatomy: Bool {
        (selectedSection == "All Sections" || selectedSection == "Business Anatomy") &&
        (!thesis.valueProposition.isEmpty || !thesis.targetMarket.isEmpty || !thesis.leadership.isEmpty || !thesis.customers.isEmpty || !thesis.competitors.isEmpty || !thesis.revenueSegmentation.isEmpty || !thesis.sectorDynamics.isEmpty)
    }

    var showMoat: Bool {
         (selectedSection == "All Sections" || selectedSection == "Competitive Advantage") &&
         (thesis.hasNetworkEffect || thesis.hasSwitchingCosts || thesis.hasIntangibles || thesis.hasCostAdvantage || thesis.hasEfficientScale)
    }

    var showThreats: Bool {
        (selectedSection == "All Sections" || selectedSection == "Bear Case Threats") &&
        !thesis.bearCaseThreats.isEmpty
    }

    var showExit: Bool {
        (selectedSection == "All Sections" || selectedSection == "Exit Strategy") &&
        !thesis.exitStrategyRules.isEmpty
    }
    
    var showPostMortem: Bool {
        (selectedSection == "All Sections" || selectedSection == "Post-Mortem") &&
        !thesis.postMortem.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // HEADER STYLE SOBRE
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(thesis.ticker).font(.headline).fontWeight(.bold)
                    if !companyName.isEmpty {
                        Text(companyName).font(.caption).foregroundColor(.secondary)
                    }
                }
                
                // Pastille Status
                if thesis.thesisStatus != .none {
                    Circle()
                        .fill(thesis.thesisStatus.color)
                        .frame(width: 8, height: 8)
                        .padding(.leading, 8)
                }
                
                Spacer()
            }
            
            Divider()
            
            // 1. ANATOMY
            if showAnatomy {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Business Anatomy").font(.headline).fontWeight(.bold).foregroundColor(.blue)
                    ReadOnlyField(title: "Value Proposition", text: thesis.valueProposition)
                    ReadOnlyField(title: "Revenue Segmentation", text: thesis.revenueSegmentation)
                    ReadOnlyField(title: "Customers & Concentration", text: thesis.customers.isEmpty ? "" : "\(thesis.customers) | \(thesis.customerConcentration)")
                    ReadOnlyField(title: "Market Dynamics", text: thesis.targetMarket)
                    ReadOnlyField(title: "Management & Ownership", text: thesis.leadership.isEmpty ? "" : "\(thesis.leadership) | \(thesis.ownership)")
                    ReadOnlyField(title: "Competitors & Positioning", text: thesis.competitors.isEmpty ? "" : "\(thesis.competitors) | \(thesis.competitivePosition)")
                    ReadOnlyField(title: "Is the sector dynamic and future-oriented?", text: thesis.sectorDynamics)
                }
                Divider()
            }
            
            // 2. THE MOAT
            if showMoat {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Competitive Advantage").font(.headline).fontWeight(.bold).foregroundColor(.blue)
                    if thesis.hasNetworkEffect { ReadOnlyMoat(title: "Network Effect", notes: thesis.networkEffectNotes) }
                    if thesis.hasSwitchingCosts { ReadOnlyMoat(title: "Switching Costs", notes: thesis.switchingCostsNotes) }
                    if thesis.hasIntangibles { ReadOnlyMoat(title: "Intangibles", notes: thesis.intangiblesNotes) }
                    if thesis.hasCostAdvantage { ReadOnlyMoat(title: "Cost Advantage", notes: thesis.costAdvantageNotes) }
                    if thesis.hasEfficientScale { ReadOnlyMoat(title: "Efficient Scale", notes: thesis.efficientScaleNotes) }
                }
                Divider()
            }
            
            // 3 & 4. THREATS & EXIT STRATEGY
            if showThreats || showExit {
                HStack(alignment: .top, spacing: 30) {
                    if showThreats {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Bear Case Threats").font(.headline).fontWeight(.bold).foregroundColor(.orange)
                            ForEach(thesis.bearCaseThreats, id: \.self) { threat in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("• \(threat)").font(.callout).fontWeight(.semibold)
                                    if let notes = thesis.bearCaseNotes[threat], !notes.isEmpty {
                                        Text(notes).font(.caption).foregroundColor(.secondary).padding(.leading, 12)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    
                    if showExit {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Exit Strategy").font(.headline).fontWeight(.bold).foregroundColor(.red)
                            ForEach(thesis.exitStrategyRules, id: \.self) { rule in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("• \(rule)").font(.callout).fontWeight(.semibold)
                                    if let notes = thesis.exitStrategyNotes[rule], !notes.isEmpty {
                                        Text(notes).font(.caption).foregroundColor(.secondary).padding(.leading, 12)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Divider().padding(.top, 10)
            }
            
            // 5. POST-MORTEM
            if showPostMortem {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Post-Mortem (Lessons Learned)").font(.headline).fontWeight(.bold).foregroundColor(.purple)
                    Text(thesis.postMortem)
                        .font(.callout)
                        .italic()
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.purple.opacity(0.05))
                        .cornerRadius(8)
                }
            }
            
            if !showAnatomy && !showMoat && !showThreats && !showExit && !showPostMortem {
                Text("Double-click to start analyzing this company.")
                    .font(.body).foregroundColor(.secondary).italic()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                Text("Double-click to edit")
                    .font(.caption).foregroundColor(.secondary.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 10)
            }
        }
        .padding(30)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

// =========================================================================
// MODALE ZOOM POUR LE LOG
// =========================================================================
struct LogEntryReaderSheet: View {
    let globalEntry: GlobalJournalEntry
    @Environment(\.dismiss) var dismiss
    
    // Binding pour ouvrir la modale d'édition et fermer celle-ci
    @Binding var editingTicker: String?
    @Binding var readingLogEntry: GlobalJournalEntry?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("\(globalEntry.ticker) - Log Event Detail").font(.title2).fontWeight(.bold)
                Spacer()
                Button(action: {
                    readingLogEntry = nil
                    editingTicker = globalEntry.ticker
                }) {
                    HStack {
                        Image(systemName: "pencil")
                        Text("Edit")
                    }
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
                    .shadow(radius: 1)
                    .font(.subheadline)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 10)
                
                Button(action: { dismiss() }) { Image(systemName: "xmark.circle.fill").font(.title2).foregroundColor(.secondary) }.buttonStyle(.plain)
            }
            
            Divider()
            
            HStack {
                Text(globalEntry.entry.tag)
                    .font(.headline).fontWeight(.bold)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color.blue.opacity(0.1)).foregroundColor(.blue).cornerRadius(8)
                
                if globalEntry.entry.sentiment != .none {
                    HStack {
                        Circle().fill(globalEntry.entry.sentiment.color).frame(width: 10, height: 10)
                        Text(globalEntry.entry.sentiment.rawValue).font(.subheadline).foregroundColor(globalEntry.entry.sentiment.color)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(globalEntry.entry.sentiment.color.opacity(0.1)).cornerRadius(8)
                    .padding(.leading, 8)
                }
                
                Spacer()
                Text(globalEntry.entry.date, style: .date)
                    .font(.subheadline).foregroundColor(.secondary)
            }
            .padding(.vertical, 10)
            
            ScrollView {
                Text(globalEntry.entry.content)
                    .font(.body)
                    .lineSpacing(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(30)
        .frame(width: 600, height: 500)
    }
}

// =========================================================================
// MODALE D'ÉDITION DE LA THÈSE
// =========================================================================
struct EditThesisSheet: View {
    let ticker: String
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var thesisList: [InvestmentJournal]
    
    init(ticker: String) {
        self.ticker = ticker
        let predicate = #Predicate<InvestmentJournal> { $0.ticker == ticker }
        _thesisList = Query(filter: predicate)
    }
    
    var thesis: InvestmentJournal { thesisList.first ?? InvestmentJournal(ticker: ticker) }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Edit \(ticker) Thesis").font(.largeTitle).fontWeight(.heavy)
                Spacer()
                Button(action: { dismiss() }) { Image(systemName: "xmark.circle.fill").font(.title).foregroundColor(.secondary) }.buttonStyle(.plain)
            }
            .padding(24)
            
            Divider()
            
            ThesisEditorForm(thesis: thesis).padding(24)
            
            Divider()
            
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).controlSize(.large)
                Spacer()
                Button("Save Thesis") {
                    if thesisList.isEmpty { modelContext.insert(thesis) }
                    try? modelContext.save()
                    dismiss()
                }
                .buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction)
            }
            .padding(24)
        }
        .frame(width: 1000, height: 850)
    }
}

// =========================================================================
// SOUS-COMPOSANTS UTILITAIRES
// =========================================================================
extension String: Identifiable {
    public var id: String { self }
}

struct GlobalJournalEntry: Identifiable {
    var id: UUID { entry.id }
    let ticker: String
    let entry: JournalEntry
}

struct GlobalLogCard: View {
    let globalEntry: GlobalJournalEntry
    let dateFormatter: DateFormatter = { let f = DateFormatter(); f.dateStyle = .medium; return f }()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(globalEntry.ticker).font(.headline).fontWeight(.black)
                Spacer()
                Text(dateFormatter.string(from: globalEntry.entry.date)).font(.caption).foregroundColor(.secondary)
            }
            
            HStack {
                Text(globalEntry.entry.tag)
                    .font(.caption).fontWeight(.bold)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1)).foregroundColor(.blue).cornerRadius(6)
                
                if globalEntry.entry.sentiment != .none {
                    Circle()
                        .fill(globalEntry.entry.sentiment.color)
                        .frame(width: 10, height: 10)
                        .padding(.leading, 4)
                }
            }
            
            Text(globalEntry.entry.content)
                .font(.subheadline).lineLimit(3).multilineTextAlignment(.leading)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(14)
        .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 1)
    }
}

struct ReadOnlyField: View {
    let title: String; let text: String
    var body: some View {
        if !text.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.callout).fontWeight(.bold).foregroundColor(.secondary)
                Text(text).font(.callout).lineSpacing(4)
            }
            .padding(.bottom, 8)
        }
    }
}

struct ReadOnlyMoat: View {
    let title: String; let notes: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "checkmark.circle.fill").foregroundColor(.green).font(.callout)
                Text(title).font(.callout).fontWeight(.bold)
            }
            if !notes.isEmpty {
                Text(notes).font(.callout).foregroundColor(.secondary).padding(.leading, 24)
            }
        }
        .padding(.bottom, 8)
    }
}

// =========================================================================
// LE FORMULAIRE D'ÉDITION COMPLET
// =========================================================================
struct ThesisEditorForm: View {
    @Bindable var thesis: InvestmentJournal
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                
                // HEADER STATUS
                HStack {
                    Text("Conviction Status:").font(.headline)
                    Picker("", selection: $thesis.thesisStatus) {
                        ForEach(ThesisStatus.allCases, id: \.self) { status in
                            Text(status.rawValue).tag(status)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 400)
                    Spacer()
                }
                
                GroupBox(label: Label("1. Business Anatomy", systemImage: "building.2.fill").font(.title2)) {
                    VStack(alignment: .leading, spacing: 16) {
                        anatomyField(title: "What does the company do?", text: $thesis.valueProposition)
                        anatomyField(title: "What does it sell?", text: $thesis.revenueSegmentation)
                        anatomyField(title: "Who are its customers?", text: $thesis.customers)
                        anatomyField(title: "Customer Concentration (Diversified/Concentrated?)", text: $thesis.customerConcentration)
                        anatomyField(title: "What is its market? Is it growing?", text: $thesis.targetMarket)
                        anatomyField(title: "Who is the Management? Are they competent?", text: $thesis.leadership)
                        anatomyField(title: "Who owns the capital?", text: $thesis.ownership)
                        anatomyField(title: "Who are its competitors?", text: $thesis.competitors)
                        anatomyField(title: "Positioning vs. Competitors", text: $thesis.competitivePosition)
                        anatomyField(title: "Is the sector dynamic and future-oriented?", text: $thesis.sectorDynamics)
                    }.padding(.vertical, 12)
                }
                
                GroupBox(label: Label("2. Competitive Advantage (The Moat)", systemImage: "shield.fill").font(.title2)) {
                    VStack(alignment: .leading, spacing: 16) {
                        moatSection(title: "Network Effect", isToggled: $thesis.hasNetworkEffect, notes: $thesis.networkEffectNotes, description: "Increased value with more users (e.g., Meta, Visa).")
                        moatSection(title: "Switching Costs", isToggled: $thesis.hasSwitchingCosts, notes: $thesis.switchingCostsNotes, description: "High cost or effort to change providers (e.g., Apple, ASML).")
                        moatSection(title: "Intangibles", isToggled: $thesis.hasIntangibles, notes: $thesis.intangiblesNotes, description: "Brand, patents, licenses, proprietary data (e.g., LVMH, Disney).")
                        moatSection(title: "Cost Advantage", isToggled: $thesis.hasCostAdvantage, notes: $thesis.costAdvantageNotes, description: "Lower costs than competitors (e.g., Costco, Amazon).")
                        moatSection(title: "Efficient Scale", isToggled: $thesis.hasEfficientScale, notes: $thesis.efficientScaleNotes, description: "Market size limits viable competitors (e.g., Union Pacific).")
                    }.padding(.vertical, 12)
                }
                
                GroupBox(label: Label("3. Bear Case Threats", systemImage: "exclamationmark.triangle.fill").font(.title2).foregroundColor(.orange)) {
                    DynamicListSection(items: $thesis.bearCaseThreats, notesDict: $thesis.bearCaseNotes, placeholder: "Add a threat...")
                }
                
                GroupBox(label: Label("4. Exit Strategy", systemImage: "door.right.hand.open").font(.title2).foregroundColor(.red)) {
                    DynamicListSection(items: $thesis.exitStrategyRules, notesDict: $thesis.exitStrategyNotes, placeholder: "I will sell if...")
                }
                
                // POST-MORTEM
                if thesis.logEntries.contains(where: { $0.tag == "Sell" }) {
                    GroupBox(label: Label("Post-Mortem (Lessons Learned)", systemImage: "brain.head.profile").font(.title2).foregroundColor(.purple)) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("You logged a 'Sell' event. What did you learn from this investment?").font(.subheadline).foregroundColor(.secondary)
                            TextEditor(text: $thesis.postMortem)
                                .frame(height: 100)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
                        }.padding(.vertical, 12)
                    }
                }
                
                GroupBox(label: Label("Thesis History Logs", systemImage: "list.bullet.rectangle.portrait").font(.title2)) {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(thesis.logEntries.sorted(by: { $0.date > $1.date }), id: \.id) { entry in
                            LogEntryRow(entry: entry, thesis: thesis)
                        }
                    }.padding(.vertical, 12)
                }
            }
        }
    }
    
    @ViewBuilder
    private func anatomyField(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline).bold()
            TextField("Enter details...", text: text, axis: .vertical)
                .textFieldStyle(.roundedBorder).lineLimit(2...5).font(.body)
        }
    }
    
    @ViewBuilder
    private func moatSection(title: String, isToggled: Binding<Bool>, notes: Binding<String>, description: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: isToggled.animation()) {
                VStack(alignment: .leading) {
                    Text(title).font(.headline).bold()
                    Text(description).font(.subheadline).foregroundColor(.secondary)
                }
            }
            if isToggled.wrappedValue {
                TextField("Explain why \(title) applies...", text: notes, axis: .vertical)
                    .textFieldStyle(.roundedBorder).lineLimit(2...4).font(.body).padding(.leading, 30)
            }
        }
    }
}

// =========================================================================
// DynamicListSection & Log Creators
// =========================================================================

struct DynamicListSection: View {
    @Binding var items: [String]
    @Binding var notesDict: [String: String]
    let placeholder: String
    
    @State private var newItem: String = ""
    @State private var expandedItems: Set<String> = []
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(items, id: \.self) { item in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Button(action: {
                            if expandedItems.contains(item) { expandedItems.remove(item) } else { expandedItems.insert(item) }
                        }) {
                            Image(systemName: expandedItems.contains(item) ? "chevron.down" : "chevron.right")
                                .foregroundColor(.secondary)
                                .frame(width: 20)
                        }.buttonStyle(.plain)
                        
                        Text("• " + item).font(.body)
                        Spacer()
                        Button(action: { remove(item: item) }) {
                            Image(systemName: "trash").foregroundColor(.red.opacity(0.7))
                        }.buttonStyle(.plain)
                    }
                    if expandedItems.contains(item) {
                        TextField("Details...", text: Binding( get: { notesDict[item] ?? "" }, set: { notesDict[item] = $0 } ), axis: .vertical)
                        .textFieldStyle(.roundedBorder).padding(.leading, 30)
                    }
                }.padding(.vertical, 4)
            }
            
            HStack {
                TextField(placeholder, text: $newItem).textFieldStyle(.roundedBorder)
                Button("Add") { add() }
                .disabled(newItem.trimmingCharacters(in: .whitespaces).isEmpty)
                .buttonStyle(.bordered)
            }
        }
    }
    
    private func add() {
        let trimmed = newItem.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !items.contains(trimmed) else { return }
        items.append(trimmed)
        notesDict[trimmed] = ""
        expandedItems.insert(trimmed)
        newItem = ""
    }
    
    private func remove(item: String) {
        items.removeAll { $0 == item }
        notesDict.removeValue(forKey: item)
        expandedItems.remove(item)
    }
}

struct LogEntryRow: View {
    let entry: JournalEntry
    let thesis: InvestmentJournal
    @Environment(\.modelContext) private var modelContext
    let dateFormatter: DateFormatter = { let f = DateFormatter(); f.dateStyle = .medium; return f }()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(dateFormatter.string(from: entry.date)).font(.caption).foregroundColor(.secondary)
                
                Text(entry.tag)
                    .font(.caption).fontWeight(.bold)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Color.blue.opacity(0.1)).foregroundColor(.blue).cornerRadius(4)
                
                if entry.sentiment != .none {
                    Circle().fill(entry.sentiment.color).frame(width: 8, height: 8)
                }
                
                Spacer()
                
                Button(action: { delete() }) { Image(systemName: "trash").foregroundColor(.red.opacity(0.7)) }.buttonStyle(.plain)
            }
            Text(entry.content).font(.body)
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(10)
    }
    
    private func delete() {
        if let index = thesis.logEntries.firstIndex(where: { $0.id == entry.id }) {
            thesis.logEntries.remove(at: index)
            try? modelContext.save()
        }
    }
}
