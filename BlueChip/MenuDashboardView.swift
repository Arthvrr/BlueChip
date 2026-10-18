import SwiftUI

struct MenuBarDashboardView: View {
    @ObservedObject var viewModel: PortfolioViewModel
    
    // Pour fermer le Popover si besoin (bien que ce soit géré par le système en général)
    @Environment(\.dismiss) var dismiss
    
    // Variables calculées pour le mois en cours
    let currentMonthName: String = {
        let f = DateFormatter()
        f.dateFormat = "MMMM"
        return f.string(from: Date()).capitalized
    }()
    
    // 5) Triage et identification des événements (dont ceux d'aujourd'hui)
    var thisMonthEvents: [CalendarEvent] {
        viewModel.calendarEvents.filter {
            Calendar.current.isDate($0.date, equalTo: Date(), toGranularity: .month)
        }.sorted { $0.date < $1.date }
    }
    
    // 1) Calcul des dividendes corrigé
    var thisMonthDividends: [(ticker: String, amountEUR: Double)] {
        let currentMonthIndex = Calendar.current.component(.month, from: Date())
        var payouts: [(ticker: String, amountEUR: Double)] = []
        
        for pos in viewModel.positions {
            if pos.dividendMonths.contains(currentMonthIndex) {
                // Utilisation du dividende total annuel (déjà multiplié par la quantité en USD converti en EUR)
                let netTotalEUR = pos.totalDividendEUR
                
                // On divise par le nombre de mois où il y a un versement pour obtenir la valeur de ce versement
                let paymentsPerYear = max(1.0, Double(pos.dividendMonths.count))
                let singlePaymentEUR = netTotalEUR / paymentsPerYear
                
                payouts.append((pos.ticker, singlePaymentEUR))
            }
        }
        
        return payouts.sorted { $0.amountEUR > $1.amountEUR }
    }
    
    var totalDividendsThisMonth: Double {
        thisMonthDividends.reduce(0) { $0 + $1.amountEUR }
    }
    
    // 4) Positions triées par Ticker (Ordre alphabétique)
    var sortedPositions: [Position] {
        viewModel.positions.sorted { $0.ticker < $1.ticker }
    }

    var body: some View {
        VStack(spacing: 0) {
            // --- HEADER : VALEUR & REFRESH ---
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Total Portfolio").font(.caption).foregroundColor(.secondary)
                    Text(viewModel.currentTotalCapital.formatted(.currency(code: "EUR")))
                        .font(.headline)
                        .fontWeight(.bold)
                }
                
                Spacer()
                
                HStack(spacing: 4) {
                    Circle()
                        .fill(viewModel.isLoading ? Color.orange : Color.green)
                        .frame(width: 6, height: 6)
                    Text(viewModel.isLoading ? "Refreshing..." : "Market Open").font(.caption2).foregroundColor(.secondary)
                }.padding(.trailing, 8)
                
                // 6) Bouton Refresh Actif
                Button(action: {
                    Task {
                        await viewModel.refreshPrices()
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(Angle(degrees: viewModel.isLoading ? 360 : 0))
                        .animation(viewModel.isLoading ? Animation.linear(duration: 1).repeatForever(autoreverses: false) : .default, value: viewModel.isLoading)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isLoading)
                .help("Refresh Market Data")
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // --- CONTENU SCROLLABLE ---
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    
                    // --- 2) ALERTE ÉVÉNEMENT DU JOUR ---
                    let todayEvents = thisMonthEvents.filter { Calendar.current.isDateInToday($0.date) }
                    if !todayEvents.isEmpty {
                        VStack(spacing: 6) {
                            ForEach(todayEvents) { event in
                                HStack {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.red)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("TODAY: \(event.ticker)").font(.caption).fontWeight(.bold)
                                        Text(event.type.rawValue).font(.caption2).opacity(0.8)
                                    }
                                    Spacer()
                                }
                                .padding(8)
                                .background(Color.red.opacity(0.15))
                                .cornerRadius(6)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.red.opacity(0.4), lineWidth: 1))
                            }
                        }
                    }
                    
                    // SECTION 1 : POSITIONS & TARGETS
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Holdings & Targets").font(.subheadline).fontWeight(.bold).foregroundColor(.secondary)
                        
                        VStack(spacing: 6) {
                            ForEach(sortedPositions) { pos in
                                HStack {
                                    Text(pos.ticker).font(.system(.body, design: .monospaced)).fontWeight(.bold)
                                    Spacer()
                                    VStack(alignment: .trailing) {
                                        Text(pos.currentPrice.formatted(.currency(code: pos.currency.isEmpty ? "USD" : pos.currency)))
                                            .font(.subheadline)
                                        
                                        // 3) Ajout du % Gap à côté du Target
                                        HStack(spacing: 4) {
                                            Text("Target: \(pos.targetPrice?.formatted() ?? "-")")
                                            
                                            if let target = pos.targetPrice, target > 0 {
                                                let gap = ((pos.currentPrice - target) / target) * 100
                                                // Si le prix est < target (donc négatif), on est en dessous (vert/bien si on veut acheter), sinon rouge
                                                let gapColor = gap <= 0 ? Color.green : Color.red
                                                let sign = gap > 0 ? "+" : ""
                                                Text("(\(sign)\(gap.formatted(.number.precision(.fractionLength(1))))%)")
                                                    .foregroundColor(gapColor)
                                            }
                                        }
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
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
                                    // Vérifier si la date est passée
                                    let isPast = event.date < Calendar.current.startOfDay(for: Date())
                                    
                                    HStack {
                                        Circle()
                                            .fill(isPast ? Color.gray : event.type.color)
                                            .frame(width: 6, height: 6)
                                        
                                        // 5) Biffer les événements passés
                                        if isPast {
                                            Text(event.ticker).font(.caption).fontWeight(.bold)
                                                .strikethrough()
                                                .foregroundColor(.secondary)
                                        } else {
                                            Text(event.ticker).font(.caption).fontWeight(.bold)
                                        }
                                        
                                        Text(event.type.rawValue).font(.caption2).foregroundColor(isPast ? .secondary.opacity(0.5) : .secondary).lineLimit(1)
                                        
                                        Spacer()
                                        
                                        Text(event.date, format: .dateTime.day().month())
                                            .font(.caption2)
                                            .foregroundColor(isPast ? .secondary.opacity(0.5) : .secondary)
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
            // 6) Bouton d'ouverture actif
            Button(action: {
                // Ferme le popover de la barre de menu
                dismiss()
                
                // Amène l'application (le Dock) au premier plan
                NSApp.activate(ignoringOtherApps: true)
                
                // Si la fenêtre a été fermée (Croix rouge), la relance
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
        .frame(width: 320, height: 480) // Fixe la taille du popover
    }
}
