import SwiftUI
import Charts
import SwiftData
import Combine

// =========================================================================
// MARK: - ENUMS & HELPERS
// =========================================================================

// Modèles locaux pour lire la réponse de Yahoo Finance
private struct YahooSearchResponse: Codable {
    let quotes: [YahooQuote]
}

private struct YahooQuote: Codable, Hashable {
    let symbol: String
    let shortname: String?
    let exchDisp: String?
}

enum TxChartZoomType: String, Identifiable {
    case annualCount, typeSummary, buysOverTime, taxBreakdown
    case capitalAllocation, holdingPeriod
    case tradeBalance, cumulativeCapital, taxDrag, activityHeatmap
    var id: String { self.rawValue }
}

enum TxTimeFilter: String, CaseIterable, Identifiable {
    case all = "All Time"
    case thisMonth = "This Month"
    case thisQuarter = "This Quarter"
    case ytd = "Year to Date"
    case oneYear = "Last 12 Months"
    case custom = "Custom Range"
    var id: String { self.rawValue }
}

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
    
    @State private var chartToZoom: TxChartZoomType? = nil
    
    @State private var timeFilter: TxTimeFilter = .all
        
    @State private var customStartDate: Date = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var customEndDate: Date = Date()

    var filteredGlobalTransactions: [Transaction] {
        let now = Date()
        let cal = Calendar.current
        
        switch timeFilter {
        case .all:
            return viewModel.transactions
        case .thisMonth:
            guard let start = cal.date(from: cal.dateComponents([.year, .month], from: now)) else { return viewModel.transactions }
            return viewModel.transactions.filter { $0.date >= start }
        case .thisQuarter:
            let month = cal.component(.month, from: now)
            let quarterMonth = ((month - 1) / 3) * 3 + 1
            var comps = cal.dateComponents([.year], from: now)
            comps.month = quarterMonth
            guard let start = cal.date(from: comps) else { return viewModel.transactions }
            return viewModel.transactions.filter { $0.date >= start }
        case .ytd:
            guard let start = cal.date(from: cal.dateComponents([.year], from: now)) else { return viewModel.transactions }
            return viewModel.transactions.filter { $0.date >= start }
        case .oneYear:
            guard let start = cal.date(byAdding: .year, value: -1, to: now) else { return viewModel.transactions }
            return viewModel.transactions.filter { $0.date >= start }
        case .custom:
            let endOfDay = cal.date(bySettingHour: 23, minute: 59, second: 59, of: customEndDate) ?? customEndDate
            return viewModel.transactions.filter { $0.date >= customStartDate && $0.date <= endOfDay }
        }
    }

    var currentGoalValueForProgressBar: Double {
        switch viewModel.transactionGoalType {
        case .count:
            return Double(viewModel.transactions.count)
        case .totalInvested:
            return viewModel.transactions.filter { $0.type == .buy }.reduce(0) { $0 + $1.amountEUR }
        case .totalSold:
            return viewModel.transactions.filter { $0.type == .sell }.reduce(0) { $0 + $1.amountEUR }
        case .totalFees:
            return viewModel.transactions.reduce(0) { $0 + $1.customFields.values.reduce(0, +) }
        }
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 24) {
                TransactionsDashboardSection(viewModel: viewModel, tx: filteredGlobalTransactions, privacyMode: $privacyMode)

                let goalSym = AppCurrency(rawValue: viewModel.preferredCurrency)?.symbol ?? "€"
                GoalProgressBar(
                    title: viewModel.transactionGoalType.rawValue.replacingOccurrences(of: "€", with: goalSym),
                    currentValue: currentGoalValueForProgressBar,
                    targetValue: viewModel.transactionGoalTarget,
                    privacyMode: $privacyMode,
                    currency: $viewModel.preferredCurrency,
                    isPercentage: false,
                    isCount: viewModel.transactionGoalType == .count
                )
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { showGoalSheet = true }

                TransactionsTableSection(
                    viewModel: viewModel,
                    globalTransactions: filteredGlobalTransactions,
                    privacyMode: $privacyMode,
                    searchText: $searchText,
                    filterType: $filterType,
                    timeFilter: $timeFilter,
                    customStartDate: $customStartDate,
                    customEndDate: $customEndDate,
                    editingTransaction: $editingTransaction,
                    showAddSheet: $showAddSheet,
                    showAddColumnSheet: $showAddColumnSheet
                )

                TransactionsYearlySummarySection(viewModel: viewModel, tx: filteredGlobalTransactions, privacyMode: $privacyMode)

                TransactionsChartsSection(viewModel: viewModel, tx: filteredGlobalTransactions, privacyMode: $privacyMode, chartToZoom: $chartToZoom)
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
        .sheet(item: $chartToZoom) { type in
            TransactionsFullScreenChartView(zoomType: type, viewModel: viewModel, tx: filteredGlobalTransactions, privacyMode: $privacyMode)
        }
    }
}

// =========================================================================
// MARK: - DASHBOARD
// =========================================================================

struct TransactionsDashboardSection: View {
    @ObservedObject var viewModel: PortfolioViewModel
    let tx: [Transaction]
    @Binding var privacyMode: Bool

    var totalDeposited:   Double { tx.filter { $0.type == .deposit    }.reduce(0) { $0 + $1.amountEUR } }
    var totalWithdrawn:   Double { tx.filter { $0.type == .withdrawal }.reduce(0) { $0 + $1.amountEUR } }
    var totalBought:      Double { tx.filter { $0.type == .buy        }.reduce(0) { $0 + $1.amountEUR } }
    var totalSold:        Double { tx.filter { $0.type == .sell       }.reduce(0) { $0 + $1.amountEUR } }
    var totalCustomFees:  Double { tx.reduce(0) { $0 + $1.customFields.values.reduce(0, +) } }
    
    var netCashFlow:      Double { totalDeposited - totalWithdrawn }
    var netInvested:      Double { totalBought - totalSold }

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                txCard("Total Deposited",    value: totalDeposited)
                txCard("Total Withdrawn",    value: totalWithdrawn)
                txCard("Net Cash Flow",      value: netCashFlow)
                txCard("Total Invested",     value: totalBought)
            }
            HStack(spacing: 16) {
                txCard("Total Sold",         value: totalSold)
                txCard("Net Invested",       value: netInvested)
                txCard("Total Fees & Taxes", value: totalCustomFees)
                DashboardCard(title: "Transactions Found", value: "\(tx.count)", titleIcon: nil, privacyMode: $privacyMode)
            }
        }
    }

    @ViewBuilder
    func txCard(_ title: String, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline).foregroundColor(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            Text(value.formatted(.currency(code: viewModel.preferredCurrency).precision(.fractionLength(2))))
                .font(.title2).fontWeight(.bold).foregroundColor(.primary)
                .blur(radius: privacyMode ? 6 : 0)
        }
        .padding().frame(maxWidth: .infinity, alignment: .leading).frame(height: 110)
        .background(Color(NSColor.controlBackgroundColor)).cornerRadius(10)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}



// =========================================================================
// MARK: - TABLE SECTION
// =========================================================================

struct TransactionsTableSection: View {
    @ObservedObject var viewModel: PortfolioViewModel
    let globalTransactions: [Transaction]
    @Binding var privacyMode: Bool
    @Binding var searchText: String
    @Binding var filterType: TransactionType?
    @Binding var timeFilter: TxTimeFilter
    @Binding var customStartDate: Date
    @Binding var customEndDate: Date
    @Binding var editingTransaction: Transaction?
    @Binding var showAddSheet: Bool
    @Binding var showAddColumnSheet: Bool

    let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .short; return f
    }()

    var filtered: [Transaction] {
        var list = globalTransactions.sorted { $0.date > $1.date }
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
                
                Picker("", selection: $timeFilter) {
                    ForEach(TxTimeFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .labelsHidden()
                .frame(width: 140)
                .padding(4)
                .background(Color(NSColor.windowBackgroundColor))
                .cornerRadius(8)
                
                if timeFilter == .custom {
                    HStack(spacing: 4) {
                        DatePicker("", selection: $customStartDate, displayedComponents: .date)
                            .labelsHidden()
                            .frame(width: 100)
                        
                        Text("-").foregroundColor(.secondary)
                        
                        DatePicker("", selection: $customEndDate, displayedComponents: .date)
                            .labelsHidden()
                            .frame(width: 100)
                    }
                    .padding(4)
                    .background(Color(NSColor.windowBackgroundColor))
                    .cornerRadius(8)
                }
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        filterChip(nil, label: "All")
                        ForEach(TransactionType.allCases.filter { $0 != .dividend }, id: \.self) { type in
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
                ScrollView(.horizontal, showsIndicators: true) {
                    VStack(spacing: 0) {
                        txHeaderRow().background(Color(NSColor.windowBackgroundColor).opacity(0.6))
                        Divider()
                        
                        if filtered.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "clock.arrow.circlepath").font(.system(size: 36)).foregroundColor(.secondary)
                                Text(searchText.isEmpty ? "No transactions found in this period." : "No results for \"\(searchText)\".")
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity).padding(40)
                        } else {
                            ScrollView(.vertical) {
                                LazyVStack(spacing: 0) {
                                    ForEach(Array(filtered.enumerated()), id: \.element.id) { index, tx in
                                        TransactionRowView(
                                            viewModel: viewModel,
                                            tx: tx,
                                            columns: columns,
                                            privacyMode: privacyMode,
                                            dateFormatter: dateFormatter,
                                            isEvenRow: index % 2 == 0,
                                            onEdit: { editingTransaction = tx },
                                            onDelete: { viewModel.deleteTransaction(id: tx.id) }
                                        )
                                        Divider().opacity(0.5)
                                    }
                                }
                            }
                        }
                    }
                    .frame(minWidth: geo.size.width)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))
                }
            }
            .frame(height: 420)
        }
        .padding().background(Color(NSColor.controlBackgroundColor)).cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }

    @ViewBuilder
    func txHeaderRow() -> some View {
        let sym = AppCurrency(rawValue: viewModel.preferredCurrency)?.symbol ?? "€"
        HStack(spacing: 12) {
            Text("Date").frame(width: 120, alignment: .leading)
            Text("Type").frame(width: 100, alignment: .center)
            Text("Ticker").frame(width: 80, alignment: .center)
            Text("Qty").frame(maxWidth: .infinity, alignment: .center)
            Text("Amount \(sym)").frame(maxWidth: .infinity, alignment: .center)
            ForEach(columns, id: \.self) { col in
                Text(col).frame(maxWidth: .infinity, alignment: .center)
            }
            Text("Note").frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.caption).foregroundColor(.secondary)
        .padding(.vertical, 12).padding(.horizontal, 16)
    }

    @ViewBuilder
    func filterChip(_ type: TransactionType?, label: String) -> some View {
        let active = filterType == type
        Button(action: { filterType = type }) {
            Text(label).font(.caption).fontWeight(active ? .bold : .regular)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(active ? Color.blue.opacity(0.15) : Color.clear)
                .foregroundColor(active ? .blue : .secondary)
                .cornerRadius(12)
        }.buttonStyle(.plain)
    }
}

