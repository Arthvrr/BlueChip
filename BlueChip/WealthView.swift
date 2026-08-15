import SwiftUI
import Charts

struct WealthView: View {
    @ObservedObject var viewModel: PortfolioViewModel
    @Binding var privacyMode: Bool
    
    // States for adding Assets
    @State private var newAssetName: String = ""
    @State private var newAssetInvested: Double? = nil
    @State private var newAssetCurrent: Double? = nil
    
    // States for editing
    @State private var editingAsset: WealthAsset? = nil
    @State private var editingLiability: WealthLiability? = nil
    @State private var showGoalSheet: Bool = false
    
    var body: some View {
        let isPrivate = privacyMode
        
        ScrollView {
            VStack(spacing: 24) {
                
                // 1. DASHBOARD: 8 SUMMARY CARDS (UPDATED WITH TRUE NET WORTH)
                VStack(spacing: 16) {
                    HStack(spacing: 16) {
                        DashboardCard(title: "True Net Worth", value: viewModel.trueNetWorth.formatted(.currency(code: "EUR")), titleIcon: "building.columns.fill", privacyMode: $privacyMode)
                        DashboardCard(title: "Total Assets", value: viewModel.totalAssets.formatted(.currency(code: "EUR")), titleIcon: nil, privacyMode: $privacyMode)
                        DashboardCard(title: "Total Liabilities", value: viewModel.totalLiabilities.formatted(.currency(code: "EUR")), titleIcon: nil, privacyMode: $privacyMode)
                        
                        // Net P/L (Assets)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Net P/L (Assets)").font(.subheadline).foregroundColor(.secondary).lineLimit(1)
                            Text(viewModel.totalWealthVariationEUR.formatted(.currency(code: "EUR").sign(strategy: .always())))
                                .font(.title2).fontWeight(.bold)
                                .foregroundColor(viewModel.totalWealthVariationEUR >= 0 ? .green : .red)
                                .blur(radius: isPrivate ? 8 : 0)
                        }.padding().frame(maxWidth: .infinity, alignment: .leading).frame(height: 110).background(Color(NSColor.controlBackgroundColor)).cornerRadius(10).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                    }
                    
                    HStack(spacing: 16) {
                        DashboardCard(title: "Wealth Goal", value: viewModel.wealthGoalTarget.formatted(.currency(code: "EUR")), titleIcon: "star.fill", privacyMode: $privacyMode)
                        DashboardCard(title: "Overall Assets ROI", value: viewModel.totalWealthVariationPercent.formatted(.percent.precision(.fractionLength(2)).sign(strategy: .always())), titleIcon: nil, privacyMode: .constant(false))
                        
                        // Debt-to-Asset Ratio
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Debt-to-Asset Ratio").font(.subheadline).foregroundColor(.secondary).lineLimit(1)
                            Text(viewModel.debtToAssetRatio.formatted(.percent.precision(.fractionLength(1))))
                                .font(.title2).fontWeight(.bold)
                                .foregroundColor(viewModel.debtToAssetRatio > 0.4 ? .red : (viewModel.debtToAssetRatio > 0.2 ? .orange : .green))
                                .blur(radius: isPrivate ? 8 : 0)
                        }.padding().frame(maxWidth: .infinity, alignment: .leading).frame(height: 110).background(Color(NSColor.controlBackgroundColor)).cornerRadius(10).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                        
                        DashboardCard(title: "Brokerage Weight", value: viewModel.wealthStockWeight.formatted(.percent.precision(.fractionLength(2))), titleIcon: "chart.pie.fill", privacyMode: .constant(false))
                    }
                }
                
                // 2. GOAL PROGRESS BAR (Now linked to True Net Worth)
                WealthGoalProgressBar(
                    currentValue: viewModel.trueNetWorth,
                    targetValue: viewModel.wealthGoalTarget,
                    progress: viewModel.wealthGoalProgress,
                    privacyMode: $privacyMode
                )
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { showGoalSheet = true }
                
                // 3. ASSETS TABLE & QUICK ADD
                VStack(spacing: 16) {
                    WealthAssetsTableSection(
                        viewModel: viewModel,
                        privacyMode: $privacyMode,
                        onEdit: { asset in if !asset.isAutoFilled { editingAsset = asset } }
                    )
                    
                    WealthAddAssetSection(
                        newAssetName: $newAssetName,
                        newAssetInvested: $newAssetInvested,
                        newAssetCurrent: $newAssetCurrent,
                        onAdd: {
                            guard !newAssetName.isEmpty, let invested = newAssetInvested, let current = newAssetCurrent else { return }
                            let newAsset = WealthAsset(name: newAssetName, invested: invested, current: current, isAutoFilled: false)
                            viewModel.manualWealthAssets.append(newAsset)
                            newAssetName = ""
                            newAssetInvested = nil
                            newAssetCurrent = nil
                        }
                    )
                }
                
                // 4. LIABILITIES TABLE & QUICK ADD
                VStack(spacing: 16) {
                    WealthLiabilitiesTableSection(
                        viewModel: viewModel,
                        privacyMode: $privacyMode,
                        onEdit: { liability in editingLiability = liability }
                    )
                    
                    WealthAddLiabilitySection(viewModel: viewModel)
                }
                
                // 5. CHARTS (DONUT & BARS for Assets)
                HStack(spacing: 24) {
                    WealthAllocationChart(viewModel: viewModel)
                    WealthROIChart(viewModel: viewModel)
                }
                
                // 6. FIRE SIMULATOR (FINANCIAL INDEPENDENCE)
                WealthFIRESimulatorSection(viewModel: viewModel, privacyMode: $privacyMode)
            }
            .padding()
        }
        .background(Color(NSColor.windowBackgroundColor))
        // Goal Edit Sheet
        .sheet(isPresented: $showGoalSheet) {
            SimpleNumberEditView(title: "Edit Net Worth Goal", value: $viewModel.wealthGoalTarget)
        }
        // Asset Edit Sheet
        .sheet(item: $editingAsset) { asset in
            EditWealthAssetSheet(viewModel: viewModel, assetToEdit: asset)
        }
        // Liability Edit Sheet
        .sheet(item: $editingLiability) { liability in
            EditWealthLiabilitySheet(viewModel: viewModel, liabilityToEdit: liability)
        }
    }
}

