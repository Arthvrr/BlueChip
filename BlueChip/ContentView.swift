import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = PortfolioViewModel()
    @State private var selectedTab: AppTab = .composition
    @State private var showAddSheet = false
    @AppStorage("privacyMode") private var privacyMode = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("BlueChip - Stocks Portfolio Manager").font(.system(size: 24, weight: .black, design: .rounded)).foregroundColor(.primary)
                Spacer()
                
                Button(action: { withAnimation { privacyMode.toggle() } }) { Image(systemName: privacyMode ? "eye.slash" : "eye").font(.body) }.buttonStyle(.plain).padding(.trailing, 8)
                Button(action: { Task { await viewModel.refreshPrices() } }) { if viewModel.isLoading { ProgressView().controlSize(.small) } else { Label("Refresh", systemImage: "arrow.clockwise") } }.disabled(viewModel.isLoading).buttonStyle(.bordered).padding(.trailing, 8)
                Button(action: { showAddSheet = true }) { Label("Add", systemImage: "plus") }.buttonStyle(.borderedProminent)
            }.padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 10)
            
            HStack { CustomTabBar(selectedTab: $selectedTab); Spacer() }
            Divider()
            
            Group {
                switch selectedTab {
                case .composition: CompositionTabView(viewModel: viewModel, privacyMode: $privacyMode)
                case .dividends: DividendsView(viewModel: viewModel, privacyMode: $privacyMode)
                default: VStack(spacing: 20) { Image(systemName: "hammer.fill").font(.system(size: 50)).foregroundColor(.secondary); Text("\(selectedTab.rawValue) view is under construction.").font(.title).foregroundColor(.secondary) }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .navigationTitle("")
        .sheet(isPresented: $showAddSheet) { AddPositionView(viewModel: viewModel) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in viewModel.saveData() }
    }
}
