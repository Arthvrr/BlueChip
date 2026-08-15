import SwiftUI
import Charts

struct WealthView: View {
    @ObservedObject var viewModel: PortfolioViewModel
    @Binding var privacyMode: Bool
    
    // States for the add form
    @State private var newAssetName: String = ""
    @State private var newAssetInvested: Double? = nil
    @State private var newAssetCurrent: Double? = nil
    
    // States for editing and goals
    @State private var editingAsset: WealthAsset? = nil
    @State private var showGoalSheet: Bool = false
    
    var body: some View {
        let isPrivate = privacyMode
        
        ScrollView {
            VStack(spacing: 24) {
                
                // 1. DASHBOARD: 8 SUMMARY CARDS
                VStack(spacing: 16) {
                    HStack(spacing: 16) {
                        DashboardCard(title: "Total Wealth", value: viewModel.totalWealth.formatted(.currency(code: "EUR")), titleIcon: nil, privacyMode: $privacyMode)
                        DashboardCard(title: "Total Invested", value: viewModel.totalWealthInvested.formatted(.currency(code: "EUR")), titleIcon: nil, privacyMode: $privacyMode)
                        
                        // Net P/L
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Net P/L").font(.subheadline).foregroundColor(.secondary).lineLimit(1)
                            Text(viewModel.totalWealthVariationEUR.formatted(.currency(code: "EUR").sign(strategy: .always())))
                                .font(.title2).fontWeight(.bold)
                                .foregroundColor(viewModel.totalWealthVariationEUR >= 0 ? .green : .red)
                                .blur(radius: isPrivate ? 8 : 0)
                        }.padding().frame(maxWidth: .infinity, alignment: .leading).frame(height: 110).background(Color(NSColor.controlBackgroundColor)).cornerRadius(10).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                        
                        // Overall ROI
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Overall ROI").font(.subheadline).foregroundColor(.secondary).lineLimit(1)
                            Text(viewModel.totalWealthVariationPercent.formatted(.percent.precision(.fractionLength(2)).sign(strategy: .always())))
                                .font(.title2).fontWeight(.bold)
                                .foregroundColor(viewModel.totalWealthVariationPercent >= 0 ? .green : .red)
                                .blur(radius: isPrivate ? 8 : 0)
                        }.padding().frame(maxWidth: .infinity, alignment: .leading).frame(height: 110).background(Color(NSColor.controlBackgroundColor)).cornerRadius(10).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                    }
                    
                    HStack(spacing: 16) {
                        DashboardCard(title: "Wealth Goal", value: viewModel.wealthGoalTarget.formatted(.currency(code: "EUR")), titleIcon: "star.fill", privacyMode: $privacyMode)
                        DashboardCard(title: "Brokerage Weight", value: viewModel.wealthStockWeight.formatted(.percent.precision(.fractionLength(2))), titleIcon: "chart.pie.fill", privacyMode: .constant(false))
                        DashboardCard(title: "Top Asset (%)", value: viewModel.bestWealthAsset, titleIcon: "trophy.fill", privacyMode: .constant(false))
                        DashboardCard(title: "Asset Count", value: "\(viewModel.allWealthAssets.count)", titleIcon: "building.columns.fill", privacyMode: .constant(false))
                    }
                }
                
                // 2. GOAL PROGRESS BAR
                WealthGoalProgressBar(
                    currentValue: viewModel.totalWealth,
                    targetValue: viewModel.wealthGoalTarget,
                    progress: viewModel.wealthGoalProgress,
                    privacyMode: $privacyMode
                )
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { showGoalSheet = true }
                
                // 3. ASSETS TABLE
                WealthTableSection(
                    viewModel: viewModel,
                    privacyMode: $privacyMode,
                    onEdit: { asset in
                        if !asset.isAutoFilled { editingAsset = asset } // Do not edit the auto-filled Brokerage account
                    }
                )
                
                // 4. ADD NEW ASSET SECTION
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
                
                // 5. CHARTS (DONUT & BARS)
                HStack(spacing: 24) {
                    WealthAllocationChart(viewModel: viewModel)
                    WealthROIChart(viewModel: viewModel)
                }
            }
            .padding()
        }
        .background(Color(NSColor.windowBackgroundColor))
        // Goal Edit Sheet
        .sheet(isPresented: $showGoalSheet) {
            SimpleNumberEditView(title: "Edit Wealth Goal", value: $viewModel.wealthGoalTarget)
        }
        // Asset Edit/Delete Sheet
        .sheet(item: $editingAsset) { asset in
            EditWealthAssetSheet(viewModel: viewModel, assetToEdit: asset)
        }
    }
}

// =========================================================================
// MARK: - ASSETS TABLE
// =========================================================================

struct WealthTableSection: View {
    @ObservedObject var viewModel: PortfolioViewModel
    @Binding var privacyMode: Bool
    let onEdit: (WealthAsset) -> Void
    