// =========================================================================
// MARK: - ASSETS TABLE
// =========================================================================

struct WealthAssetsTableSection: View {
    @ObservedObject var viewModel: PortfolioViewModel
    @Binding var privacyMode: Bool
    let onEdit: (WealthAsset) -> Void
    
    var body: some View {
        let isPrivate = privacyMode
        
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Assets Allocation").font(.title2).fontWeight(.bold).foregroundColor(.secondary)
                Spacer()
                Text("(Double-click to edit a manual asset)").font(.caption).foregroundColor(.secondary).italic()
            }
            .padding(.bottom, 4)
            
            VStack(spacing: 0) {
                // Header
                HStack(spacing: 8) {
                    Text("Asset").fontWeight(.bold).frame(maxWidth: .infinity, alignment: .leading)
                    Text("Current Value").fontWeight(.bold).frame(maxWidth: .infinity, alignment: .trailing)
                    Text("Invested").fontWeight(.bold).frame(maxWidth: .infinity, alignment: .trailing)
                    Text("P/L €").fontWeight(.bold).frame(maxWidth: .infinity, alignment: .trailing)
                    Text("P/L %").fontWeight(.bold).frame(maxWidth: .infinity, alignment: .trailing)
                    Text("% of Assets").fontWeight(.bold).frame(maxWidth: .infinity, alignment: .trailing)
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(NSColor.windowBackgroundColor))
                
                Divider()
                
                // Rows
                ForEach(viewModel.allWealthAssets) { asset in
                    HStack(spacing: 8) {
                        HStack {
                            Text(asset.name).fontWeight(.bold)
                            if asset.isAutoFilled { Image(systemName: "lock.fill").font(.caption2).foregroundColor(.secondary) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
                        Text(asset.current.formatted(.currency(code: "EUR"))).fontWeight(.semibold).blur(radius: isPrivate ? 6 : 0).frame(maxWidth: .infinity, alignment: .trailing)
                        Text(asset.invested.formatted(.currency(code: "EUR"))).blur(radius: isPrivate ? 6 : 0).frame(maxWidth: .infinity, alignment: .trailing)
                        Text(asset.variationEUR.formatted(.currency(code: "EUR").sign(strategy: .always()))).fontWeight(.semibold).foregroundColor(asset.variationEUR >= 0 ? .green : .red).blur(radius: isPrivate ? 6 : 0).frame(maxWidth: .infinity, alignment: .trailing)
                        Text(asset.variationPercent.formatted(.percent.precision(.fractionLength(2)).sign(strategy: .always()))).fontWeight(.bold).padding(.horizontal, 6).padding(.vertical, 2).background((asset.variationPercent >= 0 ? Color.green : Color.red).opacity(0.15)).foregroundColor(asset.variationPercent >= 0 ? .green : .red).cornerRadius(4).frame(maxWidth: .infinity, alignment: .trailing)
                        
                        let pctTotal = viewModel.totalAssets > 0 ? (asset.current / viewModel.totalAssets) : 0
                        Text(pctTotal.formatted(.percent.precision(.fractionLength(2)))).frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12).contentShape(Rectangle())
                    .onTapGesture(count: 2) { onEdit(asset) }
                    Divider()
                }
            }
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))
        }
        .padding().background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// =========================================================================
