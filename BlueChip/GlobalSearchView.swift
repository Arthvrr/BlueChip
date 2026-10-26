import SwiftUI

struct SearchResult: Identifiable {
    // 1. CORRECTION CRUCIALE : Un ID fixe basé sur le nom, sinon la sélection bugue à chaque frappe !
    var id: String { title + subtitle }
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let tab: AppTab
}

struct GlobalSearchView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: PortfolioViewModel
    @Binding var selectedTab: AppTab
    
    @State private var searchText = ""
    @FocusState private var isFocused: Bool
    
    // 2. NOUVEAU : Mémorise la ligne actuellement sélectionnée
    @State private var selectedResultID: String? = nil
    
    var searchResults: [SearchResult] {
        guard !searchText.isEmpty else { return [] }
        
        let queryWords = searchText.lowercased().split(separator: " ").map { String($0) }
        var results: [SearchResult] = []
        
        let dfText = DateFormatter()
        dfText.dateStyle = .medium
        let dfNumEU = DateFormatter()
        dfNumEU.dateFormat = "dd/MM/yyyy"
        let dfNumUS = DateFormatter()
        dfNumUS.dateFormat = "MM/dd/yyyy"
        
        func matchesQuery(_ text: String) -> Bool {
            let lowerText = text.lowercased()
            return queryWords.allSatisfy { lowerText.contains($0) }
        }
        
        func matchDate(_ date: Date) -> Bool {
            return matchesQuery(dfText.string(from: date)) ||
                   matchesQuery(dfNumEU.string(from: date)) ||
                   matchesQuery(dfNumUS.string(from: date))
        }
        
        let sym = AppCurrency(rawValue: viewModel.preferredCurrency)?.symbol ?? "€"
        
        let uiElements: [(title: String, subtitle: String, keywords: String, icon: String, color: Color, tab: AppTab)] = [
            
            // ================= COMPOSITION =================
            ("Cash", "Dashboard Metric • Composition", "liquidity available dry powder composition", "eurosign.circle.fill", .green, .composition),
            ("Initial Investment", "Dashboard Metric • Composition", "deposits manually invested out of pocket composition", "arrow.down.circle.fill", .blue, .composition),
            ("Total (Current + Cash)", "Dashboard Metric • Composition", "total wallet value composition", "banknote.fill", .purple, .composition),
            ("Stock Value", "Dashboard Metric • Composition", "equity value composition", "chart.line.uptrend.xyaxis", .indigo, .composition),
            ("Unrealized P/L", "Dashboard Metric • Composition", "profit loss gain return composition", "arrow.up.right.circle.fill", .green, .composition),
            ("Positions", "Dashboard Metric • Composition", "stock count holdings composition", "briefcase.fill", .gray, .composition),
            ("Annual Dividends", "Dashboard Metric • Composition", "income yield cash flow composition", "banknote.fill", .orange, .composition),
            ("Total Yield", "Dashboard Metric • Composition", "portfolio yield percentage composition", "percent", .teal, .composition),
            ("Goal Progress", "Target Tracking • Composition", "goal bar target composition", "target", .purple, .composition),
            ("Positions Spreadsheet", "Data Table • Composition", "holdings list table ledger composition", "tablecells.fill", .gray, .composition),
            ("Weight by Position", "Chart • Composition", "allocation donut pie composition", "chart.pie.fill", .blue, .composition),
            ("Geographic Exposure", "Chart • Composition", "country map region donut pie composition", "globe", .blue, .composition),
            ("Sector Allocation", "Chart • Composition", "industry donut pie composition", "chart.pie.fill", .orange, .composition),
            ("Market Cap Allocation", "Chart • Composition", "size mega large mid donut pie composition", "chart.pie.fill", .purple, .composition),
            ("Currency Exposure", "Chart • Composition", "fx forex exchange rate donut pie composition", "dollarsign.circle.fill", .green, .composition),
            ("Estimated Asset Correlation", "Chart • Composition", "matrix heatmap diversification risk composition", "square.grid.3x3.fill", .gray, .composition),
            ("Avg Cost vs Current Price", "Chart • Composition", "pru compare bar chart composition", "chart.bar.fill", .blue, .composition),
            ("Return on Investment (P/L)", "Chart • Composition", "roi combo line bar performance composition", "chart.xyaxis.line", .green, .composition),
            ("Portfolio Weight vs Unrealized Performance", "Chart • Composition", "scatter plot bubble risk reward composition", "circle.grid.2x2.fill", .indigo, .composition),
            ("Capital Status (Profit vs Underwater)", "Chart • Composition", "health deployed donut pie composition", "chart.pie.fill", .red, .composition),
            ("Performance Heatmap", "Chart • Composition", "treemap square map intense composition", "squareshape.split.3x3", .green, .composition),
            ("Daily P/L by Holding Period", "Chart • Composition", "daily return bar chart time composition", "chart.bar.fill", .teal, .composition),
            
            // ================= FUNDAMENTALS =================
            ("Tracked Criteria", "Dashboard Metric • Fundamentals", "count number metrics screener fundamentals", "checklist", .blue, .fundamentals),
            ("Stocks Analyzed", "Dashboard Metric • Fundamentals", "analyzed companies screener fundamentals", "magnifyingglass", .indigo, .fundamentals),
            ("Avg Portfolio Quality", "Dashboard Metric • Fundamentals", "average score points screener fundamentals", "star.fill", .orange, .fundamentals),
            ("Avg Quality Score (%)", "Dashboard Metric • Fundamentals", "average percent screener fundamentals", "percent", .green, .fundamentals),
            ("Top Quality Stock", "Dashboard Metric • Fundamentals", "best rank winner screener fundamentals", "trophy.fill", .yellow, .fundamentals),
            ("Top Stock Score", "Dashboard Metric • Fundamentals", "best highest score points screener fundamentals", "crown.fill", .purple, .fundamentals),
            ("Strongest Section", "Dashboard Metric • Fundamentals", "best category strength screener fundamentals", "arrow.up.right.circle.fill", .green, .fundamentals),
            ("Weakest Section", "Dashboard Metric • Fundamentals", "worst category weakness screener fundamentals", "arrow.down.right.circle.fill", .red, .fundamentals),
            ("Screener Data", "Data Table • Fundamentals", "spreadsheet table matrix metrics fundamentals", "tablecells.fill", .gray, .fundamentals),
            ("Quality Score Comparison", "Chart • Fundamentals", "rank bar chart score fundamentals", "chart.bar.fill", .blue, .fundamentals),
            ("Score Composition Profile", "Chart • Fundamentals", "stacked bar segments categories fundamentals", "chart.bar.fill", .purple, .fundamentals),
            ("Quality Matrix (Score vs Weight)", "Chart • Fundamentals", "scatter plot bubble risk fundamentals", "circle.grid.2x2.fill", .indigo, .fundamentals),
            ("Stock Quality by Segment (%)", "Chart • Fundamentals", "line chart category comparison fundamentals", "chart.xyaxis.line", .teal, .fundamentals),
            ("Weighted Portfolio Scorecard", "Chart • Fundamentals", "polar area radar pie chart fundamentals", "chart.pie.fill", .orange, .fundamentals),
            ("Stock Radar Profiles", "Chart • Fundamentals", "spider web polygon radar fundamentals", "hexagon.fill", .mint, .fundamentals),

            // ================= GROWTH =================
            ("Current Wallet Value", "Dashboard Metric • Growth", "total portfolio balance growth", "banknote.fill", .green, .growth),
            ("Total Invested", "Dashboard Metric • Growth", "deposits capital out of pocket growth", "arrow.down.circle.fill", .blue, .growth),
            ("All-Time Return", "Dashboard Metric • Growth", "total gain profit loss growth", "chart.line.uptrend.xyaxis", .green, .growth),
            ("Best Year Return", "Dashboard Metric • Growth", "highest gain maximum growth", "trophy.fill", .yellow, .growth),
            ("Avg. Return / Year (\(sym))", "Dashboard Metric • Growth", "average absolute gain growth", "eurosign.circle.fill", .teal, .growth),
            ("Avg. Return / Year (%)", "Dashboard Metric • Growth", "average percentage gain growth", "percent", .teal, .growth),
            ("CAGR (Compound Growth)", "Dashboard Metric • Growth", "annualized return cagr growth", "arrow.up.right.circle.fill", .blue, .growth),
            ("Active Years Tracked", "Dashboard Metric • Growth", "time horizon duration years growth", "clock.fill", .gray, .growth),
            ("Annual Return Goal", "Target Tracking • Growth", "target bar progress growth", "target", .purple, .growth),
            ("Capital Growth History", "Data Table • Growth", "spreadsheet ledger history table growth", "tablecells.fill", .gray, .growth),
            ("Cash vs Stocks", "Chart • Growth", "allocation donut pie dry powder growth", "chart.pie.fill", .blue, .growth),
            ("Value Source", "Chart • Growth", "invested gain donut pie growth", "chart.pie.fill", .green, .growth),
            ("Gains Source", "Chart • Growth", "capital appreciation dividends donut pie growth", "chart.pie.fill", .mint, .growth),
            ("Annual Returns", "Chart • Growth", "yearly performance combo bar line growth", "chart.bar.fill", .blue, .growth),
            ("Invested vs Portfolio Value", "Chart • Growth", "area line comparison compounding growth", "chart.xyaxis.line", .blue, .growth),
            ("Wealth Accumulation Waterfall", "Chart • Growth", "bridge cascade bar step growth", "chart.bar.xaxis", .blue, .growth),
            ("MoIC Trend (Money on Money)", "Chart • Growth", "multiple ratio line chart growth", "chart.xyaxis.line", .purple, .growth),
            ("The Tipping Point (Effort vs Market) • Growth", "Chart", "effort market return bar chart growth", "chart.bar.fill", .orange, .growth),
            ("The Compounding Stack (100%)", "Chart • Growth", "principal gains stacked bar percent growth", "chart.bar.fill", .indigo, .growth),

            // ================= DIVIDENDS =================
            ("Total Received (All Time)", "Dashboard Metric • Dividends", "all time total collected income dividends", "banknote.fill", .green, .dividends),
            ("Received This Year", "Dashboard Metric • Dividends", "ytd year to date collected income dividends", "banknote.fill", .green, .dividends),
            ("Received This Month", "Dashboard Metric • Dividends", "mtd month to date collected income dividends", "banknote.fill", .green, .dividends),
            ("Avg. Monthly (This Year)", "Dashboard Metric • Dividends", "average monthly income dividends", "calendar", .blue, .dividends),
            ("Best Year", "Dashboard Metric • Dividends", "record highest year income dividends", "trophy.fill", .yellow, .dividends),
            ("YoY Growth (vs Last Year)", "Dashboard Metric • Dividends", "year over year growth percentage dividends", "arrow.up.right.circle.fill", .green, .dividends),
            ("Projected Annual Yield", "Dashboard Metric • Dividends", "yield percentage portfolio dividends", "percent", .purple, .dividends),
            ("Projected Annual Income", "Dashboard Metric • Dividends", "expected yearly forward income dividends", "banknote.fill", .green, .dividends),
            ("Dividend Goal", "Target Tracking • Dividends", "target bar progress expected dividends", "target", .purple, .dividends),
            ("This Month Tracker", "Interactive Tool • Dividends", "current month expected received payouts donut dividends", "clock.fill", .orange, .dividends),
            ("Manual Dividend Received Tracker", "Data Table • Dividends", "spreadsheet ledger history table manual dividends", "tablecells.fill", .gray, .dividends),
            ("Expected Monthly Income (Net vs Gross)", "Chart • Dividends", "forward projection bar chart dividends", "chart.bar.fill", .green, .dividends),
            ("Current Stock Yield (by Ticker)", "Chart • Dividends", "yield line chart percentage dividends", "chart.xyaxis.line", .purple, .dividends),
            ("Spreadsheet: Received This Year", "Chart • Dividends", "monthly bar chart history dividends", "chart.bar.fill", .orange, .dividends),
            ("Spreadsheet: Annual Received History", "Chart • Dividends", "yearly bar chart history dividends", "chart.bar.fill", .green, .dividends),
            ("Total Dividends by Position", "Chart • Dividends", "allocation donut pie chart dividends", "chart.pie.fill", .blue, .dividends),
            ("Yield On Cost (YOC)", "Chart • Dividends", "yoc return bar chart dividends", "percent", .purple, .dividends),
            ("All-Time Dividend History & Trend", "Chart • Dividends", "area line chart trendline snowball dividends", "chart.line.uptrend.xyaxis", .green, .dividends),
            ("Dividend Calendar Heatmap", "Chart • Dividends", "months schedule payment heatmap dividends", "calendar", .red, .dividends),
            ("Cumulative Monthly Seasonality", "Chart • Dividends", "seasonality months aggregate bar chart dividends", "chart.bar.fill", .orange, .dividends),
            ("Dividend Growth Rate (YoY DGR)", "Chart • Dividends", "dgr growth year over year line area dividends", "chart.xyaxis.line", .green, .dividends),

            // ================= VALUATION =================
            ("Valuated Stocks", "Dashboard Metric • Valuation", "count tracked analyzed valuation", "checklist", .blue, .valuation),
            ("Undervalued (Fair Price)", "Dashboard Metric • Valuation", "cheap discount margin of safety mos valuation", "arrow.down.right.circle.fill", .green, .valuation),
            ("Avg. Fair Price Upside", "Dashboard Metric • Valuation", "potential return discount valuation", "arrow.up.right.circle.fill", .green, .valuation),
            ("Avg. Historical PE Upside", "Dashboard Metric • Valuation", "pe reversion mean historical valuation", "clock.fill", .teal, .valuation),
            ("Avg. Current PE", "Dashboard Metric • Valuation", "price earnings multiple valuation", "number.circle.fill", .purple, .valuation),
            ("Avg. Forward PE", "Dashboard Metric • Valuation", "future price earnings multiple valuation", "number.circle.fill", .indigo, .valuation),
            ("Avg. 10Y Historical PE", "Dashboard Metric • Valuation", "past price earnings multiple valuation", "clock.arrow.circlepath", .gray, .valuation),
            ("Avg. Portfolio PEG", "Dashboard Metric • Valuation", "price earnings growth garp valuation", "chart.line.uptrend.xyaxis", .orange, .valuation),
            ("Global Margin of Safety", "Risk Parameter • Valuation", "mos discount slider valuation", "shield.fill", .teal, .valuation),
            ("Configure Global Data Links", "Settings • Valuation", "url gurufocus tipranks valuation", "link", .gray, .valuation),
            ("Price Valuation Models", "Data Table • Valuation", "fair price target gurufocus tipranks table spreadsheet valuation", "tablecells.fill", .gray, .valuation),
            ("Multiples & Yields", "Data Table • Valuation", "pe peg fcf earnings yield table spreadsheet valuation", "tablecells.fill", .gray, .valuation),
            ("Price vs Analyst Consensus", "Chart • Valuation", "gurufocus tipranks target bar valuation", "chart.bar.fill", .teal, .valuation),
            ("Historical PE Valuation Gauge", "Chart • Valuation", "bullet current forward average valuation", "chart.bar.xaxis", .blue, .valuation),
            ("Yield Barometer (Earnings vs Cash)", "Chart • Valuation", "earnings fcf cash yield bar valuation", "chart.bar.fill", .green, .valuation),
            ("Quality Matrix (Cash vs Accounting)", "Chart • Valuation", "cash earnings fcf scatter matrix valuation", "square.grid.2x2.fill", .indigo, .valuation),
            ("PEG Ratio Matrix (Price vs Growth)", "Chart • Valuation", "price growth garp scatter peg valuation", "chart.xyaxis.line", .orange, .valuation),
            ("Portfolio Discount Heatmap", "Chart • Valuation", "treemap undervalued fair price upside valuation", "squareshape.split.3x3", .red, .valuation),
            ("Current vs Target Price", "Chart • Valuation", "line difference gap upside valuation", "chart.xyaxis.line", .purple, .valuation),
            ("Valuation Range Distribution", "Chart • Valuation", "donut pie deep value fairly overvalued valuation", "chart.pie.fill", .blue, .valuation),

            // ================= PROJECTION =================
            ("Current Portfolio Value", "Dashboard Metric • Projection", "starting capital amount projection", "banknote.fill", .blue, .projection),
            ("Projected Value", "Dashboard Metric • Projection", "future terminal target value projection", "chart.line.uptrend.xyaxis", .green, .projection),
            ("Portfolio CAGR Used", "Dashboard Metric • Projection", "compound annual growth rate projection", "arrow.up.right.circle.fill", .orange, .projection),
            ("Projected Capital Gain", "Dashboard Metric • Projection", "future profit gain projection", "plus.circle.fill", .teal, .projection),
            ("Current Annual Div.", "Dashboard Metric • Projection", "starting dividend income projection", "banknote", .purple, .projection),
            ("Projected Div.", "Dashboard Metric • Projection", "future dividend income projection", "calendar.badge.plus", .indigo, .projection),
            ("Weighted 5Y Div Growth", "Dashboard Metric • Projection", "dgr dividend growth rate projection", "chart.line.uptrend.xyaxis", .mint, .projection),
            ("Projected Monthly Div.", "Dashboard Metric • Projection", "future monthly income projection", "calendar", .blue, .projection),
            ("Time Horizon", "Projection Parameter • Projection", "years slider duration future projection", "slider.horizontal.3", .blue, .projection),
            ("Annual Capital CAGR (%)", "Projection Parameter • Projection", "custom growth rate percentage projection", "percent", .orange, .projection),
            ("Dividend Growth 5Y (%)", "Projection Parameter • Projection", "custom dgr dividend growth percentage projection", "percent", .mint, .projection),
            ("Monthly Contributions", "Projection Parameter • Projection", "savings deposits cash injection projection", "plus.forwardslash.minus", .green, .projection),
            ("DRIP (Reinvest Dividends)", "Projection Parameter • Projection", "drip snowball compound reinvest projection", "arrow.3.trianglepath", .purple, .projection),
            ("Adjust for Inflation", "Projection Parameter • Projection", "real purchasing power nominal cpi projection", "arrow.down.right.circle.fill", .red, .projection),
            ("Year-by-Year Projection Schedule", "Data Table • Projection", "amortization schedule table timeline projection", "tablecells.fill", .gray, .projection),
            ("Portfolio Capital Growth", "Chart • Projection", "future value area chart compounding projection", "chart.xyaxis.line", .blue, .projection),
            ("Annual Dividend Income Growth", "Chart • Projection", "future income bar chart projection", "chart.bar.fill", .green, .projection),
            ("Total Cumulative Dividends Collected", "Chart • Projection", "sum total cash snowball area chart projection", "chart.xyaxis.line", .purple, .projection),
            ("Projected Yield On Cost (YOC)", "Chart • Projection", "yoc future yield line chart projection", "percent", .orange, .projection),

            // ================= SIMULATION =================
            ("Current Portfolio Value", "Dashboard Metric • Simulation", "real actual total value simulation", "banknote.fill", .blue, .simulation),
            ("Simulated Portfolio Value", "Dashboard Metric • Simulation", "fake test sandbox total value simulation", "banknote.fill", .purple, .simulation),
            ("Current Cash", "Dashboard Metric • Simulation", "real actual liquidity dry powder simulation", "eurosign.circle.fill", .green, .simulation),
            ("Simulated Cash", "Dashboard Metric • Simulation", "fake test sandbox liquidity dry powder simulation", "eurosign.circle.fill", .mint, .simulation),
            ("Current Annual Div.", "Dashboard Metric • Simulation", "real actual dividend income simulation", "banknote", .orange, .simulation),
            ("Simulated Annual Div.", "Dashboard Metric • Simulation", "fake test sandbox dividend income simulation", "banknote", .yellow, .simulation),
            ("Current Total Yield", "Dashboard Metric • Simulation", "real actual percentage yield simulation", "percent", .teal, .simulation),
            ("Simulated Total Yield", "Dashboard Metric • Simulation", "fake test sandbox percentage yield simulation", "percent", .cyan, .simulation),
            ("Sandbox Actions Log", "Sandbox Tool • Simulation", "undo history changes log line by line simulation", "list.bullet.rectangle", .gray, .simulation),
            ("Current Portfolio", "Data Table • Simulation", "real actual holdings list table simulation", "tablecells.fill", .gray, .simulation),
            ("Simulated Sandbox", "Sandbox Tool • Simulation", "fake test holdings list table what if rebalance simulation", "slider.horizontal.3", .mint, .simulation),
            ("Current Weight by Position", "Chart • Simulation", "real actual allocation donut pie simulation", "chart.pie.fill", .blue, .simulation),
            ("Simulated Weight by Position", "Chart • Simulation", "fake test sandbox allocation donut pie simulation", "chart.pie.fill", .purple, .simulation),
            ("Current Sector Allocation", "Chart • Simulation", "real actual industry donut pie simulation", "chart.pie.fill", .orange, .simulation),
            ("Simulated Sector Allocation", "Chart • Simulation", "fake test sandbox industry donut pie simulation", "chart.pie.fill", .yellow, .simulation),
            ("Total Value Comparison", "Chart • Simulation", "compare bar chart difference impact simulation", "chart.bar.fill", .indigo, .simulation),
            ("Portfolio Yield Impact", "Chart • Simulation", "compare yield bar chart difference simulation", "chart.bar.fill", .teal, .simulation),
            ("Simulated Cash Investments", "Chart • Simulation", "deployment dry powder donut pie simulation", "chart.pie.fill", .green, .simulation),
            ("Simulated Dividends by Position", "Chart • Simulation", "fake test income payout donut pie simulation", "chart.pie.fill", .mint, .simulation),
            
            // ================= WATCHLIST =================
            ("Watchlist Companies", "Dashboard Metric • Watchlist", "count tracked prospective watchlist", "eye.fill", .cyan, .watchlist),
            ("Undervalued (Fair Price)", "Dashboard Metric • Watchlist", "cheap discount margin of safety mos watchlist", "arrow.down.right.circle.fill", .green, .watchlist),
            ("Avg. Target Upside", "Dashboard Metric • Watchlist", "potential return discount watchlist", "arrow.up.right.circle.fill", .teal, .watchlist),
            ("Avg. Watchlist PEG", "Dashboard Metric • Watchlist", "price earnings growth garp watchlist", "chart.line.uptrend.xyaxis", .orange, .watchlist),
            ("Avg. Current PE", "Dashboard Metric • Watchlist", "price earnings multiple watchlist", "number.circle.fill", .purple, .watchlist),
            ("Avg. Forward PE", "Dashboard Metric • Watchlist", "future price earnings multiple watchlist", "number.circle.fill", .indigo, .watchlist),
            ("PEG ≤ 1.0 (Bargains)", "Dashboard Metric • Watchlist", "cheap garp deep value watchlist", "star.fill", .yellow, .watchlist),
            ("Top Pick (Fair Price)", "Dashboard Metric • Watchlist", "best highest upside crown watchlist", "crown.fill", .yellow, .watchlist),
            ("Watchlist Margin of Safety", "Risk Parameter • Watchlist", "mos discount slider watchlist", "shield.fill", .teal, .watchlist),
            ("Watchlist Valuation Table", "Data Table • Watchlist", "fair price target multiples spreadsheet watchlist", "tablecells.fill", .gray, .watchlist),
            ("Quality Analysis Laboratory", "Analysis Tool • Watchlist", "strengths weaknesses compare test due diligence watchlist", "testtube.2", .purple, .watchlist),
            ("Valuation & Target Prices Comparison", "Chart • Watchlist", "gurufocus tipranks target bar watchlist", "chart.bar.fill", .blue, .watchlist),
            ("PE Valuation (Current vs Fwd vs 10Y)", "Chart • Watchlist", "multiple comparison bar watchlist", "chart.bar.fill", .indigo, .watchlist),
            ("PEG Ratio (PEG < 1.0 = Undervalued)", "Chart • Watchlist", "price growth garp bar watchlist", "chart.bar.fill", .orange, .watchlist),
            ("Potential Upside % (Target vs Fair Price)", "Chart • Watchlist", "discount potential bar watchlist", "chart.bar.fill", .green, .watchlist),
            ("Analyzed Stock vs Portfolio Avg", "Chart • Watchlist", "quality score comparison laboratory watchlist", "chart.bar.fill", .purple, .watchlist),
            ("Stock Radar Profiles", "Chart • Watchlist", "spider web polygon radar laboratory watchlist", "hexagon.fill", .mint, .watchlist),
            
            // ================= EXPOSURE =================
            ("Weighted USA Exposure", "Dashboard Metric • Exposure", "america united states domestic revenue exposure", "star.fill", .blue, .exposure),
            ("Weighted ROW Exposure", "Dashboard Metric • Exposure", "rest of world international foreign revenue exposure", "globe.europe.africa.fill", .green, .exposure),
            ("Unassigned Revenue", "Dashboard Metric • Exposure", "unknown unmapped missing data exposure", "questionmark.circle.fill", .gray, .exposure),
            ("Primary Market Target", "Dashboard Metric • Exposure", "dominant main market focus exposure", "chart.bar.fill", .indigo, .exposure),
            ("Total Regions Tracked", "Dashboard Metric • Exposure", "countries geographic areas count exposure", "map.fill", .orange, .exposure),
            ("Fully Mapped Stocks", "Dashboard Metric • Exposure", "data quality completeness exposure", "checkmark.seal.fill", .teal, .exposure),
            ("Max Single-Region Focus", "Dashboard Metric • Exposure", "concentration risk highest region exposure", "exclamationmark.triangle.fill", .red, .exposure),
            ("Est. FX Risk (Non-USA)", "Dashboard Metric • Exposure", "currency foreign exchange risk exposure", "dollarsign.arrow.circlepath", .purple, .exposure),
            ("Top Dominant Markets", "Ranking List • Exposure", "highest regions countries top 5 list exposure", "list.number", .blue, .exposure),
            ("FX Risk Matrix (Currency Exposure)", "Risk Assessment • Exposure", "currency foreign exchange bars exposure", "dollarsign.circle.fill", .green, .exposure),
            ("Revenue Segmentation by Stock", "Data Table • Exposure", "spreadsheet matrix regions known percent exposure", "tablecells.fill", .gray, .exposure),
            ("Weighted Portfolio Exposure (USA vs ROW)", "Chart • Exposure", "donut pie domestic international exposure", "chart.pie.fill", .blue, .exposure),
            ("Detailed Geographic Breakdown by Stock", "Chart • Exposure", "stacked bar regions stocks exposure", "chart.bar.fill", .purple, .exposure),
            ("Global Exposure Heatmap (Treemap)", "Chart • Exposure", "treemap square map regions exposure", "squareshape.split.3x3", .orange, .exposure),
            ("Sector × Geography Risk Matrix", "Chart • Exposure", "heatmap risk concentration sector exposure", "square.grid.3x3.fill", .red, .exposure),
            
            /// ================= TRANSACTIONS =================
            ("Total Deposited", "Dashboard Metric • Transactions", "cash in deposit add funds transactions", "arrow.down.circle.fill", .green, .transactions),
            ("Total Withdrawn", "Dashboard Metric • Transactions", "cash out withdraw funds transactions", "arrow.up.circle.fill", .red, .transactions),
            ("Net Cash Flow", "Dashboard Metric • Transactions", "cash balance in out transactions", "arrow.left.arrow.right.circle.fill", .blue, .transactions),
            ("Total Invested", "Dashboard Metric • Transactions", "bought buy spend invested transactions", "cart.fill", .blue, .transactions),
            ("Total Sold", "Dashboard Metric • Transactions", "sold sell revenue transactions", "tag.fill", .orange, .transactions),
            ("Net Invested", "Dashboard Metric • Transactions", "net bought sold transactions", "chart.pie.fill", .purple, .transactions),
            ("Total Fees & Taxes", "Dashboard Metric • Transactions", "cost friction drag taxes broker state transactions", "exclamationmark.triangle.fill", .red, .transactions),
            ("Transactions Found", "Dashboard Metric • Transactions", "count total history logged transactions", "number.circle.fill", .gray, .transactions),
            ("Transactions Goal", "Target Tracking • Transactions", "goal bar target logged history transactions", "target", .purple, .transactions),
            ("Transaction History", "Data Table • Transactions", "history ledger list spreadsheet log transactions", "tablecells.fill", .gray, .transactions),
            ("Yearly Summary", "Data Table • Transactions", "annual aggregate summary table history transactions", "calendar", .blue, .transactions),
            ("Transactions per Year", "Chart • Transactions", "yearly count volume bar chart transactions", "chart.bar.fill", .blue, .transactions),
            ("Summary by Type", "Chart • Transactions", "type buy sell deposit withdraw combo chart transactions", "chart.xyaxis.line", .purple, .transactions),
            ("Buys over Time", "Chart • Transactions", "timeline purchases chronological bar trend transactions", "chart.bar.xaxis", .green, .transactions),
            ("Fees & Taxes Breakdown", "Chart • Transactions", "cost taxes broker state donut pie chart transactions", "chart.pie.fill", .red, .transactions),
            ("Deployed Capital Allocation", "Chart • Transactions", "cumulative donut pie chart spent allocation transactions", "chart.pie.fill", .blue, .transactions),
            ("Days Held per Asset", "Chart • Transactions", "holding period time days bar chart transactions", "chart.bar.xaxis", .purple, .transactions),
            ("Trade Balance (Buys vs Sells)", "Chart • Transactions", "diverging bar chart buys sells balance transactions", "chart.bar.fill", .orange, .transactions),
            ("Cumulative Capital Injected", "Chart • Transactions", "area chart dry powder deposits withdrawals transactions", "chart.xyaxis.line", .green, .transactions),
            ("Tax Drag Index (Fees / Volume)", "Chart • Transactions", "line chart fees volume percentage friction transactions", "chart.xyaxis.line", .red, .transactions),
            ("Activity Heatmap", "Chart • Transactions", "matrix squares treemap frequency months years transactions", "squareshape.split.3x3", .blue, .transactions),
            
            // ================= BENCHMARK =================
            ("Portfolio Return", "Dashboard Metric • Benchmark", "current year ytd performance benchmark", "chart.line.uptrend.xyaxis", .green, .benchmark),
            ("Portfolio Avg. Return", "Dashboard Metric • Benchmark", "average historical performance benchmark", "percent", .blue, .benchmark),
            ("Best Index (Avg.)", "Dashboard Metric • Benchmark", "top performing market index benchmark", "trophy.fill", .yellow, .benchmark),
            ("vs Best Index (Avg.)", "Dashboard Metric • Benchmark", "alpha ahead behind outperformance benchmark", "arrow.up.right.circle.fill", .green, .benchmark),
            ("Indices Tracked", "Dashboard Metric • Benchmark", "count markets tracked benchmark", "list.number", .gray, .benchmark),
            ("Years Tracked", "Dashboard Metric • Benchmark", "duration time horizon benchmark", "clock.fill", .gray, .benchmark),
            ("Portfolio 10k\(sym) Simulation", "Dashboard Metric • Benchmark", "simulated wealth compounding benchmark", "banknote.fill", .blue, .benchmark),
            ("Best Index 10k\(sym)", "Dashboard Metric • Benchmark", "simulated index wealth opportunity cost benchmark", "banknote", .purple, .benchmark),
            ("Alpha Goal", "Target Tracking • Benchmark", "outperform best index alpha target benchmark", "target", .purple, .benchmark),
            ("Performance Comparison", "Data Table • Benchmark", "annual returns list spreadsheet index benchmark", "tablecells.fill", .gray, .benchmark),
            ("Annual Return (%)", "Chart • Benchmark", "yearly comparison bar chart benchmark", "chart.bar.fill", .blue, .benchmark),
            ("\(sym)10,000 Simulated Growth", "Chart • Benchmark", "compounding opportunity cost line chart benchmark", "chart.xyaxis.line", .purple, .benchmark),
            
            // ================= CALENDAR =================
            ("Next Upcoming Events", "Dashboard Section • Calendar", "schedule timeline upcoming agenda calendar", "bell.fill", .blue, .calendar),
            ("Investor Calendar", "App Page • Calendar", "schedule dates events market closed calendar", "calendar", .red, .calendar),
            
            // ================= WEALTH =================
            ("True Net Worth", "Dashboard Metric • Wealth", "total balance sheet equity wealth", "building.columns.fill", .green, .wealth),
            ("Total Assets", "Dashboard Metric • Wealth", "gross capital holdings wealth", "plus.circle.fill", .blue, .wealth),
            ("Total Liabilities", "Dashboard Metric • Wealth", "debt loans borrowed owed wealth", "minus.circle.fill", .red, .wealth),
            ("Net P/L (Assets)", "Dashboard Metric • Wealth", "profit loss gain return wealth", "arrow.up.right.circle.fill", .green, .wealth),
            ("Wealth Goal", "Dashboard Metric • Wealth", "target milestone objective wealth", "star.fill", .yellow, .wealth),
            ("Overall Assets ROI", "Dashboard Metric • Wealth", "return on investment percentage wealth", "percent", .teal, .wealth),
            ("Debt-to-Asset Ratio", "Dashboard Metric • Wealth", "leverage risk ratio wealth", "exclamationmark.triangle.fill", .orange, .wealth),
            ("Brokerage Weight", "Dashboard Metric • Wealth", "stock market percentage wealth", "chart.pie.fill", .purple, .wealth),
            ("Net Worth Goal Progress", "Target Tracking • Wealth", "goal bar target progress wealth", "target", .purple, .wealth),
            ("Assets Allocation Ledger", "Data Table • Wealth", "real estate crypto savings list table wealth", "tablecells.fill", .blue, .wealth),
            ("Liabilities & Debts Ledger", "Data Table • Wealth", "mortgage loan credit list table wealth", "tablecells.fill", .red, .wealth),
            ("FIRE Simulator", "Analysis Tool • Wealth", "financial independence retire early passive income swr wealth", "flame.fill", .orange, .wealth),
            ("Assets Allocation (Macro)", "Chart • Wealth", "distribution donut pie chart wealth", "chart.pie.fill", .blue, .wealth),
            ("Return on Investment (ROI % by Asset)", "Chart • Wealth", "roi performance bar chart wealth", "chart.bar.fill", .green, .wealth),
            
            // ================= THESIS / CONVICTIONS =================
            ("Thesis Notes Tracker", "Dashboard Section • Thesis", "timeline events logs news alerts", "bolt.horizontal.fill", .orange, .thesis),
            ("Positions Core Convictions", "Dashboard Section • Thesis", "positions breakdown deep dive companies", "shield.fill", .purple, .thesis),
            ("Conviction Status", "Target Tracking • Thesis", "rating score confidence intact broken review", "circle.fill", .green, .thesis),
            ("Business Anatomy", "Analysis Tool • Thesis", "company structure management market customers", "building.2.fill", .blue, .thesis),
            ("Competitive Advantage", "Analysis Tool • Thesis", "moat network effect switching costs scale", "lock.shield.fill", .indigo, .thesis),
            ("Bear Case Threats", "Analysis Tool • Thesis", "risks dangers threats downside", "exclamationmark.triangle.fill", .orange, .thesis),
            ("Exit Strategy", "Analysis Tool • Thesis", "sell rules conditions target exit", "door.right.hand.open", .red, .thesis),
            ("Post-Mortem Lessons", "Analysis Tool • Thesis", "sold archive learning history", "brain.head.profile", .purple, .thesis),
            
            
        ]
        
        // --- 1. PAGES DE L'APPLICATION ---
        for tab in AppTab.allCases {
            if matchesQuery(tab.rawValue) {
                results.append(SearchResult(title: tab.rawValue, subtitle: "App Page", icon: "macwindow", color: .blue, tab: tab))
            }
        }
        
        for item in uiElements {
            let searchableText = "\(item.title) \(item.subtitle) \(item.keywords)"
            if matchesQuery(searchableText) {
                results.append(SearchResult(title: item.title, subtitle: item.subtitle, icon: item.icon, color: item.color, tab: item.tab))
            }
        }
        
        // --- 2. POSITIONS (TICKERS & COMPAGNIES) ---
        for pos in viewModel.positions {
            let searchableText = "\(pos.ticker) \(pos.companyName) \(pos.sector) \(pos.country)"
            if matchesQuery(searchableText) {
                results.append(SearchResult(title: pos.ticker, subtitle: "Position • \(pos.companyName)", icon: "briefcase.fill", color: .indigo, tab: .composition))
            }
        }
        
        // --- 3. WATCHLIST (TICKERS & COMPAGNIES) ---
        for item in viewModel.watchlistItems {
            let searchableText = "\(item.ticker) \(item.ticker)"
            if matchesQuery(searchableText) {
                results.append(SearchResult(title: item.ticker, subtitle: "Watchlist • \(item.ticker)", icon: "eye.fill", color: .cyan, tab: .watchlist))
            }
        }
        
        // --- 4. TRANSACTIONS ---
        for tx in viewModel.transactions {
            let searchableText = "\(tx.type.rawValue) \(tx.ticker.isEmpty ? "Cash" : tx.ticker) \(tx.note)"
            if matchesQuery(searchableText) || matchDate(tx.date) {
                results.append(SearchResult(title: "\(tx.type.rawValue) \(tx.ticker.isEmpty ? "Cash" : tx.ticker)", subtitle: "Transaction • \(dfText.string(from: tx.date))", icon: "arrow.left.arrow.right", color: .orange, tab: .transactions))
            }
        }
        
        // --- 5. CALENDRIER ---
        let currentYear = Calendar.current.component(.year, from: Date())
        var allSearchableEvents = viewModel.calendarEvents
        
        for year in [currentYear, currentYear + 1] {
            for month in [3, 6, 9, 12] {
                if let witchingDate = USMarketHolidayHelper.nthWeekday(nth: 3, weekday: 6, month: month, year: year) {
                    allSearchableEvents.append(CalendarEvent(id: UUID(), date: witchingDate, type: .macro, ticker: "MARKET", note: "Quadruple Witching Day (Options & Futures Expiration)"))
                }
            }
        }
        
        for pos in viewModel.positions {
            let pYear = Calendar.current.component(.year, from: pos.purchaseDate)
            let yearsHeld = currentYear - pYear
            if yearsHeld > 0 {
                var comps = Calendar.current.dateComponents([.month, .day], from: pos.purchaseDate)
                comps.year = currentYear
                if let annivDate = Calendar.current.date(from: comps) {
                    allSearchableEvents.append(CalendarEvent(id: UUID(), date: annivDate, type: .anniversary, ticker: pos.ticker, note: "Holding for \(yearsHeld) Years"))
                }
            }
        }
        
        for ev in allSearchableEvents {
            let searchableText = "\(ev.type.rawValue) \(ev.ticker) \(ev.note)"
            if matchesQuery(searchableText) || matchDate(ev.date) {
                results.append(SearchResult(
                    title: "\(ev.type.rawValue) \(ev.ticker)",
                    subtitle: "Event • \(dfText.string(from: ev.date))",
                    icon: "calendar",
                    color: .red,
                    tab: .calendar
                ))
            }
        }
        
        let marketHolidays = USMarketHolidayHelper.getHolidays(forYear: currentYear) + USMarketHolidayHelper.getHolidays(forYear: currentYear + 1)
        for holiday in marketHolidays {
            let searchableText = "Market Closed Holiday \(holiday.name)"
            if matchesQuery(searchableText) || matchDate(holiday.date) {
                results.append(SearchResult(
                    title: "Market Closed",
                    subtitle: "\(holiday.name) • \(dfText.string(from: holiday.date))",
                    icon: "lock.fill",
                    color: .red,
                    tab: .calendar
                ))
            }
        }

        // --- 6. CRITÈRES FONDAMENTAUX ---
        for crit in viewModel.fundamentalCriteria {
            let searchableText = "\(crit.name) \(crit.section)"
            if matchesQuery(searchableText) {
                results.append(SearchResult(title: crit.name, subtitle: "Screener Criterion • \(crit.section)", icon: "building.2.fill", color: .teal, tab: .fundamentals))
            }
        }
        
        // --- 7. INDICES BENCHMARK ---
        for idx in viewModel.benchmarkIndices {
            if matchesQuery(idx.name) {
                results.append(SearchResult(title: idx.name, subtitle: "Benchmark Index", icon: "chart.bar.xaxis", color: .purple, tab: .benchmark))
            }
        }
        
        // --- 8. PATRIMOINE (WEALTH ASSETS & LIABILITIES) ---
        for asset in viewModel.allWealthAssets {
            if matchesQuery(asset.name) {
                results.append(SearchResult(title: asset.name, subtitle: "Wealth Asset", icon: "house.fill", color: .mint, tab: .wealth))
            }
        }
        
        for liab in viewModel.manualWealthLiabilities {
            if matchesQuery(liab.name) {
                results.append(SearchResult(title: liab.name, subtitle: "Wealth Liability", icon: "creditcard.fill", color: .red, tab: .wealth))
            }
        }
        
        return results
    }

    // --- FONCTIONS DE NAVIGATION CLAVIER ---
    private func executeSelection() {
        if let currentID = selectedResultID, let result = searchResults.first(where: { $0.id == currentID }) {
            selectedTab = result.tab
            dismiss()
        }
    }
    
    private func moveSelection(direction: Int) {
        let results = searchResults
        guard !results.isEmpty else { return }
        
        if let currentID = selectedResultID, let currentIndex = results.firstIndex(where: { $0.id == currentID }) {
            let newIndex = currentIndex + direction
            if newIndex >= 0 && newIndex < results.count {
                selectedResultID = results[newIndex].id
            }
        } else {
            selectedResultID = results.first?.id
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Barre de recherche Spotlight
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.title)
                    .foregroundColor(.blue)
                
                TextField("Search tickers, transactions, events, pages...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.title2)
                    .focused($isFocused)
                    // 3. NOUVEAU : Interception de la touche Entrée
                    .autocorrectionDisabled()
                    .onSubmit {
                        executeSelection()
                    }
                    // 4. NOUVEAU : Interception de la flèche du bas
                    .onKeyPress(.downArrow) {
                        moveSelection(direction: 1)
                        return .handled
                    }
                    // 5. NOUVEAU : Interception de la flèche du haut
                    .onKeyPress(.upArrow) {
                        moveSelection(direction: -1)
                        return .handled
                    }
                
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(20)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            if searchText.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "text.magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("Type anything to search across your entire portfolio.")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if searchResults.isEmpty {
                Text("No results found for \"\(searchText)\".")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // 6. NOUVEAU : List(selection:) active le surlignage bleu natif de macOS !
                List(selection: $selectedResultID) {
                    ForEach(searchResults) { result in
                        HStack(spacing: 16) {
                            Circle()
                                .fill(result.color.opacity(0.2))
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Image(systemName: result.icon)
                                        .foregroundColor(result.color)
                                )
                            
                            VStack(alignment: .leading, spacing: 4) {
                                // macOS met automatiquement la couleur du texte en blanc sur fond bleu !
                                Text(result.title)
                                    .font(.headline)
                                
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(result.color)
                                        .frame(width: 6, height: 6)
                                    
                                    // Gris normalement, mais on le force en blanc si la ligne est sélectionnée
                                    Text(result.subtitle)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundColor(selectedResultID == result.id ? .white.opacity(0.8) : .secondary)
                                }
                            }

                            Spacer()
                            Image(systemName: "arrow.right")
                                .foregroundColor(selectedResultID == result.id ? .white : .secondary.opacity(0.5))
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                        .tag(result.id) // Essentiel pour que la sélection fonctionne
                        // 7. On utilise un TapGesture pour valider au clic (à la place du Button)
                        .onTapGesture {
                            selectedResultID = result.id
                            executeSelection()
                        }
                    }
                }
            }
        }
        .frame(width: 600, height: 450)
        .onAppear {
            isFocused = true
        }
        // 8. Auto-sélectionne le premier résultat à chaque fois que la recherche change
        .onChange(of: searchText) { _, _ in
            if !searchResults.isEmpty {
                selectedResultID = searchResults.first?.id
            } else {
                selectedResultID = nil
            }
        }
    }
}
