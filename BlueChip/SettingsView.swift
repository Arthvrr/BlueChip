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
    
    @AppStorage("geminiApiKey") private var geminiApiKey: String = ""
    
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
                
                
                // NOUVELLE SECTION : GLOBAL PREFERENCES
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Global Preferences")
                            .font(.headline)
                        
                        // 1. Taux de taxe sur les dividendes (CORRIGÉ SANS LE 15.0 FLOTTANT)
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Dividend Tax Rate")
                                    .fontWeight(.medium)
                                Text("Used to calculate net dividend payouts across the app.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            HStack {
                                // En mettant "", on supprime le label flottant au-dessus du champ !
                                TextField("", value: $viewModel.dividendTaxRate, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 60)
                                    .multilineTextAlignment(.trailing)
                                Text("%")
                            }
                        }
                        
                        Divider().padding(.vertical, 4)
                        
                        // 2. Fuseau horaire (SIMPLIFIÉ EN UTC)
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Local Time Zone")
                                    .fontWeight(.medium)
                                Text("US Market times will be converted to this zone.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            
                            // Transforme l'identifiant en format UTC (UTC-12 à UTC+14)
                            Picker("", selection: Binding(
                                get: { Int(viewModel.userTimeZoneIdentifier) ?? (TimeZone.current.secondsFromGMT() / 3600) },
                                set: { viewModel.userTimeZoneIdentifier = String($0) }
                            )) {
                                ForEach(-12...14, id: \.self) { offset in
                                    let sign = offset > 0 ? "+" : ""
                                    Text(offset == 0 ? "UTC" : "UTC\(sign)\(offset)").tag(offset)
                                }
                            }
                            .frame(width: 120)
                            .labelsHidden()
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                                
                // NOUVELLE SECTION : AI COPILOT
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("AI Copilot Configuration")
                            .font(.headline)
                        
                        HStack {
                            Text("Enter your Google Gemini API Key to enable the financial AI assistant. Your key is stored securely and locally on your Mac.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            Link(destination: URL(string: "https://aistudio.google.com/api-keys")!) {
                                HStack(spacing: 4) {
                                    Text("Get Free Key")
                                    Image(systemName: "arrow.up.right.square")
                                }
                                .font(.caption)
                                .foregroundColor(.blue)
                            }
                        }
                        
                        SecureField("Gemini API Key (AIzaSy...)", text: $geminiApiKey)
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding(.vertical, 8)
                }

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