// MARK: - LIABILITIES TABLE
// =========================================================================

struct WealthLiabilitiesTableSection: View {
    @ObservedObject var viewModel: PortfolioViewModel
    @Binding var privacyMode: Bool
    let onEdit: (WealthLiability) -> Void
    
    var body: some View {
        let isPrivate = privacyMode
        
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Liabilities & Debts").font(.title2).fontWeight(.bold).foregroundColor(.secondary)
                Spacer()
                Text("(Double-click to edit)").font(.caption).foregroundColor(.secondary).italic()
            }
            .padding(.bottom, 4)
            
            VStack(spacing: 0) {
                // Header
                HStack(spacing: 8) {
                    Text("Liability Name").fontWeight(.bold).frame(maxWidth: .infinity, alignment: .leading)
                    Text("Amount Owed").fontWeight(.bold).frame(maxWidth: .infinity, alignment: .trailing)
                    Text("% of Total Debt").fontWeight(.bold).frame(maxWidth: .infinity, alignment: .trailing)
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(NSColor.windowBackgroundColor))
                
                Divider()
                
                if viewModel.manualWealthLiabilities.isEmpty {
                    Text("No liabilities recorded. You are debt-free! 🎉").foregroundColor(.secondary).padding(20)
                } else {
                    // Rows
                    ForEach(viewModel.manualWealthLiabilities) { liability in
                        HStack(spacing: 8) {
                            Text(liability.name).fontWeight(.bold).frame(maxWidth: .infinity, alignment: .leading)
                            Text(liability.amount.formatted(.currency(code: "EUR"))).fontWeight(.semibold).foregroundColor(.red).blur(radius: isPrivate ? 6 : 0).frame(maxWidth: .infinity, alignment: .trailing)
                            
                            let pctTotal = viewModel.totalLiabilities > 0 ? (liability.amount / viewModel.totalLiabilities) : 0
                            Text(pctTotal.formatted(.percent.precision(.fractionLength(2)))).frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12).contentShape(Rectangle())
                        .onTapGesture(count: 2) { onEdit(liability) }
                        Divider()
                    }
                }
            }
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))
        }
        .padding().background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// =========================================================================
// MARK: - QUICK ADD FORMS
// =========================================================================

struct WealthAddAssetSection: View {
    @Binding var newAssetName: String
    @Binding var newAssetInvested: Double?
    @Binding var newAssetCurrent: Double?
    let onAdd: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            TextField("Asset Name (e.g. Real Estate, Crypto...)", text: $newAssetName).textFieldStyle(.roundedBorder)
            TextField("Invested Amount (€)", value: $newAssetInvested, format: .number).textFieldStyle(.roundedBorder).frame(width: 160)
            TextField("Current Value (€)", value: $newAssetCurrent, format: .number).textFieldStyle(.roundedBorder).frame(width: 160)
            Button(action: onAdd) { Label("Add Asset", systemImage: "plus") }.buttonStyle(.borderedProminent).disabled(newAssetName.isEmpty || newAssetInvested == nil || newAssetCurrent == nil)
        }
        .padding().background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

