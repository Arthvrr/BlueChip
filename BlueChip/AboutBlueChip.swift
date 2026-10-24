import SwiftUI

struct AboutBlueChipView: View {
    @Environment(\.dismiss) var dismiss
    
    // Remplacer par tes vrais liens
    let linkedInURL = URL(string: "https://www.linkedin.com/in/arthurlouette/")!
    let websiteURL = URL(string: "https://arthvrr.github.io/BlueChip/")!
    let emailURL = URL(string: "mailto:arthurlouette12@gmail.com?subject=BlueChip%20Feedback")!
    
    var body: some View {
        VStack(spacing: 0) {
            
            // MARK: - HEADER
            VStack(spacing: 12) {
                Image(systemName: "briefcase.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(
                        LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .shadow(color: .blue.opacity(0.3), radius: 10, x: 0, y: 5)
                
                Text("BlueChip")
                    .font(.system(size: 36, weight: .black, design: .rounded))
                
                Text("Version 1.0.0 (Beta) • Built with SwiftUI & SwiftData")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 30)
            .padding(.bottom, 20)
            
            Divider()
            
            // MARK: - MANIFESTO / PHILOSOPHY
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 24) {
                    
                    // Quote
                    HStack(alignment: .top) {
                        Image(systemName: "quote.opening")
                            .font(.title)
                            .foregroundColor(.blue.opacity(0.5))
                        Text("What gets measured, gets improved.")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .italic()
                            .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 10)
                    
                    // Section 1: The Antidote
                    ManifestoSection(
                        icon: "bolt.shield.fill",
                        color: .orange,
                        title: "The Antidote to Subscriptions",
                        text: "In an era where wealth management tools are shifting towards costly monthly subscriptions and intrusive data-harvesting, BlueChip takes a radically different approach. We believe that tracking your hard-earned net worth shouldn't cost you a percentage of it. BlueChip is designed to be the most comprehensive, privacy-first native macOS portfolio tracker—completely free of charge."
                    )
                    
                    // Section 2: Intentional Investing
                    ManifestoSection(
                        icon: "brain.head.profile",
                        color: .purple,
                        title: "Intentional Investing",
                        text: "BlueChip fetches real-time stock prices to keep your portfolio valuation accurate, but puts you in control of the rest. Why? Because we are long-term investors. Corporate fundamentals, analyst targets, and business exposures don't change by the minute. Manually logging your data fosters a deeper understanding of your investments. Opening the app once a day and updating your metrics once a month keeps you grounded and focused on your long-term thesis, filtering out the daily market noise."
                    )
                    
                    // Section 3: Continuous Evolution
                    ManifestoSection(
                        icon: "hammer.fill",
                        color: .blue,
                        title: "Continuously Evolving",
                        text: "BlueChip is a labor of love, built by an investor, for investors. The app is in continuous development, with new features and refinements being crafted regularly. Your feedback, brilliant ideas, and feature requests are not just welcome—they are the driving force behind this application's future."
                    )
                    
                }
                .padding(30)
            }
            
            Divider()
            
            // MARK: - FOOTER & LINKS
            HStack {
                HStack(spacing: 16) {
                    Link(destination: linkedInURL) {
                        HStack(spacing: 6) {
                            Image(systemName: "link")
                            Text("LinkedIn")
                        }
                    }
                    .buttonStyle(.link)
                    
                    Link(destination: websiteURL) {
                        HStack(spacing: 6) {
                            Image(systemName: "globe")
                            Text("Website")
                        }
                    }
                    .buttonStyle(.link)
                    
                    Link(destination: emailURL) {
                        HStack(spacing: 6) {
                            Image(systemName: "envelope.fill")
                            Text("Send Feedback")
                        }
                    }
                    .buttonStyle(.link)
                }
                
                Spacer()
                
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(20)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.8))
        }
        .frame(width: 600, height: 750)
    }
}

// MARK: - SUBCOMPONENT FOR TEXT BLOCKS
struct ManifestoSection: View {
    let icon: String
    let color: Color
    let title: String
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
                .frame(width: 30, alignment: .center)
            
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(text)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .lineSpacing(4)
            }
        }
    }
}
