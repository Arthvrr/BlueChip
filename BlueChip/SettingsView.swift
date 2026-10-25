import SwiftUI
import UniformTypeIdentifiers

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

// NOUVEAU: Enum pour les devises supportées
enum AppCurrency: String, CaseIterable, Identifiable {
    case eur = "EUR"
    case usd = "USD"
    case gbp = "GBP"
    case chf = "CHF"
    case cad = "CAD"
    case aud = "AUD"
    case jpy = "JPY"
    
    var id: String { self.rawValue }
    
    var symbol: String {
        switch self {
        case .eur: return "€"
        case .usd, .cad, .aud: return "$"
        case .gbp: return "£"
        case .chf: return "CHF"
        case .jpy: return "¥"
        }
    }
    
    var displayName: String {
        return "\(self.rawValue) (\(self.symbol))"
    }
}

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        if let fileData = configuration.file.regularFileContents { self.data = fileData }
        else { throw CocoaError(.fileReadCorruptFile) }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        return .init(regularFileWithContents: data)
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
    
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var backupDocument: BackupDocument?
    @State private var alertMessage = ""
    @State private var showAlert = false
    
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
                        
                        // NOUVEAU : Devise globale préférée (Base Currency)
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Base Currency")
                                    .fontWeight(.medium)
                                Text("All portfolio values will be converted and displayed in this currency.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            
                            Picker("", selection: Binding(
                                get: { AppCurrency(rawValue: viewModel.preferredCurrency) ?? .eur },
                                set: { viewModel.preferredCurrency = $0.rawValue }
                            )) {
                                ForEach(AppCurrency.allCases) { currency in
                                    Text(currency.displayName).tag(currency)
                                }
                            }
                            .frame(width: 120)
                            .labelsHidden()
                        }
                        
                        Divider().padding(.vertical, 4)
                        
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
                
                // NOUVELLE SECTION : DATA MANAGEMENT
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Data Management (Backup)")
                            .font(.headline)
                        
                        HStack(spacing: 16) {
                            Button(action: {
                                if let data = viewModel.generateFullBackup() {
                                    backupDocument = BackupDocument(data: data)
                                    showExporter = true
                                } else {
                                    alertMessage = "Failed to generate backup data."
                                    showAlert = true
                                }
                            }) {
                                HStack {
                                    Image(systemName: "square.and.arrow.up")
                                    Text("Export Full Backup")
                                }
                            }
                            .buttonStyle(.bordered)
                            
                            Button(action: {
                                showImporter = true
                            }) {
                                HStack {
                                    Image(systemName: "square.and.arrow.down")
                                    Text("Import Backup")
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                        
                        Text("Exporting creates a comprehensive JSON file containing your entire portfolio, settings, history, and goals. Importing a backup will overwrite your current data.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
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
        
        // --- MODIFICATEURS EXPORT / IMPORT ---
        .fileExporter(
            isPresented: $showExporter,
            document: backupDocument,
            contentType: .json,
            defaultFilename: "BlueChip_FullBackup.json"
        ) { result in
            switch result {
            case .success(let url):
                alertMessage = "Backup successfully saved to \(url.lastPathComponent)"
                showAlert = true
            case .failure(let error):
                alertMessage = "Failed to export backup: \(error.localizedDescription)"
                showAlert = true
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                // Demande la permission à macOS de lire le fichier
                guard url.startAccessingSecurityScopedResource() else {
                    alertMessage = "Permission denied to read the file."
                    showAlert = true
                    return
                }
                defer { url.stopAccessingSecurityScopedResource() }
                
                do {
                    let fileData = try Data(contentsOf: url)
                    try viewModel.restoreFullBackup(from: fileData)
                    alertMessage = "Welcome back! Your portfolio has been completely restored."
                    showAlert = true
                } catch {
                    alertMessage = "Failed to restore backup. The file might be corrupted. (\(error.localizedDescription))"
                    showAlert = true
                }
            case .failure(let error):
                alertMessage = "Failed to select file: \(error.localizedDescription)"
                showAlert = true
            }
        }
        .alert("Data Management", isPresented: $showAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
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