struct WealthAddLiabilitySection: View {
    @ObservedObject var viewModel: PortfolioViewModel
    var body: some View {
        HStack(spacing: 16) {
            TextField("Liability Name (e.g. Mortgage, Student Loan...)", text: $viewModel.newLiabilityName).textFieldStyle(.roundedBorder)
            TextField("Amount Owed (€)", value: $viewModel.newLiabilityAmount, format: .number).textFieldStyle(.roundedBorder).frame(width: 160)
            Button(action: viewModel.addNewLiability) { Label("Add Liability", systemImage: "plus") }.buttonStyle(.borderedProminent).tint(.red).disabled(viewModel.newLiabilityName.isEmpty || viewModel.newLiabilityAmount == nil)
        }
        .padding().background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// =========================================================================
// MARK: - GOAL PROGRESS BAR
// =========================================================================

struct WealthGoalProgressBar: View {
    let currentValue: Double
    let targetValue: Double
    let progress: Double
    @Binding var privacyMode: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Progress towards Net Worth Goal").font(.headline)
                Spacer()
                Text("\(currentValue.formatted(.currency(code: "EUR").precision(.fractionLength(0)))) / \(targetValue.formatted(.currency(code: "EUR").precision(.fractionLength(0))))")
                    .font(.subheadline).fontWeight(.bold)
                    .foregroundColor(progress >= 1 ? .green : .primary)
                    .blur(radius: privacyMode ? 8 : 0)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(NSColor.windowBackgroundColor))
                        .frame(height: 14)
                    
                    RoundedRectangle(cornerRadius: 8)
                        .fill(LinearGradient(gradient: Gradient(colors: [.blue, .purple]), startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(0, min(geometry.size.width * CGFloat(progress), geometry.size.width)), height: 14)
                        .animation(.spring(), value: progress)
                }
            }
            .frame(height: 14)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        .help("Double-click to edit your goal")
    }
}

// =========================================================================
// MARK: - FIRE SIMULATOR SECTION
// =========================================================================

struct WealthFIRESimulatorSection: View {
    @ObservedObject var viewModel: PortfolioViewModel
    @Binding var privacyMode: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Financial Independence (FIRE) Simulator").font(.title2).fontWeight(.bold).foregroundColor(.secondary)
            
            HStack(spacing: 32) {
                // Slider Section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Safe Withdrawal Rate (SWR):").fontWeight(.semibold)
                        Text("\(viewModel.safeWithdrawalRate.formatted(.number.precision(.fractionLength(1))))%").font(.title3).fontWeight(.bold).foregroundColor(.teal)
                        Spacer()
                    }
                    Slider(value: $viewModel.safeWithdrawalRate, in: 0...10, step: 0.1).tint(.teal)
                    Text("Percentage of your True Net Worth you plan to withdraw annually to cover living expenses.").font(.caption).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                
                Divider().frame(height: 80)
                
                // Result Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Estimated Passive Income").font(.headline).foregroundColor(.secondary)
                    