struct TransactionRowView: View {
    @ObservedObject var viewModel: PortfolioViewModel
    let tx: Transaction
    let columns: [String]
    let privacyMode: Bool
    let dateFormatter: DateFormatter
    let isEvenRow: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(dateFormatter.string(from: tx.date))
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .frame(width: 120, alignment: .leading)

            HStack(spacing: 4) {
                Image(systemName: tx.type.icon).font(.caption2)
                Text(tx.type.rawValue).font(.caption).fontWeight(.bold)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color.forTransactionType(tx.type).opacity(0.15))
            .foregroundColor(Color.forTransactionType(tx.type))
            .cornerRadius(8)
            .frame(width: 100, alignment: .center)

            Text(tx.ticker.isEmpty ? "—" : tx.ticker)
                .font(.system(size: 13, weight: .bold))
                .frame(width: 80, alignment: .center)

            Text(tx.quantity == 0 ? "—" : tx.quantity.formatted(.number.precision(.fractionLength(4))))
                .font(.system(size: 13))
                .blur(radius: privacyMode ? 6 : 0)
                .frame(maxWidth: .infinity, alignment: .center)

            Text(tx.amountEUR.formatted(.currency(code: viewModel.preferredCurrency).precision(.fractionLength(2))))
                .fontWeight(.bold)
                .foregroundColor(.primary)
                .font(.system(size: 13))
                .blur(radius: privacyMode ? 6 : 0)
                .frame(maxWidth: .infinity, alignment: .center)

            ForEach(columns, id: \.self) { col in
                let val = tx.customFields[col] ?? 0
                Text(val == 0 ? "—" : val.formatted(.currency(code: viewModel.preferredCurrency).precision(.fractionLength(2))))
                    .font(.system(size: 13))
                    .foregroundColor(val > 0 ? .red.opacity(0.8) : .secondary)
                    .blur(radius: privacyMode ? 6 : 0)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            Text(tx.note.isEmpty ? "—" : tx.note)
                .font(.system(size: 13)).foregroundColor(.secondary).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 14).padding(.horizontal, 16)
        .background(isEvenRow ? Color.gray.opacity(0.03) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onEdit() }
        .contextMenu {
            Button("Edit Transaction") { onEdit() }
            Button(role: .destructive) { onDelete() } label: { Label("Delete Transaction", systemImage: "trash") }
        }
    }
}

// =========================================================================
// MARK: - YEARLY SUMMARY (RESPONSIVE)
// =========================================================================

struct TransactionsYearlySummarySection: View {
    @ObservedObject var viewModel: PortfolioViewModel
    let tx: [Transaction]
    @Binding var privacyMode: Bool

    var years: [Int] {
        let currentYear = Calendar.current.component(.year, from: Date())
        let startYear = viewModel.dividendStartYear
        guard currentYear >= startYear else { return [] }
        return Array(startYear...currentYear).reversed()
    }
    
    func txForYear(_ year: Int) -> [Transaction] {
        tx.filter { Calendar.current.component(.year, from: $0.date) == year }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Yearly Summary").font(.title2).fontWeight(.bold).foregroundColor(.secondary).padding(.bottom, 4)
            if years.isEmpty {
                Text("No data for this period.").foregroundColor(.secondary).padding()
            } else {
                GeometryReader { geo in
                    ScrollView(.horizontal, showsIndicators: true) {
                        VStack(spacing: 0) {
                            summaryHeaderRow()
                                .background(Color(NSColor.windowBackgroundColor))
                            Divider()
                            
                            VStack(spacing: 0) {
                                ForEach(years, id: \.self) { year in
                                    YearlySummaryRowView(viewModel: viewModel, year: year, transactions: txForYear(year), columns: viewModel.transactionCustomColumns, privacyMode: privacyMode)
                                    Divider()
                                }
                                YearlyTotalsRowView(viewModel: viewModel, transactions: tx, columns: viewModel.transactionCustomColumns, privacyMode: privacyMode)
                            }
                        }
                        .frame(minWidth: geo.size.width)
                    }
                }
                .frame(height: CGFloat(years.count + 2) * 36 + 18)
                .background(Color(NSColor.controlBackgroundColor)).cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))
            }
        }
        .padding().background(Color(NSColor.controlBackgroundColor)).cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }

    @ViewBuilder
    func summaryHeaderRow() -> some View {
        let sym = AppCurrency(rawValue: viewModel.preferredCurrency)?.symbol ?? "€"
        HStack(spacing: 12) {
            Text("Year").frame(width: 50, alignment: .leading)
            Text("Count").frame(maxWidth: .infinity, alignment: .trailing)
            Text("Buys").frame(maxWidth: .infinity, alignment: .trailing)
            Text("Sells").frame(maxWidth: .infinity, alignment: .trailing)
            Text("Deposits").frame(maxWidth: .infinity, alignment: .trailing)
            Text("Withdrawals").frame(maxWidth: .infinity, alignment: .trailing)
            Text("Invested \(sym)").frame(maxWidth: .infinity, alignment: .trailing)
            Text("Sold \(sym)").frame(maxWidth: .infinity, alignment: .trailing)
            Text("Deposited \(sym)").frame(maxWidth: .infinity, alignment: .trailing)
            Text("Fees & Taxes").frame(maxWidth: .infinity, alignment: .trailing)
            ForEach(viewModel.transactionCustomColumns, id: \.self) { col in
                Text(col).frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .font(.subheadline).foregroundColor(.secondary)
        .padding(.vertical, 10).padding(.horizontal, 16)
    }
}

struct YearlySummaryRowView: View {
    @ObservedObject var viewModel: PortfolioViewModel
    let year: Int; let transactions: [Transaction]; let columns: [String]; let privacyMode: Bool

    var buys:        Int    { transactions.filter { $0.type == .buy        }.count }
    var sells:       Int    { transactions.filter { $0.type == .sell       }.count }
    var deposits:    Int    { transactions.filter { $0.type == .deposit    }.count }
    var withdrawals: Int    { transactions.filter { $0.type == .withdrawal }.count }
    
    var invested:    Double { transactions.filter { $0.type == .buy        }.reduce(0) { $0 + $1.amountEUR } }
    var sold:        Double { transactions.filter { $0.type == .sell       }.reduce(0) { $0 + $1.amountEUR } }
    var deposited:   Double { transactions.filter { $0.type == .deposit    }.reduce(0) { $0 + $1.amountEUR } }
    var totalFees:   Double { transactions.reduce(0) { $0 + $1.customFields.values.reduce(0, +) } }
    func colTotal(_ col: String) -> Double { transactions.reduce(0) { $0 + ($1.customFields[col] ?? 0) } }

    var body: some View {
        HStack(spacing: 12) {
            Text(String(year)).fontWeight(.bold).frame(width: 50, alignment: .leading)
            nc(transactions.count, color: .primary)
            nc(buys,        color: .blue)
            nc(sells,       color: .orange)
            nc(deposits,    color: .green)
            nc(withdrawals, color: .red)
            ec(invested,  color: .blue)
            ec(sold,      color: .orange)
            ec(deposited, color: .green)
            ec(totalFees, color: .red)
            ForEach(columns, id: \.self) { col in ec(colTotal(col), color: .red) }
        }
        .padding(.vertical, 10).padding(.horizontal, 16)
    }

    @ViewBuilder func nc(_ v: Int, color: Color) -> some View {
        Text("\(v)").foregroundColor(v == 0 ? .secondary : color).fontWeight(v == 0 ? .regular : .semibold)
            .blur(radius: privacyMode ? 6 : 0)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
    @ViewBuilder func ec(_ v: Double, color: Color) -> some View {
        Text(v == 0 ? "—" : v.formatted(.currency(code: viewModel.preferredCurrency).precision(.fractionLength(2))))
            .foregroundColor(v == 0 ? .secondary : color).fontWeight(v == 0 ? .regular : .semibold)
            .font(.system(size: 12))
            .blur(radius: privacyMode ? 6 : 0)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

struct YearlyTotalsRowView: View {
    @ObservedObject var viewModel: PortfolioViewModel
    let transactions: [Transaction]; let columns: [String]; let privacyMode: Bool

    var totalBuys:        Int    { transactions.filter { $0.type == .buy        }.count }
    var totalSells:       Int    { transactions.filter { $0.type == .sell       }.count }
    var totalDeposits:    Int    { transactions.filter { $0.type == .deposit    }.count }
    var totalWithdrawals: Int    { transactions.filter { $0.type == .withdrawal }.count }
    
    var totalInvested:    Double { transactions.filter { $0.type == .buy        }.reduce(0) { $0 + $1.amountEUR } }
    var totalSold:        Double { transactions.filter { $0.type == .sell       }.reduce(0) { $0 + $1.amountEUR } }
    var totalDeposited:   Double { transactions.filter { $0.type == .deposit    }.reduce(0) { $0 + $1.amountEUR } }
    var totalFees:        Double { transactions.reduce(0) { $0 + $1.customFields.values.reduce(0, +) } }
    func colTotal(_ col: String) -> Double { transactions.reduce(0) { $0 + ($1.customFields[col] ?? 0) } }

    var body: some View {
        HStack(spacing: 12) {
            Text("TOTAL").fontWeight(.bold).italic().frame(width: 50, alignment: .leading)
            nc(transactions.count)
            nc(totalBuys)
            nc(totalSells)
            nc(totalDeposits)
            nc(totalWithdrawals)
            ec(totalInvested)
            ec(totalSold)
            ec(totalDeposited)
            ec(totalFees)
            ForEach(columns, id: \.self) { col in ec(colTotal(col)) }
        }
        .padding(.vertical, 10).padding(.horizontal, 16)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.6))
    }

    @ViewBuilder func nc(_ v: Int) -> some View {
        Text("\(v)").fontWeight(.bold)
            .blur(radius: privacyMode ? 6 : 0)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
    @ViewBuilder func ec(_ v: Double) -> some View {
        Text(v == 0 ? "—" : v.formatted(.currency(code: viewModel.preferredCurrency).precision(.fractionLength(2))))
            .fontWeight(.bold).font(.system(size: 12))
            .blur(radius: privacyMode ? 6 : 0)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

// =========================================================================
// MARK: - CHARTS SECTION
// =========================================================================

struct TransactionsChartsSection: View {
    @ObservedObject var viewModel: PortfolioViewModel
    let tx: [Transaction]
    @Binding var privacyMode: Bool
    @Binding var chartToZoom: TxChartZoomType?

    var body: some View {
        VStack(spacing: 24) {
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Transaction Analytics").font(.title2).fontWeight(.bold).foregroundColor(.secondary)
                HStack(spacing: 24) {
                    TxAnnualCountChart(viewModel: viewModel, tx: tx, privacyMode: $privacyMode, expandedChart: $chartToZoom)
                    TxTotalByTypeChart(viewModel: viewModel, tx: tx, privacyMode: $privacyMode, expandedChart: $chartToZoom)
                }
            }
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Trading History & Taxes").font(.title2).fontWeight(.bold).foregroundColor(.secondary)
                HStack(spacing: 24) {
                    TxBuysOverTimeChart(viewModel: viewModel, tx: tx, privacyMode: $privacyMode, expandedChart: $chartToZoom)
                    TxTaxBreakdownChart(viewModel: viewModel, tx: tx, privacyMode: $privacyMode, expandedChart: $chartToZoom)
                }
            }
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Asset Breakdown & Holding Periods").font(.title2).fontWeight(.bold).foregroundColor(.secondary)
                HStack(spacing: 24) {
                    TxCapitalAllocationChart(viewModel: viewModel, tx: tx, privacyMode: $privacyMode, expandedChart: $chartToZoom)
                    TxHoldingPeriodChart(viewModel: viewModel, tx: tx, privacyMode: $privacyMode, expandedChart: $chartToZoom)
                }
            }
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Capital Dynamics").font(.title2).fontWeight(.bold).foregroundColor(.secondary)
                HStack(spacing: 24) {
                    TxTradeBalanceChart(viewModel: viewModel, tx: tx, privacyMode: $privacyMode, expandedChart: $chartToZoom)
                    TxCumulativeCapitalChart(viewModel: viewModel, tx: tx, privacyMode: $privacyMode, expandedChart: $chartToZoom)
                }
            }
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Efficiency & Activity").font(.title2).fontWeight(.bold).foregroundColor(.secondary)
                HStack(spacing: 24) {
                    TxTaxDragChart(viewModel: viewModel, tx: tx, privacyMode: $privacyMode, expandedChart: $chartToZoom)
                    TxActivityHeatmapChart(viewModel: viewModel, tx: tx, privacyMode: $privacyMode, expandedChart: $chartToZoom)
                }
            }
            
        }
    }
}

