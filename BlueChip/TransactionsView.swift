import SwiftUI
import Charts

// =========================================================================
// MARK: - ZOOM ENUM
// =========================================================================

enum TxChartZoomType: String, Identifiable {
    case annualCount, typeSummary, buysOverTime, taxBreakdown
    var id: String { self.rawValue }
}

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

// Responsive column layout helper
struct TxColumnLayout {
    let fixedWidths: [CGFloat]   // Date, Type, Ticker, Qty, Amount, Note, Actions
    let customWidth: CGFloat      // Per custom column

    static func compute(totalWidth: CGFloat, customCount: Int) -> TxColumnLayout {
        // Fixed columns: Date=120, Type=95, Ticker=70, Qty=65, Amount=100, Note=flex, Actions=44
        let fixedTotal: CGFloat = 120 + 95 + 70 + 65 + 100 + 44
        let customTotal: CGFloat = customCount == 0 ? 0 : CGFloat(customCount) * 100
        let remaining = max(totalWidth - fixedTotal - customTotal - 32, 120)
        let noteWidth = min(remaining, 280)
        return TxColumnLayout(
            fixedWidths: [120, 95, 70, 65, 100, noteWidth, 44],
            customWidth: 100
        )
    }
    var dateW: CGFloat   { fixedWidths[0] }
    var typeW: CGFloat   { fixedWidths[1] }
    var tickerW: CGFloat { fixedWidths[2] }
    var qtyW: CGFloat    { fixedWidths[3] }
    var amtW: CGFloat    { fixedWidths[4] }
    var noteW: CGFloat   { fixedWidths[5] }
    var actW: CGFloat    { fixedWidths[6] }
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
    
    // NOUVEAU: État pour le zoom des graphes
    @State private var chartToZoom: TxChartZoomType? = nil

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

                TransactionsChartsSection(viewModel: viewModel, privacyMode: $privacyMode, chartToZoom: $chartToZoom)
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
        // NOUVEAU: Sheet pour le zoom
        .sheet(item: $chartToZoom) { type in
            TransactionsFullScreenChartView(zoomType: type, viewModel: viewModel, privacyMode: $privacyMode)
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
    var totalCustomFees:  Double { tx.reduce(0) { $0 + $1.customFields.values.reduce(0, +) } }
    var netCashFlow:      Double { totalDeposited - totalWithdrawn }

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                txCard("Total Deposited",    value: totalDeposited,  color: .green)
                txCard("Total Withdrawn",    value: totalWithdrawn,  color: .red)
                txCard("Net Cash Flow",      value: netCashFlow,     color: netCashFlow >= 0 ? .green : .red)
                txCard("Total Invested",     value: totalBought,     color: .blue)
            }
            HStack(spacing: 16) {
                txCard("Total Sold",         value: totalSold,       color: .orange)
                txCard("Dividends Received", value: totalDividends,  color: .mint)
                txCard("Total Fees & Taxes", value: totalCustomFees, color: .red)
                DashboardCard(title: "Total Transactions", value: "\(tx.count)", privacyMode: .constant(false))
            }
        }
    }

    @ViewBuilder
    func txCard(_ title: String, value: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline).foregroundColor(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            Text(value.formatted(.currency(code: "EUR").precision(.fractionLength(2))))
                .font(.title2).fontWeight(.bold).foregroundColor(color)
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

    var txCount: Int   { viewModel.transactions.count }
    var target: Double { viewModel.transactionGoalTarget }
    var progress: Double { target > 0 ? min(Double(txCount) / target, 1) : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Goal : \(Int(target)) Transactions Logged").font(.headline)
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
            HStack {
                Text("Transaction History").font(.title2).fontWeight(.bold).foregroundColor(.secondary)
                Spacer()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        filterChip(nil, label: "All")
                        ForEach(TransactionType.allCases, id: \.self) { type in
                            filterChip(type, label: type.rawValue)
                        }
                    }
                }
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

            GeometryReader { geo in
                let layout = TxColumnLayout.compute(totalWidth: geo.size.width, customCount: columns.count)
                VStack(spacing: 0) {
                    txHeaderRow(layout: layout).background(Color(NSColor.windowBackgroundColor))
                    Divider()
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
                                        tx: tx, columns: columns, layout: layout,
                                        privacyMode: privacyMode, dateFormatter: dateFormatter,
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
            .frame(height: 420)
        }
        .padding().background(Color(NSColor.controlBackgroundColor)).cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }

    @ViewBuilder
    func txHeaderRow(layout: TxColumnLayout) -> some View {
        HStack(spacing: 0) {
            hCell("Date",     w: layout.dateW)
            hCell("Type",     w: layout.typeW)
            hCell("Ticker",   w: layout.tickerW)
            hCell("Qty",      w: layout.qtyW)
            hCell("Amount €", w: layout.amtW)
            ForEach(columns, id: \.self) { col in hCell(col, w: layout.customWidth) }
            hCell("Note",     w: layout.noteW)
            hCell("",         w: layout.actW)
        }
        .font(.subheadline).foregroundColor(.secondary)
        .padding(.vertical, 10).padding(.horizontal, 8)
    }

    @ViewBuilder
    func hCell(_ text: String, w: CGFloat) -> some View {
        Text(text).frame(width: w, alignment: .leading).padding(.horizontal, 4)
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

struct TransactionRowView: View {
    let tx: Transaction
    let columns: [String]
    let layout: TxColumnLayout
    let privacyMode: Bool
    let dateFormatter: DateFormatter
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Text(dateFormatter.string(from: tx.date))
                .font(.system(size: 12))
                .frame(width: layout.dateW, alignment: .leading).padding(.horizontal, 4)

            HStack(spacing: 4) {
                Image(systemName: tx.type.icon).font(.caption)
                Text(tx.type.rawValue).font(.caption).fontWeight(.semibold)
            }
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(Color.forTransactionType(tx.type).opacity(0.15))
            .foregroundColor(Color.forTransactionType(tx.type))
            .cornerRadius(6)
            .frame(width: layout.typeW, alignment: .leading).padding(.horizontal, 4)

            Text(tx.ticker.isEmpty ? "—" : tx.ticker)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: layout.tickerW, alignment: .leading).padding(.horizontal, 4)

            Text(tx.quantity == 0 ? "—" : tx.quantity.formatted(.number.precision(.fractionLength(4))))
                .font(.system(size: 12))
                .frame(width: layout.qtyW, alignment: .leading).padding(.horizontal, 4)

            Text(tx.amountEUR.formatted(.currency(code: "EUR").precision(.fractionLength(2))))
                .fontWeight(.semibold)
                .foregroundColor(tx.type == .withdrawal || tx.type == .sell ? .orange : .primary)
                .font(.system(size: 13))
                .blur(radius: privacyMode ? 6 : 0)
                .frame(width: layout.amtW, alignment: .leading).padding(.horizontal, 4)

            ForEach(columns, id: \.self) { col in
                let val = tx.customFields[col] ?? 0
                Text(val == 0 ? "—" : val.formatted(.currency(code: "EUR").precision(.fractionLength(2))))
                    .font(.system(size: 12))
                    .foregroundColor(val > 0 ? .red : .secondary)
                    .blur(radius: privacyMode ? 6 : 0)
                    .frame(width: layout.customWidth, alignment: .leading).padding(.horizontal, 4)
            }

            Text(tx.note.isEmpty ? "—" : tx.note)
                .font(.system(size: 12)).foregroundColor(.secondary).lineLimit(1)
                .frame(width: layout.noteW, alignment: .leading).padding(.horizontal, 4)

            HStack(spacing: 6) {
                Button(action: onEdit) { Image(systemName: "pencil").font(.caption) }
                    .buttonStyle(.plain).foregroundColor(.secondary)
                Button(action: onDelete) { Image(systemName: "trash").font(.caption) }
                    .buttonStyle(.plain).foregroundColor(.red.opacity(0.7))
            }
            .frame(width: layout.actW)
        }
        .padding(.vertical, 10).padding(.horizontal, 8)
    }
}

