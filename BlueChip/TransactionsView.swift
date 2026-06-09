import SwiftUI
import Charts

// =========================================================================
// MARK: - HELPERS
// =========================================================================

extension Color {
    static func forTransactionType(_ type: TransactionType) -> Color {
        switch type {
        case .deposit:    return .green
        case .withdrawal: return .red
        case .buy:        return .blue
        case .sell:       return .orange
        case .dividend:   return .mint
        case .other:      return .gray
        }
    }
}

// =========================================================================
// MARK: - MAIN VIEW
// =========================================================================

struct TransactionsView: View {
    @ObservedObject var viewModel: PortfolioViewModel
    @Binding var privacyMode: Bool

    @State private var showAddSheet        = false
    @State private var showGoalSheet       = false
    @State private var showAddColumnSheet  = false
    @State private var editingTransaction: Transaction? = nil
    @State private var searchText          = ""
    @State private var filterType: TransactionType? = nil

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 24) {
                TransactionsDashboardSection(viewModel: viewModel, privacyMode: $privacyMode)

                TransactionsGoalBar(viewModel: viewModel, privacyMode: $privacyMode)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { showGoalSheet = true }

                TransactionsTableSection(
                    viewModel: viewModel,
                    privacyMode: $privacyMode,
                    searchText: $searchText,
                    filterType: $filterType,
                    editingTransaction: $editingTransaction,
                    showAddSheet: $showAddSheet,
                    showAddColumnSheet: $showAddColumnSheet
                )

                TransactionsYearlySummarySection(viewModel: viewModel, privacyMode: $privacyMode)
            }
            .padding()
        }
        .sheet(isPresented: $showAddSheet) {
            AddEditTransactionView(viewModel: viewModel, transaction: nil)
        }
        .sheet(item: $editingTransaction) { tx in
            AddEditTransactionView(viewModel: viewModel, transaction: tx)
        }
        .sheet(isPresented: $showGoalSheet) {
            EditTransactionGoalView(viewModel: viewModel)
        }
        .sheet(isPresented: $showAddColumnSheet) {
            AddCustomColumnView(viewModel: viewModel)
        }
    }
}

// =========================================================================
// MARK: - DASHBOARD
// =========================================================================

struct TransactionsDashboardSection: View {
    @ObservedObject var viewModel: PortfolioViewModel
    @Binding var privacyMode: Bool

    var tx: [Transaction] { viewModel.transactions }

    var totalDeposited:   Double { tx.filter { $0.type == .deposit    }.reduce(0) { $0 + $1.amountEUR } }
    var totalWithdrawn:   Double { tx.filter { $0.type == .withdrawal }.reduce(0) { $0 + $1.amountEUR } }
    var totalBought:      Double { tx.filter { $0.type == .buy        }.reduce(0) { $0 + $1.amountEUR } }
    var totalSold:        Double { tx.filter { $0.type == .sell       }.reduce(0) { $0 + $1.amountEUR } }
    var totalDividends:   Double { tx.filter { $0.type == .dividend   }.reduce(0) { $0 + $1.amountEUR } }
    var totalCustomFees:  Double {
        tx.reduce(0) { sum, t in
            sum + t.customFields.values.reduce(0, +)
        }
    }
    var netCashFlow:      Double { totalDeposited - totalWithdrawn }

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                txCard("Total Deposited",   value: totalDeposited,  color: .green)
                txCard("Total Withdrawn",   value: totalWithdrawn,  color: .red)
                txCard("Net Cash Flow",     value: netCashFlow,     color: netCashFlow >= 0 ? .green : .red)
                txCard("Total Invested",    value: totalBought,     color: .blue)
            }
            HStack(spacing: 16) {
                txCard("Total Sold",        value: totalSold,       color: .orange)
                txCard("Dividends Received",value: totalDividends,  color: .mint)
                txCard("Total Fees & Taxes",value: totalCustomFees, color: .red)
                DashboardCard(title: "Total Transactions", value: "\(tx.count)", privacyMode: .constant(false))
            }
        }
    }

    @ViewBuilder
    func txCard(_ title: String, value: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline).foregroundColor(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            Text(value.formatted(.currency(code: "EUR").precision(.fractionLength(2))))
                .font(.title2).fontWeight(.bold)
                .foregroundColor(color)
                .blur(radius: privacyMode ? 8 : 0)
        }
        .padding().frame(maxWidth: .infinity, alignment: .leading).frame(height: 110)
        .background(Color(NSColor.controlBackgroundColor)).cornerRadius(10)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// =========================================================================
