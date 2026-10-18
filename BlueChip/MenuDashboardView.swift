import SwiftUI

struct MenuBarDashboardView: View {
    @ObservedObject var viewModel: PortfolioViewModel
    @Environment(\.dismiss) var dismiss
    
    // Mode Confidentialité global
    @AppStorage("privacyMode") private var privacyMode: Bool = false
    
    // --- VARIABLES CALCULÉES ---
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
    
    var thisMonthDividends: [(ticker: String, amountEUR: Double)] {
        let currentMonthIndex = Calendar.current.component(.month, from: Date())
        var payouts: [(ticker: String, amountEUR: Double)] = []
        for pos in viewModel.positions {
            if pos.dividendMonths.contains(currentMonthIndex) {
                let paymentsPerYear = max(1.0, Double(pos.dividendMonths.count))
                let singlePaymentEUR = pos.totalDividendEUR / paymentsPerYear
                payouts.append((pos.ticker, singlePaymentEUR))
            }
        }
        return payouts.sorted { $0.amountEUR > $1.amountEUR }
    }
    
    var totalDividendsThisMonth: Double {
        thisMonthDividends.reduce(0) { $0 + $1.amountEUR }
    }
    
    var sortedPositions: [Position] {
        viewModel.positions.sorted { $0.ticker < $1.ticker }
    }
    
    var sortedWatchlist: [WatchlistItem] {
        viewModel.watchlistItems.sorted { $0.ticker < $1.ticker }
    }
    
    // --- FORMATEUR HEURE LOCALE ---
    var localTimeFormatter: DateFormatter {
        let f = DateFormatter()
        if let offset = Int(viewModel.userTimeZoneIdentifier) {
            f.timeZone = TimeZone(secondsFromGMT: offset * 3600) ?? TimeZone.current
        } else {
            f.timeZone = TimeZone(identifier: viewModel.userTimeZoneIdentifier) ?? TimeZone.current
        }
        f.dateFormat = "HH:mm"
        return f
    }
    
    // --- CALCULATEUR VÉRIDIQUE MARCHÉ US ---
    var isMarketOpen: Bool {
        guard let nyTimeZone = TimeZone(identifier: "America/New_York") else { return false }
        var cal = Calendar.current
        cal.timeZone = nyTimeZone
        let now = Date()
        
        if cal.isDateInWeekend(now) { return false }
        
        let currentYear = cal.component(.year, from: now)
        let holidays = USMarketHolidayHelper.getHolidays(forYear: currentYear)
        if holidays.contains(where: { cal.isDate($0.date, inSameDayAs: now) }) {
            return false
        }
        
        let hour = cal.component(.hour, from: now)
        let minute = cal.component(.minute, from: now)
        let totalMinutes = hour * 60 + minute
        
        let openMinutes = 9 * 60 + 30
        let closeMinutes = 16 * 60
        
        return totalMinutes >= openMinutes && totalMinutes < closeMinutes
    }