// =========================================================================
// MARK: - YEARLY SUMMARY
// =========================================================================

struct TransactionsYearlySummarySection: View {
    @ObservedObject var viewModel: PortfolioViewModel
    @Binding var privacyMode: Bool

    var years: [Int] {
        Array(Set(viewModel.transactions.map { Calendar.current.component(.year, from: $0.date) })).sorted(by: >)
    }
    func txForYear(_ year: Int) -> [Transaction] {
        viewModel.transactions.filter { Calendar.current.component(.year, from: $0.date) == year }
    }

    let yearW: CGFloat      = 65
    let countW: CGFloat     = 105
    let typeW: CGFloat      = 65
    let amountW: CGFloat    = 110
    let customW: CGFloat    = 110

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Yearly Summary").font(.title2).fontWeight(.bold).foregroundColor(.secondary)
            if years.isEmpty {
                Text("No data yet.").foregroundColor(.secondary).padding()
            } else {
                VStack(spacing: 0) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        summaryHeaderRow()
                    }
                    .background(Color(NSColor.windowBackgroundColor))
                    Divider()
                    ScrollView(.horizontal, showsIndicators: false) {
                        VStack(spacing: 0) {
                            ForEach(years, id: \.self) { year in
                                YearlySummaryRowView(year: year, transactions: txForYear(year),
                                    columns: viewModel.transactionCustomColumns, privacyMode: privacyMode,
                                    yearW: yearW, countW: countW, typeW: typeW, amountW: amountW, customW: customW)
                                Divider()
                            }
                            YearlyTotalsRowView(transactions: viewModel.transactions,
                                columns: viewModel.transactionCustomColumns, privacyMode: privacyMode,
                                yearW: yearW, countW: countW, typeW: typeW, amountW: amountW, customW: customW)
                        }
                    }
                }
                .background(Color(NSColor.controlBackgroundColor)).cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))
            }
        }
        .padding().background(Color(NSColor.controlBackgroundColor)).cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }

    @ViewBuilder
    func summaryHeaderRow() -> some View {
        HStack(spacing: 0) {
            hCell("Year",          w: yearW)
            hCell("Transactions",  w: countW)
            hCell("Buys",          w: typeW)
            hCell("Sells",         w: typeW)
            hCell("Deposits",      w: typeW + 10)
            hCell("Withdrawals",   w: typeW + 10)
            hCell("Dividends",     w: typeW + 10)
            hCell("Invested €",    w: amountW)
            hCell("Sold €",        w: amountW)
            hCell("Deposited €",   w: amountW)
            hCell("Fees & Taxes",  w: amountW)
            ForEach(viewModel.transactionCustomColumns, id: \.self) { col in hCell(col, w: customW) }
        }
        .font(.subheadline).foregroundColor(.secondary)
        .padding(.vertical, 10).padding(.horizontal, 8)
    }

    @ViewBuilder func hCell(_ text: String, w: CGFloat) -> some View {
        Text(text).frame(width: w, alignment: .leading).padding(.horizontal, 4)
    }
}

