import Foundation
import CoreSpotlight
import UniformTypeIdentifiers

class SpotlightManager {
    static let shared = SpotlightManager()
    
    private let domainIdentifier = "com.bluechip.spotlight"
    
    func indexPortfolio(positions: [Position], transactions: [Transaction], watchlistItems: [WatchlistItem], calendarEvents: [CalendarEvent]) {
        
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domainIdentifier]) { error in
            if let error = error {
                print("Erreur de suppression Spotlight : \(error.localizedDescription)")
                return
            }
            
            var searchableItems = [CSSearchableItem]()
            
            // 1. Actions Rapides
            let actions = [
                ("action_add_position", "Add New Position", "Add a new stock to your BlueChip portfolio"),
                ("action_add_transaction", "Add Transaction", "Log a new buy, sell, deposit, or withdrawal"),
                ("action_add_event", "Add Calendar Event", "Schedule an earnings or dividend event")
            ]
            for action in actions {
                let attributeSet = CSSearchableItemAttributeSet(contentType: .content)
                attributeSet.title = "BlueChip: \(action.1)"
                attributeSet.contentDescription = action.2
                
                let item = CSSearchableItem(uniqueIdentifier: action.0, domainIdentifier: self.domainIdentifier, attributeSet: attributeSet)
                searchableItems.append(item)
            }
            
            // 2. Les 13 Pages
            let pages = [
                ("page_composition", "Composition"),
                ("page_fundamentals", "Fundamentals"),
                ("page_growth", "Growth"),
                ("page_dividends", "Dividends"),
                ("page_valuation", "Valuation"),
                ("page_projection", "Projection"),
                ("page_simulation", "Simulation"),
                ("page_watchlist", "Watchlist"),
                ("page_exposure", "Exposure"),
                ("page_transactions", "Transactions"),
                ("page_benchmark", "Benchmark"),
                ("page_calendar", "Calendar"),
                ("page_wealth", "Wealth")
            ]
            for page in pages {
                let attributeSet = CSSearchableItemAttributeSet(contentType: .content)
                attributeSet.title = "BlueChip: \(page.1)"
                attributeSet.contentDescription = "Open the \(page.1) dashboard"
                
                let item = CSSearchableItem(uniqueIdentifier: page.0, domainIdentifier: self.domainIdentifier, attributeSet: attributeSet)
                searchableItems.append(item)
            }
            
            // 3. Les Positions (avec Logo)
            for pos in positions {
                let attributeSet = CSSearchableItemAttributeSet(contentType: .content)
                let name = pos.companyName.isEmpty ? "Position" : pos.companyName
                attributeSet.title = "\(pos.ticker) - \(name)"
                attributeSet.contentDescription = "You own \(pos.quantity) shares at an average cost of \(pos.averageCost.formatted(.currency(code: pos.currency.isEmpty ? "USD" : pos.currency)))."
                attributeSet.thumbnailData = pos.logoData
                
                let item = CSSearchableItem(uniqueIdentifier: "position_\(pos.id.uuidString)", domainIdentifier: self.domainIdentifier, attributeSet: attributeSet)
                searchableItems.append(item)
            }
            
            // 4. Les Transactions
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            for tx in transactions {
                let attributeSet = CSSearchableItemAttributeSet(contentType: .content)
                attributeSet.title = "\(tx.type.rawValue.capitalized) \(tx.ticker.isEmpty ? "Cash" : tx.ticker) - BlueChip"
                attributeSet.contentDescription = "Date: \(dateFormatter.string(from: tx.date)) | Amount: \(tx.amountEUR.formatted(.currency(code: "EUR")))"
                
                let item = CSSearchableItem(uniqueIdentifier: "transaction_\(tx.id.uuidString)", domainIdentifier: self.domainIdentifier, attributeSet: attributeSet)
                searchableItems.append(item)
            }
            
            // 5. La Watchlist
            for watch in watchlistItems {
                let attributeSet = CSSearchableItemAttributeSet(contentType: .content)
                attributeSet.title = "👀 \(watch.ticker) - Watchlist"
                let targetText = watch.targetPrice > 0 ? watch.targetPrice.formatted() : "None"
                attributeSet.contentDescription = "Current Price: \(watch.currentPrice.formatted(.currency(code: watch.currency.isEmpty ? "USD" : watch.currency))) | Target: \(targetText)"
                
                let item = CSSearchableItem(uniqueIdentifier: "watchlist_\(watch.id.uuidString)", domainIdentifier: self.domainIdentifier, attributeSet: attributeSet)
                searchableItems.append(item)
            }
            
            // 6. Le Calendrier
            for event in calendarEvents {
                let attributeSet = CSSearchableItemAttributeSet(contentType: .content)
                attributeSet.title = "📅 \(event.ticker) - \(event.type.rawValue)"
                attributeSet.contentDescription = "Scheduled for \(dateFormatter.string(from: event.date)). \(event.note)"
                
                let item = CSSearchableItem(uniqueIdentifier: "event_\(event.id.uuidString)", domainIdentifier: self.domainIdentifier, attributeSet: attributeSet)
                searchableItems.append(item)
            }
            
            
        }
    }
}
