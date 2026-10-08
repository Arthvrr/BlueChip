import SwiftUI

// =========================================================================
// MARK: - GLOBALS & TABS
// =========================================================================

enum AppTab: String, CaseIterable {
    case composition = "Composition", fundamentals = "Fundamentals", growth = "Growth", dividends = "Dividends"
    case valuation = "Valuation", projection = "Projection", simulation = "Simulation", watchlist = "Watchlist"
    case exposure = "Exposure", transactions = "Transactions", benchmark = "Benchmark", calendar = "Calendar"
    case wealth = "Wealth"
}

struct CustomTabBar: View {
    @Binding var selectedTab: AppTab
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 24) {
                ForEach(AppTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue)
                        .font(.system(size: 14, weight: selectedTab == tab ? .bold : .medium))
                        .foregroundColor(selectedTab == tab ? .primary : .secondary)
                        .padding(.vertical, 8)
                        .overlay(Rectangle().frame(height: 3).foregroundColor(selectedTab == tab ? .blue : .clear).offset(y: 4), alignment: .bottom)
                        .contentShape(Rectangle())
                        .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { selectedTab = tab } }
                }
            }.padding(.horizontal, 20)
        }.padding(.vertical, 6).background(Color(NSColor.windowBackgroundColor))
    }
}

// =========================================================================
// MARK: - UI COMPONENTS
// =========================================================================

struct BlueChipWatermark: View {
    var body: some View {
        HStack {
            Spacer()
            Text("Powered by BlueChip").font(.system(size: 10, weight: .bold, design: .rounded)).foregroundColor(.secondary.opacity(0.3))
        }.padding(.top, 2)
    }
}

struct DashboardCard: View {
    let title: String; let value: String; var titleIcon: String? = nil
    @Binding var privacyMode: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.subheadline).foregroundColor(.secondary).lineLimit(1).minimumScaleFactor(0.8)
                if let icon = titleIcon { Image(systemName: icon).foregroundColor(.secondary).font(.caption) }
            }
            Text(value).font(.title2).fontWeight(.bold).lineLimit(1).minimumScaleFactor(0.8).blur(radius: privacyMode ? 8 : 0)
        }
        .padding().frame(maxWidth: .infinity, alignment: .leading).frame(height: 110)
        .background(Color(NSColor.controlBackgroundColor)).cornerRadius(10)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

struct GoalProgressBar: View {
    let title: String; let currentValue: Double; let targetValue: Double
    @Binding var privacyMode: Bool
    
    var progress: Double { guard targetValue > 0 else { return 0 }; return min(max(currentValue / targetValue, 0), 1) }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Goal : \(title)").font(.headline)
                Spacer()
                Text("\(currentValue.formatted(.currency(code: "EUR"))) / \(targetValue.formatted(.currency(code: "EUR")))")
                    .font(.subheadline).fontWeight(.bold)
                    .foregroundColor(progress >= 1 ? .green : .primary)
                    .blur(radius: privacyMode ? 8 : 0)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.windowBackgroundColor)).frame(height: 14)
                    RoundedRectangle(cornerRadius: 8)
                        .fill(LinearGradient(gradient: Gradient(colors: [.blue, .purple]), startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(0, geometry.size.width * CGFloat(progress)), height: 14)
                        .animation(.spring(), value: progress)
                }
            }.frame(height: 14)
        }
        .padding().background(Color(NSColor.controlBackgroundColor)).cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        .help("Double-click to edit your goal")
    }
}

struct InteractiveLegendView: View {
    let items: [String]; let colorMap: (String) -> Color; @Binding var hiddenItems: Set<String>
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(items, id: \.self) { item in
                    Button(action: { withAnimation { if hiddenItems.contains(item) { hiddenItems.remove(item) } else { hiddenItems.insert(item) } } }) {
                        HStack(spacing: 6) {
                            Circle().fill(colorMap(item)).frame(width: 10, height: 10)
                            Text(item).font(.caption).foregroundColor(hiddenItems.contains(item) ? .secondary : .primary)
                        }
                    }
                    .buttonStyle(.plain)
                    .opacity(hiddenItems.contains(item) ? 0.4 : 1.0)
                }
            }.padding(.horizontal, 4)
        }
    }
}