struct YearlySummaryRowView: View {
    let year: Int; let transactions: [Transaction]; let columns: [String]; let privacyMode: Bool
    let yearW, countW, typeW, amountW, customW: CGFloat

    var buys:        Int    { transactions.filter { $0.type == .buy        }.count }
    var sells:       Int    { transactions.filter { $0.type == .sell       }.count }
    var deposits:    Int    { transactions.filter { $0.type == .deposit    }.count }
    var withdrawals: Int    { transactions.filter { $0.type == .withdrawal }.count }
    var dividends:   Int    { transactions.filter { $0.type == .dividend   }.count }
    var invested:    Double { transactions.filter { $0.type == .buy        }.reduce(0) { $0 + $1.amountEUR } }
    var sold:        Double { transactions.filter { $0.type == .sell       }.reduce(0) { $0 + $1.amountEUR } }
    var deposited:   Double { transactions.filter { $0.type == .deposit    }.reduce(0) { $0 + $1.amountEUR } }
    var totalFees:   Double { transactions.reduce(0) { $0 + $1.customFields.values.reduce(0, +) } }
    func colTotal(_ col: String) -> Double { transactions.reduce(0) { $0 + ($1.customFields[col] ?? 0) } }

    var body: some View {
        HStack(spacing: 0) {
            Text(String(year)).fontWeight(.bold).frame(width: yearW, alignment: .leading).padding(.horizontal, 4)
            nc(transactions.count, w: countW, color: .primary)
            nc(buys,        w: typeW,      color: .blue)
            nc(sells,       w: typeW,      color: .orange)
            nc(deposits,    w: typeW + 10, color: .green)
            nc(withdrawals, w: typeW + 10, color: .red)
            nc(dividends,   w: typeW + 10, color: .mint)
            ec(invested,  w: amountW, color: .blue)
            ec(sold,      w: amountW, color: .orange)
            ec(deposited, w: amountW, color: .green)
            ec(totalFees, w: amountW, color: .red)
            ForEach(columns, id: \.self) { col in ec(colTotal(col), w: customW, color: .red) }
        }
        .padding(.vertical, 10).padding(.horizontal, 8)
    }

    @ViewBuilder func nc(_ v: Int, w: CGFloat, color: Color) -> some View {
        Text("\(v)").foregroundColor(v == 0 ? .secondary : color).fontWeight(v == 0 ? .regular : .semibold)
            .frame(width: w, alignment: .leading).padding(.horizontal, 4)
    }
    @ViewBuilder func ec(_ v: Double, w: CGFloat, color: Color) -> some View {
        Text(v == 0 ? "—" : v.formatted(.currency(code: "EUR").precision(.fractionLength(2))))
            .foregroundColor(v == 0 ? .secondary : color).fontWeight(v == 0 ? .regular : .semibold)
            .font(.system(size: 12)).blur(radius: privacyMode ? 6 : 0)
            .frame(width: w, alignment: .leading).padding(.horizontal, 4)
    }
}

