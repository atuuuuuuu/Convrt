import SwiftUI

struct SettingsView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "gearshape")
                .font(.system(size: 36))
                .foregroundColor(Color(red: 250/255, green: 75/255, blue: 0))
            Text("Settings coming in a later stage")
                .font(.headline)
            Text("Trigger keys, output folder, quality, and more will live here.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(32)
        .frame(width: 420, height: 240)
    }
}