                    HStack(alignment: .firstTextBaseline, spacing: 20) {
                        VStack(alignment: .leading) {
                            Text(viewModel.fireMonthlyIncome.formatted(.currency(code: "EUR"))).font(.system(size: 32, weight: .bold)).foregroundColor(.teal).blur(radius: privacyMode ? 8 : 0)
                            Text("/ month").font(.subheadline).foregroundColor(.secondary)
                        }
                        
                        Text("=").font(.title).foregroundColor(.secondary)
                        
                        VStack(alignment: .leading) {
                            Text(viewModel.fireAnnualIncome.formatted(.currency(code: "EUR"))).font(.title2).fontWeight(.bold).foregroundColor(.primary).blur(radius: privacyMode ? 8 : 0)
                            Text("/ year").font(.subheadline).foregroundColor(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// =========================================================================
// MARK: - CHARTS (DONUT & BARS)
// =========================================================================

struct WealthAllocationChart: View {
    @ObservedObject var viewModel: PortfolioViewModel
    let chartColors: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .yellow, .indigo, .mint, .cyan, .red, .brown]
    
    func color(for name: String) -> Color {
        if let idx = viewModel.allWealthAssets.firstIndex(where: { $0.name == name }) { return chartColors[idx % chartColors.count] }
        return .gray
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Assets Allocation").font(.headline).foregroundColor(.secondary)
            
            Chart(viewModel.allWealthAssets.sorted(by: { $0.current > $1.current })) { asset in
                SectorMark(
                    angle: .value("Value", asset.current),
                    innerRadius: .ratio(0.65),
                    angularInset: 1.5
                )
                .foregroundStyle(color(for: asset.name))
                .cornerRadius(4)
                .annotation(position: .overlay) {
                    let pct = viewModel.totalAssets > 0 ? (asset.current / viewModel.totalAssets) : 0
                    if pct > 0.05 { Text(pct.formatted(.percent.precision(.fractionLength(0)))).font(.caption2.bold()).foregroundColor(.white) }
                }
            }
            .frame(height: 250)
            
            HStack(spacing: 12) {
                ForEach(viewModel.allWealthAssets, id: \.id) { asset in
                    HStack(spacing: 4) { Circle().fill(color(for: asset.name)).frame(width: 8, height: 8); Text(asset.name).font(.caption2).foregroundColor(.secondary) }
                }
            }
            
            Spacer()
            BlueChipWatermark()
        }
        .padding().frame(maxWidth: .infinity, alignment: .leading).background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

struct WealthROIChart: View {
    @ObservedObject var viewModel: PortfolioViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Return on Investment (ROI % by Asset)").font(.headline).foregroundColor(.secondary)
            
            Chart(viewModel.allWealthAssets) { asset in
                BarMark(
                    x: .value("Asset", asset.name),
                    y: .value("ROI", asset.variationPercent * 100)
                )
                .foregroundStyle(asset.variationPercent >= 0 ? Color.green.gradient : Color.red.gradient)
                .cornerRadius(4)
                .annotation(position: .top) { Text(asset.variationPercent.formatted(.percent.precision(.fractionLength(1)))).font(.caption.bold()) }
            }
            .chartYAxis { AxisMarks(position: .leading) { value in AxisGridLine(); AxisTick(); if let val = value.as(Double.self) { AxisValueLabel("\(val.formatted(.number.precision(.fractionLength(0))))%") } } }
            .frame(height: 250)
            
            HStack { Text("Unrealized performance by asset class").font(.caption2).foregroundColor(.secondary); Spacer(); BlueChipWatermark() }
            Spacer()
        }
        .padding().frame(maxWidth: .infinity, alignment: .leading).background(Color(NSColor.controlBackgroundColor)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// =========================================================================
// MARK: - EDIT / DELETE SHEETS
// =========================================================================

struct EditWealthAssetSheet: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: PortfolioViewModel
    let assetToEdit: WealthAsset
    
    @State private var name: String = ""
    @State private var invested: Double = 0.0
    @State private var current: Double = 0.0
    
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("Edit Asset").font(.title2).fontWeight(.bold); Spacer(); Button(action: { dismiss() }) { Image(systemName: "xmark.circle.fill").foregroundColor(.secondary) }.buttonStyle(.plain) }.padding()
            Divider()
            
            Form {
                TextField("Asset Name", text: $name)
                TextField("Invested Amount (€)", value: $invested, format: .number)
                TextField("Current Value (€)", value: $current, format: .number)
            }.padding()
            
            Divider()
            HStack {
                Button(role: .destructive, action: { viewModel.manualWealthAssets.removeAll { $0.id == assetToEdit.id }; dismiss() }) { Label("Delete", systemImage: "trash") }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    if let idx = viewModel.manualWealthAssets.firstIndex(where: { $0.id == assetToEdit.id }) {
                        viewModel.manualWealthAssets[idx].name = name
                        viewModel.manualWealthAssets[idx].invested = invested
                        viewModel.manualWealthAssets[idx].current = current
                    }
                    dismiss()
                }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).disabled(name.isEmpty)
            }.padding()
        }.frame(width: 400, height: 300)
        .onAppear { name = assetToEdit.name; invested = assetToEdit.invested; current = assetToEdit.current }
    }
}

struct EditWealthLiabilitySheet: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: PortfolioViewModel
    let liabilityToEdit: WealthLiability
    
    @State private var name: String = ""
    @State private var amount: Double = 0.0
    
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("Edit Liability").font(.title2).fontWeight(.bold); Spacer(); Button(action: { dismiss() }) { Image(systemName: "xmark.circle.fill").foregroundColor(.secondary) }.buttonStyle(.plain) }.padding()
            Divider()
            
            Form {
                TextField("Liability Name", text: $name)
                TextField("Amount Owed (€)", value: $amount, format: .number)
            }.padding()
            
            Divider()
            HStack {
                Button(role: .destructive, action: { viewModel.manualWealthLiabilities.removeAll { $0.id == liabilityToEdit.id }; dismiss() }) { Label("Delete", systemImage: "trash") }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    if let idx = viewModel.manualWealthLiabilities.firstIndex(where: { $0.id == liabilityToEdit.id }) {
                        viewModel.manualWealthLiabilities[idx].name = name
                        viewModel.manualWealthLiabilities[idx].amount = amount
                    }
                    dismiss()
                }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).tint(.red).disabled(name.isEmpty)
            }.padding()
        }.frame(width: 400, height: 260)
        .onAppear { name = liabilityToEdit.name; amount = liabilityToEdit.amount }
    }
}