// MARK: - GOAL BAR
// =========================================================================

struct TransactionsGoalBar: View {
    @ObservedObject var viewModel: PortfolioViewModel
    @Binding var privacyMode: Bool

    var txCount: Int { viewModel.transactions.count }
    var target: Double { viewModel.transactionGoalTarget }
    var progress: Double { target > 0 ? min(Double(txCount) / target, 1) : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Goal : \(Int(target)) Transactions Logged")
                    .font(.headline)
                Spacer()
                Text("\(txCount) / \(Int(target))")
                    .font(.subheadline).fontWeight(.bold)
                    .foregroundColor(progress >= 1 ? .green : .primary)
                    .blur(radius: privacyMode ? 8 : 0)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.windowBackgroundColor)).frame(height: 14)
                    RoundedRectangle(cornerRadius: 8)
                        .fill(LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(0, geo.size.width * CGFloat(progress)), height: 14)
                        .animation(.spring(), value: progress)
                }
            }.frame(height: 14)
        }
        .padding().background(Color(NSColor.controlBackgroundColor)).cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        .help("Double-click to edit your goal")
    }
}

// =========================================================================
// MARK: - TABLE SECTION
// =========================================================================

struct TransactionsTableSection: View {
    @ObservedObject var viewModel: PortfolioViewModel
    @Binding var privacyMode: Bool
    @Binding var searchText: String
    @Binding var filterType: TransactionType?
    @Binding var editingTransaction: Transaction?
    @Binding var showAddSheet: Bool
    @Binding var showAddColumnSheet: Bool

