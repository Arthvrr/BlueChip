import SwiftUI

struct MenuBarDashboardView: View {
    @ObservedObject var viewModel: PortfolioViewModel
    
    // Variables calculées pour le mois en cours
    let currentMonthName: String = {
        let f = DateFormatter()
        f.dateFormat = "MMMM"
        return f.string(from: Date()).capitalized
    }()
    
    var thisMonthEvents: [CalendarEvent] {
        viewModel.calendarEvents.filter {
            Calendar.current.isDate($0.date, equalTo: Date(), toGranularity: .month)
        }.sorted { $0.date < $1.date }
    }
    
    // Logique simplifiée pour estimer les dividendes du mois en cours
    var thisMonthDividends: [(ticker: String, amountEUR: Double)] {
        let currentMonthIndex = Calendar.current.component(.month, from: Date())
        
        // CORRECTION : On ajoute explicitement les étiquettes (ticker et amountEUR) au tableau
        var payouts: [(ticker: String, amountEUR: Double)] = []
        
        for pos in viewModel.positions {
            if pos.dividendMonths.contains(currentMonthIndex) {
                let paymentsPerYear = max(1.0, Double(pos.dividendMonths.count))
                let singlePaymentUSD = (pos.annualDividendNet / paymentsPerYear) * pos.quantity
                let singlePaymentEUR = singlePaymentUSD * pos.usdToEurRate
                let netEUR = singlePaymentEUR * (1.0 - (viewModel.dividendTaxRate / 100.0))
                
                // Swift reconnaîtra automatiquement que la String est le ticker et le Double est amountEUR
                payouts.append((pos.ticker, netEUR))
            }
        }
        
        // Le tri fonctionnera maintenant parfaitement
        return payouts.sorted { $0.amountEUR > $1.amountEUR }
    }
    
    var totalDividendsThisMonth: Double {
        thisMonthDividends.reduce(0) { $0 + $1.amountEUR }
    }

    var body: some View {
        VStack(spacing: 0) {
            // --- HEADER : VALEUR & REFRESH ---
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Total Portfolio").font(.caption).foregroundColor(.secondary)
                    // TODO: Remplacer par la vraie variable de valeur totale de ton viewModel
                    Text("€ 45,230.00").font(.headline).fontWeight(.bold)
                }
                
                Spacer()
                
                // Idée d'ajout : Indicateur de marché
                HStack(spacing: 4) {
                    Circle().fill(Color.green).frame(width: 6, height: 6)
                    Text("Market Open").font(.caption2).foregroundColor(.secondary)
                }.padding(.trailing, 8)
                
                Button(action: {
                    // TODO: Lancer la fonction de rafraîchissement de Yahoo Finance
                    print("Refreshing Yahoo Finance API...")
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Refresh Market Data")
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // --- CONTENU SCROLLABLE ---
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    
                    // SECTION 1 : POSITIONS & TARGETS
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Holdings & Targets").font(.subheadline).fontWeight(.bold).foregroundColor(.secondary)
                        
                        VStack(spacing: 6) {
                            ForEach(viewModel.positions) { pos in
                                HStack {
                                    Text(pos.ticker).font(.system(.body, design: .monospaced)).fontWeight(.bold)
                                    Spacer()
                                    VStack(alignment: .trailing) {
                                        Text(pos.currentPrice.formatted(.currency(code: pos.currency.isEmpty ? "USD" : pos.currency)))
                                            .font(.subheadline)
                                        // TODO: Assure-toi d'avoir une propriété `targetPrice` dans ton modèle Position
                                        Text("Target: \(pos.targetPrice?.formatted() ?? "-")")
                                            .font(.caption2).foregroundColor(.secondary)
                                    }
                                }
                                Divider().opacity(0.5)
                            }
                        }
                    }
                    
                    // SECTION 2 : DIVIDENDES DU MOIS
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Dividends (\(currentMonthName))").font(.subheadline).fontWeight(.bold).foregroundColor(.secondary)
                            Spacer()
                            Text(totalDividendsThisMonth.formatted(.currency(code: "EUR"))).font(.caption).fontWeight(.bold).foregroundColor(.green)
                        }
                        
                        if thisMonthDividends.isEmpty {
                            Text("No dividends expected this month.").font(.caption).foregroundColor(.secondary).italic()
                        } else {
                            VStack(spacing: 6) {
                                ForEach(thisMonthDividends, id: \.ticker) { div in
                                    HStack {
                                        Text(div.ticker).font(.caption).fontWeight(.semibold)
                                        Spacer()
                                        Text(div.amountEUR.formatted(.currency(code: "EUR"))).font(.caption).foregroundColor(.green)
                                    }
                                }
                            }
                        }
                    }
                    
                    // SECTION 3 : ÉVÉNEMENTS DU MOIS
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Events (\(currentMonthName))").font(.subheadline).fontWeight(.bold).foregroundColor(.secondary)
                        
                        if thisMonthEvents.isEmpty {
                            Text("No upcoming events.").font(.caption).foregroundColor(.secondary).italic()
                        } else {
                            VStack(spacing: 6) {
                                ForEach(thisMonthEvents) { event in
                                    HStack {
                                        Circle().fill(event.type.color).frame(width: 6, height: 6)
                                        Text(event.ticker).font(.caption).fontWeight(.bold)
                                        Text(event.type.rawValue).font(.caption2).foregroundColor(.secondary).lineLimit(1)
                                        Spacer()
                                        Text(event.date, format: .dateTime.day().month()).font(.caption2).foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    
                }
                .padding(12)
            }
            
            Divider()
            
            // --- FOOTER : OUVRIR L'APP ---
            Button(action: {
                NSApp.activate(ignoringOtherApps: true)
                if NSApp.windows.isEmpty {
                    NSApp.sendAction(Selector(("showWindow:")), to: nil, from: nil)
                }
            }) {
                HStack {
                    Spacer()
                    Text("Open BlueChip Full App")
                        .font(.caption)
                        .fontWeight(.semibold)
                    Spacer()
                }
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            .onHover { hovering in
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
        }
        .frame(width: 300, height: 450) // Fixe la taille du popover
    }
}