// =========================================================================
// MARK: - MODERN FORMS (ADD, EDIT, GOALS)
// =========================================================================

struct AddPositionView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: PortfolioViewModel
    
    @State private var ticker = ""
    @State private var quantity: Double = 0
    @State private var pru: Double = 0
    @State private var dividend: Double = 0
    @State private var dividendGrowth5Y: Double = 5.0
    @State private var country = ""
    @State private var purchaseDate = Date()
    @State private var sector = ""
    @State private var marketCap = ""
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("New Position").font(.title2).fontWeight(.bold)
                Spacer()
                Button(action: { dismiss() }) { Image(systemName: "xmark.circle.fill").font(.title2).foregroundColor(.secondary) }.buttonStyle(.plain)
            }.padding()
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    GroupBox("Asset Information") {
                        VStack(spacing: 12) {
                            HStack {
                                TextField("Ticker (e.g., AAPL)", text: $ticker)
                                    .onChange(of: ticker) { ticker = ticker.uppercased() }
                                TextField("Country (e.g., US, FR)", text: $country)
                            }
                            HStack {
                                TextField("Sector", text: $sector)
                                TextField("Market Cap", text: $marketCap)
                            }
                        }
                    }
                    
                    GroupBox("Investment Details") {
                        VStack(spacing: 12) {
                            HStack {
                                TextField("Quantity", value: $quantity, format: .number)
                                TextField("Avg Cost (Original Currency)", value: $pru, format: .number)
                            }
                            DatePicker("Purchase Date", selection: $purchaseDate, displayedComponents: .date)
                        }
                    }
                    
                    GroupBox("Dividend Data") {
                        HStack {
                            TextField("Net Dividend/Share", value: $dividend, format: .number)
                            TextField("Div Growth 5Y (%)", value: $dividendGrowth5Y, format: .number)
                        }
                    }
                }.padding()
            }
            
            Divider()
            
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add Position") {
                    if !ticker.isEmpty && quantity > 0 {
                        viewModel.addPosition(ticker: ticker, quantity: quantity, pru: pru, dividend: dividend, dividendGrowth5Y: dividendGrowth5Y, country: country, sector: sector, marketCap: marketCap, purchaseDate: purchaseDate)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(ticker.isEmpty || quantity <= 0)
            }.padding()
        }
        .frame(width: 500, height: 480)
    }
}