    let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .short; return f
    }()

    var filtered: [Transaction] {
        var list = viewModel.transactions.sorted { $0.date > $1.date }
        if let f = filterType { list = list.filter { $0.type == f } }
        if !searchText.isEmpty {
            list = list.filter {
                $0.ticker.localizedCaseInsensitiveContains(searchText) ||
                $0.note.localizedCaseInsensitiveContains(searchText) ||
                $0.type.rawValue.localizedCaseInsensitiveContains(searchText)
            }
        }
        return list
    }

    var columns: [String] { viewModel.transactionCustomColumns }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header row
            HStack {
                Text("Transaction History").font(.title2).fontWeight(.bold).foregroundColor(.secondary)
                Spacer()

                // Filtre par type
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        filterChip(nil, label: "All")
                        ForEach(TransactionType.allCases, id: \.self) { type in
                            filterChip(type, label: type.rawValue)
                        }
                    }
                }

                // Search
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                    TextField("Search…", text: $searchText).textFieldStyle(.plain).frame(width: 120)
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                        }.buttonStyle(.plain)
                    }
                }
                .padding(6).background(Color(NSColor.windowBackgroundColor)).cornerRadius(8)

                Button(action: { showAddColumnSheet = true }) {
                    Label("Column", systemImage: "plus.rectangle")
                }.buttonStyle(.bordered)

                Button(action: { showAddSheet = true }) {
                    Label("Add", systemImage: "plus")
                }.buttonStyle(.borderedProminent)
            }.padding(.bottom, 4)

            // Table
            VStack(spacing: 0) {
                // HEADER
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        headerCell("Date",     width: 130)
                        headerCell("Type",     width: 100)
                        headerCell("Ticker",   width: 80)
                        headerCell("Qty",      width: 70)
                        headerCell("Amount €", width: 110)
                        ForEach(columns, id: \.self) { col in
                            headerCell(col, width: 110)
                        }
                        headerCell("Note",     width: 160)
                        headerCell("",         width: 40) // actions
                    }
                    .font(.subheadline).foregroundColor(.secondary)
                    .padding(.vertical, 10).padding(.horizontal, 8)
                }
                .background(Color(NSColor.windowBackgroundColor))
                Divider()

                // ROWS
                if filtered.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "clock.arrow.circlepath").font(.system(size: 36)).foregroundColor(.secondary)
                        Text(searchText.isEmpty ? "No transactions yet. Tap + Add to log your first." : "No results for \"\(searchText)\".")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity).padding(40)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(filtered) { tx in
                                TransactionRowView(
                                    tx: tx,
                                    columns: columns,
                                    privacyMode: privacyMode,
                                    dateFormatter: dateFormatter,
                                    onEdit: { editingTransaction = tx },
                                    onDelete: { viewModel.transactions.removeAll { $0.id == tx.id } }
                                )
                                Divider()
                            }
                        }
                    }
                }
            }
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))
        }
        .frame(height: 480)
        .padding().background(Color(NSColor.controlBackgroundColor)).cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }

    @ViewBuilder
    func headerCell(_ text: String, width: CGFloat) -> some View {
        Text(text).frame(width: width, alignment: .leading).padding(.horizontal, 6)
    }

    @ViewBuilder
    func filterChip(_ type: TransactionType?, label: String) -> some View {
        let active = filterType == type
        Button(action: { filterType = type }) {
            Text(label).font(.caption).fontWeight(active ? .bold : .regular)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(active ? Color.blue.opacity(0.2) : Color(NSColor.windowBackgroundColor))
                .foregroundColor(active ? .blue : .secondary)
                .cornerRadius(12)
        }.buttonStyle(.plain)
    }
}

// MARK: - Transaction Row
struct TransactionRowView: View {
    let tx: Transaction
    let columns: [String]
    let privacyMode: Bool
    let dateFormatter: DateFormatter
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                // Date
                Text(dateFormatter.string(from: tx.date))
                    .font(.system(size: 12))
                    .frame(width: 130, alignment: .leading).padding(.horizontal, 6)

                // Type badge
                HStack(spacing: 4) {
                    Image(systemName: tx.type.icon).font(.caption)
                    Text(tx.type.rawValue).font(.caption).fontWeight(.semibold)
                }
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Color.forTransactionType(tx.type).opacity(0.15))
                .foregroundColor(Color.forTransactionType(tx.type))
                .cornerRadius(6)
                .frame(width: 100, alignment: .leading).padding(.horizontal, 6)

                // Ticker
                Text(tx.ticker.isEmpty ? "—" : tx.ticker)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 80, alignment: .leading).padding(.horizontal, 6)

                // Qty
                Text(tx.quantity == 0 ? "—" : tx.quantity.formatted(.number.precision(.fractionLength(4))))
                    .font(.system(size: 12))
                    .frame(width: 70, alignment: .leading).padding(.horizontal, 6)

                // Amount
                Text(tx.amountEUR.formatted(.currency(code: "EUR").precision(.fractionLength(2))))
                    .fontWeight(.semibold)
                    .foregroundColor(tx.type == .withdrawal || tx.type == .sell ? .orange : .primary)
                    .font(.system(size: 13))
                    .blur(radius: privacyMode ? 6 : 0)
                    .frame(width: 110, alignment: .leading).padding(.horizontal, 6)

                // Custom columns
                ForEach(columns, id: \.self) { col in
                    let val = tx.customFields[col] ?? 0
                    Text(val == 0 ? "—" : val.formatted(.currency(code: "EUR").precision(.fractionLength(2))))
                        .font(.system(size: 12))
                        .foregroundColor(val > 0 ? .red : .secondary)
                        .blur(radius: privacyMode ? 6 : 0)
                        .frame(width: 110, alignment: .leading).padding(.horizontal, 6)
                }

                // Note
                Text(tx.note.isEmpty ? "—" : tx.note)
                    .font(.system(size: 12)).foregroundColor(.secondary).lineLimit(1)
                    .frame(width: 160, alignment: .leading).padding(.horizontal, 6)

                // Actions
                HStack(spacing: 6) {
                    Button(action: onEdit) {
                        Image(systemName: "pencil").font(.caption)
                    }.buttonStyle(.plain).foregroundColor(.secondary)
                    Button(action: onDelete) {
                        Image(systemName: "trash").font(.caption)
                    }.buttonStyle(.plain).foregroundColor(.red.opacity(0.7))
                }
                .frame(width: 40)
            }
            .padding(.vertical, 10).padding(.horizontal, 8)
        }
    }
}