struct YearlyTotalsRowView: View {
    let transactions: [Transaction]; let columns: [String]; let privacyMode: Bool
    let yearW, countW, typeW, amountW, customW: CGFloat

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
        HStack(spacing: 0) {
            Text("TOTAL").fontWeight(.bold).italic().frame(width: yearW, alignment: .leading).padding(.horizontal, 4)
            nc(transactions.count, w: countW)
            nc(totalBuys,        w: typeW)
            nc(totalSells,       w: typeW)
            nc(totalDeposits,    w: typeW + 10)
            nc(totalWithdrawals, w: typeW + 10)
            nc(totalDividends,   w: typeW + 10)
            ec(totalInvested,    w: amountW)
            ec(totalSold,        w: amountW)
            ec(totalDeposited,   w: amountW)
            ec(totalFees,        w: amountW)
            ForEach(columns, id: \.self) { col in ec(colTotal(col), w: customW) }
        }
        .padding(.vertical, 10).padding(.horizontal, 8)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.6))
    }

    @ViewBuilder func nc(_ v: Int, w: CGFloat) -> some View {
        Text("\(v)").fontWeight(.bold).frame(width: w, alignment: .leading).padding(.horizontal, 4)
    }
    @ViewBuilder func ec(_ v: Double, w: CGFloat) -> some View {
        Text(v == 0 ? "—" : v.formatted(.currency(code: "EUR").precision(.fractionLength(2))))
            .fontWeight(.bold).font(.system(size: 12)).blur(radius: privacyMode ? 6 : 0)
            .frame(width: w, alignment: .leading).padding(.horizontal, 4)
    }
}

// =========================================================================
// MARK: - CHARTS SECTION
// =========================================================================

struct TransactionsChartsSection: View {
    @ObservedObject var viewModel: PortfolioViewModel
    @Binding var privacyMode: Bool
    @Binding var chartToZoom: TxChartZoomType?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Transaction Analytics").font(.title2).fontWeight(.bold).foregroundColor(.secondary)
            HStack(spacing: 24) {
                TxAnnualCountChart(viewModel: viewModel, expandedChart: $chartToZoom)
                TxTotalByTypeChart(viewModel: viewModel, privacyMode: $privacyMode, expandedChart: $chartToZoom)
            }
            HStack(spacing: 24) {
                TxBuysOverTimeChart(viewModel: viewModel, privacyMode: $privacyMode, expandedChart: $chartToZoom)
                TxTaxBreakdownChart(viewModel: viewModel, privacyMode: $privacyMode, expandedChart: $chartToZoom)
            }
        }
    }
}

// =========================================================================
// MARK: - CHART 1 : Total Transactions per Year (stacked bars)
// =========================================================================

struct TxAnnualCountChart: View {
    @ObservedObject var viewModel: PortfolioViewModel
    var isExpanded: Bool = false
    @Binding var expandedChart: TxChartZoomType?

    struct AnnualCountItem: Identifiable {
        let id = UUID()
        let year: String
        let type: TransactionType
        let count: Int
    }

    var years: [Int] {
        guard !viewModel.transactions.isEmpty else { return [] }
        let all = viewModel.transactions.map { Calendar.current.component(.year, from: $0.date) }
        let minY = all.min() ?? 2022
        let maxY = all.max() ?? Calendar.current.component(.year, from: Date())
        return Array(minY...maxY)
    }

    var data: [AnnualCountItem] {
        let stackedTypes: [TransactionType] = [.buy, .sell, .deposit, .withdrawal]
        var items: [AnnualCountItem] = []
        for year in years {
            let txYear = viewModel.transactions.filter { Calendar.current.component(.year, from: $0.date) == year }
            for type in stackedTypes {
                let count = txYear.filter { $0.type == type }.count
                items.append(AnnualCountItem(year: String(year), type: type, count: count))
            }
        }
        return items
    }

    @State private var hiddenTypes: Set<String> = []
    @State private var hoveredYear: String? = nil

    var seriesLabels: [String] { [TransactionType.buy, .sell, .deposit, .withdrawal].map { $0.rawValue } }
    func color(for label: String) -> Color {
        guard let type = TransactionType(rawValue: label) else { return .gray }
        return Color.forTransactionType(type)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if !isExpanded { Text("Transactions per Year").font(.headline).foregroundColor(.secondary) }
                Spacer()
                if !isExpanded { Button(action: { expandedChart = .annualCount }) { Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary) }.buttonStyle(.plain) }
            }
            InteractiveLegendView(items: seriesLabels, colorMap: color, hiddenItems: $hiddenTypes)
            
            if data.isEmpty {
                emptyState("No transactions yet.")
            } else {
                Chart {
                    ForEach(data.filter { !hiddenTypes.contains($0.type.rawValue) }) { item in
                        BarMark(
                            x: .value("Year", item.year),
                            y: .value("Count", item.count)
                        )
                        .foregroundStyle(Color.forTransactionType(item.type).opacity(0.8))
                        .position(by: .value("Type", item.type.rawValue))
                        .cornerRadius(3)
                        
                        // Infobulle Interactive
                        if let h = hoveredYear, h == item.year {
                            RuleMark(x: .value("Year", h))
                                .foregroundStyle(.secondary.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                                .annotation(position: .top) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(h).font(.caption.bold())
                                        Divider()
                                        ForEach(seriesLabels.filter { !hiddenTypes.contains($0) }, id: \.self) { label in
                                            let c = data.first { $0.year == h && $0.type.rawValue == label }?.count ?? 0
                                            HStack {
                                                Circle().fill(color(for: label)).frame(width: 6, height: 6)
                                                Text("\(label): \(c)").font(.caption2)
                                            }
                                        }
                                    }.padding(8).background(Color(NSColor.windowBackgroundColor).opacity(0.95)).cornerRadius(8).shadow(radius: 4)
                                }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { v in
                        AxisGridLine(); AxisTick()
                        AxisValueLabel { if let i = v.as(Int.self) { Text("\(i)").font(.system(size: 10)) } }
                    }
                }
                .chartXAxis {
                    AxisMarks { v in AxisValueLabel { if let s = v.as(String.self) { Text(s).font(.caption) } } }
                }
                .chartXSelection(value: $hoveredYear)
            }
            BlueChipWatermark()
        }
        .padding().frame(minHeight: isExpanded ? 500 : 360, maxHeight: isExpanded ? .infinity : 360).background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// =========================================================================