struct EditPositionView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: PortfolioViewModel
    let position: Position
    
    @State private var quantity: Double
    @State private var pru: Double
    @State private var dividend: Double
    @State private var dividendGrowth5Y: Double
    @State private var country: String
    @State private var sector: String
    @State private var marketCap: String
    @State private var purchaseDate: Date
    @State private var dividendMonths: Set<Int>
    
    let monthsNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    
    init(viewModel: PortfolioViewModel, position: Position) {
        self.viewModel = viewModel; self.position = position
        _quantity = State(initialValue: position.quantity)
        _pru = State(initialValue: position.averageCost)
        _dividend = State(initialValue: position.annualDividendNet)
        _dividendGrowth5Y = State(initialValue: position.dividendGrowth5Y)
        _country = State(initialValue: position.country)
        _sector = State(initialValue: position.sector)
        _marketCap = State(initialValue: position.marketCap)
        _purchaseDate = State(initialValue: position.purchaseDate)
        _dividendMonths = State(initialValue: position.dividendMonths)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Edit \(position.ticker)").font(.title2).fontWeight(.bold)
                Spacer()
                Button(action: { dismiss() }) { Image(systemName: "xmark.circle.fill").font(.title2).foregroundColor(.secondary) }.buttonStyle(.plain)
            }.padding()
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    GroupBox("Asset Information") {
                        VStack(spacing: 12) {
                            HStack {
                                TextField("Country", text: $country)
                                TextField("Sector", text: $sector)
                            }
                            TextField("Market Cap", text: $marketCap)
                        }
                    }
                    
                    GroupBox("Investment Details") {
                        VStack(spacing: 12) {
                            HStack {
                                TextField("Quantity", value: $quantity, format: .number)
                                TextField("Avg Cost", value: $pru, format: .number)
                            }
                            DatePicker("Purchase Date", selection: $purchaseDate, displayedComponents: .date)
                        }
                    }
                    
                    GroupBox("Dividend Data") {
                        VStack(spacing: 16) {
                            HStack {
                                TextField("Net Dividend/Share", value: $dividend, format: .number)
                                TextField("Div Growth 5Y (%)", value: $dividendGrowth5Y, format: .number)
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Dividend Payment Months").font(.caption).foregroundColor(.secondary)
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 8) {
                                    ForEach(0..<12, id: \.self) { index in
                                        let m = index + 1
                                        Toggle(monthsNames[index], isOn: Binding(
                                            get: { dividendMonths.contains(m) },
                                            set: { isSet in if isSet { dividendMonths.insert(m) } else { dividendMonths.remove(m) } }
                                        ))
                                        .toggleStyle(.button)
                                        .font(.caption2)
                                    }
                                }
                            }
                        }
                    }
                }.padding()
            }
            
            Divider()
            
            HStack {
                Button(role: .destructive) {
                    viewModel.deletePosition(id: position.id)
                    dismiss()
                } label: { Label("Delete", systemImage: "trash") }
                
                Spacer()
                
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save Changes") {
                    viewModel.updatePosition(id: position.id, quantity: quantity, pru: pru, dividend: dividend, dividendGrowth5Y: dividendGrowth5Y, country: country, sector: sector, marketCap: marketCap, dividendMonths: dividendMonths, purchaseDate: purchaseDate)
                    dismiss()
                }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }.padding()
        }
        .frame(width: 500, height: 600)
    }
}

// =========================================================================
// MARK: - SMALL EDIT PANELS
// =========================================================================

struct SimpleNumberEditView: View {
    @Environment(\.dismiss) var dismiss
    let title: String
    @Binding var value: Double
    @State private var input: Double = 0
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.title2).fontWeight(.bold)
                Spacer()
                Button(action: { dismiss() }) { Image(systemName: "xmark.circle.fill").font(.title2).foregroundColor(.secondary) }.buttonStyle(.plain)
            }.padding()
            
            Divider()
            
            VStack(alignment: .leading, spacing: 16) {
                GroupBox {
                    HStack {
                        Text("Amount:")
                        Spacer()
                        TextField("€", value: $input, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 140)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }.padding()
            
            Spacer()
            Divider()
            
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") { value = input; dismiss() }
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }.padding()
        }
        .frame(width: 350, height: 200)
        .onAppear { input = value }
    }
}

struct EditGoalView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: PortfolioViewModel
    @State private var selectedGoal: GoalType
    @State private var targetInput: Double
    
    init(viewModel: PortfolioViewModel) {
        self.viewModel = viewModel
        _selectedGoal = State(initialValue: viewModel.currentGoalType)
        _targetInput = State(initialValue: viewModel.currentGoalTarget)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Portfolio Goal").font(.title2).fontWeight(.bold)
                Spacer()
                Button(action: { dismiss() }) { Image(systemName: "xmark.circle.fill").font(.title2).foregroundColor(.secondary) }.buttonStyle(.plain)
            }.padding()
            
            Divider()
            
            VStack(alignment: .leading, spacing: 16) {
                GroupBox {
                    VStack(spacing: 12) {
                        HStack {
                            Text("Goal Type:")
                            Spacer()
                            Picker("", selection: $selectedGoal) {
                                ForEach(GoalType.allCases, id: \.self) { type in Text(type.rawValue).tag(type) }
                            }.frame(width: 200)
                        }
                        
                        HStack {
                            Text("Target Amount:")
                            Spacer()
                            TextField("€", value: $targetInput, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 140)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
            }.padding()
            
            Spacer()
            Divider()
            
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save Goal") {
                    viewModel.currentGoalType = selectedGoal
                    viewModel.currentGoalTarget = targetInput
                    dismiss()
                }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }.padding()
        }
        .frame(width: 420, height: 260)
    }
}
