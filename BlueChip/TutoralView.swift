import SwiftUI

struct TutorialView: View {
    @Environment(\.dismiss) var dismiss
    let currentTab: AppTab // Le tutoriel s'adapte !
    
    var tutorialContent: (title: String, icon: String, text: String) {
        switch currentTab {

        case .composition:
            return (
                "Composition",
                "chart.pie.fill",
                "This page gives you a bird's eye view of your portfolio. Use it to check your asset allocation, overall returns, and geographic exposure."
            )

        case .dividends:
            return (
                "Dividends",
                "banknote.fill",
                "Track your passive income here. Fill in the 'Spreadsheet' to see your year-over-year dividend growth and projected future income."
            )

        case .growth:
            return (
                "Capital Growth",
                "chart.line.uptrend.xyaxis",
                "This is your wealth accumulator. It compares your net deposits against market returns to show your compound annual growth rate (CAGR)."
            )

        case .benchmark:
            return (
                "Benchmark",
                "chart.bar.xaxis",
                "Compare your portfolio's performance against major market indices. See how your investment strategy performs relative to the broader market."
            )

        case .transactions:
            return (
                "Transactions",
                "arrow.left.arrow.right",
                "Review your investment activity here. Track your purchases, sales, deposits, and withdrawals to keep your portfolio history accurate."
            )

        case .projection:
            return (
                "Projections",
                "chart.xyaxis.line",
                "Explore your portfolio's potential future value. Adjust your assumptions about contributions, returns, and time to understand how your wealth could grow."
            )

        case .watchlist:
            return (
                "Watchlist",
                "eye.fill",
                "Keep an eye on stocks you're interested in. Monitor potential investments and follow their performance before deciding to buy."
            )

        case .calendar:
            return (
                "Financial Calendar",
                "calendar",
                "Stay on top of important financial dates. Track upcoming dividends, earnings announcements, and other events that may affect your investments."
            )

        case .simulation:
            return (
                "Simulation",
                "slider.horizontal.3",
                "Experiment with different investment scenarios. Adjust your assumptions to understand how different decisions could impact your portfolio over time."
            )

        case .exposure:
            return (
                "Exposure",
                "globe.europe.africa.fill",
                "Understand where your money is invested. Analyze your portfolio's geographic and regional exposure to identify concentrations and diversification opportunities."
            )

        case .fundamentals:
            return (
                "Fundamentals",
                "building.2.fill",
                "Dive into the financial health of companies. Examine key metrics such as revenue, earnings, profitability, debt, and other fundamental indicators."
            )

        case .wealth:
            return (
                "Net Worth",
                "wallet.bifold.fill",
                "Track your overall wealth over time. Get a broader picture of your financial progress and see how your assets and liabilities contribute to your net worth."
            )

        case .valuation:
            return (
                "Valuation Lab",
                "scale.3d",
                "Analyze whether a stock is undervalued or overvalued. Set your Margin of Safety in the settings to estimate fair value using metrics such as PEG and Forward P/E ratios."
            )

        default:
            return (
                "Welcome to BlueChip",
                "info.circle.fill",
                "Explore your investment dashboard and discover the tools available to help you analyze and manage your portfolio."
            )
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: tutorialContent.icon).font(.system(size: 60)).foregroundColor(.blue)
            Text(tutorialContent.title).font(.largeTitle).fontWeight(.bold)
            Text(tutorialContent.text).font(.body).multilineTextAlignment(.center).foregroundColor(.secondary).padding(.horizontal, 20)
            Spacer()
            Button("Got it!") { dismiss() }.buttonStyle(.borderedProminent).controlSize(.large)
        }.padding(40).frame(width: 600, height: 400)
    }
}