    var body: some View {
        let isPrivate = privacyMode
        
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Wealth Allocation").font(.title2).fontWeight(.bold).foregroundColor(.secondary)
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
                    Text("% of Wealth").fontWeight(.bold).frame(maxWidth: .infinity, alignment: .trailing)
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
                            if asset.isAutoFilled {
                                Image(systemName: "lock.fill").font(.caption2).foregroundColor(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
                        Text(asset.current.formatted(.currency(code: "EUR")))
                            .fontWeight(.semibold).blur(radius: isPrivate ? 6 : 0)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        
                        Text(asset.invested.formatted(.currency(code: "EUR")))
                            .blur(radius: isPrivate ? 6 : 0)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        
                        Text(asset.variationEUR.formatted(.currency(code: "EUR").sign(strategy: .always())))
                            .fontWeight(.semibold)
                            .foregroundColor(asset.variationEUR >= 0 ? .green : .red)
                            .blur(radius: isPrivate ? 6 : 0)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        
                        Text(asset.variationPercent.formatted(.percent.precision(.fractionLength(2)).sign(strategy: .always())))
                            .fontWeight(.bold)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background((asset.variationPercent >= 0 ? Color.green : Color.red).opacity(0.15))
                            .foregroundColor(asset.variationPercent >= 0 ? .green : .red)
                            .cornerRadius(4)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        
                        let pctTotal = viewModel.totalWealth > 0 ? (asset.current / viewModel.totalWealth) : 0
                        Text(pctTotal.formatted(.percent.precision(.fractionLength(2))))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { onEdit(asset) }
                    
                    Divider()
                }
            }
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// =========================================================================
// MARK: - QUICK ADD FORM
// =========================================================================

struct WealthAddAssetSection: View {
    @Binding var newAssetName: String
    @Binding var newAssetInvested: Double?
    @Binding var newAssetCurrent: Double?
    let onAdd: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            TextField("Asset Name (e.g. Real Estate, Crypto...)", text: $newAssetName)
                .textFieldStyle(.roundedBorder)
            
            TextField("Invested Amount (€)", value: $newAssetInvested, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 160)
            
            TextField("Current Value (€)", value: $newAssetCurrent, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 160)
            
            Button(action: onAdd) {
                Label("Add Asset", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .disabled(newAssetName.isEmpty || newAssetInvested == nil || newAssetCurrent == nil)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
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
                Text("Progress towards Wealth Goal").font(.headline)
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
// MARK: - CHART 1: ALLOCATION DONUT
// =========================================================================

struct WealthAllocationChart: View {
    @ObservedObject var viewModel: PortfolioViewModel
    
    let chartColors: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .yellow, .indigo, .mint, .cyan, .red, .brown]
    
    func color(for name: String) -> Color {
        if let idx = viewModel.allWealthAssets.firstIndex(where: { $0.name == name }) {
            return chartColors[idx % chartColors.count]
        }
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
                    let pct = viewModel.totalWealth > 0 ? (asset.current / viewModel.totalWealth) : 0
                    if pct > 0.05 {
                        Text(pct.formatted(.percent.precision(.fractionLength(0))))
                            .font(.caption2.bold())
                            .foregroundColor(.white)
                    }
                }
            }
            .frame(height: 250)
            
            HStack(spacing: 12) {
                ForEach(viewModel.allWealthAssets, id: \.id) { asset in
                    HStack(spacing: 4) {
                        Circle().fill(color(for: asset.name)).frame(width: 8, height: 8)
                        Text(asset.name).font(.caption2).foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            BlueChipWatermark()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// =========================================================================
// MARK: - CHART 2: ROI BARS
// =========================================================================

struct WealthROIChart: View {
    @ObservedObject var viewModel: PortfolioViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Return on Investment (ROI %)")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Chart(viewModel.allWealthAssets) { asset in
                BarMark(
                    x: .value("Asset", asset.name),
                    y: .value("ROI", asset.variationPercent * 100)
                )
                .foregroundStyle(asset.variationPercent >= 0 ? Color.green.gradient : Color.red.gradient)
                .cornerRadius(4)
                .annotation(position: .top) {
                    Text(asset.variationPercent.formatted(.percent.precision(.fractionLength(1))))
                        .font(.caption.bold())
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisTick()
                    if let val = value.as(Double.self) {
                        AxisValueLabel("\(val.formatted(.number.precision(.fractionLength(0))))%")
                    }
                }
            }
            .frame(height: 250)
            
            HStack {
                Text("Unrealized performance by asset class")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                BlueChipWatermark()
            }
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// =========================================================================
// MARK: - EDIT / DELETE SHEET
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
            HStack {
                Text("Edit Asset").font(.title2).fontWeight(.bold)
                Spacer()
                Button(action: { dismiss() }) { Image(systemName: "xmark.circle.fill").foregroundColor(.secondary) }.buttonStyle(.plain)
            }.padding()
            Divider()
            
            Form {
                TextField("Asset Name", text: $name)
                TextField("Invested Amount (€)", value: $invested, format: .number)
                TextField("Current Value (€)", value: $current, format: .number)
            }
            .padding()
            
            Divider()
            HStack {
                Button(role: .destructive, action: {
                    viewModel.manualWealthAssets.removeAll { $0.id == assetToEdit.id }
                    dismiss()
                }) {
                    Label("Delete", systemImage: "trash")
                }
                
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    if let idx = viewModel.manualWealthAssets.firstIndex(where: { $0.id == assetToEdit.id }) {
                        viewModel.manualWealthAssets[idx].name = name
                        viewModel.manualWealthAssets[idx].invested = invested
                        viewModel.manualWealthAssets[idx].current = current
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty)
            }.padding()
        }
        .frame(width: 400, height: 300)
        .onAppear {
            name = assetToEdit.name
            invested = assetToEdit.invested
            current = assetToEdit.current
        }
    }
}
