import SwiftUI

struct CheatSheetView: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("Keyboard Shortcuts").font(.title2).fontWeight(.bold); Spacer(); Button(action: { dismiss() }) { Image(systemName: "xmark.circle.fill").foregroundColor(.secondary) }.buttonStyle(.plain) }.padding()
            Divider()
            
            Form {
                Section("Navigation & Interface") {
                    ShortcutRow(title: "Global Search", keys: ["⌘", "F"])
                    ShortcutRow(title: "Toggle Privacy Mode", keys: ["⌘", "K"])
                    ShortcutRow(title: "Lock Application", keys: ["⌘", "L"])
                    ShortcutRow(title: "Next Tab", keys: ["⌃", "Tab"])
                    ShortcutRow(title: "Previous Tab", keys: ["⌃", "⇧", "Tab"])
                    ShortcutRow(title: "Full Screen", keys: ["⌃", "⌘", "F"])
                }
                Section("Actions") {
                    ShortcutRow(title: "Add Position", keys: ["⌘", "N"])
                    ShortcutRow(title: "Add Transaction", keys: ["⌘", "T"])
                    ShortcutRow(title: "Add Calendar Event", keys: ["⌘", "E"])
                    ShortcutRow(title: "Add Thesis Note", keys: ["⌘", "B"])
                    ShortcutRow(title: "Refresh Prices", keys: ["⌘", "R"])
                    ShortcutRow(title: "AI Copilot Insights", keys: ["⌘", "I"])

                }
                Section("Help") {
                    ShortcutRow(title: "Show Shortcuts", keys: ["⌘", "/"])
                    ShortcutRow(title: "Show Page Tutorial", keys: ["⌘", "⇧", "T"])
                }
            }.formStyle(.grouped)
            
            Button("Done") { dismiss() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).padding()
        }.frame(width: 450, height: 600)
    }
}

struct ShortcutRow: View {
    let title: String
    let keys: [String]
    var body: some View {
        HStack {
            Text(title)
            Spacer()
            HStack(spacing: 4) {
                ForEach(keys, id: \.self) { key in
                    Text(key).font(.system(.body, design: .rounded)).fontWeight(.medium).padding(.horizontal, 6).padding(.vertical, 2).background(Color(NSColor.windowBackgroundColor)).cornerRadius(4).shadow(color: .black.opacity(0.1), radius: 1, y: 1)
                }
            }
        }
    }
}

