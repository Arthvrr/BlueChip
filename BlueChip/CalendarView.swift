import SwiftUI

// =========================================================================
// MARK: - US MARKET HOLIDAY CALCULATOR
// =========================================================================

struct MarketHoliday: Identifiable {
    let id = UUID()
    let name: String
    let date: Date
}

struct USMarketHolidayHelper {
    
    // Ajustement WE : Samedi -> Vendredi précédent, Dimanche -> Lundi suivant
    static func adjustForWeekend(_ date: Date) -> Date {
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: date)
        if weekday == 7 { // Samedi
            return cal.date(byAdding: .day, value: -1, to: date) ?? date
        } else if weekday == 1 { // Dimanche
            return cal.date(byAdding: .day, value: 1, to: date) ?? date
        }
        return date
    }
    
    // Algorithme de calcul de la date de Pâques
    static func calculateEaster(year: Int) -> Date? {
        let a = year % 19
        let b = year / 100
        let c = year % 100
        let d = b / 4
        let e = b % 4
        let f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4
        let k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = ((h + l - 7 * m + 114) % 31) + 1
        
        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = day
        return Calendar.current.date(from: comps)
    }
    
    static func nthWeekday(nth: Int, weekday: Int, month: Int, year: Int) -> Date? {
        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.weekday = weekday; comps.weekdayOrdinal = nth
        return Calendar.current.date(from: comps)
    }
    
    static func lastWeekday(weekday: Int, month: Int, year: Int) -> Date? {
        let cal = Calendar.current
        var comps = DateComponents()
        comps.year = year; comps.month = month + 1; comps.day = 0
        guard let lastDay = cal.date(from: comps) else { return nil }
        var current = lastDay
        while cal.component(.weekday, from: current) != weekday {
            current = cal.date(byAdding: .day, value: -1, to: current)!
        }
        return current
    }
    
    // Récupération des 10 jours fériés boursiers pour une année donnée
    static func getHolidays(forYear year: Int) -> [MarketHoliday] {
        var holidays: [MarketHoliday] = []
        let cal = Calendar.current
        
        func addFixed(_ name: String, month: Int, day: Int) {
            var comps = DateComponents(year: year, month: month, day: day)
            if let rawDate = cal.date(from: comps) {
                let adjDate = adjustForWeekend(rawDate)
                holidays.append(MarketHoliday(name: name, date: adjDate))
            }
        }
        
        // 1. New Year's Day (1er janvier)
        addFixed("New Year's Day", month: 1, day: 1)
        
        // 2. MLK Day (3e lundi de janvier)
        if let mlk = nthWeekday(nth: 3, weekday: 2, month: 1, year: year) {
            holidays.append(MarketHoliday(name: "Martin Luther King Jr. Day", date: mlk))
        }
        
        // 3. Presidents' Day (3e lundi de février)
        if let pres = nthWeekday(nth: 3, weekday: 2, month: 2, year: year) {
            holidays.append(MarketHoliday(name: "Presidents' Day", date: pres))
        }
        
        // 4. Good Friday (Vendredi saint - 2 jours avant Pâques)
        if let easter = calculateEaster(year: year), let gf = cal.date(byAdding: .day, value: -2, to: easter) {
            holidays.append(MarketHoliday(name: "Good Friday", date: gf))
        }
        
        // 5. Memorial Day (Dernier lundi de mai)
        if let mem = lastWeekday(weekday: 2, month: 5, year: year) {
            holidays.append(MarketHoliday(name: "Memorial Day", date: mem))
        }
        
        // 6. Juneteenth (19 juin)
        addFixed("Juneteenth National Independence Day", month: 6, day: 19)
        
        // 7. Independence Day (4 juillet)
        addFixed("Independence Day", month: 7, day: 4)
        
        // 8. Labor Day (1er lundi de septembre)
        if let labor = nthWeekday(nth: 1, weekday: 2, month: 9, year: year) {
            holidays.append(MarketHoliday(name: "Labor Day", date: labor))
        }
        
        // 9. Thanksgiving Day (4e jeudi de novembre)
        if let thanksgiving = nthWeekday(nth: 4, weekday: 5, month: 11, year: year) {
            holidays.append(MarketHoliday(name: "Thanksgiving Day", date: thanksgiving))
        }
        
        // 10. Christmas Day (25 décembre)
        addFixed("Christmas Day", month: 12, day: 25)
        
        return holidays
    }
}