    var body: some View {
        VStack(spacing: 0) {
            
            // =====================================================================
            // MARK: - HEADER
            // =====================================================================
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Total Portfolio").font(.caption).foregroundColor(.secondary)
                    Text(privacyMode ? "€ ****" : viewModel.currentTotalCapital.formatted(.currency(code: "EUR")))
                        .font(.headline)
                        .fontWeight(.bold)
                    
                    // --- ROI GLOBAL (Corrigé pour correspondre au dashboard Composition) ---
                    let roiValue = viewModel.currentTotalCapital - viewModel.manuallyInvested
                    let roiPercent = viewModel.manuallyInvested > 0 ? (roiValue / viewModel.manuallyInvested) : 0
                    let isPositive = roiValue >= 0
                    let sign = isPositive ? "+" : ""
                    let color = isPositive ? Color.green : Color.red
                    
                    // On ne retire plus le HStack en mode privé, on remplace juste le texte pour garder la hauteur
                    HStack(spacing: 4) {
                        Text(privacyMode ? "****" : "\(sign)\(roiValue.formatted(.currency(code: "EUR")))")
                        Text(privacyMode ? "(***%)" : "(\(sign)\(roiPercent.formatted(.percent.precision(.fractionLength(1)))))")
                    }
                    .font(.caption2)
                    .foregroundColor(privacyMode ? .secondary : color)
                    .fontWeight(.semibold)
                }
                
                Spacer()
                
                HStack(spacing: 4) {
                    Circle()
                        .fill(viewModel.isLoading ? Color.orange : (isMarketOpen ? Color.green : Color.red))
                        .frame(width: 6, height: 6)
                        .opacity(viewModel.isLoading ? 0.5 : 1.0)
                    
                    Text(viewModel.isLoading ? "Refreshing..." : (isMarketOpen ? "Market Open" : "Market Closed"))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }.padding(.trailing, 8)
                
                Button(action: {
                    // Pas besoin d'animation ici pour éviter un effet de saut étrange du texte masqué
                    privacyMode.toggle()
                }) {
                    Image(systemName: privacyMode ? "eye.slash" : "eye")
                }
                .buttonStyle(.plain)
                .help(privacyMode ? "Show Values" : "Hide Values")
                .padding(.trailing, 4)
                
                Button(action: {
                    Task { await viewModel.refreshPrices() }
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
            
            // =====================================================================
            // MARK: - CONTENU SCROLLABLE
            // =====================================================================
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    
                    // --- ALERTE ÉVÉNEMENT DU JOUR ---
                    let todayEvents = thisMonthEvents.filter { Calendar.current.isDateInToday($0.date) }
                    if !todayEvents.isEmpty {
                        VStack(spacing: 6) {
                            ForEach(todayEvents) { event in
                                HStack {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.red)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("TODAY: \(event.ticker)").font(.caption).fontWeight(.bold)
                                        HStack(spacing: 4) {
                                            Text(event.type.rawValue)
                                            if event.hasTime {
                                                Text("at \(localTimeFormatter.string(from: event.date))")
                                                    .fontWeight(.bold)
                                            }
                                        }
                                        .font(.caption2).opacity(0.8)
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
                    
                    // --- SECTION 1 : POSITIONS & TARGETS ---
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Holdings & Targets").font(.subheadline).fontWeight(.bold).foregroundColor(.secondary)
                        
                        VStack(spacing: 6) {
                            ForEach(sortedPositions) { pos in
                                HStack {
                                    Text(pos.ticker).font(.system(.body, design: .monospaced)).fontWeight(.bold)
                                    Spacer()
                                    VStack(alignment: .trailing) {
                                        Text(privacyMode ? "****" : pos.currentPrice.formatted(.currency(code: pos.currency.isEmpty ? "USD" : pos.currency)))
                                            .font(.subheadline)
                                        
                                        HStack(spacing: 4) {
                                            Text("Target: \(privacyMode ? "****" : (pos.targetPrice?.formatted() ?? "-"))")
                                            
                                            if let target = pos.targetPrice, target > 0 {
                                                let gap = ((pos.currentPrice - target) / target) * 100
                                                let gapColor = gap <= 0 ? Color.green : Color.red
                                                let sign = gap > 0 ? "+" : ""
                                                // Remplacement fixe pour éviter le saut
                                                Text(privacyMode ? "(***%)" : "(\(sign)\(gap.formatted(.number.precision(.fractionLength(1))))%)")
                                                    .foregroundColor(privacyMode ? .secondary : gapColor)
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
                    
                    // --- SECTION 1.5 : WATCHLIST ---
                    if !sortedWatchlist.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Watchlist").font(.subheadline).fontWeight(.bold).foregroundColor(.secondary)
                            
                            VStack(spacing: 6) {
                                ForEach(sortedWatchlist) { item in
                                    HStack {
                                        Text(item.ticker).font(.system(.body, design: .monospaced)).fontWeight(.bold)
                                        Spacer()
                                        VStack(alignment: .trailing) {
                                            Text(privacyMode ? "****" : item.currentPrice.formatted(.currency(code: item.currency.isEmpty ? "USD" : item.currency)))
                                                .font(.subheadline)
                                            
                                            HStack(spacing: 4) {
                                                let targetText = item.targetPrice > 0 ? item.targetPrice.formatted() : "-"
                                                Text("Target: \(privacyMode ? "****" : targetText)")
                                                
                                                if item.targetPrice > 0 {
                                                    let target = item.targetPrice
                                                    let gap = ((item.currentPrice - target) / target) * 100
                                                    let gapColor = gap <= 0 ? Color.green : Color.red
                                                    let sign = gap > 0 ? "+" : ""
                                                    Text(privacyMode ? "(***%)" : "(\(sign)\(gap.formatted(.number.precision(.fractionLength(1))))%)")
                                                        .foregroundColor(privacyMode ? .secondary : gapColor)
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
                    }
                    
                    // --- SECTION 2 : DIVIDENDES ---
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Dividends (\(currentMonthName))").font(.subheadline).fontWeight(.bold).foregroundColor(.secondary)
                            Spacer()
                            Text(privacyMode ? "€ ****" : totalDividendsThisMonth.formatted(.currency(code: "EUR"))).font(.caption).fontWeight(.bold).foregroundColor(privacyMode ? .secondary : .green)
                        }
                        
                        if thisMonthDividends.isEmpty {
                            Text("No dividends expected this month.").font(.caption).foregroundColor(.secondary).italic()
                        } else {
                            VStack(spacing: 6) {
                                ForEach(thisMonthDividends, id: \.ticker) { div in
                                    HStack {
                                        Text(div.ticker).font(.caption).fontWeight(.semibold)
                                        Spacer()
                                        Text(privacyMode ? "€ ****" : div.amountEUR.formatted(.currency(code: "EUR"))).font(.caption).foregroundColor(privacyMode ? .secondary : .green)
                                    }
                                }
                            }
                        }
                    }
                    
                    // --- SECTION 3 : ÉVÉNEMENTS ---
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Events (\(currentMonthName))").font(.subheadline).fontWeight(.bold).foregroundColor(.secondary)
                        
                        if thisMonthEvents.isEmpty {
                            Text("No upcoming events.").font(.caption).foregroundColor(.secondary).italic()
                        } else {
                            VStack(spacing: 6) {
                                ForEach(thisMonthEvents) { event in
                                    let isPast = event.date < Calendar.current.startOfDay(for: Date())
                                    HStack {
                                        Circle()
                                            .fill(isPast ? Color.gray : event.type.color)
                                            .frame(width: 6, height: 6)
                                        
                                        if isPast {
                                            Text(event.ticker).font(.caption).fontWeight(.bold).strikethrough().foregroundColor(.secondary)
                                        } else {
                                            Text(event.ticker).font(.caption).fontWeight(.bold)
                                        }
                                        
                                        Text(event.type.rawValue).font(.caption2).foregroundColor(isPast ? .secondary.opacity(0.5) : .secondary).lineLimit(1)
                                        Spacer()
                                        Text(event.date, format: .dateTime.day().month()).font(.caption2).foregroundColor(isPast ? .secondary.opacity(0.5) : .secondary)
                                    }
                                }
                            }
                        }
                    }
                    
                }
                .padding(12)
            }
            
            Divider()
            
            // =====================================================================
            // MARK: - FOOTER PROPRE & CENTRÉ
            // =====================================================================
            Button(action: {
                dismiss()
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
        .frame(width: 320, height: 480)
    }
}