// =========================================================================
// MARK: - CHART 1 : Total Transactions per Year
// =========================================================================

struct TxAnnualCountChart: View {
    @ObservedObject var viewModel: PortfolioViewModel
    let tx: [Transaction]
    @Binding var privacyMode: Bool
    var isExpanded: Bool = false
    @Binding var expandedChart: TxChartZoomType?

    struct AnnualCountItem: Identifiable {
        let id = UUID()
        let year: String
        let type: TransactionType
        let count: Int
    }

    var years: [Int] {
        guard !tx.isEmpty else { return [] }
        let all = tx.map { Calendar.current.component(.year, from: $0.date) }
        let minY = all.min() ?? 2022
        let maxY = all.max() ?? Calendar.current.component(.year, from: Date())
        return Array(minY...maxY)
    }

    var data: [AnnualCountItem] {
        let stackedTypes: [TransactionType] = [.buy, .sell, .deposit, .withdrawal]
        var items: [AnnualCountItem] = []
        for year in years {
            let txYear = tx.filter { Calendar.current.component(.year, from: $0.date) == year }
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
                emptyState("No transactions in this period.")
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
                        
                        if let h = hoveredYear, h == item.year {
                            RuleMark(x: .value("Year", h)).foregroundStyle(Color.secondary.opacity(0.3)).zIndex(-1)
                        }
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let location):
                                    if let year: String = proxy.value(atX: location.x) { hoveredYear = year }
                                case .ended:
                                    hoveredYear = nil
                                }
                            }
                        
                        if let h = hoveredYear {
                            if let xPosition = proxy.position(forX: h) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(h).font(.caption.bold())
                                    Divider()
                                    ForEach(seriesLabels.filter { !hiddenTypes.contains($0) }, id: \.self) { label in
                                        let c = data.first { $0.year == h && $0.type.rawValue == label }?.count ?? 0
                                        HStack {
                                            Circle().fill(color(for: label)).frame(width: 6, height: 6)
                                            Text(label).font(.caption2).foregroundColor(color(for: label))
                                            Spacer()
                                            Text("\(c)").font(.caption2.bold()).blur(radius: privacyMode ? 6 : 0)
                                        }
                                    }
                                }
                                .frame(width: 100)
                                .padding(8).background(Color(NSColor.windowBackgroundColor).opacity(0.95)).cornerRadius(8).shadow(radius: 4)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))
                                .position(x: max(60, min(geometry.size.width - 60, xPosition)), y: 60)
                            }
                        }
                    }
                }
                .chartLegend(.hidden)
                .chartYAxis { AxisMarks(position: .leading) { v in AxisGridLine(); AxisTick(); AxisValueLabel { if let i = v.as(Int.self) { Text("\(i)").font(.system(size: 10)) } } } }
                .chartXAxis { AxisMarks { v in AxisValueLabel { if let s = v.as(String.self) { Text(s).font(.caption) } } } }
            }
            HStack { Text("Shows the frequency of different transaction events annually").font(.caption2).foregroundColor(.secondary); Spacer(); BlueChipWatermark() }
        }
        .padding().frame(minHeight: isExpanded ? 500 : 360, maxHeight: isExpanded ? .infinity : 360).background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// =========================================================================
// MARK: - CHART 2 : Total by Transaction Type
// =========================================================================

struct TxTotalByTypeChart: View {
    @ObservedObject var viewModel: PortfolioViewModel
    let tx: [Transaction]
    @Binding var privacyMode: Bool
    var isExpanded: Bool = false
    @Binding var expandedChart: TxChartZoomType?

    let displayedTypes: [TransactionType] = [.buy, .sell, .deposit, .withdrawal]

    struct TypeSummary: Identifiable {
        let id = UUID()
        let type: TransactionType
        let amount: Double
        let count: Int
    }

    var data: [TypeSummary] {
        displayedTypes.map { t in
            let filtered = tx.filter { $0.type == t }
            return TypeSummary(type: t, amount: filtered.reduce(0) { $0 + $1.amountEUR }, count: filtered.count)
        }.filter { $0.count > 0 }
    }

    var maxAmount: Double { data.map { $0.amount }.max() ?? 1 }
    var maxCount:  Int    { data.map { $0.count  }.max() ?? 1 }
    func scaledCount(_ count: Int) -> Double { maxAmount > 0 ? (Double(count) / Double(maxCount)) * maxAmount : 0 }

    @State private var hiddenSeries: Set<String> = []
    @State private var hoveredType: String? = nil