// =========================================================================
// MARK: - YEARLY SUMMARY
// =========================================================================

struct TransactionsYearlySummarySection: View {
    @ObservedObject var viewModel: PortfolioViewModel
    @Binding var privacyMode: Bool

    var years: [Int] {
        let all = viewModel.transactions.map { Calendar.current.component(.year, from: $0.date) }
        return Array(Set(all)).sorted(by: >)
    }

    func txForYear(_ year: Int) -> [Transaction] {
        viewModel.transactions.filter { Calendar.current.component(.year, from: $0.date) == year }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Yearly Summary").font(.title2).fontWeight(.bold).foregroundColor(.secondary)

            if years.isEmpty {
                Text("No data yet.").foregroundColor(.secondary).padding()
            } else {
                VStack(spacing: 0) {
                    // Header
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 0) {
                            yearHeaderCell("Year",          width: 70)
                            yearHeaderCell("Transactions",  width: 110)
                            yearHeaderCell("Buys",          width: 70)
                            yearHeaderCell("Sells",         width: 70)
                            yearHeaderCell("Deposits",      width: 80)
                            yearHeaderCell("Withdrawals",   width: 90)
                            yearHeaderCell("Dividends",     width: 90)
                            yearHeaderCell("Invested €",    width: 110)
                            yearHeaderCell("Sold €",        width: 110)
                            yearHeaderCell("Deposited €",   width: 110)
                            yearHeaderCell("Fees & Taxes",  width: 110)
                            ForEach(viewModel.transactionCustomColumns, id: \.self) { col in
                                yearHeaderCell(col, width: 110)
                            }
                        }
                        .font(.subheadline).foregroundColor(.secondary)
                        .padding(.vertical, 10).padding(.horizontal, 8)
                    }
                    .background(Color(NSColor.windowBackgroundColor))
                    Divider()

                    // Rows
                    ForEach(years, id: \.self) { year in
                        let list = txForYear(year)
                        YearlySummaryRowView(year: year, transactions: list, columns: viewModel.transactionCustomColumns, privacyMode: privacyMode)
                        Divider()
                    }

                    // Totaux
                    YearlyTotalsRowView(transactions: viewModel.transactions, columns: viewModel.transactionCustomColumns, privacyMode: privacyMode)
                }
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))
            }
        }
        .padding().background(Color(NSColor.controlBackgroundColor)).cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }

    @ViewBuilder
    func yearHeaderCell(_ text: String, width: CGFloat) -> some View {
        Text(text).frame(width: width, alignment: .leading).padding(.horizontal, 6)
    }
}

struct YearlySummaryRowView: View {
    let year: Int
    let transactions: [Transaction]
    let columns: [String]
    let privacyMode: Bool

    var buys:        Int    { transactions.filter { $0.type == .buy        }.count }
    var sells:       Int    { transactions.filter { $0.type == .sell       }.count }
    var deposits:    Int    { transactions.filter { $0.type == .deposit    }.count }
    var withdrawals: Int    { transactions.filter { $0.type == .withdrawal }.count }
    var dividends:   Int    { transactions.filter { $0.type == .dividend   }.count }
    var invested:    Double { transactions.filter { $0.type == .buy        }.reduce(0) { $0 + $1.amountEUR } }
    var sold:        Double { transactions.filter { $0.type == .sell       }.reduce(0) { $0 + $1.amountEUR } }
    var deposited:   Double { transactions.filter { $0.type == .deposit    }.reduce(0) { $0 + $1.amountEUR } }
    var totalFees:   Double { transactions.reduce(0) { $0 + $1.customFields.values.reduce(0, +) } }

