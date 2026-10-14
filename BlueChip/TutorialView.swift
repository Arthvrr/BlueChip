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
                """
                **The Central Command Center of Your Portfolio**
                The Composition page serves as your high-level dashboard, providing a holistic and comprehensive snapshot of your overall invested capital, available cash, and total unrealized returns.
                
                **The Executive Dashboard**
                At the top of the page, you will find 8 key metric cards. 
                • **Manual Inputs:** You only need to manually update two metrics. Click the pencil icon on the **Cash** card to log your available liquidity, and the **Initial Investment** card to track your total out-of-pocket deposits.
                • **Automated Metrics:** The remaining six cards (Total Value, Unrealized P/L, Positions count, Annual Dividends, etc.) are calculated automatically in real-time based on your holdings and live market data!
                
                **Custom Portfolio Goals**
                Just below the dashboard, you can track your overarching financial objective using the Goal Progress Bar. **Double-click** the bar to configure it. You can choose to track either your *Initial Investment* milestone or your *Total Portfolio Value* objective. Simply enter your target amount, and the progress bar will automatically update as your wealth grows.
                
                **Adding & Managing Assets**
                To register a new holding, click the **+ Add** button at the top right of the application (or use the shortcut **⌘ + N**). You will need to provide:
                • **Asset Information:** Ticker (e.g., AAPL), Company Name, Country, Sector, and Market Cap.
                • **Investment Details:** Your exact Quantity, Average Cost (PRU), and Purchase Date.
                • **Dividend Data (Optional):** Annual Dividend per share, 5Y Growth rate, and payout months.
                
                *(Note: Live pricing and USD/EUR FX rates are fetched automatically based on the ticker!)*
                
                To modify an existing asset, simply **double-click** its row in the main table.
                
                **Interactive Positions Table**
                Your holdings are displayed in a powerful data table. You can dynamically sort your portfolio by clicking on any column header (e.g., sort by P/L %, Total Value, or Ticker). Click the exact same column header again to reverse the sorting order (ascending/descending).
                
                **Visual Analytics & Charts**
                Scroll down to explore 12 institutional-grade diagnostics:
                • **Weight by Position:** A classic donut chart breaking down the exact percentage each individual stock represents in your overall portfolio.
                • **Macro Allocation (Geography, Sector, Market Cap):** Three dedicated donut charts analyzing your structural diversification by country, industry sector, and company size.
                • **Currency Exposure:** A donut chart revealing your underlying foreign exchange (FX) risk across different currencies, including your available cash.
                • **Estimated Asset Correlation:** A heatmap matrix estimating how your assets move in relation to one another to ensure true structural diversification.
                • **Avg Cost vs Current Price:** A comparative bar chart mapping your Average Cost (PRU) directly against the live Current Price for every holding.
                • **Return on Investment (P/L):** A dual-axis combo chart tracking your unrealized performance in both absolute Euros and percentage terms.
                • **Weight vs Unrealized Performance:** A crucial scatter plot ensuring your heaviest portfolio allocations are actually generating the highest returns.
                • **Capital Status:** A donut chart showing what proportion of your originally invested capital is currently generating a positive return versus running at a loss.
                • **Performance Heatmap:** An interactive treemap scaling your holdings by portfolio weight and dynamically color-coding them by their performance intensity.
                • **Daily P/L by Holding Period:** A bar chart tracking the daily equivalent return for each position based on how long you've held it in your portfolio.
                
                *Pro-tip: Click the magnifying glass icon on any chart to open a detailed full-screen view!*
                """
            )

            
        case .fundamentals:
            return (
                "Fundamentals",
                "building.2.fill",
                """
                **The Ultimate Stock Quality Screener**
                The Fundamentals page is a powerful, fully customizable screener designed to evaluate the intrinsic quality of your portfolio. Rather than relying on generic external ratings, you build your own scoring engine to rank your stocks based on the financial metrics that matter most to your strategy.
                
                **The Executive Dashboard**
                At the top of the page, the 8-card dashboard is generated **entirely automatically** based on your screener data. It provides an instant snapshot of your portfolio's average quality score, your highest-rated stock, and the specific fundamental categories where your portfolio excels or lags.
                
                **Building Your Scoring Engine**
                Click the **+ Add Criterion** button to create a new metric (e.g., Gross Margin, P/E Ratio, Payout Ratio).
                • **Data Types:** You can flexibly define each criterion to be evaluated as a Boolean (Yes/No condition), a Percentage, or a standard Numeric Value.
                • **Scoring Thresholds:** For numeric and percentage metrics, you define two targets: a Premium Threshold and a Standard Threshold. Meeting these targets awards points to the stock, multiplied by the weight you assign to the metric.
                • **Reference Links:** You can attach a dynamic web link to any criterion. When it's time to enter data for a holding, a built-in shortcut will instantly open your preferred financial website directly to that specific ticker's metrics page.
                • **Custom Sections & Layout:** Group your criteria into logical categories (e.g., *PROFITABILITY, GROWTH, DEBT*) and use the **Reorder Layout** button to seamlessly drag and drop your columns into your preferred order.
                
                **Data Entry & Portfolio Weighted Averages**
                Click on any cell in the spreadsheet to input the financial data for a specific stock. The system will instantly color-code the result (Green for Premium, Blue for Standard, Red for Failed) and recalculate the stock's total score.
                To modify an existing criterion's underlying rules or weight, simply **double-click** its column header in the table.
                At the bottom of the spreadsheet, the **WEIGHTED AVG** row calculates the true fundamental health of your entire portfolio by weighting each stock's score according to its actual capital allocation.
                
                **Visual Analytics & Charts**
                Scroll down to explore 6 dynamic, institutional-grade visualizations:
                • **Quality Score Comparison:** A clear, ranked bar chart of your stocks based on their total fundamental score.
                • **Score Composition Profile:** A stacked bar chart breaking down exactly how each stock earns its points across your custom sections.
                • **Quality Matrix (Score vs Weight):** A crucial scatter plot ensuring your heaviest portfolio weights are correctly allocated to your highest-quality stocks.
                • **Stock Quality by Segment:** A comparative line chart to easily identify which stocks dominate specific fundamental categories.
                • **Weighted Portfolio Scorecard:** A polar area chart summarizing the macro-fundamental health of your overall portfolio.
                • **Stock Radar Profiles:** A classic radar web comparing the multi-dimensional footprint of your individual holdings.
                
                *Pro-tip: Click the magnifying glass icon on any chart to open a detailed full-screen view!*
                """
            )
        
        case .growth:
            return (
                "Growth",
                "chart.line.uptrend.xyaxis",
                """
                **The Wealth Accumulator Engine**
                The Growth page is your long-term performance tracker. It isolates your out-of-pocket deposits from pure market returns to reveal your true compounding trajectory over time.
                
                **The Executive Dashboard**
                At the top of the page, 8 fully automated metric cards provide a real-time summary of your capital appreciation. You can instantly track your Current Wallet Value, Total Invested Capital, and All-Time Returns. Advanced metrics like your Compound Annual Growth Rate (CAGR), Average Yearly Returns, and Best Year Return are continuously recalculated as your portfolio evolves.
                
                **Custom Annual Targets**
                Just below the dashboard, you can monitor your performance against your personalized annual goal. **Double-click** the progress bar to configure whether you want to target a specific *Percentage Return (%)* or an *Absolute Euro Amount (€)* for the ongoing year.
                
                **Portfolio Structure & Gains**
                Three side-by-side donut charts break down your exact wealth composition:
                • **Cash vs Stocks:** Visualizes your deployment ratio (Dry Powder vs Invested Capital).
                • **Value Source:** Separates your net deposits from your market-generated gains.
                • **Gains Source:** Breaks down your total gains between collected Dividends and pure Capital Appreciation.
                
                **Capital Growth History (The Spreadsheet)**
                This table is the engine of the Growth page. To make it work, you must manually input three values for each past year: **Start Wallet**, **Invested** (Net deposits during the year), and **End Wallet**. The system will automatically calculate your exact Return in € and % for each year. 
                *(Note: The current year's End Wallet is automatically synced to your live portfolio value!).*
                To adjust the timeline of this table, open your **Preferences (⌘ + ,)** and set your *Investment Start Year*. The table will automatically generate rows from that specific year up to the present day.
                
                **Advanced Growth Analytics**
                Scroll down to explore 6 advanced institutional-grade charts based on your spreadsheet data:
                • **Annual Returns:** A dual-axis combo chart tracking your absolute (€) and relative (%) performance year-over-year.
                • **Invested vs Portfolio Value:** An area chart visualizing the widening gap between what you put in and what it's worth.
                • **Wealth Accumulation Waterfall:** A clear step-by-step bridge showing exactly how your initial capital grew into your current wealth.
                • **MoIC Trend:** Tracks your *Multiple on Invested Capital* (Money on Money), showing how many times you've multiplied your out-of-pocket cash.
                • **The Tipping Point:** A bar chart comparing your active effort (Contributions) against passive market returns. Watch for the year your money starts working harder than you do!
                • **The Compounding Stack:** A 100% stacked bar chart revealing how investment growth eventually snowballs and overtakes your principal capital.
                
                *Pro-tip: Click the magnifying glass icon on any chart to open a detailed full-screen view!*
                """
            )

        case .dividends:
            return (
                "Dividends",
                "banknote.fill",
                """
                **The Passive Income Engine**
                The Dividends page is your ultimate cash flow command center. It bridges the gap between your theoretical projected yields and your actual out-of-pocket cash collected, allowing you to master your passive income snowball.
                
                **The Executive Dashboard**
                At the top of the page, 8 fully automated metric cards summarize your cash flow health. You can instantly track your *Total Received (All Time)*, *Projected Annual Income*, and *Projected Portfolio Yield*. The dashboard also monitors your momentum by calculating your *YoY Growth* against last year, your *Avg. Monthly* income, and highlighting your *Best Year* on record.
                
                **Custom Income Targets**
                Set a personalized passive income goal using the progress bar. **Double-click** the bar to toggle your objective: you can either aim for a target *Portfolio Yield (%)* or a flat *Annual Expected Dividends (€)* amount.
                
                **Projected Analytics**
                Two forward-looking charts map out your portfolio's potential:
                • **Expected Monthly Income:** A bar chart comparing your Gross vs Net expected payouts for all 12 months based on your current holdings.
                • **Current Stock Yield:** A visual ranking of your individual stocks by their current dividend yield.
                
                **This Month's Payout Radar**
                A dedicated, interactive tracker for the current ongoing month. The system automatically identifies which stocks are scheduled to pay you and exactly how much you should expect. Use the mini-table to log the actual cash you receive, and watch your monthly progress donut chart fill up to 100%!
                
                **Manual Dividend Tracker (The Spreadsheet)**
                This is your core accounting tool for historical tracking. Simply input the net dividends you receive each month (Jan-Dec) for every year, and the table will automatically calculate your annual totals. 
                *(Note: To adjust the timeline of this table, open your **Preferences (⌘ + ,)** and set your 'Investment Start Year'. The spreadsheet will generate rows from that date up to the current year).*
                
                **Advanced Income Analytics**
                Scroll down to explore 8 advanced visualizations powered by your spreadsheet data:
                • **Received This Year & Annual Received History:** Two bar charts tracking your manual monthly receipts for the current year, and your macro year-over-year progression.
                • **Total Dividends by Position & Yield On Cost (YOC):** Discover which stocks are your biggest cash cows, and track your true YOC (how much your dividend has grown relative to your original purchase price).
                • **All-Time History & Trend:** A majestic area chart mapping your entire dividend journey since inception, complete with an algorithmic trendline.
                • **Dividend Calendar Heatmap:** A visual matrix showing exactly which stocks pay during which months, highlighting payout concentration risks.
                • **Cumulative Monthly Seasonality:** Aggregates your all-time data to reveal your strongest and weakest payout months historically.
                • **Dividend Growth Rate (YoY DGR):** A line chart tracking the crucial year-over-year percentage increase of your total dividends, showing the true speed of your compounding engine.
                
                *Pro-tip: Click the magnifying glass icon on any chart to open a detailed full-screen view!*
                """
            )
            
        case .valuation:
            return (
                "Valuation",
                "scale.3d",
                """
                **The Intrinsic Value Command Center**
                The Valuation page is your dedicated pricing and risk assessment engine. It empowers you to look beyond daily market noise by evaluating your holdings through strict fundamental pricing models, historical multiples, and cash flow yields.
                
                **The Executive Dashboard**
                At the top of the page, the 8-card dashboard is generated **entirely automatically** based on the data you provide. It delivers an instant macro-snapshot of your portfolio's valuation health, revealing the number of Undervalued Stocks, the Average Fair Price Upside, and comprehensive portfolio-wide multiples such as the Average Current P/E, Historical 10Y P/E, and PEG Ratio.
                
                **Risk Controls & Global Data Links**
                Just below the dashboard, you have total control over your pricing conservatism:
                • **Global Margin of Safety:** Use the slider to enforce a strict discount (adjustable from 0% up to 50%) across all your intrinsic value calculations. A 20% margin means you demand a 20% discount on the fair price before considering a stock undervalued.
                • **Global Data Links:** Configure your preferred financial research websites (e.g., GuruFocus, TipRanks, FinanceCharts). By using the `{ticker}` tag in the URL, the system will automatically generate dynamic shortcuts in the edit menu to instantly pull external valuation data for any specific stock!
                
                **Valuation Spreadsheets**
                Your data is organized into two comprehensive tables. To input or update metrics for any holding, simply **double-click** its row in either table:
                • **Price Valuation Models:** Track the Current Price against Analyst Targets, GuruFocus estimates, and TipRanks consensus to determine your blended Fair Price and ultimate Upside.
                • **Multiples & Yields:** Monitor crucial pricing metrics including Current P/E, Forward P/E, 10-Year Historical P/E, Price-to-FCF, PEG Ratio, Earnings Yield, and FCF Yield.
                
                **Visual Analytics & Charts**
                Scroll down to explore 8 sophisticated, institutional-grade visual diagnostics:
                • **Price vs Analyst Consensus:** A comparative bar chart mapping the current price against your external fair value estimates.
                • **Historical PE Valuation Gauge:** A bullet chart pinpointing where a stock's current P/E sits relative to its 10-Year historical average.
                • **Yield Barometer (Earnings vs Cash):** A direct comparison of Earnings Yield versus Free Cash Flow (FCF) Yield.
                • **Quality Matrix (Cash vs Accounting):** A scatter plot separating true cash-generating machines from paper-profit illusions.
                • **PEG Ratio Matrix (Price vs Growth):** Evaluates if you are overpaying for growth (GARP analysis).
                • **Portfolio Discount Heatmap:** A visual treemap scaling your holdings by portfolio weight and color-coding them by their Margin of Safety upside.
                • **Current vs Target Price:** A visual gap analysis between where the stock trades today and your ultimate price target.
                • **Valuation Range Distribution:** A donut chart classifying your deployed capital into Deep Value, Fairly Valued, and Overvalued territories.
                
                *Pro-tip: Click the magnifying glass icon on any chart to open a detailed full-screen view!*
                """
            )

        
        case .projection:
            return (
                "Projections",
                "chart.xyaxis.line",
                """
                **The Future Wealth Simulator**
                The Projections page is your financial time machine. It uses your historical portfolio data and advanced compounding algorithms to forecast your future net worth and passive income over a multi-decade horizon.
                
                **The Executive Dashboard**
                At the top of the page, the 8-card dashboard provides an instant **fully automated** comparison between your portfolio today and its projected terminal value. 
                • The top row contrasts your *Current Portfolio Value* against your *Projected Value* at the end of the horizon, displaying the *Portfolio CAGR Used* and the exact *Projected Capital Gain*.
                • The bottom row focuses on cash flow, comparing your *Current Annual Div.* to your *Projected Div.*, alongside your *Weighted 5Y Div Growth* rate and your future *Projected Monthly Div.*
                
                **Projection Parameters & Assumptions**
                You have complete control over the variables that dictate your compounding trajectory:
                • **Time Horizon:** Use the slider to set your forecasting period (from 5 up to 50 years).
                • **Capital CAGR & Dividend Growth:** The system automatically calculates and applies your portfolio's real historical rates. However, you can manually override these to stress-test more conservative or aggressive scenarios.
                • **Monthly Contributions:** Toggle this on to simulate injecting fresh capital into your portfolio every month.
                • **DRIP (Reinvest Dividends):** Toggle this to activate the ultimate snowball effect, where your generated dividends automatically buy more shares to compound your returns.
                • **Adjust for Inflation:** Toggle this to discount your future terminal values by an annual inflation rate, revealing your true "Real" purchasing power rather than just "Nominal" numbers.
                
                **Visual Analytics & Charts**
                Scroll down to explore 4 institutional-grade forecasting models:
                • **Portfolio Capital Growth:** An area chart mapping your portfolio's total projected value alongside pure capital gains over the time horizon.
                • **Annual Dividend Income Growth:** A dual-axis chart tracking the exponential rise of your Gross Annual Dividends and your Monthly Equivalent payouts.
                • **Total Cumulative Dividends Collected:** An area chart visualizing the massive snowball effect of all cash generated and collected throughout the entire period.
                • **Projected Yield On Cost (YOC):** A vital trend line showing how your dividends scale relative to your out-of-pocket invested capital (watch for the 100% line where your portfolio effectively pays for itself!).
                
                **Year-by-Year Projection Schedule**
                At the bottom of the page, a dynamic accounting table automatically generates a detailed row for every single year of your chosen horizon. It provides a transparent, year-by-year breakdown of your projected Portfolio Value, Cumulative Gain, and Expected Income.
                
                *Pro-tip: Click the magnifying glass icon on any chart to open a detailed full-screen view!*
                """
            )

        case .simulation:
            return (
                "Simulation",
                "slider.horizontal.3",
                """
                **The Ultimate Sandbox Environment**
                The Simulation page is your risk-free testing ground. It creates an isolated, identical clone of your current portfolio, allowing you to test theoretical trades, rebalancing strategies, and cash deployments without ever altering your real accounting data.
                
                **The Executive Dashboard**
                At the top of the page, 8 fully automated metric cards provide a direct, side-by-side comparison between Reality and your Sandbox. Instantly evaluate how your theoretical trades impact your *Total Portfolio Value*, *Available Cash*, *Annual Expected Dividends*, and *Total Portfolio Yield*.
                
                **The Sandbox Workbenches**
                Below the dashboard and the Action Log, you will find two comparative tables:
                • **Current Portfolio (Left):** A read-only snapshot of your actual, real-world holdings and weights.
                • **Simulated Sandbox (Right):** Your interactive testing environment. 
                
                **Executing Simulated Trades**
                Use the control icons above the Sandbox table to manipulate your theoretical portfolio:
                • **Modify Cash (Euro Icon):** Add or remove simulated cash (e.g., simulating a new salary deposit or a major withdrawal).
                • **Add/Edit Position (+ Icon):** Simulate buying a new stock or selling an existing one. Enter the Ticker, click 'Fetch Price' for live data, and input the exact number of shares. You can also specify the *Net Dividend / Share* and *Sector*.
                • **Taxes & Fees Calculator:** The simulation is hyper-realistic. You can input exact *Broker Taxes* and *Country Taxes* (either as a flat € amount or as a %) to see the true *Net Cash Impact* of your theoretical trade.
                • **Reset (Arrow Icon):** Instantly wipe all theoretical trades and reset the Sandbox to strictly match your current real portfolio.
                
                *Note: Every trade you make is recorded in the **Sandbox Actions Log** just above the tables, complete with a convenient "Undo" button to revert any specific action!*
                
                **Comparative Visual Analytics**
                Scroll down to explore 8 comparative charts showing the before-and-after impact of your decisions:
                • **Weight by Position:** Two side-by-side donuts comparing your current vs simulated stock concentration.
                • **Sector Allocation:** Evaluate how your simulated trades alter your macro sector exposure.
                • **Total Value & Yield Impact:** Two clear bar charts contrasting your absolute Wealth (€) and your Portfolio Yield (%) before and after the trades.
                • **Simulated Cash Allocation & Dividends:** Two final donuts visualizing exactly where your freshly deployed cash was allocated and which positions are generating your new simulated dividends.
                
                *Pro-tip: Click the magnifying glass icon on any chart to open a detailed full-screen view!*
                """
            )


        case .benchmark:
            return (
                "Benchmark",
                "chart.bar.xaxis",
                "Compare your portfolio's performance against major market indices.\nSee how your investment strategy performs relative to the broader market."
            )

        case .transactions:
            return (
                "Transactions",
                "arrow.left.arrow.right",
                "Review your investment activity here.\nTrack your purchases, sales, deposits, and withdrawals to keep your portfolio history accurate."
            )

        case .watchlist:
            return (
                "Watchlist",
                "eye.fill",
                "Keep an eye on stocks you're interested in.\nMonitor potential investments and follow their performance before deciding to buy."
            )

        case .calendar:
            return (
                "Calendar",
                "calendar",
                "Stay on top of important financial dates.\nTrack upcoming dividends, earnings announcements, and other events that may affect your investments."
            )

        case .exposure:
            return (
                "Exposure",
                "globe.europe.africa.fill",
                "Understand where your money is invested.\nAnalyze your portfolio's geographic and regional exposure to identify concentrations and diversification opportunities."
            )

        case .fundamentals:
            return (
                "Fundamentals",
                "building.2.fill",
                "Dive into the financial health of companies.\nExamine key metrics such as revenue, earnings, profitability, debt, and other fundamental indicators."
            )

        case .wealth:
            return (
                "Wealth",
                "wallet.bifold.fill",
                "Track your overall wealth over time.\nGet a broader picture of your financial progress and see how your assets and liabilities contribute to your net worth."
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
        VStack(spacing: 24) {
            Image(systemName: tutorialContent.icon)
                .font(.system(size: 60))
                .foregroundColor(.blue)
                .padding(.top, 24)
            
            Text(tutorialContent.title)
                .font(.largeTitle)
                .fontWeight(.bold)
            
            // Ajout d'un ScrollView pour que les textes longs ne soient pas coupés
            ScrollView(.vertical, showsIndicators: true) {
                // L'astuce "inlineOnlyPreservingWhitespace" force SwiftUI à respecter les sauts de ligne !
                if let mdText = try? AttributedString(markdown: tutorialContent.text, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                    Text(mdText)
                        .font(.system(size: 15)) // Taille de police confortable
                        .multilineTextAlignment(.leading)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 30)
                        .lineSpacing(6) // Espacement aéré
                } else {
                    Text(tutorialContent.text)
                        .font(.system(size: 15))
                        .multilineTextAlignment(.leading)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 30)
                        .lineSpacing(6)
                }
            }
            .frame(maxHeight: 400) // Laisse le texte prendre beaucoup plus de place
            
            Spacer()
            
            Button("Got it!") { dismiss() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.bottom, 24)
        }
        .frame(width: 700, height: 600) // Fenêtre globale considérablement agrandie
    }
}