    var body: some View {
        let sym = AppCurrency(rawValue: viewModel.preferredCurrency)?.symbol ?? "€"
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if !isExpanded { Text("Summary by Type").font(.headline).foregroundColor(.secondary) }
                Spacer()
                HStack(spacing: 12) {
                    Button(action: { withAnimation { toggleHidden("Amount") } }) {
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 2).fill(Color.blue.opacity(0.6)).frame(width: 12, height: 12)
                            Text("Amount \(sym)").font(.caption).foregroundColor(hiddenSeries.contains("Amount") ? .secondary : .primary)
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
                emptyState("No transactions in this period.")
            } else {
                Chart {
                    if !hiddenSeries.contains("Amount") {
                        ForEach(data) { item in
                            BarMark(
                                x: .value("Type", item.type.rawValue),
                                y: .value("Amount", item.amount)
                            )
                            .foregroundStyle(Color.forTransactionType(item.type).opacity(0.75))
                            .cornerRadius(4)
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
                    
                    if let h = hoveredType, let _ = data.first(where: { $0.type.rawValue == h }) {
                        RuleMark(x: .value("Type", h))
                            .foregroundStyle(Color.secondary.opacity(0.3))
                            .zIndex(-1)
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let location):
                                    if let type: String = proxy.value(atX: location.x) { hoveredType = type }
                                case .ended:
                                    hoveredType = nil
                                }
                            }
                        
                        if let h = hoveredType, let item = data.first(where: { $0.type.rawValue == h }) {
                            if let xPosition = proxy.position(forX: h) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(h).font(.caption.bold()).foregroundColor(.primary)
                                    Divider()
                                    Text("Amount: \(item.amount.formatted(.currency(code: viewModel.preferredCurrency).precision(.fractionLength(0))))")
                                        .font(.caption2).foregroundColor(Color.forTransactionType(item.type))
                                        .blur(radius: privacyMode ? 6 : 0)
                                    Text("Count: \(item.count)")
                                        .font(.caption2).foregroundColor(.purple)
                                        .blur(radius: privacyMode ? 6 : 0)
                                }
                                .frame(width: 130)
                                .padding(8).background(Color(NSColor.windowBackgroundColor).opacity(0.95)).cornerRadius(8).shadow(radius: 4)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))
                                .position(x: max(75, min(geometry.size.width - 75, xPosition)), y: 40)
                            }
                        }
                    }
                }
                .chartYScale(domain: 0...(maxAmount > 0 ? maxAmount * 1.3 : 100))
                .chartLegend(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading) { v in
                        AxisGridLine(); AxisTick()
                        AxisValueLabel {
                            if let d = v.as(Double.self) {
                                Text(d.formatted(.currency(code: viewModel.preferredCurrency).precision(.fractionLength(0)))).font(.system(size: 10))
                            }
                        }
                    }
                }
                .chartXAxis { AxisMarks { v in AxisValueLabel { if let s = v.as(String.self) { Text(s).font(.caption) } } } }
            }
            HStack { Text("Compares the monetary volume against the number of transactions").font(.caption2).foregroundColor(.secondary); Spacer(); BlueChipWatermark() }
        }
        .padding().frame(minHeight: isExpanded ? 500 : 360, maxHeight: isExpanded ? .infinity : 360).background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }

    func toggleHidden(_ key: String) {
        if hiddenSeries.contains(key) { hiddenSeries.remove(key) } else { hiddenSeries.insert(key) }
    }
}

// =========================================================================
// MARK: - CHART 3 : Buys over Time
// =========================================================================

struct TxBuysOverTimeChart: View {
    @ObservedObject var viewModel: PortfolioViewModel
    let tx: [Transaction]
    @Binding var privacyMode: Bool
    var isExpanded: Bool = false
    @Binding var expandedChart: TxChartZoomType?

    struct BuyPoint: Identifiable {
        let id = UUID()
        let index: Int
        let date: Date
        let amount: Double
        let ticker: String
    }

    let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "dd/MM/yy"; return f
    }()

    var buys: [BuyPoint] {
        let sorted = tx.filter { $0.type == .buy }.sorted { $0.date < $1.date }
        return sorted.enumerated().map { (idx, t) in
            BuyPoint(index: idx, date: t.date, amount: t.amountEUR, ticker: t.ticker)
        }
    }
    
    var maxAmount: Double {
        buys.map { $0.amount }.max() ?? 100
    }

    var trendPoints: [(index: Int, value: Double)] {
        guard buys.count >= 2 else { return [] }
        let xs = buys.map { Double($0.index) }
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
            let y = slope * Double(pt.index) + intercept
            return (index: pt.index, value: max(0, y))
        }
    }

    @State private var hoveredIndex: Int? = nil
    @State private var hiddenSeries: Set<String> = []

    var body: some View {
        let sym = AppCurrency(rawValue: viewModel.preferredCurrency)?.symbol ?? "€"
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if !isExpanded { Text("Buys over Time").font(.headline).foregroundColor(.secondary) }
                Spacer()
                
                HStack(spacing: 12) {
                    Button(action: { withAnimation { toggleHidden("Amount") } }) {
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 2).fill(Color.blue.opacity(0.8)).frame(width: 12, height: 12)
                            Text("Amount \(sym)").font(.caption).foregroundColor(hiddenSeries.contains("Amount") ? .secondary : .primary)
                        }
                    }.buttonStyle(.plain).opacity(hiddenSeries.contains("Amount") ? 0.4 : 1)

                    Button(action: { withAnimation { toggleHidden("Trend") } }) {
                        HStack(spacing: 4) {
                            Rectangle().fill(Color.gray).frame(width: 12, height: 2)
                            Text("Trend").font(.caption).foregroundColor(hiddenSeries.contains("Trend") ? .secondary : .primary)
                        }
                    }.buttonStyle(.plain).opacity(hiddenSeries.contains("Trend") ? 0.4 : 1)
                }
                
                if !isExpanded { Button(action: { expandedChart = .buysOverTime }) { Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary) }.buttonStyle(.plain) }
            }.padding(.bottom, 4)
            
            if buys.isEmpty {
                emptyState("No buy transactions in this period.")
            } else {
                Chart {
                    if !hiddenSeries.contains("Amount") {
                        ForEach(buys) { buy in
                            BarMark(
                                x: .value("Tx", buy.index),
                                y: .value("Amount", buy.amount)
                            )
                            .foregroundStyle(Color.blue.opacity(0.8))
                            .cornerRadius(2)
                        }
                    }
                    
                    if !hiddenSeries.contains("Trend") {
                        ForEach(trendPoints, id: \.index) { pt in
                            LineMark(
                                x: .value("Tx", pt.index),
                                y: .value("Trend", pt.value)
                            )
                            .foregroundStyle(Color.gray.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1.5))
                        }
                    }
                    
                    if let h = hoveredIndex, let _ = buys.first(where: { $0.index == h }) {
                        RuleMark(x: .value("Tx", h))
                            .foregroundStyle(Color.secondary.opacity(0.4))
                            .zIndex(-1)
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let location):
                                    if let idx: Int = proxy.value(atX: location.x) { hoveredIndex = idx }
                                case .ended:
                                    hoveredIndex = nil
                                }
                            }
                        
                        if let h = hoveredIndex, let buy = buys.first(where: { $0.index == h }) {
                            if let xPosition = proxy.position(forX: h) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(dateFmt.string(from: buy.date)).font(.caption.bold()).foregroundColor(.primary)
                                    Divider()
                                    Text("\(buy.ticker)").font(.caption2.bold()).foregroundColor(.blue)
                                    Text("\(buy.amount.formatted(.currency(code: viewModel.preferredCurrency).precision(.fractionLength(0))))")
                                        .font(.caption2)
                                        .blur(radius: privacyMode ? 6 : 0)
                                }
                                .frame(width: 100)
                                .padding(8).background(Color(NSColor.windowBackgroundColor).opacity(0.95)).cornerRadius(8).shadow(radius: 4)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))
                                .position(x: max(60, min(geometry.size.width - 60, xPosition)), y: 40)
                            }
                        }
                    }
                }
                .chartYScale(domain: 0...(maxAmount > 0 ? maxAmount * 1.3 : 100))
                .chartLegend(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading) { v in
                        AxisGridLine(); AxisTick()
                        AxisValueLabel { if let d = v.as(Double.self) { Text(d.formatted(.currency(code: viewModel.preferredCurrency).precision(.fractionLength(0)))).font(.system(size: 10)) } }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: min(10, buys.count))) { v in
                        if let idx = v.as(Int.self), idx >= 0, idx < buys.count {
                            AxisTick()
                            AxisValueLabel {
                                Text(dateFmt.string(from: buys[idx].date))
                                    .font(.system(size: 9))
                                    .rotationEffect(.degrees(-45))
                                    .offset(x: -10, y: 10)
                            }
                        }
                    }
                }
            }
            HStack { Text("Shows the historical scale of each buy order with its long-term trend").font(.caption2).foregroundColor(.secondary); Spacer(); BlueChipWatermark() }
        }
        .padding().frame(minHeight: isExpanded ? 500 : 360, maxHeight: isExpanded ? .infinity : 360).background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }

    func toggleHidden(_ key: String) {
        if hiddenSeries.contains(key) { hiddenSeries.remove(key) } else { hiddenSeries.insert(key) }
    }
}

// =========================================================================
// MARK: - CHART 4 : Tax breakdown donut
// =========================================================================

