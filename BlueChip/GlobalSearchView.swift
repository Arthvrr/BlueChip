import SwiftUI

struct SearchResult: Identifiable {
    let id = UUID()
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
    
    var searchResults: [SearchResult] {
        guard !searchText.isEmpty else { return [] }
        
        // 1. DÉCOUPAGE DE LA RECHERCHE EN MOTS (Tokenized Search)
        // Permet de chercher "aapl div" ou "heatmap dividend" peu importe l'ordre des mots
        let queryWords = searchText.lowercased().split(separator: " ").map { String($0) }
        var results: [SearchResult] = []
        
        let dfText = DateFormatter()
        dfText.dateStyle = .medium
        let dfNumEU = DateFormatter()
        dfNumEU.dateFormat = "dd/MM/yyyy"
        let dfNumUS = DateFormatter()
        dfNumUS.dateFormat = "MM/dd/yyyy"
        
        // 2. MOTEUR DE CORRESPONDANCE (Vérifie que TOUS les mots tapés sont dans le texte)
        func matchesQuery(_ text: String) -> Bool {
            let lowerText = text.lowercased()
            return queryWords.allSatisfy { lowerText.contains($0) }
        }
        
        func matchDate(_ date: Date) -> Bool {
            return matchesQuery(dfText.string(from: date)) ||
                   matchesQuery(dfNumEU.string(from: date)) ||
                   matchesQuery(dfNumUS.string(from: date))
        }
        
        // --- 0. UI ELEMENTS (BASE DE DONNÉES COMPLÈTE DES GRAPHES & HEADERS) ---
        // Ajout d'un champ "keywords" invisible pour améliorer les résultats
        let uiElements: [(title: String, subtitle: String, keywords: String, icon: String, color: Color, tab: AppTab)] = [
            
            // ================= COMPOSITION =================
            
            // --- Dashboard Metrics (Top 8 Cards) ---
            ("Cash", "Dashboard Metric", "liquidity available dry powder composition", "eurosign.circle.fill", .green, .composition),
            ("Initial Investment", "Dashboard Metric", "deposits manually invested out of pocket composition", "arrow.down.circle.fill", .blue, .composition),
            ("Total (Current + Cash)", "Dashboard Metric", "total wallet value composition", "banknote.fill", .purple, .composition),
            ("Stock Value", "Dashboard Metric", "equity value composition", "chart.line.uptrend.xyaxis", .indigo, .composition),
            ("Unrealized P/L", "Dashboard Metric", "profit loss gain return composition", "arrow.up.right.circle.fill", .green, .composition),
            ("Positions", "Dashboard Metric", "stock count holdings composition", "briefcase.fill", .gray, .composition),
            ("Annual Dividends", "Dashboard Metric", "income yield cash flow composition", "banknote.fill", .orange, .composition),
            ("Total Yield", "Dashboard Metric", "portfolio yield percentage composition", "percent", .teal, .composition),
            
            // --- Goal & Table ---
            ("Goal Progress", "Target Tracking", "goal bar target composition", "target", .purple, .composition),
            ("Positions Spreadsheet", "Data Table", "holdings list table ledger composition", "tablecells.fill", .gray, .composition),
            
            // --- Charts (12 Visuals) ---
            ("Weight by Position", "Chart", "allocation donut pie composition", "chart.pie.fill", .blue, .composition),
            ("Geographic Exposure", "Chart", "country map region donut pie composition", "globe", .blue, .composition),
            ("Sector Allocation", "Chart", "industry donut pie composition", "chart.pie.fill", .orange, .composition),
            ("Market Cap Allocation", "Chart", "size mega large mid donut pie composition", "chart.pie.fill", .purple, .composition),
            ("Currency Exposure", "Chart", "fx forex exchange rate donut pie composition", "dollarsign.circle.fill", .green, .composition),
            ("Estimated Asset Correlation", "Chart", "matrix heatmap diversification risk composition", "square.grid.3x3.fill", .gray, .composition),
            ("Avg Cost vs Current Price", "Chart", "pru compare bar chart composition", "chart.bar.fill", .blue, .composition),
            ("Return on Investment (P/L)", "Chart", "roi combo line bar performance composition", "chart.xyaxis.line", .green, .composition),
            ("Portfolio Weight vs Unrealized Performance", "Chart", "scatter plot bubble risk reward composition", "circle.grid.2x2.fill", .indigo, .composition),
            ("Capital Status (Profit vs Underwater)", "Chart", "health deployed donut pie composition", "chart.pie.fill", .red, .composition),
            ("Performance Heatmap", "Chart", "treemap square map intense composition", "squareshape.split.3x3", .green, .composition),
            ("Daily P/L by Holding Period", "Chart", "daily return bar chart time composition", "chart.bar.fill", .teal, .composition),
            
            // ================= FUNDAMENTALS =================
            
            // --- Dashboard Metrics (Top 8 Cards) ---
            ("Tracked Criteria", "Dashboard Metric", "count number metrics screener fundamentals", "checklist", .blue, .fundamentals),
            ("Stocks Analyzed", "Dashboard Metric", "analyzed companies screener fundamentals", "magnifyingglass", .indigo, .fundamentals),
            ("Avg Portfolio Quality", "Dashboard Metric", "average score points screener fundamentals", "star.fill", .orange, .fundamentals),
            ("Avg Quality Score (%)", "Dashboard Metric", "average percent screener fundamentals", "percent", .green, .fundamentals),
            ("Top Quality Stock", "Dashboard Metric", "best rank winner screener fundamentals", "trophy.fill", .yellow, .fundamentals),
            ("Top Stock Score", "Dashboard Metric", "best highest score points screener fundamentals", "crown.fill", .purple, .fundamentals),
            ("Strongest Section", "Dashboard Metric", "best category strength screener fundamentals", "arrow.up.right.circle.fill", .green, .fundamentals),
            ("Weakest Section", "Dashboard Metric", "worst category weakness screener fundamentals", "arrow.down.right.circle.fill", .red, .fundamentals),
            
            // --- Screener Table ---
            ("Screener Data", "Data Table", "spreadsheet table matrix metrics fundamentals", "tablecells.fill", .gray, .fundamentals),
            
            // --- Charts (6 Visuals) ---
            ("Quality Score Comparison", "Chart", "rank bar chart score fundamentals", "chart.bar.fill", .blue, .fundamentals),
            ("Score Composition Profile", "Chart", "stacked bar segments categories fundamentals", "chart.bar.fill", .purple, .fundamentals),
            ("Quality Matrix (Score vs Weight)", "Chart", "scatter plot bubble risk fundamentals", "circle.grid.2x2.fill", .indigo, .fundamentals),
            ("Stock Quality by Segment (%)", "Chart", "line chart category comparison fundamentals", "chart.xyaxis.line", .teal, .fundamentals),
            ("Weighted Portfolio Scorecard", "Chart", "polar area radar pie chart fundamentals", "chart.pie.fill", .orange, .fundamentals),
            ("Stock Radar Profiles", "Chart", "spider web polygon radar fundamentals", "hexagon.fill", .mint, .fundamentals),

            // ================= GROWTH =================
            
            // --- Dashboard Metrics (Top 8 Cards) ---
            ("Current Wallet Value", "Dashboard Metric", "total portfolio balance growth", "banknote.fill", .green, .growth),
            ("Total Invested", "Dashboard Metric", "deposits capital out of pocket growth", "arrow.down.circle.fill", .blue, .growth),
            ("All-Time Return", "Dashboard Metric", "total gain profit loss growth", "chart.line.uptrend.xyaxis", .green, .growth),
            ("Best Year Return", "Dashboard Metric", "highest gain maximum growth", "trophy.fill", .yellow, .growth),
            ("Avg. Return / Year (€)", "Dashboard Metric", "average absolute gain growth", "eurosign.circle.fill", .teal, .growth),
            ("Avg. Return / Year (%)", "Dashboard Metric", "average percentage gain growth", "percent", .teal, .growth),
            ("CAGR (Compound Growth)", "Dashboard Metric", "annualized return cagr growth", "arrow.up.right.circle.fill", .blue, .growth),
            ("Active Years Tracked", "Dashboard Metric", "time horizon duration years growth", "clock.fill", .gray, .growth),
            
            // --- Goal & Table ---
            ("Annual Return Goal", "Target Tracking", "target bar progress growth", "target", .purple, .growth),
            ("Capital Growth History", "Data Table", "spreadsheet ledger history table growth", "tablecells.fill", .gray, .growth),
            
            // --- Charts (9 Visuals) ---
            ("Cash vs Stocks", "Chart", "allocation donut pie dry powder growth", "chart.pie.fill", .blue, .growth),
            ("Value Source", "Chart", "invested gain donut pie growth", "chart.pie.fill", .green, .growth),
            ("Gains Source", "Chart", "capital appreciation dividends donut pie growth", "chart.pie.fill", .mint, .growth),
            ("Annual Returns", "Chart", "yearly performance combo bar line growth", "chart.bar.fill", .blue, .growth),
            ("Invested vs Portfolio Value", "Chart", "area line comparison compounding growth", "chart.xyaxis.line", .blue, .growth),
            ("Wealth Accumulation Waterfall", "Chart", "bridge cascade bar step growth", "chart.bar.xaxis", .blue, .growth),
            ("MoIC Trend (Money on Money)", "Chart", "multiple ratio line chart growth", "chart.xyaxis.line", .purple, .growth),
            ("The Tipping Point (Effort vs Market)", "Chart", "effort market return bar chart growth", "chart.bar.fill", .orange, .growth),
            ("The Compounding Stack (100%)", "Chart", "principal gains stacked bar percent growth", "chart.bar.fill", .indigo, .growth),

            // ================= DIVIDENDS =================
            
            // --- Dashboard Metrics (Top 8 Cards) ---
            ("Total Received (All Time)", "Dashboard Metric", "all time total collected income dividends", "banknote.fill", .green, .dividends),
            ("Received This Year", "Dashboard Metric", "ytd year to date collected income dividends", "banknote.fill", .green, .dividends),
            ("Received This Month", "Dashboard Metric", "mtd month to date collected income dividends", "banknote.fill", .green, .dividends),
            ("Avg. Monthly (This Year)", "Dashboard Metric", "average monthly income dividends", "calendar", .blue, .dividends),
            ("Best Year", "Dashboard Metric", "record highest year income dividends", "trophy.fill", .yellow, .dividends),
            ("YoY Growth (vs Last Year)", "Dashboard Metric", "year over year growth percentage dividends", "arrow.up.right.circle.fill", .green, .dividends),
            ("Projected Annual Yield", "Dashboard Metric", "yield percentage portfolio dividends", "percent", .purple, .dividends),
            ("Projected Annual Income", "Dashboard Metric", "expected yearly forward income dividends", "banknote.fill", .green, .dividends),
            
            // --- Goals & Trackers ---
            ("Dividend Goal", "Target Tracking", "target bar progress expected dividends", "target", .purple, .dividends),
            ("This Month Tracker", "Interactive Tool", "current month expected received payouts donut dividends", "clock.fill", .orange, .dividends),
            ("Manual Dividend Received Tracker", "Data Table", "spreadsheet ledger history table manual dividends", "tablecells.fill", .gray, .dividends),
            
            // --- Charts (10 Visuals) ---
            ("Expected Monthly Income (Net vs Gross)", "Chart", "forward projection bar chart dividends", "chart.bar.fill", .green, .dividends),
            ("Current Stock Yield (by Ticker)", "Chart", "yield line chart percentage dividends", "chart.xyaxis.line", .purple, .dividends),
            ("Spreadsheet: Received This Year", "Chart", "monthly bar chart history dividends", "chart.bar.fill", .orange, .dividends),
            ("Spreadsheet: Annual Received History", "Chart", "yearly bar chart history dividends", "chart.bar.fill", .green, .dividends),
            ("Total Dividends by Position", "Chart", "allocation donut pie chart dividends", "chart.pie.fill", .blue, .dividends),
            ("Yield On Cost (YOC)", "Chart", "yoc return bar chart dividends", "percent", .purple, .dividends),
            ("All-Time Dividend History & Trend", "Chart", "area line chart trendline snowball dividends", "chart.line.uptrend.xyaxis", .green, .dividends),
            ("Dividend Calendar Heatmap", "Chart", "months schedule payment heatmap dividends", "calendar", .red, .dividends),
            ("Cumulative Monthly Seasonality", "Chart", "seasonality months aggregate bar chart dividends", "chart.bar.fill", .orange, .dividends),
            ("Dividend Growth Rate (YoY DGR)", "Chart", "dgr growth year over year line area dividends", "chart.xyaxis.line", .green, .dividends),

            // ================= VALUATION =================
            
            // --- Dashboard Metrics (Top 8 Cards) ---
            ("Valuated Stocks", "Dashboard Metric", "count tracked analyzed valuation", "checklist", .blue, .valuation),
            ("Undervalued (Fair Price)", "Dashboard Metric", "cheap discount margin of safety mos valuation", "arrow.down.right.circle.fill", .green, .valuation),
            ("Avg. Fair Price Upside", "Dashboard Metric", "potential return discount valuation", "arrow.up.right.circle.fill", .green, .valuation),
            ("Avg. Historical PE Upside", "Dashboard Metric", "pe reversion mean historical valuation", "clock.fill", .teal, .valuation),
            ("Avg. Current PE", "Dashboard Metric", "price earnings multiple valuation", "number.circle.fill", .purple, .valuation),
            ("Avg. Forward PE", "Dashboard Metric", "future price earnings multiple valuation", "number.circle.fill", .indigo, .valuation),
            ("Avg. 10Y Historical PE", "Dashboard Metric", "past price earnings multiple valuation", "clock.arrow.circlepath", .gray, .valuation),
            ("Avg. Portfolio PEG", "Dashboard Metric", "price earnings growth garp valuation", "chart.line.uptrend.xyaxis", .orange, .valuation),
            
            // --- Controls & Tables ---
            ("Global Margin of Safety", "Risk Parameter", "mos discount slider valuation", "shield.fill", .teal, .valuation),
            ("Configure Global Data Links", "Settings", "url gurufocus tipranks valuation", "link", .gray, .valuation),
            ("Price Valuation Models", "Data Table", "fair price target gurufocus tipranks table spreadsheet valuation", "tablecells.fill", .gray, .valuation),
            ("Multiples & Yields", "Data Table", "pe peg fcf earnings yield table spreadsheet valuation", "tablecells.fill", .gray, .valuation),
            
            // --- Charts (8 Visuals) ---
            ("Price vs Analyst Consensus", "Chart", "gurufocus tipranks target bar valuation", "chart.bar.fill", .teal, .valuation),
            ("Historical PE Valuation Gauge", "Chart", "bullet current forward average valuation", "chart.bar.xaxis", .blue, .valuation),
            ("Yield Barometer (Earnings vs Cash)", "Chart", "earnings fcf cash yield bar valuation", "chart.bar.fill", .green, .valuation),
            ("Quality Matrix (Cash vs Accounting)", "Chart", "cash earnings fcf scatter matrix valuation", "square.grid.2x2.fill", .indigo, .valuation),
            ("PEG Ratio Matrix (Price vs Growth)", "Chart", "price growth garp scatter peg valuation", "chart.xyaxis.line", .orange, .valuation),
            ("Portfolio Discount Heatmap", "Chart", "treemap undervalued fair price upside valuation", "squareshape.split.3x3", .red, .valuation),
            ("Current vs Target Price", "Chart", "line difference gap upside valuation", "chart.xyaxis.line", .purple, .valuation),
            ("Valuation Range Distribution", "Chart", "donut pie deep value fairly overvalued valuation", "chart.pie.fill", .blue, .valuation),

            // ================= PROJECTION =================
            
            // --- Dashboard Metrics (Top 8 Cards) ---
            ("Current Portfolio Value", "Dashboard Metric", "starting capital amount projection", "banknote.fill", .blue, .projection),
            ("Projected Value", "Dashboard Metric", "future terminal target value projection", "chart.line.uptrend.xyaxis", .green, .projection),
            ("Portfolio CAGR Used", "Dashboard Metric", "compound annual growth rate projection", "arrow.up.right.circle.fill", .orange, .projection),
            ("Projected Capital Gain", "Dashboard Metric", "future profit gain projection", "plus.circle.fill", .teal, .projection),
            ("Current Annual Div.", "Dashboard Metric", "starting dividend income projection", "banknote", .purple, .projection),
            ("Projected Div.", "Dashboard Metric", "future dividend income projection", "calendar.badge.plus", .indigo, .projection),
            ("Weighted 5Y Div Growth", "Dashboard Metric", "dgr dividend growth rate projection", "chart.line.uptrend.xyaxis", .mint, .projection),
            ("Projected Monthly Div.", "Dashboard Metric", "future monthly income projection", "calendar", .blue, .projection),
            
            // --- Controls & Parameters ---
            ("Time Horizon", "Projection Parameter", "years slider duration future projection", "slider.horizontal.3", .blue, .projection),
            ("Annual Capital CAGR (%)", "Projection Parameter", "custom growth rate percentage projection", "percent", .orange, .projection),
            ("Dividend Growth 5Y (%)", "Projection Parameter", "custom dgr dividend growth percentage projection", "percent", .mint, .projection),
            ("Monthly Contributions", "Projection Parameter", "savings deposits cash injection projection", "plus.forwardslash.minus", .green, .projection),
            ("DRIP (Reinvest Dividends)", "Projection Parameter", "drip snowball compound reinvest projection", "arrow.3.trianglepath", .purple, .projection),
            ("Adjust for Inflation", "Projection Parameter", "real purchasing power nominal cpi projection", "arrow.down.right.circle.fill", .red, .projection),
            
            // --- Projection Schedule Table ---
            ("Year-by-Year Projection Schedule", "Data Table", "amortization schedule table timeline projection", "tablecells.fill", .gray, .projection),
            
            // --- Charts (4 Visuals) ---
            ("Portfolio Capital Growth", "Chart", "future value area chart compounding projection", "chart.xyaxis.line", .blue, .projection),
            ("Annual Dividend Income Growth", "Chart", "future income bar chart projection", "chart.bar.fill", .green, .projection),
            ("Total Cumulative Dividends Collected", "Chart", "sum total cash snowball area chart projection", "chart.xyaxis.line", .purple, .projection),
            ("Projected Yield On Cost (YOC)", "Chart", "yoc future yield line chart projection", "percent", .orange, .projection),

            // ================= SIMULATION =================
            
            // --- Dashboard Metrics (Top 8 Cards) ---
            ("Current Portfolio Value", "Dashboard Metric", "real actual total value simulation", "banknote.fill", .blue, .simulation),
            ("Simulated Portfolio Value", "Dashboard Metric", "fake test sandbox total value simulation", "banknote.fill", .purple, .simulation),
            ("Current Cash", "Dashboard Metric", "real actual liquidity dry powder simulation", "eurosign.circle.fill", .green, .simulation),
            ("Simulated Cash", "Dashboard Metric", "fake test sandbox liquidity dry powder simulation", "eurosign.circle.fill", .mint, .simulation),
            ("Current Annual Div.", "Dashboard Metric", "real actual dividend income simulation", "banknote", .orange, .simulation),
            ("Simulated Annual Div.", "Dashboard Metric", "fake test sandbox dividend income simulation", "banknote", .yellow, .simulation),
            ("Current Total Yield", "Dashboard Metric", "real actual percentage yield simulation", "percent", .teal, .simulation),
            ("Simulated Total Yield", "Dashboard Metric", "fake test sandbox percentage yield simulation", "percent", .cyan, .simulation),
            
            // --- Logs & Tables ---
            ("Sandbox Actions Log", "Sandbox Tool", "undo history changes log line by line simulation", "list.bullet.rectangle", .gray, .simulation),
            ("Current Portfolio", "Data Table", "real actual holdings list table simulation", "tablecells.fill", .gray, .simulation),
            ("Simulated Sandbox", "Sandbox Tool", "fake test holdings list table what if rebalance simulation", "slider.horizontal.3", .mint, .simulation),
            
            // --- Charts (8 Visuals) ---
            ("Current Weight by Position", "Chart", "real actual allocation donut pie simulation", "chart.pie.fill", .blue, .simulation),
            ("Simulated Weight by Position", "Chart", "fake test sandbox allocation donut pie simulation", "chart.pie.fill", .purple, .simulation),
            ("Current Sector Allocation", "Chart", "real actual industry donut pie simulation", "chart.pie.fill", .orange, .simulation),
            ("Simulated Sector Allocation", "Chart", "fake test sandbox industry donut pie simulation", "chart.pie.fill", .yellow, .simulation),
            ("Total Value Comparison", "Chart", "compare bar chart difference impact simulation", "chart.bar.fill", .indigo, .simulation),
            ("Portfolio Yield Impact", "Chart", "compare yield bar chart difference simulation", "chart.bar.fill", .teal, .simulation),
            ("Simulated Cash Investments", "Chart", "deployment dry powder donut pie simulation", "chart.pie.fill", .green, .simulation),
            ("Simulated Dividends by Position", "Chart", "fake test income payout donut pie simulation", "chart.pie.fill", .mint, .simulation),
            
            // ================= WATCHLIST =================
            
            // --- Dashboard Metrics (Top 8 Cards) ---
            ("Watchlist Companies", "Dashboard Metric", "count tracked prospective watchlist", "eye.fill", .cyan, .watchlist),
            ("Undervalued (Fair Price)", "Dashboard Metric", "cheap discount margin of safety mos watchlist", "arrow.down.right.circle.fill", .green, .watchlist),
            ("Avg. Target Upside", "Dashboard Metric", "potential return discount watchlist", "arrow.up.right.circle.fill", .teal, .watchlist),
            ("Avg. Watchlist PEG", "Dashboard Metric", "price earnings growth garp watchlist", "chart.line.uptrend.xyaxis", .orange, .watchlist),
            ("Avg. Current PE", "Dashboard Metric", "price earnings multiple watchlist", "number.circle.fill", .purple, .watchlist),
            ("Avg. Forward PE", "Dashboard Metric", "future price earnings multiple watchlist", "number.circle.fill", .indigo, .watchlist),
            ("PEG ≤ 1.0 (Bargains)", "Dashboard Metric", "cheap garp deep value watchlist", "star.fill", .yellow, .watchlist),
            ("Top Pick (Fair Price)", "Dashboard Metric", "best highest upside crown watchlist", "crown.fill", .yellow, .watchlist),
            
            // --- Controls & Tables ---
            ("Watchlist Margin of Safety", "Risk Parameter", "mos discount slider watchlist", "shield.fill", .teal, .watchlist),
            ("Watchlist Valuation Table", "Data Table", "fair price target multiples spreadsheet watchlist", "tablecells.fill", .gray, .watchlist),
            ("Quality Analysis Laboratory", "Analysis Tool", "strengths weaknesses compare test due diligence watchlist", "testtube.2", .purple, .watchlist),
            
            // --- Charts (6 Visuals) ---
            ("Valuation & Target Prices Comparison", "Chart", "gurufocus tipranks target bar watchlist", "chart.bar.fill", .blue, .watchlist),
            ("PE Valuation (Current vs Fwd vs 10Y)", "Chart", "multiple comparison bar watchlist", "chart.bar.fill", .indigo, .watchlist),
            ("PEG Ratio (PEG < 1.0 = Undervalued)", "Chart", "price growth garp bar watchlist", "chart.bar.fill", .orange, .watchlist),
            ("Potential Upside % (Target vs Fair Price)", "Chart", "discount potential bar watchlist", "chart.bar.fill", .green, .watchlist),
            ("Analyzed Stock vs Portfolio Avg", "Chart", "quality score comparison laboratory watchlist", "chart.bar.fill", .purple, .watchlist),
            ("Stock Radar Profiles", "Chart", "spider web polygon radar laboratory watchlist", "hexagon.fill", .mint, .watchlist),
            
            // ================= EXPOSURE =================
            
            // --- Dashboard Metrics (Top 8 Cards) ---
            ("Weighted USA Exposure", "Dashboard Metric", "america united states domestic revenue exposure", "star.fill", .blue, .exposure),
            ("Weighted ROW Exposure", "Dashboard Metric", "rest of world international foreign revenue exposure", "globe.europe.africa.fill", .green, .exposure),
            ("Unassigned Revenue", "Dashboard Metric", "unknown unmapped missing data exposure", "questionmark.circle.fill", .gray, .exposure),
            ("Primary Market Target", "Dashboard Metric", "dominant main market focus exposure", "chart.bar.fill", .indigo, .exposure),
            ("Total Regions Tracked", "Dashboard Metric", "countries geographic areas count exposure", "map.fill", .orange, .exposure),
            ("Fully Mapped Stocks", "Dashboard Metric", "data quality completeness exposure", "checkmark.seal.fill", .teal, .exposure),
            ("Max Single-Region Focus", "Dashboard Metric", "concentration risk highest region exposure", "exclamationmark.triangle.fill", .red, .exposure),
            ("Est. FX Risk (Non-USA)", "Dashboard Metric", "currency foreign exchange risk exposure", "dollarsign.arrow.circlepath", .purple, .exposure),
            
            // --- Widgets & Tables ---
            ("Top Dominant Markets", "Ranking List", "highest regions countries top 5 list exposure", "list.number", .blue, .exposure),
            ("FX Risk Matrix (Currency Exposure)", "Risk Assessment", "currency foreign exchange bars exposure", "dollarsign.circle.fill", .green, .exposure),
            ("Revenue Segmentation by Stock", "Data Table", "spreadsheet matrix regions known percent exposure", "tablecells.fill", .gray, .exposure),
            
            // --- Charts (4 Visuals) ---
            ("Weighted Portfolio Exposure (USA vs ROW)", "Chart", "donut pie domestic international exposure", "chart.pie.fill", .blue, .exposure),
            ("Detailed Geographic Breakdown by Stock", "Chart", "stacked bar regions stocks exposure", "chart.bar.fill", .purple, .exposure),
            ("Global Exposure Heatmap (Treemap)", "Chart", "treemap square map regions exposure", "squareshape.split.3x3", .orange, .exposure),
            ("Sector × Geography Risk Matrix", "Chart", "heatmap risk concentration sector exposure", "square.grid.3x3.fill", .red, .exposure),
            
            // ================= TRANSACTIONS =================
            
            // --- Dashboard Metrics (Top 8 Cards) ---
            ("Total Deposited", "Dashboard Metric", "cash in deposit add funds transactions", "arrow.down.circle.fill", .green, .transactions),
            ("Total Withdrawn", "Dashboard Metric", "cash out withdraw funds transactions", "arrow.up.circle.fill", .red, .transactions),
            ("Net Cash Flow", "Dashboard Metric", "cash balance in out transactions", "arrow.left.arrow.right.circle.fill", .blue, .transactions),
            ("Total Invested", "Dashboard Metric", "bought buy spend invested transactions", "cart.fill", .blue, .transactions),
            ("Total Sold", "Dashboard Metric", "sold sell revenue transactions", "tag.fill", .orange, .transactions),
            ("Net Invested", "Dashboard Metric", "net bought sold transactions", "chart.pie.fill", .purple, .transactions),
            ("Total Fees & Taxes", "Dashboard Metric", "cost friction drag taxes broker state transactions", "exclamationmark.triangle.fill", .red, .transactions),
            ("Transactions Found", "Dashboard Metric", "count total history logged transactions", "number.circle.fill", .gray, .transactions),
            
            // --- Goals & Tables ---
            ("Transactions Goal", "Target Tracking", "goal bar target logged history transactions", "target", .purple, .transactions),
            ("Transaction History", "Data Table", "history ledger list spreadsheet log transactions", "tablecells.fill", .gray, .transactions),
            ("Yearly Summary", "Data Table", "annual aggregate summary table history transactions", "calendar", .blue, .transactions),
            
            // --- Charts (4 Visuals) ---
            ("Transactions per Year", "Chart", "yearly count volume bar chart transactions", "chart.bar.fill", .blue, .transactions),
            ("Summary by Type", "Chart", "type buy sell deposit withdraw combo chart transactions", "chart.xyaxis.line", .purple, .transactions),
            ("Buys over Time", "Chart", "timeline purchases chronological bar trend transactions", "chart.bar.xaxis", .green, .transactions),
            ("Fees & Taxes Breakdown", "Chart", "cost taxes broker state donut pie chart transactions", "chart.pie.fill", .red, .transactions),
            
            // ================= BENCHMARK =================
            
            // --- Dashboard Metrics (Top 8 Cards) ---
            ("Portfolio Return", "Dashboard Metric", "current year ytd performance benchmark", "chart.line.uptrend.xyaxis", .green, .benchmark),
            ("Portfolio Avg. Return", "Dashboard Metric", "average historical performance benchmark", "percent", .blue, .benchmark),
            ("Best Index (Avg.)", "Dashboard Metric", "top performing market index benchmark", "trophy.fill", .yellow, .benchmark),
            ("vs Best Index (Avg.)", "Dashboard Metric", "alpha ahead behind outperformance benchmark", "arrow.up.right.circle.fill", .green, .benchmark),
            ("Indices Tracked", "Dashboard Metric", "count markets tracked benchmark", "list.number", .gray, .benchmark),
            ("Years Tracked", "Dashboard Metric", "duration time horizon benchmark", "clock.fill", .gray, .benchmark),
            ("Portfolio 10k€ Simulation", "Dashboard Metric", "simulated wealth compounding benchmark", "banknote.fill", .blue, .benchmark),
            ("Best Index 10k€", "Dashboard Metric", "simulated index wealth opportunity cost benchmark", "banknote", .purple, .benchmark),
            
            // --- Goals & Tables ---
            ("Alpha Goal", "Target Tracking", "outperform best index alpha target benchmark", "target", .purple, .benchmark),
            ("Performance Comparison", "Data Table", "annual returns list spreadsheet index benchmark", "tablecells.fill", .gray, .benchmark),
            
            // --- Charts (2 Visuals) ---
            ("Annual Return (%)", "Chart", "yearly comparison bar chart benchmark", "chart.bar.fill", .blue, .benchmark),
            ("€10,000 Simulated Growth", "Chart", "compounding opportunity cost line chart benchmark", "chart.xyaxis.line", .purple, .benchmark),
            
            // ================= CALENDAR =================
            ("Next Upcoming Events", "Dashboard Section", "schedule timeline upcoming agenda calendar", "bell.fill", .blue, .calendar),
            ("Investor Calendar", "App Page", "schedule dates events market closed calendar", "calendar", .red, .calendar),
            
            // ================= WEALTH =================
            
            // --- Dashboard Metrics (Top 8 Cards) ---
            ("True Net Worth", "Dashboard Metric", "total balance sheet equity wealth", "building.columns.fill", .green, .wealth),
            ("Total Assets", "Dashboard Metric", "gross capital holdings wealth", "plus.circle.fill", .blue, .wealth),
            ("Total Liabilities", "Dashboard Metric", "debt loans borrowed owed wealth", "minus.circle.fill", .red, .wealth),
            ("Net P/L (Assets)", "Dashboard Metric", "profit loss gain return wealth", "arrow.up.right.circle.fill", .green, .wealth),
            ("Wealth Goal", "Dashboard Metric", "target milestone objective wealth", "star.fill", .yellow, .wealth),
            ("Overall Assets ROI", "Dashboard Metric", "return on investment percentage wealth", "percent", .teal, .wealth),
            ("Debt-to-Asset Ratio", "Dashboard Metric", "leverage risk ratio wealth", "exclamationmark.triangle.fill", .orange, .wealth),
            ("Brokerage Weight", "Dashboard Metric", "stock market percentage wealth", "chart.pie.fill", .purple, .wealth),
            
            // --- Tables, Goals & Tools ---
            ("Net Worth Goal Progress", "Target Tracking", "goal bar target progress wealth", "target", .purple, .wealth),
            ("Assets Allocation Ledger", "Data Table", "real estate crypto savings list table wealth", "tablecells.fill", .blue, .wealth),
            ("Liabilities & Debts Ledger", "Data Table", "mortgage loan credit list table wealth", "tablecells.fill", .red, .wealth),
            ("FIRE Simulator", "Analysis Tool", "financial independence retire early passive income swr wealth", "flame.fill", .orange, .wealth),
            
            // --- Charts (2 Visuals) ---
            ("Assets Allocation (Macro)", "Chart", "distribution donut pie chart wealth", "chart.pie.fill", .blue, .wealth),
            ("Return on Investment (ROI % by Asset)", "Chart", "roi performance bar chart wealth", "chart.bar.fill", .green, .wealth),






        ]
        
        for item in uiElements {
            let searchableText = "\(item.title) \(item.subtitle) \(item.keywords)"
            if matchesQuery(searchableText) {
                results.append(SearchResult(title: item.title, subtitle: item.subtitle, icon: item.icon, color: item.color, tab: item.tab))
            }
        }
        
        // --- 1. PAGES DE L'APPLICATION ---
        for tab in AppTab.allCases {
            if matchesQuery(tab.rawValue) {
                results.append(SearchResult(title: tab.rawValue, subtitle: "App Page", icon: "macwindow", color: .blue, tab: tab))
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
        
        // A. Génération virtuelle des 4 sorcières (Quadruple Witching) pour la recherche
        for year in [currentYear, currentYear + 1] {
            for month in [3, 6, 9, 12] {
                if let witchingDate = USMarketHolidayHelper.nthWeekday(nth: 3, weekday: 6, month: month, year: year) {
                    allSearchableEvents.append(CalendarEvent(id: UUID(), date: witchingDate, type: .macro, ticker: "MARKET", note: "Quadruple Witching Day (Options & Futures Expiration)"))
                }
            }
        }
        
        // B. Génération virtuelle des Anniversaires d'achat pour la recherche
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
        
        // C. Recherche dans les Événements (Manuels + Sorcières + Anniversaires)
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
        
        // D. Recherche dans les Jours Fériés (Market Closed)
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
                    .focused($isFocused) // Permet de taper directement sans devoir cliquer
                
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
                List(searchResults) { result in
                    Button(action: {
                        selectedTab = result.tab // Change l'onglet en arrière-plan
                        dismiss() // Ferme la recherche
                    }) {
                        HStack(spacing: 16) {
                            Circle()
                                .fill(result.color.opacity(0.2))
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Image(systemName: result.icon)
                                        .foregroundColor(result.color)
                                )
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.title)
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Text(result.subtitle)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.right")
                                .foregroundColor(.secondary.opacity(0.5))
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(width: 600, height: 450)
        .onAppear {
            isFocused = true // Force le curseur dans la barre de recherche à l'ouverture
        }
    }
}