    func colTotal(_ col: String) -> Double {
        transactions.reduce(0) { $0 + ($1.customFields[col] ?? 0) }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                Text(String(year)).fontWeight(.bold).frame(width: 70, alignment: .leading).padding(.horizontal, 6)
                numCell(transactions.count, width: 110, color: .primary)
                numCell(buys,        width: 70,  color: .blue)
                numCell(sells,       width: 70,  color: .orange)
                numCell(deposits,    width: 80,  color: .green)
                numCell(withdrawals, width: 90,  color: .red)
                numCell(dividends,   width: 90,  color: .mint)
                eurCell(invested,    width: 110, color: .blue)
                eurCell(sold,        width: 110, color: .orange)
                eurCell(deposited,   width: 110, color: .green)
                eurCell(totalFees,   width: 110, color: .red)
                ForEach(columns, id: \.self) { col in
                    eurCell(colTotal(col), width: 110, color: .red)
                }
            }
            .padding(.vertical, 10).padding(.horizontal, 8)
        }
    }

    @ViewBuilder
    func numCell(_ v: Int, width: CGFloat, color: Color) -> some View {
        Text("\(v)").foregroundColor(v == 0 ? .secondary : color).fontWeight(v == 0 ? .regular : .semibold)
            .frame(width: width, alignment: .leading).padding(.horizontal, 6)
    }
    @ViewBuilder
    func eurCell(_ v: Double, width: CGFloat, color: Color) -> some View {
        Text(v == 0 ? "—" : v.formatted(.currency(code: "EUR").precision(.fractionLength(2))))
            .foregroundColor(v == 0 ? .secondary : color).fontWeight(v == 0 ? .regular : .semibold)
            .font(.system(size: 12))
            .blur(radius: privacyMode ? 6 : 0)
            .frame(width: width, alignment: .leading).padding(.horizontal, 6)
    }
}

struct YearlyTotalsRowView: View {
    let transactions: [Transaction]
    let columns: [String]
    let privacyMode: Bool

    var totalBuys:        Int    { transactions.filter { $0.type == .buy        }.count }
    var totalSells:       Int    { transactions.filter { $0.type == .sell       }.count }
    var totalDeposits:    Int    { transactions.filter { $0.type == .deposit    }.count }
    var totalWithdrawals: Int    { transactions.filter { $0.type == .withdrawal }.count }
    var totalDividends:   Int    { transactions.filter { $0.type == .dividend   }.count }
    var totalInvested:    Double { transactions.filter { $0.type == .buy        }.reduce(0) { $0 + $1.amountEUR } }
    var totalSold:        Double { transactions.filter { $0.type == .sell       }.reduce(0) { $0 + $1.amountEUR } }
    var totalDeposited:   Double { transactions.filter { $0.type == .deposit    }.reduce(0) { $0 + $1.amountEUR } }
    var totalFees:        Double { transactions.reduce(0) { $0 + $1.customFields.values.reduce(0, +) } }
    func colTotal(_ col: String) -> Double { transactions.reduce(0) { $0 + ($1.customFields[col] ?? 0) } }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                Text("TOTAL").fontWeight(.bold).italic().frame(width: 70, alignment: .leading).padding(.horizontal, 6)
                numCell(transactions.count, width: 110)
                numCell(totalBuys,        width: 70)
                numCell(totalSells,       width: 70)
                numCell(totalDeposits,    width: 80)
                numCell(totalWithdrawals, width: 90)
                numCell(totalDividends,   width: 90)
                eurCell(totalInvested,    width: 110)
                eurCell(totalSold,        width: 110)
                eurCell(totalDeposited,   width: 110)
                eurCell(totalFees,        width: 110)
                ForEach(columns, id: \.self) { col in
                    eurCell(colTotal(col), width: 110)
                }
            }
            .padding(.vertical, 10).padding(.horizontal, 8)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.6))
        }
    }

    @ViewBuilder
    func numCell(_ v: Int, width: CGFloat) -> some View {
        Text("\(v)").fontWeight(.bold).frame(width: width, alignment: .leading).padding(.horizontal, 6)
    }
    @ViewBuilder
    func eurCell(_ v: Double, width: CGFloat) -> some View {
        Text(v == 0 ? "—" : v.formatted(.currency(code: "EUR").precision(.fractionLength(2))))
            .fontWeight(.bold).font(.system(size: 12))
            .blur(radius: privacyMode ? 6 : 0)
            .frame(width: width, alignment: .leading).padding(.horizontal, 6)
    }
}

