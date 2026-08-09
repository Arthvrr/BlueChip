import SwiftUI

// =========================================================================
// MARK: - MAIN CALENDAR VIEW
// =========================================================================

struct CalendarView: View {
    @ObservedObject var viewModel: PortfolioViewModel
    @Binding var privacyMode: Bool
    
    @State private var selectedDate: Date = Date()
    @State private var showAddEventSheet: Bool = false
    @State private var editingEvent: CalendarEvent? = nil
    
    // Génère les 12 prochains mois glissants
    var months: [Date] {
        let calendar = Calendar.current
        let today = Date()
        guard let currentMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: today)) else { return [] }
        return (0..<12).compactMap { calendar.date(byAdding: .month, value: $0, to: currentMonthStart) }
    }
    
    // Les 5 prochains événements à venir (date >= début d'aujourd'hui)
    var upcomingEvents: [CalendarEvent] {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        return viewModel.calendarEvents
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
                
                // 1. RÉSUMÉ SOUS FORME DE TIRETS (5 PROCHAINS ÉVÉNEMENTS)
                UpcomingEventsSummarySection(
                    events: upcomingEvents,
                    onEdit: { event in editingEvent = event },
                    onDelete: { id in viewModel.calendarEvents.removeAll { $0.id == id } }
                )
                
                // 2. CALENDRIER SUR 12 MOIS GLISSANTS (PLEINE LARGEUR, SCROLL VERTICAL)
                VStack(spacing: 32) {
                    ForEach(months, id: \.self) { monthDate in
                        FullWidthMonthView(
                            month: monthDate,
                            events: viewModel.calendarEvents,
                            selectedDate: $selectedDate,
                            onAddEvent: { date in
                                selectedDate = date
                                showAddEventSheet = true
                            },
                            onEditEvent: { event in
                                editingEvent = event
                            },
                            onDeleteEvent: { id in
                                viewModel.calendarEvents.removeAll { $0.id == id }
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
    }
}

// =========================================================================
// MARK: - RÉSUMÉ DES 5 PROCHAINS ÉVÉNEMENTS
// =========================================================================

struct UpcomingEventsSummarySection: View {
    let events: [CalendarEvent]
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
                        HStack(spacing: 12) {
                            Text("•")
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(event.type.color)
                            
                            Text(dateFormatter.string(from: event.date))
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                                .frame(width: 110, alignment: .leading)
                            
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
                            
                            HStack(spacing: 8) {
                                Button(action: { onEdit(event) }) {
                                    Image(systemName: "pencil").font(.caption).foregroundColor(.secondary)
                                }.buttonStyle(.plain)
                                
                                Button(action: { onDelete(event.id) }) {
                                    Image(systemName: "trash").font(.caption).foregroundColor(.red.opacity(0.7))
                                }.buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                        
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
// MARK: - VUE D'UN MOIS PLEINE LARGEUR
// =========================================================================

struct FullWidthMonthView: View {
    let month: Date
    let events: [CalendarEvent]
    @Binding var selectedDate: Date
    let onAddEvent: (Date) -> Void
    let onEditEvent: (CalendarEvent) -> Void
    let onDeleteEvent: (UUID) -> Void
    
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
                        
                        FullWidthDayCellView(
                            date: date,
                            events: dayEvents,
                            isSelected: Calendar.current.isDate(date, inSameDayAs: selectedDate),
                            onTapDay: {
                                selectedDate = date
                                onAddEvent(date)
                            },
                            onEditEvent: onEditEvent,
                            onDeleteEvent: onDeleteEvent
                        )
                    } else {
                        Color.clear
                            .frame(height: 85)
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

// CELLULE D'UN JOUR PLEINE LARGEUR
struct FullWidthDayCellView: View {
    let date: Date
    let events: [CalendarEvent]
    let isSelected: Bool
    let onTapDay: () -> Void
    let onEditEvent: (CalendarEvent) -> Void
    let onDeleteEvent: (UUID) -> Void
    
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
                        .onTapGesture {
                            onEditEvent(event)
                        }
                    }
                }
            }
        }
        .frame(height: 85)
        .frame(maxWidth: .infinity)
        .background(Color(NSColor.windowBackgroundColor).opacity(isSelected ? 0.9 : 0.4))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(isToday ? Color.blue.opacity(0.6) : (isSelected ? Color.blue.opacity(0.3) : Color.gray.opacity(0.15)), lineWidth: 1))
    }
}

// =========================================================================
// MARK: - FORMULAIRE D'AJOUT / ÉDITION (AVEC SUGGESTIONS)
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
}