struct TxTaxBreakdownChart: View {
    @ObservedObject var viewModel: PortfolioViewModel
    let tx: [Transaction]
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
            let total = tx.reduce(0) { $0 + ($1.customFields[col] ?? 0) }
            guard total > 0 else { return nil }
            return TaxSlice(name: col, amount: total, color: colors[idx % colors.count])
        }
    }

    var grandTotal: Double { slices.reduce(0) { $0 + $1.amount } }
    
    @State private var selectedAngleValue: Double? = nil
    @State private var hiddenItems: Set<String> = []

    func color(for name: String) -> Color {
        if let slice = slices.first(where: { $0.name == name }) { return slice.color }
        return .gray
    }
    
    var filteredSlices: [TaxSlice] {
        slices.filter { !hiddenItems.contains($0.name) }
    }
    
    func getSelectedSlice(for angle: Double) -> TaxSlice? {
        var cum = 0.0
        for slice in filteredSlices {
            cum += slice.amount
            if angle <= cum { return slice }
        }
        return filteredSlices.last
    }

    var body: some View {
        VStack {
            HStack {
                if !isExpanded { Text("Fees & Taxes Breakdown").font(.headline).foregroundColor(.secondary) }
                Spacer()
                if !isExpanded { Button(action: { expandedChart = .taxBreakdown }) { Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary) }.buttonStyle(.plain) }
            }.padding(.bottom, 4)
            
            InteractiveLegendView(items: slices.map { $0.name }, colorMap: color, hiddenItems: $hiddenItems).padding(.bottom, 8)
            
            if filteredSlices.isEmpty {
                Spacer(); Text("No fees/taxes recorded in this period.").foregroundColor(.secondary); Spacer()
            } else {
                Chart(filteredSlices) { slice in
                    SectorMark(
                        angle: .value("Amount", slice.amount),
                        innerRadius: .ratio(0.65),
                        angularInset: 1.5
                    )
                    .foregroundStyle(slice.color)
                    .cornerRadius(4)
                }
                .chartLegend(.hidden)
                .chartAngleSelection(value: $selectedAngleValue)
                .chartBackground { proxy in
                    GeometryReader { geometry in
                        if let s = selectedAngleValue, let slice = getSelectedSlice(for: s) {
                            VStack {
                                Text(slice.name).font(.headline).foregroundColor(slice.color)
                                Text(slice.amount.formatted(.currency(code: viewModel.preferredCurrency).precision(.fractionLength(2))))
                                    .font(.title3).fontWeight(.bold)
                                    .blur(radius: privacyMode ? 6 : 0)
                            }.position(x: geometry.frame(in: .local).midX, y: geometry.frame(in: .local).midY)
                        } else {
                            let displayedTotal = filteredSlices.reduce(0) { $0 + $1.amount }
                            VStack {
                                Text("Total").font(.subheadline).foregroundColor(.secondary)
                                Text(displayedTotal.formatted(.currency(code: viewModel.preferredCurrency).precision(.fractionLength(2))))
                                    .font(.title2).fontWeight(.bold)
                                    .blur(radius: privacyMode ? 6 : 0)
                            }.position(x: geometry.frame(in: .local).midX, y: geometry.frame(in: .local).midY)
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: selectedAngleValue)
            }
            HStack { Text("Distributes the total overhead costs linked to custom tax columns").font(.caption2).foregroundColor(.secondary); Spacer(); BlueChipWatermark() }
        }
        .padding().frame(minHeight: isExpanded ? 500 : 360, maxHeight: isExpanded ? .infinity : 360).background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// =========================================================================
// MARK: - CHART 5 : Deployed Capital Allocation (Donut)
// =========================================================================

struct TxCapitalAllocationChart: View {
    @ObservedObject var viewModel: PortfolioViewModel
    let tx: [Transaction]
    @Binding var privacyMode: Bool
    var isExpanded: Bool = false
    @Binding var expandedChart: TxChartZoomType?

    struct CapitalSlice: Identifiable {
        let id = UUID()
        let ticker: String
        let amount: Double
    }

    var slices: [CapitalSlice] {
        var dict: [String: Double] = [:]
        
        let buys = tx.filter { $0.type == .buy }
        for b in buys {
            let totalTaxes = b.customFields.values.reduce(0, +)
            dict[b.ticker, default: 0] += (b.amountEUR + totalTaxes)
        }
        
        var result: [CapitalSlice] = []
        var oldStocksTotal: Double = 0
        let currentTickers = Set(viewModel.positions.map { $0.ticker })
        
        for (ticker, amount) in dict {
            if currentTickers.contains(ticker) {
                result.append(CapitalSlice(ticker: ticker, amount: amount))
            } else {
                oldStocksTotal += amount
            }
        }
        
        result.sort { $0.amount > $1.amount }
        if oldStocksTotal > 0 {
            result.append(CapitalSlice(ticker: "Sold Stocks", amount: oldStocksTotal))
        }
        return result
    }

    @State private var selectedAngleValue: Double? = nil
    @State private var hiddenItems: Set<String> = []

    func color(for ticker: String) -> Color {
        if ticker == "Sold Stocks" { return .gray.opacity(0.5) }
        return viewModel.color(for: ticker)
    }
    
    var filteredSlices: [CapitalSlice] {
        slices.filter { !hiddenItems.contains($0.ticker) }
    }
    
    func getSelectedSlice(for angle: Double) -> CapitalSlice? {
        var cum = 0.0
        for slice in filteredSlices {
            cum += slice.amount
            if angle <= cum { return slice }
        }
        return filteredSlices.last
    }

    var body: some View {
        VStack {
            HStack {
                if !isExpanded { Text("Deployed Capital Allocation").font(.headline).foregroundColor(.secondary) }
                Spacer()
                if !isExpanded { Button(action: { expandedChart = .capitalAllocation }) { Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary) }.buttonStyle(.plain) }
            }.padding(.bottom, 4)
            
            InteractiveLegendView(items: slices.map { $0.ticker }, colorMap: color, hiddenItems: $hiddenItems).padding(.bottom, 8)
            
            if filteredSlices.isEmpty {
                emptyState("No buy transactions recorded.")
            } else {
                Chart(filteredSlices) { slice in
                    SectorMark(
                        angle: .value("Amount", slice.amount),
                        innerRadius: .ratio(0.65),
                        angularInset: 1.5
                    )
                    .foregroundStyle(color(for: slice.ticker))
                    .cornerRadius(4)
                }
                .chartLegend(.hidden)
                .chartAngleSelection(value: $selectedAngleValue)
                .chartBackground { proxy in
                    GeometryReader { geometry in
                        if let s = selectedAngleValue, let slice = getSelectedSlice(for: s) {
                            VStack {
                                Text(slice.ticker).font(.headline).foregroundColor(color(for: slice.ticker))
                                Text(slice.amount.formatted(.currency(code: viewModel.preferredCurrency).precision(.fractionLength(0))))
                                    .font(.title3).fontWeight(.bold)
                                    .blur(radius: privacyMode ? 6 : 0)
                            }.position(x: geometry.frame(in: .local).midX, y: geometry.frame(in: .local).midY)
                        } else {
                            let displayedTotal = filteredSlices.reduce(0) { $0 + $1.amount }
                            VStack {
                                Text("Total Spent").font(.subheadline).foregroundColor(.secondary)
                                Text(displayedTotal.formatted(.currency(code: viewModel.preferredCurrency).precision(.fractionLength(0))))
                                    .font(.title2).fontWeight(.bold)
                                    .blur(radius: privacyMode ? 6 : 0)
                            }.position(x: geometry.frame(in: .local).midX, y: geometry.frame(in: .local).midY)
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: selectedAngleValue)
            }
            HStack { Text("Breaks down where the total invested volume has been distributed").font(.caption2).foregroundColor(.secondary); Spacer(); BlueChipWatermark() }
        }
        .padding().frame(minHeight: isExpanded ? 500 : 360, maxHeight: isExpanded ? .infinity : 360).background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// =========================================================================
// MARK: - CHART 6 : Days Held per Asset (Bar Chart)
// =========================================================================

struct TxHoldingPeriodChart: View {
    @ObservedObject var viewModel: PortfolioViewModel
    let tx: [Transaction]
    @Binding var privacyMode: Bool
    var isExpanded: Bool = false
    @Binding var expandedChart: TxChartZoomType?

    struct HoldingItem: Identifiable {
        let id = UUID()
        let ticker: String
        let days: Int
        let isCurrent: Bool
    }

    var data: [HoldingItem] {
        var items: [HoldingItem] = []
        let currentTickers = Set(viewModel.positions.map { $0.ticker })
        let now = Date()
        
        let groupedTx = Dictionary(grouping: tx.filter { $0.type == .buy || $0.type == .sell }, by: { $0.ticker })
        
        for (ticker, transactions) in groupedTx {
            guard let firstBuy = transactions.filter({ $0.type == .buy }).map({ $0.date }).min() else { continue }
            
            let isCurrent = currentTickers.contains(ticker)
            var endDate = now
            
            if !isCurrent {
                if let lastSell = transactions.filter({ $0.type == .sell }).map({ $0.date }).max() {
                    endDate = lastSell
                }
            }
            
            let components = Calendar.current.dateComponents([.day], from: firstBuy, to: endDate)
            let daysHeld = components.day ?? 0
            
            if daysHeld >= 0 {
                items.append(HoldingItem(ticker: ticker, days: daysHeld, isCurrent: isCurrent))
            }
        }
        
        return items.sorted { $0.days > $1.days }
    }
    
    // Calcul de la moyenne des jours de détention
    var averageDays: Double {
        guard !data.isEmpty else { return 0 }
        let totalDays = data.reduce(0) { $0 + $1.days }
        return Double(totalDays) / Double(data.count)
    }
    
    // Propriété calculée pour les éléments de la légende
    var legendItems: [String] {
        var items = data.map { $0.ticker }
        if !data.isEmpty {
            items.insert("Average", at: 0)
        }
        return items
    }
    
    @State private var hiddenTickers: Set<String> = []
    @State private var hoveredTicker: String? = nil

    func color(for ticker: String) -> Color {
        if ticker == "Average" { return .gray.opacity(0.8) }
        if let item = data.first(where: { $0.ticker == ticker }) {
            return item.isCurrent ? viewModel.color(for: item.ticker) : .gray.opacity(0.5)
        }
        return .gray
    }

    var body: some View {
        let filteredData = data.filter { !hiddenTickers.contains($0.ticker) }
        
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if !isExpanded { Text("Days Held per Asset").font(.headline).foregroundColor(.secondary) }
                Spacer()
                if !isExpanded { Button(action: { expandedChart = .holdingPeriod }) { Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary) }.buttonStyle(.plain) }
            }.padding(.bottom, 4)
            
            InteractiveLegendView(items: legendItems, colorMap: { color(for: $0) }, hiddenItems: $hiddenTickers)
                .padding(.bottom, 8)

            if filteredData.isEmpty && data.isEmpty {
                emptyState("No buy transactions recorded.")
            } else {
                Chart {
                    ForEach(filteredData) { item in
                        BarMark(
                            x: .value("Ticker", item.ticker),
                            y: .value("Days Held", item.days)
                        )
                        .foregroundStyle(color(for: item.ticker))
                        .cornerRadius(4)
                        
                        // Ligne verticale grise au survol
                        if let hTicker = hoveredTicker, item.ticker == hTicker {
                            RuleMark(x: .value("Ticker", hTicker))
                                .foregroundStyle(Color.secondary.opacity(0.3))
                                .zIndex(-1)
                        }
                    }
                    
                    // MODIFIÉ : La ligne de moyenne est placée APRÈS les barres pour être au premier plan
                    if !hiddenTickers.contains("Average") && !data.isEmpty {
                        RuleMark(y: .value("Average Days", averageDays))
                            .foregroundStyle(Color.primary.opacity(0.7)) // Plus contrasté
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                            .zIndex(10) // Force l'affichage au-dessus des barres
                            .annotation(position: .top, alignment: .leading) {
                                Text("Avg: \(Int(averageDays))d")
                                    .font(.caption2.bold())
                                    .foregroundColor(.primary)
                                    .padding(.horizontal, 4).padding(.vertical, 2)
                                    .background(Color(NSColor.windowBackgroundColor).opacity(0.8))
                                    .cornerRadius(4)
                                    .blur(radius: privacyMode ? 6 : 0)
                            }
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let location):
                                    if let ticker: String = proxy.value(atX: location.x) { hoveredTicker = ticker }
                                case .ended:
                                    hoveredTicker = nil
                                }
                            }
                        
                        if let hTicker = hoveredTicker, let item = filteredData.first(where: { $0.ticker == hTicker }) {
                            if let xPosition = proxy.position(forX: hTicker) {
                                VStack(alignment: .center, spacing: 2) {
                                    Text(item.ticker).font(.caption.bold())
                                    Text("\(item.days) days")
                                        .font(.caption2)
                                        .blur(radius: privacyMode ? 6 : 0)
                                }
                                .padding(6)
                                .background(Color(NSColor.windowBackgroundColor).opacity(0.95))
                                .cornerRadius(6)
                                .shadow(radius: 4)
                                .position(x: max(40, min(geometry.size.width - 40, xPosition)), y: 35)
                            }
                        }
                    }
                }
                .chartLegend(.hidden)
                .chartXSelection(value: $hoveredTicker)
                .chartYAxis { AxisMarks(position: .leading) { v in AxisGridLine(); AxisTick(); AxisValueLabel { if let d = v.as(Int.self) { Text("\(d)") } } } }
            }
            HStack { Text("Measures the duration from the first buy to the last sell (or today)").font(.caption2).foregroundColor(.secondary); Spacer(); BlueChipWatermark() }
        }
        .padding().frame(minHeight: isExpanded ? 500 : 360, maxHeight: isExpanded ? .infinity : 360).background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// =========================================================================
// MARK: - CHART 7 : Trade Balance (Diverging Bar Chart)
// =========================================================================

struct TxTradeBalanceChart: View {
    @ObservedObject var viewModel: PortfolioViewModel
    let tx: [Transaction]
    @Binding var privacyMode: Bool
    var isExpanded: Bool = false
    @Binding var expandedChart: TxChartZoomType?

    struct BalanceItem: Identifiable {
        let id = UUID()
        let year: String
        let type: String
        let amount: Double
    }

    var data: [BalanceItem] {
        let cal = Calendar.current
        var dict: [Int: (buys: Double, sells: Double)] = [:]
        
        for t in tx {
            let year = cal.component(.year, from: t.date)
            if t.type == .buy { dict[year, default: (0,0)].buys += t.amountEUR }
            if t.type == .sell { dict[year, default: (0,0)].sells -= t.amountEUR }
        }
        
        var result: [BalanceItem] = []
        for year in dict.keys.sorted() {
            result.append(BalanceItem(year: String(year), type: "Buy", amount: dict[year]!.buys))
            result.append(BalanceItem(year: String(year), type: "Sell", amount: dict[year]!.sells))
        }
        return result
    }

    @State private var hoveredYear: String? = nil
    @State private var hiddenTypes: Set<String> = []

    var body: some View {
        let filteredData = data.filter { !hiddenTypes.contains($0.type) }
        
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if !isExpanded { Text("Trade Balance (Buys vs Sells)").font(.headline).foregroundColor(.secondary) }
                Spacer()
                if !isExpanded { Button(action: { expandedChart = .tradeBalance }) { Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary) }.buttonStyle(.plain) }
            }.padding(.bottom, 4)
            
            InteractiveLegendView(items: ["Buy", "Sell"], colorMap: { $0 == "Buy" ? .blue : .orange }, hiddenItems: $hiddenTypes).padding(.bottom, 8)

            if filteredData.isEmpty { emptyState("No trading activity found.") } else {
                Chart(filteredData) { item in
                    BarMark(
                        x: .value("Year", item.year),
                        y: .value("Amount", item.amount)
                    )
                    .foregroundStyle(item.type == "Buy" ? Color.blue.opacity(0.8) : Color.orange.opacity(0.8))
                    .cornerRadius(2)
                    
                    if let h = hoveredYear, h == item.year {
                        RuleMark(x: .value("Year", h)).foregroundStyle(Color.secondary.opacity(0.3)).zIndex(-1)
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle().fill(.clear).contentShape(Rectangle()).onContinuousHover { phase in
                            switch phase {
                            case .active(let location): if let year: String = proxy.value(atX: location.x) { hoveredYear = year }
                            case .ended: hoveredYear = nil
                            }
                        }
                        
                        if let h = hoveredYear, let xPosition = proxy.position(forX: h) {
                            let b = filteredData.first { $0.year == h && $0.type == "Buy" }?.amount ?? 0
                            let s = abs(filteredData.first { $0.year == h && $0.type == "Sell" }?.amount ?? 0)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(h).font(.caption.bold())
                                Divider()
                                if !hiddenTypes.contains("Buy") {
                                    HStack { Circle().fill(Color.blue).frame(width: 6, height: 6); Text("Buys:").font(.caption2); Spacer(); Text(b.formatted(.currency(code: viewModel.preferredCurrency).precision(.fractionLength(0)))).font(.caption2.bold()).blur(radius: privacyMode ? 6 : 0) }
                                }
                                if !hiddenTypes.contains("Sell") {
                                    HStack { Circle().fill(Color.orange).frame(width: 6, height: 6); Text("Sells:").font(.caption2); Spacer(); Text(s.formatted(.currency(code: viewModel.preferredCurrency).precision(.fractionLength(0)))).font(.caption2.bold()).blur(radius: privacyMode ? 6 : 0) }
                                }
                            }
                            .frame(width: 140).padding(8).background(Color(NSColor.windowBackgroundColor).opacity(0.95)).cornerRadius(8).shadow(radius: 4).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))
                            .position(x: max(70, min(geometry.size.width - 70, xPosition)), y: 50)
                        }
                    }
                }
                .chartLegend(.hidden).chartYAxis { AxisMarks(position: .leading) { v in AxisGridLine(); AxisTick(); AxisValueLabel { if let d = v.as(Double.self) { Text(d.formatted(.currency(code: viewModel.preferredCurrency).notation(.compactName))) } } } }
            }
            HStack { Text("Shows your net accumulation vs distribution phases").font(.caption2).foregroundColor(.secondary); Spacer(); BlueChipWatermark() }
        }.padding().frame(minHeight: isExpanded ? 500 : 360, maxHeight: isExpanded ? .infinity : 360).background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// =========================================================================