// =========================================================================
// MARK: - FORMS
// =========================================================================

struct AddEditTransactionView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: PortfolioViewModel
    let transaction: Transaction?

    @State private var date         = Date()
    @State private var type         = TransactionType.buy
    @State private var ticker       = ""
    @State private var quantity     = ""
    @State private var amountEUR    = ""
    @State private var note         = ""
    @State private var customValues: [String: String] = [:]

    var isEditing: Bool { transaction != nil }

    var body: some View {
        VStack(spacing: 0) {
            // Title
            HStack {
                Text(isEditing ? "Edit Transaction" : "New Transaction")
                    .font(.title2).fontWeight(.bold)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill").font(.title2).foregroundColor(.secondary)
                }.buttonStyle(.plain)
            }.padding()
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Date & Time
                    GroupBox("Date & Time") {
                        DatePicker("", selection: $date, displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden()
                    }

                    // Type
                    GroupBox("Transaction Type") {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                            ForEach(TransactionType.allCases, id: \.self) { t in
                                Button(action: { type = t }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: t.icon)
                                        Text(t.rawValue)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(type == t ? Color.forTransactionType(t).opacity(0.2) : Color(NSColor.windowBackgroundColor))
                                    .foregroundColor(type == t ? Color.forTransactionType(t) : .secondary)
                                    .cornerRadius(8)
                                    .fontWeight(type == t ? .semibold : .regular)
                                }.buttonStyle(.plain)
                            }
                        }
                    }

                    // Ticker & Quantity (only for buy/sell)
                    if type == .buy || type == .sell {
                        GroupBox("Asset") {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Ticker").font(.caption).foregroundColor(.secondary)
                                    TextField("e.g. AAPL", text: $ticker)
                                        .textFieldStyle(.roundedBorder)
                                        .onChange(of: ticker) { ticker = ticker.uppercased() }
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Quantity").font(.caption).foregroundColor(.secondary)
                                    TextField("0.00", text: $quantity).textFieldStyle(.roundedBorder)
                                }
                            }
                        }
                    }

                    // Amount
                    GroupBox("Amount (€)") {
                        TextField("0.00", text: $amountEUR).textFieldStyle(.roundedBorder)
                    }

                    // Custom columns
                    if !viewModel.transactionCustomColumns.isEmpty {
                        GroupBox("Fees & Custom Fields") {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(viewModel.transactionCustomColumns, id: \.self) { col in
                                    HStack {
                                        Text(col).frame(width: 130, alignment: .leading)
                                        TextField("0.00", text: Binding(
                                            get: { customValues[col] ?? "" },
                                            set: { customValues[col] = $0 }
                                        )).textFieldStyle(.roundedBorder)
                                    }
                                }
                            }
                        }
                    }

                    // Note
                    GroupBox("Note (optional)") {
                        TextField("Add a note…", text: $note).textFieldStyle(.roundedBorder)
                    }
                }.padding()
            }

            Divider()
            // Buttons
            HStack {
                if isEditing {
                    Button(role: .destructive) {
                        viewModel.transactions.removeAll { $0.id == transaction!.id }
                        dismiss()
                    } label: { Text("Delete") }
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(isEditing ? "Save" : "Add") { save() }
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }.padding()
        }
        .frame(width: 520)
        .onAppear { populate() }
    }

    func populate() {
        guard let tx = transaction else { return }
        date      = tx.date
        type      = tx.type
        ticker    = tx.ticker
        quantity  = tx.quantity == 0 ? "" : String(tx.quantity)
        amountEUR = tx.amountEUR == 0 ? "" : String(tx.amountEUR)
        note      = tx.note
        for (k, v) in tx.customFields { customValues[k] = String(v) }
    }

    func save() {
        let qty = Double(quantity.replacingOccurrences(of: ",", with: ".")) ?? 0
        let amt = Double(amountEUR.replacingOccurrences(of: ",", with: ".")) ?? 0
        var fields: [String: Double] = [:]
        for col in viewModel.transactionCustomColumns {
            if let raw = customValues[col], let val = Double(raw.replacingOccurrences(of: ",", with: ".")) {
                fields[col] = val
            }
        }
        if isEditing, let idx = viewModel.transactions.firstIndex(where: { $0.id == transaction!.id }) {
            viewModel.transactions[idx].date         = date
            viewModel.transactions[idx].type         = type
            viewModel.transactions[idx].ticker       = ticker
            viewModel.transactions[idx].quantity     = qty
            viewModel.transactions[idx].amountEUR    = amt
            viewModel.transactions[idx].note         = note
            viewModel.transactions[idx].customFields = fields
        } else {
            viewModel.transactions.append(Transaction(date: date, type: type, ticker: ticker, quantity: qty, amountEUR: amt, note: note, customFields: fields))
        }
        dismiss()
    }
}

