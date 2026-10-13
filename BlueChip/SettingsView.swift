import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case system = "Automatic"
    case light = "Light"
    case dark = "Dark"
    
    var id: String { self.rawValue }
    
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: PortfolioViewModel
    
    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    
    // NOUVELLES VARIABLES DE SÉCURITÉ
    @AppStorage("forcePrivacyOnStartup") private var forcePrivacyOnStartup: Bool = false
    @AppStorage("requireAuthOnStartup") private var requireAuthOnStartup: Bool = false
    
    // État pour afficher l'alerte de confirmation
    @State private var showResetAlert = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Preferences")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            
            Divider()
            
            // Main Content
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Appearance")
                            .font(.headline)
                        Picker("App Theme", selection: $appTheme) {
                            ForEach(AppTheme.allCases) { theme in
                                Text(theme.rawValue).tag(theme)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.vertical, 8)
                }
                
                //Divider().padding(.vertical, 4)
                
                // NOUVELLE SECTION : SECURITY & PRIVACY
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Security & Privacy")
                            .font(.headline)
                        
                        Toggle("Always enable Privacy Mode on startup", isOn: $forcePrivacyOnStartup)
                        Toggle("Require Touch ID / Password on startup", isOn: $requireAuthOnStartup)
                    }
                    .padding(.vertical, 8)
                }
                
                //Divider().padding(.vertical, 4)
                
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Portfolio Configuration")
                            .font(.headline)
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Investment Start Year")
                                    .fontWeight(.medium)
                                Text("Used as the baseline for Growth and Dividends history tables.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Stepper(value: $viewModel.dividendStartYear, in: 1980...2050) {
                                Text(String(viewModel.dividendStartYear))
                                    .font(.title3.bold())
                                    .foregroundColor(.blue)
                            }
                            .frame(width: 120)
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                //Divider().padding(.vertical, 4)
                
                // NOUVELLE SECTION : DANGER ZONE
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Danger Zone")
                            .font(.headline)
                            .foregroundColor(.red)
                        
                        HStack {
                            Text("Permanently delete all positions, dividends, and history.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Button(role: .destructive, action: { showResetAlert = true }) {
                                Text("Wipe All Data")
                                    .fontWeight(.semibold)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(false) // Permet de scroller si la fenêtre est trop petite
            
            Divider()
            
            // Footer
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
        .frame(width: 550, height: 600)
        // L'alerte de confirmation
        .alert("Erase all data?", isPresented: $showResetAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Yes, Wipe My Portfolio", role: .destructive) {
                viewModel.wipeAllData()
                dismiss() // Ferme les réglages après effacement
            }
        } message: {
            Text("This action cannot be undone. All your stocks, settings, and historical data will be permanently deleted.")
        }
    }
}