// MARK: - CHART 8 : Cumulative Capital Injected (Area Chart)
// =========================================================================

struct TxCumulativeCapitalChart: View {
    @ObservedObject var viewModel: PortfolioViewModel
    let tx: [Transaction]
    @Binding var privacyMode: Bool
    var isExpanded: Bool = false
    @Binding var expandedChart: TxChartZoomType?

    struct CumulItem: Identifiable {
        let id = UUID()
        let date: Date
        let total: Double
    }

    var data: [CumulItem] {
        let cashTx = tx.filter { $0.type == .deposit || $0.type == .withdrawal }.sorted { $0.date < $1.date }
        var runningTotal = 0.0
        var items: [CumulItem] = []
        
        for t in cashTx {
            runningTotal += (t.type == .deposit ? t.amountEUR : -t.amountEUR)
            items.append(CumulItem(date: t.date, total: runningTotal))
        }
        
        if let last = items.last { items.append(CumulItem(date: Date(), total: last.total)) }
        return items
    }
    
    var maxAmount: Double { data.map { $0.total }.max() ?? 100 }

    @State private var hoveredDate: Date? = nil
    
    var hoveredItem: CumulItem? {
        guard let hDate = hoveredDate else { return nil }
        return data.min(by: { abs($0.date.timeIntervalSince(hDate)) < abs($1.date.timeIntervalSince(hDate)) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if !isExpanded { Text("Cumulative Capital Injected").font(.headline).foregroundColor(.secondary) }
                Spacer()
                if !isExpanded { Button(action: { expandedChart = .cumulativeCapital }) { Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary) }.buttonStyle(.plain) }
            }.padding(.bottom, 8)
            
            if data.isEmpty { emptyState("No deposits or withdrawals recorded.") } else {
                Chart {
                    ForEach(data) { item in
                        AreaMark(
                            x: .value("Date", item.date),
                            y: .value("Capital", item.total)
                        )
                        .foregroundStyle(LinearGradient(colors: [Color.green.opacity(0.4), .clear], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.stepCenter)
                        
                        LineMark(
                            x: .value("Date", item.date),
                            y: .value("Capital", item.total)
                        )
                        .foregroundStyle(Color.green)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.stepCenter)
                    }
                    
                    if let item = hoveredItem {
                        RuleMark(x: .value("Date", item.date))
                            .foregroundStyle(Color.secondary.opacity(0.4))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        if let item = hoveredItem, let xPosition = proxy.position(forX: item.date) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.date.formatted(date: .abbreviated, time: .omitted)).font(.caption.bold())
                                Text(item.total.formatted(.currency(code: viewModel.preferredCurrency))).font(.caption2.bold()).foregroundColor(.green).blur(radius: privacyMode ? 6 : 0)
                            }
                            .padding(6).background(Color(NSColor.windowBackgroundColor).opacity(0.95)).cornerRadius(6).shadow(radius: 3)
                            .position(x: max(60, min(geometry.size.width - 60, xPosition)), y: 50)
                        }
                    }
                }
                .chartLegend(.hidden).chartXSelection(value: $hoveredDate)
                .chartYScale(domain: 0...(maxAmount * 1.2))
                .chartYAxis { AxisMarks(position: .leading) { v in AxisGridLine(); AxisTick(); AxisValueLabel { if let d = v.as(Double.self) { Text(d.formatted(.currency(code: viewModel.preferredCurrency).notation(.compactName))) } } } }
            }
            HStack { Text("Total deposits minus withdrawals over time (Dry Powder)").font(.caption2).foregroundColor(.secondary); Spacer(); BlueChipWatermark() }
        }.padding().frame(minHeight: isExpanded ? 500 : 360, maxHeight: isExpanded ? .infinity : 360).background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// =========================================================================