struct EditTransactionGoalView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: PortfolioViewModel
    @State private var input: Double

    init(viewModel: PortfolioViewModel) {
        self.viewModel = viewModel
        _input = State(initialValue: viewModel.transactionGoalTarget)
    }

    var body: some View {
        Form {
            Section(header: Text("Transaction Goal").font(.headline)) {
                TextField("Target number of transactions", value: $input, format: .number)
            }.padding()
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") { viewModel.transactionGoalTarget = input; dismiss() }
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }.padding()
        }.frame(width: 380).padding()
    }
}

struct AddCustomColumnView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: PortfolioViewModel
    @State private var columnName = ""
    @State private var toDelete: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Custom Columns").font(.title2).fontWeight(.bold)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill").font(.title2).foregroundColor(.secondary)
                }.buttonStyle(.plain)
            }.padding()
            Divider()

            VStack(alignment: .leading, spacing: 16) {
                // Existing columns
                if !viewModel.transactionCustomColumns.isEmpty {
                    Text("Current columns").font(.subheadline).foregroundColor(.secondary)
                    ForEach(viewModel.transactionCustomColumns, id: \.self) { col in
                        HStack {
                            Text(col)
                            Spacer()
                            Button(action: {
                                viewModel.transactionCustomColumns.removeAll { $0 == col }
                            }) {
                                Image(systemName: "trash").foregroundColor(.red.opacity(0.7))
                            }.buttonStyle(.plain)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Color(NSColor.windowBackgroundColor))
                        .cornerRadius(8)
                    }
                    Divider()
                }

                // Add new
                Text("Add a column").font(.subheadline).foregroundColor(.secondary)
                HStack {
                    TextField("Column name (e.g. TOB, Frais…)", text: $columnName)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        let name = columnName.trimmingCharacters(in: .whitespaces)
                        guard !name.isEmpty, !viewModel.transactionCustomColumns.contains(name) else { return }
                        viewModel.transactionCustomColumns.append(name)
                        columnName = ""
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(columnName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }.padding()

            Spacer()
            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }.padding()
        }
        .frame(width: 440, height: 460)
    }
}