// =========================================================================
// MARK: - MAIN CALENDAR VIEW
// =========================================================================

struct CalendarView: View {
    @ObservedObject var viewModel: PortfolioViewModel
    @Binding var privacyMode: Bool
    
    @State private var selectedDate: Date = Date()
    @State private var showAddEventSheet: Bool = false
    @State private var editingEvent: CalendarEvent? = nil
    @State private var detailEvent: CalendarEvent? = nil
    
    // Filtres
    @State private var searchText: String = ""
    @State private var selectedTypeFilter: CalendarEventType? = nil
    @State private var selectedTickerFilter: String = ""
    
    // 12 mois glissants
    var months: [Date] {
        let calendar = Calendar.current
        let today = Date()
        guard let currentMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: today)) else { return [] }
        return (0..<12).compactMap { calendar.date(byAdding: .month, value: $0, to: currentMonthStart) }
    }
    
    // Jours fériés pour les années couvertes par les 12 mois glissants
    var marketHolidays: [MarketHoliday] {
        let currentYear = Calendar.current.component(.year, from: Date())
        return USMarketHolidayHelper.getHolidays(forYear: currentYear) + USMarketHolidayHelper.getHolidays(forYear: currentYear + 1)
    }
    
    // Tickers disponibles (Portefeuille + Watchlist)
    var availableTickers: [String] {
        let pTickers = viewModel.positions.map { $0.ticker }
        let wTickers = viewModel.watchlistItems.map { $0.ticker }
        return Array(Set(pTickers + wTickers)).sorted()
    }
    
    // Événements filtrés par la barre de recherche & filtres rapides
    var filteredEvents: [CalendarEvent] {
        viewModel.calendarEvents.filter { event in
            let matchesSearch = searchText.isEmpty ||
                event.ticker.localizedCaseInsensitiveContains(searchText) ||
                event.note.localizedCaseInsensitiveContains(searchText) ||
                event.type.rawValue.localizedCaseInsensitiveContains(searchText)
            
            let matchesType = selectedTypeFilter == nil || event.type == selectedTypeFilter
            let matchesTicker = selectedTickerFilter.isEmpty || event.ticker == selectedTickerFilter
            
            return matchesSearch && matchesType && matchesTicker
        }
    }
    
    // 5 prochains événements à venir (parmi filtrés)
    var upcomingEvents: [CalendarEvent] {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        return filteredEvents
            .filter { $0.date >= startOfToday }
            .sorted { $0.date < $1.date }
            .prefix(5)
            .map { $0 }
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 24) {
                
                // HEADER : Titre + Bouton Ajouter
                HStack {
                    Text("Investor Calendar").font(.title).fontWeight(.bold)
                    Spacer()
                    Button(action: {
                        selectedDate = Date()
                        showAddEventSheet = true
                    }) {
                        Label("Add Event", systemImage: "calendar.badge.plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
                
                // 1. BARRE DE RECHERCHE & FILTRES RAPIDES
                CalendarFiltersSection(
                    searchText: $searchText,
                    selectedTypeFilter: $selectedTypeFilter,
                    selectedTickerFilter: $selectedTickerFilter,
                    availableTickers: availableTickers
                )
                
                // 2. RÉSUMÉ SOUS FORME DE TIRETS (5 PROCHAINS ÉVÉNEMENTS + BADGE TODAY)
                UpcomingEventsSummarySection(
                    events: upcomingEvents,
                    onDetail: { event in detailEvent = event },
                    onEdit: { event in editingEvent = event },
                    onDelete: { id in viewModel.calendarEvents.removeAll { $0.id == id } }
                )
                
                // 3. CALENDRIER SUR 12 MOIS GLISSANTS (PLEINE LARGEUR, SCROLL VERTICAL)
                VStack(spacing: 32) {
                    ForEach(months, id: \.self) { monthDate in
                        FullWidthMonthView(
                            month: monthDate,
                            events: filteredEvents,
                            marketHolidays: marketHolidays,
                            selectedDate: $selectedDate,
                            onAddEvent: { date in
                                selectedDate = date
                                showAddEventSheet = true
                            },
                            onDetailEvent: { event in
                                detailEvent = event
                            },
                            onEditEvent: { event in
                                editingEvent = event
                            }
                        )
                    }
                }
                
                BlueChipWatermark()
            }
            .padding()
        }
        .sheet(isPresented: $showAddEventSheet) {
            AddEditEventSheet(viewModel: viewModel, event: nil, initialDate: selectedDate)
        }
        .sheet(item: $editingEvent) { event in
            AddEditEventSheet(viewModel: viewModel, event: event, initialDate: event.date)
        }
        .sheet(item: $detailEvent) { event in
            EventDetailSheet(event: event, onEdit: {
                detailEvent = nil
                editingEvent = event
            })
        }
    }
}

