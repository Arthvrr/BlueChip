import SwiftUI

struct AboutBlueChipView: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "briefcase.fill").font(.system(size: 80)).foregroundColor(.blue).padding(.bottom, 10)
            Text("BlueChip").font(.system(size: 32, weight: .black, design: .rounded))
            Text("Version 1.0.0 (Beta)").font(.subheadline).foregroundColor(.secondary)
            
            Text("Your ultimate native macOS portfolio tracker. Built with SwiftData and SwiftUI for maximum performance and privacy.")
                .multilineTextAlignment(.center)
                .font(.callout)
                .padding(.horizontal, 20)
                .padding(.top, 10)
            
            Spacer()
            Button("Close") { dismiss() }.keyboardShortcut(.defaultAction).buttonStyle(.bordered)
        }
        .padding(30)
        .frame(width: 500, height: 500)
    }
}

