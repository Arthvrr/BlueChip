import SwiftUI

struct TutorialView: View {
    @Environment(\.dismiss) var dismiss
    let currentTab: AppTab // Le tutoriel s'adapte !
    
    var tutorialContent: (title: String, icon: String, text: String) {
        switch currentTab {
        case .composition: return ("Composition", "piechart.fill", "This page gives you a bird's eye view of your portfolio. Use it to check your asset allocation, overall returns, and geographic exposure.")
        case .dividends: return ("Dividends", "banknote.fill", "Track your passive income here. Fill in the 'Spreadsheet' to see your year-over-year dividend growth and projected future income.")
        case .growth: return ("Capital Growth", "chart.line.uptrend.xyaxis", "This is your wealth accumulator. It compares your net deposits against market returns to show your compound annual growth rate (CAGR).")
        case .valuation: return ("Valuation Lab", "scale.3d", "Analyze if a stock is cheap or expensive. Set your Margin of Safety in the settings, and we will calculate the fair price based on PEG and Forward PEs.")
        // Tu pourras rajouter les autres onglets !
        default: return ("Welcome to BlueChip", "info.circle.fill", "This page is currently under construction or has no specific tutorial yet.")
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: tutorialContent.icon).font(.system(size: 60)).foregroundColor(.blue)
            Text(tutorialContent.title).font(.largeTitle).fontWeight(.bold)
            Text(tutorialContent.text).font(.body).multilineTextAlignment(.center).foregroundColor(.secondary).padding(.horizontal, 20)
            Spacer()
            Button("Got it!") { dismiss() }.buttonStyle(.borderedProminent).controlSize(.large)
        }.padding(40).frame(width: 400, height: 350)
    }
}