// =========================================================================
// MARK: - SECTION BARRE DE RECHERCHE & FILTRES
// =========================================================================

struct CalendarFiltersSection: View {
    @Binding var searchText: String
    @Binding var selectedTypeFilter: CalendarEventType?
    @Binding var selectedTickerFilter: String
    let availableTickers: [String]
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                // Recherche textuelle
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                    TextField("Search ticker, note, event type…", text: $searchText)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                        }.buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(Color(NSColor.windowBackgroundColor))
                .cornerRadius(8)
                
                // Filtre Ticker / Action
                Picker("Stock:", selection: $selectedTickerFilter) {
                    Text("All Stocks").tag("")
                    ForEach(availableTickers, id: \.self) { t in
                        Text(t).tag(t)
                    }
                }
                .frame(width: 180)
            }
            
            // Filtres rapides par Type d'événement (Badges/Puces)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button(action: { selectedTypeFilter = nil }) {
                        Text("All Types")
                            .font(.caption)
                            .fontWeight(selectedTypeFilter == nil ? .bold : .medium)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(selectedTypeFilter == nil ? Color.blue : Color(NSColor.windowBackgroundColor))
                            .foregroundColor(selectedTypeFilter == nil ? .white : .primary)
                            .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                    
                    ForEach(CalendarEventType.allCases, id: \.self) { type in
                        let isSelected = selectedTypeFilter == type
                        Button(action: {
                            selectedTypeFilter = isSelected ? nil : type
                        }) {
                            HStack(spacing: 4) {
                                Circle().fill(type.color).frame(width: 6, height: 6)
                                Text(type.rawValue).font(.caption).fontWeight(isSelected ? .bold : .medium)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(isSelected ? type.color.opacity(0.25) : Color(NSColor.windowBackgroundColor))
                            .overlay(Capsule().stroke(isSelected ? type.color : Color.clear, lineWidth: 1))
                            .foregroundColor(isSelected ? type.color : .primary)
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// =========================================================================
// MARK: - RÉSUMÉ DES 5 PROCHAINS ÉVÉNEMENTS (AVEC BADGE TODAY)
// =========================================================================

struct UpcomingEventsSummarySection: View {
    let events: [CalendarEvent]
    let onDetail: (CalendarEvent) -> Void
    let onEdit: (CalendarEvent) -> Void
    let onDelete: (UUID) -> Void
    
    let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "bell.fill").foregroundColor(.blue)
                Text("Next Upcoming Events").font(.title2).fontWeight(.bold).foregroundColor(.secondary)
            }
            
            if events.isEmpty {
                HStack {
                    Text("- No upcoming events scheduled.").foregroundColor(.secondary).italic()
                    Spacer()
                }
                .padding(.vertical, 8)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(events) { event in
                        let isToday = Calendar.current.isDateInToday(event.date)
                        
                        HStack(spacing: 12) {
                            Text("•")
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(event.type.color)
                            
                            // BADGE "TODAY" ROUGE SI AUJOURD'HUI
                            if isToday {
                                Text("TODAY")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.red)
                                    .foregroundColor(.white)
                                    .cornerRadius(4)
                            }
                            
                            Text(dateFormatter.string(from: event.date))
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(isToday ? .red : .secondary)
                                .frame(width: 100, alignment: .leading)
                            
                            HStack(spacing: 6) {
                                Text(event.ticker)
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                
                                Text("—")
                                    .foregroundColor(.secondary)
                                
                                Text(event.type.rawValue)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(event.type.color)
                            }
                            
                            if !event.note.isEmpty {
                                Text("(\(event.note))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            
                            Spacer()
                            
                            Text("(Click 1x detail / 2x edit)").font(.caption2).foregroundColor(.secondary.opacity(0.6))
                            
                            HStack(spacing: 8) {
                                Button(action: { onDelete(event.id) }) {
                                    Image(systemName: "trash").font(.caption).foregroundColor(.red.opacity(0.7))
                                }.buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                        // GESTE : 1x Clic = Détails, 2x Clics = Modifier
                        .onTapGesture(count: 2) {
                            onEdit(event)
                        }
                        .onTapGesture(count: 1) {
                            onDetail(event)
                        }
                        
                        if event.id != events.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// =========================================================================
// MARK: - VUE D'UN MOIS PLEINE LARGEUR (AVEC JOURS FÉRIÉS BOURSIERS)
// =========================================================================

struct FullWidthMonthView: View {
    let month: Date
    let events: [CalendarEvent]
    let marketHolidays: [MarketHoliday]
    @Binding var selectedDate: Date
    let onAddEvent: (Date) -> Void
    let onDetailEvent: (CalendarEvent) -> Void
    let onEditEvent: (CalendarEvent) -> Void
    
    let daysOfWeek = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
    
    var monthYearTitle: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f.string(from: month).capitalized
    }
    
    var daysInMonth: [Date?] {
        let calendar = Calendar.current
        guard let monthInterval = calendar.range(of: .day, in: .month, for: month),
              let monthFirstWeek = calendar.dateInterval(of: .month, for: month) else { return [] }
        
        let firstDayOfMonth = monthFirstWeek.start
        var firstWeekday = calendar.component(.weekday, from: firstDayOfMonth) - 2
        if firstWeekday < 0 { firstWeekday += 7 }
        
        var days: [Date?] = Array(repeating: nil, count: firstWeekday)
        
        for dayOffset in 0..<monthInterval.count {
            if let date = calendar.date(byAdding: .day, value: dayOffset, to: firstDayOfMonth) {
                days.append(date)
            }
        }
        
        while days.count % 7 != 0 {
            days.append(nil)
        }
        
        return days
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Titre du mois
            HStack {
                Text(monthYearTitle)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
                Spacer()
            }
            .padding(.horizontal, 4)
            
            // En-tête des jours de la semaine
            HStack(spacing: 0) {
                ForEach(daysOfWeek, id: \.self) { day in
                    Text(day)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))
            .cornerRadius(8)
            
            // Grille du mois pleine largeur
            let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(0..<daysInMonth.count, id: \.self) { index in
                    if let date = daysInMonth[index] {
                        let dayEvents = events.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
                        let holiday = marketHolidays.first { Calendar.current.isDate($0.date, inSameDayAs: date) }
                        
                        FullWidthDayCellView(
                            date: date,
                            events: dayEvents,
                            holiday: holiday,
                            isSelected: Calendar.current.isDate(date, inSameDayAs: selectedDate),
                            onTapDay: {
                                selectedDate = date
                                onAddEvent(date)
                            },
                            onDetailEvent: onDetailEvent,
                            onEditEvent: onEditEvent
                        )
                    } else {
                        Color.clear
                            .frame(height: 90)
                    }
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// CELLULE D'UN JOUR PLEINE LARGEUR (AVEC JOUR FÉRIÉ BOURSIER)
struct FullWidthDayCellView: View {
    let date: Date
    let events: [CalendarEvent]
    let holiday: MarketHoliday?
    let isSelected: Bool
    let onTapDay: () -> Void
    let onDetailEvent: (CalendarEvent) -> Void
    let onEditEvent: (CalendarEvent) -> Void
    
    var isToday: Bool { Calendar.current.isDateInToday(date) }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(Calendar.current.component(.day, from: date))")
                    .font(.system(size: 13, weight: isToday || isSelected ? .bold : .semibold))
                    .foregroundColor(isToday ? .white : (isSelected ? .blue : .primary))
                    .frame(width: 22, height: 22)
                    .background(isToday ? Color.blue : (isSelected ? Color.blue.opacity(0.2) : Color.clear))
                    .clipShape(Circle())
                
                if isToday {
                    Text("TODAY")
                        .font(.system(size: 8, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(3)
                }
                
                Spacer()
                
                Button(action: onTapDay) {
                    Image(systemName: "plus")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .opacity(0.6)
            }
            .padding(.horizontal, 4)
            .padding(.top, 4)
            
            // INDICATEUR JOUR FÉRIÉ BOURSIER US
            if let hol = holiday {
                HStack(spacing: 2) {
                    Text("🔒 Market Closed")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.red)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.red.opacity(0.12))
                .cornerRadius(4)
                .help(hol.name) // Tooltip au survol
            }
            
            // Liste des événements dans la cellule
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 3) {
                    ForEach(events) { event in
                        HStack(spacing: 4) {
                            Circle().fill(event.type.color).frame(width: 5, height: 5)
                            Text(event.ticker)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.primary)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(event.type.color.opacity(0.18))
                        .cornerRadius(4)
                        .contentShape(Rectangle())
                        // GESTE : 1x Clic = Détails, 2x Clics = Modifier
                        .onTapGesture(count: 2) {
                            onEditEvent(event)
                        }
                        .onTapGesture(count: 1) {
                            onDetailEvent(event)
                        }
                    }
                }
            }
        }
        .frame(height: 90)
        .frame(maxWidth: .infinity)
        .background(holiday != nil ? Color.red.opacity(0.03) : Color(NSColor.windowBackgroundColor).opacity(isSelected ? 0.9 : 0.4))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(isToday ? Color.blue.opacity(0.6) : (isSelected ? Color.blue.opacity(0.3) : Color.gray.opacity(0.15)), lineWidth: 1))
    }
}

// =========================================================================
// MARK: - SHEET FICHE DÉTAILLÉE D'UN ÉVÉNEMENT (CLIC 1X)
// =========================================================================

struct EventDetailSheet: View {
    @Environment(\.dismiss) var dismiss
    let event: CalendarEvent
    let onEdit: () -> Void
    
    var dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .full
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Circle().fill(event.type.color).frame(width: 12, height: 12)
                Text(event.type.rawValue).font(.title2).fontWeight(.bold).foregroundColor(event.type.color)
                Spacer()
                Button(action: { dismiss() }) { Image(systemName: "xmark.circle.fill").font(.title2).foregroundColor(.secondary) }.buttonStyle(.plain)
            }
            Divider()
            
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Stock Ticker:").fontWeight(.semibold).foregroundColor(.secondary)
                    Spacer()
                    Text(event.ticker).font(.title3).fontWeight(.bold)
                }
                
                HStack {
                    Text("Scheduled Date:").fontWeight(.semibold).foregroundColor(.secondary)
                    Spacer()
                    Text(dateFormatter.string(from: event.date)).font(.subheadline)
                }
                
                if !event.note.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Notes / Details:").fontWeight(.semibold).foregroundColor(.secondary)
                        Text(event.note)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(NSColor.windowBackgroundColor))
                            .cornerRadius(8)
                    }
                }
            }
            
            Divider()
            
            HStack {
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(action: onEdit) {
                    Label("Edit Event", systemImage: "pencil")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 400)
    }
}

