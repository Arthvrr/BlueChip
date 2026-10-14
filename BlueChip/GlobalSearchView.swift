import SwiftUI

struct SearchResult: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let tab: AppTab
}

struct GlobalSearchView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: PortfolioViewModel
    @Binding var selectedTab: AppTab
    
    @State private var searchText = ""
    @FocusState private var isFocused: Bool
    
    var searchResults: [SearchResult] {
        guard !searchText.isEmpty else { return [] }
        let query = searchText.lowercased()
        var results: [SearchResult] = []
        let df = DateFormatter()
        df.dateStyle = .medium
        
        // 1. Pages de l'application
        for tab in AppTab.allCases {
            if tab.rawValue.lowercased().contains(query) {
                results.append(SearchResult(title: tab.rawValue, subtitle: "App Page", icon: "macwindow", color: .blue, tab: tab))
            }
        }
        
        // 2. Positions (Tickers & Noms d'entreprise)
        for pos in viewModel.positions {
            if pos.ticker.lowercased().contains(query) || pos.companyName.lowercased().contains(query) {
                results.append(SearchResult(title: pos.ticker, subtitle: "Position • \(pos.companyName)", icon: "briefcase.fill", color: .indigo, tab: .composition))
            }
        }
        
        // 3. Transactions (Ticker, Note, Type, Date)
        for tx in viewModel.transactions {
            let dateStr = df.string(from: tx.date).lowercased()
            if tx.ticker.lowercased().contains(query) || tx.note.lowercased().contains(query) || tx.type.rawValue.lowercased().contains(query) || dateStr.contains(query) {
                results.append(SearchResult(title: "\(tx.type.rawValue) \(tx.ticker)", subtitle: "Transaction • \(df.string(from: tx.date))", icon: "arrow.left.arrow.right", color: .orange, tab: .transactions))
            }
        }
        
        // 4. Calendrier (Ticker, Note, Type, Date)
        for ev in viewModel.calendarEvents {
            let dateStr = df.string(from: ev.date).lowercased()
            if ev.ticker.lowercased().contains(query) || ev.note.lowercased().contains(query) || ev.type.rawValue.lowercased().contains(query) || dateStr.contains(query) {
                results.append(SearchResult(title: "\(ev.type.rawValue) \(ev.ticker)", subtitle: "Event • \(df.string(from: ev.date))", icon: "calendar", color: .red, tab: .calendar))
            }
        }
        
        // 5. Critères Fondamentaux
        for crit in viewModel.fundamentalCriteria {
            if crit.name.lowercased().contains(query) || crit.section.lowercased().contains(query) {
                results.append(SearchResult(title: crit.name, subtitle: "Screener Criterion • \(crit.section)", icon: "building.2.fill", color: .teal, tab: .fundamentals))
            }
        }
        
        // 6. Indices Benchmark
        for idx in viewModel.benchmarkIndices {
            if idx.name.lowercased().contains(query) {
                results.append(SearchResult(title: idx.name, subtitle: "Benchmark Index", icon: "chart.bar.xaxis", color: .purple, tab: .benchmark))
            }
        }
        
        return results
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Barre de recherche Spotlight
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.title)
                    .foregroundColor(.blue)
                
                TextField("Search tickers, transactions, events, pages...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.title2)
                    .focused($isFocused) // Permet de taper directement sans devoir cliquer
                
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(20)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            if searchText.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "text.magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("Type anything to search across your entire portfolio.")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if searchResults.isEmpty {
                Text("No results found for \"\(searchText)\".")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(searchResults) { result in
                    Button(action: {
                        selectedTab = result.tab // Change l'onglet en arrière-plan
                        dismiss() // Ferme la recherche
                    }) {
                        HStack(spacing: 16) {
                            Circle()
                                .fill(result.color.opacity(0.2))
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Image(systemName: result.icon)
                                        .foregroundColor(result.color)
                                )
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.title)
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Text(result.subtitle)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.right")
                                .foregroundColor(.secondary.opacity(0.5))
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(width: 600, height: 450)
        .onAppear {
            isFocused = true // Force le curseur dans la barre de recherche à l'ouverture
        }
    }
}