// MARK: - CHART 9 : Tax Drag Index (Line Chart %)
// =========================================================================

struct TxTaxDragChart: View {
    @ObservedObject var viewModel: PortfolioViewModel
    let tx: [Transaction]
    @Binding var privacyMode: Bool
    var isExpanded: Bool = false
    @Binding var expandedChart: TxChartZoomType?

    struct TaxDragItem: Identifiable {
        let id = UUID()
        let year: String
        let percent: Double
        let totalFees: Double
    }

    var data: [TaxDragItem] {
        let cal = Calendar.current
        var dict: [Int: (vol: Double, fees: Double)] = [:]
        
        for t in tx {
            let year = cal.component(.year, from: t.date)
            let fees = t.customFields.values.reduce(0, +)
            if t.type == .buy || t.type == .sell { dict[year, default: (0,0)].vol += t.amountEUR }
            dict[year, default: (0,0)].fees += fees
        }
        
        var result: [TaxDragItem] = []
        for year in dict.keys.sorted() {
            let volume = dict[year]!.vol
            let fees = dict[year]!.fees
            if volume > 0 {
                result.append(TaxDragItem(year: String(year), percent: (fees / volume), totalFees: fees))
            }
        }
        return result
    }

    // NOUVEAU : Calcul de la moyenne
    var averageDrag: Double {
        guard !data.isEmpty else { return 0 }
        let total = data.reduce(0) { $0 + $1.percent }
        return total / Double(data.count)
    }

    @State private var hoveredYear: String? = nil
    @State private var hiddenSeries: Set<String> = [] // Gère les éléments cachés

    // NOUVEAU : Définition des éléments de la légende
    var legendItems: [String] {
        var items = ["Tax Drag"]
        if !data.isEmpty { items.append("Average") }
        return items
    }

    func color(for item: String) -> Color {
        return item == "Average" ? .gray.opacity(0.8) : .red
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if !isExpanded { Text("Tax Drag Index (Fees / Volume)").font(.headline).foregroundColor(.secondary) }
                Spacer()
                if !isExpanded { Button(action: { expandedChart = .taxDrag }) { Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary) }.buttonStyle(.plain) }
            }.padding(.bottom, 4)

            // NOUVEAU : Légende interactive
            InteractiveLegendView(items: legendItems, colorMap: { color(for: $0) }, hiddenItems: $hiddenSeries)
                .padding(.bottom, 8)

            if data.isEmpty { emptyState("No trading volume or fees found.") } else {
                Chart {
                    // Ligne principale : Tax Drag
                    if !hiddenSeries.contains("Tax Drag") {
                        ForEach(data) { item in
                            LineMark(x: .value("Year", item.year), y: .value("Drag", item.percent))
                                .foregroundStyle(Color.red)
                                .lineStyle(StrokeStyle(lineWidth: 2))
                                .interpolationMethod(.monotone)
                                .symbol { Circle().fill(Color.red).frame(width: 8, height: 8) }
                        }
                    }
                    
                    // Ligne de moyenne
                    if !hiddenSeries.contains("Average") && !data.isEmpty {
                        RuleMark(y: .value("Average", averageDrag))
                            .foregroundStyle(Color.primary.opacity(0.7))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                            .zIndex(10) // Maintient la ligne au premier plan
                            .annotation(position: .top, alignment: .leading) {
                                Text("Avg: \(averageDrag.formatted(.percent.precision(.fractionLength(2))))")
                                    .font(.caption2.bold())
                                    .foregroundColor(.primary)
                                    .padding(.horizontal, 4).padding(.vertical, 2)
                                    .background(Color(NSColor.windowBackgroundColor).opacity(0.8))
                                    .cornerRadius(4)
                                    .blur(radius: privacyMode ? 6 : 0)
                            }
                    }
                    
                    // Curseur de survol (RuleMark vertical)
                    if let h = hoveredYear {
                        RuleMark(x: .value("Year", h))
                            .foregroundStyle(Color.secondary.opacity(0.3))
                            .zIndex(-1)
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        if let h = hoveredYear, let item = data.first(where: { $0.year == h }), let xPosition = proxy.position(forX: h) {
                            VStack(spacing: 2) {
                                Text(h).font(.caption.bold())
                                if !hiddenSeries.contains("Tax Drag") {
                                    Text(item.percent.formatted(.percent.precision(.fractionLength(2)))).font(.caption2.bold()).foregroundColor(.red)
                                }
                                Text("Cost: \(item.totalFees.formatted(.currency(code: viewModel.preferredCurrency).precision(.fractionLength(0))))").font(.system(size: 8)).foregroundColor(.secondary).blur(radius: privacyMode ? 6 : 0)
                            }
                            .padding(6).background(Color(NSColor.windowBackgroundColor).opacity(0.95)).cornerRadius(6).shadow(radius: 3)
                            .position(x: max(60, min(geometry.size.width - 60, xPosition)), y: 50)
                        }
                    }
                }
                .chartXSelection(value: $hoveredYear)
                .chartYAxis { AxisMarks(position: .leading) { v in AxisGridLine(); AxisTick(); AxisValueLabel { if let d = v.as(Double.self) { Text(d.formatted(.percent.precision(.fractionLength(1)))) } } } }
            }
            HStack { Text("Percentage of trading volume lost to friction (broker, state taxes)").font(.caption2).foregroundColor(.secondary); Spacer(); BlueChipWatermark() }
        }.padding().frame(minHeight: isExpanded ? 500 : 360, maxHeight: isExpanded ? .infinity : 360).background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// =========================================================================
// MARK: - CHART 10 : Activity Heatmap
// =========================================================================

struct TxActivityHeatmapChart: View {
    @ObservedObject var viewModel: PortfolioViewModel
    let tx: [Transaction]
    @Binding var privacyMode: Bool
    var isExpanded: Bool = false
    @Binding var expandedChart: TxChartZoomType?

    let allMonths = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    
    struct HeatItem: Identifiable {
        let id = UUID()
        let year: String
        let month: String
        let count: Int
    }

    var data: [HeatItem] {
        let cal = Calendar.current
        var dict: [String: [String: Int]] = [:]
        
        let years = Array(Set(tx.map { String(cal.component(.year, from: $0.date)) })).sorted(by: >)
        for y in years {
            dict[y] = [:]
            for m in allMonths { dict[y]![m] = 0 }
        }
        
        for t in tx {
            let y = String(cal.component(.year, from: t.date))
            let mIdx = cal.component(.month, from: t.date) - 1
            let m = allMonths[mIdx]
            dict[y]?[m]? += 1
        }
        
        var result: [HeatItem] = []
        for y in years {
            for m in allMonths {
                result.append(HeatItem(year: y, month: m, count: dict[y]![m]!))
            }
        }
        return result
    }
    