// MARK: - CHART 2 : Total by Transaction Type (bars + count line)
// =========================================================================

struct TxTotalByTypeChart: View {
    @ObservedObject var viewModel: PortfolioViewModel
    @Binding var privacyMode: Bool
    var isExpanded: Bool = false
    @Binding var expandedChart: TxChartZoomType?

    let displayedTypes: [TransactionType] = [.buy, .sell, .deposit, .withdrawal, .dividend]

    struct TypeSummary: Identifiable {
        let id = UUID()
        let type: TransactionType
        let amount: Double
        let count: Int
    }

    var data: [TypeSummary] {
        displayedTypes.map { t in
            let filtered = viewModel.transactions.filter { $0.type == t }
            return TypeSummary(type: t, amount: filtered.reduce(0) { $0 + $1.amountEUR }, count: filtered.count)
        }.filter { $0.count > 0 }
    }

    var maxAmount: Double { data.map { $0.amount }.max() ?? 1 }
    var maxCount:  Int    { data.map { $0.count  }.max() ?? 1 }
    func scaledCount(_ count: Int) -> Double { maxAmount > 0 ? (Double(count) / Double(maxCount)) * maxAmount : 0 }

    @State private var hiddenSeries: Set<String> = []
    @State private var hoveredType: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if !isExpanded { Text("Summary by Type").font(.headline).foregroundColor(.secondary) }
                Spacer()
                HStack(spacing: 12) {
                    Button(action: { withAnimation { toggleHidden("Amount") } }) {
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 2).fill(Color.blue.opacity(0.6)).frame(width: 12, height: 12)
                            Text("Amount €").font(.caption).foregroundColor(hiddenSeries.contains("Amount") ? .secondary : .primary)
                        }
                    }.buttonStyle(.plain).opacity(hiddenSeries.contains("Amount") ? 0.4 : 1)

                    Button(action: { withAnimation { toggleHidden("Count") } }) {
                        HStack(spacing: 4) {
                            Circle().fill(Color.purple).frame(width: 8, height: 8)
                            Text("Count").font(.caption).foregroundColor(hiddenSeries.contains("Count") ? .secondary : .primary)
                        }
                    }.buttonStyle(.plain).opacity(hiddenSeries.contains("Count") ? 0.4 : 1)
                }
                if !isExpanded { Button(action: { expandedChart = .typeSummary }) { Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary) }.buttonStyle(.plain) }
            }.padding(.bottom, 4)

            if data.isEmpty {
                emptyState("No transactions yet.")
            } else {
                Chart {
                    if !hiddenSeries.contains("Amount") {
                        ForEach(data) { item in
                            BarMark(
                                x: .value("Type", item.type.rawValue),
                                y: .value("Amount €", item.amount)
                            )
                            .foregroundStyle(Color.forTransactionType(item.type).opacity(0.75))
                            .cornerRadius(4)
                            
                            if let h = hoveredType, h == item.type.rawValue {
                                RuleMark(x: .value("Type", h))
                                    .foregroundStyle(.secondary.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                                    .annotation(position: .top) {
                                        VStack(alignment: .leading) {
                                            Text(h).font(.caption.bold())
                                            Divider()
                                            Text("Amount: \(item.amount.formatted(.currency(code: "EUR").precision(.fractionLength(0))))").font(.caption2).foregroundColor(Color.forTransactionType(item.type))
                                            Text("Count: \(item.count)").font(.caption2).foregroundColor(.purple)
                                        }.padding(8).background(Color(NSColor.windowBackgroundColor).opacity(0.95)).cornerRadius(8).shadow(radius: 4)
                                    }
                            }
                        }
                    }
                    if !hiddenSeries.contains("Count") {
                        ForEach(data) { item in
                            LineMark(
                                x: .value("Type", item.type.rawValue),
                                y: .value("Scaled Count", scaledCount(item.count))
                            )
                            .foregroundStyle(Color.purple)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                            .symbol { Circle().fill(Color.purple).frame(width: 7, height: 7) }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { v in
                        AxisGridLine(); AxisTick()
                        AxisValueLabel {
                            if let d = v.as(Double.self) {
                                Text(d.formatted(.currency(code: "EUR").precision(.fractionLength(0)))).font(.system(size: 10))
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks { v in AxisValueLabel { if let s = v.as(String.self) { Text(s).font(.caption) } } }
                }
                .chartXSelection(value: $hoveredType)
            }
            BlueChipWatermark()
        }
        .padding().frame(minHeight: isExpanded ? 500 : 360, maxHeight: isExpanded ? .infinity : 360).background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }

    func toggleHidden(_ key: String) {
        if hiddenSeries.contains(key) { hiddenSeries.remove(key) } else { hiddenSeries.insert(key) }
    }
}

// =========================================================================
// MARK: - CHART 3 : Buys over time (bars par transaction)
// =========================================================================

struct TxBuysOverTimeChart: View {
    @ObservedObject var viewModel: PortfolioViewModel
    @Binding var privacyMode: Bool
    var isExpanded: Bool = false
    @Binding var expandedChart: TxChartZoomType?

    struct BuyPoint: Identifiable {
        let id = UUID()
        let date: Date
        let amount: Double
        let ticker: String
    }

    let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "dd/MM/yy"; return f
    }()

    var buys: [BuyPoint] {
        viewModel.transactions
            .filter { $0.type == .buy }
            .sorted { $0.date < $1.date }
            .map { BuyPoint(date: $0.date, amount: $0.amountEUR, ticker: $0.ticker) }
    }

    var trendPoints: [(date: Date, value: Double)] {
        guard buys.count >= 2 else { return [] }
        let xs = buys.map { $0.date.timeIntervalSince1970 }
        let ys = buys.map { $0.amount }
        let n = Double(xs.count)
        let sumX = xs.reduce(0, +); let sumY = ys.reduce(0, +)
        let sumXY = zip(xs, ys).reduce(0) { $0 + $1.0 * $1.1 }
        let sumX2 = xs.reduce(0) { $0 + $1 * $1 }
        let denom = n * sumX2 - sumX * sumX
        guard denom != 0 else { return [] }
        let slope = (n * sumXY - sumX * sumY) / denom
        let intercept = (sumY - slope * sumX) / n
        return [buys.first!, buys.last!].map { pt in
            let y = slope * pt.date.timeIntervalSince1970 + intercept
            return (date: pt.date, value: max(0, y))
        }
    }

    @State private var hoveredDate: Date? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if !isExpanded { Text("Buys over Time").font(.headline).foregroundColor(.secondary) }
                Spacer()
                if !isExpanded { Button(action: { expandedChart = .buysOverTime }) { Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary) }.buttonStyle(.plain) }
            }.padding(.bottom, 4)
            
            if buys.isEmpty {
                emptyState("No buy transactions yet.")
            } else {
                Chart {
                    ForEach(buys) { buy in
                        BarMark(
                            x: .value("Date", buy.date, unit: .day),
                            y: .value("Amount €", buy.amount)
                        )
                        .foregroundStyle(Color.blue.opacity(0.7))
                        .cornerRadius(2)
                    }
                    ForEach(trendPoints.indices, id: \.self) { i in
                        LineMark(
                            x: .value("Date", trendPoints[i].date, unit: .day),
                            y: .value("Trend", trendPoints[i].value),
                            series: .value("Series", "trend")
                        )
                        .foregroundStyle(Color.gray.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                        .interpolationMethod(.linear)
                    }
                    
                    if let d = hoveredDate, let buy = buys.min(by: { abs($0.date.timeIntervalSince(d)) < abs($1.date.timeIntervalSince(d)) }) {
                        RuleMark(x: .value("Date", buy.date, unit: .day))
                            .foregroundStyle(.secondary.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                            .annotation(position: .top) {
                                VStack(alignment: .leading) {
                                    Text(dateFmt.string(from: buy.date)).font(.caption.bold())
                                    Divider()
                                    Text("\(buy.ticker)").font(.caption2.bold()).foregroundColor(.blue)
                                    Text("\(buy.amount.formatted(.currency(code: "EUR").precision(.fractionLength(0))))").font(.caption2)
                                }.padding(8).background(Color(NSColor.windowBackgroundColor).opacity(0.95)).cornerRadius(8).shadow(radius: 4)
                            }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { v in
                        AxisGridLine(); AxisTick()
                        AxisValueLabel { if let d = v.as(Double.self) { Text(d.formatted(.currency(code: "EUR").precision(.fractionLength(0)))).font(.system(size: 10)) } }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 6)) { v in
                        AxisValueLabel { if let d = v.as(Date.self) { Text(dateFmt.string(from: d)).font(.system(size: 9)) } }
                    }
                }
                .chartXSelection(value: $hoveredDate)
            }
            BlueChipWatermark()
        }
        .padding().frame(minHeight: isExpanded ? 500 : 360, maxHeight: isExpanded ? .infinity : 360).background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// =========================================================================
// MARK: - CHART 4 : Tax breakdown donut
// =========================================================================

struct TxTaxBreakdownChart: View {
    @ObservedObject var viewModel: PortfolioViewModel
    @Binding var privacyMode: Bool
    var isExpanded: Bool = false
    @Binding var expandedChart: TxChartZoomType?

    struct TaxSlice: Identifiable {
        let id = UUID()
        let name: String
        let amount: Double
        let color: Color
    }

    var slices: [TaxSlice] {
        let cols = viewModel.transactionCustomColumns
        guard !cols.isEmpty else { return [] }
        let colors: [Color] = [.blue, .red, .orange, .green, .purple, .teal, .pink]
        return cols.enumerated().compactMap { (idx, col) in
            let total = viewModel.transactions.reduce(0) { $0 + ($1.customFields[col] ?? 0) }
            guard total > 0 else { return nil }
            return TaxSlice(name: col, amount: total, color: colors[idx % colors.count])
        }
    }

    var grandTotal: Double { slices.reduce(0) { $0 + $1.amount } }
    @State private var selectedAngleValue: Double? = nil

    func getSelectedSlice(for angle: Double) -> TaxSlice? {
        var cum = 0.0
        for slice in slices {
            cum += slice.amount
            if angle <= cum { return slice }
        }
        return slices.last
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if !isExpanded { Text("Fees & Taxes Breakdown").font(.headline).foregroundColor(.secondary) }
                Spacer()
                if !isExpanded { Button(action: { expandedChart = .taxBreakdown }) { Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary) }.buttonStyle(.plain) }
            }
            if slices.isEmpty {
                emptyState("No fees/taxes recorded yet.")
            } else {
                HStack(spacing: 24) {
                    // Donut
                    Chart(slices) { slice in
                        SectorMark(
                            angle: .value("Amount", slice.amount),
                            innerRadius: .ratio(0.55),
                            angularInset: 2
                        )
                        .foregroundStyle(slice.color)
                        .cornerRadius(4)
                    }
                    .frame(width: isExpanded ? 300 : 180, height: isExpanded ? 300 : 180)
                    .chartAngleSelection(value: $selectedAngleValue)
                    .chartBackground { proxy in
                        GeometryReader { geometry in
                            if let s = selectedAngleValue, let slice = getSelectedSlice(for: s) {
                                VStack(spacing: 2) {
                                    Text(slice.name).font(.caption).foregroundColor(.secondary)
                                    Text(slice.amount.formatted(.currency(code: "EUR").precision(.fractionLength(2))))
                                        .font(.system(size: 13, weight: .bold))
                                        .blur(radius: privacyMode ? 4 : 0)
                                }.position(x: geometry.frame(in: .local).midX, y: geometry.frame(in: .local).midY)
                            } else {
                                VStack(spacing: 2) {
                                    Text("Total").font(.caption).foregroundColor(.secondary)
                                    Text(grandTotal.formatted(.currency(code: "EUR").precision(.fractionLength(2))))
                                        .font(.system(size: 13, weight: .bold))
                                        .blur(radius: privacyMode ? 4 : 0)
                                }.position(x: geometry.frame(in: .local).midX, y: geometry.frame(in: .local).midY)
                            }
                        }
                    }

                    // Legend + values
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(slices) { slice in
                            HStack(spacing: 8) {
                                Circle().fill(slice.color).frame(width: 10, height: 10)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(slice.name).font(.caption).fontWeight(.semibold)
                                    HStack(spacing: 6) {
                                        Text(slice.amount.formatted(.currency(code: "EUR").precision(.fractionLength(2))))
                                            .font(.caption).foregroundColor(.secondary)
                                            .blur(radius: privacyMode ? 4 : 0)
                                        if grandTotal > 0 {
                                            Text(String(format: "%.1f%%", slice.amount / grandTotal * 100))
                                                .font(.caption2).foregroundColor(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Spacer()
                }
            }
            Spacer()
            BlueChipWatermark()
        }
        .padding().frame(minHeight: isExpanded ? 500 : 360, maxHeight: isExpanded ? .infinity : 360).background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// =========================================================================
// MARK: - FULL SCREEN ZOOM VIEW
// =========================================================================

struct TransactionsFullScreenChartView: View {
    @Environment(\.dismiss) var dismiss
    let zoomType: TxChartZoomType
    @ObservedObject var viewModel: PortfolioViewModel
    @Binding var privacyMode: Bool

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Analysis Detail").font(.title).fontWeight(.bold)
                Spacer()
                Button(action: { dismiss() }) { Image(systemName: "xmark.circle.fill").font(.title).foregroundColor(.secondary) }.buttonStyle(.plain)
            }
            
            switch zoomType {
            case .annualCount:
                TxAnnualCountChart(viewModel: viewModel, isExpanded: true, expandedChart: .constant(nil))
            case .typeSummary:
                TxTotalByTypeChart(viewModel: viewModel, privacyMode: $privacyMode, isExpanded: true, expandedChart: .constant(nil))
            case .buysOverTime:
                TxBuysOverTimeChart(viewModel: viewModel, privacyMode: $privacyMode, isExpanded: true, expandedChart: .constant(nil))
            case .taxBreakdown:
                TxTaxBreakdownChart(viewModel: viewModel, privacyMode: $privacyMode, isExpanded: true, expandedChart: .constant(nil))
            }
            
        }.padding(30).frame(minWidth: 900, minHeight: 700)
    }
}

// =========================================================================
// MARK: - SHARED HELPERS
// =========================================================================

@ViewBuilder
func emptyState(_ text: String) -> some View {
    Spacer()
    Text(text).foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .center)
    Spacer()
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
            HStack {
                Text(isEditing ? "Edit Transaction" : "New Transaction").font(.title2).fontWeight(.bold)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill").font(.title2).foregroundColor(.secondary)
                }.buttonStyle(.plain)
            }.padding()
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    GroupBox("Date & Time") {
                        DatePicker("", selection: $date, displayedComponents: [.date, .hourAndMinute]).labelsHidden()
                    }
                    GroupBox("Transaction Type") {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                            ForEach(TransactionType.allCases, id: \.self) { t in
                                Button(action: { type = t }) {
                                    HStack(spacing: 6) { Image(systemName: t.icon); Text(t.rawValue) }
                                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                                        .background(type == t ? Color.forTransactionType(t).opacity(0.2) : Color(NSColor.windowBackgroundColor))
                                        .foregroundColor(type == t ? Color.forTransactionType(t) : .secondary)
                                        .cornerRadius(8).fontWeight(type == t ? .semibold : .regular)
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                    if type == .buy || type == .sell {
                        GroupBox("Asset") {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Ticker").font(.caption).foregroundColor(.secondary)
                                    TextField("e.g. AAPL", text: $ticker).textFieldStyle(.roundedBorder)
                                        .onChange(of: ticker) { ticker = ticker.uppercased() }
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Quantity").font(.caption).foregroundColor(.secondary)
                                    TextField("0.00", text: $quantity).textFieldStyle(.roundedBorder)
                                }
                            }
                        }
                    }
                    GroupBox("Amount (€)") {
                        TextField("0.00", text: $amountEUR).textFieldStyle(.roundedBorder)
                    }
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
                    GroupBox("Note (optional)") {
                        TextField("Add a note…", text: $note).textFieldStyle(.roundedBorder)
                    }
                }.padding()
            }

            Divider()
            HStack {
                if isEditing {
                    Button(role: .destructive) {
                        viewModel.transactions.removeAll { $0.id == transaction!.id }; dismiss()
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
        date = tx.date; type = tx.type; ticker = tx.ticker
        quantity  = tx.quantity  == 0 ? "" : String(tx.quantity)
        amountEUR = tx.amountEUR == 0 ? "" : String(tx.amountEUR)
        note = tx.note
        for (k, v) in tx.customFields { customValues[k] = String(v) }
    }

    func save() {
        let qty = Double(quantity.replacingOccurrences(of: ",", with: "."))  ?? 0
        let amt = Double(amountEUR.replacingOccurrences(of: ",", with: ".")) ?? 0
        var fields: [String: Double] = [:]
        for col in viewModel.transactionCustomColumns {
            if let raw = customValues[col], let val = Double(raw.replacingOccurrences(of: ",", with: ".")) { fields[col] = val }
        }
        if isEditing, let idx = viewModel.transactions.firstIndex(where: { $0.id == transaction!.id }) {
            viewModel.transactions[idx].date = date; viewModel.transactions[idx].type = type
            viewModel.transactions[idx].ticker = ticker; viewModel.transactions[idx].quantity = qty
            viewModel.transactions[idx].amountEUR = amt; viewModel.transactions[idx].note = note
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

    init(viewModel: PortfolioViewModel) { self.viewModel = viewModel; _input = State(initialValue: viewModel.transactionGoalTarget) }

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
                if !viewModel.transactionCustomColumns.isEmpty {
                    Text("Current columns").font(.subheadline).foregroundColor(.secondary)
                    ForEach(viewModel.transactionCustomColumns, id: \.self) { col in
                        HStack {
                            Text(col)
                            Spacer()
                            Button(action: { viewModel.transactionCustomColumns.removeAll { $0 == col } }) {
                                Image(systemName: "trash").foregroundColor(.red.opacity(0.7))
                            }.buttonStyle(.plain)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Color(NSColor.windowBackgroundColor)).cornerRadius(8)
                    }
                    Divider()
                }
                Text("Add a column").font(.subheadline).foregroundColor(.secondary)
                HStack {
                    TextField("Column name (e.g. TOB, Fees…)", text: $columnName).textFieldStyle(.roundedBorder)
                    Button("Add") {
                        let name = columnName.trimmingCharacters(in: .whitespaces)
                        guard !name.isEmpty, !viewModel.transactionCustomColumns.contains(name) else { return }
                        viewModel.transactionCustomColumns.append(name)
                        columnName = ""
                    }.buttonStyle(.borderedProminent).disabled(columnName.trimmingCharacters(in: .whitespaces).isEmpty)
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