// =========================================================================
// MARK: - FORMULAIRE D'AJOUT / ÉDITION (CLIC 2X)
// =========================================================================

struct AddEditEventSheet: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: PortfolioViewModel
    let event: CalendarEvent?
    let initialDate: Date
    
    @State private var date: Date
    @State private var type: CalendarEventType = .earnings
    @State private var ticker: String = ""
    @State private var note: String = ""
    
    init(viewModel: PortfolioViewModel, event: CalendarEvent?, initialDate: Date) {
        self.viewModel = viewModel
        self.event = event
        self.initialDate = initialDate
        
        _date = State(initialValue: event?.date ?? initialDate)
        if let ev = event {
            _type = State(initialValue: ev.type)
            _ticker = State(initialValue: ev.ticker)
            _note = State(initialValue: ev.note)
        }
    }
    
    var isEditing: Bool { event != nil }
    
    var availableTickers: [String] {
        let pTickers = viewModel.positions.map { $0.ticker }
        let wTickers = viewModel.watchlistItems.map { $0.ticker }
        return Array(Set(pTickers + wTickers)).sorted()
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(isEditing ? "Edit Event" : "New Event").font(.title2).fontWeight(.bold)
                Spacer()
                Button(action: { dismiss() }) { Image(systemName: "xmark.circle.fill").font(.title2).foregroundColor(.secondary) }.buttonStyle(.plain)
            }.padding()
            Divider()
            
            Form {
                Section(header: Text("Event Details").font(.headline)) {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    
                    Picker("Event Type", selection: $type) {
                        ForEach(CalendarEventType.allCases, id: \.self) { t in
                            Text(t.rawValue).tag(t)
                        }
                    }
                }.padding(.bottom, 12)
                
                Section(header: Text("Related Stock").font(.headline)) {
                    HStack {
                        TextField("Ticker (e.g., AAPL)", text: $ticker)
                            .onChange(of: ticker) { ticker = ticker.uppercased() }
                        
                        Picker("", selection: $ticker) {
                            Text("Select saved...").tag("")
                            ForEach(availableTickers, id: \.self) { t in
                                Text(t).tag(t)
                            }
                        }
                        .frame(width: 150)
                    }
                }.padding(.bottom, 12)
                
                Section(header: Text("Additional Notes (Optional)").font(.headline)) {
                    TextField("E.g. Estimated $2.50 per share", text: $note)
                }
            }
            .padding()
            
            Divider()
            HStack {
                
                if isEditing {
                    Button(role: .destructive) {
                        delete()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(ticker.isEmpty)
            }.padding()
        }
        .frame(width: 450)
    }
    
    func save() {
        let newEvent = CalendarEvent(
            id: event?.id ?? UUID(),
            date: date,
            type: type,
            ticker: ticker.uppercased(),
            note: note
        )
        
        if isEditing, let idx = viewModel.calendarEvents.firstIndex(where: { $0.id == newEvent.id }) {
            viewModel.calendarEvents[idx] = newEvent
        } else {
            viewModel.calendarEvents.append(newEvent)
        }
        
        dismiss()
    }
    
    func delete() {
        if let eventId = event?.id {
            viewModel.calendarEvents.removeAll { $0.id == eventId }
        }
        dismiss()
    }
}