    var maxCount: Int { data.map { $0.count }.max() ?? 1 }
    @State private var hoveredMonth: String? = nil
    @State private var hoveredYear: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if !isExpanded { Text("Activity Heatmap").font(.headline).foregroundColor(.secondary) }
                Spacer()
                if !isExpanded { Button(action: { expandedChart = .activityHeatmap }) { Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary) }.buttonStyle(.plain) }
            }.padding(.bottom, 8)

            if data.isEmpty { emptyState("No transactions to map.") } else {
                Chart(data) { item in
                    RectangleMark(
                        x: .value("Month", item.month),
                        y: .value("Year", item.year)
                    )
                    .foregroundStyle(item.count == 0 ? Color.gray.opacity(0.1) : Color.blue.opacity(0.2 + 0.8 * (Double(item.count) / Double(maxCount))))
                    .cornerRadius(2)
                }
                .chartLegend(.hidden)
                .chartXScale(domain: allMonths)
                .chartYScale(domain: Array(Set(data.map { $0.year })).sorted(by: >))
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle().fill(.clear).contentShape(Rectangle()).onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                if let (m, y) = proxy.value(at: location, as: (String, String).self) {
                                    hoveredMonth = m
                                    hoveredYear = y
                                }
                            case .ended:
                                hoveredMonth = nil
                                hoveredYear = nil
                            }
                        }
                        
                        if let hm = hoveredMonth, let hy = hoveredYear {
                            if let count = data.first(where: { $0.month == hm && $0.year == hy })?.count {
                                VStack(spacing: 2) {
                                    Text("\(hm) \(hy)").font(.caption.bold())
                                    Text("\(count) transactions").font(.caption2).foregroundColor(.secondary).blur(radius: privacyMode ? 6 : 0)
                                }
                                .padding(6).background(Color(NSColor.windowBackgroundColor).opacity(0.95)).cornerRadius(6).shadow(radius: 3)
                                .position(x: proxy.position(forX: hm) ?? 0, y: proxy.position(forY: hy) ?? 0)
                                .allowsHitTesting(false)
                            }
                        }
                    }
                }
            }
            HStack { Text("Darker color indicates a higher number of transactions").font(.caption2).foregroundColor(.secondary); Spacer(); BlueChipWatermark() }
        }.padding().frame(minHeight: isExpanded ? 500 : 360, maxHeight: isExpanded ? .infinity : 360).background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// =========================================================================
// MARK: - FULL SCREEN ZOOM VIEW
// =========================================================================

struct TransactionsFullScreenChartView: View {
    @Environment(\.dismiss) var dismiss
    let zoomType: TxChartZoomType
    @ObservedObject var viewModel: PortfolioViewModel
    let tx: [Transaction]
    @Binding var privacyMode: Bool
    
    var titleForZoom: String {
        switch zoomType {
        case .annualCount: return "Transactions per Year"
        case .typeSummary: return "Summary by Type"
        case .buysOverTime: return "Buys over Time"
        case .taxBreakdown: return "Fees & Taxes Breakdown"
        case .capitalAllocation: return "Deployed Capital Allocation"
        case .holdingPeriod: return "Days Held per Asset"
        case .tradeBalance: return "Trade Balance (Buys vs Sells)"
        case .cumulativeCapital: return "Cumulative Capital Injected"
        case .taxDrag: return "Tax Drag Index (Fees / Volume)"
        case .activityHeatmap: return "Activity Heatmap"
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text(titleForZoom).font(.title).fontWeight(.bold)
                Spacer()
                Button(action: { dismiss() }) { Image(systemName: "xmark.circle.fill").font(.title).foregroundColor(.secondary) }.buttonStyle(.plain)
            }
            
            switch zoomType {
            case .annualCount: TxAnnualCountChart(viewModel: viewModel, tx: tx, privacyMode: $privacyMode, isExpanded: true, expandedChart: .constant(nil))
            case .typeSummary: TxTotalByTypeChart(viewModel: viewModel, tx: tx, privacyMode: $privacyMode, isExpanded: true, expandedChart: .constant(nil))
            case .buysOverTime: TxBuysOverTimeChart(viewModel: viewModel, tx: tx, privacyMode: $privacyMode, isExpanded: true, expandedChart: .constant(nil))
            case .taxBreakdown: TxTaxBreakdownChart(viewModel: viewModel, tx: tx, privacyMode: $privacyMode, isExpanded: true, expandedChart: .constant(nil))
            case .capitalAllocation: TxCapitalAllocationChart(viewModel: viewModel, tx: tx, privacyMode: $privacyMode, isExpanded: true, expandedChart: .constant(nil))
            case .holdingPeriod: TxHoldingPeriodChart(viewModel: viewModel, tx: tx, privacyMode: $privacyMode, isExpanded: true, expandedChart: .constant(nil))
            case .tradeBalance: TxTradeBalanceChart(viewModel: viewModel, tx: tx, privacyMode: $privacyMode, isExpanded: true, expandedChart: .constant(nil))
            case .cumulativeCapital: TxCumulativeCapitalChart(viewModel: viewModel, tx: tx, privacyMode: $privacyMode, isExpanded: true, expandedChart: .constant(nil))
            case .taxDrag: TxTaxDragChart(viewModel: viewModel, tx: tx, privacyMode: $privacyMode, isExpanded: true, expandedChart: .constant(nil))
            case .activityHeatmap: TxActivityHeatmapChart(viewModel: viewModel, tx: tx, privacyMode: $privacyMode, isExpanded: true, expandedChart: .constant(nil))
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

    // NOUVEAU : Variables pour l'auto-complétion
    @State private var suggestedTickers: [YahooQuote] = []
    @State private var searchTask: Task<Void, Never>? = nil

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
                            ForEach(TransactionType.allCases.filter { $0 != .dividend }, id: \.self) { t in
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
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Ticker").font(.caption).foregroundColor(.secondary)
                                    TextField("e.g. AAPL", text: $ticker)
                                        .textFieldStyle(.roundedBorder)
                                        .onChange(of: ticker) { newValue in
                                            let upper = newValue.uppercased()
                                            if ticker != upper { ticker = upper } // Évite la boucle
                                            
                                            searchTask?.cancel()
                                            if upper.trimmingCharacters(in: .whitespaces).isEmpty {
                                                suggestedTickers = []
                                                return
                                            }
                                            searchTask = Task {
                                                try? await Task.sleep(nanoseconds: 300_000_000)
                                                guard !Task.isCancelled else { return }
                                                await searchYahooFinance(query: upper)
                                            }
                                        }
                                    
                                    if !suggestedTickers.isEmpty {
                                        VStack(spacing: 0) {
                                            ForEach(suggestedTickers, id: \.symbol) { quote in
                                                Button(action: {
                                                    searchTask?.cancel()
                                                    ticker = quote.symbol
                                                    suggestedTickers = []
                                                }) {
                                                    HStack {
                                                        Text(quote.symbol).bold()
                                                        Text(quote.shortname ?? "").foregroundColor(.secondary).lineLimit(1)
                                                        Spacer()
                                                        Text(quote.exchDisp ?? "").font(.caption2).foregroundColor(.secondary)
                                                    }
                                                    .padding(6)
                                                    .contentShape(Rectangle())
                                                }
                                                .buttonStyle(.plain)
                                                Divider()
                                            }
                                        }
                                        .background(Color(NSColor.controlBackgroundColor))
                                        .cornerRadius(6)
                                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.3), lineWidth: 1))
                                        .padding(.top, 2)
                                    }
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Quantity").font(.caption).foregroundColor(.secondary)
                                    TextField("0.00", text: $quantity).textFieldStyle(.roundedBorder)
                                }
                            }
                        }
                    }
                    let sym = AppCurrency(rawValue: viewModel.preferredCurrency)?.symbol ?? "€"
                    GroupBox("Amount (\(sym))") {
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
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                if isEditing {
                    Button("Delete Transaction") {
                        viewModel.deleteTransaction(id: transaction!.id)
                        dismiss()
                    }.foregroundColor(.red).padding(.trailing, 16)
                }
                Button(isEditing ? "Save" : "Add") { save() }
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }.padding()
        }
        .frame(width: 520, height: 600) // Un peu plus haut pour le dropdown
        .onAppear { populate() }
    }

    // NOUVEAU : Fonction de recherche asynchrone Yahoo Finance
    func searchYahooFinance(query: String) async {
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://query2.finance.yahoo.com/v1/finance/search?q=\(encodedQuery)") else { return }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(YahooSearchResponse.self, from: data)
            
            await MainActor.run {
                self.suggestedTickers = Array(decoded.quotes.prefix(5))
            }
        } catch {
            print("Erreur recherche Yahoo: \(error)")
        }
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
            viewModel.objectWillChange.send()
        } else {
            let newTx = Transaction(date: date, type: type, ticker: ticker, quantity: qty, amountEUR: amt, note: note, customFields: fields)
            viewModel.addTransaction(newTx)
        }
        dismiss()
    }
}

struct EditTransactionGoalView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: PortfolioViewModel
    @State private var selectedGoal: TransactionGoalType
    @State private var targetInput: Double

    init(viewModel: PortfolioViewModel) {
        self.viewModel = viewModel
        _selectedGoal = State(initialValue: viewModel.transactionGoalType)
        _targetInput = State(initialValue: viewModel.transactionGoalTarget)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Set Transaction Goal").font(.title2).fontWeight(.bold)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill").font(.title2).foregroundColor(.secondary)
                }.buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            VStack(alignment: .leading, spacing: 16) {
                GroupBox {
                    VStack(spacing: 16) {
                        HStack {
                            Text("Goal Type:")
                            Spacer()
                            Picker("", selection: $selectedGoal) {
                                let goalSym = AppCurrency(rawValue: viewModel.preferredCurrency)?.symbol ?? "€"
                                ForEach(TransactionGoalType.allCases, id: \.self) { type in Text(type.rawValue.replacingOccurrences(of: "€", with: goalSym)).tag(type) }
                            }
                            .labelsHidden()
                            .frame(width: 250)
                        }
                        
                        Divider().opacity(0.5)
                        
                        HStack {
                            Text("Target Amount:")
                            Spacer()
                            let sym = AppCurrency(rawValue: viewModel.preferredCurrency)?.symbol ?? "€"
                            TextField(sym, value: $targetInput, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 150)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding()
            
            Spacer()
            Divider()
            
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save Goal") {
                    viewModel.transactionGoalType = selectedGoal
                    viewModel.transactionGoalTarget = targetInput
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }.padding()
        }
        .frame(width: 440, height: 280)
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
